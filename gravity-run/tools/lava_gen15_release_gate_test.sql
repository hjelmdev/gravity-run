-- Local PostgreSQL rollback regression for the Gen15/API .11 gate, coin
-- registration/journaling/settlement retries, and MP achievement receipt.
-- Run from the repo root against a disposable local schema/database only.
\set ON_ERROR_STOP on
begin;
\i supabase/migrations/202610050004_generator15_lava_fan.sql
\set account_id '87000000-0000-4000-8000-000000000015'
\set runtime_round_id 'gen15-lava-release-round'

insert into auth.users(id) values (:'account_id') on conflict do nothing;
insert into public.player_progress(user_id, wallet_coins, total_distance_m, best_distance_m)
values (:'account_id', 50, 10, 25)
on conflict (user_id) do update set wallet_coins = 50, total_distance_m = 10, best_distance_m = 25;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
	begin
		perform public.multiplayer_v2_create_room('Wrong Gen15 gate', '2.1.20261005.10', 15::smallint, 870015, 45000, true);
		raise exception 'mixed Gen14 API/Gen15 generator tuple passed the gate';
	exception when others then
		if sqlerrm = 'mixed Gen14 API/Gen15 generator tuple passed the gate' then raise; end if;
		if sqlerrm not like '%version_mismatch%' then raise; end if;
	end;
end $$;
select public.multiplayer_v2_create_room('Gen15 lava', '2.1.20261005.11', 15::smallint, 870015, 45000, true)->>'room_id' as room_id \gset
reset role;

update public.multiplayer_rooms
set phase = 'PREPARING_COURSE', manifest_hash = repeat('e', 64)
where room_id = :'room_id'::uuid;
insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
values (:'room_id'::uuid, 1, :'account_id', :'account_id');

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.register_multiplayer_v2_coin_round(
	:'room_id'::uuid, 1, :'runtime_round_id', repeat('e', 64),
	'["coin_1_12345_0", "coin_1_12345_1"]'::jsonb
)->>'coin_round_id' as coin_round_id \gset
select (public.register_multiplayer_v2_coin_round(
	:'room_id'::uuid, 1, :'runtime_round_id', repeat('e', 64),
	'["coin_1_12345_0", "coin_1_12345_1"]'::jsonb
)->>'duplicate')::boolean as duplicate_register \gset
select case when :'duplicate_register'::boolean then 'true' else 'false' end as register_retry_ok \gset
\if :register_retry_ok
\else
\echo GEN15 duplicate catalog registration failed
\quit 1
\endif
reset role;

update public.multiplayer_rooms set phase = 'COUNTDOWN' where room_id = :'room_id'::uuid;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.start_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint);
select (public.start_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint)->>'duplicate')::boolean as duplicate_start \gset
select case when :'duplicate_start'::boolean then 'true' else 'false' end as start_retry_ok \gset
\if :start_retry_ok
\else
\echo GEN15 achievement start receipt retry was not idempotent
\quit 1
\endif
reset role;
update public.multiplayer_rooms set phase = 'RUNNING' where room_id = :'room_id'::uuid;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.journal_multiplayer_v2_coin_awards(
	:'coin_round_id'::uuid, '[{"entity_id":"coin_1_12345_0","player_slot":1}]'::jsonb
);
select (public.settle_my_pending_multiplayer_coin_awards()->>'coins_credited')::integer as first_credit \gset
select case when :'first_credit'::integer = 1 then 'true' else 'false' end as first_credit_ok \gset
\if :first_credit_ok
\else
\echo GEN15 first coin settlement did not credit exactly once
\quit 1
\endif
reset role;
do $$
begin
	if (select wallet_coins from public.player_progress where user_id = '87000000-0000-4000-8000-000000000015') <> 51 then raise exception 'first Gen15 award wallet mismatch'; end if;
	if (select coins_earned from public.multiplayer_v2_coin_settlements where coin_round_id = (select coin_round_id from public.multiplayer_v2_coin_rounds where runtime_round_id = 'gen15-lava-release-round')) <> 1 then raise exception 'first Gen15 settlement receipt mismatch'; end if;
end $$;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.journal_multiplayer_v2_coin_awards(
	:'coin_round_id'::uuid, '[{"entity_id":"coin_1_12345_1","player_slot":1}]'::jsonb
);
select (public.settle_my_pending_multiplayer_coin_awards()->>'coins_credited')::integer as second_credit \gset
select case when :'second_credit'::integer = 1 then 'true' else 'false' end as second_credit_ok \gset
\if :second_credit_ok
\else
\echo GEN15 later coin batch was not credited incrementally
\quit 1
\endif
select (public.journal_multiplayer_v2_coin_awards(
	:'coin_round_id'::uuid, '[{"entity_id":"coin_1_12345_1","player_slot":1}]'::jsonb
)->>'journaled')::integer as duplicate_award_count \gset
select case when :'duplicate_award_count'::integer = 0 then 'true' else 'false' end as duplicate_award_ok \gset
\if :duplicate_award_ok
\else
\echo GEN15 duplicate award retry created another journal entry
\quit 1
\endif
select (public.settle_my_pending_multiplayer_coin_awards()->>'coins_credited')::integer as retry_credit \gset
select case when :'retry_credit'::integer = 0 then 'true' else 'false' end as retry_credit_ok \gset
\if :retry_credit_ok
\else
\echo GEN15 repeated settlement credited the same award twice
\quit 1
\endif
reset role;

update public.multiplayer_rooms set phase = 'FINISHED' where room_id = :'room_id'::uuid;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.record_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint, 'dead', 1234, 4, array['lava_crack','lava_volcano']);
select (public.record_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint, 'dead', 1234, 4, array['lava_crack','lava_volcano'])->>'recorded')::boolean as duplicate_record \gset
select case when not :'duplicate_record'::boolean then 'true' else 'false' end as achievement_retry_ok \gset
\if :achievement_retry_ok
\else
\echo Gen15 achievement receipt retry modified progress again
\quit 1
\endif
reset role;
do $$
begin
	if (select wallet_coins from public.player_progress where user_id = '87000000-0000-4000-8000-000000000015') <> 52 then raise exception 'coin wallet should contain exactly two Gen15 awards'; end if;
	if (select total_distance_m from public.player_progress where user_id = '87000000-0000-4000-8000-000000000015') <> 1244 then raise exception 'Gen15 achievement distance was not applied once'; end if;
	if (select best_distance_m from public.player_progress where user_id = '87000000-0000-4000-8000-000000000015') <> 1234 then raise exception 'Gen15 best-distance progress is missing'; end if;
	if (select count(*) from public.multiplayer_v2_coin_awards where coin_round_id = (select coin_round_id from public.multiplayer_v2_coin_rounds where runtime_round_id = 'gen15-lava-release-round')) <> 2 then raise exception 'Gen15 coin journal count is not exactly two'; end if;
	if (select count(*) from public.multiplayer_v2_achievement_receipts where coin_round_id = (select coin_round_id from public.multiplayer_v2_coin_rounds where runtime_round_id = 'gen15-lava-release-round') and completed_at is not null) <> 1 then raise exception 'Gen15 achievement receipt did not complete exactly once'; end if;
end $$;
reset role;
rollback;
\echo LAVA_GEN15_RELEASE_GATE_TEST PASS (migration and fixtures rolled back)
