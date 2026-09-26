extends Resource
class_name RunLoadoutSnapshot
## Immutable-by-convention snapshot: a run never reads mutable equipment state.

const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")

var _is_valid := false
var _errors: Array[String] = []
var _catalog_version := 1
var _equipped_instance_ids: Dictionary = {}
var _equipped_item_ids: Dictionary = {}
var _base_stats: Dictionary = {}
var _stat_bonuses: Dictionary = {}
var _resolved_stats: Dictionary = {}
var _stat_sources: Dictionary = {}
var _loadout_signature := ""

static func create(equipped_items: Array, catalog_version: int, base_stats: Dictionary) -> RunLoadoutSnapshot:
	var snapshot := RunLoadoutSnapshot.new()
	snapshot._catalog_version = catalog_version
	if catalog_version < 1:
		snapshot._errors.append("Catalog version must be positive.")
		return snapshot
	var result := EquipmentStatsScript.resolve(equipped_items, base_stats)
	for error in result.errors:
		snapshot._errors.append(str(error))
	if not bool(result.valid):
		return snapshot
	snapshot._is_valid = true
	snapshot._base_stats = result.base_stats.duplicate(true)
	snapshot._stat_bonuses = result.bonuses.duplicate(true)
	snapshot._resolved_stats = result.totals.duplicate(true)
	snapshot._stat_sources = result.sources.duplicate(true)
	for entry in equipped_items:
		var definition: Resource = entry.definition
		var slot_key := str(entry.slot_type)
		snapshot._equipped_instance_ids[slot_key] = str(entry.instance_id)
		snapshot._equipped_item_ids[slot_key] = str(definition.get("item_id"))
	snapshot._loadout_signature = snapshot._build_signature()
	return snapshot

func is_valid() -> bool:
	return _is_valid

func get_errors() -> Array[String]:
	return _errors.duplicate()

func get_catalog_version() -> int:
	return _catalog_version

func get_equipped_instance_ids() -> Dictionary:
	return _equipped_instance_ids.duplicate(true)

func get_equipped_item_ids() -> Dictionary:
	return _equipped_item_ids.duplicate(true)

func get_base_stats() -> Dictionary:
	return _base_stats.duplicate(true)

func get_stat_bonuses() -> Dictionary:
	return _stat_bonuses.duplicate(true)

func get_resolved_stats() -> Dictionary:
	return _resolved_stats.duplicate(true)

func get_stat_sources() -> Dictionary:
	return _stat_sources.duplicate(true)

func get_loadout_signature() -> String:
	return _loadout_signature

func _build_signature() -> String:
	var parts: Array[String] = ["catalog=%d" % _catalog_version]
	for slot_key in EquipmentStatsScript.SLOT_ORDER:
		if _equipped_item_ids.has(slot_key):
			parts.append("%s=%s" % [slot_key, str(_equipped_item_ids[slot_key])])
	for stat_id in EquipmentStatsScript.STAT_ORDER:
		parts.append("%s=%d" % [stat_id, int(_resolved_stats[stat_id])])
	return "|".join(parts)
