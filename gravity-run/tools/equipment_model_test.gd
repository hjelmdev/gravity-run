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
	_test_effect_items_validate_and_reach_the_snapshot()
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

func _test_effect_items_validate_and_reach_the_snapshot() -> void:
	var bubble := _item("helmet_bubble_test", "helmet")
	bubble.set("effect_id", &"bubble_shield")
	_check(str(bubble.call("validate")).is_empty(), "an allowlisted effect on a helmet should validate")
	bubble.set("effect_level", 4)
	_check(not str(bubble.call("validate")).is_empty(), "effect levels above the maximum should be rejected")
	bubble.set("effect_level", 1)
	bubble.set("effect_id", &"laser_beam")
	_check(not str(bubble.call("validate")).is_empty(), "unknown effect IDs should be rejected")
	var magnet := _item("pack_magnet_test", "backpack")
	magnet.set("effect_id", &"coin_magnet")
	_check(str(magnet.call("validate")).is_empty(), "the coin magnet should validate in the backpack slot")
	var wrong_slot := _item("helmet_magnet_test", "helmet")
	wrong_slot.set("effect_id", &"coin_magnet")
	_check(not str(wrong_slot.call("validate")).is_empty(), "an effect cannot be carried by a slot it does not belong to")
	var plate := _item("helmet_plate_test", "helmet")
	plate.set("effect_id", &"spike_plate")
	plate.set("effect_level", 2)
	var snapshot = RunLoadoutSnapshotScript.create([
		{"slot_type": "backpack", "instance_id": "pack-1", "definition": magnet},
		{"slot_type": "helmet", "instance_id": "helmet-1", "definition": plate},
	], 3, TEST_BASE_STATS)
	_check(snapshot.is_valid(), "helmet plus backpack should resolve into a valid snapshot")
	var effects: Array[Dictionary] = snapshot.get_effects()
	_check(effects.size() == 2 and effects[0].effect_id == "spike_plate" and int(effects[0].level) == 2 and effects[1].effect_id == "coin_magnet", "snapshot should carry effects in slot order")
	_check("effect=spike_plate:2" in snapshot.get_loadout_signature(), "the signature should include effects")
	var plain = RunLoadoutSnapshotScript.create([{"slot_type": "helmet", "instance_id": "h", "definition": _item("plain_helmet", "helmet")}], 3, TEST_BASE_STATS)
	_check(not plain.has_effects() and not "effect=" in plain.get_loadout_signature(), "plain items leave the signature unchanged")
	var from_server: Resource = ItemDefinitionScript.from_catalog_entry({"item_id": "helmet_bubble_01", "slot_type": "helmet", "name_key": "a", "description_key": "b", "icon_key": "c", "effect_id": null, "effect_level": null})
	_check(from_server != null and from_server.effect_id == &"" and str(from_server.call("validate")).is_empty(), "null effect columns from the server mean no effect")
	_check(ItemDefinitionScript.from_catalog_entry({"item_id": "cape", "slot_type": "cape"}) == null, "unknown slot types are skipped")

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
