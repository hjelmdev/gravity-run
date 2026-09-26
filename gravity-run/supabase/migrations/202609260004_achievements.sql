-- Account-only, server-authoritative achievements. A tier is an independent
-- row so thresholds can be extended without migrating existing unlocks.
create table if not exists public.achievement_definitions (
	achievement_id text not null,
	tier integer not null,
	metric text not null,
	threshold bigint not null,
	title_key text not null,
	description_key text not null,
	visibility text not null default 'visible',
	primary key (achievement_id, tier),
	constraint achievement_tier_positive check (tier > 0),
	constraint achievement_threshold_positive check (threshold > 0),
	constraint achievement_metric_supported check (metric in ('total_distance_m', 'best_run_distance_m')),
	constraint achievement_visibility_supported check (visibility in ('visible', 'secret'))
);

insert into public.achievement_definitions
	(achievement_id, tier, metric, threshold, title_key, description_key, visibility)
values
	('distance_total', 1, 'total_distance_m', 250, 'Distance collector I', 'Run 250 m in total.', 'visible'),
	('distance_total', 2, 'total_distance_m', 500, 'Distance collector II', 'Run 500 m in total.', 'visible'),
	('distance_total', 3, 'total_distance_m', 1000, 'Distance collector III', 'Run 1,000 m in total.', 'visible'),
	('distance_run', 1, 'best_run_distance_m', 250, 'Long run I', 'Reach 250 m in one run.', 'visible'),
	('distance_run', 2, 'best_run_distance_m', 500, 'Long run II', 'Reach 500 m in one run.', 'visible'),
	('distance_run', 3, 'best_run_distance_m', 1000, 'Long run III', 'Reach 1,000 m in one run.', 'visible')
on conflict (achievement_id, tier) do nothing;

create table if not exists public.player_achievement_stats (
	user_id uuid primary key references auth.users (id) on delete cascade,
	total_distance_m bigint not null default 0,
	best_run_distance_m integer not null default 0,
	updated_at timestamptz not null default now(),
	constraint achievement_total_distance_range check (total_distance_m between 0 and 1000000000000000),
	constraint achievement_best_distance_range check (best_run_distance_m between 0 and 10000000)
);

alter table public.achievement_definitions enable row level security;
alter table public.player_achievement_stats enable row level security;
revoke all on table public.achievement_definitions from public, anon, authenticated;
revoke all on table public.player_achievement_stats from public, anon, authenticated;

create table if not exists public.player_achievements (
	user_id uuid not null references auth.users (id) on delete cascade,
	achievement_id text not null,
	tier integer not null,
	unlocked_at timestamptz not null default now(),
	primary key (user_id, achievement_id, tier),
	foreign key (achievement_id, tier) references public.achievement_definitions (achievement_id, tier)
);

alter table public.player_achievements enable row level security;
revoke all on table public.player_achievements from public, anon, authenticated;

-- Existing signed-in progress counts too: do not make current players repeat
-- distance they have already earned before this feature was installed.
insert into public.player_achievement_stats (user_id, total_distance_m, best_run_distance_m)
select p.user_id, p.total_distance_m, p.best_distance_m
from public.player_progress p
on conflict (user_id) do update set
	total_distance_m = greatest(public.player_achievement_stats.total_distance_m, excluded.total_distance_m),
	best_run_distance_m = greatest(public.player_achievement_stats.best_run_distance_m, excluded.best_run_distance_m),
	updated_at = now();

insert into public.player_achievements (user_id, achievement_id, tier)
select s.user_id, d.achievement_id, d.tier
from public.player_achievement_stats s
join public.achievement_definitions d
	on (d.metric = 'total_distance_m' and s.total_distance_m >= d.threshold)
	 or (d.metric = 'best_run_distance_m' and s.best_run_distance_m >= d.threshold)
on conflict (user_id, achievement_id, tier) do nothing;

create or replace function public.get_my_achievements()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	return jsonb_build_object(
		'total_distance_m', coalesce((select s.total_distance_m from public.player_achievement_stats s where s.user_id = current_user_id), 0),
		'best_run_distance_m', coalesce((select s.best_run_distance_m from public.player_achievement_stats s where s.user_id = current_user_id), 0),
		'unlocked', coalesce((
			select jsonb_agg(jsonb_build_object('achievement_id', a.achievement_id, 'tier', a.tier, 'unlocked_at', a.unlocked_at) order by a.achievement_id, a.tier)
			from public.player_achievements a where a.user_id = current_user_id
		), '[]'::jsonb)
	);
end;
$$;

create or replace function public.record_player_run(
	p_run_id uuid,
	p_distance_m integer,
	p_coins_earned integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	inserted_rows integer := 0;
	result jsonb;
	total_m bigint;
	best_m integer;
	new_unlocks jsonb := '[]'::jsonb;
	definition record;
	new_unlock record;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if p_run_id is null then
		raise exception 'invalid_run_id' using errcode = '22023';
	end if;
	if p_distance_m is null or p_distance_m not between 0 and 10000000 then
		raise exception 'invalid_distance' using errcode = '22023';
	end if;
	if p_coins_earned is null or p_coins_earned not between 0 and 1000000 then
		raise exception 'invalid_coin_reward' using errcode = '22023';
	end if;

	insert into public.player_run_history (user_id, run_id, distance_m, coins_earned)
	values (current_user_id, p_run_id, p_distance_m, p_coins_earned)
	on conflict (user_id, run_id) do nothing;
	get diagnostics inserted_rows = row_count;

	if inserted_rows = 1 then
		insert into public.player_progress (user_id, wallet_coins, total_distance_m, best_distance_m)
		values (current_user_id, p_coins_earned, p_distance_m, p_distance_m)
		on conflict (user_id) do update set
			wallet_coins = public.player_progress.wallet_coins + excluded.wallet_coins,
			total_distance_m = public.player_progress.total_distance_m + excluded.total_distance_m,
			best_distance_m = greatest(public.player_progress.best_distance_m, excluded.best_distance_m),
			updated_at = now();

		insert into public.player_achievement_stats (user_id, total_distance_m, best_run_distance_m)
		values (current_user_id, p_distance_m, p_distance_m)
		on conflict (user_id) do update set
			total_distance_m = public.player_achievement_stats.total_distance_m + excluded.total_distance_m,
			best_run_distance_m = greatest(public.player_achievement_stats.best_run_distance_m, excluded.best_run_distance_m),
			updated_at = now();

		select s.total_distance_m, s.best_run_distance_m into total_m, best_m
		from public.player_achievement_stats s where s.user_id = current_user_id;

		for definition in
			select d.achievement_id, d.tier, d.metric, d.threshold
			from public.achievement_definitions d
			where (d.metric = 'total_distance_m' and d.threshold <= total_m)
			   or (d.metric = 'best_run_distance_m' and d.threshold <= best_m)
		loop
			insert into public.player_achievements (user_id, achievement_id, tier)
			values (current_user_id, definition.achievement_id, definition.tier)
			on conflict (user_id, achievement_id, tier) do nothing
			returning achievement_id, tier, unlocked_at into new_unlock;
			if found then
				new_unlocks := new_unlocks || jsonb_build_array(jsonb_build_object(
					'achievement_id', new_unlock.achievement_id,
					'tier', new_unlock.tier,
					'unlocked_at', new_unlock.unlocked_at
				));
			end if;
		end loop;
	end if;

	select jsonb_build_object(
		'wallet_coins', p.wallet_coins,
		'total_distance_m', p.total_distance_m,
		'best_distance_m', p.best_distance_m,
		'run_recorded', inserted_rows = 1,
		'new_achievements', new_unlocks
	) into result
	from public.player_progress p where p.user_id = current_user_id;

	return coalesce(result, jsonb_build_object(
		'wallet_coins', 0, 'total_distance_m', 0, 'best_distance_m', 0,
		'run_recorded', false, 'new_achievements', '[]'::jsonb
	));
end;
$$;

revoke all on function public.get_my_achievements() from public, anon;
revoke all on function public.record_player_run(uuid, integer, integer) from public, anon;
grant execute on function public.get_my_achievements() to authenticated;
grant execute on function public.record_player_run(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';
