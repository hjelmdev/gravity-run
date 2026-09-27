-- Don't advertise rooms that have no active owner or active players. Rooms
-- themselves remain available by private code until their normal expiry.
create or replace function public.list_public_multiplayer_rooms()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	return coalesce((
		select jsonb_agg(jsonb_build_object(
			'room_code', r.room_code,
			'host_name', coalesce((select m.display_name from public.multiplayer_room_members m
				where m.room_id = r.room_id and m.user_id = r.owner_user_id), 'Host'),
			'player_count', active.member_count,
			'max_players', r.max_players
		) order by r.created_at desc)
		from public.multiplayer_rooms r
		cross join lateral (
			select
				count(*)::integer as member_count,
				coalesce(bool_or(m.user_id = r.owner_user_id), false) as owner_active
			from public.multiplayer_room_members m
			where m.room_id = r.room_id and m.last_seen_at > now() - interval '45 seconds'
		) active
		where r.is_public and r.phase = 'OPEN' and r.expires_at > now()
			and active.owner_active and active.member_count > 0
			and active.member_count < r.max_players
	), '[]'::jsonb);
end;
$$;

revoke all on function public.list_public_multiplayer_rooms() from public, anon;
grant execute on function public.list_public_multiplayer_rooms() to authenticated;
