create table if not exists public.player_progress (
	user_id uuid primary key references auth.users (id) on delete cascade,
	wallet_coins bigint not null default 0,
	total_distance_m bigint not null default 0,
	best_distance_m integer not null default 0,
	updated_at timestamptz not null default now(),
	constraint player_progress_wallet_range check (wallet_coins between 0 and 1000000000000),
	constraint player_progress_total_distance_range check (total_distance_m between 0 and 1000000000000000),
	constraint player_progress_best_distance_range check (best_distance_m between 0 and 10000000)
);

alter table public.player_progress enable row level security;
revoke all on table public.player_progress from public, anon, authenticated;

create table if not exists public.player_run_history (
	user_id uuid not null references auth.users (id) on delete cascade,
	run_id uuid not null,
	distance_m integer not null,
	coins_earned integer not null,
	created_at timestamptz not null default now(),
	primary key (user_id, run_id),
	constraint player_run_distance_range check (distance_m between 0 and 10000000),
	constraint player_run_coins_range check (coins_earned between 0 and 1000000)
);

alter table public.player_run_history enable row level security;
revoke all on table public.player_run_history from public, anon, authenticated;

create or replace function public.get_my_account_progress()
returns jsonb
language sql
security definer
set search_path = ''
as $$
	select jsonb_build_object(
		'wallet_coins', coalesce(p.wallet_coins, 0),
		'total_distance_m', coalesce(p.total_distance_m, 0),
		'best_distance_m', coalesce(p.best_distance_m, 0)
	)
	from (select (select auth.uid()) as user_id) as auth_context
	left join public.player_progress as p on p.user_id = auth_context.user_id;
$$;

create or replace function public.record_player_run(
	p_run_id uuid,
	p_distance_m integer,
	p_coins_earned integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	inserted_rows integer := 0;
	result jsonb;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if p_run_id is null then
		raise exception 'invalid_run_id' using errcode = '22023';
	end if;
	if p_distance_m is null or p_distance_m not between 0 and 10000000 then
		raise exception 'invalid_distance' using errcode = '22023';
	end if;
	if p_coins_earned is null or p_coins_earned not between 0 and 1000000 then
		raise exception 'invalid_coin_reward' using errcode = '22023';
	end if;

	insert into public.player_run_history (user_id, run_id, distance_m, coins_earned)
	values (current_user_id, p_run_id, p_distance_m, p_coins_earned)
	on conflict (user_id, run_id) do nothing;
	get diagnostics inserted_rows = row_count;

	if inserted_rows = 1 then
		insert into public.player_progress (user_id, wallet_coins, total_distance_m, best_distance_m)
		values (current_user_id, p_coins_earned, p_distance_m, p_distance_m)
		on conflict (user_id) do update set
			wallet_coins = public.player_progress.wallet_coins + excluded.wallet_coins,
			total_distance_m = public.player_progress.total_distance_m + excluded.total_distance_m,
			best_distance_m = greatest(public.player_progress.best_distance_m, excluded.best_distance_m),
			updated_at = now();
	end if;

	select jsonb_build_object(
		'wallet_coins', p.wallet_coins,
		'total_distance_m', p.total_distance_m,
		'best_distance_m', p.best_distance_m,
		'run_recorded', inserted_rows = 1
	) into result
	from public.player_progress as p
	where p.user_id = current_user_id;

	return coalesce(result, jsonb_build_object(
		'wallet_coins', 0,
		'total_distance_m', 0,
		'best_distance_m', 0,
		'run_recorded', false
	));
end;
$$;

create or replace function public.get_total_distance_leaderboard(p_limit integer default 20)
returns table(player_name text, total_distance_m bigint)
language sql
stable
security definer
set search_path = ''
as $$
	select profile.nickname, progress.total_distance_m
	from public.player_progress as progress
	join public.player_profiles as profile on profile.user_id = progress.user_id
	where progress.total_distance_m > 0
	order by progress.total_distance_m desc, progress.user_id asc
	limit greatest(1, least(coalesce(p_limit, 20), 20));
$$;

revoke all on function public.get_my_account_progress() from public, anon;
revoke all on function public.record_player_run(uuid, integer, integer) from public, anon;
revoke all on function public.get_total_distance_leaderboard(integer) from public;
grant execute on function public.get_my_account_progress() to authenticated;
grant execute on function public.record_player_run(uuid, integer, integer) to authenticated;
grant execute on function public.get_total_distance_leaderboard(integer) to anon, authenticated;
