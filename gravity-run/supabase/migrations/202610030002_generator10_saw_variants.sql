-- Generator 10 enables explicitly versioned embedded saw variants. Existing v9 rooms and coin rounds retain their original contract.
create or replace function public.register_multiplayer_v2_coin_round(
	p_room_id uuid, p_lobby_generation bigint, p_runtime_round_id text, p_manifest_hash text, p_coin_ids jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_round public.multiplayer_v2_coin_rounds%rowtype; v_ids text[]; v_round_id uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id and network_mode = 'v2' for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase not in ('PREPARING_COURSE', 'COUNTDOWN', 'RUNNING', 'FINISHED') or v_room.lobby_generation <> p_lobby_generation then raise exception 'coin_round_unavailable'; end if;
	if v_room.generator_version <> 10 or v_room.game_version <> '2.1.20261003.6' then raise exception 'coin_game_version_mismatch'; end if;
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

create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version <> '2.1.20261003.6' or p_generator_version <> 10 then raise exception 'version_mismatch'; end if;
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
