alter table public.multiplayer_room_members
	add column if not exists skin_id smallint not null default 0;

do $$
begin
	if not exists (
		select 1 from pg_constraint
		where conname = 'multiplayer_room_members_skin_id_check'
			and conrelid = 'public.multiplayer_room_members'::regclass
	) then
		alter table public.multiplayer_room_members
			add constraint multiplayer_room_members_skin_id_check check (skin_id between 0 and 3);
	end if;
end;
$$;

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

create or replace function public.set_multiplayer_skin(p_room_id uuid, p_skin_id smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_phase text;
	v_rows integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_skin_id not between 0 and 3 then raise exception 'invalid_skin'; end if;
	select r.phase into v_phase
	from public.multiplayer_rooms r
	where r.room_id = p_room_id
	for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	update public.multiplayer_room_members m
	set skin_id = p_skin_id, last_seen_at = now()
	where m.room_id = p_room_id and m.user_id = auth.uid();
	get diagnostics v_rows = row_count;
	if v_rows = 0 then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms r
	set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where r.room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

revoke all on function public.set_multiplayer_skin(uuid, smallint) from public, anon;
grant execute on function public.set_multiplayer_skin(uuid, smallint) to authenticated;
