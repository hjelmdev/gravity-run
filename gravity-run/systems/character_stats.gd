extends Resource
class_name CharacterStats
## Per-character base attributes. Equipment is resolved into a separate run snapshot.

const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")

@export var character_id: StringName = &"runner"
@export var base_stats: Dictionary = {
	"run_speed_percent": 10000,
	"flip_cooldown_percent": 10000,
}

func get_base_stats() -> Dictionary:
	return base_stats.duplicate(true)

func validate() -> String:
	for stat_id in EquipmentStatsScript.STAT_ORDER:
		if not base_stats.has(stat_id):
			return "Character profile is missing base stat '%s'." % stat_id
		if typeof(base_stats[stat_id]) != TYPE_INT:
			return "Character base stat '%s' must be an integer." % stat_id
		var bounds: Dictionary = EquipmentStatsScript.STAT_REGISTRY[stat_id]
		if int(base_stats[stat_id]) < int(bounds.minimum_total) or int(base_stats[stat_id]) > int(bounds.maximum_total):
			return "Character base stat '%s' is outside its supported range." % stat_id
	for stat_id in base_stats:
		if not EquipmentStatsScript.STAT_ORDER.has(str(stat_id)):
			return "Unknown character base stat '%s'." % str(stat_id)
	return "" if not character_id.is_empty() else "Character profile needs an ID."
