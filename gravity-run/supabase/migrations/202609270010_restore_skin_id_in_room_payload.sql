-- Preserve the selected character skin in lobby snapshots. Migration 009
-- replaced this payload function and inadvertently dropped the skin_id field.
create or replace function public._multiplayer_room_payload(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'room_id', r.room_id,
		'room_code', r.room_code,
		'owner_user_id', r.owner_user_id,
		'phase', r.phase,
		'protocol_version', r.protocol_version,
		'game_version', r.game_version,
		'generator_version', r.generator_version,
		'max_players', r.max_players,
		'seed', r.seed,
		'course_length_px', r.course_length_px,
		'manifest_hash', r.manifest_hash,
		'signaling_topic', r.signaling_topic,
		'expires_at', r.expires_at,
		'countdown_start_at_unix', extract(epoch from r.countdown_started_at),
		'members', coalesce((
			select jsonb_agg(jsonb_build_object(
				'user_id', m.user_id,
				'player_slot', m.player_slot,
				'display_name', m.display_name,
				'is_ready', m.is_ready,
				'loaded_manifest_hash', m.loaded_manifest_hash,
				'is_connected', m.last_seen_at > now() - interval '45 seconds',
				'skin_id', m.skin_id
			) order by m.player_slot)
			from public.multiplayer_room_members m
			where m.room_id = r.room_id
		), '[]'::jsonb)
	)
	from public.multiplayer_rooms r
	where r.room_id = p_room_id
	  and exists (
		select 1 from public.multiplayer_room_members mine
		where mine.room_id = r.room_id and mine.user_id = auth.uid()
	  );
$$;

revoke all on function public._multiplayer_room_payload(uuid) from public, anon, authenticated;
