-- Local PostgreSQL integration regression for the gen11 MP achievement RPCs.
-- Uses synthetic identities and rolls back every fixture.
\set ON_ERROR_STOP on
begin;
\set account_id '66000000-0000-4000-8000-000000000001'
\set network_id '66000000-0000-4000-8000-000000000002'
\set outsider_id '66000000-0000-4000-8000-000000000003'
\set room_id '66000000-0000-4000-8000-000000000004'
\set coin_round_id '66000000-0000-4000-8000-000000000005'

insert into auth.users(id) values (:'account_id'), (:'network_id'), (:'outsider_id') on conflict do nothing;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
 begin
  perform public.multiplayer_v2_create_room('Old client', '2.1.20261003.6', 10::smallint, 76000::bigint, 45000, true);
  raise exception 'old client version passed the gen11 gate';
 exception when others then
  if sqlerrm = 'old client version passed the gen11 gate' then raise; end if;
  if sqlerrm not like '%version_mismatch%' then raise; end if;
 end;
end $$;
do $$
declare room_payload jsonb;
begin
 room_payload := public.multiplayer_v2_create_room('Current client', '2.1.20261003.7', 11::smallint, 76002::bigint, 45000, true);
 if room_payload->>'room_id' is null then raise exception 'gen11 create room returned no room id'; end if;
end $$;
reset role;
insert into public.multiplayer_rooms(room_id, room_code, owner_user_id, phase, protocol_version, game_version, generator_version, max_players, seed, course_length_px, manifest_hash, signaling_topic, network_mode, v2_protocol_version, lobby_generation)
values (:'room_id', 'ACHPASS1', :'account_id', 'COUNTDOWN', 2, '2.1.20261003.7', 11, 5, 76001, 45000, repeat('a',64), 'achievement-test-topic', 'v2', 2, 1);
insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name, is_ready, loaded_manifest_hash)
values (:'room_id', :'network_id', 1, 'Host', true, repeat('a',64));
insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
values (:'room_id', 1, :'network_id', :'account_id');

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select (public.register_multiplayer_v2_coin_round(:'room_id'::uuid, 1, 'mp-achievement-test-round', repeat('a',64), '["coin_1_00001_0"]'::jsonb)->>'coin_round_id') as coin_round_id \gset
do $$
declare result jsonb;
begin
 result := public.register_multiplayer_v2_coin_round('66000000-0000-4000-8000-000000000004', 1, 'mp-achievement-test-round', repeat('a',64), '["coin_1_00001_0"]'::jsonb);
 if result->>'duplicate' <> 'true' then raise exception 'coin-round registration retry was not idempotent'; end if;
end $$;
reset role;
insert into public.multiplayer_v2_coin_awards(coin_round_id, entity_id, network_user_id, account_user_id, value)
values (:'coin_round_id', 'coin_1_00001_0', :'network_id', :'account_id', 1);
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
declare denied boolean := false;
begin
 begin
  execute 'select * from public.multiplayer_v2_achievement_receipts limit 1';
 exception when insufficient_privilege then denied := true;
 end;
 if not denied then raise exception 'authenticated role can read private achievement receipts'; end if;
end $$;
reset role;
update public.multiplayer_rooms set phase = 'PREPARING_COURSE' where room_id = :'room_id';
set role authenticated;
do $$
begin
 begin
  perform public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint);
  raise exception 'preparing round created an achievement receipt';
 exception when others then
  if sqlerrm = 'preparing round created an achievement receipt' then raise; end if;
  if sqlerrm not like '%multiplayer_round_not_started%' then raise; end if;
 end;
end $$;
reset role;
update public.multiplayer_rooms set phase = 'COUNTDOWN' where room_id = :'room_id';
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
declare first_result jsonb; retry_result jsonb;
begin
 first_result := public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint);
 retry_result := public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint);
 if first_result->>'duplicate' <> 'false' or retry_result->>'duplicate' <> 'true' then raise exception 'start receipt is not idempotent'; end if;
end $$;
reset role;
update public.multiplayer_rooms set phase = 'COUNTDOWN', lobby_generation = 2 where room_id = :'room_id';
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
declare retry_result jsonb;
begin
 retry_result := public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint);
 if retry_result->>'duplicate' <> 'true' then raise exception 'lost start ACK retry failed after room generation advanced'; end if;
end $$;
set local request.jwt.claims = '{"is_anonymous":true}';
do $$
begin
 begin
  perform public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint);
  raise exception 'anonymous account was accepted';
 exception when others then
  if sqlerrm = 'anonymous account was accepted' then raise; end if;
 end;
end $$;
set local request.jwt.claims = '{"is_anonymous":false}';
reset role;
update public.multiplayer_rooms set phase = 'FINISHED' where room_id = :'room_id';
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
declare first_result jsonb; retry_result jsonb;
begin
 first_result := public.record_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint, 'dead', 321, 7, array['ghost','spike_group']);
 retry_result := public.record_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint, 'dead', 321, 7, array['ghost','spike_group']);
 if first_result->>'recorded' <> 'true' or retry_result->>'recorded' <> 'false' then raise exception 'receipt idempotency failed'; end if;
 if (first_result->'achievement_state'->>'total_distance_m')::bigint <> 321 or (retry_result->'achievement_state'->>'total_distance_m')::bigint <> 321 then raise exception 'MP distance double counted'; end if;
 if (first_result->'progress'->>'total_distance_m')::bigint <> 321 or (first_result->'progress'->>'best_distance_m')::bigint <> 321 then raise exception 'MP distance did not update shared account progress'; end if;
 if (retry_result->'progress'->>'total_distance_m')::bigint <> 321 or (retry_result->'progress'->>'best_distance_m')::bigint <> 321 then raise exception 'MP metric retry changed shared progress'; end if;
 if (retry_result->'achievement_state'->>'total_gravity_flips')::bigint <> 7 then raise exception 'MP flip total missing or double counted'; end if;
 if retry_result->'achievement_state'->'hazard_stats'->>'ghost' <> '1' then raise exception 'MP hazard not recorded exactly once'; end if;
 begin
  perform public.start_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 2::smallint);
  raise exception 'unbound guest account was accepted';
 exception when others then
  if sqlerrm = 'unbound guest account was accepted' then raise; end if;
 end;
 begin
  perform public.record_my_multiplayer_v2_achievement_run('mp-achievement-test-round', 1::smallint, 'dead', 999, 7, array['ghost','spike_group']);
  raise exception 'conflicting receipt was accepted';
 exception when others then
  if sqlerrm = 'conflicting receipt was accepted' then raise; end if;
 end;
end $$;
do $$
declare first_result jsonb; retry_result jsonb;
begin
 first_result := public.settle_my_pending_multiplayer_coin_awards();
 retry_result := public.settle_my_pending_multiplayer_coin_awards();
 if (first_result->>'coins_credited')::integer <> 1 or (first_result->>'wallet_coins')::bigint <> 1 then raise exception 'first coin settlement was not credited exactly once'; end if;
 if (retry_result->>'coins_credited')::integer <> 0 or (retry_result->>'wallet_coins')::bigint <> 1 then raise exception 'coin settlement retry credited twice'; end if;
 if (retry_result->'achievement_state'->>'total_coins_earned')::bigint <> 1 then raise exception 'coin achievement delta missing or duplicated'; end if;
 if (retry_result->'progress'->>'total_distance_m')::bigint <> 321 or (retry_result->'progress'->>'best_distance_m')::bigint <> 321 or (retry_result->'progress'->>'wallet_coins')::bigint <> 1 then raise exception 'settlement progress response is inconsistent'; end if;
end $$;
reset role;
rollback;
\echo 'MULTIPLAYER_ACHIEVEMENT_RECEIPT_TEST PASS'
