-- Local PostgreSQL regression for the Gen12 release gates and idempotent coin catalog.
-- All fixture rows are rolled back; run only against the disposable local test DB.
\set ON_ERROR_STOP on
begin;
\set account_id '76000000-0000-4000-8000-000000000001'

insert into auth.users(id) values (:'account_id') on conflict do nothing;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
 begin
  perform public.multiplayer_v2_create_room('Mixed', '2.1.20261005.8', 11::smallint, 76003::bigint, 45000, true);
  raise exception 'mixed API/generator tuple passed the create gate';
 exception when others then
  if sqlerrm = 'mixed API/generator tuple passed the create gate' then raise; end if;
  if sqlerrm not like '%version_mismatch%' then raise; end if;
 end;
end $$;
select public.multiplayer_v2_create_room('Gen12 current', '2.1.20261005.8', 12::smallint, 76004::bigint, 45000, true)->>'room_id' as room_id \gset
reset role;

update public.multiplayer_rooms
set phase = 'PREPARING_COURSE', manifest_hash = repeat('c', 64)
where room_id = :'room_id'::uuid;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.register_multiplayer_v2_coin_round(:'room_id'::uuid, 1, 'gen12-release-gate-round', repeat('c',64), '["coin_2_00001_0"]'::jsonb)->>'coin_round_id' as coin_round_id \gset
-- Assert through the RPC itself; authenticated callers intentionally cannot SELECT room rows.
select 1 / ((public.register_multiplayer_v2_coin_round(:'room_id'::uuid, 1, 'gen12-release-gate-round', repeat('c',64), '["coin_2_00001_0"]'::jsonb)->>'duplicate') = 'true')::integer;
reset role;
rollback;
\echo GENERATOR12_RELEASE_GATE_TEST PASS
