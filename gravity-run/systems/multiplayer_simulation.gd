extends RefCounted
class_name MultiplayerSimulation

const RaceRulesScript := preload("res://systems/multiplayer_race_rules.gd")
const TICK_RATE := 60
const FIXED_DELTA := 1.0 / TICK_RATE
const PLAYER_WIDTH := 34.0
const PLAYER_HEIGHT := 44.0
const RUN_SPEED := 500.0
const GRAVITY := 1900.0
const FLIP_SPEED := 680.0
const FLIP_COOLDOWN := 0.42
const MAX_CATCHUP_TICKS := 5

var manifest: Resource
var tick := 0
var started := false
var match_finished := false
var _accumulator := 0.0
var _players: Dictionary = {}
var _placements: Array[Dictionary] = []
var _last_flip_tick: Dictionary = {}

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
			"state": "running",
			"blocked": false,
			"finish_tick": -1,
		}
	return ""

func start() -> void:
	if manifest != null and not _players.is_empty():
		started = true

func set_player_speed_percent(user_id: String, speed_percent: int) -> bool:
	if started or not _players.has(user_id):
		return false
	var player: Dictionary = _players[user_id]
	player.run_speed_percent = clampi(speed_percent, 9500, 10500)
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
	player.cooldown = clampf(float(authoritative_state.get("cooldown", 0.0)), 0.0, FLIP_COOLDOWN)
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
	player.gravity_direction = desired_gravity
	player.grounded = false
	player.vertical_speed = float(desired_gravity) * FLIP_SPEED
	player.cooldown = FLIP_COOLDOWN
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
		_step_player_states(events)
		steps += 1
	return events

func get_snapshot() -> Dictionary:
	var snapshot_players: Array[Dictionary] = []
	for user_id in _players:
		snapshot_players.append((_players[user_id] as Dictionary).duplicate(true))
	snapshot_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.user_id) < str(b.user_id))
	return {"tick": tick, "course_identity": str(manifest.get("course_identity")) if manifest != null else "", "players": snapshot_players, "placements": _placements.duplicate(true), "finished": match_finished}

func get_player(user_id: String) -> Dictionary:
	return (_players[user_id] as Dictionary).duplicate(true) if _players.has(user_id) else {}

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
	player.cooldown = maxf(float(player.cooldown) - FIXED_DELTA, 0.0)
	var speed := RUN_SPEED * float(player.run_speed_percent) / 10000.0
	var next_x := minf(float(player.world_x) + speed * FIXED_DELTA, float(manifest.get("finish_x")))
	var blocked := _blocks_at_next_x(player, next_x)
	if not blocked:
		player.world_x = next_x
	var floor_info := _surface_at(float(player.world_x), false)
	var ceiling_info := _surface_at(float(player.world_x), true)
	var floor_contact := float(floor_info.y) - PLAYER_HEIGHT * 0.5
	var ceiling_contact := float(ceiling_info.y) + PLAYER_HEIGHT * 0.5
	var direction := int(player.gravity_direction)
	var contact_y := floor_contact if direction > 0 else ceiling_contact
	if bool(player.grounded) and float(direction) * (contact_y - float(player.y)) > 12.0:
		player.grounded = false
		player.vertical_speed = 0.0
	player.vertical_speed = float(player.vertical_speed) + float(direction) * GRAVITY * FIXED_DELTA
	player.y = float(player.y) + float(player.vertical_speed) * FIXED_DELTA
	if direction > 0:
		if not bool(floor_info.supported):
			player.grounded = false
		elif bool(player.grounded):
			player.y = floor_contact
			player.vertical_speed = 0.0
		elif float(player.vertical_speed) >= 0.0 and float(player.y) >= floor_contact and float(player.y) - floor_contact <= 38.0:
			player.y = floor_contact
			player.vertical_speed = 0.0
			player.grounded = true
	else:
		if not bool(ceiling_info.supported):
			player.grounded = false
		elif bool(player.grounded):
			player.y = ceiling_contact
			player.vertical_speed = 0.0
		elif float(player.vertical_speed) <= 0.0 and float(player.y) <= ceiling_contact and ceiling_contact - float(player.y) <= 38.0:
			player.y = ceiling_contact
			player.vertical_speed = 0.0
			player.grounded = true
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
	return false

func _hits_lethal_event(player: Dictionary) -> bool:
	var rect := Rect2(Vector2(float(player.world_x) - PLAYER_WIDTH * 0.5, float(player.y) - PLAYER_HEIGHT * 0.5), Vector2(PLAYER_WIDTH, PLAYER_HEIGHT))
	for event in manifest.get("events"):
		var kind := str(event.get("kind", ""))
		if kind == "spikes":
			var x := float(event.get("start_x", event.get("x", 0.0)))
			var width := float(event.get("width", 32.0))
			var y := float(event.get("y", 0.0))
			var spike_rect := Rect2(Vector2(x, y - 28.0 if not bool(event.get("from_ceiling", false)) else y), Vector2(width, 28.0))
			if rect.intersects(spike_rect):
				return true
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			if rect.intersects(Rect2(Vector2(float(event.get("x", 0.0)) - width * 0.5, block_y), Vector2(width, height))):
				return true
	return false
