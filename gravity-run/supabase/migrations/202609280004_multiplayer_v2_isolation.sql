-- Add a disjoint V2 room namespace and RPC surface without changing existing
-- room defaults or rewriting the historical V1 migrations.
alter table public.multiplayer_rooms
	add column if not exists network_mode text not null default 'v1',
	add column if not exists v2_protocol_version smallint,
	add column if not exists lobby_generation bigint not null default 1,
	add column if not exists room_session_id uuid not null default gen_random_uuid();

alter table public.multiplayer_rooms drop constraint if exists multiplayer_rooms_network_mode_check;
alter table public.multiplayer_rooms add constraint multiplayer_rooms_network_mode_check check (network_mode in ('v1', 'v2'));
alter table public.multiplayer_rooms drop constraint if exists multiplayer_rooms_max_players_check;
alter table public.multiplayer_rooms add constraint multiplayer_rooms_max_players_check check (max_players between 2 and 5);
alter table public.multiplayer_room_members drop constraint if exists multiplayer_room_members_player_slot_check;
alter table public.multiplayer_room_members add constraint multiplayer_room_members_player_slot_check check (player_slot between 1 and 5);

create table if not exists public.multiplayer_v2_round_acks (
	room_id uuid not null references public.multiplayer_rooms(room_id) on delete cascade,
	lobby_generation bigint not null,
	user_id uuid not null references auth.users(id) on delete cascade,
	prepared boolean not null default false,
	start_ack boolean not null default false,
	updated_at timestamptz not null default now(),
	primary key (room_id, lobby_generation, user_id)
);
alter table public.multiplayer_v2_round_acks enable row level security;
revoke all on table public.multiplayer_v2_round_acks from public, anon, authenticated;

create or replace function public._multiplayer_assert_network_mode(p_room_id uuid, p_expected text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
	if not exists (select 1 from public.multiplayer_rooms where room_id = p_room_id and network_mode = p_expected) then
		raise exception 'room_mode_mismatch';
	end if;
end;
$$;

-- Keep V1 RPCs from changing V2 rooms, even when the caller knows their UUID.
do $$
declare
	v_signature regprocedure;
	v_definition text;
	v_simple_v1 regprocedure[] := array[
		to_regprocedure('public.refresh_multiplayer_room(uuid)'),
		to_regprocedure('public.set_multiplayer_ready(uuid,boolean)'),
		to_regprocedure('public.set_multiplayer_skin(uuid,smallint)'),
		to_regprocedure('public.ack_multiplayer_manifest(uuid,text)'),
		to_regprocedure('public.set_multiplayer_manifest(uuid,bigint,integer,text)'),
		to_regprocedure('public.start_multiplayer_countdown(uuid)'),
		to_regprocedure('public.leave_multiplayer_room(uuid)'),
		to_regprocedure('public.advance_multiplayer_match_phase(uuid,text)'),
		to_regprocedure('public.return_multiplayer_room_to_lobby(uuid)')
	];
begin
	foreach v_signature in array v_simple_v1 loop
		if v_signature is null then continue; end if;
		v_definition := pg_get_functiondef(v_signature);
		if position('public._multiplayer_assert_network_mode(p_room_id, ''v1'')' in v_definition) = 0 then
			v_definition := regexp_replace(v_definition, E'\nbegin\n', E'\nbegin\n\tperform public._multiplayer_assert_network_mode(p_room_id, ''v1'');\n', 'i');
			execute v_definition;
		end if;
	end loop;
	-- V1 joins resolve a room by code rather than UUID.
	v_signature := to_regprocedure('public.join_multiplayer_room(text,text,text,smallint,smallint)');
	if v_signature is not null then
		v_definition := pg_get_functiondef(v_signature);
		if position('v_room.network_mode' in v_definition) = 0 then
			v_definition := regexp_replace(v_definition, E'(select \\* into v_room[^;]*for update;)', E'\\1\n\tif found and v_room.network_mode <> ''v1'' then raise exception ''room_mode_mismatch''; end if;', 'i');
			execute v_definition;
		end if;
	end if;
	-- V1 public-room discovery exposes V1 rooms only.
	v_signature := to_regprocedure('public.list_public_multiplayer_rooms()');
	if v_signature is not null then
		v_definition := pg_get_functiondef(v_signature);
		if position('r.network_mode' in v_definition) = 0 then
			v_definition := replace(v_definition, 'where r.is_public', 'where r.network_mode = ''v1'' and r.is_public');
			execute v_definition;
		end if;
	end if;
end $$;

create or replace function public._multiplayer_room_payload(p_room_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
	select jsonb_build_object(
		'room_id', r.room_id, 'room_code', r.room_code, 'owner_user_id', r.owner_user_id,
		'phase', r.phase, 'protocol_version', r.protocol_version, 'network_mode', r.network_mode,
		'v2_protocol_version', r.v2_protocol_version, 'lobby_generation', r.lobby_generation, 'room_session_id', r.room_session_id,
		'game_version', r.game_version, 'generator_version', r.generator_version,
		'max_players', r.max_players, 'seed', r.seed, 'course_length_px', r.course_length_px,
		'manifest_hash', r.manifest_hash, 'signaling_topic', r.signaling_topic,
		'expires_at', r.expires_at,
		'members', coalesce((select jsonb_agg(jsonb_build_object(
			'user_id', m.user_id, 'player_slot', m.player_slot, 'display_name', m.display_name,
			'is_ready', m.is_ready, 'loaded_manifest_hash', m.loaded_manifest_hash, 'skin_id', m.skin_id,
			'is_connected', m.last_seen_at > now() - interval '45 seconds'
		) order by m.player_slot) from public.multiplayer_room_members m where m.room_id = r.room_id), '[]'::jsonb)
	)
	from public.multiplayer_rooms r
	where r.room_id = p_room_id and exists (select 1 from public.multiplayer_room_members mine where mine.room_id = r.room_id and mine.user_id = auth.uid());
$$;

create or replace function public._multiplayer_v2_realtime_member(p_topic text)
returns boolean language sql stable security definer set search_path = '' as $$
	select auth.uid() is not null and exists (
		select 1 from public.multiplayer_rooms r
		join public.multiplayer_room_members m on m.room_id = r.room_id
		where r.signaling_topic = p_topic and r.network_mode = 'v2' and r.expires_at > now()
		and r.phase not in ('CLOSED', 'FINISHED') and m.user_id = auth.uid()
	);
$$;
create or replace function public._multiplayer_realtime_member(p_topic text)
returns boolean language sql stable security definer set search_path = '' as $$
	select auth.uid() is not null and exists (
		select 1 from public.multiplayer_rooms r
		join public.multiplayer_room_members m on m.room_id = r.room_id
		where r.signaling_topic = p_topic and r.network_mode = 'v1' and r.expires_at > now()
		and r.phase not in ('CLOSED', 'FINISHED') and m.user_id = auth.uid()
	);
$$;
drop policy if exists multiplayer_room_broadcast_read on realtime.messages;
create policy multiplayer_room_broadcast_read on realtime.messages for select to authenticated
	using (extension = 'broadcast' and (public._multiplayer_realtime_member(realtime.topic()) or public._multiplayer_v2_realtime_member(realtime.topic())));
drop policy if exists multiplayer_room_broadcast_send on realtime.messages;
create policy multiplayer_room_broadcast_send on realtime.messages for insert to authenticated
	with check (extension = 'broadcast' and (public._multiplayer_realtime_member(realtime.topic()) or public._multiplayer_v2_realtime_member(realtime.topic())));

create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version is null or char_length(p_game_version) not between 1 and 32 or p_generator_version <= 0 then raise exception 'invalid_version'; end if;
	if p_seed not between 1 and 2147483647 then raise exception 'invalid_seed'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;
	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	loop v_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8)); exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_code); end loop;
	insert into public.multiplayer_rooms(room_id, room_code, owner_user_id, game_version, generator_version, seed, course_length_px, signaling_topic, is_public, max_players, network_mode, v2_protocol_version)
	values(v_room_id, v_code, auth.uid(), btrim(p_game_version), p_generator_version, p_seed, p_course_length_px, v_topic, coalesce(p_is_public, true), 5, 'v2', 1);
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name) values(v_room_id, auth.uid(), 1, btrim(p_display_name));
	return public._multiplayer_room_payload(v_room_id);
end $$;

create or replace function public.multiplayer_v2_join_room(p_room_code text, p_display_name text, p_game_version text, p_generator_version smallint, p_v2_protocol_version smallint default 1)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_slot smallint;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	select * into v_room from public.multiplayer_rooms where room_code = upper(btrim(p_room_code)) for update;
	if not found or v_room.expires_at <= now() then raise exception 'room_not_found'; end if;
	if v_room.network_mode <> 'v2' then raise exception 'room_mode_mismatch'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.v2_protocol_version <> p_v2_protocol_version or v_room.game_version <> p_game_version or v_room.generator_version <> p_generator_version then raise exception 'version_mismatch'; end if;
	if exists(select 1 from public.multiplayer_room_members where room_id = v_room.room_id and user_id = auth.uid() and last_seen_at > now() - interval '45 seconds') then
		raise exception 'identity_already_in_room';
	end if;
	delete from public.multiplayer_room_members where room_id = v_room.room_id and last_seen_at < now() - interval '45 seconds';
	if auth.uid() = v_room.owner_user_id then raise exception 'host_must_reuse_current_session'; end if;
	select slots.slot::smallint into v_slot
	from generate_series(1, v_room.max_players) as slots(slot)
	where not exists(select 1 from public.multiplayer_room_members m where m.room_id = v_room.room_id and m.player_slot = slots.slot)
	order by slots.slot limit 1;
	if v_slot is null then raise exception 'room_full'; end if;
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name) values(v_room.room_id, auth.uid(), v_slot, btrim(p_display_name));
	update public.multiplayer_rooms set lobby_generation = lobby_generation + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = v_room.room_id;
	update public.multiplayer_room_members set is_ready = false, loaded_manifest_hash = null where room_id = v_room.room_id;
	return public._multiplayer_room_payload(v_room.room_id);
end $$;

create or replace function public.multiplayer_v2_list_public_rooms()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	return coalesce((select jsonb_agg(jsonb_build_object(
		'room_id', r.room_id, 'room_code', r.room_code, 'host_name', coalesce((select m.display_name from public.multiplayer_room_members m where m.room_id = r.room_id and m.user_id = r.owner_user_id), 'Host'),
		'player_count', active.member_count, 'max_players', r.max_players, 'network_mode', r.network_mode
	) order by r.created_at desc)
	from public.multiplayer_rooms r cross join lateral (select count(*)::integer as member_count, coalesce(bool_or(m.user_id = r.owner_user_id), false) as owner_active from public.multiplayer_room_members m where m.room_id = r.room_id and m.last_seen_at > now() - interval '45 seconds') active
	where r.network_mode = 'v2' and r.is_public and r.phase = 'OPEN' and r.expires_at > now() and active.owner_active and active.member_count < r.max_players), '[]'::jsonb);
end $$;

create or replace function public.multiplayer_v2_refresh_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	update public.multiplayer_room_members set last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED');
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_set_ready(p_room_id uuid, p_ready boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select phase into v_phase from public.multiplayer_rooms where room_id = p_room_id for update;
	if v_phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	update public.multiplayer_room_members set is_ready = p_ready, last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_leave_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select owner_user_id into v_owner from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then return; end if;
	if not exists(select 1 from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid()) then raise exception 'not_room_member'; end if;
	if v_owner = auth.uid() then update public.multiplayer_rooms set phase = 'CLOSED', last_activity_at = now(), expires_at = now() where room_id = p_room_id;
	else delete from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid(); update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id; end if;
end $$;

create or replace function public.multiplayer_v2_set_manifest(p_room_id uuid, p_seed bigint, p_course_length_px integer, p_manifest_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select owner_user_id, phase into v_owner, v_phase from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_owner <> auth.uid() or v_phase <> 'OPEN' then raise exception 'not_room_owner_or_open'; end if;
	if p_seed not between 1 and 2147483647 or p_course_length_px not between 10000 and 1000000 or p_manifest_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_manifest'; end if;
	update public.multiplayer_rooms set seed = p_seed, course_length_px = p_course_length_px, manifest_hash = p_manifest_hash, lobby_generation = lobby_generation + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, loaded_manifest_hash = null where room_id = p_room_id;
	delete from public.multiplayer_v2_round_acks where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_set_phase(p_room_id uuid, p_phase text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	if p_phase not in ('RUNNING', 'FINISHED') then raise exception 'invalid_phase'; end if;
	select owner_user_id, phase into v_owner, v_phase from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_owner <> auth.uid() then raise exception 'not_room_owner'; end if;
	if p_phase = 'RUNNING' and v_phase <> 'PREPARING_COURSE' then raise exception 'invalid_phase_transition'; end if;
	if p_phase = 'FINISHED' and v_phase not in ('RUNNING', 'FINISHED') then raise exception 'invalid_phase_transition'; end if;
	update public.multiplayer_rooms set phase = p_phase, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_return_to_lobby(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select owner_user_id into v_owner from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_owner <> auth.uid() then raise exception 'not_room_owner'; end if;
	update public.multiplayer_rooms set phase = 'OPEN', lobby_generation = lobby_generation + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, loaded_manifest_hash = null where room_id = p_room_id;
	delete from public.multiplayer_v2_round_acks where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_ack_manifest(p_room_id uuid, p_manifest_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_hash text; v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select manifest_hash, phase into v_hash, v_phase from public.multiplayer_rooms where room_id = p_room_id;
	if v_phase <> 'OPEN' or v_hash is null or v_hash <> p_manifest_hash then raise exception 'manifest_hash_mismatch'; end if;
	update public.multiplayer_room_members set loaded_manifest_hash = p_manifest_hash, last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	return public._multiplayer_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_prepare_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_count integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' or v_room.manifest_hash is null then raise exception 'room_not_preparable'; end if;
	select count(*) into v_count from public.multiplayer_room_members where room_id = p_room_id and last_seen_at > now() - interval '45 seconds' and is_ready and loaded_manifest_hash = v_room.manifest_hash;
	if v_count < 2 then raise exception 'players_not_ready'; end if;
	update public.multiplayer_rooms set phase = 'PREPARING_COURSE', lobby_generation = lobby_generation + 1, last_activity_at = now() where room_id = p_room_id;
	insert into public.multiplayer_v2_round_acks(room_id, lobby_generation, user_id) select p_room_id, v_room.lobby_generation + 1, user_id from public.multiplayer_room_members where room_id = p_room_id and last_seen_at > now() - interval '45 seconds' on conflict do nothing;
	return public._multiplayer_room_payload(p_room_id);
end $$;

revoke all on function public._multiplayer_assert_network_mode(uuid,text) from public, anon, authenticated;
revoke all on function public._multiplayer_v2_realtime_member(text) from public, anon, authenticated;
revoke all on function public.multiplayer_v2_create_room(text,text,smallint,bigint,integer,boolean) from public, anon;
revoke all on function public.multiplayer_v2_join_room(text,text,text,smallint,smallint) from public, anon;
revoke all on function public.multiplayer_v2_list_public_rooms() from public, anon;
revoke all on function public.multiplayer_v2_refresh_room(uuid) from public, anon;
revoke all on function public.multiplayer_v2_set_ready(uuid,boolean) from public, anon;
revoke all on function public.multiplayer_v2_leave_room(uuid) from public, anon;
revoke all on function public.multiplayer_v2_set_manifest(uuid,bigint,integer,text) from public, anon;
revoke all on function public.multiplayer_v2_ack_manifest(uuid,text) from public, anon;
revoke all on function public.multiplayer_v2_prepare_round(uuid) from public, anon;
revoke all on function public.multiplayer_v2_set_phase(uuid,text) from public, anon;
revoke all on function public.multiplayer_v2_return_to_lobby(uuid) from public, anon;
grant execute on function public._multiplayer_v2_realtime_member(text) to authenticated;
grant execute on function public.multiplayer_v2_create_room(text,text,smallint,bigint,integer,boolean) to authenticated;
grant execute on function public.multiplayer_v2_join_room(text,text,text,smallint,smallint) to authenticated;
grant execute on function public.multiplayer_v2_list_public_rooms() to authenticated;
grant execute on function public.multiplayer_v2_refresh_room(uuid) to authenticated;
grant execute on function public.multiplayer_v2_set_ready(uuid,boolean) to authenticated;
grant execute on function public.multiplayer_v2_leave_room(uuid) to authenticated;
grant execute on function public.multiplayer_v2_set_manifest(uuid,bigint,integer,text) to authenticated;
grant execute on function public.multiplayer_v2_ack_manifest(uuid,text) to authenticated;
grant execute on function public.multiplayer_v2_prepare_round(uuid) to authenticated;
grant execute on function public.multiplayer_v2_set_phase(uuid,text) to authenticated;
grant execute on function public.multiplayer_v2_return_to_lobby(uuid) to authenticated;
