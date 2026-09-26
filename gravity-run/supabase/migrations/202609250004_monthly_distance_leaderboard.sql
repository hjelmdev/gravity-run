create index if not exists player_run_history_created_at_user_id_idx
	on public.player_run_history (created_at, user_id);

create or replace function public.get_monthly_distance_leaderboard(p_limit integer default 20)
returns table(player_name text, monthly_distance_m bigint)
language sql
stable
security definer
set search_path = ''
as $$
	select profile.nickname, sum(history.distance_m)::bigint as monthly_distance_m
	from public.player_run_history as history
	join public.player_profiles as profile on profile.user_id = history.user_id
	where history.created_at >= date_trunc('month', now() at time zone 'Europe/Stockholm') at time zone 'Europe/Stockholm'
		and history.created_at < (date_trunc('month', now() at time zone 'Europe/Stockholm') + interval '1 month') at time zone 'Europe/Stockholm'
	group by history.user_id, profile.nickname
	order by monthly_distance_m desc, history.user_id asc
	limit greatest(1, least(coalesce(p_limit, 20), 20));
$$;

revoke all on function public.get_monthly_distance_leaderboard(integer) from public;
grant execute on function public.get_monthly_distance_leaderboard(integer) to anon, authenticated;
