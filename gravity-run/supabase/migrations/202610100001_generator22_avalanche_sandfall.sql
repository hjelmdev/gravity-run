-- Gen22 avalanches and sandfalls (rock clusters in frost and desert stretches)
-- use API .18. Gen21/.17 and older tuples remain supported; auth, wallet,
-- and receipt semantics are unchanged.
create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if not ((p_game_version = '2.1.20261003.7' and p_generator_version = 11) or (p_game_version = '2.1.20261005.8' and p_generator_version = 12) or (p_game_version = '2.1.20261005.9' and p_generator_version = 13) or (p_game_version = '2.1.20261005.10' and p_generator_version = 14) or (p_game_version = '2.1.20261005.11' and p_generator_version = 15) or (p_game_version = '2.1.20261006.12' and p_generator_version = 16) or (p_game_version = '2.1.20261006.13' and p_generator_version = 17) or (p_game_version = '2.1.20261007.14' and p_generator_version = 18) or (p_game_version = '2.1.20261007.15' and p_generator_version = 19) or (p_game_version = '2.1.20261007.16' and p_generator_version = 20) or (p_game_version = '2.1.20261008.17' and p_generator_version = 21) or (p_game_version = '2.1.20261010.18' and p_generator_version = 22)) then raise exception 'version_mismatch'; end if;
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
	if not ((v_room.generator_version = 11 and v_room.game_version = '2.1.20261003.7') or (v_room.generator_version = 12 and v_room.game_version = '2.1.20261005.8') or (v_room.generator_version = 13 and v_room.game_version = '2.1.20261005.9') or (v_room.generator_version = 14 and v_room.game_version = '2.1.20261005.10') or (v_room.generator_version = 15 and v_room.game_version = '2.1.20261005.11') or (v_room.generator_version = 16 and v_room.game_version = '2.1.20261006.12') or (v_room.generator_version = 17 and v_room.game_version = '2.1.20261006.13') or (v_room.generator_version = 18 and v_room.game_version = '2.1.20261007.14') or (v_room.generator_version = 19 and v_room.game_version = '2.1.20261007.15') or (v_room.generator_version = 20 and v_room.game_version = '2.1.20261007.16') or (v_room.generator_version = 21 and v_room.game_version = '2.1.20261008.17') or (v_room.generator_version = 22 and v_room.game_version = '2.1.20261010.18')) then raise exception 'coin_game_version_mismatch'; end if;
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

create or replace function public.start_my_multiplayer_v2_achievement_run(p_runtime_round_id text, p_player_slot smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_round public.multiplayer_v2_coin_rounds%rowtype; v_member public.multiplayer_v2_coin_round_members%rowtype; v_receipt public.multiplayer_v2_achievement_receipts%rowtype; v_phase text; v_inserted integer := 0;
begin
	if v_user is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	if p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 or p_player_slot is null or p_player_slot not between 1 and 5 then raise exception 'invalid_multiplayer_run'; end if;
	select * into v_round from public.multiplayer_v2_coin_rounds r where r.runtime_round_id = p_runtime_round_id and r.generator_version in (11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22) order by r.created_at desc limit 1 for no key update;
	if not found then raise exception 'multiplayer_round_not_registered'; end if;
	select * into v_member from public.multiplayer_v2_coin_round_members m where m.coin_round_id = v_round.coin_round_id and m.player_slot = p_player_slot for no key update;
	if not found or v_member.account_user_id is distinct from v_user then raise exception 'multiplayer_round_account_mismatch'; end if;
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
	if p_hazards is null or cardinality(p_hazards) > 12 or exists (select 1 from unnest(p_hazards) h where h not in ('spike_group','block','barrel_chain','floor_gap','ceiling_gap','terrain_step','terrain_slope','falling_rock','saw_blade','ghost','lava_crack','lava_volcano')) or cardinality(p_hazards) <> (select count(distinct h) from unnest(p_hazards) h) then raise exception 'invalid_hazard_catalog'; end if;
	v_hazards := coalesce(p_hazards, array[]::text[]);
	select * into v_round from public.multiplayer_v2_coin_rounds r where r.runtime_round_id = p_runtime_round_id and r.generator_version in (11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22) order by r.created_at desc limit 1 for no key update;
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

notify pgrst, 'reload schema';
