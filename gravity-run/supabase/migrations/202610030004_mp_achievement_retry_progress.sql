-- Correct MP achievement retry ordering and keep shared account-distance
-- progress in sync with the achievement metrics, without touching wallet.

create or replace function public._apply_achievement_progress_delta(
	p_user_id uuid, p_distance_m bigint, p_best_distance_m integer, p_coin_delta bigint,
	p_gravity_flips bigint, p_hazards text[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unlocks jsonb := '[]'::jsonb; v_definition record; v_unlock record; v_value bigint; v_hazard text; v_total bigint; v_best integer; v_coins bigint; v_flips bigint;
begin
	if p_user_id is null or p_distance_m is null or p_distance_m < 0 or p_best_distance_m is null or p_best_distance_m < 0 or p_coin_delta is null or p_coin_delta < 0 or p_gravity_flips is null or p_gravity_flips < 0 then raise exception 'invalid_achievement_delta'; end if;
	if exists (select 1 from unnest(coalesce(p_hazards, array[]::text[])) h where h !~ '^[a-z0-9_]{1,40}$') then raise exception 'invalid_achievement_hazard'; end if;
	insert into public.player_progress(user_id, wallet_coins, total_distance_m, best_distance_m)
	values(p_user_id, 0, p_distance_m, p_best_distance_m)
	on conflict(user_id) do update set
		total_distance_m = public.player_progress.total_distance_m + excluded.total_distance_m,
		best_distance_m = greatest(public.player_progress.best_distance_m, excluded.best_distance_m);
	insert into public.player_achievement_stats(user_id, total_distance_m, best_run_distance_m, total_coins_earned, total_gravity_flips)
	values(p_user_id, p_distance_m, p_best_distance_m, p_coin_delta, p_gravity_flips)
	on conflict (user_id) do update set
		total_distance_m = public.player_achievement_stats.total_distance_m + excluded.total_distance_m,
		best_run_distance_m = greatest(public.player_achievement_stats.best_run_distance_m, excluded.best_run_distance_m),
		total_coins_earned = public.player_achievement_stats.total_coins_earned + excluded.total_coins_earned,
		total_gravity_flips = public.player_achievement_stats.total_gravity_flips + excluded.total_gravity_flips,
		updated_at = now();
	foreach v_hazard in array coalesce(p_hazards, array[]::text[]) loop
		insert into public.player_achievement_hazards(user_id, hazard_id)
		values(p_user_id, v_hazard)
		on conflict(user_id, hazard_id) do update set encountered_runs = public.player_achievement_hazards.encountered_runs + 1, last_seen_at = now();
	end loop;
	select s.total_distance_m, s.best_run_distance_m, s.total_coins_earned, s.total_gravity_flips
	into v_total, v_best, v_coins, v_flips from public.player_achievement_stats s where s.user_id = p_user_id;
	for v_definition in select d.achievement_id, d.tier, d.metric, d.threshold, d.scope_key from public.achievement_definitions d loop
		v_value := case v_definition.metric
			when 'total_distance_m' then v_total
			when 'best_run_distance_m' then v_best
			when 'total_coins_earned' then v_coins
			when 'total_gravity_flips' then v_flips
			when 'distinct_hazards_seen' then (select count(*) from public.player_achievement_hazards h where h.user_id = p_user_id)
			when 'hazard_encounters' then coalesce((select h.encountered_runs from public.player_achievement_hazards h where h.user_id = p_user_id and h.hazard_id = v_definition.scope_key), 0)
			else 0
		end;
		if v_value < v_definition.threshold then continue; end if;
		insert into public.player_achievements(user_id, achievement_id, tier)
		values(p_user_id, v_definition.achievement_id, v_definition.tier)
		on conflict(user_id, achievement_id, tier) do nothing
		returning achievement_id, tier, unlocked_at into v_unlock;
		if found then v_unlocks := v_unlocks || jsonb_build_array(jsonb_build_object('achievement_id', v_unlock.achievement_id, 'tier', v_unlock.tier, 'unlocked_at', v_unlock.unlocked_at)); end if;
	end loop;
	return v_unlocks;
end $$;
revoke all on function public._apply_achievement_progress_delta(uuid,bigint,integer,bigint,bigint,text[]) from public, anon, authenticated;

create or replace function public.start_my_multiplayer_v2_achievement_run(p_runtime_round_id text, p_player_slot smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_round public.multiplayer_v2_coin_rounds%rowtype; v_member public.multiplayer_v2_coin_round_members%rowtype; v_receipt public.multiplayer_v2_achievement_receipts%rowtype; v_phase text; v_inserted integer := 0;
begin
	if v_user is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	if p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 or p_player_slot is null or p_player_slot not between 1 and 5 then raise exception 'invalid_multiplayer_run'; end if;
	select * into v_round from public.multiplayer_v2_coin_rounds r where r.runtime_round_id = p_runtime_round_id and r.generator_version = 11 order by r.created_at desc limit 1 for no key update;
	if not found then raise exception 'multiplayer_round_not_registered'; end if;
	select * into v_member from public.multiplayer_v2_coin_round_members m where m.coin_round_id = v_round.coin_round_id and m.player_slot = p_player_slot for no key update;
	if not found or v_member.account_user_id is distinct from v_user then raise exception 'multiplayer_round_account_mismatch'; end if;
	-- A lost ACK must remain safely retryable after the room advances to a new
	-- lobby generation. Authenticate against the frozen member binding first.
	select * into v_receipt from public.multiplayer_v2_achievement_receipts a where a.coin_round_id = v_round.coin_round_id and a.player_slot = p_player_slot for no key update;
	if found then
		if v_receipt.account_user_id is distinct from v_user or v_receipt.network_user_id is distinct from v_member.network_user_id or v_receipt.started_at is null then raise exception 'multiplayer_receipt_conflict'; end if;
		return jsonb_build_object('started', true, 'duplicate', true, 'runtime_round_id', p_runtime_round_id, 'player_slot', p_player_slot);
	end if;
	select r.phase into v_phase from public.multiplayer_rooms r where r.room_id = v_round.room_id and r.lobby_generation = v_round.lobby_generation;
	if v_phase is null or v_phase not in ('COUNTDOWN', 'RUNNING', 'FINISHED') then raise exception 'multiplayer_round_not_started'; end if;
	insert into public.multiplayer_v2_achievement_receipts(coin_round_id, player_slot, network_user_id, account_user_id, started_at)
	values(v_round.coin_round_id, p_player_slot, v_member.network_user_id, v_user, now())
	on conflict(coin_round_id, player_slot) do nothing;
	get diagnostics v_inserted = row_count;
	select * into v_receipt from public.multiplayer_v2_achievement_receipts a where a.coin_round_id = v_round.coin_round_id and a.player_slot = p_player_slot for no key update;
	if not found or v_receipt.account_user_id is distinct from v_user or v_receipt.network_user_id is distinct from v_member.network_user_id or v_receipt.started_at is null then raise exception 'multiplayer_receipt_conflict'; end if;
	return jsonb_build_object('started', true, 'duplicate', v_inserted = 0, 'runtime_round_id', p_runtime_round_id, 'player_slot', p_player_slot);
end $$;
revoke all on function public.start_my_multiplayer_v2_achievement_run(text,smallint) from public, anon;
grant execute on function public.start_my_multiplayer_v2_achievement_run(text,smallint) to authenticated;

create or replace function public.record_my_multiplayer_v2_achievement_run(
	p_runtime_round_id text, p_player_slot smallint, p_terminal_state text,
	p_distance_m integer, p_gravity_flips integer, p_hazards text[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_round public.multiplayer_v2_coin_rounds%rowtype; v_member public.multiplayer_v2_coin_round_members%rowtype; v_receipt public.multiplayer_v2_achievement_receipts%rowtype; v_phase text; v_hazards text[]; v_new jsonb := '[]'::jsonb; v_progress jsonb; v_inserted boolean := false;
begin
	if v_user is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	if p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 or p_player_slot is null or p_player_slot not between 1 and 5 then raise exception 'invalid_multiplayer_run'; end if;
	if p_terminal_state not in ('dead', 'finished') then raise exception 'multiplayer_round_not_terminal'; end if;
	if p_distance_m is null or p_distance_m not between 0 and 10000000 or p_gravity_flips is null or p_gravity_flips not between 0 and 100000 then raise exception 'invalid_multiplayer_metrics'; end if;
	if p_hazards is null or cardinality(p_hazards) > 10 or exists (select 1 from unnest(p_hazards) h where h not in ('spike_group','block','barrel_chain','floor_gap','ceiling_gap','terrain_step','terrain_slope','falling_rock','saw_blade','ghost')) or cardinality(p_hazards) <> (select count(distinct h) from unnest(p_hazards) h) then raise exception 'invalid_hazard_catalog'; end if;
	v_hazards := coalesce(p_hazards, array[]::text[]);
	select * into v_round from public.multiplayer_v2_coin_rounds r where r.runtime_round_id = p_runtime_round_id and r.generator_version = 11 order by r.created_at desc limit 1 for no key update;
	if not found then raise exception 'multiplayer_round_not_registered'; end if;
	select * into v_member from public.multiplayer_v2_coin_round_members m where m.coin_round_id = v_round.coin_round_id and m.player_slot = p_player_slot for no key update;
	if not found or v_member.account_user_id is distinct from v_user then raise exception 'multiplayer_round_account_mismatch'; end if;
	select r.phase into v_phase from public.multiplayer_rooms r where r.room_id = v_round.room_id and r.lobby_generation = v_round.lobby_generation;
	if v_phase is not null and v_phase not in ('FINISHED', 'CLOSED') then raise exception 'multiplayer_round_not_terminal'; end if;
	select * into v_receipt from public.multiplayer_v2_achievement_receipts a where a.coin_round_id = v_round.coin_round_id and a.player_slot = p_player_slot for no key update;
	if not found or v_receipt.started_at is null then raise exception 'multiplayer_round_not_started'; end if;
	if v_receipt.completed_at is not null then
		if v_receipt.terminal_state <> p_terminal_state or v_receipt.distance_m <> p_distance_m or v_receipt.gravity_flips <> p_gravity_flips or v_receipt.hazards_seen is distinct from v_hazards then raise exception 'multiplayer_receipt_conflict'; end if;
		v_new := v_receipt.new_achievements;
	else
		update public.multiplayer_v2_achievement_receipts set completed_at = now(), terminal_state = p_terminal_state, distance_m = p_distance_m, gravity_flips = p_gravity_flips, hazards_seen = v_hazards where coin_round_id = v_round.coin_round_id and player_slot = p_player_slot;
		v_new := public._apply_achievement_progress_delta(v_user, p_distance_m::bigint, p_distance_m, 0, p_gravity_flips::bigint, v_hazards);
		update public.multiplayer_v2_achievement_receipts set new_achievements = v_new where coin_round_id = v_round.coin_round_id and player_slot = p_player_slot;
		v_inserted := true;
	end if;
	select jsonb_build_object('wallet_coins', coalesce(p.wallet_coins, 0), 'total_distance_m', coalesce(p.total_distance_m, 0), 'best_distance_m', coalesce(p.best_distance_m, 0)) into v_progress from public.player_progress p where p.user_id = v_user;
	if v_progress is null then v_progress := jsonb_build_object('wallet_coins', 0, 'total_distance_m', 0, 'best_distance_m', 0); end if;
	return jsonb_build_object('recorded', v_inserted, 'runtime_round_id', p_runtime_round_id, 'player_slot', p_player_slot, 'new_achievements', v_new, 'achievement_state', public.get_my_achievements(), 'progress', v_progress);
end $$;
revoke all on function public.record_my_multiplayer_v2_achievement_run(text,smallint,text,integer,integer,text[]) from public, anon;
grant execute on function public.record_my_multiplayer_v2_achievement_run(text,smallint,text,integer,integer,text[]) to authenticated;

create or replace function public.settle_my_pending_multiplayer_coin_awards()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account uuid := auth.uid(); v_member record; v_total integer := 0; v_balance bigint; v_previous integer; v_current integer; v_delta integer; v_settlements jsonb; v_new jsonb := '[]'::jsonb; v_progress jsonb;
begin
	if v_account is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	for v_member in select m.coin_round_id, m.network_user_id from public.multiplayer_v2_coin_round_members m where m.account_user_id = v_account order by m.coin_round_id, m.network_user_id loop
		perform 1 from public.multiplayer_v2_coin_round_members m where m.coin_round_id = v_member.coin_round_id and m.network_user_id = v_member.network_user_id for no key update;
		select coalesce(sum(a.value), 0)::integer into v_current from public.multiplayer_v2_coin_awards a where a.coin_round_id = v_member.coin_round_id and a.network_user_id = v_member.network_user_id and a.account_user_id = v_account;
		insert into public.multiplayer_v2_coin_settlements(coin_round_id, network_user_id, account_user_id, coins_earned) values (v_member.coin_round_id, v_member.network_user_id, v_account, 0) on conflict (coin_round_id, network_user_id) do nothing;
		select s.coins_earned into v_previous from public.multiplayer_v2_coin_settlements s where s.coin_round_id = v_member.coin_round_id and s.network_user_id = v_member.network_user_id for no key update;
		if v_current > v_previous then
			v_delta := v_current - v_previous;
			update public.multiplayer_v2_coin_settlements set coins_earned = v_current, settled_at = now() where coin_round_id = v_member.coin_round_id and network_user_id = v_member.network_user_id;
			insert into public.player_progress(user_id, wallet_coins) values(v_account, v_delta) on conflict(user_id) do update set wallet_coins = public.player_progress.wallet_coins + excluded.wallet_coins;
			v_total := v_total + v_delta;
		end if;
	end loop;
	if v_total > 0 then v_new := public._apply_achievement_progress_delta(v_account, 0, 0, v_total, 0, array[]::text[]); end if;
	select coalesce(p.wallet_coins, 0) into v_balance from public.player_progress p where p.user_id = v_account;
	select jsonb_build_object('wallet_coins', coalesce(p.wallet_coins, 0), 'total_distance_m', coalesce(p.total_distance_m, 0), 'best_distance_m', coalesce(p.best_distance_m, 0)) into v_progress from public.player_progress p where p.user_id = v_account;
	if v_progress is null then v_progress := jsonb_build_object('wallet_coins', 0, 'total_distance_m', 0, 'best_distance_m', 0); end if;
	select coalesce(jsonb_agg(jsonb_build_object('coin_round_id', s.coin_round_id, 'network_user_id', s.network_user_id, 'account_user_id', s.account_user_id, 'coins_earned', s.coins_earned, 'runtime_round_id', r.runtime_round_id, 'room_id', r.room_id, 'lobby_generation', r.lobby_generation) order by s.coin_round_id, s.network_user_id), '[]'::jsonb)
	into v_settlements from public.multiplayer_v2_coin_settlements s join public.multiplayer_v2_coin_rounds r using (coin_round_id)
	where s.account_user_id = v_account and s.coin_round_id in (select recent.coin_round_id from (select distinct sr.coin_round_id, max(rr.created_at) as created_at from public.multiplayer_v2_coin_settlements sr join public.multiplayer_v2_coin_rounds rr using (coin_round_id) where sr.account_user_id = v_account group by sr.coin_round_id order by max(rr.created_at) desc limit 32) recent);
	return jsonb_build_object('coins_credited', v_total, 'wallet_coins', coalesce(v_balance, 0), 'progress', v_progress, 'settlements', v_settlements, 'new_achievements', v_new, 'achievement_state', public.get_my_achievements());
end $$;
revoke all on function public.settle_my_pending_multiplayer_coin_awards() from public, anon;
grant execute on function public.settle_my_pending_multiplayer_coin_awards() to authenticated;

notify pgrst, 'reload schema';
