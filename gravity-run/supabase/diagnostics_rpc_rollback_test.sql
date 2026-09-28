begin;
create temporary table diagnostic_verification_result (result jsonb) on commit drop;

do $$
declare
	users uuid[];
	room_id uuid := gen_random_uuid();
	match_id uuid := gen_random_uuid();
	report_id uuid;
	session_id uuid;
	client_id uuid;
	payload jsonb;
	summary jsonb := '{"role":"unknown","player_label":"unknown"}'::jsonb;
	response jsonb;
	fetched jsonb;
	duplicate_ok boolean := false;
	rejected boolean := false;
	i integer;
	labels jsonb;
begin
	select array_agg(id order by created_at desc)
	into users
	from (select id, created_at from auth.users order by created_at desc limit 3) recent;
	if coalesce(cardinality(users), 0) <> 3 then raise exception 'Verification needs three existing authenticated test identities.'; end if;
	for i in 1..3 loop
		perform set_config('request.jwt.claim.sub', users[i]::text, true);
		perform public.set_multiplayer_diagnostic_opt_in(true);
	end loop;

	insert into public.multiplayer_rooms (
		room_id, room_code, owner_user_id, phase, protocol_version, game_version,
		generator_version, max_players, seed, course_length_px, manifest_hash,
		signaling_topic, created_at, last_activity_at, expires_at, is_public
	) values (
		room_id, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)), users[1], 'OPEN',
		1, 'diagnostic-rollback-test', 1, 5, 123456, 10000, 'verification-manifest',
		'diagnostic-' || room_id::text, now(), now(), now() + interval '1 hour', false
	);
	for i in 1..3 loop
		insert into public.multiplayer_room_members (
			room_id, user_id, player_slot, display_name, is_ready, loaded_manifest_hash,
			joined_at, last_seen_at, skin_id
		) values (room_id, users[i], i, 'Test' || i, true, 'verification-manifest', now(), now(), i - 1);
	end loop;

	perform set_config('request.jwt.claim.sub', users[1]::text, true);
	response := public.create_multiplayer_diagnostic_session(room_id, match_id);
	session_id := (response->>'session_id')::uuid;
	if (response->>'expected_count')::integer <> 3 then raise exception 'Session did not bind all three expected clients.'; end if;

	for i in 1..3 loop
		perform set_config('request.jwt.claim.sub', users[i]::text, true);
		report_id := gen_random_uuid();
		client_id := gen_random_uuid();
		payload := jsonb_build_object(
			'schema_version', 1, 'report_id', report_id, 'match_id', match_id,
			'diagnostic_session_id', session_id, 'client_instance_id', client_id,
			'match_generation', 'rollback-verification', 'role', case when i = 1 then 'host' else 'guest' end,
			'player_label', 'p' || (i - 1)::text, 'build_id', 'rollback-test', 'terminal_state', 'finished'
		);
		response := public.upload_multiplayer_diagnostic_report(
			session_id, match_id, report_id, 1, 'rollback-test',
			jsonb_build_object('role', payload->>'role', 'player_label', payload->>'player_label'), payload
		);
		if i = 1 then
			response := public.upload_multiplayer_diagnostic_report(
				session_id, match_id, report_id, 1, 'rollback-test',
				jsonb_build_object('role', payload->>'role', 'player_label', payload->>'player_label'), payload
			);
			duplicate_ok := (response->>'duplicate')::boolean;
		end if;
	end loop;

	-- Server-side boundaries must reject an oversized report and an unknown session.
	rejected := false;
	perform set_config('request.jwt.claim.sub', users[1]::text, true);
	report_id := gen_random_uuid();
client_id := gen_random_uuid();
	payload := jsonb_build_object(
		'report_id', report_id, 'match_id', match_id, 'diagnostic_session_id', session_id,
		'client_instance_id', client_id, 'match_generation', 'rollback-verification',
		'role', 'host', 'player_label', 'p0', 'build_id', 'rollback-test', 'padding', repeat('x', 140000)
	);
	begin
		perform public.upload_multiplayer_diagnostic_report(session_id, match_id, report_id, 1, 'rollback-test', '{}'::jsonb, payload);
	exception when others then
		rejected := sqlerrm = 'diagnostic_report_too_large';
	end;
	if not rejected then raise exception 'The server did not reject an oversized report with its size limit.'; end if;

	rejected := false;
	report_id := gen_random_uuid();
	payload := jsonb_build_object(
		'report_id', report_id, 'match_id', match_id, 'diagnostic_session_id', gen_random_uuid(),
		'client_instance_id', client_id, 'match_generation', 'rollback-verification',
		'role', 'host', 'player_label', 'p0', 'build_id', 'rollback-test'
	);
	begin
		perform public.upload_multiplayer_diagnostic_report((payload->>'diagnostic_session_id')::uuid, match_id, report_id, 1, 'rollback-test', '{}'::jsonb, payload);
	exception when others then
		rejected := sqlerrm = 'diagnostic_session_not_found';
	end;
	if not rejected then raise exception 'The server did not reject an unknown diagnostic session.'; end if;

	-- If a fourth account exists, verify that it cannot add itself to the bound roster.
	if (select count(*) from auth.users) >= 4 then
		select u.id into strict client_id from auth.users u where u.id <> all(users) order by u.created_at desc limit 1;
		perform set_config('request.jwt.claim.sub', client_id::text, true);
		report_id := gen_random_uuid();
		payload := jsonb_build_object(
			'report_id', report_id, 'match_id', match_id, 'diagnostic_session_id', session_id,
			'client_instance_id', gen_random_uuid(), 'match_generation', 'rollback-verification',
			'role', 'guest', 'player_label', 'p3', 'build_id', 'rollback-test'
		);
		rejected := false;
		begin
			perform public.upload_multiplayer_diagnostic_report(session_id, match_id, report_id, 1, 'rollback-test', '{}'::jsonb, payload);
		exception when others then
			rejected := sqlerrm = 'diagnostic_user_not_in_session';
		end;
		if not rejected then raise exception 'An account outside the session roster was accepted.'; end if;
	end if;

	perform set_config('request.jwt.claim.sub', users[2]::text, true);
	fetched := public.get_multiplayer_diagnostic_session_reports(session_id);
	if (fetched->>'expected_count')::integer <> 3 or (fetched->>'received_count')::integer <> 3 or jsonb_array_length(fetched->'reports') <> 3 then
		raise exception 'Expected three uploaded reports under one shared debug ID.';
	end if;
	if fetched ? 'expected_user_ids' or exists (select 1 from jsonb_array_elements(fetched->'reports') r where r ? 'uploaded_by') then
		raise exception 'A client-facing RPC response exposed account UUIDs.';
	end if;
	if not duplicate_ok then raise exception 'Exact report retry was not idempotent.'; end if;
	select jsonb_agg(r->>'player_label' order by r->>'player_label') into labels from jsonb_array_elements(fetched->'reports') r;
	insert into diagnostic_verification_result values (jsonb_build_object(
		'fixture_only', true, 'expected_clients', fetched->>'expected_count',
		'reports_fetched', fetched->>'received_count', 'player_labels', labels,
		'idempotent_retry', duplicate_ok, 'account_ids_exposed', false,
		'shared_debug_id_present', not (fetched->>'session_id' is null)
	));
end;
$$;

select result from diagnostic_verification_result;
rollback;
