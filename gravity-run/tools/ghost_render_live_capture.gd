extends Node
## Bounded, non-headless capture of the actual main scene's render callback.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const MainScene := preload("res://main.tscn")
const SEED := 100000030
const RUN_SECONDS := 2.2
const MAX_RECORDS := 1200

var failures: Array[String] = []
var _game: Node
var _ghost: Node2D
var _records: Array[Dictionary] = []
var _mode := ""
var _mode_start_usec := 0
var _capture_active := false
var _uneven_index := 0
var _reported_game_over := false
var _flipped_to_safe_lane := false

func _ready() -> void:
	process_priority = 1000
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = 60
	for config in [{"name": "fps60", "max_fps": 60}, {"name": "fps240", "max_fps": 240}, {"name": "uneven", "max_fps": 0}]:
		await _begin_mode(config)
		if _game == null:
			continue
		_mode = str(config.name)
		_records.clear()
		_capture_active = true
		_mode_start_usec = Time.get_ticks_usec()
		while Time.get_ticks_usec() - _mode_start_usec < int(RUN_SECONDS * 1_000_000.0):
			await get_tree().process_frame
			if _ghost == null or not is_instance_valid(_ghost):
				break
			if _mode == "uneven":
				OS.delay_usec(7000 if _uneven_index % 2 == 0 else 20000)
				_uneven_index += 1
		_capture_active = false
		await RenderingServer.frame_post_draw
		_save_mode_capture(str(config.name))
		_game.queue_free()
		_game = null
		_ghost = null
		await get_tree().process_frame
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	print("GHOST_RENDER_LIVE_CAPTURE failures=%d seed=%d output=%s" % [failures.size(), SEED, ProjectSettings.globalize_path("res://.codex-ghost-render-review")])
	get_tree().quit(1 if failures.size() > 0 else 0)

func _begin_mode(config: Dictionary) -> void:
	_reported_game_over = false
	_flipped_to_safe_lane = false
	Engine.time_scale = 1.0
	Engine.max_fps = int(config.max_fps)
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	challenge.call("clear_challenge")
	if not bool(challenge.call("start_singleplayer_seed_input", str(SEED))):
		_fail("could not set challenge seed")
		return
	_game = MainScene.instantiate()
	add_child(_game)
	await get_tree().process_frame
	if not is_instance_valid(_game.get("player")):
		_fail("main scene has no runner")
		return
	var generator: Object = _game.get("course_generator")
	generator.call("ensure_horizon", 50000.0, 500.0, float(_game.get("screen_height")), 820.0)
	var selected: Dictionary = {}
	for event in generator.call("get_planned_events"):
		if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3:
			selected = event
			break
	if selected.is_empty():
		_fail("selected Gen19 seed contains no moving pursuit ghost")
		return
	for obstacle in _game.get("obstacles").duplicate():
		if is_instance_valid(obstacle): obstacle.queue_free()
	_game.get("obstacles").clear()
	for terrain in _game.get("slopes").duplicate():
		if is_instance_valid(terrain): terrain.queue_free()
	_game.get("slopes").clear()
	for gap in _game.get("gaps").duplicate():
		if is_instance_valid(gap): gap.queue_free()
	_game.get("gaps").clear()
	_game.set("floor_level_y", 460.0)
	_game.set("ceiling_level_y", 80.0)
	_game.set("planned_floor_level_y", 460.0)
	_game.set("planned_ceiling_level_y", 80.0)
	var isolated_events: Array = generator.get("_events")
	isolated_events.clear()
	isolated_events.append(selected.duplicate(true))
	generator.set("_events", isolated_events)
	generator.set("_next_spawn_index", 1)
	generator.set("_configuration_failed", true)
	if (generator.call("get_planned_events") as Array).size() != 1:
		_fail("capture fixture failed to isolate generated event list")
		return
	var player: Node = _game.get("player")
	var key := str(_game.call("_singleplayer_ghost_key", selected))
	(_game.get("_spawned_early_ghost_ids") as Dictionary)[key] = true
	_game.call("_spawn_course_event", selected)
	for obstacle in _game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards"):
			_ghost = obstacle
			break
	if _ghost == null:
		_fail("actual main scene adapter did not spawn the selected ghost")
		return
	# Generator events carry course_distance before the SP adapter resolves their
	# absolute world x. Start against the actual shared-scene event contract.
	var actual_event: Dictionary = _ghost.get("event")
	var trigger_x := GhostModel.trigger_x(actual_event)
	player.set("world_x", trigger_x - 20.0)
	player.position = Vector2(trigger_x - 20.0, 438.0)
	_game.set("course_distance", trigger_x - 20.0 - 180.0)
	_game.set("_render_player_position", player.position)
	_game.get("_presentation").call("reset", player.position)
	_game.call("_update_camera")

func _process(_delta: float) -> void:
	if not _capture_active or not is_instance_valid(_game) or not is_instance_valid(_ghost) or _records.size() >= MAX_RECORDS:
		return
	var tick := int(_game.get("_singleplayer_simulation_tick"))
	var fraction := float(_game.get("_render_interpolation_fraction"))
	var render_tick := float(_ghost.get("_presentation_tick"))
	var player_render: Vector2 = _game.get("_render_player_position")
	var player: Node = _game.get("player")
	var activation_tick := int(_ghost.get("activation_tick"))
	if activation_tick >= 0 and not _flipped_to_safe_lane and tick >= activation_tick + 12 and bool(player.get("grounded")):
		var lane := int((_ghost.get("activation_state") as Dictionary).get("lane", 0))
		var target_gravity := -1 if lane == 1 else 1
		player.call("_try_flip", target_gravity, "ghost_render_capture_reaction")
		_flipped_to_safe_lane = int(player.call("get_gravity_direction")) == target_gravity
	var canvas: Transform2D = _game.get_viewport().get_canvas_transform()
	var ghost_screen := canvas * _ghost.global_position
	var runner_screen := canvas * player_render
	if bool(_game.get("game_over")) and not _reported_game_over:
		_reported_game_over = true
		var obstacle_rows: Array[String] = []
		for obstacle in _game.get("obstacles"):
			if is_instance_valid(obstacle):
				var obstacle_event: Variant = obstacle.get("event")
				var hitbox: Rect2 = obstacle.call("get_hitbox_rect") if obstacle.has_method("get_hitbox_rect") else Rect2()
				obstacle_rows.append("%s groups=%s pos=%s phase=%s hitbox=%s event=%s" % [obstacle.name, str(obstacle.get_groups()), str(obstacle.global_position), str(obstacle.get("phase")), str(hitbox), JSON.stringify(obstacle_event) if obstacle_event is Dictionary else ""])
		print("GHOST_RENDER_CAPTURE_GAME_OVER mode=%s tick=%d y=%f v=%f grounded=%s nodes=%s" % [_mode, tick, float(player.position.y), float(player.get("vertical_speed")), str(bool(player.get("grounded"))), str(obstacle_rows)])
	_records.append({"at_usec": Time.get_ticks_usec(), "mode": _mode, "simulation_tick": tick, "physics_fraction": fraction, "presentation_tick": render_tick, "phase": str(_ghost.get("phase")), "presentation_phase": str(_ghost.get("_presentation_phase")), "game_over": bool(_game.get("game_over")), "player_y": float(player.position.y), "player_vertical_speed": float(player.get("vertical_speed")), "player_grounded": bool(player.get("grounded")), "ghost_world_x": _ghost.global_position.x, "runner_render_world_x": player_render.x, "relative_world_x": _ghost.global_position.x - player_render.x, "ghost_screen_x": ghost_screen.x, "runner_screen_x": runner_screen.x, "relative_screen_x": ghost_screen.x - runner_screen.x, "camera_world_x": float(_game.get("camera").global_position.x), "camera_transform_x": canvas.x.x, "camera_transform_origin_x": canvas.origin.x})

func _save_mode_capture(mode_name: String) -> void:
	var output_dir := ProjectSettings.globalize_path("res://.codex-ghost-render-review")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var presentation_monotonic := true
	var danger_relative_monotonic := true
	var same_tick_pairs := 0
	var same_tick_relative_screen_deltas: Array[float] = []
	var prior_tick := -1
	var prior_render_tick := -INF
	var prior_relative := -INF
	for row_index in range(_records.size()):
		var row: Dictionary = _records[row_index]
		var render_tick := float(row.presentation_tick)
		var relative := float(row.relative_world_x)
		if render_tick + 0.0001 < prior_render_tick:
			presentation_monotonic = false
		if int(row.simulation_tick) == prior_tick:
			same_tick_pairs += 1
			same_tick_relative_screen_deltas.append(float(row.relative_screen_x) - float(_records[row_index - 1].relative_screen_x))
		if str(row.phase) == GhostModel.DANGEROUS and relative + 0.05 < prior_relative:
			danger_relative_monotonic = false
		if str(row.phase) == GhostModel.DANGEROUS:
			prior_relative = relative
		prior_tick = int(row.simulation_tick)
		prior_render_tick = render_tick
	var frequencies: Array[float] = []
	var observed_phases: Dictionary = {}
	for index in range(1, _records.size()):
		frequencies.append(1_000_000.0 / maxf(float(_records[index].at_usec) - float(_records[index - 1].at_usec), 1.0))
		observed_phases[str(_records[index].phase)] = true
	var image := _game.get_viewport().get_texture().get_image()
	var image_path := output_dir.path_join("gen19-ghost-%s.png" % mode_name)
	var image_error := image.save_png(image_path)
	if image_error != OK:
		_fail("GPU capture failed for %s: %d" % [mode_name, image_error])
	same_tick_relative_screen_deltas.sort()
	var same_tick_median: float = same_tick_relative_screen_deltas[same_tick_relative_screen_deltas.size() / 2] if not same_tick_relative_screen_deltas.is_empty() else 0.0
	var same_tick_min: float = same_tick_relative_screen_deltas.front() if not same_tick_relative_screen_deltas.is_empty() else 0.0
	var report := {"mode": mode_name, "seed": SEED, "render_records": _records, "record_count": _records.size(), "observed_phases": observed_phases, "same_simulation_tick_pairs": same_tick_pairs, "same_tick_relative_screen_dx_median": same_tick_median, "same_tick_relative_screen_dx_min": same_tick_min, "presentation_tick_monotonic": presentation_monotonic, "danger_relative_motion_monotonic": danger_relative_monotonic, "observed_render_hz_median": _median(frequencies), "physics_ticks_per_second": Engine.physics_ticks_per_second, "viewport": [image.get_width(), image.get_height()], "physics_interpolation_enabled_globally": bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)), "ghost_native_interpolation_mode": int(_ghost.physics_interpolation_mode), "visual_hitbox_policy": "rendered global position is fractional; collision reads integer simulation_tick"}
	var file := FileAccess.open(output_dir.path_join("gen19-ghost-%s.json" % mode_name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		_fail("could not save report for %s" % mode_name)
	print("GHOST_RENDER_CAPTURE mode=%s records=%d same_tick_pairs=%d same_tick_relative_screen_dx_median=%.4f min=%.4f median_hz=%.1f presentation_monotonic=%s danger_relative_monotonic=%s png=%s" % [mode_name, _records.size(), same_tick_pairs, same_tick_median, same_tick_min, _median(frequencies), str(presentation_monotonic), str(danger_relative_monotonic), image_path])
	if _records.size() < 30:
		_fail("too few actual render callbacks in %s" % mode_name)
	if not observed_phases.has(GhostModel.WARNING) or not observed_phases.has(GhostModel.DANGEROUS):
		_fail("actual runtime did not traverse warning and danger in %s: %s" % [mode_name, str(observed_phases)])
	if not presentation_monotonic:
		_fail("presentation tick regressed in %s" % mode_name)
	if not danger_relative_monotonic:
		_fail("danger-phase relative pursuit motion regressed in %s" % mode_name)
	if same_tick_min < -0.05:
		_fail("same-tick rendered ghost/runner relative motion regressed in %s (minimum %.4f px)" % [mode_name, same_tick_min])

func _median(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	values.sort()
	return values[values.size() / 2]

func _fail(message: String) -> void:
	failures.append(message)
	push_error("GHOST_RENDER_LIVE_CAPTURE: " + message)
