-- Shared V2 coins: immutable member/account snapshots and exactly-once wallet settlement.
-- Network identities remain separate from signed-in account identities.

create table if not exists public.multiplayer_v2_coin_account_links (
	room_id uuid not null,
	lobby_generation bigint not null check (lobby_generation > 0),
	network_user_id uuid not null,
	account_user_id uuid,
	created_at timestamptz not null default now(),
	primary key (room_id, lobby_generation, network_user_id)
);
-- Multiple browser identities may intentionally bind to one signed-in account.
alter table public.multiplayer_v2_coin_account_links drop constraint if exists multiplayer_v2_coin_account_links_room_id_lobby_generation_account_user_id_key;
alter table public.multiplayer_v2_coin_account_links drop constraint if exists multiplayer_v2_coin_account_l_room_id_lobby_generation_acco_key;

create table if not exists public.multiplayer_v2_coin_link_challenges (
	challenge_id uuid primary key default gen_random_uuid(),
	room_id uuid not null,
	lobby_generation bigint not null check (lobby_generation > 0),
	network_user_id uuid not null,
	nonce_hash bytea not null,
	expires_at timestamptz not null default now() + interval '5 minutes',
	consumed_at timestamptz,
	created_at timestamptz not null default now()
);

create table if not exists public.multiplayer_v2_coin_rounds (
	coin_round_id uuid primary key default gen_random_uuid(),
	room_id uuid not null,
	lobby_generation bigint not null check (lobby_generation > 0),
	runtime_round_id text not null check (char_length(runtime_round_id) between 1 and 64),
	manifest_hash text not null check (manifest_hash ~ '^[0-9a-f]{64}$'),
	seed bigint not null,
	generator_version smallint not null,
	host_network_user_id uuid not null,
	created_at timestamptz not null default now(),
	unique (room_id, lobby_generation)
);

create table if not exists public.multiplayer_v2_coin_round_members (
	coin_round_id uuid not null references public.multiplayer_v2_coin_rounds(coin_round_id) on delete cascade,
	network_user_id uuid not null,
	player_slot smallint not null check (player_slot between 1 and 5),
	account_user_id uuid,
	primary key (coin_round_id, network_user_id),
	unique (coin_round_id, player_slot)
);

create table if not exists public.multiplayer_v2_coin_catalog (
	coin_round_id uuid not null references public.multiplayer_v2_coin_rounds(coin_round_id) on delete cascade,
	entity_id text not null check (entity_id ~ '^coin_[1-9][0-9]?_[0-9]{5}_[0-3]$'),
	value smallint not null default 1 check (value = 1),
	primary key (coin_round_id, entity_id)
);

create table if not exists public.multiplayer_v2_coin_awards (
	coin_round_id uuid not null references public.multiplayer_v2_coin_rounds(coin_round_id) on delete cascade,
	entity_id text not null,
	network_user_id uuid not null,
	account_user_id uuid,
	value smallint not null check (value = 1),
	created_at timestamptz not null default now(),
	primary key (coin_round_id, entity_id),
	foreign key (coin_round_id, entity_id) references public.multiplayer_v2_coin_catalog(coin_round_id, entity_id),
	foreign key (coin_round_id, network_user_id) references public.multiplayer_v2_coin_round_members(coin_round_id, network_user_id)
);

create table if not exists public.multiplayer_v2_coin_settlements (
	coin_round_id uuid not null references public.multiplayer_v2_coin_rounds(coin_round_id) on delete cascade,
	network_user_id uuid not null,
	account_user_id uuid not null,
	coins_earned integer not null default 0 check (coins_earned >= 0),
	settled_at timestamptz not null default now(),
	primary key (coin_round_id, network_user_id),
	foreign key (coin_round_id, network_user_id) references public.multiplayer_v2_coin_round_members(coin_round_id, network_user_id)
);
alter table public.multiplayer_v2_coin_settlements alter column coins_earned set default 0;
alter table public.multiplayer_v2_coin_settlements drop constraint if exists multiplayer_v2_coin_settlements_coins_earned_check;
alter table public.multiplayer_v2_coin_settlements add constraint multiplayer_v2_coin_settlements_coins_earned_check check (coins_earned >= 0);

alter table public.multiplayer_v2_coin_account_links enable row level security;
alter table public.multiplayer_v2_coin_link_challenges enable row level security;
alter table public.multiplayer_v2_coin_rounds enable row level security;
alter table public.multiplayer_v2_coin_round_members enable row level security;
alter table public.multiplayer_v2_coin_catalog enable row level security;
alter table public.multiplayer_v2_coin_awards enable row level security;
alter table public.multiplayer_v2_coin_settlements enable row level security;
revoke all on table public.multiplayer_v2_coin_account_links, public.multiplayer_v2_coin_link_challenges,
	public.multiplayer_v2_coin_rounds, public.multiplayer_v2_coin_round_members,
	public.multiplayer_v2_coin_catalog, public.multiplayer_v2_coin_awards,
	public.multiplayer_v2_coin_settlements from public, anon, authenticated;

create or replace function public.request_multiplayer_v2_coin_account_link(p_room_id uuid, p_lobby_generation bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_challenge uuid; v_nonce text;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true then raise exception 'network_identity_required'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id and network_mode = 'v2' for update;
	if not found or v_room.lobby_generation <> p_lobby_generation or v_room.phase not in ('PREPARING_COURSE', 'COUNTDOWN') then raise exception 'coin_link_round_unavailable'; end if;
	if not exists (select 1 from public.multiplayer_room_members m where m.room_id = p_room_id and m.user_id = auth.uid()) then raise exception 'not_room_member'; end if;
	if exists (select 1 from public.multiplayer_v2_coin_rounds cr where cr.room_id = p_room_id and cr.lobby_generation = p_lobby_generation) then raise exception 'coin_account_binding_frozen'; end if;
	-- The anonymous network identity cannot tell which signed-in account owns an
	-- earlier link. Always require a fresh nonce; resolve enforces same-account
	-- idempotency and rejects a different account.
	v_nonce := encode(extensions.gen_random_bytes(32), 'hex');
	insert into public.multiplayer_v2_coin_link_challenges(room_id, lobby_generation, network_user_id, nonce_hash)
	values (p_room_id, p_lobby_generation, auth.uid(), extensions.digest(convert_to(v_nonce, 'UTF8'), 'sha256'))
	returning challenge_id into v_challenge;
	return jsonb_build_object('bound', false, 'challenge_id', v_challenge, 'nonce', v_nonce, 'expires_in_seconds', 300);
end $$;

create or replace function public.resolve_multiplayer_v2_coin_account_link(p_challenge_id uuid, p_nonce text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_challenge public.multiplayer_v2_coin_link_challenges%rowtype; v_account uuid := auth.uid(); v_existing uuid;
begin
	if v_account is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	select * into v_challenge from public.multiplayer_v2_coin_link_challenges where challenge_id = p_challenge_id for update;
	if not found or v_challenge.expires_at <= now() or v_challenge.consumed_at is not null then raise exception 'coin_link_challenge_expired_or_used'; end if;
	-- Serialize redemption with snapshot freeze and room cleanup.
	perform 1 from public.multiplayer_rooms r where r.room_id = v_challenge.room_id
		and r.network_mode = 'v2' and r.lobby_generation = v_challenge.lobby_generation
		and r.phase in ('PREPARING_COURSE', 'COUNTDOWN') for update;
	if not found or not exists (select 1 from public.multiplayer_room_members m where m.room_id = v_challenge.room_id and m.user_id = v_challenge.network_user_id) then
		raise exception 'coin_link_round_unavailable';
	end if;
	if p_nonce is null or char_length(p_nonce) <> 64 or extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256') <> v_challenge.nonce_hash then raise exception 'coin_link_challenge_invalid'; end if;
	if exists (select 1 from public.multiplayer_v2_coin_rounds cr where cr.room_id = v_challenge.room_id and cr.lobby_generation = v_challenge.lobby_generation) then raise exception 'coin_account_binding_frozen'; end if;
	select l.account_user_id into v_existing from public.multiplayer_v2_coin_account_links l
	where l.room_id = v_challenge.room_id and l.lobby_generation = v_challenge.lobby_generation and l.network_user_id = v_challenge.network_user_id for update;
	if v_existing is not null and v_existing <> v_account then raise exception 'coin_account_already_bound'; end if;
	insert into public.multiplayer_v2_coin_account_links(room_id, lobby_generation, network_user_id, account_user_id)
	values (v_challenge.room_id, v_challenge.lobby_generation, v_challenge.network_user_id, v_account)
	on conflict (room_id, lobby_generation, network_user_id) do update set account_user_id = excluded.account_user_id
	where public.multiplayer_v2_coin_account_links.account_user_id is null or public.multiplayer_v2_coin_account_links.account_user_id = excluded.account_user_id;
	if not found then raise exception 'coin_account_already_bound'; end if;
	update public.multiplayer_v2_coin_link_challenges set consumed_at = now() where challenge_id = p_challenge_id;
	return jsonb_build_object('bound', true, 'room_id', v_challenge.room_id, 'lobby_generation', v_challenge.lobby_generation);
end $$;

create or replace function public.register_multiplayer_v2_coin_round(
	p_room_id uuid, p_lobby_generation bigint, p_runtime_round_id text, p_manifest_hash text, p_coin_ids jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.multiplayer_rooms%rowtype; v_round public.multiplayer_v2_coin_rounds%rowtype; v_ids text[]; v_round_id uuid;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_room from public.multiplayer_rooms where room_id = p_room_id and network_mode = 'v2' for update;
	if not found or v_room.owner_user_id <> auth.uid() then raise exception 'not_room_owner'; end if;
	if v_room.phase not in ('PREPARING_COURSE', 'COUNTDOWN', 'RUNNING', 'FINISHED') or v_room.lobby_generation <> p_lobby_generation then raise exception 'coin_round_unavailable'; end if;
	if v_room.generator_version <> 5 or v_room.game_version <> '2.1.20261001.1' then raise exception 'coin_game_version_mismatch'; end if;
	if v_room.manifest_hash is null or p_manifest_hash <> v_room.manifest_hash or p_runtime_round_id is null or char_length(p_runtime_round_id) not between 1 and 64 then raise exception 'coin_manifest_mismatch'; end if;
	if p_coin_ids is null or jsonb_typeof(p_coin_ids) <> 'array' or jsonb_array_length(p_coin_ids) > 1600 then raise exception 'invalid_coin_catalog'; end if;
	if exists (select 1 from jsonb_array_elements(p_coin_ids) e(value) where jsonb_typeof(e.value) <> 'string' or (e.value #>> '{}') !~ '^coin_[1-9][0-9]?_[0-9]{5}_[0-3]$') then raise exception 'invalid_coin_catalog'; end if;
	select array_agg(e.value #>> '{}' order by e.ordinality) into v_ids from jsonb_array_elements(p_coin_ids) with ordinality e(value, ordinality);
	if cardinality(v_ids) <> (select count(distinct i) from unnest(v_ids) i) then raise exception 'duplicate_coin_id'; end if;
	select * into v_round from public.multiplayer_v2_coin_rounds cr where cr.room_id = p_room_id and cr.lobby_generation = p_lobby_generation for update;
	if found then
		if v_round.runtime_round_id <> p_runtime_round_id or v_round.manifest_hash <> p_manifest_hash then raise exception 'coin_round_mismatch'; end if;
		if (select array_agg(c.entity_id order by c.entity_id) from public.multiplayer_v2_coin_catalog c where c.coin_round_id = v_round.coin_round_id)
			is distinct from (select array_agg(i order by i) from unnest(v_ids) i) then raise exception 'coin_catalog_mismatch'; end if;
		return jsonb_build_object('coin_round_id', v_round.coin_round_id, 'duplicate', true);
	end if;
	insert into public.multiplayer_v2_coin_rounds(room_id, lobby_generation, runtime_round_id, manifest_hash, seed, generator_version, host_network_user_id)
	values (p_room_id, p_lobby_generation, p_runtime_round_id, p_manifest_hash, v_room.seed, v_room.generator_version, auth.uid()) returning coin_round_id into v_round_id;
	insert into public.multiplayer_v2_coin_round_members(coin_round_id, network_user_id, player_slot, account_user_id)
	select v_round_id, m.user_id, m.player_slot, l.account_user_id
	from public.multiplayer_room_members m
	left join public.multiplayer_v2_coin_account_links l on l.room_id = p_room_id and l.lobby_generation = p_lobby_generation and l.network_user_id = m.user_id
	where m.room_id = p_room_id;
	insert into public.multiplayer_v2_coin_catalog(coin_round_id, entity_id)
	select v_round_id, unnest(v_ids);
	return jsonb_build_object('coin_round_id', v_round_id, 'duplicate', false, 'coin_count', cardinality(v_ids));
end $$;

create or replace function public.journal_multiplayer_v2_coin_awards(p_coin_round_id uuid, p_awards jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_round public.multiplayer_v2_coin_rounds%rowtype; v_count integer; v_inserted integer;
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	select * into v_round from public.multiplayer_v2_coin_rounds where coin_round_id = p_coin_round_id for no key update;
	if not found or v_round.host_network_user_id <> auth.uid() then raise exception 'not_round_host'; end if;
	if p_awards is null or jsonb_typeof(p_awards) <> 'array' or jsonb_array_length(p_awards) > 64 then raise exception 'invalid_coin_award_batch'; end if;
	if exists (select 1 from jsonb_array_elements(p_awards) e(value) where jsonb_typeof(e.value) <> 'object' or (select count(*) from jsonb_object_keys(e.value)) <> 2 or not (e.value ? 'entity_id' and e.value ? 'player_slot') or jsonb_typeof(e.value->'entity_id') <> 'string' or jsonb_typeof(e.value->'player_slot') <> 'number') then raise exception 'invalid_coin_award_batch'; end if;
	if exists (select 1 from (select value->>'entity_id' id, count(*) n from jsonb_array_elements(p_awards) group by 1) d where d.n > 1) then raise exception 'duplicate_coin_award_in_batch'; end if;
	if exists (
		select 1 from jsonb_array_elements(p_awards) e(value)
		where not exists (select 1 from public.multiplayer_v2_coin_catalog c where c.coin_round_id = p_coin_round_id and c.entity_id = e.value->>'entity_id')
		or not exists (select 1 from public.multiplayer_v2_coin_round_members m where m.coin_round_id = p_coin_round_id and m.player_slot = (e.value->>'player_slot')::smallint)
	) then raise exception 'unknown_coin_or_member'; end if;
	if exists (
		select 1 from jsonb_array_elements(p_awards) e(value)
		join public.multiplayer_v2_coin_round_members m on m.coin_round_id = p_coin_round_id and m.player_slot = (e.value->>'player_slot')::smallint
		join public.multiplayer_v2_coin_awards a on a.coin_round_id = p_coin_round_id and a.entity_id = e.value->>'entity_id'
		where a.network_user_id <> m.network_user_id
	) then raise exception 'coin_award_conflict'; end if;
	insert into public.multiplayer_v2_coin_awards(coin_round_id, entity_id, network_user_id, account_user_id, value)
	select p_coin_round_id, e.value->>'entity_id', m.network_user_id, m.account_user_id, c.value
	from jsonb_array_elements(p_awards) e(value)
	join public.multiplayer_v2_coin_catalog c on c.coin_round_id = p_coin_round_id and c.entity_id = e.value->>'entity_id'
	join public.multiplayer_v2_coin_round_members m on m.coin_round_id = p_coin_round_id and m.player_slot = (e.value->>'player_slot')::smallint
	on conflict (coin_round_id, entity_id) do nothing;
	get diagnostics v_inserted = row_count;
	select count(*) into v_count from jsonb_array_elements(p_awards);
	return jsonb_build_object('accepted', v_count, 'journaled', v_inserted, 'duplicates', v_count - v_inserted);
end $$;

create or replace function public.settle_my_pending_multiplayer_coin_awards()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account uuid := auth.uid(); v_member record; v_total integer := 0; v_balance bigint; v_previous integer; v_current integer; v_delta integer; v_settlements jsonb;
begin
	if v_account is null then raise exception 'not_authenticated'; end if;
	if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'signed_in_account_required'; end if;
	for v_member in
		select m.coin_round_id, m.network_user_id
		from public.multiplayer_v2_coin_round_members m
		where m.account_user_id = v_account
		order by m.coin_round_id, m.network_user_id
	loop
		-- The member row serializes settlements for this identity while late journal
		-- batches can continue to arrive. Credit only the increase in the snapshot sum.
		perform 1 from public.multiplayer_v2_coin_round_members m
		where m.coin_round_id = v_member.coin_round_id and m.network_user_id = v_member.network_user_id
		for no key update;
		select coalesce(sum(a.value), 0)::integer into v_current
		from public.multiplayer_v2_coin_awards a
		where a.coin_round_id = v_member.coin_round_id and a.network_user_id = v_member.network_user_id and a.account_user_id = v_account;
		insert into public.multiplayer_v2_coin_settlements(coin_round_id, network_user_id, account_user_id, coins_earned)
		values (v_member.coin_round_id, v_member.network_user_id, v_account, 0)
		on conflict (coin_round_id, network_user_id) do nothing;
		select s.coins_earned into v_previous from public.multiplayer_v2_coin_settlements s
		where s.coin_round_id = v_member.coin_round_id and s.network_user_id = v_member.network_user_id
		for no key update;
		if v_current > v_previous then
			v_delta := v_current - v_previous;
			update public.multiplayer_v2_coin_settlements set coins_earned = v_current, settled_at = now()
			where coin_round_id = v_member.coin_round_id and network_user_id = v_member.network_user_id;
			insert into public.player_progress(user_id, wallet_coins)
			values (v_account, v_delta)
			on conflict (user_id) do update set wallet_coins = public.player_progress.wallet_coins + excluded.wallet_coins;
			v_total := v_total + v_delta;
		end if;
	end loop;
	select coalesce(p.wallet_coins, 0) into v_balance from public.player_progress p where p.user_id = v_account;
	select coalesce(jsonb_agg(jsonb_build_object(
		'coin_round_id', s.coin_round_id,
		'network_user_id', s.network_user_id,
		'account_user_id', s.account_user_id,
		'coins_earned', s.coins_earned,
		'runtime_round_id', r.runtime_round_id,
		'room_id', r.room_id,
		'lobby_generation', r.lobby_generation
	) order by s.coin_round_id, s.network_user_id), '[]'::jsonb) into v_settlements
	from public.multiplayer_v2_coin_settlements s
	join public.multiplayer_v2_coin_rounds r using (coin_round_id)
	where s.account_user_id = v_account and s.coin_round_id in (
		select recent.coin_round_id from (
			select distinct sr.coin_round_id, max(rr.created_at) as created_at
			from public.multiplayer_v2_coin_settlements sr
			join public.multiplayer_v2_coin_rounds rr using (coin_round_id)
			where sr.account_user_id = v_account
			group by sr.coin_round_id
			order by max(rr.created_at) desc
			limit 32
		) recent
	);
	return jsonb_build_object('coins_credited', v_total, 'wallet_coins', coalesce(v_balance, 0), 'settlements', v_settlements);
end $$;

revoke all on function public.request_multiplayer_v2_coin_account_link(uuid,bigint) from public, anon;
revoke all on function public.resolve_multiplayer_v2_coin_account_link(uuid,text) from public, anon;
revoke all on function public.register_multiplayer_v2_coin_round(uuid,bigint,text,text,jsonb) from public, anon;
revoke all on function public.journal_multiplayer_v2_coin_awards(uuid,jsonb) from public, anon;
revoke all on function public.settle_my_pending_multiplayer_coin_awards() from public, anon;
grant execute on function public.request_multiplayer_v2_coin_account_link(uuid,bigint) to authenticated;
grant execute on function public.resolve_multiplayer_v2_coin_account_link(uuid,text) to authenticated;
grant execute on function public.register_multiplayer_v2_coin_round(uuid,bigint,text,text,jsonb) to authenticated;
grant execute on function public.journal_multiplayer_v2_coin_awards(uuid,jsonb) to authenticated;
grant execute on function public.settle_my_pending_multiplayer_coin_awards() to authenticated;

-- Compatibility gate: existing rooms stay on their old version; only new v5 clients join this contract.
create or replace function public.multiplayer_v2_create_room(
	p_display_name text, p_game_version text, p_generator_version smallint,
	p_seed bigint, p_course_length_px integer, p_is_public boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid := gen_random_uuid(); v_code text; v_topic text := 'gravity-run-v2:' || encode(extensions.gen_random_bytes(24), 'hex');
begin
	if auth.uid() is null then raise exception 'not_authenticated'; end if;
	if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 16 or p_display_name !~ '^[[:alnum:]_ ]+$' then raise exception 'invalid_display_name'; end if;
	if p_game_version <> '2.1.20261001.1' or p_generator_version <> 5 then raise exception 'version_mismatch'; end if;
	if p_seed not between 1 and 2147483647 then raise exception 'invalid_seed'; end if;
	if p_course_length_px not between 10000 and 1000000 then raise exception 'invalid_course_length'; end if;
	delete from public.multiplayer_rooms where expires_at <= now() or phase in ('CLOSED', 'FINISHED') and last_activity_at < now() - interval '1 hour';
	loop v_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 8)); exit when not exists (select 1 from public.multiplayer_rooms where room_code = v_code); end loop;
	insert into public.multiplayer_rooms(room_id, room_code, owner_user_id, game_version, generator_version, seed, course_length_px, signaling_topic, is_public, max_players, network_mode, v2_protocol_version)
	values(v_room_id, v_code, auth.uid(), btrim(p_game_version), p_generator_version, p_seed, p_course_length_px, v_topic, coalesce(p_is_public, true), 5, 'v2', 2);
	insert into public.multiplayer_room_members(room_id, user_id, player_slot, display_name, returned_for_cycle)
	values(v_room_id, auth.uid(), 1, btrim(p_display_name), 1);
	return public._multiplayer_v2_room_payload(v_room_id);
end $$;
