-- Seed challenge results are public, nickname-based records. No account UUID is
-- stored: each submitted run gets a database-generated bigint row id instead.
create table if not exists public.seed_challenge_runs (
	id bigint generated always as identity primary key,
	generator_version smallint not null,
	seed integer not null,
	player_name text not null,
	player_name_normalized text not null,
	distance_m integer not null,
	created_at timestamptz not null default now(),
	constraint seed_challenge_runs_version check (generator_version > 0),
	constraint seed_challenge_runs_seed check (seed between 1 and 2147483647),
	constraint seed_challenge_runs_name check (player_name ~ '^[A-Za-z0-9_]{3,16}$'),
	constraint seed_challenge_runs_name_normalized check (player_name_normalized = lower(player_name)),
	constraint seed_challenge_runs_distance check (distance_m >= 0)
);

create index if not exists seed_challenge_runs_board_idx
	on public.seed_challenge_runs (generator_version, seed, player_name_normalized, distance_m desc);

alter table public.seed_challenge_runs enable row level security;
revoke all on table public.seed_challenge_runs from public, anon, authenticated;

create or replace function public.get_seed_challenge_leaderboard(
	p_generator_version smallint,
	p_seed integer
)
returns table (player_name text, best_distance_m integer, attempts bigint)
language sql
security definer
set search_path = ''
as $$
	select
		(array_agg(r.player_name order by r.created_at desc))[1] as player_name,
		max(r.distance_m)::integer as best_distance_m,
		count(*)::bigint as attempts
	from public.seed_challenge_runs as r
	where r.generator_version = p_generator_version
		and r.seed = p_seed
	group by r.player_name_normalized
	order by max(r.distance_m) desc, min(r.created_at) asc
	limit 5;
$$;

create or replace function public.submit_seed_challenge_run(
	p_generator_version smallint,
	p_seed integer,
	p_nickname text,
	p_distance_m integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	submitted_name text := btrim(coalesce(p_nickname, ''));
	profile_name text;
begin
	if p_generator_version <= 0 or p_seed < 1 or p_distance_m < 0 then
		raise exception 'invalid_challenge_result' using errcode = '22023';
	end if;
	if submitted_name !~ '^[A-Za-z0-9_]{3,16}$' then
		raise exception 'invalid_nickname' using errcode = '22023';
	end if;

	if current_user_id is not null then
		select p.nickname into profile_name
		from public.player_profiles as p
		where p.user_id = current_user_id;
		if profile_name is not null then
			submitted_name := profile_name;
		end if;
	else
		-- Keep guest submissions from impersonating a registered profile name.
		if exists (
			select 1 from public.player_profiles as p
			where p.nickname_normalized = lower(submitted_name)
		) then
			raise exception 'nickname_reserved' using errcode = '23505';
		end if;
	end if;

	insert into public.seed_challenge_runs (
		generator_version, seed, player_name, player_name_normalized, distance_m
	) values (
		p_generator_version, p_seed, submitted_name, lower(submitted_name), p_distance_m
	);
	return jsonb_build_object('saved', true, 'player_name', submitted_name);
end;
$$;

revoke all on function public.get_seed_challenge_leaderboard(smallint, integer) from public;
revoke all on function public.submit_seed_challenge_run(smallint, integer, text, integer) from public;
grant execute on function public.get_seed_challenge_leaderboard(smallint, integer) to anon, authenticated;
grant execute on function public.submit_seed_challenge_run(smallint, integer, text, integer) to anon, authenticated;
