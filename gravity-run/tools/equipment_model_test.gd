extends SceneTree
## Run with: godot --headless --path . --script res://tools/equipment_model_test.gd

const ItemDefinitionScript := preload("res://systems/item_definition.gd")
const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")
const RunLoadoutSnapshotScript := preload("res://systems/run_loadout_snapshot.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_empty_and_neutral_loadouts()
	_test_modifiers_are_summed_deterministically()
	_test_invalid_modifiers_and_slots_are_rejected()
	_test_snapshot_is_stable_and_returns_copies()
	if failures == 0:
		print("Equipment model tests passed.")
	quit(1 if failures > 0 else 0)

func _test_empty_and_neutral_loadouts() -> void:
	var empty_result: Dictionary = EquipmentStatsScript.resolve([])
	_check(bool(empty_result.valid), "an empty loadout should resolve")
	_check(empty_result.totals == EquipmentStatsScript.BASE_STATS, "an empty loadout should preserve base stats")
	var helmet := _item("cap_canvas", "helmet")
	var boots := _item("boots_canvas", "boots")
	var result: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "boots-1", "definition": boots},
		{"slot_type": "helmet", "instance_id": "helmet-1", "definition": helmet},
	])
	_check(bool(result.valid), "neutral helmet and boots should resolve")
	_check(result.bonuses["run_speed_percent"] == 0, "neutral items should not claim a speed bonus")
	_check(result.bonuses["flip_cooldown_percent"] == 0, "neutral items should not claim a cooldown bonus")

func _test_modifiers_are_summed_deterministically() -> void:
	var helmet := _item("cap_test", "helmet", {"run_speed_percent": 500})
	var boots := _item("boots_test", "boots", {"run_speed_percent": 1000, "flip_cooldown_percent": -1000})
	var helmet_entry := {"slot_type": "helmet", "instance_id": "h-1", "definition": helmet}
	var boots_entry := {"slot_type": "boots", "instance_id": "b-1", "definition": boots}
	var first: Dictionary = EquipmentStatsScript.resolve([helmet_entry, boots_entry])
	var reversed: Dictionary = EquipmentStatsScript.resolve([boots_entry, helmet_entry])
	_check(bool(first.valid), "valid fixture bonuses should resolve")
	_check(first.bonuses["run_speed_percent"] == 1500, "speed bonuses should add as integer basis points")
	_check(first.totals["run_speed_percent"] == 11500, "speed total should include the base 100 percent")
	_check(first.totals["flip_cooldown_percent"] == 9000, "negative cooldown modifier should reduce its multiplier")
	_check(first.totals == reversed.totals, "input item order should not change resolved stats")
	_check(first.sources["run_speed_percent"].size() == 2, "resolver should expose each stat source")

func _test_invalid_modifiers_and_slots_are_rejected() -> void:
	_check(not str(_item("unknown_stat", "boots", {"speed": 500}).call("validate")).is_empty(), "unknown stat IDs should be rejected")
	_check(not str(_item("float_stat", "boots", {"run_speed_percent": 1.5}).call("validate")).is_empty(), "non-integer modifiers should be rejected")
	_check(not str(_item("large_stat", "boots", {"run_speed_percent": 6000}).call("validate")).is_empty(), "out-of-range modifiers should be rejected")
	var wrong_slot := _item("helmet_item", "helmet")
	var mismatch: Dictionary = EquipmentStatsScript.resolve([{"slot_type": "boots", "instance_id": "h-1", "definition": wrong_slot}])
	_check(not bool(mismatch.valid), "an item cannot be equipped in a different slot")
	var duplicate: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "b-1", "definition": _item("boots_one", "boots")},
		{"slot_type": "boots", "instance_id": "b-2", "definition": _item("boots_two", "boots")},
	])
	_check(not bool(duplicate.valid), "a slot cannot contain two equipped items")
	var duplicate_instance: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "same-instance", "definition": _item("boots_instance", "boots")},
		{"slot_type": "helmet", "instance_id": "same-instance", "definition": _item("helmet_instance", "helmet")},
	])
	_check(not bool(duplicate_instance.valid), "one owned instance cannot occupy multiple slots")
	var fast_boots := _item("fast_boots", "boots", {"run_speed_percent": 5000})
	var fast_helmet := _item("fast_helmet", "helmet", {"run_speed_percent": 5000})
	var bounded: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "fast-1", "definition": fast_boots},
		{"slot_type": "helmet", "instance_id": "fast-2", "definition": fast_helmet},
	])
	_check(not bool(bounded.valid), "resolved stats outside global bounds should be rejected")

func _test_snapshot_is_stable_and_returns_copies() -> void:
	var boots := _item("boots_snapshot", "boots", {"run_speed_percent": 250})
	var helmet := _item("helmet_snapshot", "helmet")
	var boots_entry := {"slot_type": "boots", "instance_id": "owned-boots-1", "definition": boots}
	var helmet_entry := {"slot_type": "helmet", "instance_id": "owned-helmet-1", "definition": helmet}
	var snapshot = RunLoadoutSnapshotScript.create([boots_entry, helmet_entry], 7)
	_check(snapshot.is_valid(), "valid loadout should produce a valid run snapshot")
	_check(snapshot.get_catalog_version() == 7, "snapshot should record the catalog version")
	_check(snapshot.get_equipped_instance_ids()["boots"] == "owned-boots-1", "snapshot should capture owned instance IDs")
	_check(snapshot.get_resolved_stats()["run_speed_percent"] == 10250, "snapshot should freeze resolved values")
	_check(not snapshot.get_loadout_signature().is_empty(), "snapshot should expose a stable loadout signature")
	var same_loadout = RunLoadoutSnapshotScript.create([
		helmet_entry,
		boots_entry,
	], 7)
	_check(snapshot.get_loadout_signature() == same_loadout.get_loadout_signature(), "same loadout should have a stable signature")
	var mutable_copy: Dictionary = snapshot.get_resolved_stats()
	mutable_copy["run_speed_percent"] = 1
	_check(snapshot.get_resolved_stats()["run_speed_percent"] == 10250, "snapshot getters should not expose mutable internal dictionaries")
	var invalid_snapshot = RunLoadoutSnapshotScript.create([], 0)
	_check(not invalid_snapshot.is_valid(), "snapshot should reject invalid catalog versions")

func _item(item_id: String, slot_type: String, modifiers: Dictionary = {}, rarity: StringName = &"common") -> Resource:
	var definition: Resource = ItemDefinitionScript.new()
	definition.set("item_id", StringName(item_id))
	definition.set("slot_type", StringName(slot_type))
	definition.set("rarity", rarity)
	definition.set("name_key", StringName("ITEM_%s_NAME" % item_id.to_upper()))
	definition.set("description_key", StringName("ITEM_%s_DESCRIPTION" % item_id.to_upper()))
	definition.set("icon_key", StringName(item_id))
	definition.set("stat_modifiers", modifiers)
	return definition

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
