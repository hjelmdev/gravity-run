-- Step 2 of the equipment plan: regret boots (boots slot, effect regret_flip) and
-- the gravity anchor (backpack slot, effect gravity_anchor, an active ability).
-- The effects are simulated by the game client (RunEffects); the database only
-- names them.

alter table public.item_definitions drop constraint if exists item_definition_effect_valid;
alter table public.item_definitions add constraint item_definition_effect_valid check (
	effect_id is null
	or (
		effect_level between 1 and 3
		and (
			(effect_id in ('bubble_shield', 'spike_plate') and slot_type = 'helmet')
			or (effect_id = 'regret_flip' and slot_type = 'boots')
			or (effect_id in ('coin_magnet', 'gravity_anchor') and slot_type = 'backpack')
		)
	)
);

insert into public.item_definitions
	(item_id, slot_type, rarity, name_key, description_key, icon_key, stat_modifiers, effect_ids, effect_id, effect_level, shop_price, shop_enabled, drop_enabled, catalog_version)
values
	('boots_regret_01', 'boots', 'rare', 'item.boots_regret_01.name', 'item.boots_regret_01.description', 'boots_regret_01', '{}', '[]', 'regret_flip', 1, 650, true, false, 3),
	('backpack_anchor_01', 'backpack', 'rare', 'item.backpack_anchor_01.name', 'item.backpack_anchor_01.description', 'backpack_anchor_01', '{}', '[]', 'gravity_anchor', 1, 700, true, false, 3)
on conflict (item_id) do nothing;

notify pgrst, 'reload schema';
