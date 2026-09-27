-- Private, short-lived multiplayer rooms. All writes go through narrow RPCs;
-- clients never receive direct table privileges.

create table if not exists public.multiplayer_rooms (
	room_id uuid primary key default gen_random_uuid(),
	room_code text not null unique,
	owner_user_id uuid not null references auth.users(id) on delete cascade,
	phase text not null default 'OPEN'
		check (phase in ('OPEN', 'PREPARING_COURSE', 'COUNTDOWN', 'RUNNING', 'FINISHED', 'CLOSED')),
	protocol_version smallint not null default 1 check (protocol_version > 0),
	game_version text not null,
	generator_version smallint not null check (generator_version > 0),
	max_players smallint not null default 4 check (max_players between 2 and 4),
	seed bigint not null,
	course_length_px integer not null default 45000 check (course_length_px between 10000 and 1000000),
	manifest_hash text,
	-- The topic is a capability as well as a room-scoped channel name. It is
	-- returned only to room members and is never derivable from the join code.
	signaling_topic text not null unique,
	created_at timestamptz not null default now(),
	last_activity_at timestamptz not null default now(),
	expires_at timestamptz not null default now() + interval '15 minutes'
);

create table if not exists public.multiplayer_room_members (
	room_id uuid not null references public.multiplayer_rooms(room_id) on delete cascade,
	user_id uuid not null references auth.users(id) on delete cascade,
	player_slot smallint not null check (player_slot between 1 and 4),
	display_name text not null check (char_length(display_name) between 1 and 16),
	is_ready boolean not null default false,
	loaded_manifest_hash text,
	joined_at timestamptz not null default now(),
	last_seen_at timestamptz not null default now(),
	primary key (room_id, user_id),
	unique (room_id, player_slot)
);

create index if not exists multiplayer_rooms_expiry_idx
	on public.multiplayer_rooms (expires_at);
create index if not exists multiplayer_members_user_idx
	on public.multiplayer_room_members (user_id, last_seen_at desc);

alter table public.multiplayer_rooms enable row level security;
alter table public.multiplayer_room_members enable row level security;
revoke all on table public.multiplayer_rooms, public.multiplayer_room_members
	from public, anon, authenticated;

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
				'is_connected', m.last_seen_at > now() - interval '45 seconds'
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

create or replace function public.create_multiplayer_room(
	p_display_name text,
	p_game_version text,
	p_generator_version smallint,
	p_seed bigint,
	p_course_length_px integer default 45000
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
	-- Eight-character code is for typing convenience only; it is not an auth token.
	loop
		v_room_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8));
		exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_room_code);
	end loop;
	insert into public.multiplayer_rooms (
		room_id, room_code, owner_user_id, game_version, generator_version,
		seed, course_length_px, signaling_topic
	) values (
		v_room_id, v_room_code, auth.uid(), btrim(p_game_version),
		p_generator_version, p_seed, p_course_length_px, v_topic
	);
	insert into public.multiplayer_room_members (room_id, user_id, player_slot, display_name)
	values (v_room_id, auth.uid(), 1, btrim(p_display_name));
	return public._multiplayer_room_payload(v_room_id);
end;
$$;

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
	select coalesce(max(player_slot), 0) + 1 into v_slot
	from public.multiplayer_room_members where room_id = v_room.room_id;
	if v_slot > v_room.max_players then raise exception 'room_full'; end if;
	insert into public.multiplayer_room_members (room_id, user_id, player_slot, display_name)
	values (v_room.room_id, auth.uid(), v_slot, btrim(p_display_name));
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = v_room.room_id;
	return public._multiplayer_room_payload(v_room.room_id);
end;
$$;

create or replace function public.refresh_multiplayer_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	update public.multiplayer_room_members set last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id and phase not in ('CLOSED', 'FINISHED');
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

create or replace function public.set_multiplayer_ready(p_room_id uuid, p_ready boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_phase text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select phase into v_phase from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	update public.multiplayer_room_members set is_ready = p_ready, last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

create or replace function public.ack_multiplayer_manifest(p_room_id uuid, p_manifest_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.phase <> 'OPEN' or v_room.manifest_hash is null then raise exception 'manifest_not_available'; end if;
	if p_manifest_hash is null or p_manifest_hash <> v_room.manifest_hash then raise exception 'manifest_hash_mismatch'; end if;
	update public.multiplayer_room_members set loaded_manifest_hash = p_manifest_hash, last_seen_at = now()
	where room_id = p_room_id and user_id = auth.uid();
	if not found then raise exception 'not_room_member'; end if;
	update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

create or replace function public.set_multiplayer_manifest(
	p_room_id uuid,
	p_seed bigint,
	p_course_length_px integer,
	p_manifest_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_room public.multiplayer_rooms%rowtype;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;
	if p_manifest_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_manifest_hash'; end if;
	update public.multiplayer_rooms set seed = p_seed, course_length_px = p_course_length_px,
		manifest_hash = p_manifest_hash, last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	update public.multiplayer_room_members set is_ready = false, loaded_manifest_hash = null where room_id = p_room_id;
	return public._multiplayer_room_payload(p_room_id);
end;
$$;

create or replace function public.start_multiplayer_countdown(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_room public.multiplayer_rooms%rowtype;
	v_member_count integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase <> 'OPEN' then raise exception 'room_not_open'; end if;
	if v_room.manifest_hash is null then raise exception 'manifest_not_available'; end if;
	select count(*) into v_member_count from public.multiplayer_room_members
	where room_id = p_room_id and last_seen_at > now() - interval '45 seconds';
	if v_member_count < 2 then raise exception 'not_enough_players'; end if;
	if exists (
		select 1 from public.multiplayer_room_members
		where room_id = p_room_id and last_seen_at > now() - interval '45 seconds'
		  and (not is_ready or loaded_manifest_hash is distinct from v_room.manifest_hash)
	) then raise exception 'players_not_ready'; end if;
	update public.multiplayer_rooms set phase = 'COUNTDOWN', last_activity_at = now(), expires_at = now() + interval '15 minutes'
	where room_id = p_room_id;
	return jsonb_build_object('room', public._multiplayer_room_payload(p_room_id), 'start_at', now() + interval '5 seconds');
end;
$$;

create or replace function public.leave_multiplayer_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_owner uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select owner_user_id into v_owner from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then return; end if;
	if not exists (select 1 from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid()) then
		raise exception 'not_room_member';
	end if;
	if v_owner = auth.uid() then
		update public.multiplayer_rooms set phase = 'CLOSED', last_activity_at = now(), expires_at = now() where room_id = p_room_id;
	else
		delete from public.multiplayer_room_members where room_id = p_room_id and user_id = auth.uid();
		update public.multiplayer_rooms set last_activity_at = now(), expires_at = now() + interval '15 minutes' where room_id = p_room_id;
	end if;
end;
$$;

create or replace function public._multiplayer_realtime_member(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
	select auth.uid() is not null and exists (
		select 1 from public.multiplayer_rooms r
		join public.multiplayer_room_members m on m.room_id = r.room_id
		where r.signaling_topic = p_topic and r.expires_at > now()
		  and r.phase not in ('CLOSED', 'FINISHED') and m.user_id = auth.uid()
	);
$$;

-- These policies grant access only on private Realtime topics matching the
-- opaque topic returned by a successful create/join RPC. They do not grant any
-- access to room tables through PostgREST.
drop policy if exists multiplayer_room_broadcast_read on realtime.messages;
create policy multiplayer_room_broadcast_read on realtime.messages
	for select to authenticated
	using (extension = 'broadcast' and public._multiplayer_realtime_member(realtime.topic()));
drop policy if exists multiplayer_room_broadcast_send on realtime.messages;
create policy multiplayer_room_broadcast_send on realtime.messages
	for insert to authenticated
	with check (extension = 'broadcast' and public._multiplayer_realtime_member(realtime.topic()));

revoke all on function public._multiplayer_room_payload(uuid) from public, anon, authenticated;
revoke all on function public._multiplayer_realtime_member(text) from public, anon, authenticated;
revoke all on function public.create_multiplayer_room(text, text, smallint, bigint, integer) from public, anon;
revoke all on function public.join_multiplayer_room(text, text, text, smallint, smallint) from public, anon;
revoke all on function public.refresh_multiplayer_room(uuid) from public, anon;
revoke all on function public.set_multiplayer_ready(uuid, boolean) from public, anon;
revoke all on function public.ack_multiplayer_manifest(uuid, text) from public, anon;
revoke all on function public.set_multiplayer_manifest(uuid, bigint, integer, text) from public, anon;
revoke all on function public.start_multiplayer_countdown(uuid) from public, anon;
revoke all on function public.leave_multiplayer_room(uuid) from public, anon;
grant execute on function public._multiplayer_realtime_member(text) to authenticated;
grant execute on function public.create_multiplayer_room(text, text, smallint, bigint, integer) to authenticated;
grant execute on function public.join_multiplayer_room(text, text, text, smallint, smallint) to authenticated;
grant execute on function public.refresh_multiplayer_room(uuid) to authenticated;
grant execute on function public.set_multiplayer_ready(uuid, boolean) to authenticated;
grant execute on function public.ack_multiplayer_manifest(uuid, text) to authenticated;
grant execute on function public.set_multiplayer_manifest(uuid, bigint, integer, text) to authenticated;
grant execute on function public.start_multiplayer_countdown(uuid) to authenticated;
grant execute on function public.leave_multiplayer_room(uuid) to authenticated;
