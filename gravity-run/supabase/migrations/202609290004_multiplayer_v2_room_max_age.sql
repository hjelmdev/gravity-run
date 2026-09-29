-- Bound V2 room discovery and refresh to a hard lifetime. Refresh polling must
-- not keep an abandoned public room alive forever.
create or replace function public.multiplayer_v2_list_public_rooms()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	return coalesce((select jsonb_agg(jsonb_build_object(
		'room_id', r.room_id, 'room_code', r.room_code, 'host_name', coalesce((select m.display_name from public.multiplayer_room_members m where m.room_id = r.room_id and m.user_id = r.owner_user_id), 'Host'),
		'player_count', active.member_count, 'max_players', r.max_players, 'network_mode', r.network_mode
	) order by r.created_at desc)
	from public.multiplayer_rooms r cross join lateral (select count(*)::integer as member_count, coalesce(bool_or(m.user_id = r.owner_user_id), false) as owner_active from public.multiplayer_room_members m where m.room_id = r.room_id and m.last_seen_at > now() - interval '45 seconds') active
	where r.network_mode = 'v2' and r.is_public and r.phase = 'OPEN' and r.expires_at > now() and r.created_at > now() - interval '1 hour' and active.owner_active and active.member_count < r.max_players), '[]'::jsonb);
end $$;

create or replace function public.multiplayer_v2_refresh_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_created_at timestamptz;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	perform public._multiplayer_assert_network_mode(p_room_id, 'v2');
	select created_at into v_created_at from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then return '{}'::jsonb; end if;
	if v_created_at <= now() - interval '1 hour' then
		update public.multiplayer_rooms set phase = 'CLOSED', last_activity_at = now(), expires_at = now() where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED');
		return public._multiplayer_room_payload(p_room_id);
	end if;
	update public.multiplayer_room_members set last_seen_at = now() where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED');
	return public._multiplayer_room_payload(p_room_id);
end $$;
