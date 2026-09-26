-- Account-owned inventory and server-authoritative shop/equipment operations.
-- Item definitions are safe data only; no database-provided code is executed.

create table if not exists public.item_definitions (
	item_id text primary key,
	slot_type text not null,
	rarity text not null,
	name_key text not null,
	description_key text not null,
	icon_key text not null,
	stat_modifiers jsonb not null default '{}'::jsonb,
	effect_ids jsonb not null default '[]'::jsonb,
	shop_price integer not null default 0,
	shop_enabled boolean not null default false,
	drop_enabled boolean not null default false,
	catalog_version integer not null default 1,
	active boolean not null default true,
	constraint item_definition_id_valid check (item_id ~ '^[a-z0-9_]{1,64}$'),
	constraint item_definition_slot_valid check (slot_type in ('helmet', 'boots')),
	constraint item_definition_rarity_valid check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
	constraint item_definition_keys_valid check (
		name_key ~ '^[A-Za-z0-9_.-]{1,100}$'
		and description_key ~ '^[A-Za-z0-9_.-]{1,100}$'
		and icon_key ~ '^[a-z0-9_]{1,64}$'
	),
	constraint item_definition_modifiers_object check (jsonb_typeof(stat_modifiers) = 'object'),
	constraint item_definition_effects_array check (jsonb_typeof(effect_ids) = 'array'),
	constraint item_definition_shop_price_range check (shop_price between 0 and 1000000),
	constraint item_definition_catalog_version_positive check (catalog_version > 0)
);

-- Keep the initial catalog intentionally neutral: none of its entries claim
-- gameplay bonuses until a supported effect is implemented in the game.
insert into public.item_definitions
	(item_id, slot_type, rarity, name_key, description_key, icon_key, stat_modifiers, effect_ids, shop_price, shop_enabled, drop_enabled, catalog_version)
values
	('helmet_copper_01', 'helmet', 'common', 'item.helmet_copper_01.name', 'item.helmet_copper_01.description', 'helmet_copper_01', '{}', '[]', 100, true, true, 1),
	('helmet_scout_01', 'helmet', 'uncommon', 'item.helmet_scout_01.name', 'item.helmet_scout_01.description', 'helmet_scout_01', '{}', '[]', 250, true, true, 1),
	('helmet_night_01', 'helmet', 'rare', 'item.helmet_night_01.name', 'item.helmet_night_01.description', 'helmet_night_01', '{}', '[]', 500, true, false, 1),
	('boots_canvas_01', 'boots', 'common', 'item.boots_canvas_01.name', 'item.boots_canvas_01.description', 'boots_canvas_01', '{}', '[]', 100, true, true, 1),
	('boots_runner_01', 'boots', 'uncommon', 'item.boots_runner_01.name', 'item.boots_runner_01.description', 'boots_runner_01', '{}', '[]', 250, true, true, 1),
	('boots_gravity_01', 'boots', 'rare', 'item.boots_gravity_01.name', 'item.boots_gravity_01.description', 'boots_gravity_01', '{}', '[]', 500, true, false, 1)
on conflict (item_id) do nothing;

create table if not exists public.player_items (
	instance_id uuid primary key default gen_random_uuid(),
	user_id uuid not null references auth.users (id) on delete cascade,
	item_id text not null references public.item_definitions (item_id),
	acquired_at timestamptz not null default now(),
	source text not null,
	constraint player_item_source_valid check (source in ('shop', 'run_drop', 'achievement')),
	constraint player_item_unique_definition_per_user unique (user_id, item_id),
	constraint player_item_instance_owner_unique unique (user_id, instance_id)
);

create table if not exists public.player_equipment (
	user_id uuid not null references auth.users (id) on delete cascade,
	slot_type text not null,
	instance_id uuid not null,
	updated_at timestamptz not null default now(),
	primary key (user_id, slot_type),
	constraint player_equipment_slot_valid check (slot_type in ('helmet', 'boots')),
	constraint player_equipment_instance_unique unique (instance_id),
	constraint player_equipment_owned_item_fk foreign key (user_id, instance_id)
		references public.player_items (user_id, instance_id) on delete cascade
);

create table if not exists public.shop_purchases (
	user_id uuid not null references auth.users (id) on delete cascade,
	request_id uuid not null,
	item_id text not null references public.item_definitions (item_id),
	price_paid integer not null,
	instance_id uuid not null,
	purchased_at timestamptz not null default now(),
	primary key (user_id, request_id),
	constraint shop_purchase_price_range check (price_paid between 0 and 1000000),
	constraint shop_purchase_instance_owner_fk foreign key (user_id, instance_id)
		references public.player_items (user_id, instance_id)
);

-- Loot is not enabled yet, but reserve an idempotent, auditable claim shape.
create table if not exists public.run_item_claims (
	user_id uuid not null,
	run_id uuid not null,
	pickup_index integer not null,
	item_id text references public.item_definitions (item_id),
	instance_id uuid,
	claim_status text not null,
	claimed_at timestamptz not null default now(),
	primary key (user_id, run_id, pickup_index),
	constraint run_item_claim_index_valid check (pickup_index between 0 and 100),
	constraint run_item_claim_status_valid check (claim_status in ('awarded', 'already_owned', 'no_drop')),
	constraint run_item_claim_run_fk foreign key (user_id, run_id)
		references public.player_run_history (user_id, run_id) on delete cascade,
	constraint run_item_claim_instance_owner_fk foreign key (user_id, instance_id)
		references public.player_items (user_id, instance_id)
);

alter table public.item_definitions enable row level security;
alter table public.player_items enable row level security;
alter table public.player_equipment enable row level security;
alter table public.shop_purchases enable row level security;
alter table public.run_item_claims enable row level security;
revoke all on table public.item_definitions, public.player_items, public.player_equipment,
	public.shop_purchases, public.run_item_claims from public, anon, authenticated;

create or replace function public.get_my_inventory_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	result jsonb;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	select jsonb_build_object(
		'wallet_coins', coalesce((select p.wallet_coins from public.player_progress p where p.user_id = current_user_id), 0),
		'catalog', coalesce((
			select jsonb_agg(jsonb_build_object(
				'item_id', d.item_id, 'slot_type', d.slot_type, 'rarity', d.rarity,
				'name_key', d.name_key, 'description_key', d.description_key, 'icon_key', d.icon_key,
				'stat_modifiers', d.stat_modifiers, 'effect_ids', d.effect_ids,
				'shop_price', d.shop_price, 'shop_enabled', d.shop_enabled,
				'drop_enabled', d.drop_enabled, 'catalog_version', d.catalog_version, 'active', d.active
			) order by d.slot_type, d.rarity, d.item_id)
			from public.item_definitions d where d.active
		), '[]'::jsonb),
		'items', coalesce((
			select jsonb_agg(jsonb_build_object(
				'instance_id', i.instance_id, 'item_id', i.item_id,
				'acquired_at', i.acquired_at, 'source', i.source
			) order by i.acquired_at, i.instance_id)
			from public.player_items i where i.user_id = current_user_id
		), '[]'::jsonb),
		'equipment', coalesce((
			select jsonb_object_agg(e.slot_type, e.instance_id)
			from public.player_equipment e where e.user_id = current_user_id
		), '{}'::jsonb)
	) into result;
	return result;
end;
$$;

create or replace function public.purchase_item(p_item_id text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	item_row public.item_definitions%rowtype;
	purchase_row public.shop_purchases%rowtype;
	new_instance_id uuid;
	current_balance bigint;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if p_request_id is null or p_item_id is null or p_item_id !~ '^[a-z0-9_]{1,64}$' then
		raise exception 'invalid_purchase_request' using errcode = '22023';
	end if;
	select * into purchase_row from public.shop_purchases p
	where p.user_id = current_user_id and p.request_id = p_request_id;
	if found then
		return jsonb_build_object('purchase', jsonb_build_object(
			'item_id', purchase_row.item_id, 'instance_id', purchase_row.instance_id,
			'price_paid', purchase_row.price_paid, 'purchased_at', purchase_row.purchased_at
		), 'state', public.get_my_inventory_state());
	end if;

	-- Serialize all shop operations for this account; create the wallet row if
	-- the account has not recorded a run yet.
	insert into public.player_progress (user_id) values (current_user_id)
		on conflict (user_id) do nothing;
	select p.wallet_coins into current_balance from public.player_progress p
	where p.user_id = current_user_id for update;
	-- Recheck request id after acquiring the account lock for concurrent retries.
	select * into purchase_row from public.shop_purchases p
	where p.user_id = current_user_id and p.request_id = p_request_id;
	if found then
		return jsonb_build_object('purchase', jsonb_build_object(
			'item_id', purchase_row.item_id, 'instance_id', purchase_row.instance_id,
			'price_paid', purchase_row.price_paid, 'purchased_at', purchase_row.purchased_at
		), 'state', public.get_my_inventory_state());
	end if;

	select * into item_row from public.item_definitions d
	where d.item_id = p_item_id and d.active and d.shop_enabled;
	if not found then
		raise exception 'item_not_for_sale' using errcode = '22023';
	end if;
	if exists (select 1 from public.player_items i where i.user_id = current_user_id and i.item_id = p_item_id) then
		raise exception 'item_already_owned' using errcode = '22023';
	end if;
	if current_balance < item_row.shop_price then
		raise exception 'insufficient_coins' using errcode = '22023';
	end if;
	update public.player_progress p
	set wallet_coins = p.wallet_coins - item_row.shop_price, updated_at = now()
	where p.user_id = current_user_id;
	insert into public.player_items (user_id, item_id, source)
	values (current_user_id, p_item_id, 'shop')
	returning instance_id into new_instance_id;
	insert into public.shop_purchases (user_id, request_id, item_id, price_paid, instance_id)
	values (current_user_id, p_request_id, p_item_id, item_row.shop_price, new_instance_id)
	returning * into purchase_row;
	return jsonb_build_object('purchase', jsonb_build_object(
		'item_id', purchase_row.item_id, 'instance_id', purchase_row.instance_id,
		'price_paid', purchase_row.price_paid, 'purchased_at', purchase_row.purchased_at
	), 'state', public.get_my_inventory_state());
end;
$$;

create or replace function public.equip_item(p_instance_id uuid, p_slot_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
	current_user_id uuid := (select auth.uid());
	item_slot text;
begin
	if current_user_id is null then
		raise exception 'not_authenticated' using errcode = '28000';
	end if;
	if p_instance_id is null or p_slot_type not in ('helmet', 'boots') then
		raise exception 'invalid_equipment_slot' using errcode = '22023';
	end if;
	insert into public.player_progress (user_id) values (current_user_id)
		on conflict (user_id) do nothing;
	perform 1 from public.player_progress p where p.user_id = current_user_id for update;
	select d.slot_type into item_slot
	from public.player_items i join public.item_definitions d on d.item_id = i.item_id
	where i.user_id = current_user_id and i.instance_id = p_instance_id and d.active;
	if not found then
		raise exception 'item_not_owned' using errcode = '22023';
	end if;
	if item_slot <> p_slot_type then
		raise exception 'item_wrong_slot' using errcode = '22023';
	end if;
	if exists (select 1 from public.player_equipment e
		where e.user_id = current_user_id and e.instance_id = p_instance_id and e.slot_type <> p_slot_type) then
		raise exception 'item_already_equipped' using errcode = '22023';
	end if;
	insert into public.player_equipment (user_id, slot_type, instance_id, updated_at)
	values (current_user_id, p_slot_type, p_instance_id, now())
	on conflict (user_id, slot_type) do update set
		instance_id = excluded.instance_id, updated_at = excluded.updated_at;
	return public.get_my_inventory_state();
end;
$$;

create or replace function public.unequip_item(p_slot_type text)
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
	if p_slot_type not in ('helmet', 'boots') then
		raise exception 'invalid_equipment_slot' using errcode = '22023';
	end if;
	insert into public.player_progress (user_id) values (current_user_id)
		on conflict (user_id) do nothing;
	perform 1 from public.player_progress p where p.user_id = current_user_id for update;
	delete from public.player_equipment e
	where e.user_id = current_user_id and e.slot_type = p_slot_type;
	return public.get_my_inventory_state();
end;
$$;

revoke all on function public.get_my_inventory_state() from public, anon;
revoke all on function public.purchase_item(text, uuid) from public, anon;
revoke all on function public.equip_item(uuid, text) from public, anon;
revoke all on function public.unequip_item(text) from public, anon;
grant execute on function public.get_my_inventory_state() to authenticated;
grant execute on function public.purchase_item(text, uuid) to authenticated;
grant execute on function public.equip_item(uuid, text) to authenticated;
grant execute on function public.unequip_item(text) to authenticated;

notify pgrst, 'reload schema';
