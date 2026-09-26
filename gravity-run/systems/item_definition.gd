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
	return EquipmentStatsScript.validate_modifiers(stat_modifiers)

func _is_safe_key(value: String) -> bool:
	if value.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(value) != null
