-- Pause regular run drops while keeping the weighted drop catalog/configuration
-- available for later event or special-item loot.
update public.item_drop_weights
set active = false, updated_at = now()
where active;

notify pgrst, 'reload schema';
