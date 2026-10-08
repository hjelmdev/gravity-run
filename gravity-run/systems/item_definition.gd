extends Resource
class_name ItemDefinition
## Static catalog data. Ownership and equipment state belong to separate models.

const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")
const RARITIES := [&"common", &"uncommon", &"rare", &"epic", &"legendary"]

@export var item_id: StringName
@export var slot_type: StringName
@export var rarity: StringName = &"common"
@export var name_key: StringName
@export var description_key: StringName
@export var icon_key: StringName
## Integer basis-point modifiers keyed by an allowlisted stat ID.
@export var stat_modifiers: Dictionary = {}
## Allowlisted gameplay effect (see EquipmentStats.EFFECT_REGISTRY); empty for none.
@export var effect_id: StringName = &""
@export_range(0, 9, 1) var effect_level := 1
@export_range(0, 1000000, 1) var shop_price := 0
@export var shop_enabled := false
@export var drop_enabled := false
@export var active := true
@export_range(1, 1000000, 1) var catalog_version := 1

func validate() -> String:
	if not _is_safe_key(String(item_id)):
		return "Item ID must use lowercase letters, digits and underscores."
	if not EquipmentStatsScript.is_known_item_type(slot_type):
		return "Item references an unsupported item type."
	if not RARITIES.has(rarity):
		return "Item references an unsupported rarity."
	if name_key == StringName() or description_key == StringName():
		return "Items need localization keys for their name and description."
	if not _is_safe_key(String(icon_key)):
		return "Icon key must use lowercase letters, digits and underscores."
	if shop_price < 0:
		return "Shop price cannot be negative."
	if catalog_version < 1:
		return "Catalog version must be positive."
	var effect_error := EquipmentStatsScript.validate_effect(effect_id, effect_level, slot_type)
	if not effect_error.is_empty():
		return effect_error
	return EquipmentStatsScript.validate_modifiers(stat_modifiers)

## Builds a definition from a server catalog entry. Entries this client cannot
## represent (unknown slot) return null; an unknown or invalid effect is dropped
## so the item still works as a plain item instead of invalidating the loadout.
static func from_catalog_entry(raw: Dictionary) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.item_id = str(raw.get("item_id", ""))
	definition.slot_type = str(raw.get("slot_type", ""))
	if not EquipmentStatsScript.is_known_item_type(definition.slot_type):
		return null
	definition.rarity = str(raw.get("rarity", "common"))
	definition.name_key = str(raw.get("name_key", ""))
	definition.description_key = str(raw.get("description_key", ""))
	definition.icon_key = str(raw.get("icon_key", "unknown"))
	var modifiers: Variant = raw.get("stat_modifiers", {})
	definition.stat_modifiers = modifiers if modifiers is Dictionary else {}
	var raw_effect := str(raw.get("effect_id", "")) if raw.get("effect_id") != null else ""
	var raw_level := int(raw.get("effect_level", 1)) if raw.get("effect_level") != null else 1
	if EquipmentStatsScript.validate_effect(StringName(raw_effect), raw_level, definition.slot_type).is_empty():
		definition.effect_id = StringName(raw_effect)
		definition.effect_level = raw_level
	return definition

func _is_safe_key(value: String) -> bool:
	if value.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(value) != null
