extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const MainScene := preload("res://main.tscn")

const TEST_SEED := 100000030
const TEST_ACTIVATION_TICK := 120

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(TEST_SEED, 45000, Generator.GENERATOR_VERSION)
	var manifest: Resource = built.get("manifest")
	_check(manifest != null, "Gen19 test manifest builds")
	if manifest == null:
		_finish()
		return
	var event: Dictionary = {}
	for candidate in manifest.events:
		if str(candidate.get("kind", "")) == "ghost" and int(candidate.get("ghost_variant", 0)) == 3:
			event = candidate
			break
	_check(not event.is_empty(), "selected seed contains a moving Gen19 pursuit ghost")
	if event.is_empty():
		_finish()
		return

	_check_sp_shared_scene(event)
	_check_world_render_contract(manifest, event)
	_check_actual_main_adapter(event)
	_finish()

func _activation(event: Dictionary) -> Dictionary:
	return {"activation_tick": TEST_ACTIVATION_TICK, "lane": 1, "world_x": 12000.0, "speed": 500.0, "target_peer_id": 1}

func _check_sp_shared_scene(event: Dictionary) -> void:
	var ghost := GhostScene.instantiate() as Node2D
	add_child(ghost)
	ghost.call("configure", event)
	ghost.call("set_activation_snapshot", _activation(event))
	var sim_tick := TEST_ACTIVATION_TICK + int(event.get("warning_ticks", 90)) + 4
	ghost.call("set_simulation_tick", sim_tick)
	var authoritative_hitbox: Rect2 = ghost.call("get_hitbox_rect")
	var previous_x := -INF
	for fraction in [0.0, 0.125, 0.5, 0.875, 1.0]:
		var render_tick := float(sim_tick - 1) + float(fraction)
		ghost.call("set_presentation_tick", render_tick)
		var expected: Vector2 = GhostModel.center_for_activation(event, TEST_ACTIVATION_TICK, render_tick, _activation(event))
		var actual: Vector2 = ghost.global_position
		_check(actual.distance_to(expected) < 0.001, "SP presentation pose samples the same fractional tick as runner/camera")
		_check(actual.x >= previous_x, "SP ghost render X is monotonic across fractional frames")
		previous_x = actual.x
		_check(ghost.call("get_hitbox_rect") == authoritative_hitbox, "fractional render pose never changes tick-authoritative collision")
	_check(str(ghost.get("phase")) == GhostModel.DANGEROUS, "render sampling does not mutate authoritative phase")
	_check(str(ghost.get("_presentation_phase")) == GhostModel.DANGEROUS, "danger presentation uses the same fractional phase clock")
	ghost.queue_free()

func _check_world_render_contract(manifest: Resource, event: Dictionary) -> void:
	var world = WorldSimulation.new()
	_check(str(world.configure(manifest)).is_empty(), "MP world simulation configures the same manifest")
	var entity_id := str(event.get("event_id", ""))
	var entity: Dictionary = world.entity_ledger.entities.get(entity_id, {}).duplicate(true)
	entity["ghost_activation_tick"] = TEST_ACTIVATION_TICK
	entity["ghost_activation_lane"] = 1
	entity["ghost_activation_world_x"] = 12000.0
	entity["ghost_activation_speed"] = 500.0
	entity["ghost_target_peer_id"] = 1
	world.entity_ledger.entities[entity_id] = entity
	world.tick = TEST_ACTIVATION_TICK + int(event.get("warning_ticks", 90))
	var rendered: Dictionary = world.render_state(0.5)
	var found_state: Dictionary = {}
	for row in rendered.get("ghosts", []):
		if str(row.get("event_id", "")) == entity_id:
			found_state = row.get("state", {})
			break
	_check(not found_state.is_empty(), "MP world render state includes the generated ghost")
	_check(float(found_state.get("render_tick", -99.0)) == float(world.tick - 1) + 0.5, "MP ghost carries the same delayed shared-clock fraction as other rendered hazards")
	var ghost := GhostScene.instantiate() as Node2D
	add_child(ghost)
	ghost.call("configure", event)
	ghost.call("apply_world_state", found_state)
	var expected: Vector2 = GhostModel.center_for_activation(event, TEST_ACTIVATION_TICK, float(found_state.render_tick), {"lane": 1, "world_x": 12000.0, "speed": 500.0, "target_peer_id": 1})
	_check(ghost.global_position.distance_to(expected) < 0.001, "shared MP scene consumes fractional state without moving its authoritative hitbox")
	var sim_hitbox: Rect2 = GhostModel.hitbox(event, world.tick, TEST_ACTIVATION_TICK, {"lane": 1, "world_x": 12000.0, "speed": 500.0, "target_peer_id": 1})
	_check(ghost.call("get_hitbox_rect") == sim_hitbox, "MP collision remains tied to integer world tick")
	ghost.queue_free()
	world = null

func _check_actual_main_adapter(event: Dictionary) -> void:
	var game := MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var ghost := GhostScene.instantiate() as Node2D
	game.add_child(ghost)
	ghost.call("configure", event)
	ghost.call("set_activation_snapshot", _activation(event))
	var sim_tick := TEST_ACTIVATION_TICK + int(event.get("warning_ticks", 90)) + 4
	ghost.call("set_simulation_tick", sim_tick)
	(game.get("obstacles") as Array).append(ghost)
	game.set("_singleplayer_simulation_tick", sim_tick)
	var fraction := 0.375
	game.call("_update_ghost_presentation", fraction)
	var render_tick := float(sim_tick - 1) + fraction
	var expected: Vector2 = GhostModel.center_for_activation(event, TEST_ACTIVATION_TICK, render_tick, _activation(event))
	_check(ghost.global_position.distance_to(expected) < 0.001, "actual main scene uses the SP camera/runner render interpolation fraction for the shared ghost node")
	var authoritative_hitbox: Rect2 = ghost.call("get_hitbox_rect")
	game.call("_update_ghost_presentation", 0.875)
	_check(ghost.call("get_hitbox_rect") == authoritative_hitbox, "actual main render callbacks cannot alter contact state")
	game.queue_free()
	await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GHOST_RENDER_INTERPOLATION: " + message)

func _finish() -> void:
	print("GHOST_RENDER_INTERPOLATION failures=%d seed=%d" % [failures.size(), TEST_SEED])
	get_tree().quit(1 if failures.size() > 0 else 0)
