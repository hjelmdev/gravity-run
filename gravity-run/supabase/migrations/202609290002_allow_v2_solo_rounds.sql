-- V2 lobbies support a host starting a single-player round.
-- Re-create this function only; all V1 multiplayer routines remain untouched.
create or replace function public.multiplayer_v2_prepare_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_count integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' or v_room.manifest_hash is null then raise exception 'room_not_preparable'; end if;
	select count(*) into v_count from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
		and is_ready and loaded_manifest_hash = v_room.manifest_hash;
	if v_count < 1 then raise exception 'players_not_ready'; end if;
	update public.multiplayer_rooms
	set phase = 'PREPARING_COURSE', lobby_generation = lobby_generation + 1, last_activity_at = now()
	where room_id = p_room_id;
	insert into public.multiplayer_v2_round_acks(room_id, lobby_generation, user_id)
	select p_room_id, v_room.lobby_generation + 1, user_id from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
	on conflict do nothing;
	return public._multiplayer_room_payload(p_room_id);
end $$;

revoke all on function public.multiplayer_v2_prepare_round(uuid) from public, anon;
grant execute on function public.multiplayer_v2_prepare_round(uuid) to authenticated;
