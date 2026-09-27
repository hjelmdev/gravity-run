-- Match lifecycle writes are host-owned. Guests request a return through the
-- reliable peer channel; only the host may change the room-wide phase.
create or replace function public.advance_multiplayer_match_phase(p_room_id uuid, p_next_phase text)
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
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if p_next_phase = v_room.phase then
		return public._multiplayer_room_payload(p_room_id);
	end if;
	if not ((v_room.phase = 'COUNTDOWN' and p_next_phase = 'RUNNING')
		or (v_room.phase = 'RUNNING' and p_next_phase = 'FINISHED')) then
		raise exception 'invalid_match_phase_transition';
	end if;
	update public.multiplayer_rooms
	set phase = p_next_phase, last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
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
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if not exists (
		select 1 from public.multiplayer_room_members m
		where m.room_id = p_room_id and m.user_id = auth.uid()
	) then raise exception 'not_room_member'; end if;
	if v_room.phase = 'OPEN' then
		return public._multiplayer_room_payload(p_room_id);
	end if;
	if v_room.phase <> 'FINISHED' then raise exception 'room_not_finished'; end if;
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

-- FINISHED remains a live room while players inspect results and the host
-- decides whether to return the group to the lobby.
create or replace function public.refresh_multiplayer_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_owner_user_id uuid;
	v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select owner_user_id, phase into v_owner_user_id, v_phase
	from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	update public.multiplayer_room_members
	set last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	if v_phase = 'OPEN' then
		delete from public.multiplayer_room_members
		where room_id = p_room_id and user_id <> v_owner_user_id
		  and last_seen_at < now() - interval '45 seconds';
	end if;
	update public.multiplayer_rooms
	set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

revoke all on function public.advance_multiplayer_match_phase(uuid, text) from public, anon;
grant execute on function public.advance_multiplayer_match_phase(uuid, text) to authenticated;
revoke all on function public.return_multiplayer_room_to_lobby(uuid) from public, anon;
grant execute on function public.return_multiplayer_room_to_lobby(uuid) to authenticated;
revoke all on function public.refresh_multiplayer_room(uuid) from public, anon;
grant execute on function public.refresh_multiplayer_room(uuid) to authenticated;
