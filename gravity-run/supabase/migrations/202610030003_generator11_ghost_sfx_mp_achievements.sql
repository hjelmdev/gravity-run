-- Generator 11 adds a haunted ghost. Existing generator-10 rounds and
-- achievement receipts remain immutable and use API 2.1.20261003.7.

create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version <> '2.1.20261003.7' or p_generator_version <> 11 then raise exception 'version_mismatch'; end if;
	if p_seed not between 1 and 2147483647 then raise exception 'invalid_seed'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;
	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	loop v_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8)); exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_code); end loop;
	insert into public.multiplayer_rooms(room_id, room_code, owner_user_id, game_version, generator_version, seed, course_length_px, signaling_topic, is_public, max_players, network_mode, v2_protocol_version)
	values(v_room_id, v_code, auth.uid(), btrim(p_game_version), p_generator_version, p_seed, p_course_length_px, v_topic, coalesce(p_is_public, true), 5, 'v2', 2);
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name, returned_for_cycle)
	values(v_room_id, auth.uid(), 1, btrim(p_display_name), 1);
	return public._multiplayer_v2_room_payload(v_room_id);
end $$;

create or replace function public.register_multiplayer_v2_coin_round(
	p_room_id uuid, p_lobby_generation bigint, p_runtime_round_id text, p_manifest_hash text, p_coin_ids jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_round public.multiplayer_v2_coin_rounds%rowtype; v_ids text[]; v_round_id uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id and network_mode = 'v2' for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase not in ('PREPARING_COURSE', 'COUNTDOWN', 'RUNNING', 'FINISHED') or v_room.lobby_generation <> p_lobby_generation then raise exception 'coin_round_unavailable'; end if;
	if v_room.generator_version <> 11 or v_room.game_version <> '2.1.20261003.7' then raise exception 'coin_game_version_mismatch'; end if;
	if v_room.manifest_hash is null or p_manifest_hash <> v_room.manifest_hash or p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 then raise exception 'coin_manifest_mismatch'; end if;
	if p_coin_ids is null or jsonb_typeof(p_coin_ids) <> 'array' or jsonb_array_length(p_coin_ids) > 1600 then raise exception 'invalid_coin_catalog'; end if;
	if exists (select 1 from jsonb_array_elements(p_coin_ids) e(value) where jsonb_typeof(e.value) <> 'string' or (e.value #>> '{}') !~ '^coin_[1-9][0-9]?_[0-9]{5}_[0-3]$') then raise exception 'invalid_coin_catalog'; end if;
	select array_agg(e.value #>> '{}' order by e.ordinality) into v_ids from jsonb_array_elements(p_coin_ids) with ordinality e(value, ordinality);
	if cardinality(v_ids) <> (select count(distinct i) from unnest(v_ids) i) then raise exception 'duplicate_coin_id'; end if;
	select * into v_round from public.multiplayer_v2_coin_rounds cr where cr.room_id = p_room_id and cr.lobby_generation = p_lobby_generation for update;
	if found then
		if v_round.runtime_round_id <> p_runtime_round_id or v_round.manifest_hash <> p_manifest_hash then raise exception 'coin_round_mismatch'; end if;
		if (select array_agg(c.entity_id order by c.entity_id) from public.multiplayer_v2_coin_catalog c where c.coin_round_id = v_round.coin_round_id)
			is distinct from (select array_agg(i order by i) from unnest(v_ids) i) then raise exception 'coin_catalog_mismatch'; end if;
		return jsonb_build_object('coin_round_id', v_round.coin_round_id, 'duplicate', true);
	end if;
	insert into public.multiplayer_v2_coin_rounds(room_id, lobby_generation, runtime_round_id, manifest_hash, seed, generator_version, host_network_user_id)
	values (p_room_id, p_lobby_generation, p_runtime_round_id, p_manifest_hash, v_room.seed, v_room.generator_version, auth.uid()) returning coin_round_id into v_round_id;
	insert into public.multiplayer_v2_coin_round_members(coin_round_id, network_user_id, player_slot, account_user_id)
	select v_round_id, m.user_id, m.player_slot, l.account_user_id
	from public.multiplayer_room_members m
	left join public.multiplayer_v2_coin_account_links l on l.room_id = p_room_id and l.lobby_generation = p_lobby_generation and l.network_user_id = m.user_id
	where m.room_id = p_room_id;
	insert into public.multiplayer_v2_coin_catalog(coin_round_id, entity_id)
	select v_round_id, unnest(v_ids);
	return jsonb_build_object('coin_round_id', v_round_id, 'duplicate', false, 'coin_count', cardinality(v_ids));
end $$;

create table public.multiplayer_v2_achievement_receipts (
	coin_round_id uuid not null references public.multiplayer_v2_coin_rounds(coin_round_id) on delete cascade,
	player_slot smallint not null check (player_slot between 1 and 5),
	network_user_id uuid not null,
	account_user_id uuid not null references auth.users(id) on delete cascade,
	started_at timestamptz,
	completed_at timestamptz,
	terminal_state text,
	distance_m integer,
	gravity_flips integer,
	hazards_seen text[] not null default array[]::text[],
	new_achievements jsonb not null default '[]'::jsonb,
	primary key (coin_round_id, player_slot),
	unique (coin_round_id, network_user_id),
	foreign key (coin_round_id, network_user_id) references public.multiplayer_v2_coin_round_members(coin_round_id, network_user_id),
	check ((completed_at is null and terminal_state is null and distance_m is null and gravity_flips is null)
		or (completed_at is not null and terminal_state in ('dead', 'finished') and distance_m between 0 and 10000000 and gravity_flips between 0 and 100000))
);
create index multiplayer_v2_achievement_receipts_account_idx on public.multiplayer_v2_achievement_receipts(account_user_id, completed_at desc);
alter table public.multiplayer_v2_achievement_receipts enable row level security;
revoke all on table public.multiplayer_v2_achievement_receipts from public, anon, authenticated;

create or replace function public._apply_achievement_progress_delta(
	p_user_id uuid, p_distance_m bigint, p_best_distance_m integer, p_coin_delta bigint,
	p_gravity_flips bigint, p_hazards text[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unlocks jsonb := '[]'::jsonb; v_definition record; v_unlock record; v_value bigint; v_hazard text; v_total bigint; v_best integer; v_coins bigint; v_flips bigint;
begin
	if p_user_id is null or p_distance_m is null or p_distance_m < 0 or p_best_distance_m is null or p_best_distance_m < 0 or p_coin_delta is null or p_coin_delta < 0 or p_gravity_flips is null or p_gravity_flips < 0 then raise exception 'invalid_achievement_delta'; end if;
	if exists (select 1 from unnest(coalesce(p_hazards, array[]::text[])) h where h !~ '^[a-z0-9_]{1,40}$') then raise exception 'invalid_achievement_hazard'; end if;
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

create or replace function public.record_my_multiplayer_v2_achievement_run(
	p_runtime_round_id text, p_player_slot smallint, p_terminal_state text,
	p_distance_m integer, p_gravity_flips integer, p_hazards text[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_round public.multiplayer_v2_coin_rounds%rowtype; v_member public.multiplayer_v2_coin_round_members%rowtype; v_receipt public.multiplayer_v2_achievement_receipts%rowtype; v_phase text; v_hazards text[]; v_new jsonb := '[]'::jsonb; v_inserted boolean := false;
begin
	if v_user is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	if p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 or p_player_slot is null or p_player_slot not between 1 and 5 then raise exception 'invalid_multiplayer_run'; end if;
	if p_terminal_state not in ('dead', 'finished') then raise exception 'multiplayer_round_not_terminal'; end if;
	if p_distance_m is null or p_distance_m not between 0 and 10000000 or p_gravity_flips is null or p_gravity_flips not between 0 and 100000 then raise exception 'invalid_multiplayer_metrics'; end if;
	if p_hazards is null or cardinality(p_hazards) > 10 or exists (
		select 1 from unnest(p_hazards) h where h not in ('spike_group','block','barrel_chain','floor_gap','ceiling_gap','terrain_step','terrain_slope','falling_rock','saw_blade','ghost')
	) or cardinality(p_hazards) <> (select count(distinct h) from unnest(p_hazards) h) then raise exception 'invalid_hazard_catalog'; end if;
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
		update public.multiplayer_v2_achievement_receipts set completed_at = now(), terminal_state = p_terminal_state, distance_m = p_distance_m, gravity_flips = p_gravity_flips, hazards_seen = v_hazards
		where coin_round_id = v_round.coin_round_id and player_slot = p_player_slot;
		v_new := public._apply_achievement_progress_delta(v_user, p_distance_m::bigint, p_distance_m, 0, p_gravity_flips::bigint, v_hazards);
		update public.multiplayer_v2_achievement_receipts set new_achievements = v_new where coin_round_id = v_round.coin_round_id and player_slot = p_player_slot;
		v_inserted := true;
	end if;
	return jsonb_build_object('recorded', v_inserted, 'runtime_round_id', p_runtime_round_id, 'player_slot', p_player_slot, 'new_achievements', v_new, 'achievement_state', public.get_my_achievements());
end $$;

create or replace function public.settle_my_pending_multiplayer_coin_awards()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account uuid := auth.uid(); v_member record; v_total integer := 0; v_balance bigint; v_previous integer; v_current integer; v_delta integer; v_settlements jsonb; v_new jsonb := '[]'::jsonb;
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
	select coalesce(jsonb_agg(jsonb_build_object('coin_round_id', s.coin_round_id, 'network_user_id', s.network_user_id, 'account_user_id', s.account_user_id, 'coins_earned', s.coins_earned, 'runtime_round_id', r.runtime_round_id, 'room_id', r.room_id, 'lobby_generation', r.lobby_generation) order by s.coin_round_id, s.network_user_id), '[]'::jsonb)
	into v_settlements from public.multiplayer_v2_coin_settlements s join public.multiplayer_v2_coin_rounds r using (coin_round_id)
	where s.account_user_id = v_account and s.coin_round_id in (select recent.coin_round_id from (select distinct sr.coin_round_id, max(rr.created_at) as created_at from public.multiplayer_v2_coin_settlements sr join public.multiplayer_v2_coin_rounds rr using (coin_round_id) where sr.account_user_id = v_account group by sr.coin_round_id order by max(rr.created_at) desc limit 32) recent);
	return jsonb_build_object('coins_credited', v_total, 'wallet_coins', coalesce(v_balance, 0), 'settlements', v_settlements, 'new_achievements', v_new, 'achievement_state', public.get_my_achievements());
end $$;

revoke all on function public.start_my_multiplayer_v2_achievement_run(text,smallint) from public, anon;
revoke all on function public.record_my_multiplayer_v2_achievement_run(text,smallint,text,integer,integer,text[]) from public, anon;
grant execute on function public.start_my_multiplayer_v2_achievement_run(text,smallint) to authenticated;
grant execute on function public.record_my_multiplayer_v2_achievement_run(text,smallint,text,integer,integer,text[]) to authenticated;

notify pgrst, 'reload schema';
