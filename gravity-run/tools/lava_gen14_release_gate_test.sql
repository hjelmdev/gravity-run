-- Local PostgreSQL regression for the Gen14/API .10 gate and lava achievement IDs.
-- Run only in the disposable local PostgreSQL clone; the transaction rolls back all fixtures.
\set ON_ERROR_STOP on
begin;
\set account_id '87000000-0000-4000-8000-000000000001'
\set network_id '87000000-0000-4000-8000-000000000002'

insert into auth.users(id) values (:'account_id') on conflict do nothing;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
 begin
  perform public.multiplayer_v2_create_room('Mixed', '2.1.20261005.9', 14::smallint, 870001::bigint, 45000, true);
  raise exception 'mixed API/generator tuple passed the Gen14 gate';
 exception when others then
  if sqlerrm = 'mixed API/generator tuple passed the Gen14 gate' then raise; end if;
  if sqlerrm not like '%version_mismatch%' then raise; end if;
 end;
end $$;
select public.multiplayer_v2_create_room('Legacy Gen13', '2.1.20261005.9', 13::smallint, 870013::bigint, 45000, true)->>'room_id' as legacy_room_id \gset
select public.multiplayer_v2_create_room('Gen14 lava', '2.1.20261005.10', 14::smallint, 870014::bigint, 45000, true)->>'room_id' as room_id \gset
reset role;

update public.multiplayer_rooms
set phase = 'PREPARING_COURSE', manifest_hash = repeat('d', 64)
where room_id = :'room_id'::uuid;
insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
values (:'room_id'::uuid, 1, :'account_id', :'account_id');

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select (public.register_multiplayer_v2_coin_round(:'room_id'::uuid, 1, 'gen14-lava-release-round', repeat('d',64), '[]'::jsonb)->>'coin_round_id') as coin_round_id \gset
reset role;
update public.multiplayer_rooms set phase = 'COUNTDOWN' where room_id = :'room_id'::uuid;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.start_my_multiplayer_v2_achievement_run('gen14-lava-release-round', 1::smallint);
reset role;
update public.multiplayer_rooms set phase = 'FINISHED' where room_id = :'room_id'::uuid;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
declare first_result jsonb; retry_result jsonb;
begin
 first_result := public.record_my_multiplayer_v2_achievement_run('gen14-lava-release-round', 1::smallint, 'dead', 1234, 4, array['lava_crack','lava_volcano']);
 retry_result := public.record_my_multiplayer_v2_achievement_run('gen14-lava-release-round', 1::smallint, 'dead', 1234, 4, array['lava_crack','lava_volcano']);
 if first_result->>'recorded' <> 'true' or retry_result->>'recorded' <> 'false' then raise exception 'Gen14 lava receipt is not idempotent'; end if;
 if (retry_result->'achievement_state'->>'total_distance_m')::bigint <> 1234 then raise exception 'Gen14 receipt distance missing'; end if;
 if retry_result->'achievement_state'->'hazard_stats'->>'lava_crack' <> '1' or retry_result->'achievement_state'->'hazard_stats'->>'lava_volcano' <> '1' then raise exception 'Gen14 lava hazard IDs were not accepted exactly once'; end if;
 if (retry_result->'progress'->>'wallet_coins')::bigint <> 0 then raise exception 'achievement receipt modified the wallet'; end if;
end $$;
reset role;
rollback;
\echo LAVA_GEN14_RELEASE_GATE_TEST PASS
