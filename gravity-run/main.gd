extends Node2D

@export var demo_mode := false

var screen_width := 960.0
var screen_height := 540.0
const RUN_SPEED_START := 330.0
const COIN_DISTANCE := 720.0
const SLOPE_WIDTH := 440.0
const PLAYER_X := 180.0
const SPIKE_WIDTH := 28.0
const SPIKE_HEIGHT := 32.0
const SPIKE_GROUP_SPACING := 32.0
const STEP_SPIKE_CLEARANCE := 32.0
const DEMO_AI_LOOKAHEAD := 700.0
const SPIKE_SCENE := preload("res://hazards/spikes.tscn")
const BLOCK_SCENE := preload("res://hazards/block.tscn")
const BARREL_SCENE := preload("res://hazards/barrel.tscn")
const COIN_SCENE := preload("res://collectibles/coin.tscn")
const SLOPE_SCENE := preload("res://terrain/slope.tscn")
const LEDGE_SCENE := preload("res://terrain/ledge.tscn")
const COURSE_GENERATOR_SCRIPT := preload("res://systems/course_generator.gd")
const COURSE_RULESET_SCRIPT := preload("res://systems/course_generation_ruleset.gd")
const COURSE_RUN_DEFINITION_SCRIPT := preload("res://systems/course_run_definition.gd")
const TRACK_GAP_SCRIPT := preload("res://terrain/track_gap.gd")

@onready var player: Node2D = $Player
@onready var run_state: Node = $RunState
@onready var hud: Node2D = $HUD
@onready var run_end_panel: CanvasLayer = $RunEndPanel

var obstacles: Array[Node2D] = []
var coins: Array[Node2D] = []
var slopes: Array[Node2D] = []
var gaps: Array[Node2D] = []
var _seed_scores: Array[Dictionary] = []
var _pending_hazard_discoveries: Array[Dictionary] = []
var _active_seed := 0
var _active_seed_version := 0
var _default_ruleset: Resource
var course_generator: CourseGenerator
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

func _ready() -> void:
	course_generator = COURSE_GENERATOR_SCRIPT.new()
	_default_ruleset = COURSE_RULESET_SCRIPT.new()
	_sync_screen_size()
	get_viewport().size_changed.connect(_sync_screen_size)
	run_state.connect("stats_changed", Callable(self, "_on_run_stats_changed"))
	run_state.connect("achievement_metrics_changed", Callable(self, "_on_run_achievement_metrics_changed"))
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
	player.call("reset_to_floor", screen_height - 80.0)
	run_state.call("start_run")
	course_distance = 0.0
	var run_seed := ChallengeService.begin_run()
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
	floor_level_y = screen_height - 80.0
	ceiling_level_y = 80.0
	planned_floor_level_y = floor_level_y
	planned_ceiling_level_y = ceiling_level_y
	_clear_nodes(obstacles)
	_clear_nodes(coins)
	_clear_nodes(slopes)
	_clear_nodes(gaps)
	game_over = false
	run_blocked = false
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
	var old_height := screen_height
	if is_equal_approx(viewport_size.x, screen_width) and is_equal_approx(viewport_size.y, screen_height):
		return
	screen_width = viewport_size.x
	screen_height = viewport_size.y
	if not is_equal_approx(old_height, screen_height):
		var height_scale := maxf(screen_height - 112.0, 1.0) / maxf(old_height - 112.0, 1.0)
		floor_level_y = _scale_track_y(floor_level_y, height_scale)
		ceiling_level_y = _scale_track_y(ceiling_level_y, height_scale)
		planned_floor_level_y = _scale_track_y(planned_floor_level_y, height_scale)
		planned_ceiling_level_y = _scale_track_y(planned_ceiling_level_y, height_scale)
		for terrain in slopes:
			if terrain.has_method("scale_track_height"):
				terrain.call("scale_track_height", height_scale)
		for obstacle in obstacles:
			obstacle.position.y = _scale_track_y(obstacle.position.y, height_scale)
			if obstacle.has_method("scale_track_height"):
				obstacle.call("scale_track_height", height_scale)
		for coin in coins:
			coin.position.y = _scale_track_y(coin.position.y, height_scale)
		if is_instance_valid(player):
			player.position.y = _scale_track_y(player.position.y, height_scale)
			player.set("vertical_speed", float(player.get("vertical_speed")) * height_scale)
	if is_instance_valid(hud):
		hud.queue_redraw()
	queue_redraw()

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
	if game_over:
		if event is InputEventScreenTouch and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
	var movement := speed * delta if not run_blocked else 0.0
	if not run_blocked:
		var previous_distance := float(run_state.get("distance_m"))
		run_state.call("add_distance", movement)
		var current_distance := float(run_state.get("distance_m"))
		_mark_crossed_seed_records(previous_distance, current_distance)
		course_distance += movement
		coin_distance += movement
		course_generator.ensure_horizon(course_distance + screen_width + 1400.0, speed, screen_height, screen_width + 40.0 - PLAYER_X)
		var spawn_line := course_distance + COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE
		for event in course_generator.pop_events_until(spawn_line):
			_spawn_course_event(event)
		_update_hazard_discoveries()
		if coin_distance >= COIN_DISTANCE:
			coin_distance -= COIN_DISTANCE
			_spawn_coin_row()

	_update_moving_slopes(movement)
	_update_moving_nodes(obstacles, movement, delta)
	_update_moving_nodes(coins, movement, delta)
	_update_moving_nodes(gaps, movement, delta)
	_resolve_obstacle_interactions()

	if demo_mode:
		_update_demo_ai(delta)
	player.call("advance", delta, _floor_surface_y(PLAYER_X), _ceiling_surface_y(PLAYER_X), _surface_is_solid_at_x(PLAYER_X, false), _surface_is_solid_at_x(PLAYER_X, true))
	if player.position.y < -64.0 or player.position.y > screen_height + 64.0:
		_end_run()

	var blocked_by_edge := false
	for obstacle in obstacles:
		if bool(obstacle.call("is_destroying_now")):
			continue
		var player_rect: Rect2 = player.call("get_player_rect")
		if obstacle.has_method("intersects_spikes") and bool(obstacle.call("intersects_spikes", player_rect)):
			if not bool(player.call("is_spike_immune")):
				_end_run()
				break
		if _player_hits_obstacle(obstacle):
			if obstacle.is_in_group("blocking_edges"):
				blocked_by_edge = true
				continue
			if bool(player.call("is_spike_immune")) and obstacle.is_in_group("spikes"):
				continue
			_end_run()
			break
	if not game_over:
		var player_rect: Rect2 = player.call("get_player_rect")
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			if bool(terrain.call("intersects_spikes", player_rect)) and not bool(player.call("is_spike_immune")):
				_end_run()
				break
			if bool(terrain.call("intersects_wall", player_rect)):
				blocked_by_edge = true
	run_blocked = blocked_by_edge and not game_over
	hud.call("set_run_blocked", run_blocked)
	if not demo_mode:
		for coin in coins:
			if _player_hits_obstacle(coin):
				coin.call("collect")
	coins = coins.filter(func(coin: Node2D) -> bool: return is_instance_valid(coin) and not bool(coin.call("is_collected")) and coin.position.x > -100.0)
	queue_redraw()

func _end_run() -> void:
	game_over = true
	player.call("set_input_enabled", false)
	if not demo_mode:
		run_state.call("finish_run")
		run_end_panel.call("show_result", float(run_state.get("distance_m")), int(run_state.get("coins")), ChallengeService.get_challenge_code(), ChallengeService.active)

func retry_run() -> void:
	_start_run()

func return_to_main_menu() -> void:
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
		else:
			node.position.x -= movement
	var active_nodes: Array[Node2D] = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if (node.has_method("is_destroying_now") and bool(node.call("is_destroying_now"))) or node.position.x > -200.0:
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
	var distance_m := float(run_state.get("distance_m"))
	return (RUN_SPEED_START + minf(distance_m * 0.012, 170.0)) * float(player.call("get_speed_multiplier"))

func _spawn_course_event(event: Dictionary) -> void:
	var event_x := PLAYER_X + float(event["course_distance"]) - course_distance
	var hazard_id := str(event.get("id", ""))
	if not hazard_id.is_empty():
		_pending_hazard_discoveries.append({
			"hazard_id": hazard_id,
			"course_distance": float(event.get("course_distance", 0.0)),
			"width": float(event.get("width", 48.0)),
		})
	var from_ceiling := bool(event.get("from_ceiling", false))
	var width := float(event.get("width", 48.0))
	var height := float(event.get("height", 72.0))
	match StringName(event.get("kind", "")):
		&"spikes":
			var count := int(event.get("count", 4))
			var group_width := float(count - 1) * SPIKE_GROUP_SPACING
			_spawn_spike_group(count, from_ceiling, event_x - group_width * 0.5)
		&"block":
			_spawn_obstacle_scene(BLOCK_SCENE, width, height, from_ceiling, event_x)
		&"barrels":
			var count := int(event.get("count", 1))
			var chain_width := float(count - 1) * 70.0
			for index in range(count):
				_spawn_obstacle_scene(BARREL_SCENE, 54.0, height, false, event_x - chain_width * 0.5 + float(index) * 70.0, float(event.get("motion_speed_multiplier", 1.0)))
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
	var high_limit := 220.0 if from_ceiling else screen_height - 40.0
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
	var high_limit := 220.0 if from_ceiling else screen_height - 40.0
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
		var barrel_rect: Rect2 = barrel.call("get_hitbox_rect")
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if obstacle.is_in_group("spikes") and obstacle.has_method("intersects_rect") and bool(obstacle.call("intersects_rect", barrel_rect)):
				barrel.call("destroy")
				break
		if bool(barrel.call("is_destroying_now")):
			continue
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			# Barrels travel left with the world; allow them to roll off a floor drop.
			var is_floor_drop := not bool(terrain.call("is_ceiling_slope")) and float(terrain.call("get_start_y")) > float(terrain.call("get_end_y"))
			if not is_floor_drop and bool(barrel.call("intersects_rect", terrain.call("get_wall_rect"))):
				barrel.call("destroy")
				break
		if bool(barrel.call("is_destroying_now")):
			continue
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if not obstacle.is_in_group("breakable"):
				continue
			if bool(barrel.call("intersects_rect", obstacle.call("get_hitbox_rect"))):
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
		var coin_x := screen_width + 70.0 + float(i) * 48.0
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

func _coin_position_is_clear(coin: Node2D) -> bool:
	var coin_rect: Rect2 = coin.call("get_hitbox_rect")
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.call("get_hitbox_rect").grow(4.0).intersects(coin_rect):
			return false
	return true

func _update_moving_slopes(movement: float) -> void:
	for slope in slopes:
		slope.position.x -= movement
	var active_slopes: Array[Node2D] = []
	for slope in slopes:
		if not is_instance_valid(slope):
			continue
		var end_x: float = slope.call("get_end_x")
		if end_x <= 0.0:
			if bool(slope.call("is_ceiling_slope")):
				ceiling_level_y = float(slope.call("get_end_y"))
			else:
				floor_level_y = float(slope.call("get_end_y"))
			slope.queue_free()
		elif slope.position.x > -SLOPE_WIDTH:
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
		var marker_x := PLAYER_X + float(record_distance_m * 10) - current_distance
		if marker_x < 0.0 or marker_x > screen_width:
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
	draw_rect(Rect2(Vector2.ZERO, Vector2(screen_width, screen_height)), Color("101827"))
	# Use the continuous course coordinate: integer meter rounding made the
	# stars jump in small steps, especially visible through moving track gaps.
	var star_scroll := course_distance * 0.12
	for i in range(18):
		var x := fposmod(float(i * 83) + star_scroll, screen_width)
		draw_circle(Vector2(x, 58.0 + float((i * 47) % 390)), 1.5, Color("26364b"))

func _draw_track() -> void:
	_draw_track_surface(true)
	_draw_track_surface(false)

func _draw_track_surface(ceiling: bool) -> void:
	var surface_gaps: Array[Dictionary] = []
	for gap in gaps:
		if is_instance_valid(gap) and bool(gap.get("from_ceiling")) == ceiling:
			var half_width := float(gap.get("width")) * 0.5
			surface_gaps.append({"start": gap.position.x - half_width, "end": gap.position.x + half_width})
	surface_gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["start"]) < float(b["start"]))
	var cursor := 0.0
	for gap_interval in surface_gaps:
		var gap_start := clampf(float(gap_interval["start"]), 0.0, screen_width)
		var gap_end := clampf(float(gap_interval["end"]), 0.0, screen_width)
		if gap_end <= cursor:
			continue
		if gap_start > cursor:
			_draw_track_surface_segment(ceiling, cursor, gap_start)
		cursor = maxf(cursor, gap_end)
	if cursor < screen_width:
		_draw_track_surface_segment(ceiling, cursor, screen_width)

func _draw_track_surface_segment(ceiling: bool, start_x: float, end_x: float) -> void:
	if end_x - start_x < 0.5:
		return
	var surface_points := _get_surface_points(ceiling, start_x, end_x)
	var fill_points := PackedVector2Array()
	if ceiling:
		fill_points.append(Vector2(start_x, 0.0))
		fill_points.append_array(surface_points)
		fill_points.append(Vector2(end_x, 0.0))
	else:
		fill_points.append_array(surface_points)
		fill_points.append(Vector2(end_x, screen_height))
		fill_points.append(Vector2(start_x, screen_height))
	draw_colored_polygon(fill_points, Color("202d40"))
	draw_polyline(surface_points, Color("42d6c5"), 3.0, true)

func _get_surface_points(ceiling: bool, start_x: float = 0.0, end_x: float = -1.0) -> PackedVector2Array:
	if end_x < 0.0:
		end_x = screen_width
	var points := PackedVector2Array()
	var x_positions: Array[float] = [start_x]
	# Keep the sampling lattice fixed to the viewport instead of moving it with
	# the segment start. Moving sample points made sloped joins subtly shimmer as
	# they crossed the screen edge. Add every slope endpoint explicitly so the
	# polyline always contains the exact corners, regardless of the sample grid.
	var x := ceilf(start_x / 16.0) * 16.0
	while x < end_x:
		if x > start_x:
			x_positions.append(x)
		x += 16.0
	for terrain in slopes:
		if bool(terrain.call("is_ceiling_slope")) != ceiling:
			continue
		for boundary_x in [float(terrain.call("get_start_x")), float(terrain.call("get_end_x"))]:
			if boundary_x > start_x and boundary_x < end_x:
				x_positions.append(boundary_x)
	x_positions.append(end_x)
	for terrain in slopes:
		if bool(terrain.call("is_ceiling_slope")) != ceiling:
			continue
		if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")):
			var step_x := float(terrain.call("get_start_x"))
			if step_x > start_x and step_x < end_x:
				x_positions.append(step_x)
	x_positions.sort()
	var last_x := -1000000.0
	for point_x in x_positions:
		if is_equal_approx(point_x, last_x):
			continue
		last_x = point_x
		var is_step_point := false
		for terrain in slopes:
			if bool(terrain.call("is_ceiling_slope")) == ceiling and terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")) and is_equal_approx(float(terrain.call("get_start_x")), point_x):
				is_step_point = true
				break
		if is_step_point:
			points.append(Vector2(point_x, _surface_y_at(point_x - 0.01, ceiling)))
			points.append(Vector2(point_x, _surface_y_at(point_x + 0.01, ceiling)))
		else:
			points.append(Vector2(point_x, _surface_y_at(point_x, ceiling)))
	return points
