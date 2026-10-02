-- Run after the ordered migration chain against a Supabase-auth shim database.
-- Everything is rolled back; the JWT claim is a test identity, not a credential.
begin;

insert into auth.users(id) values ('a8e24939-3303-42a5-9aa8-6fe9f7df07dc') on conflict (id) do nothing;
select set_config('request.jwt.claim.sub', 'a8e24939-3303-42a5-9aa8-6fe9f7df07dc', true);

do $$
declare
	created jsonb;
	room uuid;
	registered jsonb;
	message text;
begin
	execute 'set local role authenticated';
	created := public.multiplayer_v2_create_room('version_test', '2.1.20261002.4', 8::smallint, 100000000, 45000, true);
	execute 'reset role';
	room := (created ->> 'room_id')::uuid;
	if room is null then raise exception 'v8_create_returned_no_room'; end if;
	if not exists (
		select 1 from public.multiplayer_rooms
		where room_id = room and game_version = '2.1.20261002.4' and generator_version = 8
	) then raise exception 'v8_create_did_not_persist_current_version'; end if;

	begin
		execute 'set local role authenticated';
		perform public.multiplayer_v2_create_room('old_version', '2.1.20261002.3', 7::smallint, 100000001, 45000, true);
		raise exception 'expected_old_create_version_rejected';
	exception when others then
		get stacked diagnostics message = message_text;
		if message <> 'version_mismatch' then raise; end if;
	end;
	execute 'reset role';

	update public.multiplayer_rooms set phase = 'PREPARING_COURSE', manifest_hash = repeat('a', 64)
	where room_id = room;
	execute 'set local role authenticated';
	registered := public.register_multiplayer_v2_coin_round(room, 1, 'v8-test-round', repeat('a', 64), '["coin_1_00001_0"]'::jsonb);
	execute 'reset role';
	if registered ->> 'duplicate' <> 'false' or (registered ->> 'coin_count')::integer <> 1 then
		raise exception 'v8_coin_round_registration_failed';
	end if;

	update public.multiplayer_rooms set game_version = '2.1.20261002.3', generator_version = 7
	where room_id = room;
	begin
		execute 'set local role authenticated';
		perform public.register_multiplayer_v2_coin_round(room, 1, 'wrong-version-round', repeat('b', 64), '["coin_1_00002_0"]'::jsonb);
		raise exception 'expected_old_coin_round_version_rejected';
	exception when others then
		get stacked diagnostics message = message_text;
		if message <> 'coin_game_version_mismatch' then raise; end if;
	end;
	execute 'reset role';
end;
$$;

rollback;
