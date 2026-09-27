-- Make the lobby countdown observable to every client, even if the one-shot
-- WebRTC start packet is lost. Deleting a host-owned room on leave also
-- prevents a closed room from lingering in the public-room table.
alter table public.multiplayer_rooms
	add column if not exists countdown_started_at timestamptz;

create or replace function public._multiplayer_room_payload(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'room_id', r.room_id,
		'room_code', r.room_code,
		'owner_user_id', r.owner_user_id,
		'phase', r.phase,
		'protocol_version', r.protocol_version,
		'game_version', r.game_version,
		'generator_version', r.generator_version,
		'max_players', r.max_players,
		'seed', r.seed,
		'course_length_px', r.course_length_px,
		'manifest_hash', r.manifest_hash,
		'signaling_topic', r.signaling_topic,
		'expires_at', r.expires_at,
		'countdown_start_at_unix', extract(epoch from r.countdown_started_at),
		'members', coalesce((
			select jsonb_agg(jsonb_build_object(
				'user_id', m.user_id,
				'player_slot', m.player_slot,
				'display_name', m.display_name,
				'is_ready', m.is_ready,
				'loaded_manifest_hash', m.loaded_manifest_hash,
				'is_connected', m.last_seen_at > now() - interval '45 seconds'
			) order by m.player_slot)
			from public.multiplayer_room_members m
			where m.room_id = r.room_id
		), '[]'::jsonb)
	)
	from public.multiplayer_rooms r
	where r.room_id = p_room_id
	  and exists (
		select 1 from public.multiplayer_room_members mine
		where mine.room_id = r.room_id and mine.user_id = auth.uid()
	  );
$$;

create or replace function public.start_multiplayer_countdown(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room public.multiplayer_rooms%rowtype;
	v_member_count integer;
	v_start_at timestamptz := now();
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.manifest_hash is null then raise exception 'manifest_not_available'; end if;
	select count(*) into v_member_count from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds';
	if v_member_count < 1 then raise exception 'no_active_players'; end if;
	if exists (
		select 1 from public.multiplayer_room_members
		where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
		  and (not is_ready or loaded_manifest_hash is distinct from v_room.manifest_hash)
	) then raise exception 'players_not_ready'; end if;
	update public.multiplayer_rooms
	set phase = 'COUNTDOWN', countdown_started_at = v_start_at,
		last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return jsonb_build_object(
		'room', public._multiplayer_room_payload(p_room_id),
		'start_at', v_start_at + interval '5 seconds',
		'start_at_unix', extract(epoch from v_start_at + interval '5 seconds')
	);
end;
$$;

create or replace function public.return_multiplayer_room_to_lobby(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if not exists (
		select 1 from public.multiplayer_room_members m
		where m.room_id = p_room_id and m.user_id = auth.uid()
	) then raise exception 'not_room_member'; end if;
	if v_room.phase not in ('COUNTDOWN', 'RUNNING', 'FINISHED') then raise exception 'room_not_in_match'; end if;
	update public.multiplayer_rooms
	set phase = 'OPEN', countdown_started_at = null,
		last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	update public.multiplayer_room_members
	set is_ready = false, loaded_manifest_hash = null, last_seen_at = now()
	where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

create or replace function public.leave_multiplayer_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_owner uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select owner_user_id into v_owner from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then return; end if;
	if not exists (select 1 from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid()) then
		raise exception 'not_room_member';
	end if;
	if v_owner = auth.uid() then
		delete from public.multiplayer_rooms where room_id = p_room_id;
	else
		delete from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid();
		update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	end if;
end;
$$;

revoke all on function public._multiplayer_room_payload(uuid) from public, anon, authenticated;
revoke all on function public.start_multiplayer_countdown(uuid) from public, anon;
grant execute on function public.start_multiplayer_countdown(uuid) to authenticated;
revoke all on function public.return_multiplayer_room_to_lobby(uuid) from public, anon;
grant execute on function public.return_multiplayer_room_to_lobby(uuid) to authenticated;
revoke all on function public.leave_multiplayer_room(uuid) from public, anon;
grant execute on function public.leave_multiplayer_room(uuid) to authenticated;
