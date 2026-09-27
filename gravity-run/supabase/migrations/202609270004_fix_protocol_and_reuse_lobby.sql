-- Rooms created by the current client must advertise protocol 2. The original
-- table default (1) made every newly created room reject current clients.
alter table public.multiplayer_rooms
	alter column protocol_version set default 2;

alter table public.multiplayer_rooms
	add column if not exists is_public boolean not null default false;

create or replace function public.create_multiplayer_room_with_visibility(
	p_display_name text,
	p_game_version text,
	p_generator_version smallint,
	p_seed bigint,
	p_course_length_px integer,
	p_is_public boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room_id uuid := gen_random_uuid();
	v_room_code text;
	v_topic text := 'gravity-run:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16
		or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version is null or char_length(p_game_version) not between 1 and 32 then raise exception 'invalid_game_version'; end if;
	if p_generator_version <= 0 then raise exception 'unsupported_generator_version'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;

	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	loop
		v_room_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8));
		exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_room_code);
	end loop;
	insert into public.multiplayer_rooms (
		room_id, room_code, owner_user_id, game_version, generator_version,
		seed, course_length_px, signaling_topic, is_public
	) values (
		v_room_id, v_room_code, auth.uid(), btrim(p_game_version),
		p_generator_version, p_seed, p_course_length_px, v_topic, coalesce(p_is_public, false)
	);
	insert into public.multiplayer_room_members (room_id, user_id, player_slot, display_name)
	values (v_room_id, auth.uid(), 1, btrim(p_display_name));
	return public._multiplayer_room_payload(v_room_id);
end;
$$;

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
			select count(*)::integer as member_count
			from public.multiplayer_room_members m
			where m.room_id = r.room_id and m.last_seen_at > now() - interval '45 seconds'
		) active
		where r.is_public and r.phase = 'OPEN' and r.expires_at > now()
			and active.member_count < r.max_players
	), '[]'::jsonb);
end;
$$;

revoke all on function public.create_multiplayer_room_with_visibility(text, text, smallint, bigint, integer, boolean) from public, anon;
grant execute on function public.create_multiplayer_room_with_visibility(text, text, smallint, bigint, integer, boolean) to authenticated;
revoke all on function public.list_public_multiplayer_rooms() from public, anon;
grant execute on function public.list_public_multiplayer_rooms() to authenticated;

-- Keep the same room and membership after a match so the group can ready up
-- and launch another race without exchanging a new room code.
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
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
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
