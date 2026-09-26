-- Small, functional equipment bonuses for the initial boot catalog.
update public.item_definitions
set stat_modifiers = '{"run_speed_percent":100}'::jsonb,
	catalog_version = 2
where item_id = 'boots_canvas_01';

update public.item_definitions
set stat_modifiers = '{"run_speed_percent":250}'::jsonb,
	catalog_version = 2
where item_id = 'boots_runner_01';

update public.item_definitions
set stat_modifiers = '{"flip_cooldown_percent":-300}'::jsonb,
	catalog_version = 2
where item_id = 'boots_gravity_01';
