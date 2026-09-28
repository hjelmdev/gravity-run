-- Short-lived, explicit-opt-in multiplayer diagnostics. Match telemetry stays
-- in client memory and is uploaded once, after the round has ended.

create table if not exists public.multiplayer_diagnostic_testers (
	user_id uuid primary key references auth.users(id) on delete cascade,
	enabled boolean not null default false,
	enabled_until timestamptz not null default now() + interval '30 days',
	updated_at timestamptz not null default now()
);

create table if not exists public.multiplayer_diagnostic_sessions (
	session_id uuid primary key default gen_random_uuid(),
	match_id uuid not null unique,
	room_id uuid not null,
	owner_user_id uuid not null references auth.users(id) on delete cascade,
	expected_user_ids uuid[] not null check (cardinality(expected_user_ids) between 1 and 5),
	created_at timestamptz not null default now(),
	expires_at timestamptz not null default now() + interval '7 days',
	check (expires_at <= created_at + interval '7 days' + interval '1 minute')
);

create table if not exists public.multiplayer_diagnostic_reports (
	report_id uuid primary key,
	session_id uuid not null references public.multiplayer_diagnostic_sessions(session_id) on delete cascade,
	match_id uuid not null,
	match_generation text not null default '' check (char_length(match_generation) <= 96),
	client_instance_id uuid not null,
	uploaded_by uuid not null references auth.users(id) on delete cascade,
	role text not null check (role in ('host', 'guest', 'unknown')),
	player_label text not null default 'unknown' check (char_length(player_label) <= 32),
	build_id text not null default 'unknown' check (char_length(build_id) <= 80),
	schema_version smallint not null check (schema_version = 1),
	created_at timestamptz not null default now(),
	expires_at timestamptz not null default now() + interval '7 days',
	payload_bytes integer not null check (payload_bytes between 1 and 131072),
	summary jsonb not null check (jsonb_typeof(summary) = 'object'),
	report jsonb not null check (jsonb_typeof(report) = 'object'),
	unique (session_id, uploaded_by)
);

create index if not exists multiplayer_diagnostic_reports_session_idx
	on public.multiplayer_diagnostic_reports (session_id, created_at);
create index if not exists multiplayer_diagnostic_reports_expiry_idx
	on public.multiplayer_diagnostic_reports (expires_at);
create index if not exists multiplayer_diagnostic_sessions_expiry_idx
	on public.multiplayer_diagnostic_sessions (expires_at, created_at);

alter table public.multiplayer_diagnostic_testers enable row level security;
alter table public.multiplayer_diagnostic_sessions enable row level security;
alter table public.multiplayer_diagnostic_reports enable row level security;
revoke all on public.multiplayer_diagnostic_testers, public.multiplayer_diagnostic_sessions, public.multiplayer_diagnostic_reports from public, anon, authenticated;

create or replace function public.set_multiplayer_diagnostic_opt_in(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid();
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	if p_enabled then
		insert into public.multiplayer_diagnostic_testers (user_id, enabled, enabled_until, updated_at)
		values (v_user_id, true, now() + interval '30 days', now())
		on conflict (user_id) do update set enabled = true, enabled_until = excluded.enabled_until, updated_at = now();
	else
		update public.multiplayer_diagnostic_testers set enabled = false, updated_at = now() where user_id = v_user_id;
	end if;
	return jsonb_build_object('enabled', p_enabled, 'expires_at', (select enabled_until from public.multiplayer_diagnostic_testers where user_id = v_user_id));
end;
$$;

create or replace function public.create_multiplayer_diagnostic_session(p_room_id uuid, p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_user_id uuid := auth.uid();
	v_room public.multiplayer_rooms%rowtype;
	v_expected uuid[];
	v_missing integer;
	v_session public.multiplayer_diagnostic_sessions%rowtype;
	v_count integer;
	v_old_session uuid;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	if p_match_id is null then raise exception 'invalid_match_id'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id for update;
	if not found then raise exception 'room_not_found'; end if;
	if v_room.owner_user_id <> v_user_id then raise exception 'not_room_owner'; end if;
	if v_room.phase not in ('OPEN', 'COUNTDOWN', 'RUNNING') then raise exception 'diagnostic_session_requires_active_match'; end if;
	select array_agg(m.user_id order by m.player_slot), count(*) filter (where coalesce(t.enabled, false) = false or t.enabled_until <= now())
	into v_expected, v_missing
	from public.multiplayer_room_members m
	left join public.multiplayer_diagnostic_testers t on t.user_id = m.user_id
	where m.room_id = p_room_id;
	if coalesce(cardinality(v_expected), 0) < 1 or cardinality(v_expected) > 5 then raise exception 'invalid_diagnostic_roster'; end if;
	if v_missing > 0 then raise exception 'diagnostic_opt_in_required_for_all_players'; end if;
	perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('multiplayer_diagnostics_global_capacity', 0));
	if v_room.phase = 'OPEN' and exists (
		select 1 from public.multiplayer_room_members m
		where m.room_id = p_room_id and (not m.is_ready or m.loaded_manifest_hash is distinct from v_room.manifest_hash)
	) then raise exception 'diagnostic_session_requires_ready_players'; end if;
	select * into v_session from public.multiplayer_diagnostic_sessions where match_id = p_match_id;
	if found then
		if v_session.owner_user_id <> v_user_id or v_session.room_id <> p_room_id or v_session.expected_user_ids <> v_expected then raise exception 'diagnostic_match_id_conflict'; end if;
		return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id, 'expected_user_ids', v_session.expected_user_ids, 'expires_at', v_session.expires_at);
	end if;
	if (select count(*) from public.multiplayer_diagnostic_sessions where owner_user_id = v_user_id and created_at > now() - interval '1 hour') >= 10 then raise exception 'diagnostic_account_hourly_session_quota_exceeded'; end if;
	select count(*) into v_count from public.multiplayer_diagnostic_sessions;
	while v_count >= 200 loop
		select session_id into v_old_session from public.multiplayer_diagnostic_sessions
		order by created_at asc limit 1 for update skip locked;
		if v_old_session is null then raise exception 'diagnostic_global_session_capacity_reached'; end if;
		delete from public.multiplayer_diagnostic_sessions where session_id = v_old_session;
		select count(*) into v_count from public.multiplayer_diagnostic_sessions;
	end loop;
	insert into public.multiplayer_diagnostic_sessions (match_id, room_id, owner_user_id, expected_user_ids)
	values (p_match_id, p_room_id, v_user_id, v_expected)
	returning * into v_session;
	return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id, 'expected_user_ids', v_session.expected_user_ids, 'expires_at', v_session.expires_at);
end;
$$;

create or replace function public._cleanup_multiplayer_diagnostic_reports()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_reports integer; v_sessions integer;
begin
	delete from public.multiplayer_diagnostic_reports where expires_at <= now();
	get diagnostics v_reports = row_count;
	delete from public.multiplayer_diagnostic_sessions where expires_at <= now();
	get diagnostics v_sessions = row_count;
	delete from public.multiplayer_diagnostic_testers where enabled_until <= now();
	return jsonb_build_object('expired_reports_deleted', v_reports, 'expired_sessions_deleted', v_sessions);
end;
$$;

create or replace function public.upload_multiplayer_diagnostic_report(
	p_session_id uuid, p_match_id uuid, p_report_id uuid, p_schema_version integer,
	p_build_id text, p_summary jsonb, p_report jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_user_id uuid := auth.uid();
	v_session public.multiplayer_diagnostic_sessions%rowtype;
	v_existing public.multiplayer_diagnostic_reports%rowtype;
	v_payload_bytes integer;
	v_count integer;
	v_old_session uuid;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	if p_schema_version <> 1 or jsonb_typeof(p_summary) <> 'object' or jsonb_typeof(p_report) <> 'object' then raise exception 'invalid_diagnostic_schema'; end if;
	if p_report_id is null or p_match_id is null or p_build_id is null or char_length(p_build_id) > 80 then raise exception 'invalid_diagnostic_metadata'; end if;
	v_payload_bytes := octet_length(convert_to(jsonb_build_object('summary', p_summary, 'report', p_report)::text, 'UTF8'));
	if v_payload_bytes < 1 or v_payload_bytes > 131072 then raise exception 'diagnostic_report_too_large'; end if;
	if p_report->>'report_id' <> p_report_id::text or p_report->>'match_id' <> p_match_id::text or p_report->>'diagnostic_session_id' <> p_session_id::text then raise exception 'diagnostic_report_identity_mismatch'; end if;
	if coalesce(p_report->>'build_id', '') <> p_build_id or char_length(coalesce(p_report->>'match_generation', '')) > 96 then raise exception 'invalid_diagnostic_metadata'; end if;
	select * into v_session from public.multiplayer_diagnostic_sessions where session_id = p_session_id and match_id = p_match_id and expires_at > now();
	if not found then raise exception 'diagnostic_session_not_found'; end if;
	if not (v_user_id = any(v_session.expected_user_ids)) then raise exception 'diagnostic_user_not_in_session'; end if;
	if not exists (select 1 from public.multiplayer_diagnostic_testers where user_id = v_user_id and enabled and enabled_until > now()) then raise exception 'diagnostic_opt_in_required'; end if;
	if p_report->>'client_instance_id' is null or coalesce(p_report->>'role', 'unknown') not in ('host', 'guest', 'unknown') then raise exception 'invalid_diagnostic_metadata'; end if;
	perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('multiplayer_diagnostics_global_capacity', 0));
	perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 1));
	select * into v_existing from public.multiplayer_diagnostic_reports where report_id = p_report_id;
	if found then
		if v_existing.uploaded_by = v_user_id and v_existing.session_id = p_session_id and v_existing.match_id = p_match_id and v_existing.summary = p_summary and v_existing.report = p_report then
			return jsonb_build_object('accepted', true, 'duplicate', true, 'session_id', p_session_id, 'received_count', (select count(*) from public.multiplayer_diagnostic_reports where session_id = p_session_id));
		end if;
		raise exception 'diagnostic_report_id_payload_mismatch';
	end if;
	if exists (select 1 from public.multiplayer_diagnostic_reports where session_id = p_session_id and uploaded_by = v_user_id) then raise exception 'diagnostic_report_already_uploaded'; end if;
	if (select count(*) from public.multiplayer_diagnostic_reports where uploaded_by = v_user_id and created_at > now() - interval '1 hour') >= 10 then raise exception 'diagnostic_account_hourly_quota_exceeded'; end if;
	perform public._cleanup_multiplayer_diagnostic_reports();
	select count(*) into v_count from public.multiplayer_diagnostic_reports;
	while v_count >= 200 loop
		select s.session_id into v_old_session
		from public.multiplayer_diagnostic_sessions s
		where s.session_id <> p_session_id and exists (select 1 from public.multiplayer_diagnostic_reports r where r.session_id = s.session_id)
		order by s.created_at asc limit 1 for update skip locked;
		if v_old_session is null then raise exception 'diagnostic_global_capacity_reached'; end if;
		delete from public.multiplayer_diagnostic_sessions where session_id = v_old_session;
		select count(*) into v_count from public.multiplayer_diagnostic_reports;
	end loop;
	insert into public.multiplayer_diagnostic_reports (
		report_id, session_id, match_id, match_generation, client_instance_id, uploaded_by,
		role, player_label, build_id, schema_version, expires_at, payload_bytes, summary, report
	) values (
		p_report_id, p_session_id, p_match_id, coalesce(p_report->>'match_generation', ''),
		(p_report->>'client_instance_id')::uuid, v_user_id, p_report->>'role',
		left(coalesce(p_report->>'player_label', 'unknown'), 32), p_build_id, p_schema_version,
		now() + interval '7 days', v_payload_bytes, p_summary, p_report
	);
	return jsonb_build_object('accepted', true, 'duplicate', false, 'session_id', p_session_id, 'received_count', (select count(*) from public.multiplayer_diagnostic_reports where session_id = p_session_id), 'expected_count', cardinality(v_session.expected_user_ids));
end;
$$;

create or replace function public.list_my_multiplayer_diagnostic_sessions(p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_result jsonb;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	select coalesce(jsonb_agg(row_value order by created_at desc), '[]'::jsonb) into v_result
	from (
		select s.created_at, jsonb_build_object(
			'session_id', s.session_id, 'match_id', s.match_id, 'room_id', s.room_id,
			'created_at', s.created_at, 'expires_at', s.expires_at,
			'expected_count', cardinality(s.expected_user_ids),
			'received_count', (select count(*) from public.multiplayer_diagnostic_reports r where r.session_id = s.session_id),
			'expected_user_ids', s.expected_user_ids,
			'reports', coalesce((select jsonb_agg(jsonb_build_object('uploaded_by', r.uploaded_by, 'role', r.role, 'player_label', r.player_label, 'build_id', r.build_id, 'created_at', r.created_at, 'summary', r.summary) order by r.created_at) from public.multiplayer_diagnostic_reports r where r.session_id = s.session_id), '[]'::jsonb)
		) as row_value
		from public.multiplayer_diagnostic_sessions s
		where v_user_id = any(s.expected_user_ids) and s.expires_at > now()
		order by s.created_at desc limit greatest(1, least(coalesce(p_limit, 10), 20))
	) q;
	return v_result;
end;
$$;

create or replace function public.get_multiplayer_diagnostic_session_reports(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_user_id uuid := auth.uid(); v_session public.multiplayer_diagnostic_sessions%rowtype; v_reports jsonb;
begin
	if v_user_id is null then raise exception 'not_authenticated'; end if;
	select * into v_session from public.multiplayer_diagnostic_sessions where session_id = p_session_id and expires_at > now();
	if not found or not (v_user_id = any(v_session.expected_user_ids)) then raise exception 'diagnostic_session_not_available'; end if;
	select coalesce(jsonb_agg(jsonb_build_object(
		'report_id', r.report_id, 'uploaded_by', r.uploaded_by, 'role', r.role,
		'player_label', r.player_label, 'client_instance_id', r.client_instance_id,
		'build_id', r.build_id, 'schema_version', r.schema_version,
		'created_at', r.created_at, 'payload_bytes', r.payload_bytes,
		'summary', r.summary, 'report', r.report
	) order by r.created_at), '[]'::jsonb) into v_reports
	from public.multiplayer_diagnostic_reports r where r.session_id = p_session_id;
	return jsonb_build_object('session_id', v_session.session_id, 'match_id', v_session.match_id,
		'created_at', v_session.created_at, 'expires_at', v_session.expires_at,
		'expected_user_ids', v_session.expected_user_ids, 'expected_count', cardinality(v_session.expected_user_ids),
		'received_count', jsonb_array_length(v_reports), 'reports', v_reports);
end;
$$;

create or replace function public.multiplayer_diagnostic_storage_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'reports', (select count(*) from public.multiplayer_diagnostic_reports),
		'sessions', (select count(*) from public.multiplayer_diagnostic_sessions),
		'reports_table_bytes', pg_catalog.pg_total_relation_size('public.multiplayer_diagnostic_reports'::regclass),
		'sessions_table_bytes', pg_catalog.pg_total_relation_size('public.multiplayer_diagnostic_sessions'::regclass),
		'global_report_cap', 200, 'max_report_bytes', 131072, 'retention_days', 7
	);
$$;

revoke all on function public.set_multiplayer_diagnostic_opt_in(boolean) from public, anon;
revoke all on function public.create_multiplayer_diagnostic_session(uuid, uuid) from public, anon;
revoke all on function public.upload_multiplayer_diagnostic_report(uuid, uuid, uuid, integer, text, jsonb, jsonb) from public, anon;
revoke all on function public.list_my_multiplayer_diagnostic_sessions(integer) from public, anon;
revoke all on function public.get_multiplayer_diagnostic_session_reports(uuid) from public, anon;
revoke all on function public.multiplayer_diagnostic_storage_stats() from public, anon, authenticated;
revoke all on function public._cleanup_multiplayer_diagnostic_reports() from public, anon, authenticated;
grant execute on function public.set_multiplayer_diagnostic_opt_in(boolean) to authenticated;
grant execute on function public.create_multiplayer_diagnostic_session(uuid, uuid) to authenticated;
grant execute on function public.upload_multiplayer_diagnostic_report(uuid, uuid, uuid, integer, text, jsonb, jsonb) to authenticated;
grant execute on function public.list_my_multiplayer_diagnostic_sessions(integer) to authenticated;
grant execute on function public.get_multiplayer_diagnostic_session_reports(uuid) to authenticated;

-- pg_cron is supported on hosted Supabase but may not be enabled in an existing project.
create extension if not exists pg_cron;
do $$
begin
	if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
		perform cron.schedule('multiplayer-diagnostics-hourly-cleanup', '17 * * * *', 'select public._cleanup_multiplayer_diagnostic_reports()');
	end if;
end;
$$;
