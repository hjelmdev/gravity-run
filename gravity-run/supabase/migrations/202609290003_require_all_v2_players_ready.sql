-- Require every currently connected V2 lobby member to be ready on the
-- room's exact course manifest before freezing the round roster.
-- This replaces only the V2 start RPC; V1 lobby routines are unchanged.
create or replace function public.multiplayer_v2_prepare_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
	v_room public.multiplayer_rooms%rowtype;
	v_active_count integer;
	v_ready_count integer;
	v_payload jsonb;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' or v_room.manifest_hash is null then raise exception 'room_not_preparable'; end if;

	perform 1 from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
	for update;
	select
		count(*),
		count(*) filter (where is_ready and loaded_manifest_hash = v_room.manifest_hash)
	into v_active_count, v_ready_count
	from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds';
	if v_active_count < 1 or v_ready_count <> v_active_count then
		raise exception 'players_not_ready';
	end if;

	update public.multiplayer_rooms
	set phase = 'PREPARING_COURSE', lobby_generation = lobby_generation + 1, last_activity_at = now()
	where room_id = p_room_id;

	insert into public.multiplayer_v2_round_acks(room_id, lobby_generation, user_id)
	select p_room_id, v_room.lobby_generation + 1, user_id
	from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
	on conflict do nothing;

	-- Freeze only members that were active in the readiness check above. The
	-- shared V1/V2 room-payload helper intentionally remains unchanged.
	v_payload := public._multiplayer_room_payload(p_room_id);
	v_payload := jsonb_set(v_payload, '{members}', coalesce((
		select jsonb_agg(jsonb_build_object(
			'user_id', m.user_id,
			'player_slot', m.player_slot,
			'display_name', m.display_name,
			'is_ready', m.is_ready,
			'loaded_manifest_hash', m.loaded_manifest_hash,
			'skin_id', m.skin_id,
			'is_connected', true
		) order by m.player_slot)
		from public.multiplayer_room_members m
		where m.room_id = p_room_id and m.last_seen_at > now() - interval '45 seconds'
	), '[]'::jsonb), true);
	return v_payload;
end $$;

revoke all on function public.multiplayer_v2_prepare_round(uuid) from public, anon;
grant execute on function public.multiplayer_v2_prepare_round(uuid) to authenticated;
