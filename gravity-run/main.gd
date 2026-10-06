extends Node2D

@export var demo_mode := false

var screen_width := 960.0
var screen_height := 540.0
const RUNNER_MOTION_SCRIPT := preload("res://systems/runner_motion.gd")
const HAZARD_RULES_SCRIPT := preload("res://systems/hazard_interaction_rules.gd")
const COURSE_GENERATOR_SCRIPT := preload("res://systems/course_generator.gd")
const RUN_SPEED_BASE := RUNNER_MOTION_SCRIPT.BASE_RUN_SPEED
const COIN_DISTANCE := 720.0
const WORLD_WIDTH := 960.0
const WORLD_HEIGHT := 540.0
const SLOPE_WIDTH := COURSE_GENERATOR_SCRIPT.SLOPE_WIDTH
const PLAYER_X := 180.0
const SPIKE_WIDTH := COURSE_GENERATOR_SCRIPT.SPIKE_WIDTH
const SPIKE_HEIGHT := COURSE_GENERATOR_SCRIPT.SPIKE_HEIGHT
const SPIKE_GROUP_SPACING := COURSE_GENERATOR_SCRIPT.SPIKE_GROUP_SPACING
const STEP_SPIKE_CLEARANCE := COURSE_GENERATOR_SCRIPT.STEP_SPIKE_CLEARANCE
const DEMO_AI_LOOKAHEAD := 700.0
const SPIKE_SCENE := preload("res://hazards/spikes.tscn")
const BLOCK_SCENE := preload("res://hazards/block.tscn")
const BARREL_SCENE := preload("res://hazards/barrel.tscn")
const COIN_SCENE := preload("res://collectibles/coin.tscn")
const LOOT_PICKUP_SCENE := preload("res://collectibles/loot_pickup.tscn")
const LOOT_PLANNER_SCRIPT := preload("res://systems/loot_spawn_planner.gd")
const SHARED_COIN_PLANNER_SCRIPT := preload("res://systems/shared_coin_planner.gd")
const FALLING_ROCK_SCENE := preload("res://hazards/falling_rock.tscn")
const FALLING_ROCK_MODEL := preload("res://systems/falling_rock_model.gd")
const SAW_BLADE_SCENE := preload("res://hazards/saw_blade.tscn")
const SAW_BLADE_MODEL := preload("res://systems/saw_blade_model.gd")
const GHOST_HAZARD_SCENE := preload("res://hazards/ghost_hazard.tscn")
const GHOST_HAZARD_MODEL := preload("res://systems/ghost_hazard_model.gd")
const LAVA_HAZARD_SCENE := preload("res://hazards/lava_hazard.tscn")
const COURSE_SURFACE_INDEX_SCRIPT := preload("res://systems/course_surface_index.gd")
const ROCK_WARNING_ICON_SCRIPT := preload("res://systems/rock_warning_icon.gd")
const ROCK_WARNING_PULSE_SCRIPT := preload("res://systems/rock_warning_pulse.gd")
const GHOST_WARNING_PULSE_SCRIPT := preload("res://systems/ghost_warning_pulse.gd")
const MANIFEST_BUILDER_SCRIPT := preload("res://systems/course_manifest_builder.gd")
const RUN_LOOT_ENABLED := false
const SLOPE_SCENE := preload("res://terrain/slope.tscn")
const LEDGE_SCENE := preload("res://terrain/ledge.tscn")
const COURSE_RULESET_SCRIPT := preload("res://systems/course_generation_ruleset.gd")
const COURSE_RUN_DEFINITION_SCRIPT := preload("res://systems/course_run_definition.gd")
const TRACK_GAP_SCRIPT := preload("res://terrain/track_gap.gd")
const COURSE_SURFACE_RENDERER := preload("res://systems/course_surface_renderer.gd")
const BIOME_RENDERER_SCRIPT := preload("res://biomes/biome_renderer.gd")
const CoursePresentation := preload("res://systems/race_course_presentation.gd")
const SfxAudibilityRules := preload("res://systems/sfx_audibility_rules.gd")
const SfxAudioDiagnosticCapture := preload("res://systems/sfx_audio_diagnostic_capture.gd")

@onready var player: Node2D = $Player
@onready var run_state: Node = $RunState
@onready var hud: Node2D = $HUDLayer/HUD
@onready var run_end_panel: CanvasLayer = $RunEndPanel
@onready var camera: Camera2D = $Camera2D

var obstacles: Array[Node2D] = []
var coins: Array[Node2D] = []
var loot_pickups: Array[Node2D] = []
var slopes: Array[Node2D] = []
var gaps: Array[Node2D] = []
var _seed_scores: Array[Dictionary] = []
var _pending_hazard_discoveries: Array[Dictionary] = []
var _active_seed := 0
var _active_seed_version := 0
var _default_ruleset: Resource
var course_generator: CourseGenerator
var loot_spawn_planner: LootSpawnPlanner
var course_distance := 0.0
var coin_distance := 0.0
var _spawned_shared_coin_ids: Dictionary = {}
var _pending_shared_coins: Array[Dictionary] = []
var _shared_coin_planner: RefCounted
var _shared_coin_planned_until := -INF
var _singleplayer_simulation_tick := 0
var _singleplayer_audio_round_id := ""
var _sfx_audio_diagnostic_capture: Node
var _rock_warning_pulse: RefCounted = ROCK_WARNING_PULSE_SCRIPT.new()
var _ghost_warning_pulse: RefCounted = GHOST_WARNING_PULSE_SCRIPT.new()
var _rock_warning_accessibility_button: Button
var _spawned_early_rock_ids: Dictionary = {}
var _spawned_early_saw_ids: Dictionary = {}
var _spawned_early_ghost_ids: Dictionary = {}
var _singleplayer_saw_activation_ticks: Dictionary = {}
var _singleplayer_ghost_activation_ticks: Dictionary = {}
var _singleplayer_saw_surface_indexes: Dictionary = {}
var _step_start_barrel_centers: Dictionary = {}
var _manifest_builder: RefCounted
var floor_level_y := screen_height - 80.0
var ceiling_level_y := 80.0
var planned_floor_level_y := screen_height - 80.0
var planned_ceiling_level_y := 80.0
var game_over := false
var run_blocked := false
var demo_flip_timer := 1.0
var demo_restart_timer := 0.0
var _speed_debug_visible := false
const Presentation := preload("res://systems/runner_presentation.gd")
const CameraScript := preload("res://systems/runner_camera.gd")
var _presentation := Presentation.new()
var _render_player_position := Vector2(180.0, 438.0)
var _render_course_distance := 0.0
var render_diagnostics_enabled := false
var _render_diagnostic_frames: Array[Dictionary] = []
var _render_diagnostic_tick := 0
var _render_callback_index := 0
var _render_callback_begin_usec := -1
var _render_presentation_sample_usec := -1
var _render_pose_sampled_usec := -1
var _render_presentation_ready_usec := -1
var _render_interpolation_fraction := 0.0
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")

func _ready() -> void:
	_rock_warning_accessibility_button = Button.new()
	_rock_warning_accessibility_button.name = "RockWarningAccessibility"
	_rock_warning_accessibility_button.text = ""
	_rock_warning_accessibility_button.tooltip_text = tr("Falling rock")
	_rock_warning_accessibility_button.accessibility_name = tr("Falling rock")
	_rock_warning_accessibility_button.focus_mode = Control.FOCUS_ALL
	_rock_warning_accessibility_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rock_warning_accessibility_button.flat = true
	_rock_warning_accessibility_button.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_rock_warning_accessibility_button.size = Vector2(48.0, 48.0)
	_rock_warning_accessibility_button.visible = false
	$HUDLayer.add_child(_rock_warning_accessibility_button)
	course_generator = COURSE_GENERATOR_SCRIPT.new()
	loot_spawn_planner = LOOT_PLANNER_SCRIPT.new()
	_manifest_builder = MANIFEST_BUILDER_SCRIPT.new()
	_default_ruleset = COURSE_RULESET_SCRIPT.new()
	camera.set_script(CameraScript)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position_smoothing_enabled = false
	camera.enabled = true
	camera.make_current()
	_sync_screen_size()
	get_viewport().size_changed.connect(_sync_screen_size)
	run_state.connect("stats_changed", Callable(self, "_on_run_stats_changed"))
	run_state.connect("achievement_metrics_changed", Callable(self, "_on_run_achievement_metrics_changed"))
	run_state.connect("loot_pending_changed", Callable(hud, "set_loot_pending_count"))
	run_state.connect("run_started", Callable(hud, "hide_game_over"))
	run_state.connect("run_finished", Callable(hud, "show_game_over"))
	player.connect("gravity_flipped", Callable(run_state, "record_gravity_flip"))
	player.connect("gravity_flipped", Callable(self, "_on_singleplayer_gravity_flipped"))
	player.connect("status_changed", Callable(hud, "update_player_status"))
	ChallengeService.leaderboard_received.connect(_on_seed_leaderboard_received)
	if demo_mode:
		hud.visible = false
		$PauseMenu.visible = false
	_start_run()
	if not demo_mode and SfxAudioDiagnosticCapture.is_requested():
		_start_singleplayer_audio_diagnostic_capture()

func _start_singleplayer_audio_diagnostic_capture(duration_seconds := 12.0) -> bool:
	if demo_mode or is_instance_valid(_sfx_audio_diagnostic_capture):
		return false
	var capture := SfxAudioDiagnosticCapture.new()
	capture.name = "SfxAudioDiagnosticCapture"
	add_child(capture)
	if not bool(capture.call("start_capture", _active_seed, _active_seed_version, duration_seconds)):
		capture.queue_free()
		return false
	_sfx_audio_diagnostic_capture = capture
	return true
func _start_run() -> void:
	_rock_warning_pulse.call("reset")
	_ghost_warning_pulse.call("reset")
	_rock_warning_accessibility_button.visible = false
	_render_diagnostic_tick = 0
	_render_diagnostic_frames.clear()
	run_end_panel.visible = false
	if not demo_mode:
		AchievementService.begin_run()
		_singleplayer_audio_round_id = "singleplayer:%d" % Time.get_ticks_usec()
		MusicController.start_round(_singleplayer_audio_round_id)
		SfxController.begin_round(_singleplayer_audio_round_id)
	player.call("reset_to_floor", WORLD_HEIGHT - 80.0)
	var loadout_snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	run_state.call("set_loadout_snapshot", loadout_snapshot)
	player.call("set_loadout_snapshot", loadout_snapshot)
	run_state.call("start_run")
	course_distance = 0.0
	var run_seed := ChallengeService.begin_run()
	loot_spawn_planner.reset(run_seed)
	_active_seed = run_seed
	_active_seed_version = ChallengeService.generation_version
	_seed_scores.clear()
	_pending_hazard_discoveries.clear()
	var run_definition := COURSE_RUN_DEFINITION_SCRIPT.new() as Resource
	run_definition.set("scenario_id", &"seed_challenge" if ChallengeService.active else &"endless")
	run_definition.set("seed_value", run_seed)
	run_definition.set("generator_version", _active_seed_version)
	run_definition.set("ruleset", ChallengeService.ruleset if ChallengeService.ruleset != null else _default_ruleset)
	if not course_generator.configure_run_definition(run_definition):
		push_error("Could not apply this run's seed and ruleset to the course generator.")
	if not demo_mode:
		hud.call("set_seed", ChallengeService.generation_version, run_seed)
		ChallengeService.fetch_current_scores()
	coin_distance = 0.0
	_spawned_shared_coin_ids.clear()
	_spawned_early_rock_ids.clear()
	_spawned_early_saw_ids.clear()
	_spawned_early_ghost_ids.clear()
	_singleplayer_saw_activation_ticks.clear()
	_singleplayer_ghost_activation_ticks.clear()
	_singleplayer_saw_surface_indexes.clear()
	_pending_shared_coins.clear()
	_shared_coin_planned_until = PLAYER_X + SHARED_COIN_PLANNER_SCRIPT.COURSE_START_OFFSET
	_shared_coin_planner = SHARED_COIN_PLANNER_SCRIPT.new()
	var coin_ruleset: Resource = ChallengeService.ruleset if ChallengeService.ruleset != null else _default_ruleset
	_shared_coin_planner.reset(_active_seed, PLAYER_X, int(coin_ruleset.get("coin_revision")), float(coin_ruleset.get("coin_density")))
	floor_level_y = WORLD_HEIGHT - 80.0
	ceiling_level_y = 80.0
	planned_floor_level_y = floor_level_y
	planned_ceiling_level_y = ceiling_level_y
	_clear_nodes(obstacles)
	_clear_nodes(coins)
	_clear_nodes(loot_pickups)
	_clear_nodes(slopes)
	_clear_nodes(gaps)
	game_over = false
	_singleplayer_simulation_tick = 0
	run_blocked = false
	_presentation.reset(player.position)
	_render_player_position = player.position
	_render_course_distance = 0.0
	_update_camera()
	demo_flip_timer = randf_range(0.9, 1.8)
	demo_restart_timer = 0.0
	player.call("set_input_enabled", not demo_mode)
	if demo_mode:
		player.call("set_running", true)
	hud.call("set_run_blocked", false)
	queue_redraw()

func _sync_screen_size() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var view_scale := minf(viewport_size.x / WORLD_WIDTH, viewport_size.y / WORLD_HEIGHT)
	view_scale = maxf(view_scale, 0.01)
	screen_width = viewport_size.x / view_scale
	screen_height = viewport_size.y / view_scale
	camera.zoom = Vector2.ONE * view_scale
	_update_camera()
	if is_instance_valid(hud):
		hud.queue_redraw()
	queue_redraw()

func _update_camera() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return
	camera.call("configure", Vector2(screen_width, screen_height), PLAYER_X, camera.zoom.x)
	camera.call("follow", _render_player_position)

func _on_run_stats_changed(distance_pixels: float, coins: int) -> void:
	hud.call("update_stats", distance_pixels, coins)
	if not demo_mode:
		AchievementService.update_run_distance(distance_pixels)

func _on_run_achievement_metrics_changed(coins: int, gravity_flips: int, hazards_seen: Array) -> void:
	if not demo_mode:
		AchievementService.update_run_metrics(coins, gravity_flips, hazards_seen)

func _scale_track_y(y: float, scale: float) -> float:
	return 56.0 + (y - 56.0) * scale

func _clear_nodes(nodes: Array[Node2D]) -> void:
	for node in nodes:
		node.queue_free()
	nodes.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_speed_debug_visible = not _speed_debug_visible
		hud.call("set_speed_debug_visible", _speed_debug_visible)
		_update_speed_debug()
		get_viewport().set_input_as_handled()
		return
	if game_over:
		if event is InputEventScreenTouch and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			AppNavigation.request_game_hub()
			get_tree().change_scene_to_file("res://ui/main_menu.tscn")
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(_sfx_audio_diagnostic_capture):
		_sfx_audio_diagnostic_capture.call("record_callback_timing", "sp_process", delta, _singleplayer_simulation_tick)
	var callback_started_usec := Time.get_ticks_usec()
	if render_diagnostics_enabled and not _render_diagnostic_frames.is_empty():
		var previous_frame: Dictionary = _render_diagnostic_frames.back()
		previous_frame["next_callback_begin_usec"] = callback_started_usec
		_render_diagnostic_frames[_render_diagnostic_frames.size() - 1] = previous_frame
	_render_callback_index += 1
	_render_callback_begin_usec = callback_started_usec
	_render_interpolation_fraction = Engine.get_physics_interpolation_fraction()
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.has_method("set_render_fraction") and (obstacle.is_in_group("falling_rocks") or obstacle.is_in_group("saw_blades")):
			obstacle.call("set_render_fraction", _render_interpolation_fraction)
	_render_presentation_sample_usec = Time.get_ticks_usec()
	_render_player_position = _presentation.sample(_render_interpolation_fraction)
	_render_pose_sampled_usec = Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_render_course_distance = _render_player_position.x - PLAYER_X
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.position = _render_player_position - player.position + Vector2(0.0, -float(player.call("get_gravity_direction")))
	_update_camera()
	_update_singleplayer_rock_warning_pulse(delta)
	_ghost_warning_pulse.call("advance", delta)
	_render_presentation_ready_usec = Time.get_ticks_usec()
	if render_diagnostics_enabled and not game_over:
		_record_render_diagnostic(delta)
	queue_redraw()

func set_render_diagnostics_enabled(enabled: bool) -> void:
	render_diagnostics_enabled = enabled
	if enabled:
		_render_diagnostic_frames.clear()

func _record_render_diagnostic(delta: float) -> void:
	var capture_started_usec := Time.get_ticks_usec()
	var reference: Dictionary = {}
	var left := float(camera.get("left"))
	var reference_nodes: Array[Dictionary] = []
	var static_hazard_recorded := false
	var barrel_recorded := false
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or obstacle.get_script() == null:
			continue
		if obstacle.has_method("is_destroying_now") and bool(obstacle.call("is_destroying_now")):
			continue
		var is_barrel := obstacle.is_in_group("barrels")
		if (is_barrel and barrel_recorded) or (not is_barrel and static_hazard_recorded):
			continue
		if obstacle.position.x < left - 100.0 or obstacle.position.x > left + screen_width + 100.0:
			continue
		var canvas_transform: Transform2D = obstacle.get_global_transform_with_canvas()
		var diagnostic_id := str(obstacle.get_meta("render_diagnostic_id", ""))
		if diagnostic_id.is_empty():
			var script_path := str(obstacle.get_script().resource_path)
			diagnostic_id = "%s@%.1f,%.1f" % [script_path, obstacle.position.x, obstacle.position.y]
			obstacle.set_meta("render_diagnostic_id", diagnostic_id)
		var node_record := {"kind": "barrel" if is_barrel else "static_hazard", "id": diagnostic_id, "instance_id": obstacle.get_instance_id(), "world_position": _render_diagnostic_vector(obstacle.global_position), "canvas_transform": _render_diagnostic_transform(canvas_transform), "canvas_origin": _render_diagnostic_vector(canvas_transform.origin)}
		if is_barrel:
			var render_fraction := Engine.get_physics_interpolation_fraction()
			var rendered_position: Vector2 = obstacle.get("_previous_position").lerp(obstacle.position, render_fraction)
			var previous_rotation := float(obstacle.get("_previous_rotation"))
			var rotation_delta := lerp_angle(previous_rotation, obstacle.rotation, render_fraction) - obstacle.rotation
			var draw_offset := (rendered_position - obstacle.position).rotated(-obstacle.rotation)
			var barrel_size: Vector2 = obstacle.get("size")
			var barrel_radius := HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y)
			var barrel_center_y := barrel_radius if bool(obstacle.get("from_ceiling")) else -barrel_radius
			var rendered_center := canvas_transform * (draw_offset + Vector2(0.0, barrel_center_y).rotated(rotation_delta))
			node_record["render_fraction"] = render_fraction
			node_record["rendered_world_position"] = _render_diagnostic_vector(rendered_position)
			node_record["rendered_canvas_center"] = _render_diagnostic_vector(rendered_center)
			node_record["rendered_rotation"] = lerp_angle(previous_rotation, obstacle.rotation, render_fraction)
			barrel_recorded = true
		else:
			var camera_top := camera.global_position.y - screen_height * 0.5
			node_record["expected_canvas_origin"] = _render_diagnostic_vector(Vector2((obstacle.position.x - left) * camera.zoom.x, (obstacle.position.y - camera_top) * camera.zoom.y))
			static_hazard_recorded = true
			reference = {"id": diagnostic_id, "instance_id": obstacle.get_instance_id(), "world_x": obstacle.position.x, "world_y": obstacle.position.y, "screen_x": (obstacle.position.x - left) * camera.zoom.x, "canvas_origin": node_record.canvas_origin}
		reference_nodes.append(node_record)
	var viewport_canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var track_world_x := left + PLAYER_X
	var track_floor_y := _floor_surface_y(track_world_x)
	var floor_slope: Dictionary = {}
	for terrain in slopes:
		if not is_instance_valid(terrain) or bool(terrain.call("is_ceiling_slope")):
			continue
		var slope_start := float(terrain.call("get_start_x"))
		var slope_end := float(terrain.call("get_end_x"))
		if track_world_x >= slope_start and track_world_x <= slope_end:
			floor_slope = {"id": "%s@%.1f" % [str(terrain.get_script().resource_path), slope_start], "start_x": slope_start, "end_x": slope_end, "canvas_transform": _render_diagnostic_transform(terrain.get_global_transform_with_canvas())}
			break
	var player_canvas_transform: Transform2D = player.get_node("AnimatedSprite2D").get_global_transform_with_canvas()
	if _render_diagnostic_frames.size() >= 4096:
		_render_diagnostic_frames.pop_front()
	var captured_at_usec := Time.get_ticks_usec()
	var frame_record := {"at_usec": captured_at_usec, "render_callback_index": _render_callback_index, "render_callback_begin_usec": _render_callback_begin_usec, "presentation_sample_usec": _render_presentation_sample_usec, "pose_sampled_usec": _render_pose_sampled_usec, "presentation_ready_usec": _render_presentation_ready_usec, "sample_to_ready_usec": _render_presentation_ready_usec - _render_presentation_sample_usec, "ready_to_capture_usec": captured_at_usec - _render_presentation_ready_usec, "diagnostic_capture_usec": 0, "phase": "terminal" if game_over else "running", "render_delta_ms": delta * 1000.0, "tick": _render_diagnostic_tick, "fraction": _render_interpolation_fraction, "previous_x": _presentation.previous.x, "current_x": _presentation.current.x, "previous_y": _presentation.previous.y, "current_y": _presentation.current.y, "render_x": _render_player_position.x, "render_y": _render_player_position.y, "player_world_position": _render_diagnostic_vector(player.global_position), "gravity_direction": int(player.call("get_gravity_direction")), "grounded": bool(player.get("grounded")), "vertical_speed": float(player.get("vertical_speed")), "camera_left": left, "camera_global_position": _render_diagnostic_vector(camera.global_position), "camera_canvas_transform": _render_diagnostic_transform(viewport_canvas_transform), "render_course_distance": _render_course_distance, "speed": _run_speed(), "player_speed_multiplier": float(player.call("get_speed_multiplier")), "equipment_speed_multiplier": _equipment_speed_multiplier(), "blocked": run_blocked, "reference": reference, "reference_nodes": reference_nodes, "player_canvas_position": _render_diagnostic_vector(player_canvas_transform.origin), "track_surface": {"world_position": _render_diagnostic_vector(Vector2(track_world_x, track_floor_y)), "canvas_position": _render_diagnostic_vector(viewport_canvas_transform * Vector2(track_world_x, track_floor_y)), "floor_y": track_floor_y, "ceiling_y": _ceiling_surface_y(track_world_x), "slope": floor_slope}, "fps": Engine.get_frames_per_second()}
	_render_diagnostic_frames.append(frame_record)
	_render_diagnostic_frames[_render_diagnostic_frames.size() - 1]["diagnostic_capture_usec"] = Time.get_ticks_usec() - capture_started_usec

func save_render_diagnostics() -> String:
	var report := {"session": {"network_mode": "singleplayer", "build_id": str(ProjectSettings.get_setting("application/config/version", "")), "godot_version": Engine.get_version_info(), "seed": _active_seed, "viewport": [screen_width, screen_height], "zoom": camera.zoom.x}, "frames": _render_diagnostic_frames.duplicate(true), "exported_at_unix": Time.get_unix_time_from_system()}
	return DiagnosticsExport.save_report(report, "singleplayer_smoothness_%d.json" % Time.get_unix_time_from_system())

func _render_diagnostic_vector(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func _render_diagnostic_transform(value: Transform2D) -> Dictionary:
	return {"x": _render_diagnostic_vector(value.x), "y": _render_diagnostic_vector(value.y), "origin": _render_diagnostic_vector(value.origin)}

func _physics_process(delta: float) -> void:
	if is_instance_valid(_sfx_audio_diagnostic_capture):
		_sfx_audio_diagnostic_capture.call("record_callback_timing", "sp_physics", delta, _singleplayer_simulation_tick)
	if game_over:
		if demo_mode:
			demo_restart_timer += delta
			if demo_restart_timer >= 0.8:
				_start_run()
		return
	var previous_player_rect: Rect2 = player.call("get_player_rect")
	var previous_world_x := float(player.get("world_x"))
	_step_start_barrel_centers.clear()
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			_step_start_barrel_centers[obstacle.get_instance_id()] = HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
	_singleplayer_simulation_tick += 1
	for hazard in obstacles:
		if is_instance_valid(hazard) and hazard.is_in_group("lava_hazards") and hazard.has_method("apply_simulation_tick"):
			hazard.call("apply_simulation_tick", _singleplayer_simulation_tick, PLAYER_X)

	_render_diagnostic_tick += 1
	var speed := _run_speed()
	_update_speed_debug()
	var movement_multiplier := _equipment_speed_multiplier() * float(player.call("get_speed_multiplier"))
	var movement := RUNNER_MOTION_SCRIPT.distance_for_delta(delta, movement_multiplier, run_blocked)
	if not run_blocked:
		var previous_distance := float(run_state.get("distance_m"))
		player.call("advance_world_x", movement)
		course_distance = float(player.get("world_x")) - PLAYER_X
		run_state.call("add_distance", movement)
		var current_distance := float(run_state.get("distance_m"))
		_mark_crossed_seed_records(previous_distance, current_distance)
		coin_distance += movement
		var event_spawn_lead := COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
		course_generator.ensure_horizon(course_distance + screen_width + 1400.0, speed, screen_height, event_spawn_lead)
		if RUN_LOOT_ENABLED and AuthService.is_authenticated and not demo_mode:
			loot_spawn_planner.ensure_horizon(course_distance + screen_width + 1400.0)
		var spawn_line := course_distance + event_spawn_lead
		if _active_seed_version >= COURSE_GENERATOR_SCRIPT.PUBLISHED_SHARED_GENERATOR_VERSION:
			var rock_spawn_line := course_distance + FALLING_ROCK_MODEL.TRIGGER_LEAD + 300.0
			var saw_spawn_line := course_distance + SAW_BLADE_MODEL.SPAWN_LEAD
			for planned_event in course_generator.get_planned_events():
				var planned_kind := str(planned_event.get("kind", ""))
				var event_distance := float(planned_event.get("course_distance", INF))
				if planned_kind == "rock" and event_distance <= rock_spawn_line:
					var rock_id := _singleplayer_rock_key(planned_event)
					if not _spawned_early_rock_ids.has(rock_id):
						_spawned_early_rock_ids[rock_id] = true
						_spawn_course_event(planned_event)
				elif planned_kind == "saw" and event_distance <= saw_spawn_line:
					var saw_id := _singleplayer_saw_key(planned_event)
					if not _spawned_early_saw_ids.has(saw_id):
						_spawned_early_saw_ids[saw_id] = true
						_spawn_course_event(planned_event)
				elif planned_kind == "ghost" and event_distance <= course_distance + float(planned_event.get("trigger_lead", 2200.0)):
					var ghost_id := _singleplayer_ghost_key(planned_event)
					if not _spawned_early_ghost_ids.has(ghost_id):
						_spawned_early_ghost_ids[ghost_id] = true
						_spawn_course_event(planned_event)
		for event in course_generator.pop_events_until(spawn_line):
			var event_kind := str(event.get("kind", ""))
			if event_kind == "rock":
				var event_id := _singleplayer_rock_key(event)
				if _spawned_early_rock_ids.has(event_id):
					continue
				_spawned_early_rock_ids[event_id] = true
			elif event_kind == "saw":
				var event_id := _singleplayer_saw_key(event)
				if _spawned_early_saw_ids.has(event_id):
					continue
				_spawned_early_saw_ids[event_id] = true
			elif event_kind == "ghost":
				var event_id := _singleplayer_ghost_key(event)
				if _spawned_early_ghost_ids.has(event_id):
					continue
				_spawned_early_ghost_ids[event_id] = true
			_spawn_course_event(event)
		if RUN_LOOT_ENABLED:
			for loot_event in loot_spawn_planner.pop_events_until(spawn_line):
				_spawn_loot_pickup(loot_event)
		_update_hazard_discoveries()
		if not demo_mode:
			if _active_seed_version >= COURSE_GENERATOR_SCRIPT.PUBLISHED_SHARED_GENERATOR_VERSION:
				_spawn_shared_coins()
			elif coin_distance >= COIN_DISTANCE:
				coin_distance -= COIN_DISTANCE
				_spawn_coin_row()

	_update_moving_slopes(movement)
	# Barrel motion has its own fallback while the player is blocked; other
	# obstacle behavior remains synchronized to actual player movement.
	_update_moving_nodes(obstacles, movement, delta)
	_update_moving_nodes(coins, movement, delta)
	_update_moving_nodes(loot_pickups, movement, delta)
	_update_moving_nodes(gaps, movement, delta)
	_resolve_obstacle_interactions()

	if demo_mode:
		_update_demo_ai(delta)
	player.call("advance", delta, _floor_surface_y(float(player.get("world_x"))), _ceiling_surface_y(float(player.get("world_x"))), _surface_is_solid_at_x(float(player.get("world_x")), false), _surface_is_solid_at_x(float(player.get("world_x")), true))
	_update_falling_rocks(previous_world_x, float(player.get("world_x")))
	_update_saw_blades(previous_world_x, float(player.get("world_x")))
	_update_ghost_hazards(float(player.get("world_x")))
	_presentation.push(player.position)
	var run_end_requested := player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0

	var blocked_by_edge := false
	for obstacle in obstacles:
		if bool(obstacle.call("is_destroying_now")):
			continue
		var player_rect: Rect2 = player.call("get_player_rect")
		var impact := HAZARD_RULES_SCRIPT.PlayerImpact.NONE
		if obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, "spikes", Rect2(), obstacle.call("get_world_triangles"), Vector2.ZERO, 0.0, bool(player.call("is_spike_immune")))
		elif obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			var barrel_center: Vector2 = HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, "barrel", Rect2(), [], barrel_center, HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y))
		elif obstacle.is_in_group("saw_blades"):
			impact = _saw_endpoint_impact(player_rect, obstacle)
		elif obstacle.is_in_group("lava_hazards") and obstacle.has_method("is_lethal_at"):
			impact = HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL if bool(obstacle.call("is_lethal_at", player_rect, _singleplayer_simulation_tick, PLAYER_X)) else HAZARD_RULES_SCRIPT.PlayerImpact.NONE
		else:
			var kind := "edge" if obstacle.is_in_group("blocking_edges") else "rect"
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, kind, obstacle.call("get_hitbox_rect"))
		if impact == HAZARD_RULES_SCRIPT.PlayerImpact.BLOCKED:
			blocked_by_edge = true
		elif impact == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
			run_end_requested = true
			break
	if not game_over:
		var player_rect: Rect2 = player.call("get_player_rect")
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			var spike_triangles: Array = terrain.call("get_world_spike_triangles") if terrain.has_method("get_world_spike_triangles") else []
			if HAZARD_RULES_SCRIPT.player_impact(player_rect, "spikes", Rect2(), spike_triangles, Vector2.ZERO, 0.0, bool(player.call("is_spike_immune"))) == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
				run_end_requested = true
				break
			var from_ceiling := bool(terrain.call("is_ceiling_slope"))
			var gravity_direction := int(player.call("get_gravity_direction"))
			var step_rect: Rect2 = terrain.call("get_wall_rect")
			var impact := HAZARD_RULES_SCRIPT.player_impact(player_rect, "step", step_rect, [], Vector2.ZERO, 0.0, false, gravity_direction, from_ceiling, float(terrain.call("get_start_y")), float(terrain.call("get_end_y")))
			if impact == HAZARD_RULES_SCRIPT.PlayerImpact.BLOCKED:
				# Let the runner pass a step when its surface moves away in the
				# direction of gravity: down over a floor drop or up over a rising
				# ceiling step.
				blocked_by_edge = true
	var final_player_rect: Rect2 = player.call("get_player_rect")
	var lethal_fraction := _earliest_lethal_contact_fraction(previous_player_rect, final_player_rect)
	if lethal_fraction >= 0.0 and lethal_fraction <= 1.0:
		run_end_requested = true
	run_blocked = blocked_by_edge and not game_over
	hud.call("set_run_blocked", run_blocked)
	if not demo_mode:
		for coin in coins:
			if not is_instance_valid(coin) or bool(coin.call("is_collected")):
				continue
			var center := coin.global_position
			var fraction := HAZARD_RULES_SCRIPT.swept_rect_circle_fraction(previous_player_rect, final_player_rect.position - previous_player_rect.position, center, 13.0)
			if is_instance_valid(_sfx_audio_diagnostic_capture) and bool(_sfx_audio_diagnostic_capture.call("is_capture_active")):
				var coin_rect: Rect2 = coin.call("get_hitbox_rect")
				var broadphase := previous_player_rect.merge(final_player_rect).grow(24.0)
				if fraction >= 0.0 or broadphase.intersects(coin_rect):
					_sfx_audio_diagnostic_capture.call("record_coin_sweep", {"tick": _singleplayer_simulation_tick, "swept_fraction": fraction, "survives_terminal": fraction >= 0.0 and fraction < lethal_fraction - 0.000001, "player_rect_start": [previous_player_rect.position.x, previous_player_rect.position.y, previous_player_rect.size.x, previous_player_rect.size.y], "player_rect_end": [final_player_rect.position.x, final_player_rect.position.y, final_player_rect.size.x, final_player_rect.size.y], "coin_center": [center.x, center.y], "coin_rect": [coin_rect.position.x, coin_rect.position.y, coin_rect.size.x, coin_rect.size.y], "run_coins_before": int(run_state.get("coins"))})
			if fraction >= 0.0 and fraction < lethal_fraction - 0.000001:
				coin.call("collect")
		for pickup in loot_pickups:
			if _player_hits_obstacle(pickup):
				pickup.call("collect")
	if run_end_requested:
		_end_run()
	var camera_left := course_distance
	coins = coins.filter(func(coin: Node2D) -> bool: return is_instance_valid(coin) and not bool(coin.call("is_collected")) and coin.position.x > camera_left - 100.0)
	loot_pickups = loot_pickups.filter(func(pickup: Node2D) -> bool: return is_instance_valid(pickup) and pickup.position.x > camera_left - 100.0)
	queue_redraw()

func _end_run() -> void:
	if game_over:
		return
	game_over = true
	_rock_warning_pulse.call("reset")
	_rock_warning_accessibility_button.visible = false
	if not demo_mode:
		SfxController.play_death(_singleplayer_audio_round_id, "local")
		MusicController.enter_menu()
	_presentation.reset(player.position)
	for obstacle in obstacles:
		if obstacle.has_method("freeze_render_motion"):
			obstacle.call("freeze_render_motion")
	player.call("set_input_enabled", false)
	if not demo_mode:
		AchievementService.finish_run()
		run_state.call("finish_run")
		run_end_panel.call("show_result", float(run_state.get("distance_m")), int(run_state.get("coins")), ChallengeService.get_challenge_code(), ChallengeService.active, str(run_state.get("last_run_id")))

func retry_run() -> void:
	if not bool(ChallengeService.get("active")) and _active_seed > 0:
		ChallengeService.call("start_singleplayer_seed_input", "GR%d-%d" % [_active_seed_version, _active_seed])
	_start_run()

func new_random_run() -> void:
	ChallengeService.clear_challenge()
	_start_run()

func return_to_main_menu() -> void:
	AppNavigation.request_game_hub()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _update_demo_ai(delta: float) -> void:
	demo_flip_timer -= delta
	var current_side := int(player.call("get_gravity_direction"))
	if run_blocked and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", -current_side)
		demo_flip_timer = randf_range(1.0, 1.7)
		return
	var current_risk := _demo_side_risk(current_side)
	var other_risk := _demo_side_risk(-current_side)
	var must_evade := current_risk >= 0.55 and other_risk < current_risk * 0.78
	var timed_flip := demo_flip_timer <= 0.0 and other_risk < 0.38
	if not must_evade and not timed_flip:
		return
	if not bool(player.get("grounded")) or float(player.call("get_cooldown_left")) > 0.0:
		return
	player.call("_try_flip", -current_side)
	demo_flip_timer = randf_range(0.85, 1.35) if must_evade else randf_range(1.5, 2.6)

func _demo_side_risk(side: int) -> float:
	var player_rect: Rect2 = player.call("get_player_rect")
	var risk := 0.0
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or bool(obstacle.call("is_destroying_now")):
			continue
		var obstacle_side := -1 if _demo_obstacle_from_ceiling(obstacle) else 1
		if obstacle.is_in_group("barrels"):
			obstacle_side = 1
		if obstacle_side != side:
			continue
		var hazard_rect: Rect2 = obstacle.call("get_hitbox_rect")
		var distance := hazard_rect.position.x - player_rect.end.x
		if distance < -60.0 or distance > DEMO_AI_LOOKAHEAD:
			continue
		var proximity := 1.0 - maxf(distance, 0.0) / DEMO_AI_LOOKAHEAD
		var weight := 1.0
		if obstacle.is_in_group("spikes") or obstacle.is_in_group("blocking_edges"):
			weight = 1.4
		elif obstacle.is_in_group("barrels"):
			weight = 1.25
		risk += (0.25 + proximity) * weight

	for terrain in slopes:
		if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
			continue
		var terrain_side := -1 if bool(terrain.call("is_ceiling_slope")) else 1
		if terrain_side != side:
			continue
		var distance := float(terrain.call("get_start_x")) - player_rect.end.x
		if distance < -60.0 or distance > DEMO_AI_LOOKAHEAD:
			continue
		var proximity := 1.0 - maxf(distance, 0.0) / DEMO_AI_LOOKAHEAD
		var step_weight := 2.0 if bool(terrain.get("has_spikes")) else 1.1
		risk += (0.25 + proximity) * step_weight
	return risk

func _demo_obstacle_from_ceiling(obstacle: Node) -> bool:
	for property_info in obstacle.get_property_list():
		if str(property_info.get("name", "")) != "from_ceiling":
			continue
		var direct_value: Variant = obstacle.get("from_ceiling")
		if direct_value is bool:
			return direct_value
		break
	var event_value: Variant = obstacle.get("event")
	if event_value is Dictionary:
		var event_side: Variant = event_value.get("from_ceiling", false)
		return event_side if event_side is bool else false
	return false
func _update_moving_nodes(nodes: Array[Node2D], movement: float, delta: float = 0.0) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_destroying_now") and bool(node.call("is_destroying_now")):
			continue
		if node.has_method("advance_motion"):
			node.call(
				"advance_motion",
				delta,
				movement,
				player.global_position,
				Callable(self, "_floor_surface_y"),
				Callable(self, "_surface_angle_at"),
				Callable(self, "_surface_is_solid_at_x")
			)
	var active_nodes: Array[Node2D] = []
	var camera_left := course_distance
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.is_in_group("falling_rocks") or (node.has_method("is_destroying_now") and bool(node.call("is_destroying_now"))) or node.position.x > camera_left - 220.0:
			active_nodes.append(node)
		else:
			node.queue_free()
	nodes.clear()
	nodes.append_array(active_nodes)

func _floor_surface_y(x: float) -> float:
	return _surface_y_at(x, false)

func _ceiling_surface_y(x: float) -> float:
	return _surface_y_at(x, true)

func _surface_is_solid_at_x(x: float, ceiling: bool) -> bool:
	for gap in gaps:
		if is_instance_valid(gap) and bool(gap.call("contains_track_x", x, ceiling)):
			return false
	return true

func _surface_y_at(x: float, ceiling: bool) -> float:
	var surface_y := ceiling_level_y if ceiling else floor_level_y
	for slope in slopes:
		if bool(slope.call("is_ceiling_slope")) != ceiling:
			continue
		var start_x := float(slope.call("get_start_x"))
		if x < start_x:
			break
		if slope.has_method("is_terrain_step") and bool(slope.call("is_terrain_step")):
			if x <= start_x:
				return surface_y
			surface_y = float(slope.call("get_end_y"))
			continue
		if x <= float(slope.call("get_end_x")):
			return float(slope.call("get_surface_y_at", x))
		surface_y = float(slope.call("get_end_y"))
	return surface_y

func _surface_angle_at(x: float, ceiling: bool) -> float:
	for slope in slopes:
		if bool(slope.call("is_ceiling_slope")) != ceiling:
			continue
		var angle: float = slope.call("get_surface_angle_at", x)
		if not is_zero_approx(angle):
			return angle
	return 0.0

func _run_speed() -> float:
	return RUNNER_MOTION_SCRIPT.speed_for_multiplier(float(player.call("get_speed_multiplier")) * _equipment_speed_multiplier())

func _base_run_speed() -> float:
	return RUNNER_MOTION_SCRIPT.speed_for_multiplier(float(player.call("get_speed_multiplier")))

func _equipment_speed_multiplier() -> float:
	var equipment_multiplier := 1.0
	var snapshot: Variant = run_state.get("loadout_snapshot")
	if snapshot is Resource and snapshot.has_method("get_resolved_stats"):
		var stats: Variant = snapshot.call("get_resolved_stats")
		if stats is Dictionary:
			equipment_multiplier = float(stats.get("run_speed_percent", 10000)) / 10000.0
	return equipment_multiplier

func _update_speed_debug() -> void:
	if not _speed_debug_visible or not is_instance_valid(hud):
		return
	hud.call("set_speed_debug_values", _run_speed(), _base_run_speed(), _equipment_speed_multiplier() * 100.0)

func _spawn_course_event(event: Dictionary) -> void:
	var event_x := PLAYER_X + float(event["course_distance"])
	var event_spawn_lead := COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
	var from_ceiling := bool(event.get("from_ceiling", false))
	var width := float(event.get("width", 48.0))
	var height := float(event.get("height", 72.0))
	var event_kind := StringName(event.get("kind", ""))
	if event_kind == &"block" or event_kind == &"barrels":
		var lane_clearance := _floor_surface_y(event_x) - _ceiling_surface_y(event_x)
		# Keep the authored hazard dimensions. If it cannot fit while leaving a
		# character-sized route in the opposite lane, omit this encounter.
		if lane_clearance < height + 44.0 + 12.0:
			return
	var hazard_id := str(event.get("id", ""))
	if not hazard_id.is_empty():
		_pending_hazard_discoveries.append({
			"hazard_id": hazard_id,
			"course_distance": float(event.get("course_distance", 0.0)),
			"width": float(event.get("width", 48.0)),
		})
	match event_kind:
		&"spikes":
			var count := int(event.get("count", 4))
			var group_width := float(count - 1) * SPIKE_GROUP_SPACING
			_spawn_spike_group(count, from_ceiling, event_x - group_width * 0.5)
		&"block":
			_spawn_obstacle_scene(BLOCK_SCENE, width, height, from_ceiling, event_x)
		&"barrels":
			var count := int(event.get("count", 1))
			var chain_width := float(count - 1) * HAZARD_RULES_SCRIPT.BARREL_CHAIN_SPACING
			var motion_speed_multiplier := float(event.get("motion_speed_multiplier", 1.0))
			# Keep the barrel's encounter timing tied to the canonical planner lead
			# even when a wide desktop viewport requires spawning it much earlier.
			var early_spawn_offset := maxf(event_spawn_lead - COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE, 0.0) * (motion_speed_multiplier - 1.0)
			for index in range(count):
				_spawn_obstacle_scene(BARREL_SCENE, HAZARD_RULES_SCRIPT.BARREL_WIDTH, height, false, event_x + early_spawn_offset - chain_width * 0.5 + float(index) * HAZARD_RULES_SCRIPT.BARREL_CHAIN_SPACING, motion_speed_multiplier, bool(event.get("spiked", false)))
		&"gap":
			var gap := TRACK_GAP_SCRIPT.new() as TrackGap
			gap.position = Vector2(event_x, 0.0)
			gap.configure(width, from_ceiling)
			add_child(gap)
			gaps.append(gap)
		&"step":
			_spawn_ledge(event, event_x)
		&"slope":
			_spawn_course_slope(event, event_x)
		&"rock":
			var near_terrain := false
			for planned in course_generator.get_planned_events():
				if str(planned.get("kind", "")) in ["step", "slope", "gap"] and absf(float(planned.get("course_distance", 0.0)) - float(event.get("course_distance", 0.0))) < 420.0:
					near_terrain = true
					break
			if not near_terrain and _floor_surface_y(event_x) - _ceiling_surface_y(event_x) >= 260.0:
				var rock := FALLING_ROCK_SCENE.instantiate() as Node2D
				var rock_event_id := _singleplayer_rock_key(event)
				rock.connect("impact_started", Callable(self, "_on_rock_impact_started"))
				var rock_event := {"event_id": rock_event_id, "kind": "rock", "x": event_x, "width": width, "height": height, "floor_y": _floor_surface_y(event_x), "ceiling_y": _ceiling_surface_y(event_x), "trigger_lead": float(event.get("trigger_lead", FALLING_ROCK_MODEL.TRIGGER_LEAD)), "warning_ticks": int(event.get("warning_ticks", FALLING_ROCK_MODEL.WARNING_TICKS)), "fall_ticks": int(event.get("fall_ticks", FALLING_ROCK_MODEL.FALL_TICKS)), "burial_depth": float(event.get("burial_depth", FALLING_ROCK_MODEL.BURIAL_DEPTH))}
				rock.call("configure", rock_event)
				rock.name = "FallingRock_%s" % rock_event_id
				add_child(rock)
				obstacles.append(rock)
		&"saw":
			var saw_event := _resolve_singleplayer_saw_event(event)
			if saw_event.is_empty():
				return
			var saw_event_id := str(saw_event.get("event_id", _singleplayer_saw_key(event)))
			if bool(saw_event.get("from_ceiling", false)) and str(saw_event.get("saw_variant", "legacy_floor_then_drop")) in ["legacy_floor_then_drop", "ceiling_gap_drop"]:
				var gap := TRACK_GAP_SCRIPT.new() as TrackGap
				gap.position = Vector2(float(saw_event.get("roof_gap_x", event_x + SAW_BLADE_MODEL.ROOF_GAP_OFFSET)), 0.0)
				gap.configure(float(saw_event.get("roof_gap_width", SAW_BLADE_MODEL.ROOF_GAP_WIDTH)), true)
				gap.name = "SawRoofGap_%s" % saw_event_id
				add_child(gap)
				gaps.append(gap)
			var saw := SAW_BLADE_SCENE.instantiate() as Node2D
			var saw_key := str(saw_event.get("source_saw_key", _singleplayer_saw_key(event)))
			var saw_surface_index: RefCounted = _singleplayer_saw_surface_indexes.get(saw_key)
			var surface_callable := Callable(saw_surface_index, "surface_at") if saw_surface_index != null else Callable(self, "_saw_surface_at")
			saw.call("configure", saw_event, surface_callable, PLAYER_X, 0)
			saw.name = "SawBlade_%s" % saw_event_id
			add_child(saw)
			obstacles.append(saw)
			if _singleplayer_saw_activation_ticks.has(saw_key):
				saw.call("set_activation_tick", int(_singleplayer_saw_activation_ticks[saw_key]))
				saw.call("set_simulation_tick", _singleplayer_simulation_tick)
		&"ghost":
			var ghost_event := _resolve_singleplayer_ghost_event(event)
			if ghost_event.is_empty():
				return
			var ghost_id := str(ghost_event.get("event_id", _singleplayer_ghost_key(event)))
			var ghost := GHOST_HAZARD_SCENE.instantiate() as Node2D
			ghost.call("configure", ghost_event)
			ghost.name = "Ghost_%s" % ghost_id
			ghost.connect("phase_changed", Callable(self, "_on_singleplayer_ghost_phase_changed").bind(ghost_event))
			add_child(ghost)
			obstacles.append(ghost)
			if _singleplayer_ghost_activation_ticks.has(ghost_id):
				ghost.call("set_activation_tick", int(_singleplayer_ghost_activation_ticks[ghost_id]))
				ghost.call("set_simulation_tick", _singleplayer_simulation_tick)
		&"lava_crack", &"volcano":
			_spawn_singleplayer_lava_event(event, event_x)
		_:
			_spawn_custom_course_event(event, event_x)

func _spawn_singleplayer_lava_event(source_event: Dictionary, target_x: float) -> void:
	var horizon := ceili(maxf(float(course_distance) + screen_width + 2400.0, float(source_event.get("course_distance", 0.0)) + 1.0))
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("_resolve_events", course_generator.get_planned_events(), horizon, _active_seed_version, biome_start_offset)
	var source_kind := str(source_event.get("kind", ""))
	for event in resolved_events:
		if str(event.get("kind", "")) != source_kind or absf(float(event.get("x", INF)) - target_x) > 0.5:
			continue
		var hazard := LAVA_HAZARD_SCENE.instantiate() as Node2D
		hazard.call("configure", event, PLAYER_X)
		hazard.call("apply_simulation_tick", _singleplayer_simulation_tick, PLAYER_X)
		hazard.name = "Lava_%s" % str(event.get("event_id", ""))
		add_child(hazard)
		obstacles.append(hazard)
		return

func _update_hazard_discoveries() -> void:
	for index in range(_pending_hazard_discoveries.size() - 1, -1, -1):
		var encounter: Dictionary = _pending_hazard_discoveries[index]
		var event_x := PLAYER_X + float(encounter["course_distance"]) - course_distance
		var half_width := float(encounter["width"]) * 0.5
		if event_x - half_width > screen_width:
			continue
		if event_x + half_width >= 0.0:
			run_state.call("record_hazard_seen", str(encounter["hazard_id"]))
		_pending_hazard_discoveries.remove_at(index)

func _spawn_custom_course_event(event: Dictionary, x: float) -> void:
	var profile := event.get("profile") as CourseHazardProfile
	if profile == null or profile.runtime_scene == null:
		push_warning("Course event '%s' has no runtime scene; skipped." % str(event.get("id", "unknown")))
		return
	var hazard := profile.runtime_scene.instantiate() as Node2D
	if hazard == null or not hazard.has_method("configure_course_event"):
		push_warning("Course event '%s' scene must implement configure_course_event(event)." % str(profile.profile_id))
		if is_instance_valid(hazard):
			hazard.queue_free()
		return
	if hazard.has_signal("destroyed"):
		hazard.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	hazard.position.x = x
	hazard.call("configure_course_event", event)
	add_child(hazard)
	obstacles.append(hazard)

func _singleplayer_rock_key(event: Dictionary) -> String:
	# Profile ids identify the rock type, not an individual encounter.
	# Pair with its deterministic course position so early-spawn and normal
	# event-pop paths deduplicate the same rock without suppressing later rocks.
	return "%s:%.3f" % [str(event.get("id", "rock")), float(event.get("course_distance", -1.0))]

func _singleplayer_saw_key(event: Dictionary) -> String:
	return "%s:%.3f" % [str(event.get("id", "saw")), float(event.get("course_distance", -1.0))]

func _singleplayer_ghost_key(event: Dictionary) -> String:
	return "%s:%.3f" % [str(event.get("id", "ghost")), float(event.get("course_distance", -1.0))]

func _resolve_singleplayer_saw_event(source_event: Dictionary) -> Dictionary:
	if course_generator == null or _manifest_builder == null:
		return {}
	var source_distance := float(source_event.get("course_distance", 0.0))
	var support_horizon := source_distance + SAW_BLADE_MODEL.START_OFFSET + 3000.0
	course_generator.ensure_horizon(support_horizon, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("_resolve_events", course_generator.get_planned_events(), ceili(support_horizon), _active_seed_version, biome_start_offset)
	var target_x := PLAYER_X + source_distance
	for resolved_event in resolved_events:
		if str(resolved_event.get("kind", "")) == "saw" and absf(float(resolved_event.get("x", INF)) - target_x) < 0.5:
			var result := resolved_event.duplicate(true)
			result["source_saw_key"] = _singleplayer_saw_key(source_event)
			var surface_index: RefCounted = COURSE_SURFACE_INDEX_SCRIPT.new()
			surface_index.call("configure", resolved_events, WORLD_HEIGHT - 80.0, 80.0)
			_singleplayer_saw_surface_indexes[_singleplayer_saw_key(source_event)] = surface_index
			return result
	return {}

func _resolve_singleplayer_ghost_event(source_event: Dictionary) -> Dictionary:
	if course_generator == null or _manifest_builder == null:
		return {}
	var source_distance := float(source_event.get("course_distance", 0.0))
	var support_horizon := source_distance + 200.0
	course_generator.ensure_horizon(support_horizon, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("_resolve_events", course_generator.get_planned_events(), ceili(support_horizon), _active_seed_version, biome_start_offset)
	var target_x := PLAYER_X + source_distance
	for resolved_event in resolved_events:
		if str(resolved_event.get("kind", "")) == "ghost" and absf(float(resolved_event.get("x", INF)) - target_x) < 0.5:
			var result := resolved_event.duplicate(true)
			result["source_ghost_key"] = _singleplayer_ghost_key(source_event)
			return result
	return {}

func _saw_surface_at(x: float, ceiling: bool) -> Dictionary:
	return {"y": _ceiling_surface_y(x) if ceiling else _floor_surface_y(x), "supported": _surface_is_solid_at_x(x, ceiling)}

func _update_saw_blades(previous_world_x: float = -1.0, current_world_x: float = -1.0) -> void:
	if current_world_x >= 0.0 and is_finite(current_world_x):
		for planned_event in course_generator.get_planned_events():
			if str(planned_event.get("kind", "")) != "saw":
				continue
			var saw_key := _singleplayer_saw_key(planned_event)
			var trigger_x := PLAYER_X + float(planned_event.get("course_distance", 0.0)) + SAW_BLADE_MODEL.START_OFFSET - SAW_BLADE_MODEL.SPAWN_LEAD
			if not _singleplayer_saw_activation_ticks.has(saw_key) and current_world_x >= trigger_x:
				_singleplayer_saw_activation_ticks[saw_key] = _singleplayer_simulation_tick + SAW_BLADE_MODEL.ACTIVATION_DELAY_TICKS
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_in_group("saw_blades"):
			var event: Dictionary = obstacle.get("event")
			var saw_key := str(event.get("source_saw_key", _singleplayer_saw_key(event)))
			if _singleplayer_saw_activation_ticks.has(saw_key) and int(obstacle.get("state").get("activation_tick", -1)) != int(_singleplayer_saw_activation_ticks[saw_key]):
				obstacle.call("set_activation_tick", int(_singleplayer_saw_activation_ticks[saw_key]))
			obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _update_falling_rocks(previous_x: float, current_x: float) -> void:
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks"):
			continue
		obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)
		if int(obstacle.call("get_activation_tick")) >= 0:
			continue
		var event: Dictionary = obstacle.get("event")
		var trigger_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", FALLING_ROCK_MODEL.TRIGGER_LEAD))
		if current_x >= trigger_x:
			obstacle.call("set_activation_tick", _singleplayer_simulation_tick + FALLING_ROCK_MODEL.DELIVERY_TICKS)
			obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _update_ghost_hazards(current_x: float) -> void:
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("ghost_hazards"):
			continue
		var event: Dictionary = obstacle.get("event")
		var event_id := str(event.get("event_id", ""))
		if not _singleplayer_ghost_activation_ticks.has(event_id) and current_x >= GHOST_HAZARD_MODEL.trigger_x(event):
			_singleplayer_ghost_activation_ticks[event_id] = _singleplayer_simulation_tick
			obstacle.call("set_activation_tick", _singleplayer_simulation_tick)
		obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _spawn_spike_group(count: int, from_ceiling: bool, start_x: float) -> void:
	for i in range(count):
		var spike_x := start_x + float(i) * SPIKE_GROUP_SPACING
		_spawn_obstacle_scene(SPIKE_SCENE, SPIKE_WIDTH, SPIKE_HEIGHT, from_ceiling, spike_x)

func _spawn_ledge(event: Dictionary, x: float) -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var has_spikes := bool(event.get("spiked_step", false))
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var change := float(event.get("height", 84.0))
	var low_limit := 40.0 if from_ceiling else 330.0
	var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
	var end_y: float = start_y + change if from_ceiling else start_y - change
	end_y = clampf(end_y, low_limit, high_limit)
	if absf(end_y - start_y) < 40.0:
		end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
	var step := LEDGE_SCENE.instantiate() as Node2D
	step.position = Vector2(x, 0.0)
	step.call("configure_step", start_y, end_y, from_ceiling, has_spikes)
	add_child(step)
	slopes.append(step)
	if has_spikes:
		var spike_count := int(event.get("count", 4))
		var spike_width := float(spike_count - 1) * SPIKE_GROUP_SPACING
		var points_left := bool(step.call("spikes_point_left"))
		var spike_start_x := x + STEP_SPIKE_CLEARANCE if points_left else x - spike_width - STEP_SPIKE_CLEARANCE
		_spawn_spike_group(spike_count, from_ceiling, spike_start_x)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y

func _spawn_course_slope(event: Dictionary, center_x: float) -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var low_limit := 40.0 if from_ceiling else 330.0
	var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
	var direction := float(event.get("slope_direction", 1.0))
	var end_y := clampf(start_y + direction * float(event.get("height", 65.0)), low_limit, high_limit)
	if absf(end_y - start_y) < 40.0:
		end_y = clampf(start_y - direction * 45.0, low_limit, high_limit)
	var slope := SLOPE_SCENE.instantiate() as Node2D
	slope.position = Vector2(center_x - SLOPE_WIDTH * 0.5, start_y)
	slope.call("configure", start_y, end_y, from_ceiling)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y
	add_child(slope)
	slopes.append(slope)

func _resolve_obstacle_interactions() -> void:
	for barrel in obstacles:
		if not is_instance_valid(barrel) or barrel.is_queued_for_deletion() or bool(barrel.call("is_destroying_now")) or not barrel.is_in_group("barrels"):
			continue
		var barrel_size: Vector2 = barrel.get("size")
		var radius := HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y)
		var center := HAZARD_RULES_SCRIPT.barrel_center(barrel.global_position, barrel_size.x, barrel_size.y, bool(barrel.get("from_ceiling")))
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
				var impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "spikes", Rect2(), obstacle.call("get_world_triangles"))
				if impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
					barrel.call("destroy")
					break
		if bool(barrel.call("is_destroying_now")):
			continue
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			if bool(terrain.get("has_spikes")) and terrain.has_method("get_world_spike_triangles"):
				var spike_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "spikes", Rect2(), terrain.call("get_world_spike_triangles"))
				if spike_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
					barrel.call("destroy")
					break
			# Barrels travel left with the world; allow them to roll off a floor drop.
			var is_floor_drop := not bool(terrain.call("is_ceiling_slope")) and float(terrain.call("get_start_y")) > float(terrain.call("get_end_y"))
			var step_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "step", terrain.call("get_wall_rect"))
			if not is_floor_drop and step_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
				barrel.call("destroy")
				break
		if bool(barrel.call("is_destroying_now")):
			continue
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if not obstacle.is_in_group("breakable"):
				continue
			var block_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "block", obstacle.call("get_hitbox_rect"))
			if block_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_AND_TARGET_DESTROYED:
				obstacle.call("destroy")
				if not bool(barrel.get("is_spiked")):
					barrel.call("destroy")
					break
	obstacles = obstacles.filter(func(obstacle: Node2D) -> bool:
		return is_instance_valid(obstacle) and not obstacle.is_queued_for_deletion()
	)

func _spawn_obstacle_scene(scene: PackedScene, width: float, height: float, from_ceiling: bool, x: float, motion_speed_multiplier: float = 1.0, spiked_barrel: bool = false) -> void:
	var obstacle := CoursePresentation.create_hazard(scene, Vector2(x, _ceiling_surface_y(x) if from_ceiling else _floor_surface_y(x)), Vector2(width, height), from_ceiling, _surface_angle_at(x, from_ceiling))
	obstacle.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	if obstacle.is_in_group("barrels") and obstacle.has_signal("destruction_started"):
		_connect_barrel_audio(obstacle)
	if obstacle.has_method("set_motion_speed_multiplier"):
		obstacle.call("set_motion_speed_multiplier", motion_speed_multiplier)
	if obstacle.has_method("set_spiked"):
		obstacle.call("set_spiked", spiked_barrel)
	add_child(obstacle)
	obstacles.append(obstacle)

func _on_obstacle_destroyed(obstacle: Node2D) -> void:
	obstacles.erase(obstacle)

func _on_barrel_destruction_started(obstacle: Node2D) -> void:
	var audible := is_instance_valid(obstacle) and _is_singleplayer_event_audible(obstacle.global_position.x)
	_play_singleplayer_sfx("barrel_destroy", "%s|barrel_destroy|%d" % [_singleplayer_audio_round_id, obstacle.get_instance_id()], audible)

func _connect_barrel_audio(obstacle: Node) -> void:
	if is_instance_valid(obstacle) and obstacle.has_signal("destruction_started"):
		var callback := Callable(self, "_on_barrel_destruction_started")
		if not obstacle.is_connected("destruction_started", callback):
			obstacle.connect("destruction_started", callback)

func _is_singleplayer_event_audible(world_x: float) -> bool:
	var camera_left := float(camera.get("left")) if is_instance_valid(camera) else course_distance
	var view_width := screen_width
	if is_instance_valid(camera):
		view_width = float(camera.get("view_size").x)
	return SfxAudibilityRules.is_world_x_audible(world_x, camera_left, view_width)

func _on_rock_impact_started(event_id: String) -> void:
	_play_singleplayer_sfx("rock_impact", "%s|rock_impact|%s" % [_singleplayer_audio_round_id, event_id])

func _spawn_coin_row() -> void:
	var coin_count := randi_range(1, 3)
	for i in range(coin_count):
		var coin := COIN_SCENE.instantiate() as Node2D
		coin.connect("collected", Callable(run_state, "add_coins"))
		_connect_coin_audio(coin, "coin:%d" % coin.get_instance_id())
		var coin_x := course_distance + screen_width + 70.0 + float(i) * 48.0
		var placed := false
		for attempt in range(20):
			var coin_y := randf_range(_ceiling_surface_y(coin_x) + 28.0, _floor_surface_y(coin_x) - 28.0)
			coin.position = Vector2(coin_x, coin_y)
			if _coin_position_is_clear(coin):
				placed = true
				break
		if not placed:
			coin.queue_free()
			continue
		add_child(coin)
		coins.append(coin)

func _spawn_shared_coins() -> void:
	if _active_seed <= 0 or _manifest_builder == null or _shared_coin_planner == null:
		return
	var horizon := course_distance + screen_width + 1400.0
	if PLAYER_X + horizon >= _shared_coin_planned_until + 100.0:
		var source_events: Array[Dictionary] = course_generator.get_planned_events()
		var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
		var resolved_events: Array[Dictionary] = _manifest_builder.call("_resolve_events", source_events, ceili(horizon), _active_seed_version, biome_start_offset)
		var planned: Array[Dictionary] = _shared_coin_planner.extend(PLAYER_X + horizon, resolved_events, WORLD_HEIGHT - 80.0, 80.0, 0)
		_pending_shared_coins.append_array(planned)
		_shared_coin_planned_until = PLAYER_X + horizon
	var spawn_limit := PLAYER_X + course_distance + COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
	for index in range(_pending_shared_coins.size() - 1, -1, -1):
		var item: Dictionary = _pending_shared_coins[index]
		var entity_id := str(item.get("entity_id", ""))
		if entity_id.is_empty() or _spawned_shared_coin_ids.has(entity_id) or float(item.get("world_x", INF)) > spawn_limit:
			continue
		_pending_shared_coins.remove_at(index)
		_spawned_shared_coin_ids[entity_id] = true
		var coin := COIN_SCENE.instantiate() as Node2D
		coin.connect("collected", Callable(run_state, "add_coins"))
		coin.connect("collected", Callable(self, "_on_shared_coin_collected").bind(entity_id))
		_connect_coin_audio(coin, "coin:%s" % entity_id)
		coin.position = Vector2(float(item.world_x), float(item.world_y))
		add_child(coin)
		coins.append(coin)

func _on_shared_coin_collected(_value: int, entity_id: String) -> void:
	_spawned_shared_coin_ids.erase(entity_id)

func _connect_coin_audio(coin: Node, event_id: String) -> void:
	var event_key := "%s|%s" % [_singleplayer_audio_round_id, event_id]
	coin.connect("visual_collection_started", Callable(self, "_on_singleplayer_coin_visual_started").bind(coin, event_key))
	coin.connect("visual_collection_cancelled", Callable(SfxController, "clear_event_key").bind(event_key))

func _on_singleplayer_coin_visual_started(coin: Node2D, event_key: String) -> void:
	if not is_instance_valid(coin):
		return
	var camera_left := float(player.get("world_x")) - PLAYER_X if is_instance_valid(player) else course_distance
	var audible := coin.global_position.x >= camera_left - 64.0 and coin.global_position.x <= camera_left + screen_width + 64.0
	_play_singleplayer_sfx("coin", event_key, audible)

func _play_singleplayer_sfx(event_name: String, event_key: String, audible: bool = true) -> bool:
	# Menu preview/demo runs deliberately have no gameplay audio identity.
	if demo_mode or _singleplayer_audio_round_id.is_empty():
		return false
	return SfxController.play_event(event_name, event_key, audible)

func _on_singleplayer_gravity_flipped() -> void:
	_play_singleplayer_sfx("gravity_flip", "%s|gravity_flip|%d" % [_singleplayer_audio_round_id, _singleplayer_simulation_tick])

func _on_singleplayer_ghost_phase_changed(event_id: String, phase: String, event: Dictionary) -> void:
	if phase != GHOST_HAZARD_MODEL.WARNING:
		return
	_ghost_warning_pulse.call("observe_warning", event_id, bool(event.get("from_ceiling", false)))
	queue_redraw()
	var event_x := float(event.get("x", 0.0))
	var camera_left := float(player.get("world_x")) - PLAYER_X if is_instance_valid(player) else course_distance
	var audible := event_x >= camera_left - 64.0 and event_x <= camera_left + screen_width + 64.0
	_play_singleplayer_sfx("ghost_warning", "%s|ghost_warning|%s" % [_singleplayer_audio_round_id, event_id], audible)

func _spawn_loot_pickup(event: Dictionary) -> void:
	if not RUN_LOOT_ENABLED or demo_mode or not AuthService.is_authenticated:
		return
	var pickup := LOOT_PICKUP_SCENE.instantiate() as Node2D
	var pickup_distance := float(event.get("course_distance", 0.0))
	var pickup_x := PLAYER_X + pickup_distance
	pickup.call("configure", int(event.get("pickup_index", 0)))
	var placed := false
	for attempt in range(24):
		var ceiling_y := _ceiling_surface_y(pickup_x) + 52.0
		var floor_y := _floor_surface_y(pickup_x) - 52.0
		if floor_y <= ceiling_y:
			break
		pickup.position = Vector2(pickup_x, loot_spawn_planner.random_between(ceiling_y, floor_y))
		if _loot_position_is_clear(pickup):
			placed = true
			break
	if not placed:
		pickup.queue_free()
		return
	pickup.connect("collected", Callable(run_state, "record_loot_pickup"))
	add_child(pickup)
	loot_pickups.append(pickup)

func _loot_position_is_clear(pickup: Node2D) -> bool:
	var rect: Rect2 = pickup.call("get_hitbox_rect")
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.call("get_hitbox_rect").grow(26.0).intersects(rect):
			return false
	for coin in coins:
		if is_instance_valid(coin) and coin.call("get_hitbox_rect").grow(12.0).intersects(rect):
			return false
	return true

func _coin_position_is_clear(coin: Node2D) -> bool:
	var coin_rect: Rect2 = coin.call("get_hitbox_rect")
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.call("get_hitbox_rect").grow(4.0).intersects(coin_rect):
			return false
	return true

func _update_moving_slopes(_movement: float) -> void:
	var active_slopes: Array[Node2D] = []
	var camera_left := course_distance
	for slope in slopes:
		if not is_instance_valid(slope):
			continue
		var end_x: float = slope.call("get_end_x")
		if end_x <= camera_left:
			if bool(slope.call("is_ceiling_slope")):
				ceiling_level_y = float(slope.call("get_end_y"))
			else:
				floor_level_y = float(slope.call("get_end_y"))
			slope.queue_free()
		elif slope.position.x > camera_left - SLOPE_WIDTH:
			active_slopes.append(slope)
		else:
			slope.queue_free()
	slopes = active_slopes

func _player_hits_obstacle(obstacle: Node2D) -> bool:
	var player_rect: Rect2 = player.call("get_player_rect")
	if obstacle.has_method("intersects_rect"):
		return bool(obstacle.call("intersects_rect", player_rect))
	var obstacle_rect: Rect2 = obstacle.call("get_hitbox_rect")
	return player_rect.intersects(obstacle_rect)

func _earliest_lethal_contact_fraction(start_rect: Rect2, finish_rect: Rect2) -> float:
	var displacement := finish_rect.position - start_rect.position
	var earliest := 1.0 if player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0 else INF
	var immune := bool(player.call("is_spike_immune"))
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or bool(obstacle.call("is_destroying_now")):
			continue
		var kind := "edge" if obstacle.is_in_group("blocking_edges") else "rect"
		var fraction := -1.0
		if obstacle.is_in_group("falling_rocks") or obstacle.is_in_group("saw_blades"):
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect, maxi(_singleplayer_simulation_tick - 1, 0), _singleplayer_simulation_tick, Vector2(34.0, 44.0)))
		elif obstacle.is_in_group("lava_hazards") and obstacle.has_method("swept_contact_fraction"):
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect, maxi(_singleplayer_simulation_tick - 1, 0), _singleplayer_simulation_tick, start_rect.size))
		elif obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
			if immune:
				continue
			for triangle in obstacle.call("get_world_triangles"):
				var candidate := HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, triangle)
				if candidate >= 0.0 and (fraction < 0.0 or candidate < fraction):
					fraction = candidate
		elif obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			var center := HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
			var start_center: Vector2 = _step_start_barrel_centers.get(obstacle.get_instance_id(), center)
			var relative_displacement := displacement - (center - start_center)
			fraction = HAZARD_RULES_SCRIPT.swept_rect_circle_fraction(start_rect, relative_displacement, start_center, HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y))
		else:
			var target: Rect2 = obstacle.call("get_hitbox_rect")
			if kind != "edge":
				var polygon := PackedVector2Array([target.position, Vector2(target.end.x, target.position.y), target.end, Vector2(target.position.x, target.end.y)])
				fraction = HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, polygon)
		if fraction >= 0.0:
			earliest = minf(earliest, fraction)
	for terrain in slopes:
		if not is_instance_valid(terrain) or not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")) or immune:
			continue
		if terrain.has_method("get_world_spike_triangles"):
			for triangle in terrain.call("get_world_spike_triangles"):
				var candidate := HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, triangle)
				if candidate >= 0.0:
					earliest = minf(earliest, candidate)
	return earliest

func _saw_endpoint_impact(player_rect: Rect2, obstacle: Node2D) -> int:
	if not is_instance_valid(obstacle) or not obstacle.is_in_group("saw_blades"):
		return HAZARD_RULES_SCRIPT.PlayerImpact.NONE
	var saw_state: Dictionary = obstacle.get("state")
	if not bool(saw_state.get("active", false)) or bool(saw_state.get("removed", false)):
		return HAZARD_RULES_SCRIPT.PlayerImpact.NONE
	var center := Vector2(float(saw_state.get("x", 0.0)), float(saw_state.get("y", 0.0)))
	return HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL if HAZARD_RULES_SCRIPT.circle_intersects_rect(center, SAW_BLADE_MODEL.radius_for_state(saw_state), player_rect) else HAZARD_RULES_SCRIPT.PlayerImpact.NONE

func _draw() -> void:
	var draw_started_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_draw_background()
	var background_draw_done_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	var track_draw_started_usec := background_draw_done_usec
	_draw_track()
	var track_draw_done_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_draw_seed_finish_markers()
	_draw_falling_rock_warning_markers()
	_draw_rock_hud_warning()
	_draw_ghost_hud_warning()
	if render_diagnostics_enabled and not _render_diagnostic_frames.is_empty():
		var frame_record: Dictionary = _render_diagnostic_frames.back()
		if int(frame_record.get("render_callback_index", -1)) == _render_callback_index:
			frame_record["background_draw_usec"] = background_draw_done_usec - draw_started_usec
			frame_record["track_draw_usec"] = track_draw_done_usec - track_draw_started_usec
			frame_record["canvas_submission_usec"] = Time.get_ticks_usec() - draw_started_usec
			frame_record["canvas_submission_end_usec"] = Time.get_ticks_usec()
			_render_diagnostic_frames[_render_diagnostic_frames.size() - 1] = frame_record

func _draw_falling_rock_warning_markers() -> void:
	if not is_instance_valid(camera):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5
	var view_right := view_left + screen_width
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks") or not FALLING_ROCK_MODEL.offscreen_marker_active(str(obstacle.call("get_phase"))) or obstacle.global_position.x <= view_right:
			continue
		var marker_x := view_right - 44.0
		var event: Dictionary = obstacle.get("event")
		var floor_y := float(event.get("floor_y", WORLD_HEIGHT - 80.0))
		ROCK_WARNING_ICON_SCRIPT.draw(self, Vector2(marker_x, floor_y - 64.0), 38.0)
		ROCK_WARNING_ICON_SCRIPT.draw_forward_chevron(self, Vector2(marker_x + 25.0, floor_y - 64.0), 8.0)

func _update_singleplayer_rock_warning_pulse(delta: float) -> void:
	_rock_warning_pulse.call("advance", delta)
	var warnings: Array[Dictionary] = []
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks"):
			continue
		var phase := str(obstacle.call("get_phase"))
		if phase != "warning":
			continue
		var event: Dictionary = obstacle.get("event")
		warnings.append({"event_id": str(event.get("event_id", "")), "phase": phase})
	_rock_warning_pulse.call("observe_warning_events", warnings)
	_rock_warning_accessibility_button.visible = not game_over and bool(_rock_warning_pulse.call("is_active"))
	if _rock_warning_accessibility_button.visible:
		_rock_warning_accessibility_button.position = ROCK_WARNING_PULSE_SCRIPT.screen_center(get_viewport_rect().size) - Vector2(24.0, 24.0)

func _draw_rock_hud_warning() -> void:
	if not bool(_rock_warning_pulse.call("is_active")):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5 if is_instance_valid(camera) else _render_course_distance
	var viewport_size := Vector2(screen_width, screen_height)
	var center := ROCK_WARNING_PULSE_SCRIPT.world_center(view_left, viewport_size)
	ROCK_WARNING_ICON_SCRIPT.draw(self, center, 56.0 * float(_rock_warning_pulse.call("scale")), Color("ff814f"), float(_rock_warning_pulse.call("alpha")))

func _draw_ghost_hud_warning() -> void:
	if not bool(_ghost_warning_pulse.call("is_active")):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5 if is_instance_valid(camera) else _render_course_distance
	_ghost_warning_pulse.call("draw", self, Vector2(view_left + screen_width * 0.5, screen_height * 0.5))

func _on_seed_leaderboard_received(version: int, seed: int, rows: Array, _error_message: String) -> void:
	if version != _active_seed_version or seed != _active_seed:
		return
	_seed_scores.clear()
	for row in rows:
		if row is Dictionary:
			_seed_scores.append(row)

func _mark_crossed_seed_records(previous_distance: float, current_distance: float) -> void:
	if _seed_scores.is_empty() or current_distance <= previous_distance:
		return
	for index in range(mini(_seed_scores.size(), 5)):
		var score: Dictionary = _seed_scores[index]
		var record_distance := int(score.get("best_distance_m", 0)) * 10
		if record_distance <= previous_distance or record_distance > current_distance:
			continue
		var nickname := str(score.get("player_name", ""))
		hud.call("show_pass_flash", nickname)
	queue_redraw()

func _draw_seed_finish_markers() -> void:
	if _seed_scores.is_empty():
		return
	var current_distance := float(run_state.get("distance_m"))
	var rank_colors := [Color("f5d45e"), Color("42d6c5"), Color("ff647c"), Color("b69cff"), Color("8ee0a1")]
	for index in range(mini(_seed_scores.size(), 5)):
		var score: Dictionary = _seed_scores[index]
		var record_distance_m := int(score.get("best_distance_m", 0))
		var marker_x := PLAYER_X + float(record_distance_m * 10)
		var marker_screen_x := marker_x - course_distance
		if marker_screen_x < 0.0 or marker_screen_x > screen_width:
			continue
		var marker_color: Color = rank_colors[mini(index, rank_colors.size() - 1)]
		var y := 0.0
		while y < screen_height:
			draw_line(Vector2(marker_x, y), Vector2(marker_x, minf(y + 10.0, screen_height)), marker_color, 2.0, true)
			y += 19.0
		var nickname := str(score.get("player_name", ""))
		var label := "%s · %dm" % [nickname.left(8), record_distance_m]
		var label_center_y := 148.0 + float(index % 3) * 64.0
		draw_set_transform(Vector2(marker_x + 5.0, label_center_y), PI / 2.0)
		draw_string(ThemeDB.fallback_font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 9, marker_color)
		draw_set_transform(Vector2.ZERO)

func _draw_background() -> void:
	var view_left := _render_course_distance
	# The same distance-addressed backdrop renderer is used by MP presentation.
	# SP world coordinates begin at PLAYER_X, matching manifest.start_x in MP.
	# Normalize backdrop phase by that same origin so absolute world points match.
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	BIOME_RENDERER_SCRIPT.draw_backdrop(self, view_left, Vector2(screen_width, screen_height), BIOME_RENDERER_SCRIPT.course_distance_at_world_x(view_left + PLAYER_X, PLAYER_X) + biome_start_offset, _active_seed_version)

func _draw_track() -> void:
	var surface_gaps: Array[Dictionary] = []
	for gap in gaps:
		if is_instance_valid(gap):
			var half_width := float(gap.get("width")) * 0.5
			surface_gaps.append({"start": gap.position.x - half_width, "end": gap.position.x + half_width, "ceiling": bool(gap.get("from_ceiling"))})
	var terrain_boundaries: Array[float] = []
	var step_positions: Array[float] = []
	for terrain in slopes:
		terrain_boundaries.append(float(terrain.call("get_start_x")))
		terrain_boundaries.append(float(terrain.call("get_end_x")))
		if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")):
			step_positions.append(float(terrain.call("get_start_x")))
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	COURSE_SURFACE_RENDERER.draw_track(self, _render_course_distance, Vector2(screen_width, screen_height), surface_gaps, terrain_boundaries, step_positions, Callable(self, "_surface_y_at"), 0.0, null, BIOME_RENDERER_SCRIPT.course_distance_at_world_x(PLAYER_X, 0.0) - biome_start_offset, _active_seed_version)
