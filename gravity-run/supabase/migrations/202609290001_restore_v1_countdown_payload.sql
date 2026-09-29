-- The V2 room payload replaced the V1 helper and omitted this timestamp.
-- V1 clients use it to keep polling from restarting the countdown at 5s.
create or replace function public._multiplayer_room_payload(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'room_id', r.room_id, 'room_code', r.room_code, 'owner_user_id', r.owner_user_id,
		'phase', r.phase, 'protocol_version', r.protocol_version, 'network_mode', r.network_mode,
		'v2_protocol_version', r.v2_protocol_version, 'lobby_generation', r.lobby_generation, 'room_session_id', r.room_session_id,
		'game_version', r.game_version, 'generator_version', r.generator_version,
		'max_players', r.max_players, 'seed', r.seed, 'course_length_px', r.course_length_px,
		'manifest_hash', r.manifest_hash, 'signaling_topic', r.signaling_topic,
		'expires_at', r.expires_at,
		'countdown_start_at_unix', extract(epoch from r.countdown_started_at),
		'members', coalesce((select jsonb_agg(jsonb_build_object(
			'user_id', m.user_id, 'player_slot', m.player_slot, 'display_name', m.display_name,
			'is_ready', m.is_ready, 'loaded_manifest_hash', m.loaded_manifest_hash, 'skin_id', m.skin_id,
			'is_connected', m.last_seen_at > now() - interval '45 seconds'
		) order by m.player_slot) from public.multiplayer_room_members m where m.room_id = r.room_id), '[]'::jsonb)
	)
	from public.multiplayer_rooms r
	where r.room_id = p_room_id and exists (select 1 from public.multiplayer_room_members mine where mine.room_id = r.room_id and mine.user_id = auth.uid());
$$;

revoke all on function public._multiplayer_room_payload(uuid) from public, anon, authenticated;
