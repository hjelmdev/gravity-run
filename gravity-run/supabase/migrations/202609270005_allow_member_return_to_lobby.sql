-- A finished race is a group flow, but any player should be able to request
-- the existing room to return to its lobby instead of waiting on the host.
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
	set phase = 'OPEN', last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	update public.multiplayer_room_members
	set is_ready = false, loaded_manifest_hash = null, last_seen_at = now()
	where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

revoke all on function public.return_multiplayer_room_to_lobby(uuid) from public, anon;
grant execute on function public.return_multiplayer_room_to_lobby(uuid) to authenticated;
