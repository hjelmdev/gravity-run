extends RefCounted
class_name EquipmentStats
## Pure equipment rules. No live gameplay values are changed by this resolver.

const SLOT_REGISTRY := {
	"helmet": {"allowed_item_types": [&"helmet"]},
	"boots": {"allowed_item_types": [&"boots"]},
}
const SLOT_ORDER: Array[String] = ["helmet", "boots"]
const STAT_ORDER: Array[String] = ["run_speed_percent", "flip_cooldown_percent"]
const BASE_STATS := {
	"run_speed_percent": 10000,
	"flip_cooldown_percent": 10000,
}
const STAT_REGISTRY := {
	"run_speed_percent": {
		"unit": "basis_points",
		"minimum_total": 5000,
		"maximum_total": 15000,
		"minimum_modifier": -5000,
		"maximum_modifier": 5000,
	},
	"flip_cooldown_percent": {
		"unit": "basis_points",
		"minimum_total": 5000,
		"maximum_total": 20000,
		"minimum_modifier": -5000,
		"maximum_modifier": 10000,
	},
}

static func validate_modifiers(modifiers: Dictionary) -> String:
	for stat_id in modifiers:
		var stat_key := str(stat_id)
		if not STAT_REGISTRY.has(stat_key):
			return "Unknown equipment stat '%s'." % stat_key
		var value: Variant = modifiers[stat_id]
		if typeof(value) != TYPE_INT:
			return "Equipment stat '%s' must be an integer basis-point value." % stat_key
		var stat_definition: Dictionary = STAT_REGISTRY[stat_key]
		if int(value) < int(stat_definition.minimum_modifier) or int(value) > int(stat_definition.maximum_modifier):
			return "Equipment stat '%s' is outside its supported modifier range." % stat_key
	return ""

static func is_known_item_type(item_type: StringName) -> bool:
	for slot_definition in SLOT_REGISTRY.values():
		if slot_definition.allowed_item_types.has(item_type):
			return true
	return false

## Each entry has slot_type, instance_id and a Resource ItemDefinition in definition.
## Result keys: valid, errors, base_stats, bonuses, totals, sources.
static func resolve(equipped_items: Array, base_stats: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var bases := BASE_STATS.duplicate(true)
	for stat_id in base_stats:
		var stat_key := str(stat_id)
		if not STAT_REGISTRY.has(stat_key):
			errors.append("Unknown base stat '%s'." % stat_key)
			continue
		if typeof(base_stats[stat_id]) != TYPE_INT:
			errors.append("Base stat '%s' must be an integer basis-point value." % stat_key)
			continue
		bases[stat_key] = int(base_stats[stat_id])

	var bonuses: Dictionary = {}
	var totals := bases.duplicate(true)
	var sources: Dictionary = {}
	for stat_id in STAT_ORDER:
		bonuses[stat_id] = 0
		sources[stat_id] = []
	var occupied_slots: Dictionary = {}
	var occupied_instances: Dictionary = {}
	var normalized_items: Array[Dictionary] = []
	for entry in equipped_items:
		if not entry is Dictionary:
			errors.append("Equipped item entries must be dictionaries.")
			continue
		var slot_key := str(entry.get("slot_type", ""))
		if not SLOT_REGISTRY.has(slot_key):
			errors.append("Unsupported equipment slot '%s'." % slot_key)
			continue
		if occupied_slots.has(slot_key):
			errors.append("Equipment slot '%s' is occupied more than once." % slot_key)
			continue
		var definition: Variant = entry.get("definition")
		if not definition is Resource:
			errors.append("Equipped item '%s' has no item definition." % str(entry.get("instance_id", "")))
			continue
		if not definition.has_method("validate"):
			errors.append("Equipped item has an invalid definition resource.")
			continue
		var definition_error := str(definition.call("validate"))
		if not definition_error.is_empty():
			errors.append("Item '%s': %s" % [str(definition.get("item_id")), definition_error])
			continue
		var slot_definition: Dictionary = SLOT_REGISTRY[slot_key]
		var item_type: StringName = definition.get("slot_type")
		if not slot_definition.allowed_item_types.has(item_type):
			errors.append("Item '%s' cannot be equipped in slot '%s'." % [str(definition.get("item_id")), slot_key])
			continue
		var instance_id := str(entry.get("instance_id", "")).strip_edges()
		if instance_id.is_empty():
			errors.append("Equipped items must have a stable instance ID.")
			continue
		if occupied_instances.has(instance_id):
			errors.append("An item instance cannot be equipped more than once.")
			continue
		occupied_slots[slot_key] = true
		occupied_instances[instance_id] = true
		normalized_items.append({"slot_type": slot_key, "instance_id": instance_id, "definition": definition})

	## Sorting makes calculations and diagnostic source lists independent of input order.
	normalized_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return SLOT_ORDER.find(str(a.slot_type)) < SLOT_ORDER.find(str(b.slot_type))
	)
	for item in normalized_items:
		var definition: Resource = item.definition
		var item_id := str(definition.get("item_id"))
		var slot_key := str(item.slot_type)
		var modifiers: Dictionary = definition.get("stat_modifiers")
		for stat_id in modifiers:
			var stat_key := str(stat_id)
			if not STAT_REGISTRY.has(stat_key) or typeof(modifiers[stat_id]) != TYPE_INT:
				continue
			var amount := int(modifiers[stat_id])
			bonuses[stat_key] = int(bonuses[stat_key]) + amount
			sources[stat_key].append({"slot_type": slot_key, "item_id": item_id, "amount_bps": amount})
	for stat_id in STAT_ORDER:
		var stat_definition: Dictionary = STAT_REGISTRY[stat_id]
		var total := int(bases.get(stat_id, -1)) + int(bonuses[stat_id])
		if total < int(stat_definition.minimum_total) or total > int(stat_definition.maximum_total):
			errors.append("Resolved stat '%s' is outside its supported range." % stat_id)
		else:
			totals[stat_id] = total
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"base_stats": bases.duplicate(true),
		"bonuses": bonuses.duplicate(true),
		"totals": totals.duplicate(true),
		"sources": sources.duplicate(true),
	}
