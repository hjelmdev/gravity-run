create table if not exists public.leaderboard_runs (
	id bigint generated always as identity primary key,
	player_name text not null,
	distance_m integer not null,
	coins integer not null,
	created_at timestamptz not null default now(),
	constraint leaderboard_player_name_length check (char_length(btrim(player_name)) between 1 and 16),
	constraint leaderboard_player_name_no_control_chars check (player_name !~ '[[:cntrl:]]'),
	constraint leaderboard_distance_range check (distance_m between 0 and 10000000),
	constraint leaderboard_coins_range check (coins between 0 and 1000000)
);

alter table public.leaderboard_runs enable row level security;

revoke all on table public.leaderboard_runs from anon, authenticated;
grant select on table public.leaderboard_runs to anon, authenticated;
grant insert (player_name, distance_m, coins) on table public.leaderboard_runs to anon, authenticated;

drop policy if exists "Leaderboard entries are publicly readable" on public.leaderboard_runs;
create policy "Leaderboard entries are publicly readable"
	on public.leaderboard_runs
	for select
	to anon, authenticated
	using (true);

drop policy if exists "Players can submit leaderboard entries" on public.leaderboard_runs;
create policy "Players can submit leaderboard entries"
	on public.leaderboard_runs
	for insert
	to anon, authenticated
	with check (
		char_length(btrim(player_name)) between 1 and 16
		and player_name !~ '[[:cntrl:]]'
		and distance_m between 0 and 10000000
		and coins between 0 and 1000000
	);
