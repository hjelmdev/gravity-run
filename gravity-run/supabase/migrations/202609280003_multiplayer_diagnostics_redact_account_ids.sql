-- Session IDs are the user-facing correlation key. Do not expose participant
-- account UUIDs through client-callable diagnostic RPC responses.

create or replace function public.create_multiplayer_diagnostic_session(p_room_id uuid, p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_user_id uuid := auth.uid();
	v_room public.multiplayer_rooms%rowtype;
	v_expected uuid[];
	v_missing integer;
	v_session public.multiplayer_diagnostic_sessions%rowtype;
	v_count integer;
	v_old_session uuid;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	if p_match_id is null then raise exception 'invalid_match_id'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> v_user_id then raise exception 'not_room_owner'; end if;
	if v_room.phase not in ('OPEN', 'COUNTDOWN', 'RUNNING') then raise exception 'diagnostic_session_requires_active_match'; end if;
	select array_agg(m.user_id order by m.player_slot), count(*) filter (where coalesce(t.enabled, false) = false or t.enabled_until <= now())
	into v_expected, v_missing
	from public.multiplayer_room_members m
	left join public.multiplayer_diagnostic_testers t on t.user_id = m.user_id
	where m.room_id = p_room_id;
	if coalesce(cardinality(v_expected), 0) < 1 or cardinality(v_expected) > 5 then raise exception 'invalid_diagnostic_roster'; end if;
	if v_missing > 0 then raise exception 'diagnostic_opt_in_required_for_all_players'; end if;
	perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('multiplayer_diagnostics_global_capacity', 0));
	if v_room.phase = 'OPEN' and exists (
		select 1 from public.multiplayer_room_members m
		where m.room_id = p_room_id and (not m.is_ready or m.loaded_manifest_hash is distinct from v_room.manifest_hash)
	) then raise exception 'diagnostic_session_requires_ready_players'; end if;
	select * into v_session from public.multiplayer_diagnostic_sessions where match_id = p_match_id;
	if found then
		if v_session.owner_user_id <> v_user_id or v_session.room_id <> p_room_id or v_session.expected_user_ids <> v_expected then raise exception 'diagnostic_match_id_conflict'; end if;
		return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id, 'expected_count', cardinality(v_session.expected_user_ids), 'expires_at', v_session.expires_at);
	end if;
	if (select count(*) from public.multiplayer_diagnostic_sessions where owner_user_id = v_user_id and created_at > now() - interval '1 hour') >= 10 then raise exception 'diagnostic_account_hourly_session_quota_exceeded'; end if;
	select count(*) into v_count from public.multiplayer_diagnostic_sessions;
	while v_count >= 200 loop
		select session_id into v_old_session from public.multiplayer_diagnostic_sessions
		order by created_at asc limit 1 for update skip locked;
		if v_old_session is null then raise exception 'diagnostic_global_session_capacity_reached'; end if;
		delete from public.multiplayer_diagnostic_sessions where session_id = v_old_session;
		select count(*) into v_count from public.multiplayer_diagnostic_sessions;
	end loop;
	insert into public.multiplayer_diagnostic_sessions (match_id, room_id, owner_user_id, expected_user_ids)
	values (p_match_id, p_room_id, v_user_id, v_expected)
	returning * into v_session;
	return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id, 'expected_count', cardinality(v_session.expected_user_ids), 'expires_at', v_session.expires_at);
end;
$$;

create or replace function public.list_my_multiplayer_diagnostic_sessions(p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_result jsonb;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	select coalesce(jsonb_agg(row_value order by created_at desc), '[]'::jsonb) into v_result
	from (
		select s.created_at, jsonb_build_object(
			'session_id', s.session_id, 'match_id', s.match_id,
			'created_at', s.created_at, 'expires_at', s.expires_at,
			'expected_count', cardinality(s.expected_user_ids),
			'received_count', (select count(*) from public.multiplayer_diagnostic_reports r where r.session_id = s.session_id),
			'reports', coalesce((select jsonb_agg(jsonb_build_object('role', r.role, 'player_label', r.player_label, 'build_id', r.build_id, 'created_at', r.created_at, 'summary', r.summary) order by r.created_at) from public.multiplayer_diagnostic_reports r where r.session_id = s.session_id), '[]'::jsonb)
		) as row_value
		from public.multiplayer_diagnostic_sessions s
		where v_user_id = any(s.expected_user_ids) and s.expires_at > now()
		order by s.created_at desc limit greatest(1, least(coalesce(p_limit, 10), 20))
	) q;
	return v_result;
end;
$$;

create or replace function public.get_multiplayer_diagnostic_session_reports(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_session public.multiplayer_diagnostic_sessions%rowtype; v_reports jsonb;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	select * into v_session from public.multiplayer_diagnostic_sessions where session_id = p_session_id and expires_at > now();
	if not found or not (v_user_id = any(v_session.expected_user_ids)) then raise exception 'diagnostic_session_not_available'; end if;
	select coalesce(jsonb_agg(jsonb_build_object(
		'report_id', r.report_id, 'role', r.role,
		'player_label', r.player_label, 'client_instance_id', r.client_instance_id,
		'build_id', r.build_id, 'schema_version', r.schema_version,
		'created_at', r.created_at, 'payload_bytes', r.payload_bytes,
		'summary', r.summary, 'report', r.report
	) order by r.created_at), '[]'::jsonb) into v_reports
	from public.multiplayer_diagnostic_reports r where r.session_id = p_session_id;
	return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id,
		'created_at', v_session.created_at, 'expires_at', v_session.expires_at,
		'expected_count', cardinality(v_session.expected_user_ids),
		'received_count', jsonb_array_length(v_reports), 'reports', v_reports);
end;
$$;
