-- Add V2-scoped skin changes for visual parity with the V1 room roster.
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
	update public.multiplayer_room_members
	set skin_id = p_skin_id, last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	get diagnostics v_rows = row_count;
	if v_rows = 0 then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms
	set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end $$;

revoke all on function public.multiplayer_v2_set_skin(uuid,smallint) from public, anon;
grant execute on function public.multiplayer_v2_set_skin(uuid,smallint) to authenticated;
