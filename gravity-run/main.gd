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
const RUN_LOOT_ENABLED := false
const SLOPE_SCENE := preload("res://terrain/slope.tscn")
const LEDGE_SCENE := preload("res://terrain/ledge.tscn")
const COURSE_RULESET_SCRIPT := preload("res://systems/course_generation_ruleset.gd")
const COURSE_RUN_DEFINITION_SCRIPT := preload("res://systems/course_run_definition.gd")
const TRACK_GAP_SCRIPT := preload("res://terrain/track_gap.gd")
const COURSE_SURFACE_RENDERER := preload("res://systems/course_surface_renderer.gd")

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
var floor_level_y := screen_height - 80.0
var ceiling_level_y := 80.0
var planned_floor_level_y := screen_height - 80.0
var planned_ceiling_level_y := 80.0
var game_over := false
var run_blocked := false
var demo_flip_timer := 1.0
var demo_restart_timer := 0.0
var _speed_debug_visible := false

func _ready() -> void:
	course_generator = COURSE_GENERATOR_SCRIPT.new()
	loot_spawn_planner = LOOT_PLANNER_SCRIPT.new()
	_default_ruleset = COURSE_RULESET_SCRIPT.new()
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
	player.connect("status_changed", Callable(hud, "update_player_status"))
	ChallengeService.leaderboard_received.connect(_on_seed_leaderboard_received)
	if demo_mode:
		hud.visible = false
		$PauseMenu.visible = false
	_start_run()

func _start_run() -> void:
	run_end_panel.visible = false
	if not demo_mode:
		AchievementService.begin_run()
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
	run_blocked = false
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
	camera.position = Vector2(
		float(player.get("world_x")) + screen_width * 0.5 - PLAYER_X,
		screen_height * 0.5
	)

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

func _physics_process(delta: float) -> void:
	if game_over:
		if demo_mode:
			demo_restart_timer += delta
			if demo_restart_timer >= 0.8:
				_start_run()
		return

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
		for event in course_generator.pop_events_until(spawn_line):
			_spawn_course_event(event)
		if RUN_LOOT_ENABLED:
			for loot_event in loot_spawn_planner.pop_events_until(spawn_line):
				_spawn_loot_pickup(loot_event)
		_update_hazard_discoveries()
		if coin_distance >= COIN_DISTANCE:
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
	_update_camera()
	if player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0:
		_end_run()

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
		else:
			var kind := "edge" if obstacle.is_in_group("blocking_edges") else "rect"
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, kind, obstacle.call("get_hitbox_rect"))
		if impact == HAZARD_RULES_SCRIPT.PlayerImpact.BLOCKED:
			blocked_by_edge = true
		elif impact == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
			_end_run()
			break
	if not game_over:
		var player_rect: Rect2 = player.call("get_player_rect")
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			var spike_triangles: Array = terrain.call("get_world_spike_triangles") if terrain.has_method("get_world_spike_triangles") else []
			if HAZARD_RULES_SCRIPT.player_impact(player_rect, "spikes", Rect2(), spike_triangles, Vector2.ZERO, 0.0, bool(player.call("is_spike_immune"))) == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
				_end_run()
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
	run_blocked = blocked_by_edge and not game_over
	hud.call("set_run_blocked", run_blocked)
	if not demo_mode:
		for coin in coins:
			if _player_hits_obstacle(coin):
				coin.call("collect")
		for pickup in loot_pickups:
			if _player_hits_obstacle(pickup):
				pickup.call("collect")
	var camera_left := course_distance
	coins = coins.filter(func(coin: Node2D) -> bool: return is_instance_valid(coin) and not bool(coin.call("is_collected")) and coin.position.x > camera_left - 100.0)
	loot_pickups = loot_pickups.filter(func(pickup: Node2D) -> bool: return is_instance_valid(pickup) and pickup.position.x > camera_left - 100.0)
	queue_redraw()

func _end_run() -> void:
	game_over = true
	player.call("set_input_enabled", false)
	if not demo_mode:
		AchievementService.finish_run()
		run_state.call("finish_run")
		run_end_panel.call("show_result", float(run_state.get("distance_m")), int(run_state.get("coins")), ChallengeService.get_challenge_code(), ChallengeService.active, str(run_state.get("last_run_id")))

func retry_run() -> void:
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
		var obstacle_side := -1 if bool(obstacle.get("from_ceiling")) else 1
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
		if (node.has_method("is_destroying_now") and bool(node.call("is_destroying_now"))) or node.position.x > camera_left - 220.0:
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
				_spawn_obstacle_scene(BARREL_SCENE, HAZARD_RULES_SCRIPT.BARREL_WIDTH, height, false, event_x + early_spawn_offset - chain_width * 0.5 + float(index) * HAZARD_RULES_SCRIPT.BARREL_CHAIN_SPACING, motion_speed_multiplier)
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
		_:
			_spawn_custom_course_event(event, event_x)

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
				barrel.call("destroy")
				break
	obstacles = obstacles.filter(func(obstacle: Node2D) -> bool:
		return is_instance_valid(obstacle) and not obstacle.is_queued_for_deletion()
	)

func _spawn_obstacle_scene(scene: PackedScene, width: float, height: float, from_ceiling: bool, x: float, motion_speed_multiplier: float = 1.0) -> void:
	var obstacle := scene.instantiate() as Node2D
	obstacle.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	obstacle.position = Vector2(x, _ceiling_surface_y(x) if from_ceiling else _floor_surface_y(x))
	obstacle.call("configure", Vector2(width, height), from_ceiling)
	if obstacle.has_method("set_motion_speed_multiplier"):
		obstacle.call("set_motion_speed_multiplier", motion_speed_multiplier)
	obstacle.rotation = _surface_angle_at(x, from_ceiling)
	add_child(obstacle)
	obstacles.append(obstacle)

func _on_obstacle_destroyed(obstacle: Node2D) -> void:
	obstacles.erase(obstacle)

func _spawn_coin_row() -> void:
	var coin_count := randi_range(1, 3)
	for i in range(coin_count):
		var coin := COIN_SCENE.instantiate() as Node2D
		coin.connect("collected", Callable(run_state, "add_coins"))
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

func _draw() -> void:
	_draw_background()
	_draw_track()
	_draw_seed_finish_markers()

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
	var view_left := course_distance
	draw_rect(Rect2(Vector2(view_left, 0.0), Vector2(screen_width, screen_height)), Color("101827"))
	# Use the continuous course coordinate: integer meter rounding made the
	# stars drift gently while course objects remain at fixed world coordinates.
	for i in range(18):
		var x := view_left + fposmod(float(i * 83) + course_distance * 0.12, screen_width)
		draw_circle(Vector2(x, 58.0 + float((i * 47) % 390)), 1.5, Color("26364b"))

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
	COURSE_SURFACE_RENDERER.draw_track(self, course_distance, Vector2(screen_width, screen_height), surface_gaps, terrain_boundaries, step_positions, Callable(self, "_surface_y_at"), 0.0)
