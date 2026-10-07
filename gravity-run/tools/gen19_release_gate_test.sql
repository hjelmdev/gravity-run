-- Local rollback-only contract test for API .14/Gen18 and API .15/Gen19.
-- Exercises room creation, coin-round registration and achievement receipts
-- under authenticated role. Run only on the disposable local Supabase-shim DB.
\set ON_ERROR_STOP on
begin;
\i supabase/migrations/202610070001_generator19_ghost_pursuit.sql
\set account_id '19000000-0000-4000-8000-000000000019'
\set runtime19 'gen19-release-gate-round'
\set runtime18 'gen18-release-gate-round'

insert into auth.users(id) values (:'account_id') on conflict do nothing;
insert into public.player_progress(user_id, wallet_coins, total_distance_m, best_distance_m)
values (:'account_id', 7, 10, 25)
on conflict (user_id) do update set wallet_coins = 7, total_distance_m = 10, best_distance_m = 25;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
do $$
begin
	begin
		perform public.multiplayer_v2_create_room('Bad19', '2.1.20261007.14', 19::smallint, 910019, 45000, true);
		raise exception 'Gen18 API with Gen19 generator unexpectedly passed';
	exception when others then
		if sqlerrm = 'Gen18 API with Gen19 generator unexpectedly passed' then raise; end if;
		if sqlerrm not like '%version_mismatch%' then raise; end if;
	end;
	begin
		perform public.multiplayer_v2_create_room('Bad18', '2.1.20261007.15', 18::smallint, 910018, 45000, true);
		raise exception 'Gen19 API with Gen18 generator unexpectedly passed';
	exception when others then
		if sqlerrm = 'Gen19 API with Gen18 generator unexpectedly passed' then raise; end if;
		if sqlerrm not like '%version_mismatch%' then raise; end if;
	end;
end $$;
select public.multiplayer_v2_create_room('Gen19 current', '2.1.20261007.15', 19::smallint, 910019, 45000, true)->>'room_id' as room19_id \gset
select public.multiplayer_v2_create_room('Gen18 legacy', '2.1.20261007.14', 18::smallint, 910018, 45000, true)->>'room_id' as room18_id \gset
select public.multiplayer_v2_create_room('Gen17 legacy', '2.1.20261006.13', 17::smallint, 910017, 45000, true)->>'room_id' as room17_id \gset
reset role;

update public.multiplayer_rooms set phase = 'PREPARING_COURSE', manifest_hash = repeat('9', 64)
where room_id in (:'room19_id'::uuid, :'room18_id'::uuid);
insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
select room_id, lobby_generation, :'account_id', :'account_id' from public.multiplayer_rooms
where room_id in (:'room19_id'::uuid, :'room18_id'::uuid);
create function pg_temp.gen19_bad_coin_gate(p_room_id uuid) returns boolean language plpgsql as $$
begin
	perform public.register_multiplayer_v2_coin_round(p_room_id, 1, 'wrong-pair', repeat('9', 64), '[]'::jsonb);
	return false;
exception when others then
	return sqlerrm = 'coin_game_version_mismatch';
end $$;

update public.multiplayer_rooms set game_version = '2.1.20261007.14' where room_id = :'room19_id'::uuid;
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select pg_temp.gen19_bad_coin_gate(:'room19_id'::uuid) as bad_coin_pair_rejected \gset
\if :bad_coin_pair_rejected
\else
\echo Coin registration accepted a mismatched Gen19 tuple
\quit 1
\endif
reset role;
update public.multiplayer_rooms set game_version = '2.1.20261007.15' where room_id = :'room19_id'::uuid;

set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.register_multiplayer_v2_coin_round(:'room19_id'::uuid, 1, :'runtime19', repeat('9', 64), '["coin_1_00019_0"]'::jsonb)->>'coin_round_id' as coin_round19_id \gset
select (public.register_multiplayer_v2_coin_round(:'room19_id'::uuid, 1, :'runtime19', repeat('9', 64), '["coin_1_00019_0"]'::jsonb)->>'duplicate')::boolean as duplicate19 \gset
select public.register_multiplayer_v2_coin_round(:'room18_id'::uuid, 1, :'runtime18', repeat('9', 64), '["coin_1_00018_0"]'::jsonb)->>'coin_round_id' as coin_round18_id \gset
select (public.register_multiplayer_v2_coin_round(:'room18_id'::uuid, 1, :'runtime18', repeat('9', 64), '["coin_1_00018_0"]'::jsonb)->>'duplicate')::boolean as duplicate18 \gset
select case when :'duplicate19'::boolean and :'duplicate18'::boolean then 'true' else 'false' end as duplicate_registration_ok \gset
\if :duplicate_registration_ok
\else
\echo Gen18/Gen19 coin-round registration retry was not idempotent
\quit 1
\endif
reset role;

update public.multiplayer_rooms set phase = 'COUNTDOWN' where room_id in (:'room19_id'::uuid, :'room18_id'::uuid);
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.start_my_multiplayer_v2_achievement_run(:'runtime19', 1::smallint);
select public.start_my_multiplayer_v2_achievement_run(:'runtime18', 1::smallint);
select (public.start_my_multiplayer_v2_achievement_run(:'runtime19', 1::smallint)->>'duplicate')::boolean as duplicate_start19 \gset
select (public.start_my_multiplayer_v2_achievement_run(:'runtime18', 1::smallint)->>'duplicate')::boolean as duplicate_start18 \gset
select case when :'duplicate_start19'::boolean and :'duplicate_start18'::boolean then 'true' else 'false' end as duplicate_start_ok \gset
\if :duplicate_start_ok
\else
\echo Gen18/Gen19 achievement start receipt retry was not idempotent
\quit 1
\endif
reset role;

update public.multiplayer_rooms set phase = 'FINISHED' where room_id in (:'room19_id'::uuid, :'room18_id'::uuid);
set role authenticated;
set local request.jwt.claim.sub = :'account_id';
set local request.jwt.claims = '{"is_anonymous":false}';
select public.record_my_multiplayer_v2_achievement_run(:'runtime19', 1::smallint, 'dead', 1234, 4, array['ghost']);
select (public.record_my_multiplayer_v2_achievement_run(:'runtime19', 1::smallint, 'dead', 1234, 4, array['ghost'])->>'recorded')::boolean as duplicate_record \gset
select case when not :'duplicate_record'::boolean then 'true' else 'false' end as duplicate_record_ok \gset
\if :duplicate_record_ok
\else
\echo Gen19 achievement receipt retry applied progress twice
\quit 1
\endif
reset role;

select exists (select 1 from public.multiplayer_rooms where room_id = :'room17_id'::uuid and game_version = '2.1.20261006.13' and generator_version = 17) as gen17_preserved \gset
\if :gen17_preserved
\else
\echo Gen17 create-room tuple was not preserved
\quit 1
\endif
select exists (select 1 from public.multiplayer_v2_achievement_receipts r join public.multiplayer_v2_coin_rounds c using (coin_round_id) where c.runtime_round_id = :'runtime19' and r.started_at is not null and r.completed_at is not null) as gen19_receipt_saved \gset
\if :gen19_receipt_saved
\else
\echo Gen19 achievement receipt was not recorded
\quit 1
\endif
select case when (select wallet_coins from public.player_progress where user_id = :'account_id') = 7 and (select total_distance_m from public.player_progress where user_id = :'account_id') = 1244 then 'true' else 'false' end as progress_ok \gset
\if :progress_ok
\else
\echo Version-gate migration changed wallet or applied Gen19 distance more than once
\quit 1
\endif
rollback;
\echo GEN19_RELEASE_GATE_TEST PASS (migration and fixtures rolled back)
