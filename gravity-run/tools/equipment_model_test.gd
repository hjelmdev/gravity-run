extends SceneTree
## Run with: godot --headless --path . --script res://tools/equipment_model_test.gd

const ItemDefinitionScript := preload("res://systems/item_definition.gd")
const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")
const RunLoadoutSnapshotScript := preload("res://systems/run_loadout_snapshot.gd")
const CharacterStatsScript := preload("res://systems/character_stats.gd")
const TEST_BASE_STATS := {"run_speed_percent": 10000, "flip_cooldown_percent": 10000}

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_empty_and_neutral_loadouts()
	_test_modifiers_are_summed_deterministically()
	_test_invalid_modifiers_and_slots_are_rejected()
	_test_snapshot_is_stable_and_returns_copies()
	await _test_player_uses_snapshot_cooldown()
	await _test_player_falls_away_from_stepped_surfaces()
	if failures == 0:
		print("Equipment model tests passed.")
	quit(1 if failures > 0 else 0)

func _test_empty_and_neutral_loadouts() -> void:
	var empty_result: Dictionary = EquipmentStatsScript.resolve([], TEST_BASE_STATS)
	_check(bool(empty_result.valid), "an empty loadout should resolve")
	_check(empty_result.totals == TEST_BASE_STATS, "an empty loadout should preserve character profile base stats")
	var helmet := _item("cap_canvas", "helmet")
	var boots := _item("boots_canvas", "boots")
	var result: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "boots-1", "definition": boots},
		{"slot_type": "helmet", "instance_id": "helmet-1", "definition": helmet},
	], TEST_BASE_STATS)
	_check(bool(result.valid), "neutral helmet and boots should resolve")
	_check(result.bonuses["run_speed_percent"] == 0, "neutral items should not claim a speed bonus")
	_check(result.bonuses["flip_cooldown_percent"] == 0, "neutral items should not claim a cooldown bonus")

func _test_modifiers_are_summed_deterministically() -> void:
	var helmet := _item("cap_test", "helmet", {"run_speed_percent": 50})
	var boots := _item("boots_test", "boots", {"run_speed_percent": 100, "flip_cooldown_percent": -100})
	var helmet_entry := {"slot_type": "helmet", "instance_id": "h-1", "definition": helmet}
	var boots_entry := {"slot_type": "boots", "instance_id": "b-1", "definition": boots}
	var first: Dictionary = EquipmentStatsScript.resolve([helmet_entry, boots_entry], TEST_BASE_STATS)
	var reversed: Dictionary = EquipmentStatsScript.resolve([boots_entry, helmet_entry], TEST_BASE_STATS)
	_check(bool(first.valid), "valid fixture bonuses should resolve")
	_check(first.bonuses["run_speed_percent"] == 150, "speed bonuses should add as integer basis points")
	_check(first.totals["run_speed_percent"] == 10150, "speed total should include the base 100 percent")
	_check(first.totals["flip_cooldown_percent"] == 9900, "negative cooldown modifier should reduce its multiplier")
	_check(first.totals == reversed.totals, "input item order should not change resolved stats")
	_check(first.sources["run_speed_percent"].size() == 2, "resolver should expose each stat source")

func _test_invalid_modifiers_and_slots_are_rejected() -> void:
	_check(not str(_item("unknown_stat", "boots", {"speed": 500}).call("validate")).is_empty(), "unknown stat IDs should be rejected")
	_check(not str(_item("float_stat", "boots", {"run_speed_percent": 1.5}).call("validate")).is_empty(), "fractional modifiers should be rejected")
	_check(str(_item("json_integer_stat", "boots", JSON.parse_string('{"run_speed_percent":100.0}')).call("validate")).is_empty(), "integral JSON floats should be accepted as basis points")
	_check(not str(_item("large_stat", "boots", {"run_speed_percent": 400}).call("validate")).is_empty(), "out-of-range modifiers should be rejected")
	var wrong_slot := _item("helmet_item", "helmet")
	var mismatch: Dictionary = EquipmentStatsScript.resolve([{"slot_type": "boots", "instance_id": "h-1", "definition": wrong_slot}], TEST_BASE_STATS)
	_check(not bool(mismatch.valid), "an item cannot be equipped in a different slot")
	var duplicate: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "b-1", "definition": _item("boots_one", "boots")},
		{"slot_type": "boots", "instance_id": "b-2", "definition": _item("boots_two", "boots")},
	], TEST_BASE_STATS)
	_check(not bool(duplicate.valid), "a slot cannot contain two equipped items")
	var duplicate_instance: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "same-instance", "definition": _item("boots_instance", "boots")},
		{"slot_type": "helmet", "instance_id": "same-instance", "definition": _item("helmet_instance", "helmet")},
	], TEST_BASE_STATS)
	_check(not bool(duplicate_instance.valid), "one owned instance cannot occupy multiple slots")
	var fast_boots := _item("fast_boots", "boots", {"run_speed_percent": 300})
	var fast_helmet := _item("fast_helmet", "helmet", {"run_speed_percent": 300})
	var bounded: Dictionary = EquipmentStatsScript.resolve([
		{"slot_type": "boots", "instance_id": "fast-1", "definition": fast_boots},
		{"slot_type": "helmet", "instance_id": "fast-2", "definition": fast_helmet},
	], TEST_BASE_STATS)
	_check(bool(bounded.valid), "the combined equipment bonus should respect the global ceiling")
	var exceeded_base := TEST_BASE_STATS.duplicate(true)
	exceeded_base["run_speed_percent"] = 10400
	var exceeded := EquipmentStatsScript.resolve([{"slot_type": "boots", "instance_id": "fast-3", "definition": fast_boots}], exceeded_base)
	_check(not bool(exceeded.valid), "resolved stats outside global bounds should be rejected")

func _test_snapshot_is_stable_and_returns_copies() -> void:
	var boots := _item("boots_snapshot", "boots", {"run_speed_percent": 250})
	var helmet := _item("helmet_snapshot", "helmet")
	var boots_entry := {"slot_type": "boots", "instance_id": "owned-boots-1", "definition": boots}
	var helmet_entry := {"slot_type": "helmet", "instance_id": "owned-helmet-1", "definition": helmet}
	var snapshot = RunLoadoutSnapshotScript.create([boots_entry, helmet_entry], 7, TEST_BASE_STATS)
	_check(snapshot.is_valid(), "valid loadout should produce a valid run snapshot")
	_check(snapshot.get_catalog_version() == 7, "snapshot should record the catalog version")
	_check(snapshot.get_equipped_instance_ids()["boots"] == "owned-boots-1", "snapshot should capture owned instance IDs")
	_check(snapshot.get_resolved_stats()["run_speed_percent"] == 10250, "snapshot should freeze resolved values")
	_check(not snapshot.get_loadout_signature().is_empty(), "snapshot should expose a stable loadout signature")
	var same_loadout = RunLoadoutSnapshotScript.create([
		helmet_entry,
		boots_entry,
	], 7, TEST_BASE_STATS)
	_check(snapshot.get_loadout_signature() == same_loadout.get_loadout_signature(), "same loadout should have a stable signature")
	var mutable_copy: Dictionary = snapshot.get_resolved_stats()
	mutable_copy["run_speed_percent"] = 1
	_check(snapshot.get_resolved_stats()["run_speed_percent"] == 10250, "snapshot getters should not expose mutable internal dictionaries")
	var invalid_snapshot = RunLoadoutSnapshotScript.create([], 0, TEST_BASE_STATS)
	_check(not invalid_snapshot.is_valid(), "snapshot should reject invalid catalog versions")
	_check(is_equal_approx(float(snapshot.get_resolved_stats()["run_speed_percent"]) / 10000.0, 1.025), "a +2.5% loadout should resolve to a 1.025 speed multiplier")

func _test_player_uses_snapshot_cooldown() -> void:
	var boots := _item("boots_gravity_test", "boots", {"flip_cooldown_percent": -300})
	var character_profile: Resource = CharacterStatsScript.new()
	var snapshot = RunLoadoutSnapshotScript.create([{"slot_type": "boots", "instance_id": "gravity-boots-1", "definition": boots}], 1, character_profile.call("get_base_stats"))
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player := player_scene.instantiate()
	root.add_child(player)
	await process_frame
	player.call("reset_to_floor", 400.0)
	player.call("set_loadout_snapshot", snapshot)
	player.call("_try_flip", -1)
	_check(is_equal_approx(float(player.get("cooldown_left")), 0.42 * 0.97), "gravity boots should reduce the flip cooldown by 3 percent")
	player.queue_free()

func _test_player_falls_away_from_stepped_surfaces() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player := player_scene.instantiate()
	root.add_child(player)
	await process_frame
	player.call("reset_to_floor", 400.0)
	player.call("advance", 0.1, 500.0, 80.0, true, true)
	_check(not bool(player.get("grounded")), "a floor that drops away should release the runner into a downward fall")
	_check(float(player.position.y) > 378.0 and float(player.position.y) < 478.0, "the downward drop should use gravity instead of snapping to the lower floor")
	player.call("reset_to_floor", 400.0)
	player.set("gravity_direction", -1)
	player.set("grounded", true)
	player.position.y = 102.0
	player.call("advance", 0.1, 400.0, 0.0, true, true)
	_check(not bool(player.get("grounded")), "a ceiling that rises away should release the runner into an upward fall")
	_check(float(player.position.y) < 102.0 and float(player.position.y) > 22.0, "the upward drop should use gravity instead of snapping to the higher ceiling")
	player.queue_free()

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
