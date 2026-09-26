-- Expand the normalized catalog and account aggregates without storing
-- frame-by-frame gameplay events. This migration follows 202609260004.
alter table public.achievement_definitions
	add column if not exists scope_key text not null default '';
alter table public.achievement_definitions
	drop constraint if exists achievement_metric_supported;
alter table public.achievement_definitions
	add constraint achievement_metric_supported check (metric in (
		'total_distance_m', 'best_run_distance_m', 'total_coins_earned',
		'total_gravity_flips', 'distinct_hazards_seen', 'hazard_encounters'
	));
alter table public.achievement_definitions
	drop constraint if exists achievement_scope_key_valid;
alter table public.achievement_definitions
	add constraint achievement_scope_key_valid check (
		(metric = 'hazard_encounters' and scope_key ~ '^[a-z0-9_]{1,40}$')
		or (metric <> 'hazard_encounters' and scope_key = '')
	);

alter table public.player_achievement_stats
	add column if not exists total_coins_earned bigint not null default 0,
	add column if not exists total_gravity_flips bigint not null default 0;
alter table public.player_achievement_stats
	drop constraint if exists achievement_coin_total_range;
alter table public.player_achievement_stats
	drop constraint if exists achievement_flip_total_range;
alter table public.player_achievement_stats
	add constraint achievement_coin_total_range check (total_coins_earned between 0 and 1000000000000000),
	add constraint achievement_flip_total_range check (total_gravity_flips between 0 and 1000000000000000);

alter table public.player_run_history
	add column if not exists achievements_unlocked jsonb not null default '[]'::jsonb;

create table if not exists public.player_achievement_hazards (
	user_id uuid not null references auth.users (id) on delete cascade,
	hazard_id text not null,
	encountered_runs bigint not null default 1,
	first_seen_at timestamptz not null default now(),
	last_seen_at timestamptz not null default now(),
	primary key (user_id, hazard_id),
	constraint achievement_hazard_id_format check (hazard_id ~ '^[a-z0-9_]{1,40}$'),
	constraint achievement_hazard_run_count check (encountered_runs > 0)
);
alter table public.player_achievement_hazards enable row level security;
revoke all on table public.player_achievement_hazards from public, anon, authenticated;

-- Seed a starter set. Future tiers using these existing metrics need only a
-- new catalog row plus localized text; no evaluator/code changes are needed.
insert into public.achievement_definitions
	(achievement_id, tier, metric, threshold, scope_key, title_key, description_key, visibility)
values
	('coins_earned', 1, 'total_coins_earned', 100, '', 'Coin saver I', 'Collect 100 coins in total.', 'visible'),
	('coins_earned', 2, 'total_coins_earned', 500, '', 'Coin saver II', 'Collect 500 coins in total.', 'visible'),
	('coins_earned', 3, 'total_coins_earned', 1000, '', 'Coin saver III', 'Collect 1,000 coins in total.', 'visible'),
	('gravity_flips', 1, 'total_gravity_flips', 100, '', 'Flip master I', 'Change gravity 100 times.', 'visible'),
	('gravity_flips', 2, 'total_gravity_flips', 500, '', 'Flip master II', 'Change gravity 500 times.', 'visible'),
	('gravity_flips', 3, 'total_gravity_flips', 1000, '', 'Flip master III', 'Change gravity 1,000 times.', 'visible'),
	('hazards_discovered', 1, 'distinct_hazards_seen', 1, '', 'Sharp eyes I', 'Encounter 1 different hazard type.', 'visible'),
	('hazards_discovered', 2, 'distinct_hazards_seen', 4, '', 'Sharp eyes II', 'Encounter 4 different hazard types.', 'visible'),
	('hazards_discovered', 3, 'distinct_hazards_seen', 7, '', 'Sharp eyes III', 'Encounter 7 different hazard types.', 'visible')
on conflict (achievement_id, tier) do nothing;

-- Coin history is already retained per completed run, so it can be rebuilt
-- accurately without confusing lifetime earnings with the spendable wallet.
insert into public.player_achievement_stats (user_id, total_coins_earned)
select h.user_id, sum(h.coins_earned)::bigint
from public.player_run_history h
group by h.user_id
on conflict (user_id) do update set
	total_coins_earned = greatest(public.player_achievement_stats.total_coins_earned, excluded.total_coins_earned),
	updated_at = now();

insert into public.player_achievements (user_id, achievement_id, tier)
select s.user_id, d.achievement_id, d.tier
from public.player_achievement_stats s
join public.achievement_definitions d
	on (d.metric = 'total_distance_m' and s.total_distance_m >= d.threshold)
	 or (d.metric = 'best_run_distance_m' and s.best_run_distance_m >= d.threshold)
	 or (d.metric = 'total_coins_earned' and s.total_coins_earned >= d.threshold)
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
		'total_coins_earned', coalesce((select s.total_coins_earned from public.player_achievement_stats s where s.user_id = current_user_id), 0),
		'total_gravity_flips', coalesce((select s.total_gravity_flips from public.player_achievement_stats s where s.user_id = current_user_id), 0),
		'hazard_stats', coalesce((
			select jsonb_object_agg(h.hazard_id, h.encountered_runs)
			from public.player_achievement_hazards h where h.user_id = current_user_id
		), '{}'::jsonb),
		'unlocked', coalesce((
			select jsonb_agg(jsonb_build_object('achievement_id', a.achievement_id, 'tier', a.tier, 'unlocked_at', a.unlocked_at) order by a.achievement_id, a.tier)
			from public.player_achievements a where a.user_id = current_user_id
		), '[]'::jsonb),
		'catalog', coalesce((
			select jsonb_agg(jsonb_build_object(
				'achievement_id', d.achievement_id, 'tier', d.tier, 'metric', d.metric,
				'threshold', d.threshold, 'scope_key', d.scope_key,
				'title_key', d.title_key, 'description_key', d.description_key,
				'visibility', d.visibility
			) order by d.achievement_id, d.tier)
			from public.achievement_definitions d
		), '[]'::jsonb)
	);
end;
$$;

create or replace function public.record_player_run(
	p_run_id uuid,
	p_distance_m integer,
	p_coins_earned integer,
	p_gravity_flips integer,
	p_hazards_encountered text[]
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
	total_coins bigint;
	total_flips bigint;
	new_unlocks jsonb := '[]'::jsonb;
	definition record;
	new_unlock record;
	current_value bigint;
	hazard_id text;
	hazard_counts jsonb;
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
	if p_gravity_flips is null or p_gravity_flips not between 0 and 100000 then
		raise exception 'invalid_gravity_flips' using errcode = '22023';
	end if;
	if exists (select 1 from unnest(coalesce(p_hazards_encountered, array[]::text[])) h where h !~ '^[a-z0-9_]{1,40}$') then
		raise exception 'invalid_hazard_id' using errcode = '22023';
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

		insert into public.player_achievement_stats (user_id, total_distance_m, best_run_distance_m, total_coins_earned, total_gravity_flips)
		values (current_user_id, p_distance_m, p_distance_m, p_coins_earned, p_gravity_flips)
		on conflict (user_id) do update set
			total_distance_m = public.player_achievement_stats.total_distance_m + excluded.total_distance_m,
			best_run_distance_m = greatest(public.player_achievement_stats.best_run_distance_m, excluded.best_run_distance_m),
			total_coins_earned = public.player_achievement_stats.total_coins_earned + excluded.total_coins_earned,
			total_gravity_flips = public.player_achievement_stats.total_gravity_flips + excluded.total_gravity_flips,
			updated_at = now();

		for hazard_id in
			select distinct h from unnest(coalesce(p_hazards_encountered, array[]::text[])) h
		loop
			insert into public.player_achievement_hazards (user_id, hazard_id)
			values (current_user_id, hazard_id)
			on conflict (user_id, hazard_id) do update set
				encountered_runs = public.player_achievement_hazards.encountered_runs + 1,
				last_seen_at = now();
		end loop;

		select s.total_distance_m, s.best_run_distance_m, s.total_coins_earned, s.total_gravity_flips
		into total_m, best_m, total_coins, total_flips
		from public.player_achievement_stats s where s.user_id = current_user_id;

		for definition in select d.achievement_id, d.tier, d.metric, d.threshold, d.scope_key
			from public.achievement_definitions d
		loop
			current_value := case definition.metric
				when 'total_distance_m' then total_m
				when 'best_run_distance_m' then best_m
				when 'total_coins_earned' then total_coins
				when 'total_gravity_flips' then total_flips
				when 'distinct_hazards_seen' then (select count(*) from public.player_achievement_hazards h where h.user_id = current_user_id)
				when 'hazard_encounters' then coalesce((select h.encountered_runs from public.player_achievement_hazards h where h.user_id = current_user_id and h.hazard_id = definition.scope_key), 0)
				else 0
			end;
			if current_value < definition.threshold then
				continue;
			end if;
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
		update public.player_run_history
		set achievements_unlocked = new_unlocks
		where user_id = current_user_id and run_id = p_run_id;
	else
		-- If the original HTTP response was lost, return the same unlocks on
		-- retry so the client can show the confirmed post-run awards.
		select h.achievements_unlocked into new_unlocks
		from public.player_run_history h
		where h.user_id = current_user_id and h.run_id = p_run_id;
	end if;

	select s.total_distance_m, s.best_run_distance_m, s.total_coins_earned, s.total_gravity_flips
	into total_m, best_m, total_coins, total_flips
	from public.player_achievement_stats s where s.user_id = current_user_id;
	select coalesce(jsonb_object_agg(h.hazard_id, h.encountered_runs), '{}'::jsonb)
	into hazard_counts from public.player_achievement_hazards h where h.user_id = current_user_id;

	select jsonb_build_object(
		'wallet_coins', p.wallet_coins, 'total_distance_m', p.total_distance_m,
		'best_distance_m', p.best_distance_m, 'run_recorded', inserted_rows = 1,
		'new_achievements', new_unlocks,
		'achievement_state', jsonb_build_object(
			'total_distance_m', coalesce(total_m, 0), 'best_run_distance_m', coalesce(best_m, 0),
			'total_coins_earned', coalesce(total_coins, 0), 'total_gravity_flips', coalesce(total_flips, 0),
			'hazard_stats', coalesce(hazard_counts, '{}'::jsonb)
		)
	) into result from public.player_progress p where p.user_id = current_user_id;
	return coalesce(result, jsonb_build_object('wallet_coins', 0, 'total_distance_m', 0, 'best_distance_m', 0, 'run_recorded', false, 'new_achievements', '[]'::jsonb));
end;
$$;

-- Keep the old request shape working for already-open web clients while they
-- finish an in-flight run. New clients send all aggregate fields.
create or replace function public.record_player_run(
	p_run_id uuid,
	p_distance_m integer,
	p_coins_earned integer
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
	select public.record_player_run(p_run_id, p_distance_m, p_coins_earned, 0, array[]::text[]);
$$;

revoke all on function public.get_my_achievements() from public, anon;
revoke all on function public.record_player_run(uuid, integer, integer, integer, text[]) from public, anon;
revoke all on function public.record_player_run(uuid, integer, integer) from public, anon;
grant execute on function public.get_my_achievements() to authenticated;
grant execute on function public.record_player_run(uuid, integer, integer, integer, text[]) to authenticated;
grant execute on function public.record_player_run(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';
