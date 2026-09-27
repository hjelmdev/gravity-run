-- Keep transient disconnects visible during the existing 45-second grace
-- period, then remove abandoned guest rows during any active room refresh.
-- Preserve the owner row so a temporarily disconnected host can reconnect.
create or replace function public.refresh_multiplayer_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_owner_user_id uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	update public.multiplayer_room_members
	set last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;

	select owner_user_id into v_owner_user_id
	from public.multiplayer_rooms
	where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED')
	for update;
	if not found then raise exception 'room_not_found'; end if;

	delete from public.multiplayer_room_members
	where room_id = p_room_id
		and user_id <> v_owner_user_id
		and last_seen_at < now() - interval '45 seconds';

	update public.multiplayer_rooms
	set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED');
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

revoke all on function public.refresh_multiplayer_room(uuid) from public, anon;
grant execute on function public.refresh_multiplayer_room(uuid) to authenticated;
