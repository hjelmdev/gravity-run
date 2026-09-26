-- Shareable challenge definitions. These rows contain only public challenge
-- settings and a display nickname; they are not tied to an account UUID.
create table if not exists public.seed_challenges (
	challenge_code text primary key,
	generator_version smallint not null,
	seed integer not null,
	ruleset_fingerprint text not null,
	ruleset jsonb not null,
	creator_name text not null,
	created_at timestamptz not null default now(),
	constraint seed_challenges_code check (challenge_code ~ '^GC-[A-F0-9]{12}$'),
	constraint seed_challenges_version check (generator_version > 0),
	constraint seed_challenges_seed check (seed between 1 and 2147483647),
	constraint seed_challenges_fingerprint check (ruleset_fingerprint ~ '^[a-f0-9]{16}$'),
	constraint seed_challenges_ruleset_object check (
		jsonb_typeof(ruleset) = 'object' and octet_length(ruleset::text) <= 8192
	),
	constraint seed_challenges_name check (creator_name ~ '^[A-Za-z0-9_]{3,16}$')
);

create index if not exists seed_challenges_created_idx
	on public.seed_challenges (created_at desc);

alter table public.seed_challenges enable row level security;
revoke all on table public.seed_challenges from public, anon, authenticated;

-- Existing generic seed scores remain intact. New challenge-linked attempts
-- are scoped to the shareable challenge, so distinct rulesets never mix boards.
alter table public.seed_challenge_runs
	add column if not exists challenge_code text references public.seed_challenges(challenge_code) on delete cascade;

create index if not exists seed_challenge_runs_challenge_board_idx
	on public.seed_challenge_runs (challenge_code, player_name_normalized, distance_m desc)
	where challenge_code is not null;

create or replace function public.create_seed_challenge(
	p_generator_version smallint,
	p_seed integer,
	p_ruleset_fingerprint text,
	p_ruleset jsonb,
	p_nickname text
)
returns table (challenge_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
	new_code text;
	weight_entry record;
	current_user_id uuid := (select auth.uid());
	submitted_name text := btrim(coalesce(p_nickname, ''));
	profile_name text;
begin
	if p_generator_version <= 0 or p_seed < 1 or p_seed > 2147483647 then
		raise exception 'invalid_challenge_definition' using errcode = '22023';
	end if;
	if coalesce(p_ruleset_fingerprint, '') !~ '^[a-f0-9]{16}$' or jsonb_typeof(p_ruleset) is distinct from 'object' then
		raise exception 'invalid_challenge_ruleset' using errcode = '22023';
	end if;
	if jsonb_typeof(p_ruleset -> 'include_all_profiles') is distinct from 'boolean'
		or jsonb_typeof(p_ruleset -> 'ruleset_id') is distinct from 'string'
		or length(coalesce(p_ruleset ->> 'ruleset_id', '')) not between 1 and 48
		or jsonb_typeof(p_ruleset -> 'revision') is distinct from 'number'
		or jsonb_typeof(p_ruleset -> 'included_profile_ids') is distinct from 'array'
		or jsonb_typeof(p_ruleset -> 'profile_weight_multipliers') is distinct from 'object'
		or jsonb_typeof(p_ruleset -> 'event_density') is distinct from 'number'
		or jsonb_typeof(p_ruleset -> 'hazard_size') is distinct from 'number'
		or jsonb_typeof(p_ruleset -> 'lane_alternation') is distinct from 'number'
		or jsonb_typeof(p_ruleset -> 'reaction_margin') is distinct from 'number'
		or octet_length(p_ruleset::text) > 8192
	then
		raise exception 'invalid_challenge_ruleset' using errcode = '22023';
	end if;
	if (p_ruleset ->> 'revision')::numeric not between 1 and 1000
		or (p_ruleset ->> 'revision')::numeric <> trunc((p_ruleset ->> 'revision')::numeric)
		or jsonb_array_length(p_ruleset -> 'included_profile_ids') > 64
	then
		raise exception 'invalid_challenge_ruleset' using errcode = '22023';
	end if;
	if exists (
		select 1
		from jsonb_array_elements(p_ruleset -> 'included_profile_ids') as profile(value)
		where jsonb_typeof(profile.value) is distinct from 'string'
			or length(profile.value #>> '{}') not between 1 and 48
	) then
		raise exception 'invalid_challenge_ruleset' using errcode = '22023';
	end if;
	for weight_entry in
		select key, value from jsonb_each(p_ruleset -> 'profile_weight_multipliers')
	loop
		if jsonb_typeof(weight_entry.value) is distinct from 'number' then
			raise exception 'invalid_challenge_ruleset' using errcode = '22023';
		end if;
		if (weight_entry.value #>> '{}')::numeric not between 0 and 100 then
			raise exception 'invalid_challenge_ruleset' using errcode = '22023';
		end if;
	end loop;
	if (p_ruleset ->> 'event_density')::numeric not between 0.5 and 2.5
		or (p_ruleset ->> 'hazard_size')::numeric not between 0.75 and 1.5
		or (p_ruleset ->> 'lane_alternation')::numeric not between 0 and 1
		or (p_ruleset ->> 'reaction_margin')::numeric not between 0 and 2
	then
		raise exception 'invalid_challenge_ruleset' using errcode = '22023';
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
		if exists (
			select 1 from public.player_profiles as p
			where p.nickname_normalized = lower(submitted_name)
		) then
			raise exception 'nickname_reserved' using errcode = '23505';
		end if;
	end if;

	loop
		new_code := 'GC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
		exit when not exists (
			select 1 from public.seed_challenges as c where c.challenge_code = new_code
		);
	end loop;

	insert into public.seed_challenges (
		challenge_code, generator_version, seed, ruleset_fingerprint, ruleset, creator_name
	) values (
		new_code, p_generator_version, p_seed, p_ruleset_fingerprint, p_ruleset, submitted_name
	);
	return query select new_code;
end;
$$;

create or replace function public.get_seed_challenge(p_challenge_code text)
returns table (
	challenge_code text,
	generator_version smallint,
	seed integer,
	ruleset_fingerprint text,
	ruleset jsonb,
	creator_name text,
	created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
	select c.challenge_code, c.generator_version, c.seed,
		c.ruleset_fingerprint, c.ruleset, c.creator_name, c.created_at
	from public.seed_challenges as c
	where c.challenge_code = upper(btrim(p_challenge_code))
	limit 1;
$$;

create or replace function public.get_seed_challenge_leaderboard(p_challenge_code text)
returns table (player_name text, best_distance_m integer, attempts bigint)
language sql
stable
security definer
set search_path = ''
as $$
	select
		(array_agg(r.player_name order by r.created_at desc))[1] as player_name,
		max(r.distance_m)::integer as best_distance_m,
		count(*)::bigint as attempts
	from public.seed_challenge_runs as r
	where r.challenge_code = upper(btrim(p_challenge_code))
	group by r.player_name_normalized
	order by max(r.distance_m) desc, min(r.created_at) asc
	limit 5;
$$;

create or replace function public.submit_seed_challenge_run(
	p_challenge_code text,
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
	if p_distance_m < 0 or not exists (
		select 1 from public.seed_challenges as c
		where c.challenge_code = upper(btrim(p_challenge_code))
	) then
		raise exception 'unknown_challenge_or_distance' using errcode = '22023';
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
		if exists (
			select 1 from public.player_profiles as p
			where p.nickname_normalized = lower(submitted_name)
		) then
			raise exception 'nickname_reserved' using errcode = '23505';
		end if;
	end if;

	insert into public.seed_challenge_runs (
		generator_version, seed, challenge_code, player_name, player_name_normalized, distance_m
	)
	select c.generator_version, c.seed, c.challenge_code,
		submitted_name, lower(submitted_name), p_distance_m
	from public.seed_challenges as c
	where c.challenge_code = upper(btrim(p_challenge_code));

	return jsonb_build_object('saved', true, 'player_name', submitted_name);
end;
$$;

revoke all on function public.create_seed_challenge(smallint, integer, text, jsonb, text) from public;
revoke all on function public.get_seed_challenge(text) from public;
revoke all on function public.get_seed_challenge_leaderboard(text) from public;
revoke all on function public.submit_seed_challenge_run(text, text, integer) from public;
grant execute on function public.create_seed_challenge(smallint, integer, text, jsonb, text) to anon, authenticated;
grant execute on function public.get_seed_challenge(text) to anon, authenticated;
grant execute on function public.get_seed_challenge_leaderboard(text) to anon, authenticated;
grant execute on function public.submit_seed_challenge_run(text, text, integer) to anon, authenticated;
