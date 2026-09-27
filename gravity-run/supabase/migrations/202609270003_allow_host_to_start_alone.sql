-- The host may start immediately with the active members currently in the
-- room (including a solo run for testing). Any other active member must still
-- be ready and have acknowledged the exact authoritative course manifest.
create or replace function public.start_multiplayer_countdown(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room public.multiplayer_rooms%rowtype;
	v_member_count integer;
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
	update public.multiplayer_rooms set phase = 'COUNTDOWN', last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return jsonb_build_object('room', public._multiplayer_room_payload(p_room_id), 'start_at', now() + interval '5 seconds');
end;
$$;
