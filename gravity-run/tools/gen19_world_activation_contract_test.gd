extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const GhostScene := preload("res://hazards/ghost_hazard.tscn")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var selected: Dictionary = {}
	for seed_value in range(100000001, 100000081):
		var built: Dictionary = Builder.new().build(seed_value, 45000, 19)
		var manifest: Variant = built.get("manifest")
		if manifest == null:
			continue
		for event in manifest.events:
			if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3:
				selected = {"seed": seed_value, "manifest": manifest, "event": event}
				break
		if not selected.is_empty():
			break
	_check(not selected.is_empty(), "bounded Gen19 course contains a shared pursuit")
	if selected.is_empty():
		quit(1)
		return
	var manifest: Resource = selected.manifest
	var event: Dictionary = selected.event
	var event_id := str(event.get("event_id", ""))
	var trigger_x := GhostModel.trigger_x(event)
	var world := World.new()
	_check(str(world.configure(manifest)).is_empty(), "actual shared world accepts the selected Gen19 manifest")
	var commit := _activation_commit(event_id, 1, 12, 2, trigger_x, 500.0, 7)
	_check(str(world.apply_world_commit(commit)) == "applied", "authoritative pursuit activation is committed once")
	_check(str(world.apply_world_commit(commit)) == "duplicate", "replayed activation commit is idempotent")
	for tick in range(1, 100):
		_check(world.step_to(tick), "shared world advances through pursuit danger")
	var entity: Dictionary = world.entity_ledger.entities.get(event_id, {})
	_check(int(entity.get("ghost_activation_tick", -1)) == 12 and int(entity.get("ghost_activation_lane", 0)) == 2 and int(entity.get("ghost_target_peer_id", 0)) == 7, "committed lane, tick and target remain immutable in the world ledger")
	var hash_before := world.state_hash()
	var baseline: Dictionary = world.entity_ledger.baseline()
	_check(int(baseline.get("baseline_format_version", -1)) == 4, "activated snapshot is carried by baseline format 4")
	var restored := World.new()
	var restored_configured := str(restored.configure(manifest)).is_empty()
	for tick in range(1, world.tick + 1):
		restored.step_to(tick)
	_check(restored_configured and restored.apply_baseline(baseline), "active pursuit baseline restores into the same manifest and simulation tick")
	_check(restored.state_hash() == hash_before, "baseline restore preserves activation snapshot and entity-state hash")
	var restored_entity: Dictionary = restored.entity_ledger.entities.get(event_id, {})
	_check(int(restored_entity.get("ghost_activation_lane", 0)) == 2 and int(restored_entity.get("ghost_target_peer_id", 0)) == 7, "reconnect baseline cannot retarget the ghost")
	var service := Service.new()
	service.set("world_simulation", world)
	service.set("_validated_motion_history", {1: [{"simulation_tick": world.tick, "world_x": trigger_x + 30.0, "velocity_x": 500.0, "gravity_direction": -1, "grounded": true, "locomotion_state": "running"}]})
	service.set("terminal_status", {})
	var coordinator: Object = service.get("_round_coordinator")
	coordinator.set("round_descriptor", {"players": [{"player_slot": 1}, {"player_slot": 2}]})
	var proposed := {"simulation_tick": world.tick, "world_x": trigger_x + 30.0, "velocity_x": 500.0, "gravity_direction": 1, "grounded": true, "locomotion_state": "running"}
	var selected_target: Dictionary = service.call("_select_ghost_flyby_target", event, 2, proposed)
	_check(int(selected_target.get("peer_id", 0)) == 1 and int(selected_target.get("lane", 0)) == 2, "host's validated participant tie-break is stable by peer ID")
	var conflict := _activation_commit(event_id, 2, 12, 1, trigger_x, 250.0, 1)
	_check(str(world.apply_world_commit(conflict)) == "ghost_already_activated" and world.state_hash() == hash_before, "later conflicting activation cannot replace the winner snapshot")
	var bad_world := World.new()
	bad_world.configure(manifest)
	var invalid := {"world_revision": 1, "commit_id": "bad-ghost-snapshot", "entity_id": event_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": 12, "ghost_activation_tick": 12, "state_before": "active", "state_after": "active"}
	_check(str(bad_world.apply_world_commit(invalid)) == "invalid_ghost_snapshot" and bad_world.entity_ledger.revision == 0, "missing target snapshot is rejected atomically")
	var rendered: Array = world.render_state(0.0).get("ghosts", [])
	var ghost_row: Dictionary = {}
	for row in rendered:
		if str(row.get("event_id", "")) == event_id:
			ghost_row = row
	var node := GhostScene.instantiate()
	root.add_child(node)
	node.call("configure", event)
	_check(not ghost_row.is_empty(), "shared world render state includes the activated pursuit")
	if not ghost_row.is_empty():
		node.call("apply_world_state", {"state": ghost_row.state})
		_check(node.global_position.distance_to(Vector2(float(ghost_row.state.x), float(ghost_row.state.y))) < 0.01, "shared GhostHazard scene follows authoritative rendered pose")
		var altered: Dictionary = ghost_row.state.duplicate(true)
		altered.lane = 1
		altered.target_peer_id = 1
		node.call("apply_world_state", {"state": altered})
		_check(int(node.get("activation_state").get("lane", 0)) == 2 and int(node.get("activation_state").get("target_peer_id", 0)) == 7, "conflicting same-tick presentation snapshot is ignored")
	var unactivated := GhostScene.instantiate()
	root.add_child(unactivated)
	unactivated.call("configure", event)
	unactivated.call("apply_world_state", {"state": {"activation_tick": 12, "tick": 12, "phase": GhostModel.WARNING}})
	_check(int(unactivated.get("activation_tick")) == -1, "malformed presentation cannot activate variant 3 without its snapshot")
	service.free()
	print("GEN19_WORLD_ACTIVATION_TEST seed=%d event=%s tick=12 target_peer=7 baseline=%d failures=%d" % [int(selected.seed), event_id, baseline.size(), failures])
	quit(1 if failures > 0 else 0)

func _activation_commit(event_id: String, revision: int, tick: int, lane: int, world_x: float, speed: float, target_peer: int) -> Dictionary:
	return {"world_revision": revision, "commit_id": "ghost-activation-%d" % revision, "entity_id": event_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": tick, "ghost_activation_tick": tick, "ghost_activation_lane": lane, "ghost_activation_world_x": world_x, "ghost_activation_speed": speed, "ghost_target_peer_id": target_peer, "state_before": "active", "state_after": "active"}

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("GEN19_WORLD_ACTIVATION_TEST: " + message)
