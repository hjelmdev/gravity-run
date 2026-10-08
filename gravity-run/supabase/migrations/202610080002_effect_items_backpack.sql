-- Step 1 of the equipment plan: the backpack slot, an allowlisted gameplay effect
-- (effect_id + effect_level) on catalog items, and the first three effect items:
-- bubble helmet, spike plate and coin magnet. The effects themselves are
-- simulated by the game client (RunEffects); the database only names them.

alter table public.item_definitions
	add column if not exists effect_id text,
	add column if not exists effect_level integer not null default 1;

alter table public.item_definitions drop constraint if exists item_definition_effect_valid;
alter table public.item_definitions add constraint item_definition_effect_valid check (
	effect_id is null
	or (
		effect_level between 1 and 3
		and (
			(effect_id in ('bubble_shield', 'spike_plate') and slot_type = 'helmet')
			or (effect_id = 'coin_magnet' and slot_type = 'backpack')
		)
	)
);

alter table public.item_definitions drop constraint if exists item_definition_slot_valid;
alter table public.item_definitions add constraint item_definition_slot_valid
	check (slot_type in ('helmet', 'boots', 'backpack'));

alter table public.player_equipment drop constraint if exists player_equipment_slot_valid;
alter table public.player_equipment add constraint player_equipment_slot_valid
	check (slot_type in ('helmet', 'boots', 'backpack'));

insert into public.item_definitions
	(item_id, slot_type, rarity, name_key, description_key, icon_key, stat_modifiers, effect_ids, effect_id, effect_level, shop_price, shop_enabled, drop_enabled, catalog_version)
values
	('helmet_bubble_01', 'helmet', 'rare', 'item.helmet_bubble_01.name', 'item.helmet_bubble_01.description', 'helmet_bubble_01', '{}', '[]', 'bubble_shield', 1, 600, true, false, 3),
	('helmet_spikeplate_01', 'helmet', 'uncommon', 'item.helmet_spikeplate_01.name', 'item.helmet_spikeplate_01.description', 'helmet_spikeplate_01', '{}', '[]', 'spike_plate', 1, 350, true, false, 3),
	('backpack_magnet_01', 'backpack', 'uncommon', 'item.backpack_magnet_01.name', 'item.backpack_magnet_01.description', 'backpack_magnet_01', '{}', '[]', 'coin_magnet', 1, 450, true, false, 3)
on conflict (item_id) do nothing;

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
				'effect_id', d.effect_id, 'effect_level', d.effect_level,
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
	if p_instance_id is null or p_slot_type not in ('helmet', 'boots', 'backpack') then
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
	if p_slot_type not in ('helmet', 'boots', 'backpack') then
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
revoke all on function public.equip_item(uuid, text) from public, anon;
revoke all on function public.unequip_item(text) from public, anon;
grant execute on function public.get_my_inventory_state() to authenticated;
grant execute on function public.equip_item(uuid, text) to authenticated;
grant execute on function public.unequip_item(text) to authenticated;

notify pgrst, 'reload schema';
