extends Node
## Effect items in the real multiplayer match scene, stepped tick by tick:
##  - equipment off (or no field): the runner dies at the first lethal contact,
##    no effect state exists;
##  - equipment on with a bubble helmet: the same contact is absorbed, nothing is
##    reported as a terminal, the runner survives past it and the HUD row shows
##    the used bubble; the next hit before the recharge kills as usual;
##  - equipment on without effect items stays clean;
##  - the spike plate ignores spikes right after a flip and nothing else.

const Builder := preload("res://systems/course_manifest_builder.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const RunEffectsScript := preload("res://systems/run_effects.gd")
const MAX_TICKS := 1800

var failures := 0
var _manifest: Resource

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _catalog_entry(item_id: String, slot: String, effect_id: String) -> Dictionary:
	return {"item_id": item_id, "slot_type": slot, "rarity": "rare", "name_key": "item.%s.name" % item_id, "description_key": "item.%s.description" % item_id, "icon_key": item_id, "stat_modifiers": {}, "effect_id": effect_id, "effect_level": 1, "catalog_version": 3}

func _equip(entries: Array[Dictionary]) -> void:
	var items: Array = []
	var equipment := {}
	for entry in entries:
		var instance_id := "owned-%s" % entry.item_id
		items.append({"instance_id": instance_id, "item_id": entry.item_id})
		equipment[entry.slot_type] = instance_id
	InventoryService.inventory_state = {"catalog": entries, "items": items, "equipment": equipment, "wallet_coins": 0}

## A match whose round descriptor carries (or lacks) the equipment flag.
func _make_match(descriptor_extra: Dictionary) -> Node:
	MultiplayerV2Service.current_manifest = _manifest
	MultiplayerV2Service.session = {"role": "host", "round_id": "equipment-match-test", "local_peer_id": 1}
	MultiplayerV2Service.room_state = {"phase": "RUNNING", "room_id": "fixture-room", "lobby_generation": 1, "members": []}
	var descriptor := {"round_id": "equipment-match-test", "players": []}
	descriptor.merge(descriptor_extra, true)
	MultiplayerV2Service._round_coordinator.round_descriptor = descriptor
	var match_node := MatchScene.instantiate()
	add_child(match_node)
	await get_tree().process_frame
	return match_node

## Steps until the local runner is dead; returns the tick it died on (or -1).
func _run_until_dead(match_node: Node, limit: int = MAX_TICKS) -> int:
	for _i in range(limit):
		match_node.call("_step_local_round_impl")
		if str(match_node.get("_runner").player_state.get("state", "")) == "dead":
			return int(match_node.get("_runner").simulation_tick)
	return -1

func _run() -> void:
	var original_state: Dictionary = InventoryService.inventory_state.duplicate(true)
	var built: Dictionary = Builder.new().build(100000014, 12000, 15)
	_manifest = built.get("manifest")
	_check(_manifest != null, "fixture builds a real multiplayer manifest")
	if _manifest == null:
		get_tree().quit(1)
		return
	var bubble := _catalog_entry("helmet_bubble_01", "helmet", "bubble_shield")
	var plate := _catalog_entry("helmet_spikeplate_01", "helmet", "spike_plate")

	_equip([bubble])
	var off_match := await _make_match({})
	_check(not bool(off_match.get("_effects_active")) and off_match.get("_run_effects") == null, "no flag: no effect state exists even with a bubble helmet equipped")
	_check(not bool(off_match.call("is_run_modified")), "no flag: the run is not modified")
	var clean_death: int = _run_until_dead(off_match)
	_check(clean_death > 0, "no flag: the straight-running runner dies at a hazard (tick %d)" % clean_death)
	off_match.queue_free()
	await get_tree().process_frame

	var off_flag_match := await _make_match({"equipment_enabled": false})
	_check(not bool(off_flag_match.get("_effects_active")), "flag false: effects stay off")
	var off_flag_death: int = _run_until_dead(off_flag_match)
	_check(off_flag_death == clean_death, "flag false: identical death tick to a round without the field (%d)" % off_flag_death)
	off_flag_match.queue_free()
	await get_tree().process_frame

	var on_match := await _make_match({"equipment_enabled": true})
	_check(bool(on_match.get("_effects_active")) and bool(on_match.call("is_run_modified")), "flag on with a bubble helmet: effects active and the run is modified")
	var row: Control = on_match.get("_effect_row")
	_check(is_instance_valid(row) and int(row.call("entry_count")) == 1, "the HUD row shows one effect slot")
	var absorbed_before := _count_events(on_match, "effect_absorbed_contact")
	var on_death: int = _run_until_dead(on_match)
	var absorbed := _count_events(on_match, "effect_absorbed_contact") - absorbed_before
	_check(absorbed >= 1, "the bubble absorbed the first lethal contact (%d absorptions)" % absorbed)
	_check(on_death > clean_death, "the bubble run survives past the clean death tick (%d > %d)" % [on_death, clean_death])
	var entry: Dictionary = on_match.get("_run_effects").get_hud_entries()[0]
	_check(not bool(entry.ready) and float(entry.charge) < 1.0, "the used bubble is recharging in the HUD")
	on_match.queue_free()
	await get_tree().process_frame

	_equip([])
	var empty_match := await _make_match({"equipment_enabled": true})
	_check(not bool(empty_match.get("_effects_active")), "flag on without effect items stays clean")
	_check(_run_until_dead(empty_match) == clean_death, "flag on without effect items dies exactly like a clean round")
	empty_match.queue_free()
	await get_tree().process_frame

	_equip([plate])
	var plate_match := await _make_match({"equipment_enabled": true})
	_check(bool(plate_match.get("_effects_active")), "spike plate round is active")
	var effects: RefCounted = plate_match.get("_run_effects")
	var spikes := {"kind": "terminal", "reason": "spikes", "entity_id": "x"}
	var saw := {"kind": "terminal", "reason": "saw_blade", "entity_id": "y"}
	_check(not bool(plate_match.call("_effects_absorb_contact", spikes)), "spikes kill without a recent flip")
	effects.on_flip()
	_check(bool(plate_match.call("_effects_absorb_contact", spikes)), "spikes are ignored right after a flip")
	_check(not bool(plate_match.call("_effects_absorb_contact", saw)), "the plate does not help against other hazards")
	plate_match.queue_free()
	await get_tree().process_frame

	InventoryService.inventory_state = original_state
	print("EQUIPMENT_MATCH_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _count_events(_match_node: Node, event_name: String) -> int:
	var count := 0
	for event in MultiplayerV2Service.diagnostics.events:
		if str(event.get("name", "")) == event_name:
			count += 1
	return count
