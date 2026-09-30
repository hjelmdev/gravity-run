-- V2-only lobby revisions and per-member result return. V1 room RPCs and the
-- shared room payload are deliberately untouched.
alter table public.multiplayer_rooms
	add column if not exists roster_revision bigint not null default 1,
	add column if not exists content_revision bigint not null default 1,
	add column if not exists lobby_cycle bigint not null default 1,
	add column if not exists state_revision bigint not null default 1;

alter table public.multiplayer_room_members
	add column if not exists ready_cycle bigint not null default 0,
	add column if not exists ready_content_revision bigint not null default 0,
	add column if not exists loadout_hash text,
	add column if not exists ready_loadout_hash text,
	add column if not exists returned_for_cycle bigint not null default 0;

create or replace function public._multiplayer_v2_room_payload(p_room_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_payload jsonb;
begin
	-- Extend the common payload only for V2 so the established V1 JSON contract
	-- keeps its original shape.
	v_payload := public._multiplayer_room_payload(p_room_id);
	if v_payload is null then return null; end if;
	select v_payload || jsonb_build_object(
		'roster_revision', r.roster_revision, 'content_revision', r.content_revision,
		'lobby_cycle', r.lobby_cycle, 'state_revision', r.state_revision,
		'members', coalesce((select jsonb_agg(jsonb_build_object(
			'user_id', m.user_id, 'player_slot', m.player_slot, 'display_name', m.display_name,
			'is_ready', m.is_ready, 'ready_cycle', m.ready_cycle,
			'ready_content_revision', m.ready_content_revision,
			'loadout_hash', m.loadout_hash, 'ready_loadout_hash', m.ready_loadout_hash,
			'returned_for_cycle', m.returned_for_cycle,
			'loaded_manifest_hash', m.loaded_manifest_hash, 'skin_id', m.skin_id,
			'is_connected', m.last_seen_at > now() - interval '45 seconds'
		) order by m.player_slot) from public.multiplayer_room_members m where m.room_id = r.room_id), '[]'::jsonb)
	) into v_payload
	from public.multiplayer_rooms r where r.room_id = p_room_id;
	return v_payload;
end $$;

-- New protocol/game versions prevent a pre-cycle client from joining this
-- RPC contract while old V1 clients keep using their unchanged endpoints.
create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version is null or char_length(p_game_version) not between 1 and 32 or p_generator_version <= 0 then raise exception 'invalid_version'; end if;
	if p_game_version <> '2.1.20260930.4' then raise exception 'version_mismatch'; end if;
	if p_seed not between 1 and 2147483647 then raise exception 'invalid_seed'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;
	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	loop v_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8)); exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_code); end loop;
	insert into public.multiplayer_rooms(room_id, room_code, owner_user_id, game_version, generator_version, seed, course_length_px, signaling_topic, is_public, max_players, network_mode, v2_protocol_version)
	values(v_room_id, v_code, auth.uid(), btrim(p_game_version), p_generator_version, p_seed, p_course_length_px, v_topic, coalesce(p_is_public, true), 5, 'v2', 2);
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name, returned_for_cycle)
	values(v_room_id, auth.uid(), 1, btrim(p_display_name), 1);
	return public._multiplayer_v2_room_payload(v_room_id);
end $$;

create or replace function public.multiplayer_v2_join_room(p_room_code text, p_display_name text, p_game_version text, p_generator_version smallint, p_v2_protocol_version smallint default 2)
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
	if exists(select 1 from public.multiplayer_room_members where room_id = v_room.room_id and user_id = auth.uid() and last_seen_at > now() - interval '45 seconds') then raise exception 'identity_already_in_room'; end if;
	delete from public.multiplayer_room_members where room_id = v_room.room_id and last_seen_at < now() - interval '45 seconds';
	if auth.uid() = v_room.owner_user_id then raise exception 'host_must_reuse_current_session'; end if;
	select slots.slot::smallint into v_slot from generate_series(1, v_room.max_players) as slots(slot)
	where not exists(select 1 from public.multiplayer_room_members m where m.room_id = v_room.room_id and m.player_slot = slots.slot) order by slots.slot limit 1;
	if v_slot is null then raise exception 'room_full'; end if;
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name, returned_for_cycle)
	values(v_room.room_id, auth.uid(), v_slot, btrim(p_display_name), v_room.lobby_cycle);
	update public.multiplayer_rooms set lobby_generation = lobby_generation + 1, roster_revision = roster_revision + 1,
		state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = v_room.room_id;
	return public._multiplayer_v2_room_payload(v_room.room_id);
end $$;

create or replace function public.multiplayer_v2_set_ready(
	p_room_id uuid, p_ready boolean, p_expected_cycle bigint, p_expected_content_revision bigint, p_loadout_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.lobby_cycle <> p_expected_cycle or v_room.content_revision <> p_expected_content_revision then raise exception 'stale_lobby_confirmation'; end if;
	if p_loadout_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_loadout_hash'; end if;
	update public.multiplayer_room_members set is_ready = p_ready,
		ready_cycle = case when p_ready then p_expected_cycle else 0 end,
		ready_content_revision = case when p_ready then p_expected_content_revision else 0 end,
		loadout_hash = p_loadout_hash,
		ready_loadout_hash = case when p_ready then p_loadout_hash else null end,
		last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid() and returned_for_cycle = v_room.lobby_cycle;
	if not found then raise exception 'not_returned_to_current_cycle'; end if;
	update public.multiplayer_rooms set state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

-- Prevent old clients from bypassing cycle/content-bound ready confirmation.
drop function if exists public.multiplayer_v2_set_ready(uuid, boolean);

create or replace function public.multiplayer_v2_refresh_room(p_room_id uuid, p_loadout_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_old_hash text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	if p_loadout_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_loadout_hash'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	select loadout_hash into v_old_hash from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid() for update;
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_room_members set
		is_ready = case when v_old_hash is distinct from p_loadout_hash then false else is_ready end,
		ready_cycle = case when v_old_hash is distinct from p_loadout_hash then 0 else ready_cycle end,
		ready_content_revision = case when v_old_hash is distinct from p_loadout_hash then 0 else ready_content_revision end,
		ready_loadout_hash = case when v_old_hash is distinct from p_loadout_hash then null else ready_loadout_hash end,
		loadout_hash = p_loadout_hash, last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	update public.multiplayer_rooms set state_revision = state_revision + case when v_old_hash is distinct from p_loadout_hash then 1 else 0 end,
		last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id and phase <> 'CLOSED';
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

drop function if exists public.multiplayer_v2_refresh_room(uuid);

create or replace function public.multiplayer_v2_set_manifest(p_room_id uuid, p_seed bigint, p_course_length_px integer, p_manifest_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.owner_user_id <> auth.uid() or v_room.phase <> 'OPEN' then raise exception 'not_room_owner_or_open'; end if;
	if p_seed not between 1 and 2147483647 or p_course_length_px not between 10000 and 1000000 or p_manifest_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_manifest'; end if;
	if v_room.seed = p_seed and v_room.course_length_px = p_course_length_px and v_room.manifest_hash = p_manifest_hash then
		return public._multiplayer_v2_room_payload(p_room_id);
	end if;
	update public.multiplayer_rooms set seed = p_seed, course_length_px = p_course_length_px, manifest_hash = p_manifest_hash,
		content_revision = content_revision + 1, state_revision = state_revision + 1, lobby_generation = lobby_generation + 1,
		last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, ready_cycle = 0, ready_content_revision = 0, loaded_manifest_hash = null where room_id = p_room_id;
	delete from public.multiplayer_v2_round_acks where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_ack_manifest(p_room_id uuid, p_manifest_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.phase <> 'OPEN' or v_room.manifest_hash is null or v_room.manifest_hash <> p_manifest_hash then raise exception 'manifest_hash_mismatch'; end if;
	update public.multiplayer_room_members set loaded_manifest_hash = p_manifest_hash, last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set state_revision = state_revision + 1 where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_return_member(p_room_id uuid, p_expected_cycle bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_target_cycle bigint;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.phase not in ('FINISHED', 'PREPARING_COURSE', 'RUNNING', 'OPEN') then raise exception 'stale_result_return'; end if;
	if v_room.phase = 'OPEN' then
		if p_expected_cycle not in (v_room.lobby_cycle - 1, v_room.lobby_cycle) then raise exception 'stale_result_return'; end if;
	else
		if p_expected_cycle <> v_room.lobby_cycle then raise exception 'stale_result_return'; end if;
	end if;
	v_target_cycle := v_room.lobby_cycle + case when v_room.phase = 'OPEN' then 0 else 1 end;
	update public.multiplayer_room_members set returned_for_cycle = greatest(returned_for_cycle, v_target_cycle), is_ready = false,
		ready_cycle = 0, ready_content_revision = 0, last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_return_to_lobby(p_room_id uuid, p_expected_cycle bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase = 'OPEN' then
		if p_expected_cycle not in (v_room.lobby_cycle - 1, v_room.lobby_cycle) then raise exception 'stale_result_return'; end if;
		return public._multiplayer_v2_room_payload(p_room_id);
	end if;
	if p_expected_cycle <> v_room.lobby_cycle then raise exception 'stale_result_return'; end if;
	if v_room.phase not in ('FINISHED', 'PREPARING_COURSE', 'RUNNING') then raise exception 'round_not_finished'; end if;
	update public.multiplayer_rooms set phase = 'OPEN', lobby_generation = lobby_generation + 1,
		lobby_cycle = lobby_cycle + 1, state_revision = state_revision + 1,
		last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, ready_cycle = 0, ready_content_revision = 0,
		returned_for_cycle = case when user_id = auth.uid() then v_room.lobby_cycle + 1 else least(returned_for_cycle, v_room.lobby_cycle + 1) end
	where room_id = p_room_id;
	delete from public.multiplayer_v2_round_acks where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_kick_member(p_room_id uuid, p_target_user_id uuid, p_target_slot smallint, p_expected_cycle bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_current_slot smallint;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' or v_room.lobby_cycle <> p_expected_cycle then raise exception 'stale_kick'; end if;
	if p_target_user_id = auth.uid() or p_target_slot < 2 then raise exception 'invalid_kick_target'; end if;
	select player_slot into v_current_slot from public.multiplayer_room_members where room_id = p_room_id and user_id = p_target_user_id;
	if not found then return public._multiplayer_v2_room_payload(p_room_id); end if;
	if v_current_slot <> p_target_slot then raise exception 'kick_target_changed'; end if;
	delete from public.multiplayer_room_members where room_id = p_room_id and user_id = p_target_user_id and player_slot = p_target_slot;
	if not found then raise exception 'kick_target_changed'; end if;
	update public.multiplayer_rooms set lobby_generation = lobby_generation + 1, roster_revision = roster_revision + 1,
		state_revision = state_revision + 1, last_activity_at = now() where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

-- The former host-only call has no generation guard and could open a later
-- cycle from a stale result page.
drop function if exists public.multiplayer_v2_return_to_lobby(uuid);

create or replace function public.multiplayer_v2_prepare_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_count integer; v_payload jsonb;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' or v_room.manifest_hash is null then raise exception 'room_not_preparable'; end if;
	perform 1 from public.multiplayer_room_members where room_id = p_room_id for update;
	select count(*) into v_count from public.multiplayer_room_members where room_id = p_room_id
		and last_seen_at > now() - interval '45 seconds' and returned_for_cycle >= v_room.lobby_cycle
		and is_ready and ready_cycle = v_room.lobby_cycle and ready_content_revision = v_room.content_revision
		and loadout_hash is not null and ready_loadout_hash = loadout_hash
		and loaded_manifest_hash = v_room.manifest_hash;
	if v_count < 1 or v_count <> (select count(*) from public.multiplayer_room_members where room_id = p_room_id and last_seen_at > now() - interval '45 seconds') then raise exception 'players_not_ready_or_returned'; end if;
	update public.multiplayer_rooms set phase = 'PREPARING_COURSE', lobby_generation = lobby_generation + 1,
		state_revision = state_revision + 1, last_activity_at = now() where room_id = p_room_id;
	insert into public.multiplayer_v2_round_acks(room_id, lobby_generation, user_id)
	select p_room_id, v_room.lobby_generation + 1, user_id from public.multiplayer_room_members where room_id = p_room_id and last_seen_at > now() - interval '45 seconds' on conflict do nothing;
	v_payload := public._multiplayer_v2_room_payload(p_room_id);
	v_payload := jsonb_set(v_payload, '{members}', coalesce((select jsonb_agg(jsonb_build_object(
		'user_id', m.user_id, 'player_slot', m.player_slot, 'display_name', m.display_name, 'is_ready', m.is_ready,
		'ready_cycle', m.ready_cycle, 'ready_content_revision', m.ready_content_revision, 'returned_for_cycle', m.returned_for_cycle,
		'loadout_hash', m.loadout_hash, 'ready_loadout_hash', m.ready_loadout_hash,
		'loaded_manifest_hash', m.loaded_manifest_hash, 'skin_id', m.skin_id, 'is_connected', true)
		order by m.player_slot) from public.multiplayer_room_members m where m.room_id = p_room_id and m.last_seen_at > now() - interval '45 seconds'), '[]'::jsonb), true);
	return v_payload;
end $$;

create or replace function public.multiplayer_v2_set_skin(p_room_id uuid, p_skin_id smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_phase text; v_rows integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	if p_skin_id not between 0 and 3 then raise exception 'invalid_skin'; end if;
	select phase into v_phase from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	update public.multiplayer_room_members set skin_id = p_skin_id, last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	get diagnostics v_rows = row_count;
	if v_rows = 0 then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_set_phase(p_room_id uuid, p_phase text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	if p_phase not in ('RUNNING', 'FINISHED') then raise exception 'invalid_phase'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if p_phase = 'RUNNING' and v_room.phase <> 'PREPARING_COURSE' then raise exception 'invalid_phase_transition'; end if;
	if p_phase = 'FINISHED' and v_room.phase not in ('RUNNING', 'FINISHED') then raise exception 'invalid_phase_transition'; end if;
	update public.multiplayer_rooms set phase = p_phase, state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_v2_room_payload(p_room_id);
end $$;

create or replace function public.multiplayer_v2_leave_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_removed integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then return; end if;
	if not exists(select 1 from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid()) then raise exception 'not_room_member'; end if;
	if v_room.owner_user_id = auth.uid() then
		update public.multiplayer_rooms set phase = 'CLOSED', lobby_generation = lobby_generation + 1, roster_revision = roster_revision + 1, state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() where room_id = p_room_id;
	else
		delete from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid();
		get diagnostics v_removed = row_count;
		if v_removed > 0 then
			update public.multiplayer_rooms set lobby_generation = lobby_generation + 1, roster_revision = roster_revision + 1, state_revision = state_revision + 1, last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
		end if;
	end if;
end $$;

revoke all on function public._multiplayer_v2_room_payload(uuid) from public, anon, authenticated;

revoke all on function public.multiplayer_v2_set_ready(uuid,boolean,bigint,bigint,text) from public, anon;
revoke all on function public.multiplayer_v2_refresh_room(uuid,text) from public, anon;
revoke all on function public.multiplayer_v2_return_member(uuid,bigint) from public, anon;
revoke all on function public.multiplayer_v2_return_to_lobby(uuid,bigint) from public, anon;
revoke all on function public.multiplayer_v2_kick_member(uuid,uuid,smallint,bigint) from public, anon;
grant execute on function public.multiplayer_v2_set_ready(uuid,boolean,bigint,bigint,text) to authenticated;
grant execute on function public.multiplayer_v2_refresh_room(uuid,text) to authenticated;
grant execute on function public.multiplayer_v2_return_member(uuid,bigint) to authenticated;
grant execute on function public.multiplayer_v2_return_to_lobby(uuid,bigint) to authenticated;
grant execute on function public.multiplayer_v2_kick_member(uuid,uuid,smallint,bigint) to authenticated;
