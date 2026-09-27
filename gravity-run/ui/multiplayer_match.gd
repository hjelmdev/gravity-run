extends Node2D

const PlayerScene := preload("res://player/player.tscn")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")

const WORLD_HEIGHT := 540.0
const CAMERA_LEAD := 300.0

var _manifest: Resource
var _simulation: RefCounted
var _snapshot: Dictionary = {}
var _authoritative_snapshot: Dictionary = {}
var _snapshot_buffer: Array[Dictionary] = []
var _network_clock := 0.0
var _last_authoritative_tick := -1
var _visual_correction := Vector2.ZERO
var _input_sequence := 0
var _last_input_sequence: Dictionary = {}
var _player_views: Dictionary = {}
var _local_user_id := ""
var _owner_user_id := ""
var _go_start_at := 0.0
var _waiting_since := 0.0
var _received_match_ready: Dictionary = {}
var _snapshot_elapsed := 0.0
var _hud_elapsed := 0.0
var _status_label: Label
var _distance_label: Label
var _result_label: Label
var _flip_touch_active := false
var _touch_index := -1
var _touch_start := Vector2.ZERO

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	_local_user_id = MultiplayerService.identity_user_id
	_owner_user_id = str(MultiplayerService.room_state.get("owner_user_id", ""))
	_manifest = MultiplayerService.course_manifest
	MultiplayerService.peer_data_received.connect(_on_peer_data_received)
	MultiplayerService.peer_connection_state_changed.connect(_on_peer_connection_state_changed)
	_build_hud()
	if _manifest == null or not str(_manifest.call("validate")).is_empty():
		_show_failure(tr("The shared course is unavailable or failed validation."))
		return
	var members := MultiplayerService.get_members()
	var simulation_players: Array = []
	for member in members:
		if member is Dictionary and bool(member.get("is_connected", true)):
			var speed_percent: int = _local_speed_percent() if str(member.get("user_id", "")) == _local_user_id else 10000
			simulation_players.append({
				"user_id": str(member.get("user_id", "")),
				"display_name": str(member.get("display_name", "Runner")),
				"run_speed_percent": speed_percent,
			})
	_simulation = SimulationScript.new()
	var configuration_error := str(_simulation.configure(_manifest, simulation_players))
	if not configuration_error.is_empty():
		_show_failure(configuration_error)
		return
	_snapshot = _simulation.get_snapshot()
	_sync_player_views()
	if MultiplayerService.is_room_owner():
		_received_match_ready[_local_user_id] = true
	else:
		MultiplayerService.send_peer_message(_owner_user_id, "control", {
			"kind": "runner_profile",
			"run_speed_percent": _local_speed_percent(),
		})
		MultiplayerService.send_peer_message(_owner_user_id, "control", {"kind": "match_ready"})
		_status_label.text = tr("Waiting for the host to synchronize the start…")
	_waiting_since = _network_clock

func _process(delta: float) -> void:
	if _simulation == null:
		return
	_network_clock += delta
	if _go_start_at > 0.0 and _network_clock >= _go_start_at and not _simulation.started:
		_simulation.start()
		_status_label.text = tr("RUN!")
	if MultiplayerService.is_room_owner() and not _simulation.started and _go_start_at <= 0.0:
		_try_schedule_start()
		if _network_clock - _waiting_since > 15.0 and _go_start_at <= 0.0:
			_status_label.text = tr("A player did not finish loading the match. Waiting for reconnection…")
	if _simulation.started:
		var events: Array[Dictionary] = _simulation.advance_frame(delta)
		if MultiplayerService.is_room_owner():
			for event in events:
				if str(event.get("kind", "")) == "match_finished":
					_status_label.text = tr("Race finished")
			_snapshot = _simulation.get_snapshot()
			_snapshot_elapsed += delta
			if _snapshot_elapsed >= 1.0 / 15.0:
				_snapshot_elapsed = 0.0
				MultiplayerService.send_peer_message_to_all("snapshot", {"kind": "snapshot", "state": _snapshot})
		else:
			_visual_correction = _visual_correction.move_toward(Vector2.ZERO, delta * 420.0)
			_compose_client_snapshot()
	_hud_elapsed += delta
	if _hud_elapsed >= 0.1:
		_hud_elapsed = 0.0
		_update_hud()
	_sync_player_views()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _simulation == null or not _simulation.started or _player_state(_local_user_id).get("state", "") != "running":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_index = event.index
			_touch_start = event.position
			if PlayerProfile.flip_control == "tap":
				_request_flip(-int(_player_state(_local_user_id).get("gravity_direction", 1)))
		elif event.index == _touch_index:
			if PlayerProfile.flip_control != "tap":
				var swipe_delta: Vector2 = event.position - _touch_start
				if absf(swipe_delta.y) >= 48.0 and absf(swipe_delta.y) > absf(swipe_delta.x) * 1.2:
					_request_flip(-1 if swipe_delta.y < 0.0 else 1)
			_touch_index = -1
			_flip_touch_active = false
		return
	if event is InputEventKey and event.pressed and not event.echo and PlayerProfile.flip_control == "keyboard":
		if event.keycode in [KEY_UP, KEY_W]:
			_request_flip(-1)
		elif event.keycode in [KEY_DOWN, KEY_S]:
			_request_flip(1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and PlayerProfile.flip_control == "mouse":
		_request_flip(-int(_player_state(_local_user_id).get("gravity_direction", 1)))

func _request_flip(direction: int) -> void:
	if MultiplayerService.is_room_owner():
		_simulation.submit_flip(_local_user_id, direction)
	else:
		_simulation.submit_flip(_local_user_id, direction)
		_input_sequence += 1
		MultiplayerService.send_peer_message(_owner_user_id, "control", {
			"kind": "flip",
			"gravity_direction": direction,
			"input_sequence": _input_sequence,
			"client_tick": int(_simulation.tick),
		})

func _on_peer_data_received(peer_user_id: String, channel_name: String, payload: Dictionary) -> void:
	if MultiplayerService.is_room_owner() and channel_name == "control":
		if not _is_active_room_member(peer_user_id):
			return
		match str(payload.get("kind", "")):
			"runner_profile":
				_simulation.set_player_speed_percent(peer_user_id, int(payload.get("run_speed_percent", 10000)))
			"match_ready":
				_received_match_ready[peer_user_id] = true
			"flip":
				var sequence := int(payload.get("input_sequence", 0))
				if sequence > int(_last_input_sequence.get(peer_user_id, 0)):
					_last_input_sequence[peer_user_id] = sequence
					_simulation.submit_flip(peer_user_id, int(payload.get("gravity_direction", 0)))
	elif not MultiplayerService.is_room_owner():
		if channel_name == "control" and str(payload.get("kind", "")) == "race_go":
			_go_start_at = _network_clock + clampf(float(payload.get("start_delay_seconds", 2.0)), 0.5, 5.0)
			_status_label.text = tr("Get ready…")
		elif channel_name == "snapshot" and str(payload.get("kind", "")) == "snapshot":
			var new_snapshot: Variant = payload.get("state", {})
			if _accept_authoritative_snapshot(new_snapshot):
				if bool(_authoritative_snapshot.get("finished", false)):
					_status_label.text = tr("Race finished")

func _on_peer_connection_state_changed(peer_user_id: String, state: String, message: String) -> void:
	if state == "failed":
		_status_label.text = message
		if MultiplayerService.is_room_owner():
			if _simulation != null and _simulation.mark_disconnected(peer_user_id):
				_snapshot = _simulation.get_snapshot()
				MultiplayerService.send_peer_message_to_all("snapshot", {"kind": "snapshot", "state": _snapshot})
		elif peer_user_id == _owner_user_id:
			_result_label.text = tr("Connection to the race host was lost.")
			_result_label.visible = true

func _accept_authoritative_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or str(snapshot.get("course_identity", "")) != str(_manifest.get("course_identity")):
		return false
	var incoming_tick := int(snapshot.get("tick", -1))
	var states: Variant = snapshot.get("players", null)
	if incoming_tick <= _last_authoritative_tick or not states is Array:
		return false
	var member_ids := {}
	for member in MultiplayerService.get_members():
		if member is Dictionary:
			member_ids[str(member.get("user_id", ""))] = true
	if states.size() != member_ids.size():
		return false
	var seen := {}
	var local_state: Dictionary = {}
	for state in states:
		if not state is Dictionary:
			return false
		var user_id := str(state.get("user_id", ""))
		if not member_ids.has(user_id) or seen.has(user_id):
			return false
		seen[user_id] = true
		if user_id == _local_user_id:
			local_state = state
	if local_state.is_empty():
		return false
	var predicted: Dictionary = _simulation.get_player(_local_user_id)
	_visual_correction = Vector2(
		float(predicted.get("world_x", 0.0)) + _visual_correction.x - float(local_state.get("world_x", 0.0)),
		float(predicted.get("y", 0.0)) + _visual_correction.y - float(local_state.get("y", 0.0))
	).clamp(Vector2(-160.0, -160.0), Vector2(160.0, 160.0))
	if not _simulation.apply_authoritative_player_state(_local_user_id, local_state):
		return false
	_last_authoritative_tick = incoming_tick
	_authoritative_snapshot = snapshot.duplicate(true)
	_snapshot_buffer.append({"received_at": _network_clock, "state": _authoritative_snapshot})
	while _snapshot_buffer.size() > 8:
		_snapshot_buffer.pop_front()
	return true

func _compose_client_snapshot() -> void:
	if _authoritative_snapshot.is_empty():
		_snapshot = _simulation.get_snapshot()
		return
	const INTERPOLATION_DELAY := 0.12
	var target_time := _network_clock - INTERPOLATION_DELAY
	var earlier: Dictionary = _snapshot_buffer[0]
	var later: Dictionary = _snapshot_buffer[_snapshot_buffer.size() - 1]
	for index in range(_snapshot_buffer.size()):
		var sample: Dictionary = _snapshot_buffer[index]
		if float(sample.received_at) <= target_time:
			earlier = sample
		if float(sample.received_at) >= target_time:
			later = sample
			break
	var earlier_state: Dictionary = earlier.state
	var later_state: Dictionary = later.state
	var span := float(later.received_at) - float(earlier.received_at)
	var weight := clampf((target_time - float(earlier.received_at)) / span, 0.0, 1.0) if span > 0.0001 else 1.0
	var earlier_players: Dictionary = {}
	var later_players: Dictionary = {}
	for state in earlier_state.get("players", []):
		if state is Dictionary:
			earlier_players[str(state.get("user_id", ""))] = state
	for state in later_state.get("players", []):
		if state is Dictionary:
			later_players[str(state.get("user_id", ""))] = state
	var displayed: Array[Dictionary] = []
	for member in MultiplayerService.get_members():
		if not member is Dictionary:
			continue
		var user_id := str(member.get("user_id", ""))
		if user_id == _local_user_id:
			var local: Dictionary = _simulation.get_player(user_id)
			if not local.is_empty():
				displayed.append(local)
			continue
		var from: Dictionary = earlier_players.get(user_id, {})
		var to: Dictionary = later_players.get(user_id, from)
		if from.is_empty():
			from = to
		if to.is_empty():
			continue
		var interpolated := to.duplicate(true)
		interpolated.world_x = lerpf(float(from.get("world_x", to.get("world_x", 0.0))), float(to.get("world_x", 0.0)), weight)
		interpolated.y = lerpf(float(from.get("y", to.get("y", 0.0))), float(to.get("y", 0.0)), weight)
		interpolated.vertical_speed = lerpf(float(from.get("vertical_speed", to.get("vertical_speed", 0.0))), float(to.get("vertical_speed", 0.0)), weight)
		if weight < 1.0:
			interpolated.state = from.get("state", to.get("state", "running"))
		displayed.append(interpolated)
	_snapshot = _authoritative_snapshot.duplicate(true)
	_snapshot.players = displayed

func _local_speed_percent() -> int:
	var snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	if snapshot != null and snapshot.has_method("get_resolved_stats"):
		var stats: Variant = snapshot.call("get_resolved_stats")
		if stats is Dictionary:
			return clampi(int(stats.get("run_speed_percent", 10000)), 9500, 10500)
	return 10000

func _try_schedule_start() -> void:
	var present_members: Array[Dictionary] = []
	for member in MultiplayerService.get_members():
		if member is Dictionary and bool(member.get("is_connected", true)):
			present_members.append(member)
	if present_members.is_empty():
		return
	for member in present_members:
		var user_id := str(member.get("user_id", ""))
		if not bool(_received_match_ready.get(user_id, false)):
			return
	const START_DELAY_SECONDS := 2.0
	_go_start_at = _network_clock + START_DELAY_SECONDS
	MultiplayerService.send_peer_message_to_all("control", {"kind": "race_go", "start_delay_seconds": START_DELAY_SECONDS})
	_status_label.text = tr("Get ready…")

func _is_active_room_member(user_id: String) -> bool:
	for member in MultiplayerService.get_members():
		if member is Dictionary and bool(member.get("is_connected", true)) and str(member.get("user_id", "")) == user_id:
			return true
	return false

func _player_state(user_id: String) -> Dictionary:
	var players: Variant = _snapshot.get("players", [])
	if players is Array:
		for state in players:
			if state is Dictionary and str(state.get("user_id", "")) == user_id:
				return state
	return {}

func _sync_player_views() -> void:
	var camera_left := maxf(float(_player_state(_local_user_id).get("world_x", 180.0)) - CAMERA_LEAD, 0.0)
	var states: Variant = _snapshot.get("players", [])
	if not states is Array:
		return
	var present := {}
	for state in states:
		if not state is Dictionary:
			continue
		var user_id := str(state.get("user_id", ""))
		present[user_id] = true
		if not _player_views.has(user_id):
			var runner: Node2D = PlayerScene.instantiate()
			runner.name = "Runner_%s" % user_id.left(8)
			runner.call("set_input_enabled", false)
			add_child(runner)
			_player_views[user_id] = runner
		var view: Node2D = _player_views[user_id]
		var correction := _visual_correction if user_id == _local_user_id and not MultiplayerService.is_room_owner() else Vector2.ZERO
		view.position = Vector2(float(state.get("world_x", 0.0)) - camera_left, float(state.get("y", 0.0))) + correction
		view.visible = float(view.position.x) > -80.0 and float(view.position.x) < get_viewport_rect().size.x + 80.0
		var sprite := view.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite != null:
			sprite.flip_v = int(state.get("gravity_direction", 1)) < 0
			if str(state.get("state", "")) != "running":
				sprite.stop()
			elif not sprite.is_playing():
				sprite.play("run")
	for user_id in _player_views.keys():
		if not present.has(user_id):
			(_player_views[user_id] as Node2D).queue_free()
			_player_views.erase(user_id)

func _update_hud() -> void:
	var own := _player_state(_local_user_id)
	if own.is_empty():
		return
	var distance := maxi(0, int(float(own.get("world_x", 0.0)) - float(_manifest.get("start_x"))))
	var players: Variant = _snapshot.get("players", [])
	var place := 1
	if players is Array:
		for other in players:
			if other is Dictionary and str(other.get("state", "")) == "running" and float(other.get("world_x", 0.0)) > float(own.get("world_x", 0.0)):
				place += 1
	_distance_label.text = tr("DISTANCE %dm  ·  PLACE %d/%d") % [distance, place, players.size() if players is Array else 0]
	if bool(_snapshot.get("finished", false)):
		var placements: Variant = _snapshot.get("placements", [])
		var winner := str(placements[0].get("display_name", "")) if placements is Array and not placements.is_empty() else tr("No winner")
		_result_label.text = tr("Winner: %s") % winner
		_result_label.visible = true

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A full-rect HUD must not consume touch events intended for the game world.
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_distance_label = Label.new()
	_distance_label.position = Vector2(16, 12)
	_distance_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_distance_label)
	_status_label = Label.new()
	_status_label.anchor_left = 0.5
	_status_label.anchor_right = 0.5
	_status_label.offset_left = -260
	_status_label.offset_right = 260
	_status_label.offset_top = 72
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label_color()
	hud.add_child(_status_label)
	_result_label = Label.new()
	_result_label.anchor_left = 0.5
	_result_label.anchor_top = 0.5
	_result_label.anchor_right = 0.5
	_result_label.offset_left = -220
	_result_label.offset_right = 220
	_result_label.offset_top = -30
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 30)
	_result_label.visible = false
	hud.add_child(_result_label)
	var leave := Button.new()
	leave.text = tr("Leave race")
	leave.anchor_left = 1.0
	leave.anchor_right = 1.0
	leave.offset_left = -150
	leave.offset_right = -16
	leave.offset_top = 12
	leave.offset_bottom = 54
	leave.pressed.connect(_leave_match)
	hud.add_child(leave)
	var flip_button := Button.new()
	flip_button.text = tr("Flip gravity")
	flip_button.custom_minimum_size = Vector2(150, 54)
	flip_button.anchor_left = 1.0
	flip_button.anchor_right = 1.0
	flip_button.anchor_top = 1.0
	flip_button.anchor_bottom = 1.0
	flip_button.offset_left = -174
	flip_button.offset_right = -16
	flip_button.offset_top = -76
	flip_button.offset_bottom = -18
	flip_button.add_theme_font_size_override("font_size", 20)
	flip_button.pressed.connect(_flip_gravity)
	hud.add_child(flip_button)
	var touch_hint := Label.new()
	touch_hint.text = tr("Swipe up or down to flip gravity")
	touch_hint.anchor_left = 0.5
	touch_hint.anchor_right = 0.5
	touch_hint.anchor_top = 1.0
	touch_hint.anchor_bottom = 1.0
	touch_hint.offset_left = -210
	touch_hint.offset_right = 0
	touch_hint.offset_top = -62
	touch_hint.offset_bottom = -22
	touch_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	touch_hint.add_theme_font_size_override("font_size", 15)
	touch_hint.add_theme_color_override("font_color", Color("b9c8dc"))
	hud.add_child(touch_hint)

func _flip_gravity() -> void:
	if _simulation == null:
		return
	var state := _player_state(_local_user_id)
	if str(state.get("state", "")) == "running":
		_request_flip(-int(state.get("gravity_direction", 1)))

func status_label_color() -> void:
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color("ffd166"))

func _show_failure(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message

func _leave_match() -> void:
	MultiplayerService.leave_room()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _draw() -> void:
	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("101a2a"))
	var camera_left := maxf(float(_player_state(_local_user_id).get("world_x", 180.0)) - CAMERA_LEAD, 0.0)
	var x := 0.0
	while x < view_size.x:
		var world_a := camera_left + x
		var world_b := camera_left + minf(x + 20.0, view_size.x)
		var floor_a := _surface_at(world_a, false)
		var floor_b := _surface_at(world_b, false)
		var ceil_a := _surface_at(world_a, true)
		var ceil_b := _surface_at(world_b, true)
		if bool(floor_a.supported) and bool(floor_b.supported):
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, float(floor_a.y)), Vector2(minf(x + 20.0, view_size.x), float(floor_b.y)),
				Vector2(minf(x + 20.0, view_size.x), WORLD_HEIGHT), Vector2(x, WORLD_HEIGHT),
			]), Color("202e43"))
		if bool(ceil_a.supported) and bool(ceil_b.supported):
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 0.0), Vector2(minf(x + 20.0, view_size.x), 0.0),
				Vector2(minf(x + 20.0, view_size.x), float(ceil_b.y)), Vector2(x, float(ceil_a.y)),
			]), Color("202e43"))
		draw_line(Vector2(x, float(floor_a.y)), Vector2(minf(x + 20.0, view_size.x), float(floor_b.y)), Color("42d6c5"), 3.0)
		draw_line(Vector2(x, float(ceil_a.y)), Vector2(minf(x + 20.0, view_size.x), float(ceil_b.y)), Color("42d6c5"), 3.0)
		x += 20.0
	_draw_events(camera_left, view_size)
	var finish_screen_x := float(_manifest.get("finish_x")) - camera_left if _manifest != null else -1.0
	if finish_screen_x >= 0.0 and finish_screen_x <= view_size.x:
		draw_line(Vector2(finish_screen_x, 0), Vector2(finish_screen_x, WORLD_HEIGHT), Color("f5d45e"), 4.0)

func _draw_events(camera_left: float, view_size: Vector2) -> void:
	if _manifest == null:
		return
	for event in _manifest.get("events"):
		var kind := str(event.get("kind", ""))
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			var rect := Rect2(float(event.get("x", 0.0)) - camera_left - width * 0.5, y, width, height)
			if rect.end.x >= 0.0 and rect.position.x <= view_size.x:
				draw_rect(rect, Color("d17b42"))
				draw_rect(rect, Color("ffb05e"), false, 4.0)
		elif kind == "spikes":
			var start_x := float(event.get("start_x", event.get("x", 0.0))) - camera_left
			var y := float(event.get("y", 0.0))
			var count := int(event.get("count", 1))
			var spacing := float(event.get("spacing", 32.0))
			for spike_index in range(count):
				var sx := start_x + float(spike_index) * spacing
				if sx < -32.0 or sx > view_size.x + 32.0:
					continue
				var points := PackedVector2Array([Vector2(sx, y), Vector2(sx + 28.0, y), Vector2(sx + 14.0, y + (28.0 if bool(event.get("from_ceiling", false)) else -28.0))])
				draw_colored_polygon(points, Color("d95168"))

func _surface_at(world_x: float, ceiling: bool) -> Dictionary:
	if _manifest == null:
		return {"y": 460.0 if not ceiling else 80.0, "supported": true}
	var y := float(_manifest.get("initial_ceiling_y")) if ceiling else float(_manifest.get("initial_floor_y"))
	var supported := true
	for event in _manifest.get("events"):
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				if world_x >= float(event.get("x", 0.0)):
					y = float(event.get("end_y", y))
			"slope":
				var start_x := float(event.get("start_x", 0.0))
				var end_x := float(event.get("end_x", start_x))
				if world_x >= start_x and world_x <= end_x and end_x > start_x:
					y = lerpf(float(event.get("start_y", y)), float(event.get("end_y", y)), (world_x - start_x) / (end_x - start_x))
				elif world_x > end_x:
					y = float(event.get("end_y", y))
			"gap":
				var start_x := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
				if world_x >= start_x and world_x <= start_x + float(event.get("width", 0.0)):
					supported = false
	return {"y": y, "supported": supported}
