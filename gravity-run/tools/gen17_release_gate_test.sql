-- Local rollback-only contract test for API .13 / Gen17 and preserved Gen16 gates.
-- Execute only against a disposable local PostgreSQL clone with Supabase auth shims.
\set ON_ERROR_STOP on
begin;
\set account_id 17000000-0000-4000-8000-000000000017
\set runtime_round_id gen17-release-gate-round

insert into auth.users(id) values (:'account_id') on conflict do nothing;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
	begin
		perform public.multiplayer_v2_create_room('Wrong Gen17 gate', '2.1.20261006.12', 17::smallint, 870017, 45000, true);
		raise exception 'mixed Gen16 API/Gen17 generator tuple passed the gate';
	exception when others then
		if sqlerrm = 'mixed Gen16 API/Gen17 generator tuple passed the gate' then raise; end if;
		if sqlerrm not like '%version_mismatch%' then raise; end if;
	end;
end $$;
select public.multiplayer_v2_create_room('Gen17test', '2.1.20261006.13', 17::smallint, 870017, 45000, true)->>'room_id' as room_id \gset
select public.multiplayer_v2_create_room('Gen16test', '2.1.20261006.12', 16::smallint, 870016, 45000, true)->>'room_id' as gen16_room_id \gset
reset role;

update public.multiplayer_rooms set phase = 'PREPARING_COURSE', manifest_hash = repeat('a', 64) where room_id = :'room_id'::uuid;
insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
values (:'room_id'::uuid, 1, :'account_id', :'account_id');

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.register_multiplayer_v2_coin_round(
	:'room_id'::uuid, 1, :'runtime_round_id', repeat('a', 64), '["coin_1_00001_0"]'::jsonb
)->>'coin_round_id' as coin_round_id \gset
select (public.register_multiplayer_v2_coin_round(
	:'room_id'::uuid, 1, :'runtime_round_id', repeat('a', 64), '["coin_1_00001_0"]'::jsonb
)->>'duplicate')::boolean as duplicate_register \gset
select case when :'duplicate_register'::boolean then 'true' else 'false' end as register_retry_ok \gset
\if :register_retry_ok
\else
\echo Gen17 duplicate coin-round registration failed
\quit 1
\endif
reset role;

update public.multiplayer_rooms set phase = 'COUNTDOWN' where room_id = :'room_id'::uuid;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.start_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint)->>'started' as started \gset
select (public.start_my_multiplayer_v2_achievement_run(:'runtime_round_id', 1::smallint)->>'duplicate')::boolean as duplicate_receipt \gset
select case when :'started' = 'true' and :'duplicate_receipt'::boolean then 'true' else 'false' end as receipt_retry_ok \gset
\if :receipt_retry_ok
\else
\echo Gen17 authenticated achievement start receipt failed or did not retry idempotently
\quit 1
\endif
reset role;

select exists (select 1 from public.multiplayer_rooms where room_id = :'room_id'::uuid and game_version = '2.1.20261006.13' and generator_version = 17) as gen17_room_ok \gset
\if :gen17_room_ok
\else
\echo Gen17 room tuple was not retained
\quit 1
\endif
select exists (select 1 from public.multiplayer_rooms where room_id = :'gen16_room_id'::uuid and game_version = '2.1.20261006.12' and generator_version = 16) as gen16_room_ok \gset
\if :gen16_room_ok
\else
\echo Gen16 room tuple was not preserved
\quit 1
\endif
select exists (select 1 from public.multiplayer_v2_achievement_receipts a join public.multiplayer_v2_coin_rounds r using (coin_round_id) where r.runtime_round_id = :'runtime_round_id' and a.player_slot = 1 and a.started_at is not null) as receipt_persisted \gset
\if :receipt_persisted
\else
\echo Gen17 authenticated receipt was not recorded
\quit 1
\endif
rollback;
