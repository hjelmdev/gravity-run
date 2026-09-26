-- The local PL/pgSQL variable `hazard_id` collided with the table column of
-- the same name in the ON CONFLICT clause, preventing any account run save.
-- Keep the RPC contract and behavior unchanged; use a distinct variable name.
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
	v_hazard_id text;
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

		for v_hazard_id in
			select distinct h from unnest(coalesce(p_hazards_encountered, array[]::text[])) h
		loop
			insert into public.player_achievement_hazards (user_id, hazard_id)
			values (current_user_id, v_hazard_id)
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

revoke all on function public.record_player_run(uuid, integer, integer, integer, text[]) from public, anon;
grant execute on function public.record_player_run(uuid, integer, integer, integer, text[]) to authenticated;
notify pgrst, 'reload schema';
