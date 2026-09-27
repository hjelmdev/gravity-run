extends Node2D

const PlayerScene := preload("res://player/player.tscn")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const SpikeScene := preload("res://hazards/spikes.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const SlopeScene := preload("res://terrain/slope.tscn")
const LedgeScene := preload("res://terrain/ledge.tscn")
const TrackGapScript := preload("res://terrain/track_gap.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseSurfaceRenderer := preload("res://systems/course_surface_renderer.gd")
const ResultMedalScript := preload("res://ui/result_medal.gd")

const WORLD_HEIGHT := 540.0
const CAMERA_LEAD := 180.0

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
var _received_runner_profile: Dictionary = {}
var _match_setup_retry_elapsed := 0.0
var _match_setup_retry_count := 0
var _match_setup_acknowledged := false
var _snapshot_elapsed := 0.0
var _status_label: Label
var _distance_label: Label
var _result_label: Label
var _results_panel: PanelContainer
var _results_list: VBoxContainer
var _return_lobby_button: Button
var _course_root: Node2D
var _course_nodes: Dictionary = {}
var _terrain_events: Array[Dictionary] = []
var _gap_events: Array[Dictionary] = []
var _touch_index := -1
var _touch_start := Vector2.ZERO
var _run_banner_until := 0.0
var _return_requested := false
var _return_request_started_at := 0.0
var _leaving_match := false
var _last_snapshot_receive_msec := 0
var _snapshot_interarrival_total_msec := 0
var _snapshot_interarrival_count := 0
var _snapshot_tick_gaps := 0

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	_local_user_id = MultiplayerService.identity_user_id
	_owner_user_id = str(MultiplayerService.room_state.get("owner_user_id", ""))
	_manifest = MultiplayerService.course_manifest
	_course_root = Node2D.new()
	_course_root.name = "SharedCourse"
	add_child(_course_root)
	MultiplayerService.peer_data_received.connect(_on_peer_data_received)
	MultiplayerService.peer_connection_state_changed.connect(_on_peer_connection_state_changed)
	MultiplayerService.room_changed.connect(_on_room_changed)
	MultiplayerService.request_finished.connect(_on_request_finished)
	_build_hud()
	if _manifest == null or not str(_manifest.call("validate")).is_empty():
		_show_failure(tr("The shared course is unavailable or failed validation."))
		return
	var members := MultiplayerService.get_members()
	var simulation_players: Array = []
	for member in members:
		if member is Dictionary and bool(member.get("is_connected", true)):
			var runner_profile := _local_runner_profile() if str(member.get("user_id", "")) == _local_user_id else {"run_speed_percent": 10000, "flip_cooldown_percent": 10000}
			simulation_players.append({
				"user_id": str(member.get("user_id", "")),
				"display_name": str(member.get("display_name", "Runner")),
				"skin_id": int(member.get("skin_id", 0)),
				"run_speed_percent": int(runner_profile.run_speed_percent),
				"flip_cooldown_percent": int(runner_profile.flip_cooldown_percent),
			})
	_simulation = SimulationScript.new()
	var configuration_error := str(_simulation.configure(_manifest, simulation_players))
	if not configuration_error.is_empty():
		_show_failure(configuration_error)
		return
	_build_course_view()
	_snapshot = _simulation.get_snapshot()
	_sync_player_views()
	if MultiplayerService.is_room_owner():
		_received_match_ready[_local_user_id] = true
		_received_runner_profile[_local_user_id] = true
	else:
		_status_label.text = tr("Waiting for the host to synchronize the start…") if _queue_match_setup() else tr("Could not queue match setup for the host. Reconnect or leave the race.")
	_waiting_since = _network_clock

func _process(delta: float) -> void:
	if _simulation == null:
		return
	_network_clock += delta
	if _return_requested and not MultiplayerService.is_room_owner() and _return_request_started_at > 0.0 and _network_clock - _return_request_started_at >= 10.0:
		_return_requested = false
		_return_lobby_button.disabled = false
		_return_lobby_button.text = tr("Return to lobby")
		_status_label.text = tr("The host has not returned the room yet. You can retry or leave the race.")
		_return_request_started_at = 0.0
	if _go_start_at > 0.0 and _network_clock >= _go_start_at and not _simulation.started:
		_simulation.start()
		print("[MP_DIAG] ", JSON.stringify({"event": "simulation_started", "room_id": MultiplayerService.get_room_id(), "owner": MultiplayerService.is_room_owner(), "players": _simulation.get_snapshot().get("players", []).size(), "at_ms": Time.get_ticks_msec()}))
		if MultiplayerService.is_room_owner():
			MultiplayerService.advance_match_phase("RUNNING")
		_status_label.text = tr("RUN!")
		_run_banner_until = _network_clock + 1.3
	elif _go_start_at > 0.0 and not _simulation.started:
		_status_label.text = tr("RUN in %d…") % ceili(maxf(_go_start_at - _network_clock, 0.0))
	if MultiplayerService.is_room_owner() and not _simulation.started and _go_start_at <= 0.0:
		_try_schedule_start()
		_retry_missing_match_setup(delta)
	if _simulation.started:
		var events: Array[Dictionary] = _simulation.advance_frame(delta)
		if MultiplayerService.is_room_owner():
			for event in events:
				if str(event.get("kind", "")) == "match_finished":
					_status_label.text = tr("Race finished")
					MultiplayerService.advance_match_phase("FINISHED")
			_snapshot = _simulation.get_snapshot()
			_snapshot_elapsed += delta
			if _snapshot_elapsed >= 1.0 / 15.0:
				_snapshot_elapsed = 0.0
				MultiplayerService.send_peer_message_to_all("snapshot", {"kind": "snapshot", "state": _snapshot})
		else:
			_visual_correction = _visual_correction.move_toward(Vector2.ZERO, delta * 420.0)
			_compose_client_snapshot()
	_update_hud()
	_sync_player_views()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _simulation == null or not _simulation.started or _player_state(_local_user_id).get("state", "") != "running":
		return
	if event is InputEventScreenTouch:
		if PlayerProfile.flip_control not in ["swipe", "tap"]:
			return
		if event.pressed:
			if _touch_index == -1:
				if PlayerProfile.flip_control == "tap":
					_request_flip(-int(_player_state(_local_user_id).get("gravity_direction", 1)))
				else:
					_touch_index = event.index
					_touch_start = event.position
		elif event.index == _touch_index:
			if PlayerProfile.flip_control != "tap":
				var swipe_delta: Vector2 = event.position - _touch_start
				if absf(swipe_delta.y) >= 48.0 and absf(swipe_delta.y) > absf(swipe_delta.x) * 1.2:
					_request_flip(-1 if swipe_delta.y < 0.0 else 1)
			_touch_index = -1
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
				_simulation.set_player_profile(peer_user_id, int(payload.get("run_speed_percent", 10000)), int(payload.get("flip_cooldown_percent", 10000)))
				_received_runner_profile[peer_user_id] = true
			"match_ready":
				_received_match_ready[peer_user_id] = true
				print("[MP_DIAG] ", JSON.stringify({"event": "peer_match_ready", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "at_ms": Time.get_ticks_msec()}))
				if bool(_received_runner_profile.get(peer_user_id, false)):
					MultiplayerService.queue_reliable_peer_message(peer_user_id, {"kind": "match_setup_ack", "room_id": MultiplayerService.get_room_id()})
			"return_lobby_request":
				if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
					MultiplayerService.return_to_lobby()
			"race_go_ack":
				print("[MP_DIAG] ", JSON.stringify({"event": "race_go_ack", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "at_ms": Time.get_ticks_msec()}))
			"flip":
				var sequence := int(payload.get("input_sequence", 0))
				if sequence > int(_last_input_sequence.get(peer_user_id, 0)):
					_last_input_sequence[peer_user_id] = sequence
					_simulation.submit_flip(peer_user_id, int(payload.get("gravity_direction", 0)))
	elif not MultiplayerService.is_room_owner():
		if channel_name == "control" and str(payload.get("kind", "")) == "match_setup_request":
			if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
				_queue_match_setup()
		elif channel_name == "control" and str(payload.get("kind", "")) == "match_setup_ack":
			if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
				_match_setup_acknowledged = true
				print("[MP_DIAG] ", JSON.stringify({"event": "match_setup_ack", "room_id": MultiplayerService.get_room_id(), "at_ms": Time.get_ticks_msec()}))
		elif channel_name == "control" and str(payload.get("kind", "")) == "race_go":
			_go_start_at = _network_clock + clampf(float(payload.get("start_delay_seconds", 5.0)), 0.5, 5.0)
			print("[MP_DIAG] ", JSON.stringify({"event": "race_go_received", "room_id": MultiplayerService.get_room_id(), "delay_seconds": float(payload.get("start_delay_seconds", 5.0)), "at_ms": Time.get_ticks_msec()}))
			MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "race_go_ack", "room_id": MultiplayerService.get_room_id()})
			_status_label.text = tr("RUN in %d…") % ceili(_go_start_at - _network_clock)
		elif channel_name == "snapshot" and str(payload.get("kind", "")) == "snapshot":
			var new_snapshot: Variant = payload.get("state", {})
			var previous_tick := _last_authoritative_tick
			if _accept_authoritative_snapshot(new_snapshot):
				if _last_snapshot_receive_msec == 0:
					print("[MP_DIAG] ", JSON.stringify({"event": "first_snapshot_received", "room_id": MultiplayerService.get_room_id(), "tick": int(new_snapshot.get("tick", -1)), "at_ms": Time.get_ticks_msec()}))
				var now_msec := Time.get_ticks_msec()
				var interarrival_msec := now_msec - _last_snapshot_receive_msec if _last_snapshot_receive_msec > 0 else 0
				if interarrival_msec > 0:
					_snapshot_interarrival_total_msec += interarrival_msec
					_snapshot_interarrival_count += 1
				var tick_gap := int(new_snapshot.get("tick", -1)) - previous_tick
				if previous_tick >= 0 and tick_gap > 5:
					_snapshot_tick_gaps += tick_gap - 4
				if _snapshot_interarrival_count >= 150:
					print("[MP_DIAG] ", JSON.stringify({"event": "snapshot_quality", "room_id": MultiplayerService.get_room_id(), "samples": _snapshot_interarrival_count, "mean_interarrival_ms": _snapshot_interarrival_total_msec / _snapshot_interarrival_count, "estimated_missing_ticks": _snapshot_tick_gaps}))
					_snapshot_interarrival_total_msec = 0
					_snapshot_interarrival_count = 0
					_snapshot_tick_gaps = 0
				_last_snapshot_receive_msec = now_msec
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
	if not _simulation.apply_authoritative_world_hazards(snapshot.get("world_hazards", {})):
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
	var earlier_hazards: Variant = earlier_state.get("world_hazards", {})
	var later_hazards: Variant = later_state.get("world_hazards", {})
	if earlier_hazards is Dictionary and later_hazards is Dictionary:
		var earlier_barrels: Dictionary = {}
		for barrel in earlier_hazards.get("barrels", []):
			if barrel is Dictionary:
				earlier_barrels[str(barrel.get("entity_id", ""))] = barrel
		var interpolated_barrels: Array[Dictionary] = []
		for barrel in later_hazards.get("barrels", []):
			if not barrel is Dictionary:
				continue
			var barrel_view: Dictionary = barrel.duplicate(true)
			var from: Dictionary = earlier_barrels.get(str(barrel.get("entity_id", "")), barrel)
			barrel_view.x = lerpf(float(from.get("x", barrel.get("x", 0.0))), float(barrel.get("x", 0.0)), weight)
			barrel_view.y = lerpf(float(from.get("y", barrel.get("y", 0.0))), float(barrel.get("y", 0.0)), weight)
			barrel_view.roll_angle = lerp_angle(float(from.get("roll_angle", barrel.get("roll_angle", 0.0))), float(barrel.get("roll_angle", 0.0)), weight)
			barrel_view.rotation = lerp_angle(float(from.get("rotation", barrel.get("rotation", 0.0))), float(barrel.get("rotation", 0.0)), weight)
			interpolated_barrels.append(barrel_view)
		var displayed_hazards: Dictionary = later_hazards.duplicate(true)
		displayed_hazards.barrels = interpolated_barrels
		_snapshot.world_hazards = displayed_hazards

func _local_runner_profile() -> Dictionary:
	var snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	if snapshot != null and snapshot.has_method("get_resolved_stats"):
		var stats: Variant = snapshot.call("get_resolved_stats")
		if stats is Dictionary:
			return {
				"run_speed_percent": clampi(int(stats.get("run_speed_percent", 10000)), 9500, 10500),
				"flip_cooldown_percent": clampi(int(stats.get("flip_cooldown_percent", 10000)), 5000, 20000),
			}
	return {"run_speed_percent": 10000, "flip_cooldown_percent": 10000}

func _try_schedule_start() -> void:
	var present_members: Array[Dictionary] = []
	for member in MultiplayerService.get_members():
		if member is Dictionary and bool(member.get("is_connected", true)):
			present_members.append(member)
	if present_members.is_empty():
		return
	for member in present_members:
		var user_id := str(member.get("user_id", ""))
		if not bool(_received_match_ready.get(user_id, false)) or not bool(_received_runner_profile.get(user_id, false)):
			return
	const START_DELAY_SECONDS := 5.0
	_go_start_at = _network_clock + START_DELAY_SECONDS
	print("[MP_DIAG] ", JSON.stringify({"event": "race_go_queued", "room_id": MultiplayerService.get_room_id(), "peers": present_members.size() - 1, "delay_seconds": START_DELAY_SECONDS, "at_ms": Time.get_ticks_msec()}))
	for member in present_members:
		var peer_id := str(member.get("user_id", ""))
		if peer_id != _local_user_id and not MultiplayerService.queue_reliable_peer_message(peer_id, {"kind": "race_go", "start_delay_seconds": START_DELAY_SECONDS}):
			_go_start_at = 0.0
			_status_label.text = tr("Could not queue the match start for every player. Check connections and retry.")
			return
	_status_label.text = tr("RUN in %d…") % ceili(START_DELAY_SECONDS)

func _queue_match_setup() -> bool:
	var profile := _local_runner_profile()
	var profile_queued := MultiplayerService.queue_reliable_peer_message(_owner_user_id, {
		"kind": "runner_profile",
		"run_speed_percent": int(profile.get("run_speed_percent", 10000)),
		"flip_cooldown_percent": int(profile.get("flip_cooldown_percent", 10000)),
	})
	var ready_queued := MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "match_ready"})
	if profile_queued and ready_queued:
		print("[MP_DIAG] ", JSON.stringify({"event": "match_setup_queued", "room_id": MultiplayerService.get_room_id(), "retry": _match_setup_retry_count, "at_ms": Time.get_ticks_msec()}))
	return profile_queued and ready_queued

func _retry_missing_match_setup(delta: float) -> void:
	var missing_peers: Array[String] = []
	for member in MultiplayerService.get_members():
		if not member is Dictionary or not bool(member.get("is_connected", true)):
			continue
		var peer_id := str(member.get("user_id", ""))
		if peer_id != _local_user_id and (not bool(_received_match_ready.get(peer_id, false)) or not bool(_received_runner_profile.get(peer_id, false))):
			missing_peers.append(peer_id)
	if missing_peers.is_empty():
		return
	_match_setup_retry_elapsed += delta
	if _match_setup_retry_elapsed < 5.0:
		return
	_match_setup_retry_elapsed = 0.0
	if _match_setup_retry_count < 3:
		_match_setup_retry_count += 1
		print("[MP_DIAG] ", JSON.stringify({"event": "match_setup_retry", "room_id": MultiplayerService.get_room_id(), "peers": missing_peers, "retry": _match_setup_retry_count, "at_ms": Time.get_ticks_msec()}))
		for peer_id in missing_peers:
			if not MultiplayerService.queue_reliable_peer_message(peer_id, {"kind": "match_setup_request", "room_id": MultiplayerService.get_room_id()}):
				_status_label.text = tr("Could not retry match setup for every player. Check the direct connection or leave the race.")
	else:
		_status_label.text = tr("A player did not finish loading the match. Ask them to reconnect or leave the race.")

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

func _build_course_view() -> void:
	_course_nodes.clear()
	_terrain_events.clear()
	_gap_events.clear()
	var floor_y := float(_manifest.get("initial_floor_y"))
	var ceiling_y := float(_manifest.get("initial_ceiling_y"))
	for event in _manifest.get("events"):
		if str(event.get("kind", "")) in ["step", "slope"]:
			_terrain_events.append(event)
		elif str(event.get("kind", "")) == "gap":
			_gap_events.append(event)
		var event_id := str(event.get("event_id", ""))
		var kind := str(event.get("kind", ""))
		var x := float(event.get("x", 0.0))
		var from_ceiling := bool(event.get("from_ceiling", false))
		var surface_y := ceiling_y if from_ceiling else floor_y
		match kind:
			"spikes":
				var start_x := float(event.get("start_x", x))
				for index in range(int(event.get("count", 1))):
					var spike := SpikeScene.instantiate() as Node2D
					spike.position = Vector2(start_x + float(index) * float(event.get("spacing", 32.0)), float(event.get("y", surface_y)))
					spike.call("configure", Vector2(CourseGenerator.SPIKE_WIDTH, CourseGenerator.SPIKE_HEIGHT), from_ceiling)
					spike.name = "Spike_%s_%d" % [event_id, index]
					_course_root.add_child(spike)
					_course_nodes["%s_%d" % [event_id, index]] = spike
			"block":
				var block := BlockScene.instantiate() as Node2D
				block.position = Vector2(x, float(event.get("y", surface_y)))
				block.call("configure", Vector2(float(event.get("width", 48.0)), float(event.get("height", 72.0))), from_ceiling)
				block.name = "Block_%s" % event_id
				_course_root.add_child(block)
				_course_nodes[event_id] = block
			"barrels":
				var count := int(event.get("count", 1))
				var spacing := float(event.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
				var chain_width := float(count - 1) * spacing
				var speed_multiplier := float(event.get("motion_speed_multiplier", 1.0))
				var spawn_offset := float(event.get("spawn_lead_distance", 820.0)) * (speed_multiplier - 1.0)
				for index in range(count):
					var barrel_id := "%s_%d" % [event_id, index]
					var barrel := BarrelScene.instantiate() as Node2D
					barrel.position = Vector2(x + spawn_offset - chain_width * 0.5 + float(index) * spacing, float(event.get("y", floor_y)))
					barrel.call("configure", Vector2(HazardRules.BARREL_WIDTH, float(event.get("height", HazardRules.BARREL_WIDTH))), false)
					barrel.call("set_motion_speed_multiplier", speed_multiplier)
					barrel.name = "Barrel_%s" % barrel_id
					_course_root.add_child(barrel)
					_course_nodes[barrel_id] = barrel
			"gap":
				var gap := TrackGapScript.new() as Node2D
				gap.position = Vector2(x, 0.0)
				gap.call("configure", float(event.get("width", 160.0)), from_ceiling)
				gap.name = "Gap_%s" % event_id
				_course_root.add_child(gap)
				_course_nodes[event_id] = gap
			"step":
				var step := LedgeScene.instantiate() as Node2D
				var start_y := float(event.get("start_y", surface_y))
				var end_y := float(event.get("end_y", start_y))
				step.position = Vector2(x, 0.0)
				step.call("configure_step", start_y, end_y, from_ceiling, bool(event.get("spiked", false)))
				step.name = "Step_%s" % event_id
				_course_root.add_child(step)
				_course_nodes[event_id] = step
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y
			"slope":
				var slope := SlopeScene.instantiate() as Node2D
				var start_y := float(event.get("start_y", surface_y))
				var end_y := float(event.get("end_y", start_y))
				slope.position.x = float(event.get("start_x", x - 220.0))
				slope.call("configure", start_y, end_y, from_ceiling)
				slope.name = "Slope_%s" % event_id
				_course_root.add_child(slope)
				_course_nodes[event_id] = slope
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y

func _sync_course_view() -> void:
	var world_hazards: Variant = _snapshot.get("world_hazards", {})
	if not world_hazards is Dictionary:
		return
	var barrels: Variant = world_hazards.get("barrels", [])
	if barrels is Array:
		for barrel_state in barrels:
			if not barrel_state is Dictionary:
				continue
			var barrel_id := str(barrel_state.get("entity_id", ""))
			var barrel_value: Variant = _course_nodes.get(barrel_id)
			# A barrel node can have completed its destruction animation and been
			# queue_freed while its ID remains in _course_nodes. Validate the raw
			# reference before casting it to Node2D.
			if not is_instance_valid(barrel_value) or not barrel_value is Node2D:
				continue
			var barrel: Node2D = barrel_value
			barrel.call("apply_replicated_motion",
				Vector2(float(barrel_state.get("x", barrel.position.x)), float(barrel_state.get("y", barrel.position.y))),
				float(barrel_state.get("roll_angle", 0.0)),
				float(barrel_state.get("rotation", 0.0)),
				bool(barrel_state.get("spawned", false))
			)
			if bool(barrel_state.get("destroyed", false)) and not bool(barrel.call("is_destroying_now")):
				barrel.call("destroy")
		var destroyed: Variant = world_hazards.get("destroyed_event_ids", [])
		if destroyed is Array:
			for event_id in destroyed:
				var node_value: Variant = _course_nodes.get(str(event_id))
				if not is_instance_valid(node_value) or not node_value is Node2D:
					continue
				var node: Node2D = node_value
				if not bool(node.call("is_destroying_now")):
					node.call("destroy")

func _sync_player_views() -> void:
	var camera_left := _camera_left()
	_course_root.position.x = -camera_left
	_sync_course_view()
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
			_course_root.add_child(runner)
			runner.call("set_input_enabled", false)
			_player_views[user_id] = runner
		var view: Node2D = _player_views[user_id]
		view.call("set_skin_id", int(state.get("skin_id", 0)))
		var correction := _visual_correction if user_id == _local_user_id and not MultiplayerService.is_room_owner() else Vector2.ZERO
		view.position = Vector2(float(state.get("world_x", 0.0)), float(state.get("y", 0.0))) + correction
		var screen_x := float(view.position.x) - camera_left
		view.visible = screen_x > -80.0 and screen_x < get_viewport_rect().size.x + 80.0
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
	var own: Dictionary = _simulation.get_player(_local_user_id) if _simulation != null else {}
	if own.is_empty():
		return
	var distance := distance_m(float(own.get("world_x", 0.0)), float(_manifest.get("start_x")))
	var players: Variant = _snapshot.get("players", [])
	var place := 1
	if players is Array:
		for other in players:
			if other is Dictionary and str(other.get("state", "")) == "running" and float(other.get("world_x", 0.0)) > float(own.get("world_x", 0.0)):
				place += 1
	var distance_text := tr("DISTANCE %dm  ·  PLACE %d/%d") % [distance, place, players.size() if players is Array else 0]
	if _distance_label.text != distance_text:
		_distance_label.text = distance_text
	if _simulation.started and str(own.get("state", "")) == "running":
		if bool(own.get("blocked", false)):
			_status_label.text = tr("BLOCKED — FLIP GRAVITY")
		elif _network_clock >= _run_banner_until and _status_label.text != "":
			_status_label.text = ""
	elif str(own.get("state", "")) == "dead" and _status_label.text != tr("You were eliminated"):
		_status_label.text = tr("You were eliminated")
	if bool(_snapshot.get("finished", false)):
		_show_results()
		_return_lobby_button.disabled = _return_requested

func _camera_left() -> float:
	var followed_x := float(_player_state(_local_user_id).get("world_x", 180.0))
	if str(_player_state(_local_user_id).get("state", "running")) != "running":
		var players: Variant = _snapshot.get("players", [])
		if players is Array:
			for player in players:
				if player is Dictionary and str(player.get("state", "")) == "running":
					followed_x = maxf(followed_x, float(player.get("world_x", followed_x)))
	return maxf(followed_x - CAMERA_LEAD, 0.0)

func _on_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		if _leaving_match:
			return
		AppNavigation.request_game_hub()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	if not room.is_empty() and str(room.get("phase", "")) == "OPEN":
		AppNavigation.request_multiplayer_lobby()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")

static func distance_m(world_x: float, start_x: float) -> int:
	return maxi(0, int((world_x - start_x) / 10.0))

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A full-rect HUD must not consume touch events intended for the game world.
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_distance_label = Label.new()
	_distance_label.anchor_left = 1.0
	_distance_label.anchor_right = 1.0
	_distance_label.offset_left = -535
	_distance_label.offset_right = -166
	_distance_label.offset_top = 15
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_distance_label.add_theme_font_size_override("font_size", 17)
	_distance_label.add_theme_color_override("font_color", Color("b8c7dc"))
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
	_results_panel = PanelContainer.new()
	_results_panel.anchor_left = 0.5
	_results_panel.anchor_top = 0.5
	_results_panel.anchor_right = 0.5
	_results_panel.anchor_bottom = 0.5
	_results_panel.offset_left = -260
	_results_panel.offset_right = 260
	_results_panel.offset_top = -205
	_results_panel.offset_bottom = 205
	_results_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("18243a")
	panel_style.border_color = Color("42d6c5")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	_results_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(_results_panel)
	var results_layout := VBoxContainer.new()
	results_layout.add_theme_constant_override("separation", 8)
	_results_panel.add_child(results_layout)
	var results_title := Label.new()
	results_title.text = tr("RACE RESULTS")
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_title.add_theme_font_size_override("font_size", 25)
	results_title.add_theme_color_override("font_color", Color("42d6c5"))
	results_layout.add_child(results_title)
	_result_label.text = ""
	_result_label.custom_minimum_size.y = 30
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.add_theme_color_override("font_color", Color("f5d45e"))
	_result_label.get_parent().remove_child(_result_label)
	results_layout.add_child(_result_label)
	_results_list = VBoxContainer.new()
	_results_list.add_theme_constant_override("separation", 5)
	results_layout.add_child(_results_list)
	_return_lobby_button = Button.new()
	_return_lobby_button.text = tr("Return to lobby")
	_return_lobby_button.custom_minimum_size.y = 44
	_return_lobby_button.pressed.connect(_return_to_lobby)
	results_layout.add_child(_return_lobby_button)
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
func _show_results() -> void:
	if _results_panel.visible:
		return
	_results_panel.visible = true
	_result_label.visible = true
	var states: Array[Dictionary] = []
	var players: Variant = _snapshot.get("players", [])
	if players is Array:
		for player in players:
			if player is Dictionary:
				states.append(player.duplicate(true))
	states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_finished := str(a.get("state", "")) == "finished"
		var b_finished := str(b.get("state", "")) == "finished"
		if a_finished != b_finished:
			return a_finished
		if a_finished and int(a.get("finish_tick", -1)) != int(b.get("finish_tick", -1)):
			return int(a.get("finish_tick", -1)) < int(b.get("finish_tick", -1))
		if not is_equal_approx(float(a.get("world_x", 0.0)), float(b.get("world_x", 0.0))):
			return float(a.get("world_x", 0.0)) > float(b.get("world_x", 0.0))
		return str(a.get("user_id", "")) < str(b.get("user_id", ""))
	)
	var winner_name := str(states[0].get("display_name", "")) if not states.is_empty() else ""
	_result_label.text = tr("Winner: %s") % winner_name if not winner_name.is_empty() else tr("No winner")
	for child in _results_list.get_children():
		child.queue_free()
	for index in range(states.size()):
		var state: Dictionary = states[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank := Label.new()
		rank.custom_minimum_size.x = 48
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.text = "#%d" % (index + 1)
		if index < 3:
			var medal := Control.new()
			medal.set_script(ResultMedalScript)
			medal.set("place", index + 1)
			medal.custom_minimum_size = Vector2(38, 34)
			medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(medal)
		row.add_child(rank)
		var player_name := Label.new()
		player_name.text = str(state.get("display_name", tr("Runner")))
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(player_name)
		var player_distance := distance_m(float(state.get("world_x", 0.0)), float(_manifest.get("start_x")))
		var distance_label := Label.new()
		distance_label.text = "%d m" % player_distance
		distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(distance_label)
		_results_list.add_child(row)
func _return_to_lobby() -> void:
	if _return_requested:
		return
	_return_requested = true
	_return_lobby_button.disabled = true
	_return_lobby_button.text = tr("Returning to lobby…")
	if MultiplayerService.is_room_owner():
		MultiplayerService.return_to_lobby()
	else:
		var queued := MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "return_lobby_request", "room_id": MultiplayerService.get_room_id()})
		if queued:
			_return_request_started_at = _network_clock
			_return_lobby_button.text = tr("Return request sent to host…")
		else:
			_return_requested = false
			_return_lobby_button.disabled = false
			_return_lobby_button.text = tr("Return to lobby")
			_status_label.text = tr("Could not send a return request to the host.")

func _on_request_finished(action: String, success: bool, message: String) -> void:
	if action == "advance_match_phase":
		if not success:
			_status_label.text = message
		return
	if action != "return_to_lobby":
		return
	if success:
		return
	_return_requested = false
	_return_request_started_at = 0.0
	_return_lobby_button.disabled = false
	_return_lobby_button.text = tr("Return to lobby")
	_status_label.text = message

func status_label_color() -> void:
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color("ffd166"))

func _show_failure(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message

func _leave_match() -> void:
	_leaving_match = true
	MultiplayerService.leave_room()
	AppNavigation.request_game_hub()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _draw() -> void:
	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("101827"))
	var camera_left := _camera_left()
	for index in range(18):
		var star_x := fposmod(float(index * 83) + camera_left * 0.12, view_size.x)
		draw_circle(Vector2(star_x, 58.0 + float((index * 47) % 390)), 1.5, Color("26364b"))
	_draw_course_surfaces(camera_left, view_size)
	var finish_screen_x := float(_manifest.get("finish_x")) - camera_left if _manifest != null else -1.0
	if finish_screen_x >= 0.0 and finish_screen_x <= view_size.x:
		draw_line(Vector2(finish_screen_x, 0), Vector2(finish_screen_x, WORLD_HEIGHT), Color("f5d45e"), 4.0)

func _draw_course_surfaces(camera_left: float, view_size: Vector2) -> void:
	if _manifest == null:
		return
	var gaps: Array[Dictionary] = []
	for event in _gap_events:
		var half_width := float(event.get("width", 0.0)) * 0.5
		gaps.append({"start": float(event.get("x", 0.0)) - half_width, "end": float(event.get("x", 0.0)) + half_width, "ceiling": bool(event.get("from_ceiling", false))})
	var boundaries: Array[float] = []
	var steps: Array[float] = []
	for event in _terrain_events:
		if str(event.get("kind", "")) == "slope":
			boundaries.append(float(event.get("start_x", 0.0)))
			boundaries.append(float(event.get("end_x", 0.0)))
		else:
			steps.append(float(event.get("x", 0.0)))
	CourseSurfaceRenderer.draw_track(self, camera_left, view_size, gaps, boundaries, steps, Callable(self, "_manifest_surface_y_at"), camera_left)

func _manifest_surface_y_at(x: float, ceiling: bool) -> float:
	var y := float(_manifest.get("initial_ceiling_y")) if ceiling else float(_manifest.get("initial_floor_y"))
	for event in _terrain_events:
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
					y = lerpf(float(event.get("start_y", y)), float(event.get("end_y", y)), (x - start_x) / (end_x - start_x))
				elif x > end_x:
					y = float(event.get("end_y", y))
	return y
