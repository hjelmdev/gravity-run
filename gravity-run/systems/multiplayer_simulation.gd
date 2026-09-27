extends RefCounted
class_name MultiplayerSimulation

const RaceRulesScript := preload("res://systems/multiplayer_race_rules.gd")
const RunnerMotionScript := preload("res://systems/runner_motion.gd")
const TICK_RATE := 60
const FIXED_DELTA := 1.0 / TICK_RATE
const PLAYER_WIDTH := RunnerMotionScript.SIZE.x
const PLAYER_HEIGHT := RunnerMotionScript.SIZE.y
const RUN_SPEED := RunnerMotionScript.BASE_RUN_SPEED
const MAX_CATCHUP_TICKS := 5

var manifest: Resource
var tick := 0
var started := false
var match_finished := false
var _accumulator := 0.0
var _players: Dictionary = {}
var _placements: Array[Dictionary] = []
var _last_flip_tick: Dictionary = {}
var _barrels: Array[Dictionary] = []
var _destroyed_event_ids: Dictionary = {}
var _world_elapsed := 0.0

func configure(course_manifest: Resource, players: Array) -> String:
	var player_error := RaceRulesScript.validate_players(players)
	if not player_error.is_empty():
		return player_error
	if course_manifest == null or not course_manifest.has_method("validate"):
		return "A validated course manifest is required."
	var manifest_error := str(course_manifest.call("validate"))
	if not manifest_error.is_empty():
		return manifest_error
	manifest = course_manifest
	tick = 0
	_accumulator = 0.0
	started = false
	match_finished = false
	_players.clear()
	_placements.clear()
	_last_flip_tick.clear()
	_barrels.clear()
	_destroyed_event_ids.clear()
	_world_elapsed = 0.0
	for player in players:
		var user_id := str(player.user_id)
		var floor_y := float(manifest.get("initial_floor_y"))
		_players[user_id] = {
			"user_id": user_id,
			"display_name": str(player.get("display_name", "Runner")),
			"world_x": float(manifest.get("start_x")),
			"y": floor_y - PLAYER_HEIGHT * 0.5,
			"vertical_speed": 0.0,
			"gravity_direction": 1,
			"grounded": true,
			"cooldown": 0.0,
			"run_speed_percent": clampi(int(player.get("run_speed_percent", 10000)), 9500, 10500),
			"flip_cooldown_percent": clampi(int(player.get("flip_cooldown_percent", 10000)), 5000, 20000),
			"state": "running",
			"blocked": false,
			"finish_tick": -1,
		}
	for event in manifest.get("events"):
		if str(event.get("kind", "")) != "barrels":
			continue
		var count := clampi(int(event.get("count", 1)), 1, 6)
		var spacing := float(event.get("spacing", 70.0))
		var chain_width := float(count - 1) * spacing
		var multiplier := maxf(float(event.get("motion_speed_multiplier", 1.0)), 1.0)
		var spawn_lead := float(event.get("spawn_lead_distance", 820.0))
		for index in range(count):
			_barrels.append({
				"entity_id": "%s_%d" % [str(event.get("event_id", "barrel")), index],
				"event_id": str(event.get("event_id", "")),
				"x": float(event.get("x", 0.0)) + spawn_lead * (multiplier - 1.0) - chain_width * 0.5 + float(index) * spacing,
				"y": float(event.get("y", manifest.get("initial_floor_y"))),
				"width": 54.0,
				"height": float(event.get("height", 54.0)),
				"speed": RunnerMotionScript.BASE_RUN_SPEED * (multiplier - 1.0),
				"spawn_time": maxf(0.0, float(event.get("x", 0.0)) - spawn_lead - float(manifest.get("start_x"))) / RunnerMotionScript.BASE_RUN_SPEED,
				"spawned": false,
				"fall_velocity": 0.0,
				"falling": false,
				"roll_angle": 0.0,
				"rotation": 0.0,
				"destroyed": false,
			})
	return ""

func start() -> void:
	if manifest != null and not _players.is_empty():
		started = true

func set_player_profile(user_id: String, speed_percent: int, flip_cooldown_percent: int = 10000) -> bool:
	if started or not _players.has(user_id):
		return false
	var player: Dictionary = _players[user_id]
	player.run_speed_percent = clampi(speed_percent, 9500, 10500)
	player.flip_cooldown_percent = clampi(flip_cooldown_percent, 5000, 20000)
	_players[user_id] = player
	return true

func mark_disconnected(user_id: String) -> bool:
	if not _players.has(user_id):
		return false
	var player: Dictionary = _players[user_id]
	if str(player.get("state", "")) != "running":
		return false
	player.state = "disconnected"
	player.blocked = false
	_players[user_id] = player
	return true

func apply_authoritative_player_state(user_id: String, authoritative_state: Dictionary) -> bool:
	if not _players.has(user_id):
		return false
	var x := float(authoritative_state.get("world_x", NAN))
	var y := float(authoritative_state.get("y", NAN))
	var vertical_speed := float(authoritative_state.get("vertical_speed", NAN))
	var gravity_direction := int(authoritative_state.get("gravity_direction", 0))
	var state := str(authoritative_state.get("state", ""))
	if not is_finite(x) or not is_finite(y) or not is_finite(vertical_speed) or gravity_direction not in [-1, 1]:
		return false
	if state not in ["running", "dead", "finished", "disconnected"]:
		return false
	var player: Dictionary = _players[user_id]
	player.world_x = clampf(x, float(manifest.get("start_x")), float(manifest.get("finish_x")))
	player.y = y
	player.vertical_speed = vertical_speed
	player.gravity_direction = gravity_direction
	player.grounded = bool(authoritative_state.get("grounded", false))
	player.cooldown = clampf(float(authoritative_state.get("cooldown", 0.0)), 0.0, RunnerMotionScript.FLIP_COOLDOWN_SECONDS * 2.0)
	player.state = state
	player.blocked = bool(authoritative_state.get("blocked", false))
	player.finish_tick = int(authoritative_state.get("finish_tick", -1))
	_players[user_id] = player
	return true

func submit_flip(user_id: String, desired_gravity: int) -> bool:
	if not started or match_finished or not _players.has(user_id) or desired_gravity not in [-1, 1]:
		return false
	var player: Dictionary = _players[user_id]
	if player.state != "running" or not player.grounded or float(player.cooldown) > 0.0:
		return false
	if desired_gravity == int(player.gravity_direction):
		return false
	if not RunnerMotionScript.try_flip(player, desired_gravity, float(player.flip_cooldown_percent) / 10000.0):
		return false
	_last_flip_tick[user_id] = tick
	return true

func advance_frame(delta: float) -> Array[Dictionary]:
	if not started or match_finished:
		return []
	_accumulator = minf(_accumulator + maxf(delta, 0.0), FIXED_DELTA * MAX_CATCHUP_TICKS)
	var events: Array[Dictionary] = []
	var steps := 0
	while _accumulator >= FIXED_DELTA and steps < MAX_CATCHUP_TICKS:
		_accumulator -= FIXED_DELTA
		tick += 1
		_step_world_hazards()
		_step_player_states(events)
		steps += 1
	return events

func get_snapshot() -> Dictionary:
	var snapshot_players: Array[Dictionary] = []
	for user_id in _players:
		snapshot_players.append((_players[user_id] as Dictionary).duplicate(true))
	snapshot_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.user_id) < str(b.user_id))
	return {"tick": tick, "course_identity": str(manifest.get("course_identity")) if manifest != null else "", "players": snapshot_players, "placements": _placements.duplicate(true), "finished": match_finished, "world_hazards": {"barrels": _barrels.duplicate(true), "destroyed_event_ids": _destroyed_event_ids.keys()}}

func apply_authoritative_world_hazards(world_hazards: Variant) -> bool:
	if not world_hazards is Dictionary or not world_hazards.get("barrels", null) is Array or not world_hazards.get("destroyed_event_ids", null) is Array:
		return false
	var authoritative_barrels: Array = world_hazards.barrels
	if authoritative_barrels.size() != _barrels.size():
		return false
	var expected_ids := {}
	for barrel in _barrels:
		expected_ids[str(barrel.get("entity_id", ""))] = true
	for barrel in authoritative_barrels:
		if not barrel is Dictionary or not expected_ids.has(str(barrel.get("entity_id", ""))):
			return false
	_barrels = authoritative_barrels.duplicate(true)
	_destroyed_event_ids.clear()
	for event_id in world_hazards.destroyed_event_ids:
		_destroyed_event_ids[str(event_id)] = true
	return true

func get_player(user_id: String) -> Dictionary:
	return (_players[user_id] as Dictionary).duplicate(true) if _players.has(user_id) else {}

func _step_world_hazards() -> void:
	_world_elapsed += FIXED_DELTA
	for barrel in _barrels:
		if bool(barrel.get("destroyed", false)):
			continue
		if not bool(barrel.get("spawned", false)):
			if _world_elapsed < float(barrel.get("spawn_time", INF)):
				continue
			barrel.spawned = true
		var delta_x := float(barrel.get("speed", 0.0)) * FIXED_DELTA
		barrel.x = float(barrel.x) - delta_x
		var floor_info := _surface_at(float(barrel.x), false)
		var floor_y := float(floor_info.y)
		if bool(barrel.falling):
			barrel.fall_velocity = float(barrel.fall_velocity) + 1800.0 * FIXED_DELTA
			barrel.y = float(barrel.y) + float(barrel.fall_velocity) * FIXED_DELTA
			if bool(floor_info.supported) and float(barrel.y) >= floor_y:
				barrel.y = floor_y
				barrel.falling = false
				barrel.fall_velocity = 0.0
		elif not bool(floor_info.supported) or floor_y - float(barrel.y) > 14.0:
			barrel.falling = true
			barrel.fall_velocity = 0.0
		elif floor_y - float(barrel.y) >= -14.0:
			barrel.y = floor_y
		barrel.roll_angle = float(barrel.roll_angle) - delta_x / maxf(minf(float(barrel.width), float(barrel.height)) * 0.5, 1.0)
		barrel.rotation = _surface_angle_at(float(barrel.x), false)
		_resolve_barrel_interactions(barrel)

func _resolve_barrel_interactions(barrel: Dictionary) -> void:
	if bool(barrel.get("destroyed", false)):
		return
	var radius := minf(float(barrel.get("width", 54.0)), float(barrel.get("height", 54.0))) * 0.5
	var center := Vector2(float(barrel.get("x", 0.0)), float(barrel.get("y", 0.0)) - radius)
	var barrel_rect := Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
	for event in manifest.get("events"):
		var event_id := str(event.get("event_id", ""))
		if _destroyed_event_ids.has(event_id):
			continue
		var kind := str(event.get("kind", ""))
		if kind == "spikes":
			var spike_start := float(event.get("start_x", event.get("x", 0.0)))
			var spike_y := float(event.get("y", 0.0))
			var spike_width := float(event.get("width", 28.0))
			var spike_rect_y := spike_y - 32.0 if not bool(event.get("from_ceiling", false)) else spike_y
			if barrel_rect.intersects(Rect2(Vector2(spike_start, spike_rect_y), Vector2(spike_width, 32.0))):
				barrel.destroyed = true
				return
		elif kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			if barrel_rect.intersects(Rect2(Vector2(float(event.get("x", 0.0)) - width * 0.5, block_y), Vector2(width, height))):
				_destroyed_event_ids[event_id] = true
				barrel.destroyed = true
				return
	for event in manifest.get("events"):
		if str(event.get("kind", "")) != "step":
			continue
		var step_x := float(event.get("x", 0.0))
		var step_top := minf(float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
		var step_rect := Rect2(Vector2(step_x - 2.0, step_top), Vector2(4.0, absf(float(event.get("end_y", 0.0)) - float(event.get("start_y", 0.0)))))
		var floor_drop := not bool(event.get("from_ceiling", false)) and float(event.get("start_y", 0.0)) > float(event.get("end_y", 0.0))
		if not floor_drop and barrel_rect.intersects(step_rect):
			barrel.destroyed = true
			return

func _circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(closest) <= radius * radius

func _surface_angle_at(x: float, ceiling: bool) -> float:
	for event in manifest.get("events"):
		if str(event.get("kind", "")) != "slope" or bool(event.get("from_ceiling", false)) != ceiling:
			continue
		var start_x := float(event.get("start_x", 0.0))
		var end_x := float(event.get("end_x", start_x))
		if x >= start_x and x <= end_x and end_x > start_x:
			return atan2(float(event.get("end_y", 0.0)) - float(event.get("start_y", 0.0)), end_x - start_x)
	return 0.0

func _step_player_states(events: Array[Dictionary]) -> void:
	for user_id in _players.keys():
		var player: Dictionary = _players[user_id]
		if str(player.state) != "running":
			continue
		_step_player(str(user_id), player, events)
		_players[user_id] = player
	if _players.size() > 0:
		var active := false
		for player in _players.values():
			if str(player.state) == "running":
				active = true
				break
		match_finished = not active
		if match_finished:
			events.append({"kind": "match_finished", "tick": tick, "result": RaceRulesScript.make_result(_placements)})

func _step_player(user_id: String, player: Dictionary, events: Array[Dictionary]) -> void:
	var movement := RunnerMotionScript.distance_for_delta(FIXED_DELTA, float(player.run_speed_percent) / 10000.0, false)
	var next_x := minf(float(player.world_x) + movement, float(manifest.get("finish_x")))
	var blocked := _blocks_at_next_x(player, next_x)
	if not blocked:
		player.world_x = next_x
	var floor_info := _surface_at(float(player.world_x), false)
	var ceiling_info := _surface_at(float(player.world_x), true)
	RunnerMotionScript.advance_vertical(player, FIXED_DELTA, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
	player.blocked = blocked
	if _hits_lethal_event(player):
		player.state = "dead"
		events.append({"kind": "player_died", "user_id": user_id, "tick": tick})
	elif float(player.y) < -64.0 or float(player.y) > float(manifest.get("world_height")) + 64.0:
		player.state = "dead"
		events.append({"kind": "player_died", "user_id": user_id, "tick": tick})
	elif float(player.world_x) >= float(manifest.get("finish_x")):
		player.state = "finished"
		player.finish_tick = tick
		_placements.append({"user_id": user_id, "display_name": str(player.display_name), "finish_tick": tick, "status": "finished"})
		events.append({"kind": "player_finished", "user_id": user_id, "tick": tick})

func _surface_at(x: float, ceiling: bool) -> Dictionary:
	var y := float(manifest.get("initial_ceiling_y")) if ceiling else float(manifest.get("initial_floor_y"))
	var supported := true
	for event in manifest.get("events"):
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				if x >= float(event.get("x", 0.0)):
					y = float(event.get("end_y", y))
			"slope":
				var start_x := float(event.get("start_x", 0.0))
				var end_x := float(event.get("end_x", start_x))
				if x >= start_x and x <= end_x and end_x > start_x:
					var amount := (x - start_x) / (end_x - start_x)
					y = lerpf(float(event.get("start_y", y)), float(event.get("end_y", y)), amount)
				elif x > end_x:
					y = float(event.get("end_y", y))
			"gap":
				var start_x := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
				if x >= start_x and x <= start_x + float(event.get("width", 0.0)):
					supported = false
	return {"y": y, "supported": supported}

func _blocks_at_next_x(player: Dictionary, next_x: float) -> bool:
	var direction := int(player.gravity_direction)
	var player_rect := Rect2(Vector2(next_x - PLAYER_WIDTH * 0.5, float(player.y) - PLAYER_HEIGHT * 0.5), Vector2(PLAYER_WIDTH, PLAYER_HEIGHT))
	for event in manifest.get("events"):
		var kind := str(event.get("kind", ""))
		if _destroyed_event_ids.has(str(event.get("event_id", ""))):
			continue
		if kind == "step":
			var from_ceiling := bool(event.get("from_ceiling", false))
			var surface_delta := float(event.get("end_y", 0.0)) - float(event.get("start_y", 0.0))
			var moves_away := (direction > 0 and not from_ceiling and surface_delta > 0.0) or (direction < 0 and from_ceiling and surface_delta < 0.0)
			var wall_x := float(event.get("x", 0.0))
			var top := minf(float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
			var height := absf(float(event.get("end_y", 0.0)) - float(event.get("start_y", 0.0)))
			if not moves_away and player_rect.intersects(Rect2(Vector2(wall_x - 5.0, top), Vector2(10.0, height))):
				return true
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var rect_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			var block := Rect2(Vector2(float(event.get("x", 0.0)) - width * 0.5, rect_y), Vector2(width, height))
			if player_rect.intersects(block):
				return true
	for barrel in _barrels:
		if not bool(barrel.get("spawned", false)) or bool(barrel.get("destroyed", false)):
			continue
		var radius := minf(float(barrel.get("width", 54.0)), float(barrel.get("height", 54.0))) * 0.5
		var center := Vector2(float(barrel.get("x", 0.0)), float(barrel.get("y", 0.0)) - radius)
		if _circle_intersects_rect(center, radius, player_rect):
			return true
	return false

func _hits_lethal_event(player: Dictionary) -> bool:
	var rect := Rect2(Vector2(float(player.world_x) - PLAYER_WIDTH * 0.5, float(player.y) - PLAYER_HEIGHT * 0.5), Vector2(PLAYER_WIDTH, PLAYER_HEIGHT))
	for event in manifest.get("events"):
		var kind := str(event.get("kind", ""))
		if _destroyed_event_ids.has(str(event.get("event_id", ""))):
			continue
		if kind == "spikes":
			var x := float(event.get("start_x", event.get("x", 0.0)))
			var width := float(event.get("width", 32.0))
			var y := float(event.get("y", 0.0))
			var spike_rect := Rect2(Vector2(x, y - 32.0 if not bool(event.get("from_ceiling", false)) else y), Vector2(width, 32.0))
			if rect.intersects(spike_rect):
				return true
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			if rect.intersects(Rect2(Vector2(float(event.get("x", 0.0)) - width * 0.5, block_y), Vector2(width, height))):
				return true
	for barrel in _barrels:
		if not bool(barrel.get("spawned", false)) or bool(barrel.get("destroyed", false)):
			continue
		var radius := minf(float(barrel.get("width", 54.0)), float(barrel.get("height", 54.0))) * 0.5
		var center := Vector2(float(barrel.get("x", 0.0)), float(barrel.get("y", 0.0)) - radius)
		if _circle_intersects_rect(center, radius, rect):
			return true
	return false
