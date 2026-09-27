-- Reuse the lowest free lobby slot when a player leaves; max(slot) + 1 can
-- otherwise report a room full while lower numbered slots are empty.
create or replace function public.join_multiplayer_room(
	p_room_code text,
	p_display_name text,
	p_game_version text,
	p_generator_version smallint,
	p_protocol_version smallint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room public.multiplayer_rooms%rowtype;
	v_slot smallint;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16
		or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	select * into v_room from public.multiplayer_rooms
	where room_code = upper(btrim(p_room_code)) for update;
	if not found or v_room.expires_at <= now() then raise exception 'room_not_found'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.protocol_version <> p_protocol_version or v_room.game_version <> p_game_version
		or v_room.generator_version <> p_generator_version then raise exception 'version_mismatch'; end if;
	if exists (select 1 from public.multiplayer_room_members where room_id = v_room.room_id and user_id = auth.uid()) then
		update public.multiplayer_room_members set last_seen_at = now(), display_name = btrim(p_display_name)
		where room_id = v_room.room_id and user_id = auth.uid();
		update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes'
		where room_id = v_room.room_id;
		return public._multiplayer_room_payload(v_room.room_id);
	end if;
	delete from public.multiplayer_room_members
	where room_id = v_room.room_id and last_seen_at < now() - interval '45 seconds';
	select slots.slot into v_slot
	from generate_series(1, v_room.max_players) as slots(slot)
	where not exists (
		select 1 from public.multiplayer_room_members m
		where m.room_id = v_room.room_id and m.player_slot = slots.slot
	)
	order by slots.slot limit 1;
	if v_slot is null then raise exception 'room_full'; end if;
	insert into public.multiplayer_room_members (room_id, user_id, player_slot, display_name)
	values (v_room.room_id, auth.uid(), v_slot, btrim(p_display_name));
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = v_room.room_id;
	return public._multiplayer_room_payload(v_room.room_id);
end;
$$;
