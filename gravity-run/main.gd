extends Node2D

const SCREEN_WIDTH := 960.0
const SCREEN_HEIGHT := 540.0
const RUN_SPEED_START := 330.0
const SPAWN_DISTANCE := 390.0
const COIN_DISTANCE := 720.0
const SLOPE_DISTANCE := 1750.0
const LEDGE_DISTANCE_MIN := 1250.0
const LEDGE_DISTANCE_MAX := 1950.0
const SLOPE_WIDTH := 320.0
const SPIKE_WIDTH := 28.0
const SPIKE_HEIGHT := 32.0
const SPIKE_GROUP_SPACING := 32.0
const SPIKE_SCENE := preload("res://hazards/spikes.tscn")
const BLOCK_SCENE := preload("res://hazards/block.tscn")
const BARREL_SCENE := preload("res://hazards/barrel.tscn")
const COIN_SCENE := preload("res://collectibles/coin.tscn")
const SLOPE_SCENE := preload("res://terrain/slope.tscn")
const LEDGE_SCENE := preload("res://terrain/ledge.tscn")

@onready var player: Node2D = $Player
@onready var run_state: Node = $RunState
@onready var hud: Node2D = $HUD

var obstacles: Array[Node2D] = []
var coins: Array[Node2D] = []
var slopes: Array[Node2D] = []
var obstacle_distance := 0.0
var coin_distance := 0.0
var slope_distance := 0.0
var ledge_distance := 0.0
var next_ledge_distance := 1500.0
var floor_level_y := SCREEN_HEIGHT - 56.0
var ceiling_level_y := 56.0
var planned_floor_level_y := SCREEN_HEIGHT - 56.0
var planned_ceiling_level_y := 56.0
var game_over := false
var run_blocked := false

func _ready() -> void:
	run_state.connect("stats_changed", Callable(hud, "update_stats"))
	run_state.connect("run_started", Callable(hud, "hide_game_over"))
	run_state.connect("run_finished", Callable(hud, "show_game_over"))
	player.connect("status_changed", Callable(hud, "update_player_status"))
	_start_run()

func _start_run() -> void:
	player.call("reset_to_floor", SCREEN_HEIGHT - 56.0)
	run_state.call("start_run")
	obstacle_distance = 0.0
	coin_distance = 0.0
	slope_distance = 0.0
	ledge_distance = 0.0
	next_ledge_distance = 1500.0
	floor_level_y = SCREEN_HEIGHT - 56.0
	ceiling_level_y = 56.0
	planned_floor_level_y = floor_level_y
	planned_ceiling_level_y = ceiling_level_y
	_clear_nodes(obstacles)
	_clear_nodes(coins)
	_clear_nodes(slopes)
	game_over = false
	run_blocked = false
	hud.call("set_run_blocked", false)
	queue_redraw()

func _clear_nodes(nodes: Array[Node2D]) -> void:
	for node in nodes:
		node.queue_free()
	nodes.clear()

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_start_run()

func _physics_process(delta: float) -> void:
	if game_over:
		return

	var speed := _run_speed()
	var movement := speed * delta if not run_blocked else 0.0
	if not run_blocked:
		run_state.call("add_distance", movement)
		obstacle_distance += movement
		coin_distance += movement
		slope_distance += movement
		ledge_distance += movement
		if obstacle_distance >= SPAWN_DISTANCE:
			obstacle_distance -= SPAWN_DISTANCE
			_spawn_obstacle()
		if coin_distance >= COIN_DISTANCE:
			coin_distance -= COIN_DISTANCE
			_spawn_coin_row()
		if slope_distance >= SLOPE_DISTANCE:
			slope_distance -= SLOPE_DISTANCE
			_spawn_slope()
		if ledge_distance >= next_ledge_distance:
			ledge_distance = 0.0
			_spawn_ledge()
			next_ledge_distance = randf_range(LEDGE_DISTANCE_MIN, LEDGE_DISTANCE_MAX)

	_update_moving_slopes(movement)
	_update_moving_nodes(obstacles, movement, delta)
	_update_moving_nodes(coins, movement, delta)
	_resolve_obstacle_interactions()

	player.call("advance", delta, _floor_surface_y(180.0), _ceiling_surface_y(180.0))

	var blocked_by_edge := false
	for obstacle in obstacles:
		if bool(obstacle.call("is_destroying_now")):
			continue
		var player_rect: Rect2 = player.call("get_player_rect")
		if obstacle.has_method("intersects_spikes") and bool(obstacle.call("intersects_spikes", player_rect)):
			if not bool(player.call("is_spike_immune")):
				game_over = true
				player.call("set_input_enabled", false)
				run_state.call("finish_run")
				break
		if _player_hits_obstacle(obstacle):
			if obstacle.is_in_group("blocking_edges"):
				blocked_by_edge = true
				continue
			if bool(player.call("is_spike_immune")) and obstacle.is_in_group("spikes"):
				continue
			game_over = true
			player.call("set_input_enabled", false)
			run_state.call("finish_run")
			break
	if not game_over:
		var player_rect: Rect2 = player.call("get_player_rect")
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			if bool(terrain.call("intersects_spikes", player_rect)) and not bool(player.call("is_spike_immune")):
				game_over = true
				player.call("set_input_enabled", false)
				run_state.call("finish_run")
				break
			if bool(terrain.call("intersects_wall", player_rect)) and not _player_is_escaping_terrain_step(terrain):
				blocked_by_edge = true
	run_blocked = blocked_by_edge and not game_over
	hud.call("set_run_blocked", run_blocked)
	for coin in coins:
		if _player_hits_obstacle(coin):
			coin.call("collect")
	coins = coins.filter(func(coin: Node2D) -> bool: return is_instance_valid(coin) and not bool(coin.call("is_collected")) and coin.position.x > -100.0)
	queue_redraw()

func _player_is_escaping_terrain_step(terrain: Node2D) -> bool:
	var gravity_direction := int(player.call("get_gravity_direction"))
	var attached_to_ceiling := bool(terrain.call("is_ceiling_slope"))
	return (attached_to_ceiling and gravity_direction > 0) or (not attached_to_ceiling and gravity_direction < 0)

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
				Callable(self, "_surface_angle_at")
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

func _spawn_obstacle() -> void:
	var kind := randi_range(0, 2)
	# Barrels stay on the floor; only the player's gravity can be flipped.
	var from_ceiling := kind != 2 and randi_range(0, 1) == 0
	var width: float
	var height: float
	var scene: PackedScene
	match kind:
		0:
			scene = SPIKE_SCENE
			width = SPIKE_WIDTH
			height = SPIKE_HEIGHT
		1:
			scene = BLOCK_SCENE
			width = 44.0 if randi_range(0, 1) == 0 else 64.0
			var block_size := randi_range(0, 4)
			height = 82.0 if block_size == 0 else (132.0 if block_size < 4 else 168.0)
		2:
			scene = BARREL_SCENE
			width = 54.0
			height = 54.0 if randi_range(0, 1) == 0 else 76.0
	if kind == 2:
		var spawn_x := SCREEN_WIDTH + 40.0
		if randi_range(0, 2) == 0:
			# A small test encounter: the faster barrel catches this crate before it reaches the player.
			_spawn_obstacle_scene(BLOCK_SCENE, 60.0, 100.0, false, spawn_x)
			_spawn_obstacle_scene(scene, width, height, false, spawn_x + 180.0)
		else:
			var barrel_count := randi_range(2, 3) if randi_range(0, 1) == 0 else 1
			for i in range(barrel_count):
				_spawn_obstacle_scene(scene, width, height, false, spawn_x + float(i) * 70.0)
	elif kind == 0:
		_spawn_spike_group(randi_range(4, 6), from_ceiling, SCREEN_WIDTH + 40.0)
	else:
		_spawn_obstacle_scene(scene, width, height, from_ceiling, SCREEN_WIDTH + 40.0)

func _spawn_spike_group(count: int, from_ceiling: bool, start_x: float) -> void:
	var group_end_x := start_x + float(count - 1) * SPIKE_GROUP_SPACING
	for terrain in slopes:
		if not terrain.has_method("is_terrain_step") or bool(terrain.call("is_terrain_step")):
			continue
		var slope_start := float(terrain.call("get_start_x"))
		var slope_end := float(terrain.call("get_end_x"))
		var group_start_edge := start_x - SPIKE_WIDTH * 0.5
		var group_end_edge := group_end_x + SPIKE_WIDTH * 0.5
		if group_start_edge < slope_end and group_end_edge > slope_start:
			start_x = slope_end + SPIKE_WIDTH * 0.5 + 2.0
			group_end_x = start_x + float(count - 1) * SPIKE_GROUP_SPACING
	for i in range(count):
		var spike_x := start_x + float(i) * SPIKE_GROUP_SPACING
		_spawn_obstacle_scene(SPIKE_SCENE, SPIKE_WIDTH, SPIKE_HEIGHT, from_ceiling, spike_x)

func _spawn_ledge() -> void:
	var from_ceiling := randi_range(0, 1) == 0
	var has_spikes := randi_range(0, 1) == 0
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var change_sizes: Array[float] = [56.0, 84.0, 116.0]
	var change: float = change_sizes[randi_range(0, change_sizes.size() - 1)]
	var low_limit := 56.0 if from_ceiling else 400.0
	var high_limit := 140.0 if from_ceiling else SCREEN_HEIGHT - 56.0
	var end_y: float = start_y + change if from_ceiling else start_y - change
	end_y = clampf(end_y, low_limit, high_limit)
	if absf(end_y - start_y) < 40.0:
		end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
	var x := SCREEN_WIDTH + 180.0
	var attempts := 0
	while _terrain_step_conflicts(x, from_ceiling) and attempts < 12:
		x += SLOPE_WIDTH + 100.0
		attempts += 1
	var step := LEDGE_SCENE.instantiate() as Node2D
	step.position = Vector2(x, 0.0)
	step.call("configure_step", start_y, end_y, from_ceiling, has_spikes)
	add_child(step)
	slopes.append(step)
	if randi_range(0, 1) == 0:
		_spawn_spike_group(randi_range(4, 6), from_ceiling, x + 32.0)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y

func _terrain_step_conflicts(x: float, from_ceiling: bool) -> bool:
	for terrain in slopes:
		if bool(terrain.call("is_ceiling_slope")) != from_ceiling:
			continue
		var start_x := float(terrain.call("get_start_x"))
		var end_x := float(terrain.call("get_end_x"))
		if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")):
			if absf(x - start_x) < 420.0:
				return true
		elif x > start_x - 80.0 and x < end_x + 80.0:
			return true
	return false

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
			if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")) and bool(barrel.call("intersects_rect", terrain.call("get_wall_rect"))):
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

func _spawn_obstacle_scene(scene: PackedScene, width: float, height: float, from_ceiling: bool, x: float) -> void:
	var obstacle := scene.instantiate() as Node2D
	obstacle.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	obstacle.position = Vector2(x, _ceiling_surface_y(x) if from_ceiling else _floor_surface_y(x))
	obstacle.call("configure", Vector2(width, height), from_ceiling)
	obstacle.rotation = _surface_angle_at(x, from_ceiling)
	add_child(obstacle)
	var attempts := 0
	while _obstacle_spawn_conflicts(obstacle) and attempts < 32:
		x += maxf(width, 32.0)
		obstacle.position = Vector2(x, _ceiling_surface_y(x) if from_ceiling else _floor_surface_y(x))
		obstacle.rotation = _surface_angle_at(x, from_ceiling)
		attempts += 1
	obstacles.append(obstacle)

func _on_obstacle_destroyed(obstacle: Node2D) -> void:
	obstacles.erase(obstacle)

func _obstacle_spawn_conflicts(obstacle: Node2D) -> bool:
	var hazard_rect: Rect2 = obstacle.call("get_hitbox_rect")
	if obstacle.is_in_group("blocking_edges"):
		for slope in slopes:
			var slope_start := float(slope.call("get_start_x"))
			var slope_end := float(slope.call("get_end_x"))
			if hazard_rect.position.x < slope_end and hazard_rect.end.x > slope_start:
				return true
	for terrain in slopes:
		if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
			continue
		var edge_x := float(terrain.call("get_start_x"))
		var edge_clearance := hazard_rect.size.x * 0.5 + 72.0
		if absf(obstacle.global_position.x - edge_x) < edge_clearance:
			return true
	for coin in coins:
		if is_instance_valid(coin) and hazard_rect.grow(4.0).intersects(coin.call("get_hitbox_rect")):
			return true
	for other in obstacles:
		if is_instance_valid(other) and hazard_rect.intersects(other.call("get_hitbox_rect")):
			return true
	return false

func _spawn_coin_row() -> void:
	var coin_count := randi_range(1, 3)
	for i in range(coin_count):
		var coin := COIN_SCENE.instantiate() as Node2D
		coin.connect("collected", Callable(run_state, "add_coins"))
		var coin_x := SCREEN_WIDTH + 70.0 + float(i) * 48.0
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

func _spawn_slope() -> void:
	var slope := SLOPE_SCENE.instantiate() as Node2D
	var from_ceiling := randi_range(0, 1) == 0
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var low_limit := 56.0 if from_ceiling else 400.0
	var high_limit := 140.0 if from_ceiling else SCREEN_HEIGHT - 56.0
	var end_y := clampf(start_y + randf_range(-90.0, 90.0), low_limit, high_limit)
	if absf(end_y - start_y) < 45.0:
		end_y = clampf(start_y + (45.0 if start_y < (low_limit + high_limit) * 0.5 else -45.0), low_limit, high_limit)
	slope.position = Vector2(SCREEN_WIDTH + 180.0, start_y)
	slope.call("configure", start_y, end_y, from_ceiling)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y
	add_child(slope)
	slopes.append(slope)

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

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)), Color("101827"))
	var distance_score := float(run_state.get("distance_m"))
	for i in range(18):
		var x := float((i * 83 + int(distance_score * 0.12)) % int(SCREEN_WIDTH))
		draw_circle(Vector2(x, 58.0 + float((i * 47) % 390)), 1.5, Color("26364b"))

func _draw_track() -> void:
	var ceiling_points := _get_surface_points(true)
	var ceiling_fill := PackedVector2Array([Vector2(0.0, 0.0)])
	ceiling_fill.append_array(ceiling_points)
	ceiling_fill.append(Vector2(SCREEN_WIDTH, 0.0))
	draw_colored_polygon(ceiling_fill, Color("202d40"))
	draw_polyline(ceiling_points, Color("42d6c5"), 3.0)

	var floor_points := _get_surface_points(false)
	var floor_fill := floor_points.duplicate()
	floor_fill.append(Vector2(SCREEN_WIDTH, SCREEN_HEIGHT))
	floor_fill.append(Vector2(0.0, SCREEN_HEIGHT))
	draw_colored_polygon(floor_fill, Color("202d40"))
	draw_polyline(floor_points, Color("42d6c5"), 3.0)

func _get_surface_points(ceiling: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var x_positions: Array[float] = []
	var x := 0.0
	while x < SCREEN_WIDTH:
		x_positions.append(x)
		x += 16.0
	x_positions.append(SCREEN_WIDTH)
	for terrain in slopes:
		if bool(terrain.call("is_ceiling_slope")) != ceiling:
			continue
		if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")):
			var step_x := float(terrain.call("get_start_x"))
			if step_x > 0.0 and step_x < SCREEN_WIDTH:
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
