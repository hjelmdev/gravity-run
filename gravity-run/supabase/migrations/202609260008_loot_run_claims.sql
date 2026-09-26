-- Versioned run RPC: preserves account/achievement processing while adding
-- server-owned, idempotent loot rolls for collected pickup indexes.

create table if not exists public.item_drop_weights (
	item_id text primary key references public.item_definitions (item_id) on delete cascade,
	drop_weight integer not null check (drop_weight between 1 and 1000000),
	active boolean not null default true,
	updated_at timestamptz not null default now()
);

insert into public.item_drop_weights (item_id, drop_weight)
select d.item_id, case d.rarity
	when 'common' then 100
	when 'uncommon' then 35
	when 'rare' then 8
	when 'epic' then 2
	else 1
end
from public.item_definitions d
where d.drop_enabled and d.active
on conflict (item_id) do nothing;

alter table public.item_drop_weights enable row level security;
revoke all on table public.item_drop_weights from public, anon, authenticated;

create or replace function public.record_player_run_v2(
	p_run_id uuid,
	p_distance_m integer,
	p_coins_earned integer,
	p_gravity_flips integer,
	p_hazards_encountered text[],
	p_loot_pickup_indexes integer[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	base_result jsonb;
	claim_index integer;
	claim_row public.run_item_claims%rowtype;
	selected_item public.item_definitions%rowtype;
	total_weight bigint;
	roll_value bigint;
	claimed_instance uuid;
	claims jsonb := '[]'::jsonb;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if cardinality(coalesce(p_loot_pickup_indexes, array[]::integer[])) > 2
		or exists (
			select 1 from unnest(coalesce(p_loot_pickup_indexes, array[]::integer[])) i
			where i not between 1 and 2
		)
		or cardinality(coalesce(p_loot_pickup_indexes, array[]::integer[])) <>
			(select count(distinct i) from unnest(coalesce(p_loot_pickup_indexes, array[]::integer[])) i)
	then
		raise exception 'invalid_loot_pickup_indexes' using errcode = '22023';
	end if;
	if exists (
		select 1 from unnest(coalesce(p_loot_pickup_indexes, array[]::integer[])) i
		where p_distance_m < i * 600
	) then
		raise exception 'loot_pickup_beyond_run_distance' using errcode = '22023';
	end if;

	-- The same account lock serializes run retries and competing item awards.
	insert into public.player_progress (user_id) values (current_user_id)
		on conflict (user_id) do nothing;
	perform 1 from public.player_progress p where p.user_id = current_user_id for update;
	base_result := public.record_player_run(
		p_run_id, p_distance_m, p_coins_earned, p_gravity_flips,
		coalesce(p_hazards_encountered, array[]::text[])
	);

	foreach claim_index in array coalesce(p_loot_pickup_indexes, array[]::integer[]) loop
		select * into claim_row from public.run_item_claims c
		where c.user_id = current_user_id and c.run_id = p_run_id and c.pickup_index = claim_index;
		if not found then
			select coalesce(sum(w.drop_weight), 0) into total_weight
			from public.item_drop_weights w
			join public.item_definitions d on d.item_id = w.item_id
			where w.active and d.active and d.drop_enabled
			and not exists (select 1 from public.player_items own where own.user_id = current_user_id and own.item_id = d.item_id);

			if total_weight > 0 then
				roll_value := floor(random() * total_weight)::bigint;
				with candidates as (
					select d.item_id, sum(w.drop_weight) over (order by d.item_id) cumulative_weight
					from public.item_drop_weights w
					join public.item_definitions d on d.item_id = w.item_id
					where w.active and d.active and d.drop_enabled
					and not exists (select 1 from public.player_items own where own.user_id = current_user_id and own.item_id = d.item_id)
				)
				select d.* into selected_item
				from candidates c join public.item_definitions d on d.item_id = c.item_id
				where c.cumulative_weight > roll_value order by c.cumulative_weight limit 1;
				if found then
					insert into public.player_items (user_id, item_id, source)
					values (current_user_id, selected_item.item_id, 'run_drop')
					on conflict (user_id, item_id) do nothing
					returning instance_id into claimed_instance;
					if claimed_instance is not null then
						insert into public.run_item_claims (user_id, run_id, pickup_index, item_id, instance_id, claim_status)
						values (current_user_id, p_run_id, claim_index, selected_item.item_id, claimed_instance, 'awarded');
					else
						insert into public.run_item_claims (user_id, run_id, pickup_index, item_id, claim_status)
						values (current_user_id, p_run_id, claim_index, selected_item.item_id, 'already_owned');
					end if;
				else
					insert into public.run_item_claims (user_id, run_id, pickup_index, claim_status)
					values (current_user_id, p_run_id, claim_index, 'no_drop');
				end if;
			else
				insert into public.run_item_claims (user_id, run_id, pickup_index, claim_status)
				values (current_user_id, p_run_id, claim_index, 'no_drop');
			end if;
			select * into claim_row from public.run_item_claims c
			where c.user_id = current_user_id and c.run_id = p_run_id and c.pickup_index = claim_index;
		end if;
		claims := claims || jsonb_build_array(jsonb_build_object(
			'pickup_index', claim_row.pickup_index,
			'claim_status', claim_row.claim_status,
			'item_id', claim_row.item_id,
			'name_key', (select d.name_key from public.item_definitions d where d.item_id = claim_row.item_id)
		));
	end loop;
	return base_result || jsonb_build_object('loot_claims', claims);
end;
$$;

revoke all on function public.record_player_run_v2(uuid, integer, integer, integer, text[], integer[]) from public, anon;
grant execute on function public.record_player_run_v2(uuid, integer, integer, integer, text[], integer[]) to authenticated;
notify pgrst, 'reload schema';
