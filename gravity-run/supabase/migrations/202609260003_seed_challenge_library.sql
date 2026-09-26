-- Give shareable challenges a creator-chosen name and let signed-in players
-- keep a private, synchronized list of challenges they created or joined.
alter table public.seed_challenges
	add column if not exists challenge_name text not null default 'Untitled challenge',
	add column if not exists creator_user_id uuid references auth.users(id) on delete set null;

update public.seed_challenges
set challenge_name = left(creator_name || ' · ' || challenge_code, 40)
where btrim(challenge_name) = '' or challenge_name = 'Untitled challenge';

do $$
begin
	if not exists (
		select 1
		from pg_constraint
		where conrelid = 'public.seed_challenges'::regclass
			and conname = 'seed_challenges_challenge_name'
	) then
		alter table public.seed_challenges
			add constraint seed_challenges_challenge_name check (
				length(btrim(challenge_name)) between 1 and 40
				and octet_length(challenge_name) <= 160
			);
	end if;
end;
$$;

create table if not exists public.seed_challenge_library (
	user_id uuid not null references auth.users(id) on delete cascade,
	challenge_code text not null references public.seed_challenges(challenge_code) on delete cascade,
	added_at timestamptz not null default now(),
	hidden_at timestamptz,
	primary key (user_id, challenge_code)
);

create index if not exists seed_challenge_library_user_visible_idx
	on public.seed_challenge_library (user_id, added_at desc)
	where hidden_at is null;

alter table public.seed_challenge_library enable row level security;
revoke all on table public.seed_challenge_library from public, anon, authenticated;

-- Keep the existing creation RPC intact for older clients. The wrapper calls
-- it atomically, then stores the chosen title and authenticated creator id.
create or replace function public.create_named_seed_challenge(
	p_generator_version smallint,
	p_seed integer,
	p_ruleset_fingerprint text,
	p_ruleset jsonb,
	p_nickname text,
	p_challenge_name text
)
returns table (challenge_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
	new_code text;
	submitted_title text := btrim(coalesce(p_challenge_name, ''));
begin
	if length(submitted_title) not between 1 and 40 or octet_length(submitted_title) > 160 then
		raise exception 'invalid_challenge_name' using errcode = '22023';
	end if;

	select created.challenge_code into new_code
	from public.create_seed_challenge(
		p_generator_version,
		p_seed,
		p_ruleset_fingerprint,
		p_ruleset,
		p_nickname
	) as created;

	update public.seed_challenges as c
	set challenge_name = submitted_title,
		creator_user_id = (select auth.uid())
	where c.challenge_code = new_code;

	return query select new_code;
end;
$$;

create or replace function public.get_named_seed_challenge(p_challenge_code text)
returns table (
	challenge_code text,
	generator_version smallint,
	seed integer,
	ruleset_fingerprint text,
	ruleset jsonb,
	creator_name text,
	challenge_name text,
	created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
	select c.challenge_code, c.generator_version, c.seed,
		c.ruleset_fingerprint, c.ruleset, c.creator_name,
		c.challenge_name, c.created_at
	from public.seed_challenges as c
	where c.challenge_code = upper(btrim(p_challenge_code))
	limit 1;
$$;

create or replace function public.save_seed_challenge_to_library(p_challenge_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	code text := upper(btrim(coalesce(p_challenge_code, '')));
begin
	if current_user_id is null then
		raise exception 'authentication_required' using errcode = '28000';
	end if;
	if not exists (select 1 from public.seed_challenges as c where c.challenge_code = code) then
		raise exception 'challenge_not_found' using errcode = '22023';
	end if;

	insert into public.seed_challenge_library (user_id, challenge_code, hidden_at)
	values (current_user_id, code, null)
	on conflict (user_id, challenge_code) do update
	set hidden_at = null, added_at = now();
end;
$$;

create or replace function public.list_my_seed_challenges()
returns table (
	challenge_code text,
	challenge_name text,
	creator_name text,
	seed integer,
	generator_version smallint,
	ruleset jsonb,
	added_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
	select c.challenge_code, c.challenge_name, c.creator_name,
		c.seed, c.generator_version, c.ruleset, l.added_at
	from public.seed_challenge_library as l
	join public.seed_challenges as c on c.challenge_code = l.challenge_code
	where l.user_id = (select auth.uid()) and l.hidden_at is null
	order by l.added_at desc
	limit 100;
$$;

create or replace function public.hide_my_seed_challenge(p_challenge_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
	if (select auth.uid()) is null then
		raise exception 'authentication_required' using errcode = '28000';
	end if;
	update public.seed_challenge_library as l
	set hidden_at = now()
	where l.user_id = (select auth.uid())
		and l.challenge_code = upper(btrim(coalesce(p_challenge_code, '')));
end;
$$;

revoke all on function public.create_named_seed_challenge(smallint, integer, text, jsonb, text, text) from public;
revoke all on function public.get_named_seed_challenge(text) from public;
revoke all on function public.save_seed_challenge_to_library(text) from public;
revoke all on function public.list_my_seed_challenges() from public;
revoke all on function public.hide_my_seed_challenge(text) from public;

grant execute on function public.create_named_seed_challenge(smallint, integer, text, jsonb, text, text) to anon, authenticated;
grant execute on function public.get_named_seed_challenge(text) to anon, authenticated;
grant execute on function public.save_seed_challenge_to_library(text) to authenticated;
grant execute on function public.list_my_seed_challenges() to authenticated;
grant execute on function public.hide_my_seed_challenge(text) to authenticated;

notify pgrst, 'reload schema';
