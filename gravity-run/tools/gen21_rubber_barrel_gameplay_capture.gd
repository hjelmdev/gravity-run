extends Node
## Actual main.tscn GPU captures of one generated barrel immediately before
## and after its shared-model bounce. The runner is shown in the safe ceiling lane.

const MainScene := preload("res://main.tscn")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const Generator := preload("res://systems/course_generator.gd")
const OUT_DIR := "res://.codex-gen21-gameplay-captures"

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed_value := 100000007
	var manifest: Resource = Builder.new().build(seed_value, 45000, Generator.GENERATOR_VERSION_21).get("manifest")
	_check(manifest != null, "capture seed builds a Gen21 manifest")
	if manifest == null:
		_finish()
		return
	var rubber_event: Dictionary = {}
	var target_block: Dictionary = {}
	for event in manifest.events:
		if str(event.get("kind", "")) == "barrels" and int(event.get("barrel_variant", 0)) == 1:
			rubber_event = event.duplicate(true)
			break
		if str(event.get("kind", "")) == "block" and absf(float(event.get("x", INF)) - float(rubber_event.get("rubber_target_x", NAN))) < 0.1:
			target_block = event.duplicate(true)
	_check(not rubber_event.is_empty(), "generated seed has a rubber barrel")
	if rubber_event.is_empty():
		_finish()
		return
	var target_x := float(rubber_event.get("rubber_target_x", NAN))
	for event in manifest.events:
		if str(event.get("kind", "")) == "block" and absf(float(event.get("x", INF)) - target_x) < 0.1:
			target_block = event.duplicate(true)
			break
	_check(not target_block.is_empty(), "rubber target block resolves for gameplay capture")
	var world := World.new()
	_check(str(world.configure(manifest)).is_empty(), "shared simulation configures capture manifest")
	var bounce_tick := -1
	var before_state: Dictionary = {}
	var contact_state: Dictionary = {}
	var after_state: Dictionary = {}
	for tick in range(1, 700):
		world.step_to(tick)
		var state := _barrel_for_event(world, str(rubber_event.get("event_id", "")))
		if bounce_tick < 0 and int(state.get("bounce_count", 0)) > 0:
			bounce_tick = tick
			contact_state = state.duplicate(true)
		if bounce_tick > 0 and tick == bounce_tick + 12:
			after_state = state.duplicate(true)
			var before_world := World.new()
			before_world.configure(manifest)
			before_world.step_to(bounce_tick - 8)
			before_state = _barrel_for_event(before_world, str(rubber_event.get("event_id", "")))
			break
	_check(bounce_tick > 0 and not before_state.is_empty() and not contact_state.is_empty() and not after_state.is_empty(), "capture obtains separated before/contact/after states for the same shared barrel")
	if bounce_tick <= 0:
		_finish()
		return
	var spent_world := World.new()
	_check(str(spent_world.configure(manifest)).is_empty(), "a separate canonical world configures the spent-pose capture")
	var spent_tick := bounce_tick
	var spent_state: Dictionary = {}
	for candidate in spent_world.get("barrels"):
		if str(candidate.get("event_id", "")) == str(rubber_event.get("event_id", "")):
			spent_state = candidate
			break
	var block_width := float(target_block.get("width", 48.0))
	var block_height := float(target_block.get("height", 72.0))
	var block_edge_y := float(target_block.get("y", manifest.initial_floor_y))
	var block_rect := Rect2(Vector2(float(target_block.x) - block_width * 0.5, block_edge_y - block_height), Vector2(block_width, block_height))
	var radius := HazardRules.barrel_radius(float(spent_state.get("width", 48.0)), float(spent_state.get("height", 48.0)))
	spent_state["spawned"] = true
	spent_state["bounce_count"] = HazardRules.RUBBER_BARREL_MAX_BOUNCES
	spent_state["travel_direction"] = 1
	spent_state["x"] = block_rect.end.x + radius - 0.5
	spent_state["y"] = block_edge_y
	spent_world.call("_resolve_barrel_interactions", spent_state)
	spent_state = _barrel_for_event(spent_world, str(rubber_event.get("event_id", "")))
	_check(bool(spent_state.get("retired", false)) and not bool(spent_state.get("destroyed", false)), "canonical shared resolver produces the parked visual state at the bounce limit")
	if not bool(spent_state.get("retired", false)):
		_finish()
		return
	var game := MainScene.instantiate() as Node
	game.set("demo_mode", false)
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await get_tree().process_frame
	var definition: Resource = RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", Generator.GENERATOR_VERSION_21)
	definition.set("ruleset", Builder.new().call("_make_multiplayer_ruleset", Generator.GENERATOR_VERSION_21))
	game.set("_active_seed", seed_value)
	game.set("_active_seed_version", Generator.GENERATOR_VERSION_21)
	var generator = game.get("course_generator")
	_check(bool(generator.call("configure_run_definition", definition)), "actual main generator accepts capture run definition")
	var source_distance := float(rubber_event.get("course_distance", target_x - float(manifest.start_x)))
	generator.call("ensure_horizon", source_distance + 1800.0, 500.0)
	var block_for_spawn := target_block.duplicate(true)
	block_for_spawn["course_distance"] = float(target_block.get("x", target_x)) - float(manifest.start_x)
	block_for_spawn["id"] = str(target_block.get("event_id", ""))
	game.call("_spawn_course_event", block_for_spawn)
	var barrel_for_spawn := rubber_event.duplicate(true)
	barrel_for_spawn["course_distance"] = source_distance
	barrel_for_spawn["id"] = str(rubber_event.get("event_id", ""))
	game.call("_spawn_course_event", barrel_for_spawn)
	var barrel_node: Node2D
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("barrels") and bool(obstacle.get("is_rubber")):
			barrel_node = obstacle
			break
	_check(is_instance_valid(barrel_node), "actual main scene spawns the real rubber barrel presentation node")
	if not is_instance_valid(barrel_node):
		game.queue_free()
		_finish()
		return
	var player: Node2D = game.get("player")
	var ceiling_y := float(manifest.initial_ceiling_y)
	var safe_lane_contact := world.surface_at(target_x, true)
	_check(bool(safe_lane_contact.get("supported", false)), "capture uses the supported opposite lane at the bounce")
	var camera = game.get("camera")
	var out_path := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_path)
	for capture in [{"label": "before", "state": before_state, "tick": bounce_tick - 8}, {"label": "contact", "state": contact_state, "tick": bounce_tick}, {"label": "after", "state": after_state, "tick": bounce_tick + 12}, {"label": "spent", "state": spent_state, "tick": spent_tick}]:
		var state: Dictionary = capture.state
		var tick := int(capture.tick)
		var runner_x := float(manifest.start_x) + Motion.BASE_RUN_SPEED * float(tick) / 60.0
		if str(capture.label) == "spent":
			# Keep the parked barrel well inside the view instead of under the left HUD.
			runner_x = float(target_x) - 300.0
		var runner_floor := world.surface_at(runner_x, false)
		var runner_ceiling := world.surface_at(runner_x, true)
		ceiling_y = float(runner_ceiling.get("y", manifest.initial_ceiling_y))
		player.position = Vector2(runner_x, ceiling_y + Motion.SIZE.y * 0.5)
		player.set("world_x", runner_x)
		player.set("gravity_direction", -1)
		player.set("grounded", bool(runner_ceiling.get("supported", false)))
		player.set("vertical_speed", 0.0)
		game.set("course_distance", runner_x - 180.0)
		game.set("_render_course_distance", runner_x - 180.0)
		game.set("_singleplayer_simulation_tick", tick)
		game.set("_render_player_position", player.position)
		barrel_node.set("position", Vector2(float(state.get("x", 0.0)), float(state.get("y", manifest.initial_floor_y))))
		barrel_node.call("apply_shared_barrel_state", {"x": float(state.get("x", 0.0)), "y": float(state.get("y", manifest.initial_floor_y)), "roll_angle": float(state.get("roll_angle", 0.0)), "rotation": float(state.get("rotation", 0.0)), "barrel_variant": 1, "rubber_target_x": target_x, "travel_direction": int(state.get("travel_direction", 1)), "bounce_count": int(state.get("bounce_count", 0)), "bounce_ticks": int(state.get("bounce_ticks", 0)), "retired": bool(state.get("retired", false)), "spawned": true, "destroyed": false})
		game.call("_update_camera")
		game.queue_redraw()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var image_path := out_path.path_join("gen21-rubber-%s-seed-%d.png" % [str(capture.label), seed_value])
		var error := image.save_png(image_path)
		var camera_left := float(game.get("course_distance"))
		var barrel_screen_x := float(state.get("x", 0.0)) - camera_left
		print("GEN21_RUBBER_GPU_CAPTURE phase=%s seed=%d tick=%d runner_x=%.1f runner_lane=ceiling floor_supported=%s barrel_world_x=%.1f barrel_screen_x=%.1f direction=%d bounces=%d retired=%s image=%s size=%s" % [str(capture.label), seed_value, tick, runner_x, str(bool(runner_floor.get("supported", false))), float(state.get("x", 0.0)), barrel_screen_x, int(state.get("travel_direction", 1)), int(state.get("bounce_count", 0)), str(bool(state.get("retired", false))), image_path, str(image.get_size())])
		_check(error == OK, "%s bounce-phase GPU screenshot saved" % str(capture.label))
	game.queue_free()
	await get_tree().process_frame
	await _capture_actual_sp_weather_sequence(seed_value)
	await _capture_offline_mp_weather_and_rubber(seed_value, manifest, bounce_tick)
	var cave_build: Dictionary = Builder.new().build(100000014, 45000, Generator.GENERATOR_VERSION_21)
	var cave_manifest: Resource = cave_build.get("manifest")
	_check(cave_manifest != null, "a separate seed with a cave start builds a Gen21 manifest")
	if cave_manifest != null:
		await _capture_actual_sp_weather_sequence(100000014)
		await _capture_offline_mp_weather_and_rubber(100000014, cave_manifest, -1)
	_finish()

func _capture_actual_sp_weather_sequence(seed_value: int) -> void:
	ChallengeService.call("clear_challenge")
	var selected := bool(ChallengeService.call("start_singleplayer_seed_input", str(seed_value)))
	_check(selected, "SP weather capture selects the real Gen21 seed through ChallengeService")
	if not selected:
		return
	var game := MainScene.instantiate() as Node
	game.set("demo_mode", false)
	add_child(game)
	await get_tree().process_frame
	game.set_physics_process(false)
	var capture_targets := [4200.0, 4808.0, 5008.0]
	var target_index := 0
	var alive := true
	for frame_index in range(720):
		if not is_instance_valid(game) or bool(game.get("game_over")):
			alive = false
			break
		_capture_route_flip(game)
		game.call("_physics_process", 1.0 / 60.0)
		await RenderingServer.frame_post_draw
		var course_distance := float(game.get("course_distance"))
		if target_index < capture_targets.size() and course_distance >= float(capture_targets[target_index]):
			var image := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path(OUT_DIR).path_join("gen21-sp-weather-seed-%d-x%05d.png" % [seed_value, int(round(course_distance))])
			var error := image.save_png(path)
			print("GEN21_SP_WEATHER_GPU seed=%d gen=%d frame=%d target=%.0f actual=%.1f tick=%d camera=%.1f image=%s size=%s" % [int(game.get("_active_seed")), int(game.get("_active_seed_version")), frame_index, float(capture_targets[target_index]), course_distance, int(game.get("_singleplayer_simulation_tick")), float(game.get("_render_course_distance")), path, str(image.get_size())])
			_check(error == OK, "actual SP weather gameplay image saved")
			target_index += 1
			if target_index == capture_targets.size():
				break
	_check(target_index == capture_targets.size(), "actual SP main gameplay reaches each requested biome weather sample before terminal contact")
	if is_instance_valid(game):
		game.queue_free()
	await get_tree().process_frame
	ChallengeService.call("clear_challenge")

func _capture_route_flip(game: Node) -> void:
	var player: Node = game.get("player")
	if not is_instance_valid(player) or not bool(player.get("grounded")):
		return
	var player_x := float(player.get("world_x"))
	var gravity := int(player.call("get_gravity_direction"))
	for obstacle in game.get("obstacles"):
		if not is_instance_valid(obstacle) or not obstacle is Node2D:
			continue
		var from_ceiling := false
		for property in obstacle.get_property_list():
			if str(property.get("name", "")) == "from_ceiling":
				from_ceiling = bool(obstacle.get("from_ceiling"))
				break
		if (gravity < 0) != from_ceiling:
			continue
		var delta_x := float((obstacle as Node2D).global_position.x) - player_x
		if delta_x >= 0.0 and delta_x < 350.0:
			player.call("_try_flip", -gravity, "gen21_capture_route")
			return

func _capture_offline_mp_weather_and_rubber(seed_value: int, manifest: Resource, bounce_tick: int) -> void:
	MultiplayerV2Service.current_manifest = manifest
	MultiplayerV2Service.session = {"round_id": "gen21-offline-visual", "local_peer_id": 1, "role": "host"}
	MultiplayerV2Service._round_coordinator.round_descriptor = {"round_id": "gen21-offline-visual", "players": [{"player_slot": 1, "display_name": "Review Runner", "skin_id": 0}]}
	var match_view := MatchScene.instantiate() as Node2D
	add_child(match_view)
	await get_tree().process_frame
	await get_tree().process_frame
	match_view.set_process(false)
	match_view.set_physics_process(false)
	var local_runner: Object = match_view.get("_runner")
	var world: Object = match_view.get("_world")
	var course_presentation: Node = match_view.get("_course_presentation")
	_check(is_instance_valid(local_runner) and is_instance_valid(world) and is_instance_valid(course_presentation), "offline MP capture initializes the actual match scene, world, runner and shared course presentation")
	if not is_instance_valid(local_runner) or not is_instance_valid(world) or not is_instance_valid(course_presentation):
		match_view.queue_free()
		MultiplayerV2Service.current_manifest = null
		MultiplayerV2Service.session.clear()
		return
	var frozen_roster: Array = match_view.get("_frozen_roster")
	if frozen_roster.is_empty():
		match_view.set("_frozen_roster", [{"player_slot": 1, "display_name": "Review Runner", "skin_id": 0}])
		match_view.call("_build_peer_slots")
	var target_ticks := {501: "weather-haunted", 577: "weather-seam", 601: "weather-after-seam"}
	if bounce_tick > 0:
		target_ticks[bounce_tick - 8] = "rubber-before"
		target_ticks[bounce_tick] = "rubber-contact"
		target_ticks[bounce_tick + 12] = "rubber-after"
	var round_clock = MultiplayerV2Service._round_coordinator.clock
	for sim_tick in range(1, 602):
		_check(bool(world.call("step_to", sim_tick)), "offline MP world advances through canonical shared ticks")
		var runner_x := float(manifest.start_x) + Motion.BASE_RUN_SPEED * float(sim_tick) / 60.0
		var floor_sample: Dictionary = world.call("surface_at", runner_x, false)
		var ceiling_sample: Dictionary = world.call("surface_at", runner_x, true)
		var ceiling_lane := not bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false))
		var support := ceiling_sample if ceiling_lane else floor_sample
		var runner_pose: Dictionary = local_runner.get("player_state")
		runner_pose["world_x"] = runner_x
		runner_pose["y"] = float(support.get("y", manifest.initial_floor_y)) + (Motion.SIZE.y * 0.5 if ceiling_lane else -Motion.SIZE.y * 0.5)
		runner_pose["vertical_speed"] = 0.0
		runner_pose["gravity_direction"] = -1 if ceiling_lane else 1
		runner_pose["grounded"] = bool(support.get("supported", false))
		runner_pose["state"] = "running"
		runner_pose["blocked"] = false
		local_runner.set("player_state", runner_pose.duplicate(true))
		local_runner.set("previous_render_state", runner_pose.duplicate(true))
		local_runner.set("current_render_state", runner_pose.duplicate(true))
		local_runner.set("simulation_tick", sim_tick)
		match_view.set("_world_tick", sim_tick)
		match_view.set("_round_started", true)
		match_view.set("_local_presentation_pose", runner_pose.duplicate(true))
		match_view.set("_camera_left", maxf(runner_x - 180.0, 0.0))
		match_view.set("_previous_camera_left", maxf(runner_x - 180.0, 0.0))
		round_clock.started_at_usec = maxi(Time.get_ticks_usec() - int(round(float(sim_tick) * 1_000_000.0 / 60.0)), 0)
		round_clock.tick = sim_tick
		round_clock.accumulator = 0.0
		match_view.get("_local_pose_history").clear()
		match_view.call("_record_local_pose", sim_tick)
		match_view.call("_process", 0.0)
		course_presentation.call("set_camera_left", maxf(runner_x - 180.0, 0.0))
		course_presentation.call("set_world_state", world.call("render_state", 1.0))
		match_view.call("_sync_player_views")
		match_view.queue_redraw()
		await RenderingServer.frame_post_draw
		if not target_ticks.has(sim_tick):
			continue
		var image := get_viewport().get_texture().get_image()
		var capture_label: String = target_ticks[sim_tick]
		var path := ProjectSettings.globalize_path(OUT_DIR).path_join("gen21-mp-offline-%s-seed-%d.png" % [capture_label, seed_value])
		var error := image.save_png(path)
		_check(error == OK and bool(runner_pose.get("grounded", false)), "offline MP running-state capture saves with a supported runner")
		print("GEN21_MP_GAMEPLAY_GPU mode=offline_match_scene network_connected=false label=%s seed=%d gen=%d tick=%d course_x=%.1f camera_left=%.1f lane=%s supported=%s image=%s size=%s" % [capture_label, seed_value, int(manifest.generator_version), sim_tick, runner_x, maxf(runner_x - 180.0, 0.0), "ceiling" if ceiling_lane else "floor", str(bool(support.get("supported", false))), path, str(image.get_size())])
	match_view.queue_free()
	await get_tree().process_frame
	MultiplayerV2Service.current_manifest = null
	MultiplayerV2Service.session.clear()

func _barrel_for_event(source_world: RefCounted, event_id: String) -> Dictionary:
	for state in source_world.get("barrels"):
		if str(state.get("event_id", "")) == event_id:
			return state.duplicate(true)
	return {}

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _finish() -> void:
	print("GEN21_RUBBER_BARREL_GAMEPLAY_CAPTURE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
