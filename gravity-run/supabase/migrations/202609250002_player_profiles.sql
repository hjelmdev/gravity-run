create table if not exists public.player_profiles (
	user_id uuid primary key references auth.users (id) on delete cascade,
	nickname text not null,
	nickname_normalized text generated always as (lower(nickname)) stored,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	constraint player_profile_nickname_length check (char_length(nickname) between 3 and 16),
	constraint player_profile_nickname_format check (nickname ~ '^[A-Za-z0-9_]+$'),
	constraint player_profile_nickname_unique unique (nickname_normalized)
);

alter table public.player_profiles enable row level security;
revoke all on table public.player_profiles from anon, authenticated;
grant select on table public.player_profiles to authenticated;

drop policy if exists "Players can read their own profile" on public.player_profiles;
create policy "Players can read their own profile"
	on public.player_profiles for select to authenticated
	using ((select auth.uid()) = user_id);

create or replace function public.get_my_player_profile()
returns jsonb
language sql
security definer
set search_path = ''
as $$
	select jsonb_build_object('nickname', p.nickname)
	from public.player_profiles as p
	where p.user_id = (select auth.uid());
$$;

create or replace function public.is_player_nickname_available(p_nickname text)
returns boolean
language sql
security definer
set search_path = ''
as $$
	select case
		when p_nickname is null or p_nickname !~ '^[A-Za-z0-9_]{3,16}$' then false
		else not exists (
			select 1 from public.player_profiles as p
			where p.nickname_normalized = lower(p_nickname)
			and p.user_id <> (select auth.uid())
		)
	end;
$$;

create or replace function public.set_my_player_nickname(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if p_nickname is null or p_nickname !~ '^[A-Za-z0-9_]{3,16}$' then
		raise exception 'invalid_nickname' using errcode = '22023';
	end if;
	insert into public.player_profiles (user_id, nickname)
	values (current_user_id, p_nickname)
	on conflict (user_id) do update
		set nickname = excluded.nickname, updated_at = now();
	return jsonb_build_object('nickname', p_nickname);
exception
	when unique_violation then
		raise exception 'nickname_taken' using errcode = '23505';
end;
$$;

revoke all on function public.get_my_player_profile() from public, anon;
revoke all on function public.is_player_nickname_available(text) from public, anon;
revoke all on function public.set_my_player_nickname(text) from public, anon;
grant execute on function public.get_my_player_profile() to authenticated;
grant execute on function public.is_player_nickname_available(text) to authenticated;
grant execute on function public.set_my_player_nickname(text) to authenticated;
