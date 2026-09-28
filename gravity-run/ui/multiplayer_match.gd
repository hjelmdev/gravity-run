extends Node2D

const PlayerScene := preload("res://player/player.tscn")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const LocalPredictionScript := preload("res://systems/multiplayer_local_prediction.gd")
const SpikeScene := preload("res://hazards/spikes.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const SlopeScene := preload("res://terrain/slope.tscn")
const LedgeScene := preload("res://terrain/ledge.tscn")
const TrackGapScript := preload("res://terrain/track_gap.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const TerminalEventRules := preload("res://systems/multiplayer_terminal_event.gd")
const CourseSurfaceRenderer := preload("res://systems/course_surface_renderer.gd")
const ResultMedalScript := preload("res://ui/result_medal.gd")

const WORLD_HEIGHT := 540.0
const CAMERA_LEAD := 180.0
const SNAPSHOT_RATE := 30.0
const SNAPSHOT_INTERVAL_SECONDS := 1.0 / SNAPSHOT_RATE
const SNAPSHOT_EXTRAPOLATION_LIMIT_TICKS := 3.0
const SIMULATION_TICK_RATE := 60.0
const LOCAL_CORRECTION_SPEED := 720.0
const MAX_PREDICTION_LEAD_TICKS := 24
const BASE_SNAPSHOT_DELAY_TICKS := 2.0
const VISUAL_PLAYER_SLOT_SPACING := 28.0
const CAMERA_MODE_LOCAL := "LOCAL_PLAYER"
const CAMERA_MODE_SPECTATING := "SPECTATING"
const CAMERA_MODE_FINISHED := "FINISHED"

var _manifest: Resource
var _simulation: RefCounted
var _local_prediction: RefCounted
var _snapshot: Dictionary = {}
var _authoritative_snapshot: Dictionary = {}
var _snapshot_buffer: Array[Dictionary] = []
var _local_render_history: Array[Dictionary] = []
var _local_render_clock_tick := 0.0
var _terminal_overlays: Dictionary = {}
var _match_roster_ids: Array[String] = []
var _finish_revision := 0
var _accepted_finish_revision := 0
var _accepted_finish_tick := -1
var _finish_reason := ""
var _finish_tick := -1
var _match_trace_ring: Array[Dictionary] = []
var _last_peer_traffic_msec: Dictionary = {}
var _camera_mode := CAMERA_MODE_LOCAL
var _spectator_target_user_id := ""
var _camera_left_cached := 0.0
var _network_clock := 0.0
var _last_authoritative_tick := -1
var _last_snapshot_received_network_clock := -1.0
var _estimated_peer_rtt_msec := 0.0
var _prediction_cap_frames := 0
var _prediction_replay_limit_frames := 0
var _prediction_frames := 0
var _prediction_tick_samples: Array[int] = []
var _frame_cost_samples: Array[int] = []
var _reconcile_cost_samples: Array[int] = []
var _max_reconcile_usec := 0
var _visual_correction := Vector2.ZERO
var _visual_slot_by_user: Dictionary = {}
var _input_sequence := 0
var _last_input_sequence: Dictionary = {}
var _start_generation := ""
var _start_probe_sent_at: Dictionary = {}
var _start_peer_offsets: Dictionary = {}
var _start_committed := false
var _start_probe_retry_elapsed := 0.0
var _start_probe_retry_count := 0
var _planned_host_start_msec := -1
var _planned_local_start_msec := -1
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
var _snapshot_send_metrics_elapsed := 0.0
var _snapshot_jitter_msec := 0.0
var _snapshot_mean_interval_msec := 0.0
var _snapshot_delay_ticks := BASE_SNAPSHOT_DELAY_TICKS
var _snapshot_render_tick := -1.0
var _snapshot_extrapolated_frames := 0
var _snapshot_render_samples := 0
var _max_local_correction_px := 0.0
var _max_correction_x_px := 0.0
var _max_correction_y_px := 0.0
var _snapshot_send_totals := {"count": 0, "bytes": 0, "serialized_usec": 0, "failed": 0, "dropped": 0}
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
var _return_requester_name := ""
var _leaving_match := false
var _last_snapshot_receive_msec := 0
var _snapshot_interarrival_total_msec := 0
var _snapshot_interarrival_count := 0
var _snapshot_tick_gaps := 0
var _return_request_notice: Label
var _return_notice_override := ""
var _diagnostic_lines: Array[String] = []
var _diagnostic_panel: PanelContainer
var _diagnostic_text: TextEdit
var _diagnostic_event_times: Dictionary = {}
var _last_snapshot_rejection := ""
var _local_finish_ignored_logged := false
var _finish_payload: Dictionary = {}
var _finish_acknowledged_peers: Dictionary = {}
var _finish_retry_elapsed := 0.0
var _diagnostic_status_label: Label
var _last_diagnostic_visual_order: Array[String] = []
var _snapshot_sequence := 0
var _last_diagnostic_snapshot_sequence := -1
var _authority_stall_elapsed := 0.0
var _authority_stall_reported := false
var _match_snapshot_received := 0
var _match_snapshot_rejected := 0
var _camera_delta_x_frame := 0.0

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
	var stable_user_ids: Array[String] = []
	for member in members:
		if member is Dictionary and bool(member.get("is_connected", true)):
			stable_user_ids.append(str(member.get("user_id", "")))
			var runner_profile := _local_runner_profile() if str(member.get("user_id", "")) == _local_user_id else {"run_speed_percent": 10000, "flip_cooldown_percent": 10000}
			simulation_players.append({
				"user_id": str(member.get("user_id", "")),
				"display_name": str(member.get("display_name", "Runner")),
				"skin_id": int(member.get("skin_id", 0)),
				"run_speed_percent": int(runner_profile.run_speed_percent),
				"flip_cooldown_percent": int(runner_profile.flip_cooldown_percent),
			})
	stable_user_ids.sort()
	_match_roster_ids = stable_user_ids.duplicate()
	for index in range(stable_user_ids.size()):
		_visual_slot_by_user[stable_user_ids[index]] = (float(index) - float(stable_user_ids.size() - 1) * 0.5) * VISUAL_PLAYER_SLOT_SPACING
	_simulation = SimulationScript.new()
	var configuration_error := str(_simulation.configure(_manifest, simulation_players))
	if not configuration_error.is_empty():
		_show_failure(configuration_error)
		return
	if not MultiplayerService.is_room_owner():
		_local_prediction = LocalPredictionScript.new()
		_local_prediction.bind(_simulation, _local_user_id)
	_build_course_view()
	_snapshot = _simulation.get_snapshot()
	if not MultiplayerService.is_room_owner():
		_reset_local_render_history(int(_simulation.get("tick")))
	_sync_player_views()
	if MultiplayerService.is_room_owner():
		_received_match_ready[_local_user_id] = true
		_received_runner_profile[_local_user_id] = true
	else:
		_status_label.text = tr("Waiting for the host to synchronize the start…") if _queue_match_setup() else tr("Could not queue match setup for the host. Reconnect or leave the race.")
	_waiting_since = _network_clock
	var diagnostic_roster: Array[Dictionary] = []
	for member_id in stable_user_ids:
		for member in members:
			if member is Dictionary and str(member.get("user_id", "")) == member_id:
				diagnostic_roster.append({"user_id": member_id, "display_name": str(member.get("display_name", "Runner")), "skin_id": int(member.get("skin_id", 0))})
				break
	var local_label := "unknown"
	for index in range(diagnostic_roster.size()):
		if str(diagnostic_roster[index].get("user_id", "")) == _local_user_id:
			local_label = "p%d" % index
	MultiplayerDiagnostics.begin_match({"role": "host" if MultiplayerService.is_room_owner() else "guest", "player_label": local_label, "roster": diagnostic_roster, "match_generation": _start_generation, "course_identity": str(_manifest.get("course_identity"))})
	MultiplayerDiagnostics.report_changed.connect(_on_diagnostics_status_changed)

func _process(delta: float) -> void:
	if _simulation == null:
		return
	var frame_work_started_usec := Time.get_ticks_usec()
	var phase := "results" if _results_panel != null and _results_panel.visible else ("running" if _simulation.started else "startup")
	if _camera_mode == CAMERA_MODE_SPECTATING:
		phase = "spectating"
	MultiplayerDiagnostics.set_phase(phase)
	_network_clock += delta
	var just_started := false
	if _return_requested and not MultiplayerService.is_room_owner() and _return_request_started_at > 0.0 and _network_clock - _return_request_started_at >= 10.0:
		_return_requested = false
		_return_lobby_button.disabled = false
		_return_lobby_button.text = tr("Ask host to return")
		_return_notice_override = tr("The host has not returned the room yet. You can retry or leave the race.")
		_update_return_request_notice()
		_return_request_started_at = 0.0
	if _go_start_at > 0.0 and _network_clock >= _go_start_at and not _simulation.started:
		_simulation.start()
		just_started = true
		MultiplayerDiagnostics.mark_simulation_started({"players": _simulation.get_snapshot().get("players", []).size(), "match_generation": _start_generation, "planned_host_start_msec": _planned_host_start_msec, "actual_start_msec": Time.get_ticks_msec(), "start_error_msec": Time.get_ticks_msec() - _planned_local_start_msec})
		_record_match_diag("simulation_started", {"players": _simulation.get_snapshot().get("players", []).size(), "match_generation": _start_generation, "planned_host_start_msec": _planned_host_start_msec, "actual_start_msec": Time.get_ticks_msec(), "start_error_msec": Time.get_ticks_msec() - _planned_local_start_msec})
		if MultiplayerService.is_room_owner():
			MultiplayerService.advance_match_phase("RUNNING")
		_status_label.text = tr("RUN!")
		_run_banner_until = _network_clock + 1.3
	elif _go_start_at > 0.0 and not _simulation.started:
		_status_label.text = tr("RUN in %d…") % ceili(maxf(_go_start_at - _network_clock, 0.0))
	if MultiplayerService.is_room_owner() and not _simulation.started and _go_start_at <= 0.0:
		_try_schedule_start()
		_retry_missing_match_setup(delta)
		_retry_start_probes(delta)
	if _simulation.started:
		var simulation_delta := delta
		if just_started:
			simulation_delta = maxf(_network_clock - _go_start_at, 0.0)
		var events: Array[Dictionary]
		if MultiplayerService.is_room_owner():
			var simulation_started_usec := Time.get_ticks_usec()
			events = _simulation.advance_frame(simulation_delta, true)
			MultiplayerDiagnostics.record_timing("host_simulation", Time.get_ticks_usec() - simulation_started_usec, {"tick": int(_simulation.get("tick")), "backlog_seconds": float(_simulation.get_snapshot().get("backlog_seconds", 0.0))})
		else:
			if not _terminal_overlays.has(_local_user_id):
				var tick_before_prediction := int(_simulation.get("tick"))
				var requested_tick := _requested_prediction_tick()
				var target_tick := _prediction_target_tick()
				var prediction_started_usec := Time.get_ticks_usec()
				_prediction_frames += 1
				if target_tick < requested_tick:
					_prediction_cap_frames += 1
				events = _simulation.advance_to_tick(target_tick, SimulationScript.MAX_CATCHUP_TICKS, [_local_user_id])
				MultiplayerDiagnostics.record_timing("guest_prediction", Time.get_ticks_usec() - prediction_started_usec, {"requested_tick": requested_tick, "target_tick": target_tick, "actual_tick": int(_simulation.get("tick"))})
				_prediction_tick_samples.append(int(_simulation.get("tick")) - tick_before_prediction)
				while _prediction_tick_samples.size() > 300:
					_prediction_tick_samples.pop_front()
		if MultiplayerService.is_room_owner():
			for event in events:
				var event_kind := str(event.get("kind", ""))
				if event_kind in ["player_died", "player_finished"]:
					var terminal_user_id := str(event.get("user_id", ""))
					_trace_match_event("terminal_transition", {"user_id": terminal_user_id, "tick": int(event.get("tick", -1)), "reason": str(event.get("reason", "")), "details": event.get("details", {}), "player": _simulation.get_player(terminal_user_id)})
					_send_reliable_player_terminal(terminal_user_id)
				elif event_kind == "match_finished":
					_status_label.text = tr("Race finished")
					_lock_finish_decision(str(event.get("reason", "elimination")), int(event.get("tick", -1)))
					_snapshot = _build_authoritative_snapshot()
					_log_terminal_snapshot("host_simulation_finished", _snapshot)
					_trace_match_event("finish_decision", {"tick": int(event.get("tick", -1)), "finish_reason": _finish_reason, "finish_revision": _finish_revision, "players": _snapshot.get("players", []), "terminal_transitions": event.get("terminal_transitions", [])})
					_dump_match_trace()
					_send_reliable_match_finished(_snapshot)
					MultiplayerService.advance_match_phase("FINISHED")
			if not bool(_snapshot.get("finished", false)):
				_snapshot = _build_authoritative_snapshot()
			_snapshot_elapsed += delta
			if _snapshot_elapsed >= SNAPSHOT_INTERVAL_SECONDS:
				_snapshot_elapsed = fmod(_snapshot_elapsed, SNAPSHOT_INTERVAL_SECONDS)
				_snapshot_sequence += 1
				_snapshot["snapshot_seq"] = _snapshot_sequence
				_snapshot["match_generation"] = _start_generation
				var snapshot_payload := {"kind": "snapshot", "state": _snapshot}
				var snapshot_started_usec := Time.get_ticks_usec()
				var send_result: Dictionary = MultiplayerService.send_peer_message_to_all("snapshot", snapshot_payload)
				MultiplayerDiagnostics.increment_total("snapshot_attempts")
				MultiplayerDiagnostics.increment_total("snapshot_sent", int(send_result.get("sent", 0)))
				MultiplayerDiagnostics.increment_total("snapshot_send_failed", int(send_result.get("failed", 0)))
				MultiplayerDiagnostics.increment_total("snapshot_send_dropped", int(send_result.get("dropped", 0)))
				MultiplayerDiagnostics.record_timing("snapshot_serialization_and_send", Time.get_ticks_usec() - snapshot_started_usec, {"sent": send_result.get("sent", 0), "bytes": send_result.get("bytes", 0), "failed": send_result.get("failed", 0), "dropped": send_result.get("dropped", 0)})
				_snapshot_send_totals.count += int(send_result.get("sent", 0))
				_snapshot_send_totals.bytes += int(send_result.get("bytes", 0))
				_snapshot_send_totals.serialized_usec += int(send_result.get("serialized_usec", 0))
				_snapshot_send_totals.failed += int(send_result.get("failed", 0))
				_snapshot_send_totals.dropped += int(send_result.get("dropped", 0))
			_snapshot_send_metrics_elapsed += delta
			if _snapshot_send_metrics_elapsed >= 5.0:
				_record_match_diag("snapshot_send_quality", {"peers_sent": _snapshot_send_totals.count, "bytes": _snapshot_send_totals.bytes, "mean_bytes_per_peer": int(_snapshot_send_totals.bytes / maxi(_snapshot_send_totals.count, 1)), "serialization_usec": _snapshot_send_totals.serialized_usec, "failed": _snapshot_send_totals.failed, "dropped_congested": _snapshot_send_totals.dropped, "simulation_backlog_ms": int(float(_snapshot.get("backlog_seconds", 0.0)) * 1000.0), "peak_simulation_backlog_ms": int(float(_snapshot.get("peak_backlog_seconds", 0.0)) * 1000.0), "host_tick": int(_snapshot.get("tick", -1))})
				_snapshot_send_totals = {"count": 0, "bytes": 0, "serialized_usec": 0, "failed": 0, "dropped": 0}
				_snapshot_send_metrics_elapsed = 0.0
			if bool(_snapshot.get("finished", false)):
				_retry_unacknowledged_finish(delta)
		else:
			_visual_correction = fade_render_correction(_visual_correction, delta, LOCAL_CORRECTION_SPEED)
			_max_correction_x_px = maxf(_max_correction_x_px, absf(_visual_correction.x))
			_max_correction_y_px = maxf(_max_correction_y_px, absf(_visual_correction.y))
			_record_local_render_sample()
			_advance_local_render_clock(delta)
			_compose_client_snapshot()
	_update_hud()
	_update_authority_health(delta)
	var previous_camera_left := _camera_left_cached
	_refresh_camera_state()
	_camera_delta_x_frame = _camera_left_cached - previous_camera_left
	_sync_player_views()
	var local_state := _player_state(_local_user_id)
	MultiplayerDiagnostics.set_metrics({"simulation_tick": int(_simulation.get("tick")), "host_tick": int(_last_authoritative_tick) if not MultiplayerService.is_room_owner() else int(_simulation.get("tick")), "snapshot_buffer_size": _snapshot_buffer.size(), "snapshot_render_tick": _snapshot_render_tick, "prediction_lead_ticks": int(_simulation.get("tick")) - _last_authoritative_tick, "camera_mode": _camera_mode, "camera_left": _camera_left_cached, "camera_delta_x": _camera_delta_x_frame, "visual_correction_x": _visual_correction.x, "visual_correction_y": _visual_correction.y, "local_player_state": local_state.get("state", "unknown"), "local_world_x": local_state.get("world_x", 0.0), "estimated_rtt_ms": _estimated_peer_rtt_msec, "snapshot_delay_ticks": _snapshot_delay_ticks, "render_mode": _current_render_mode()})
	queue_redraw()
	_frame_cost_samples.append(Time.get_ticks_usec() - frame_work_started_usec)
	while _frame_cost_samples.size() > 300:
		_frame_cost_samples.pop_front()
	MultiplayerDiagnostics.record_timing("match_process_work", Time.get_ticks_usec() - frame_work_started_usec)

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
	var previous_state: Dictionary = _simulation.get_player(_local_user_id)
	if not _simulation.submit_flip(_local_user_id, direction):
		return
	if not MultiplayerService.is_room_owner():
		_input_sequence += 1
		var target_tick := int(_simulation.get("tick")) + 1
		var sent_at_msec := Time.get_ticks_msec()
		_local_prediction.remember_input(_input_sequence, target_tick, direction, sent_at_msec)
		var input_payload := {
			"kind": "flip",
			"match_generation": _start_generation,
			"gravity_direction": direction,
			"input_sequence": _input_sequence,
			"target_host_tick": target_tick,
			"sent_at_msec": sent_at_msec,
		}
		if MultiplayerService.send_peer_message(_owner_user_id, "control", input_payload):
			_record_match_diag("flip_input_sent", {"sequence": _input_sequence, "target_host_tick": target_tick, "predicted_tick": int(_simulation.get("tick"))})
			_trace_match_event("flip_input_sent", {"sequence": _input_sequence, "target_host_tick": target_tick})
		else:
			_local_prediction.reject_input(_input_sequence)
			_simulation.apply_authoritative_player_state(_local_user_id, previous_state)
			_record_match_diag("flip_input_send_failed", {"sequence": _input_sequence, "target_host_tick": target_tick})

func _on_peer_data_received(peer_user_id: String, channel_name: String, payload: Dictionary) -> void:
	_last_peer_traffic_msec[peer_user_id] = Time.get_ticks_msec()
	if channel_name != "snapshot":
		MultiplayerDiagnostics.record_event("peer_packet_received", {"peer_id": peer_user_id, "channel": channel_name, "kind": str(payload.get("kind", ""))}, str(payload.get("kind", "")) in ["player_terminal", "match_finished", "race_start_commit"])
	if not MultiplayerService.is_room_owner() and peer_user_id != _owner_user_id:
		_record_match_diag("non_owner_authority_rejected", {"peer_id": peer_user_id, "channel": channel_name, "kind": str(payload.get("kind", ""))})
		return
	if MultiplayerService.is_room_owner() and channel_name == "control":
		var packet_kind := str(payload.get("kind", ""))
		var is_rostered_leave := packet_kind == "player_explicit_leave" and _match_roster_ids.has(peer_user_id)
		if not _is_active_room_member(peer_user_id) and not is_rostered_leave:
			return
		match packet_kind:
			"diagnostic_session":
				pass # A guest may never create or relay the host-authorized session.
			"player_explicit_leave":
				if _is_current_start_generation(payload) and _simulation.mark_disconnected(peer_user_id, "explicit_leave"):
					_trace_match_event("player_explicit_leave", {"user_id": peer_user_id, "tick": int(_simulation.get("tick"))})
					_send_reliable_player_terminal(peer_user_id)
					_snapshot = _build_authoritative_snapshot()
					MultiplayerService.send_peer_message_to_all("snapshot", {"kind": "snapshot", "state": _snapshot})
			"runner_profile":
				_simulation.set_player_profile(peer_user_id, int(payload.get("run_speed_percent", 10000)), int(payload.get("flip_cooldown_percent", 10000)))
				_received_runner_profile[peer_user_id] = true
			"match_ready":
				_received_match_ready[peer_user_id] = true
				print("[MP_DIAG] ", JSON.stringify({"event": "peer_match_ready", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "at_ms": Time.get_ticks_msec()}))
				if bool(_received_runner_profile.get(peer_user_id, false)):
					MultiplayerService.queue_reliable_peer_message(peer_user_id, {"kind": "match_setup_ack", "room_id": MultiplayerService.get_room_id()})
			"return_lobby_request":
				if str(payload.get("room_id", "")) == MultiplayerService.get_room_id() and bool(_snapshot.get("finished", false)):
					_return_requester_name = _member_display_name(peer_user_id)
					_return_notice_override = ""
					_update_return_request_notice()
			"race_go_ack":
				pass # Legacy packets from older clients are ignored; current clients use the start probe/commit protocol.
			"race_start_probe_ack":
				_accept_start_probe_ack(peer_user_id, payload)
			"race_start_commit_ack":
				if _is_current_start_generation(payload):
					_record_match_diag("race_start_commit_ack", {"peer_id": peer_user_id, "generation": _start_generation, "planned_host_start_msec": _planned_host_start_msec})
			"race_start_cancel_ack":
				pass
			"match_finished_ack":
				if str(payload.get("room_id", "")) == MultiplayerService.get_room_id() and str(payload.get("match_generation", "")) == _start_generation and int(payload.get("tick", -1)) == int(_finish_payload.get("tick", -2)) and int(payload.get("finish_revision", -1)) == int(_finish_payload.get("finish_revision", -2)):
					_finish_acknowledged_peers[peer_user_id] = true
					_record_match_diag("reliable_finish_ack", {"peer_id": peer_user_id, "tick": int(payload.get("tick", -1))})
			"flip":
				var sequence := int(payload.get("input_sequence", 0))
				if str(payload.get("match_generation", "")) != _start_generation:
					_record_match_diag("flip_input_rejected", {"peer_id": peer_user_id, "sequence": sequence, "reason": "match_generation_mismatch"})
				elif sequence > int(_last_input_sequence.get(peer_user_id, 0)):
					var queued: Dictionary = _simulation.queue_flip(peer_user_id, sequence, int(payload.get("gravity_direction", 0)), int(payload.get("target_host_tick", -1)))
					_trace_match_event("flip_input_received", {"user_id": peer_user_id, "sequence": sequence, "requested_tick": int(payload.get("target_host_tick", -1)), "effective_tick": int(queued.get("target_tick", -1)), "accepted_for_queue": bool(queued.get("queued", false))})
					_last_input_sequence[peer_user_id] = sequence
					var peer_offset := float((_start_peer_offsets.get(peer_user_id, {}) as Dictionary).get("offset_msec", 0.0))
					var input_age_msec := maxi(0, Time.get_ticks_msec() - int(payload.get("sent_at_msec", Time.get_ticks_msec())) + int(round(peer_offset)))
					_record_match_diag("flip_input_queued", {"peer_id": peer_user_id, "sequence": sequence, "requested_tick": int(payload.get("target_host_tick", -1)), "effective_tick": int(queued.get("target_tick", -1)), "queued": bool(queued.get("queued", false)), "reason": str(queued.get("reason", "")), "host_tick": int(_simulation.get("tick")), "estimated_input_one_way_ms": input_age_msec})
					if not bool(queued.get("queued", false)):
						MultiplayerService.queue_reliable_peer_message(peer_user_id, {"kind": "flip_result", "room_id": MultiplayerService.get_room_id(), "match_generation": _start_generation, "sequence": sequence, "accepted": false, "processed_tick": int(_simulation.get("tick")), "reason": str(queued.get("reason", "rejected"))})
	elif not MultiplayerService.is_room_owner():
		if channel_name == "control" and str(payload.get("kind", "")) == "match_finished":
			_accept_reliable_match_finished(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "flip_result":
			_accept_flip_result(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "player_terminal":
			_accept_reliable_player_terminal(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "match_setup_request":
			if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
				_queue_match_setup()
		elif channel_name == "control" and str(payload.get("kind", "")) == "match_setup_ack":
			if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
				_match_setup_acknowledged = true
				print("[MP_DIAG] ", JSON.stringify({"event": "match_setup_ack", "room_id": MultiplayerService.get_room_id(), "at_ms": Time.get_ticks_msec()}))
		elif channel_name == "control" and str(payload.get("kind", "")) == "race_start_probe":
			_receive_start_probe(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "race_start_commit":
			_receive_start_commit(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "race_start_cancel":
			_cancel_synchronized_start(payload)
		elif channel_name == "control" and str(payload.get("kind", "")) == "match_finished_ack":
			if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
				_record_match_diag("reliable_finish_ack", {"peer_id": peer_user_id, "tick": int(payload.get("tick", -1))})
		elif channel_name == "control" and str(payload.get("kind", "")) == "diagnostic_session":
			if MultiplayerDiagnostics.accept_shared_session(payload, peer_user_id):
				MultiplayerDiagnostics.attach_session_to_capture()
				_record_match_diag("diagnostic_session_received", {"session_id": str(payload.get("session_id", ""))})
		elif channel_name == "snapshot" and str(payload.get("kind", "")) == "snapshot":
			var new_snapshot: Variant = payload.get("state", {})
			MultiplayerDiagnostics.increment_total("snapshot_received")
			_match_snapshot_received += 1
			if new_snapshot is Dictionary:
				var received_sequence := int(new_snapshot.get("snapshot_seq", -1))
				if received_sequence >= 0:
					if _last_diagnostic_snapshot_sequence >= 0 and received_sequence <= _last_diagnostic_snapshot_sequence:
						MultiplayerDiagnostics.increment_total("snapshot_out_of_order_or_duplicate")
					elif _last_diagnostic_snapshot_sequence >= 0 and received_sequence > _last_diagnostic_snapshot_sequence + 1:
						MultiplayerDiagnostics.increment_total("snapshot_sequence_gaps", received_sequence - _last_diagnostic_snapshot_sequence - 1)
					_last_diagnostic_snapshot_sequence = maxi(_last_diagnostic_snapshot_sequence, received_sequence)
			_trace_match_event("snapshot_received", {"tick": int(new_snapshot.get("tick", -1)) if new_snapshot is Dictionary else -1})
			var previous_tick := _last_authoritative_tick
			if _accept_authoritative_snapshot(new_snapshot):
				MultiplayerDiagnostics.increment_total("snapshot_accepted")
				if previous_tick < 0:
					_record_match_diag("snapshot_stream_started", {"tick": int(new_snapshot.get("tick", -1))})
				if bool(_authoritative_snapshot.get("finished", false)):
					_log_terminal_snapshot("guest_received_finished_snapshot", _authoritative_snapshot)
				if _last_snapshot_receive_msec == 0:
					print("[MP_DIAG] ", JSON.stringify({"event": "first_snapshot_received", "room_id": MultiplayerService.get_room_id(), "tick": int(new_snapshot.get("tick", -1)), "at_ms": Time.get_ticks_msec()}))
				var now_msec := Time.get_ticks_msec()
				var interarrival_msec := now_msec - _last_snapshot_receive_msec if _last_snapshot_receive_msec > 0 else 0
				if interarrival_msec > 0:
					_snapshot_interarrival_total_msec += interarrival_msec
					_snapshot_interarrival_count += 1
					var expected_interval_msec := SNAPSHOT_INTERVAL_SECONDS * 1000.0
					var interval_error := absf(float(interarrival_msec) - expected_interval_msec)
					_snapshot_jitter_msec = lerpf(_snapshot_jitter_msec, interval_error, 0.1)
					_snapshot_mean_interval_msec = lerpf(_snapshot_mean_interval_msec, float(interarrival_msec), 0.1) if _snapshot_mean_interval_msec > 0.0 else float(interarrival_msec)
					var desired_delay_ticks := clampf(BASE_SNAPSHOT_DELAY_TICKS + ceilf(_snapshot_jitter_msec / (1000.0 / SIMULATION_TICK_RATE)), BASE_SNAPSHOT_DELAY_TICKS, 12.0)
					_snapshot_delay_ticks = move_toward(_snapshot_delay_ticks, desired_delay_ticks, 0.25)
				var tick_gap := int(new_snapshot.get("tick", -1)) - previous_tick
				var expected_interval_ticks := maxi(1, int(round(SIMULATION_TICK_RATE / SNAPSHOT_RATE)))
				if previous_tick >= 0 and tick_gap > expected_interval_ticks + 1:
					_snapshot_tick_gaps += tick_gap - expected_interval_ticks
				if _snapshot_interarrival_count >= 150:
					var latest_sample: Dictionary = _snapshot_buffer.back() if not _snapshot_buffer.is_empty() else {}
					var latest_age_msec := (Time.get_ticks_msec() - _last_snapshot_receive_msec) if _last_snapshot_receive_msec > 0 else -1
					var latest_tick := int(latest_sample.get("tick", -1))
					_record_match_diag("snapshot_quality", {"room_id": MultiplayerService.get_room_id(), "samples": _snapshot_interarrival_count, "snapshot_rate_hz": SNAPSHOT_RATE, "snapshot_delay_ticks": _snapshot_delay_ticks, "mean_interarrival_ms": _snapshot_interarrival_total_msec / _snapshot_interarrival_count, "estimated_interval_ms": _snapshot_mean_interval_msec, "jitter_ewma_ms": _snapshot_jitter_msec, "latest_age_ms": latest_age_msec, "estimated_rtt_ms": _estimated_peer_rtt_msec, "buffer_samples": _snapshot_buffer.size(), "buffer_tick_span": latest_tick - int(_snapshot_buffer.front().get("tick", latest_tick)) if not _snapshot_buffer.is_empty() else 0, "render_tick": _snapshot_render_tick, "local_render_tick": _local_render_tick(), "local_prediction_tick": int(_simulation.get("tick")), "authoritative_tick": _last_authoritative_tick, "prediction_lead_ticks": int(_simulation.get("tick")) - _last_authoritative_tick, "prediction_wallclock_capped_frames": _prediction_cap_frames, "prediction_replay_limit_snapshots": _prediction_replay_limit_frames, "prediction_frames": _prediction_frames, "prediction_ticks_p95_per_frame": percentile_int(_prediction_tick_samples, 0.95), "reconcile_p95_usec": percentile_int(_reconcile_cost_samples, 0.95), "reconcile_max_usec": _max_reconcile_usec, "frame_work_p95_usec": percentile_int(_frame_cost_samples, 0.95), "frame_work_max_usec": percentile_int(_frame_cost_samples, 1.0), "render_samples": _snapshot_render_samples, "extrapolation_frames": _snapshot_extrapolated_frames, "extrapolation_ratio": float(_snapshot_extrapolated_frames) / maxf(float(_snapshot_render_samples), 1.0), "max_local_correction_px": _max_local_correction_px, "max_correction_x_px": _max_correction_x_px, "max_correction_y_px": _max_correction_y_px, "estimated_missing_ticks": _snapshot_tick_gaps})
					_snapshot_interarrival_total_msec = 0
					_snapshot_interarrival_count = 0
					_snapshot_tick_gaps = 0
					_prediction_cap_frames = 0
					_prediction_replay_limit_frames = 0
					_prediction_frames = 0
					_prediction_tick_samples.clear()
					_reconcile_cost_samples.clear()
					_frame_cost_samples.clear()
					_max_reconcile_usec = 0
					_snapshot_extrapolated_frames = 0
					_snapshot_render_samples = 0
					_max_local_correction_px = 0.0
					_max_correction_x_px = 0.0
					_max_correction_y_px = 0.0
				_last_snapshot_receive_msec = now_msec
				if bool(_authoritative_snapshot.get("finished", false)):
					_status_label.text = tr("Race finished")
			else:
				MultiplayerDiagnostics.increment_total("snapshot_rejected")
				_match_snapshot_rejected += 1
				_record_match_diag("snapshot_rejected", {"reason": _last_snapshot_rejection, "last_tick": _last_authoritative_tick, "incoming_tick": int(new_snapshot.get("tick", -1)) if new_snapshot is Dictionary else -1, "incoming_finished": bool(new_snapshot.get("finished", false)) if new_snapshot is Dictionary else false})

func _on_peer_connection_state_changed(peer_user_id: String, state: String, message: String) -> void:
	if state == "failed":
		var player_state: Dictionary = _simulation.get_player(peer_user_id) if _simulation != null else {}
		var last_traffic := int(_last_peer_traffic_msec.get(peer_user_id, 0))
		_record_match_diag("match_peer_failed", {"peer_id": peer_user_id, "match_tick": int(_simulation.get("tick")) if _simulation != null else -1, "player_state": str(player_state.get("state", "missing")), "player_world_x": float(player_state.get("world_x", -1.0)), "last_peer_traffic_ago_ms": Time.get_ticks_msec() - last_traffic if last_traffic > 0 else -1, "message": message})
		_status_label.text = message
		if MultiplayerService.is_room_owner():
			if _simulation != null and _simulation.mark_disconnected(peer_user_id, "confirmed_disconnect"):
				_trace_match_event("terminal_transition", {"user_id": peer_user_id, "tick": int(_simulation.get("tick")), "reason": "confirmed_disconnect", "transport_reason": message, "player": _simulation.get_player(peer_user_id)})
				_send_reliable_player_terminal(peer_user_id)
				_snapshot = _build_authoritative_snapshot()
				MultiplayerService.send_peer_message_to_all("snapshot", {"kind": "snapshot", "state": _snapshot})
		elif peer_user_id == _owner_user_id:
			_result_label.text = tr("Connection to the race host was lost.")
			_result_label.visible = true

func _send_reliable_player_terminal(user_id: String) -> void:
	var player_state: Dictionary = _simulation.get_player(user_id) if _simulation != null else {}
	if player_state.is_empty():
		return
	var payload := {
		"kind": "player_terminal",
		"room_id": MultiplayerService.get_room_id(),
		"match_generation": _start_generation,
		"course_identity": str(_manifest.get("course_identity")),
		"event_tick": int(player_state.get("terminal_tick", -1)),
		"sent_host_tick": int(_simulation.get("tick")),
		"terminal_reason": str(player_state.get("terminal_reason", "")),
		"terminal_tick": int(player_state.get("terminal_tick", -1)),
		"player": player_state,
	}
	_record_match_diag("player_terminal_send", {"player_id": user_id, "state": str(player_state.get("state", "")), "event_tick": int(payload.event_tick), "sent_host_tick": int(payload.sent_host_tick), "terminal_tick": int(payload.terminal_tick), "reason": str(payload.terminal_reason)})
	for member in MultiplayerService.get_members():
		if not member is Dictionary:
			continue
		var peer_user_id := str(member.get("user_id", ""))
		if peer_user_id.is_empty() or peer_user_id == _local_user_id:
			continue
		var queued := MultiplayerService.queue_reliable_peer_message(peer_user_id, payload)
		_record_match_diag("player_terminal_queued", {"peer_id": peer_user_id, "player_id": user_id, "state": str(player_state.get("state", "")), "event_tick": int(payload.event_tick), "sent_host_tick": int(payload.sent_host_tick), "queued": queued})

func _send_reliable_match_finished(snapshot: Dictionary) -> void:
	_finish_payload = {
		"kind": "match_finished",
		"room_id": MultiplayerService.get_room_id(),
		"match_generation": _start_generation,
		"course_identity": str(snapshot.get("course_identity", "")),
		"tick": int(snapshot.get("tick", -1)),
		"finished": true,
		"finish_revision": _finish_revision,
		"finish_reason": _finish_reason,
		"finish_tick": _finish_tick,
		"players": snapshot.get("players", []),
	}
	_finish_acknowledged_peers.clear()
	_finish_retry_elapsed = 0.0
	_queue_finish_for_unacknowledged_peers()

func _build_authoritative_snapshot() -> Dictionary:
	var snapshot: Dictionary = _simulation.get_snapshot()
	snapshot["match_generation"] = _start_generation
	if bool(snapshot.get("finished", false)):
		_lock_finish_decision(str(snapshot.get("finish_reason", "elimination")), int(snapshot.get("tick", -1)))
		snapshot["finish_revision"] = _finish_revision
		snapshot["finish_reason"] = _finish_reason
		snapshot["finish_tick"] = _finish_tick
	return snapshot

func _lock_finish_decision(reason: String, decision_tick: int) -> void:
	if _finish_revision > 0:
		return
	_finish_revision = 1
	_finish_reason = reason if reason in ["finish_line", "elimination", "confirmed_disconnect"] else "elimination"
	_finish_tick = maxi(decision_tick, int(_simulation.get("tick")) if _simulation != null else 0)
	_record_match_diag("finish_decision_locked", {"finish_revision": _finish_revision, "finish_tick": _finish_tick, "finish_reason": _finish_reason, "players": _simulation.get_snapshot().get("players", []) if _simulation != null else []})

func _trace_match_event(event_name: String, details: Dictionary = {}) -> void:
	var entry := details.duplicate(true)
	entry["event"] = event_name
	entry["at_ms"] = Time.get_ticks_msec()
	entry["match_generation"] = _start_generation
	entry["tick"] = int(entry.get("tick", _simulation.get("tick") if _simulation != null else -1))
	_match_trace_ring.append(entry)
	while _match_trace_ring.size() > 240:
		_match_trace_ring.pop_front()

func _dump_match_trace() -> void:
	if _match_trace_ring.is_empty():
		return
	_record_match_diag("match_trace_dump", {"finish_tick": _finish_tick, "finish_reason": _finish_reason, "events": _match_trace_ring.duplicate(true)})

static func match_state_error(snapshot: Variant, expected_user_ids: Array, minimum_finish_revision: int = 0) -> String:
	if not snapshot is Dictionary:
		return "snapshot_not_dictionary"
	var players: Variant = snapshot.get("players", null)
	if not players is Array or players.size() != expected_user_ids.size():
		return "roster_size_mismatch"
	var expected := {}
	for user_id in expected_user_ids:
		expected[str(user_id)] = true
	var seen := {}
	var running_count := 0
	var finished_count := 0
	var disconnected_count := 0
	for player in players:
		if not player is Dictionary:
			return "player_not_dictionary"
		var user_id := str(player.get("user_id", ""))
		var state := str(player.get("state", ""))
		if not expected.has(user_id) or seen.has(user_id) or state not in ["running", "dead", "finished", "disconnected"]:
			return "unknown_duplicate_or_invalid_player:%s" % user_id
		seen[user_id] = true
		if state == "running":
			running_count += 1
		elif state == "finished":
			finished_count += 1
		elif state == "disconnected":
			disconnected_count += 1
		if state in ["dead", "finished", "disconnected"]:
			var terminal_tick := int(player.get("terminal_tick", -1))
			if str(player.get("terminal_reason", "")) not in ["hazard_hit", "out_of_bounds", "finish_line", "confirmed_disconnect", "explicit_leave"] or terminal_tick < 0 or terminal_tick > int(snapshot.get("tick", -1)):
				return "terminal_reason_or_tick_invalid:%s" % user_id
	if not bool(snapshot.get("finished", false)):
		return "" if minimum_finish_revision == 0 else "finished_state_rolled_back"
	var finish_revision := int(snapshot.get("finish_revision", 0))
	var finish_tick := int(snapshot.get("finish_tick", -1))
	var finish_reason := str(snapshot.get("finish_reason", ""))
	if running_count > 0:
		return "finished_snapshot_has_running_player"
	if finish_revision <= 0 or finish_revision < minimum_finish_revision or finish_tick != int(snapshot.get("tick", -2)):
		return "finish_revision_or_tick_invalid"
	if finish_reason not in ["finish_line", "elimination", "confirmed_disconnect"]:
		return "finish_reason_invalid"
	if finish_reason == "finish_line" and finished_count == 0:
		return "finish_line_without_finisher"
	if finish_reason == "confirmed_disconnect" and disconnected_count == 0:
		return "disconnect_finish_without_disconnect"
	if finish_reason == "elimination" and (finished_count > 0 or disconnected_count > 0):
		return "elimination_reason_conflicts_with_terminal_states"
	return ""

func _retry_unacknowledged_finish(delta: float) -> void:
	if _finish_payload.is_empty():
		return
	_finish_retry_elapsed += delta
	if _finish_retry_elapsed < 0.75:
		return
	_finish_retry_elapsed = 0.0
	_queue_finish_for_unacknowledged_peers()

func _queue_finish_for_unacknowledged_peers() -> void:
	for member in MultiplayerService.get_members():
		if not member is Dictionary:
			continue
		var peer_user_id := str(member.get("user_id", ""))
		if peer_user_id.is_empty() or peer_user_id == _local_user_id or bool(_finish_acknowledged_peers.get(peer_user_id, false)):
			continue
		var queued := MultiplayerService.queue_reliable_peer_message(peer_user_id, _finish_payload)
		_record_match_diag("match_finished_queued", {"peer_id": peer_user_id, "tick": int(_finish_payload.get("tick", -1)), "queued": queued})

func _accept_reliable_player_terminal(payload: Dictionary) -> void:
	if str(payload.get("room_id", "")) != MultiplayerService.get_room_id() or str(payload.get("match_generation", "")) != _start_generation or str(payload.get("course_identity", "")) != str(_manifest.get("course_identity")):
		_record_match_diag("player_terminal_rejected", {"reason": "room_or_course_mismatch"})
		return
	var player: Variant = payload.get("player", {})
	var event_tick := int(payload.get("event_tick", payload.get("terminal_tick", -1)))
	var sent_host_tick := int(payload.get("sent_host_tick", payload.get("tick", event_tick)))
	var terminal_error := TerminalEventRules.validation_error(payload)
	if not terminal_error.is_empty():
		_record_match_diag("player_terminal_rejected", {"reason": terminal_error, "event_tick": event_tick, "sent_host_tick": sent_host_tick, "payload_terminal_tick": int(payload.get("terminal_tick", -1)), "player_terminal_tick": int(player.get("terminal_tick", -1)) if player is Dictionary else -1, "terminal_reason": str(payload.get("terminal_reason", "")), "player_reason": str(player.get("terminal_reason", "")) if player is Dictionary else ""})
		return
	var terminal_reason := str(payload.get("terminal_reason", player.get("terminal_reason", "")))
	var user_id := str(player.get("user_id", ""))
	if not _match_roster_ids.has(user_id):
		_record_match_diag("player_terminal_rejected", {"reason": "unknown_player", "player_id": user_id})
		return
	if not _store_terminal_overlay(user_id, player, event_tick):
		return
	if user_id == _local_user_id:
		if _local_prediction != null:
			_local_prediction.clear()
			_camera_mode = CAMERA_MODE_SPECTATING
			_spectator_target_user_id = ""
	_record_match_diag("player_terminal_received", {"player_id": user_id, "state": str(player.get("state", "")), "event_tick": event_tick, "sent_host_tick": sent_host_tick, "terminal_tick": int(player.get("terminal_tick", -1)), "reason": terminal_reason, "full_snapshot_tick_unchanged": _last_authoritative_tick})

func _store_terminal_overlay(user_id: String, player: Dictionary, event_tick: int) -> bool:
	var existing: Variant = _terminal_overlays.get(user_id, {})
	if existing is Dictionary and not existing.is_empty():
		if int(existing.get("tick", -1)) >= event_tick:
			return false
		if str(existing.get("state", "")) in ["dead", "finished", "disconnected"] and str(player.get("state", "")) == "running":
			return false
	var terminal_player := player.duplicate(true)
	terminal_player["state"] = str(player.get("state", "dead"))
	_terminal_overlays[user_id] = {"tick": event_tick, "state": terminal_player.state, "player": terminal_player}
	_apply_terminal_overlays(_snapshot)
	return true

func _remember_snapshot_terminal_states(snapshot: Dictionary) -> void:
	var states: Variant = snapshot.get("players", [])
	if not states is Array:
		return
	var tick_value := int(snapshot.get("tick", -1))
	for player in states:
		if not player is Dictionary or str(player.get("state", "")) not in ["dead", "finished", "disconnected"]:
			continue
		_store_terminal_overlay(str(player.get("user_id", "")), player, int(player.get("terminal_tick", tick_value)))

func _apply_terminal_overlays(snapshot: Dictionary) -> void:
	var states: Variant = snapshot.get("players", [])
	if not states is Array or _terminal_overlays.is_empty():
		return
	var updated_states: Array[Dictionary] = []
	for player in states:
		if not player is Dictionary:
			continue
		var updated: Dictionary = player.duplicate(true)
		var overlay: Variant = _terminal_overlays.get(str(updated.get("user_id", "")), {})
		if overlay is Dictionary and not overlay.is_empty():
			var terminal_player: Dictionary = overlay.get("player", {})
			updated["state"] = str(overlay.get("state", terminal_player.get("state", "dead")))
			for key in ["world_x", "y", "gravity_direction", "grounded", "blocked", "vertical_speed"]:
				if terminal_player.has(key):
					updated[key] = terminal_player[key]
		updated_states.append(updated)
	snapshot["players"] = updated_states

func _accept_reliable_match_finished(payload: Dictionary) -> void:
	if str(payload.get("room_id", "")) != MultiplayerService.get_room_id() or str(payload.get("course_identity", "")) != str(_manifest.get("course_identity")):
		_record_match_diag("reliable_finish_rejected", {"reason": "room_or_course_mismatch"})
		return
	if str(payload.get("match_generation", "")) != _start_generation:
		_record_match_diag("reliable_finish_rejected", {"reason": "match_generation_mismatch"})
		return
	var incoming_tick := int(payload.get("tick", -1))
	var states: Variant = payload.get("players", null)
	var incoming_revision := int(payload.get("finish_revision", 0))
	if _accepted_finish_revision > 0:
		if incoming_revision == _accepted_finish_revision and incoming_tick == _accepted_finish_tick:
			var accepted_states: Array = _authoritative_snapshot.get("players", [])
			var duplicate_matches: bool = str(payload.get("finish_reason", "")) == _finish_reason and states is Array and states == accepted_states
			if not duplicate_matches:
				_record_match_diag("reliable_finish_rejected", {"reason": "duplicate_finish_identity_has_conflicting_state", "finish_revision": incoming_revision, "tick": incoming_tick})
				return
			MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "match_finished_ack", "room_id": MultiplayerService.get_room_id(), "match_generation": _start_generation, "finish_revision": incoming_revision, "tick": incoming_tick})
			return
		_record_match_diag("reliable_finish_rejected", {"reason": "conflicting_or_stale_finish_decision", "accepted_revision": _accepted_finish_revision, "incoming_revision": incoming_revision, "accepted_tick": _accepted_finish_tick, "incoming_tick": incoming_tick})
		return
	if not bool(payload.get("finished", false)) or incoming_tick < 0 or int(payload.get("finish_tick", -1)) != incoming_tick or not states is Array:
		_record_match_diag("reliable_finish_rejected", {"reason": "invalid_finish_payload", "tick": incoming_tick})
		return
	var terminal := {
		"tick": incoming_tick,
		"course_identity": str(payload.get("course_identity", "")),
		"match_generation": _start_generation,
		"finished": true,
		"finish_revision": incoming_revision,
		"finish_reason": str(payload.get("finish_reason", "")),
		"finish_tick": int(payload.get("finish_tick", -1)),
		"players": states.duplicate(true),
		"placements": [],
		"world_hazards": _authoritative_snapshot.get("world_hazards", _simulation.get_snapshot().get("world_hazards", {})),
	}
	var finish_error := match_state_error(terminal, _match_roster_ids)
	if not finish_error.is_empty() or incoming_tick < _last_authoritative_tick:
		_record_match_diag("reliable_finish_rejected", {"reason": finish_error if not finish_error.is_empty() else "finish_tick_older_than_authority", "tick": incoming_tick, "latest_tick": _last_authoritative_tick})
		return
	_remember_snapshot_terminal_states(terminal)
	_authoritative_snapshot = terminal.duplicate(true)
	_authoritative_snapshot["match_generation"] = _start_generation
	_snapshot = terminal.duplicate(true)
	if _local_prediction != null:
		_local_prediction.clear()
	_visual_correction = Vector2.ZERO
	_last_authoritative_tick = incoming_tick
	_accepted_finish_revision = incoming_revision
	_accepted_finish_tick = incoming_tick
	_finish_revision = incoming_revision
	_finish_tick = incoming_tick
	_finish_reason = str(payload.get("finish_reason", ""))
	_snapshot_buffer.clear()
	_log_terminal_snapshot("guest_received_reliable_finish", terminal)
	_trace_match_event("finish_decision_received", {"tick": incoming_tick, "finish_revision": incoming_revision, "finish_reason": _finish_reason})
	_dump_match_trace()
	MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "match_finished_ack", "room_id": MultiplayerService.get_room_id(), "match_generation": _start_generation, "finish_revision": incoming_revision, "tick": incoming_tick})

func _accept_authoritative_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		_last_snapshot_rejection = "snapshot_not_dictionary"
		return false
	if str(snapshot.get("course_identity", "")) != str(_manifest.get("course_identity")):
		_last_snapshot_rejection = "course_identity_mismatch"
		return false
	if str(snapshot.get("match_generation", "")) != _start_generation:
		_last_snapshot_rejection = "match_generation_mismatch"
		return false
	var incoming_tick := int(snapshot.get("tick", -1))
	var states: Variant = snapshot.get("players", null)
	if incoming_tick <= _last_authoritative_tick or not states is Array:
		_last_snapshot_rejection = "stale_tick_or_invalid_players"
		return false
	var state_error := match_state_error(snapshot, _match_roster_ids, _accepted_finish_revision)
	if not state_error.is_empty():
		_last_snapshot_rejection = state_error
		return false
	var seen := {}
	var local_state: Dictionary = {}
	for state in states:
		if not state is Dictionary:
			_last_snapshot_rejection = "player_not_dictionary"
			return false
		var user_id := str(state.get("user_id", ""))
		if not _match_roster_ids.has(user_id) or seen.has(user_id):
			_last_snapshot_rejection = "unknown_or_duplicate_player:%s" % user_id
			return false
		seen[user_id] = true
		if user_id == _local_user_id:
			local_state = state
	if local_state.is_empty():
		_last_snapshot_rejection = "local_player_missing"
		return false
	var old_render := _local_render_position()
	var old_prediction_tick := int(_simulation.get("tick"))
	var receive_clock := _network_clock
	var previous_anchor_clock := _last_snapshot_received_network_clock
	var previous_anchor_age := maxf(_network_clock - previous_anchor_clock, 0.0) if previous_anchor_clock >= 0.0 else -1.0
	var host_backlog := float(snapshot.get("backlog_seconds", 0.0))
	var replay_target := maxi(old_prediction_tick, estimate_prediction_target_from_anchor(incoming_tick, receive_clock, receive_clock, _estimated_peer_rtt_msec, host_backlog, MAX_PREDICTION_LEAD_TICKS))
	var local_already_terminal := _terminal_overlays.has(_local_user_id)
	var reconciliation: Dictionary = {}
	var correction := Vector2.ZERO
	if not local_already_terminal:
		var reconcile_started_usec := Time.get_ticks_usec()
		reconciliation = _local_prediction.reconcile(snapshot, replay_target)
		var reconcile_usec := Time.get_ticks_usec() - reconcile_started_usec
		_reconcile_cost_samples.append(reconcile_usec)
		while _reconcile_cost_samples.size() > 300:
			_reconcile_cost_samples.pop_front()
		_max_reconcile_usec = maxi(_max_reconcile_usec, reconcile_usec)
		if not bool(reconciliation.get("ok", false)):
			_last_snapshot_rejection = "checkpoint_or_replay_failed:%s" % str(reconciliation.get("reason", "unknown"))
			return false
		var replayed: Dictionary = reconciliation.get("new_player", {})
		var replayed_position := Vector2(float(replayed.get("world_x", 0.0)), float(replayed.get("y", 0.0)))
		var same_time_reference := same_time_prediction_reference(old_render, replayed_position, old_prediction_tick, int(reconciliation.get("replayed_to_tick", old_prediction_tick)), float(old_player_run_speed(local_state)))
		correction = correction_after_authority(same_time_reference, replayed_position, "running", str(local_state.get("state", "running")))
		_visual_correction = correction
		_reset_local_render_history(int(reconciliation.get("replayed_to_tick", incoming_tick)))
		for result in reconciliation.get("confirmed_inputs", []):
			_record_match_diag("local_input_confirmed", {"sequence": int(result.get("sequence", 0)), "accepted": bool(result.get("accepted", false)), "target_tick": int(result.get("target_tick", -1)), "processed_tick": int(result.get("processed_tick", -1)), "input_ack_delay_ms": maxi(0, Time.get_ticks_msec() - int(result.get("sent_at_msec", Time.get_ticks_msec())))})
		var replay_errors: Array = reconciliation.get("replay_errors", [])
		if bool(reconciliation.get("replay_was_bounded", false)):
			_prediction_replay_limit_frames += 1
		if not replay_errors.is_empty() or bool(reconciliation.get("replay_was_bounded", false)):
			_record_match_diag("prediction_replay_limited", {"snapshot_tick": incoming_tick, "requested_target_tick": int(reconciliation.get("target_tick", replay_target)), "replayed_to_tick": int(reconciliation.get("replayed_to_tick", -1)), "errors": replay_errors})
		_max_local_correction_px = maxf(_max_local_correction_px, _visual_correction.length())
		_max_correction_x_px = maxf(_max_correction_x_px, absf(_visual_correction.x))
		_max_correction_y_px = maxf(_max_correction_y_px, absf(_visual_correction.y))
		if _network_clock - _go_start_at <= 3.0 or absf(correction.x) >= 8.0 or absf(correction.y) >= 8.0:
			_trace_match_event("snapshot_reconcile_clock", {"incoming_tick": incoming_tick, "previous_authoritative_tick": _last_authoritative_tick, "previous_anchor_clock": previous_anchor_clock, "previous_anchor_age_seconds": previous_anchor_age, "receive_clock": receive_clock, "snapshot_age_at_receive_seconds": 0.0, "host_backlog_seconds": host_backlog, "estimated_rtt_ms": _estimated_peer_rtt_msec, "old_prediction_tick": old_prediction_tick, "replay_target_tick": replay_target, "replayed_to_tick": int(reconciliation.get("replayed_to_tick", old_prediction_tick)), "comparison_tick": int(reconciliation.get("replayed_to_tick", old_prediction_tick)), "old_render": old_render, "same_time_reference": same_time_reference, "replayed_position": replayed_position, "correction_x": correction.x, "correction_y": correction.y, "pending_inputs": _local_prediction.pending_inputs()})
	_remember_snapshot_terminal_states(snapshot)
	if bool(snapshot.get("finished", false)):
		_accepted_finish_revision = int(snapshot.get("finish_revision", 0))
		_accepted_finish_tick = int(snapshot.get("finish_tick", -1))
		_finish_revision = _accepted_finish_revision
		_finish_tick = _accepted_finish_tick
		_finish_reason = str(snapshot.get("finish_reason", ""))
		_trace_match_event("finish_decision_received", {"tick": _finish_tick, "finish_revision": _finish_revision, "finish_reason": _finish_reason})
		_dump_match_trace()
	# Publish the new authority/timing anchor only after restore and replay succeeded.
	_last_authoritative_tick = incoming_tick
	_authoritative_snapshot = snapshot.duplicate(true)
	_last_snapshot_rejection = ""
	_last_snapshot_received_network_clock = receive_clock
	_authority_stall_elapsed = 0.0
	_authority_stall_reported = false
	_snapshot_buffer.append({"tick": incoming_tick, "received_at": _network_clock, "state": _authoritative_snapshot})
	while _snapshot_buffer.size() > 32:
		_snapshot_buffer.pop_front()
	return true

func _accept_flip_result(payload: Dictionary) -> void:
	if str(payload.get("room_id", "")) != MultiplayerService.get_room_id() or str(payload.get("match_generation", "")) != _start_generation:
		return
	var sequence := int(payload.get("sequence", 0))
	if sequence <= 0:
		return
	if _terminal_overlays.has(_local_user_id):
		return
	if bool(payload.get("accepted", false)):
		return # Accepted commands are retired only by a checkpoint containing their applied tick.
	if _local_prediction == null or not _local_prediction.reject_input(sequence):
		return
	_record_match_diag("local_input_confirmed", {"sequence": sequence, "accepted": false, "processed_tick": int(payload.get("processed_tick", -1)), "reason": str(payload.get("reason", ""))})
	if _authoritative_snapshot.is_empty():
		return
	var old_render := _local_render_position()
	var reconciliation: Dictionary = _local_prediction.reconcile(_authoritative_snapshot, maxi(int(_simulation.get("tick")), _prediction_target_tick()))
	if bool(reconciliation.get("ok", false)):
		var replayed: Dictionary = reconciliation.get("new_player", {})
		var authority_player := _player_state(_local_user_id)
		_visual_correction = correction_after_authority(old_render, Vector2(float(replayed.get("world_x", 0.0)), float(replayed.get("y", 0.0))), "running", str(authority_player.get("state", "running")))

func _prediction_target_tick() -> int:
	if _planned_local_start_msec <= 0:
		return maxi(_last_authoritative_tick, 0)
	if _last_authoritative_tick < 0:
		return mini(_requested_prediction_tick(), MAX_PREDICTION_LEAD_TICKS)
	var host_backlog := float(_authoritative_snapshot.get("backlog_seconds", 0.0))
	return estimate_prediction_target_from_anchor(
		_last_authoritative_tick,
		_last_snapshot_received_network_clock,
		_network_clock,
		_estimated_peer_rtt_msec,
		host_backlog,
		MAX_PREDICTION_LEAD_TICKS
	)

static func estimate_prediction_target_from_anchor(authoritative_tick: int, received_at_network_clock: float, now_network_clock: float, estimated_rtt_msec: float, host_backlog_seconds: float, max_lead_ticks: int = 24) -> int:
	var snapshot_age := maxf(now_network_clock - received_at_network_clock, 0.0) if received_at_network_clock >= 0.0 else 0.0
	return estimate_prediction_target_tick(authoritative_tick, snapshot_age, estimated_rtt_msec, host_backlog_seconds, max_lead_ticks)

static func same_time_prediction_reference(old_render: Vector2, replayed_position: Vector2, old_tick: int, replayed_tick: int, run_speed: float) -> Vector2:
	if replayed_tick <= old_tick:
		return old_render
	var elapsed_ticks := replayed_tick - old_tick
	# Horizontal runner speed is constant during the local race simulation. Use
	# that deterministic advance to avoid treating elapsed race time as error.
	# Vertical motion may contain gravity/contact events, so compare Y at the
	# replayed phase rather than turning that unknown interval into a correction.
	return Vector2(old_render.x + maxf(run_speed, 0.0) * float(elapsed_ticks) / SIMULATION_TICK_RATE, replayed_position.y)

static func old_player_run_speed(player_state: Dictionary) -> float:
	return SimulationScript.RUN_SPEED * float(player_state.get("run_speed_percent", 10000)) / 10000.0

static func estimate_prediction_target_tick(authoritative_tick: int, snapshot_age_seconds: float, estimated_rtt_msec: float, host_backlog_seconds: float, max_lead_ticks: int = 24) -> int:
	if authoritative_tick < 0:
		return 0
	var age_ticks := maxf(snapshot_age_seconds, 0.0) * SIMULATION_TICK_RATE
	var one_way_ticks := maxf(estimated_rtt_msec, 0.0) * SIMULATION_TICK_RATE / 2000.0
	# Snapshot tick counts simulation steps already completed at send time.
	# backlog_seconds is elapsed-but-unsimulated host time, so subtract it once
	# from wall-clock age + estimated one-way transit when estimating host-now.
	var backlog_ticks := maxf(host_backlog_seconds, 0.0) * SIMULATION_TICK_RATE
	var estimated_host_tick := float(authoritative_tick) + age_ticks + one_way_ticks - backlog_ticks
	var desired_tick := maxi(authoritative_tick, int(floor(estimated_host_tick + 2.0)))
	return mini(desired_tick, authoritative_tick + maxi(max_lead_ticks, 0))

func _requested_prediction_tick() -> int:
	if _planned_local_start_msec <= 0:
		return maxi(_last_authoritative_tick, 0)
	var elapsed_msec := maxi(Time.get_ticks_msec() - _planned_local_start_msec, 0)
	return maxi(int(floor(float(elapsed_msec) * SIMULATION_TICK_RATE / 1000.0)) + 2, 0)

static func percentile_int(samples: Array, fraction: float) -> int:
	if samples.is_empty():
		return 0
	var ordered: Array = samples.duplicate()
	ordered.sort()
	var index := clampi(int(ceil(clampf(fraction, 0.0, 1.0) * ordered.size())) - 1, 0, ordered.size() - 1)
	return int(ordered[index])

static func effective_player_state(render_state: String, authoritative_state: String, allow_local_prediction_mask: bool = false) -> String:
	const TERMINAL_STATES := ["dead", "finished", "disconnected"]
	if authoritative_state in TERMINAL_STATES:
		return authoritative_state
	if allow_local_prediction_mask and render_state in TERMINAL_STATES and authoritative_state in ["", "running"]:
		return "running"
	return authoritative_state if not authoritative_state.is_empty() else render_state

static func choose_spectator_target(players: Array, current_target: String = "") -> String:
	for player in players:
		if player is Dictionary and str(player.get("user_id", "")) == current_target and str(player.get("state", "")) == "running":
			return current_target
	var candidates: Array[Dictionary] = []
	for player in players:
		if player is Dictionary and str(player.get("state", "")) == "running":
			candidates.append(player)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ax := float(a.get("world_x", 0.0))
		var bx := float(b.get("world_x", 0.0))
		return ax > bx if not is_equal_approx(ax, bx) else str(a.get("user_id", "")) < str(b.get("user_id", ""))
	)
	return str(candidates[0].get("user_id", "")) if not candidates.is_empty() else ""

func _log_terminal_snapshot(reason: String, snapshot: Dictionary) -> void:
	var player_summary: Array[Dictionary] = []
	var states: Variant = snapshot.get("players", [])
	if states is Array:
		for player in states:
			if player is Dictionary:
				player_summary.append({"user_id": str(player.get("user_id", "")), "display_name": str(player.get("display_name", "")), "state": str(player.get("state", "")), "world_x": float(player.get("world_x", 0.0))})
	_record_match_diag("match_terminal_snapshot", {"reason": reason, "tick": int(snapshot.get("tick", -1)), "finished": bool(snapshot.get("finished", false)), "players": player_summary})

func _compose_client_snapshot() -> void:
	if _authoritative_snapshot.is_empty():
		_snapshot = _simulation.get_snapshot()
		return
	if _snapshot_buffer.is_empty():
		_snapshot = _authoritative_snapshot.duplicate(true)
		return
	var latest: Dictionary = _snapshot_buffer.back()
	var latest_tick := float(latest.get("tick", 0))
	var render_target := render_target_tick(latest_tick, _network_clock - float(latest.get("received_at", _network_clock)), _snapshot_delay_ticks, _snapshot_render_tick, 0.0)
	_snapshot_render_tick = render_target
	_snapshot_render_samples += 1
	if render_target > latest_tick:
		_snapshot_extrapolated_frames += 1
	var earlier: Dictionary = _snapshot_buffer.front()
	var later: Dictionary = latest
	for sample in _snapshot_buffer:
		var sample_tick := float(sample.get("tick", 0))
		if sample_tick <= render_target:
			earlier = sample
		if sample_tick >= render_target:
			later = sample
			break
	if render_target > latest_tick and _snapshot_buffer.size() >= 2:
		earlier = _snapshot_buffer[_snapshot_buffer.size() - 2]
		later = latest
	var earlier_state: Dictionary = earlier.state
	var later_state: Dictionary = later.state
	var span_ticks := float(later.get("tick", 0)) - float(earlier.get("tick", 0))
	var weight := clampf((render_target - float(earlier.get("tick", 0))) / span_ticks, 0.0, 1.0) if span_ticks > 0.0 else 1.0
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
				var authoritative_local := _authoritative_player_state(user_id)
				var effective_state := effective_player_state(str(local.get("state", "running")), str(authoritative_local.get("state", "")), true)
				local["state"] = effective_state
				if effective_state == "running":
					local["blocked"] = bool(authoritative_local.get("blocked", local.get("blocked", false)))
				displayed.append(local)
			continue
		var from: Dictionary = earlier_players.get(user_id, {})
		var to: Dictionary = later_players.get(user_id, from)
		if from.is_empty():
			from = to
		if to.is_empty():
			continue
		displayed.append(interpolate_player_sample(from, to, weight))
	_snapshot = _authoritative_snapshot.duplicate(true)
	# Results must use the exact same terminal state on every client. Never
	# freeze a delayed/interpolated sample while displaying the final standings.
	if bool(_authoritative_snapshot.get("finished", false)):
		return
	_snapshot.players = displayed
	_apply_terminal_overlays(_snapshot)
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

func _update_authority_health(delta: float) -> void:
	if MultiplayerService.is_room_owner() or not _simulation.started or _authoritative_match_finished():
		_authority_stall_elapsed = 0.0
		return
	if _last_authoritative_tick >= 0 and _network_clock - _last_snapshot_received_network_clock < 2.0:
		_authority_stall_elapsed = 0.0
		return
	_authority_stall_elapsed += delta
	if _authority_stall_elapsed < 2.0 or _authority_stall_reported:
		return
	_authority_stall_reported = true
	_record_match_diag("snapshot_authority_stalled", {"elapsed_ms": int(_authority_stall_elapsed * 1000.0), "received": _match_snapshot_received, "accepted": _match_snapshot_received - _match_snapshot_rejected, "rejected": _match_snapshot_rejected, "last_rejection": _last_snapshot_rejection, "last_authoritative_tick": _last_authoritative_tick})
	var local_state := _player_state(_local_user_id)
	if str(local_state.get("state", "")) == "running" and not bool(local_state.get("blocked", false)):
		_status_label.text = tr("Host sync is unavailable. Your race may be out of sync.")

func _current_render_mode() -> String:
	if not _simulation.started:
		return "startup_seed"
	if _authoritative_match_finished():
		return "terminal"
	if MultiplayerService.is_room_owner():
		return "host_authority"
	if _authoritative_snapshot.is_empty():
		return "degraded_no_authority"
	if _camera_mode == CAMERA_MODE_SPECTATING:
		return "terminal_spectating"
	return "local_prediction_remote_interpolation"

static func interpolated_player_state(from_state: String, to_state: String, weight: float) -> String:
	# Position is smoothed, but elimination/finish is an authoritative event,
	# not a visual value to delay. Keep terminal state monotonic if snapshots
	# briefly arrive out of order or the interpolation buffer spans the event.
	const TERMINAL_STATES := ["dead", "finished", "disconnected"]
	if to_state in TERMINAL_STATES:
		return to_state
	if from_state in TERMINAL_STATES:
		return from_state
	return from_state if weight < 1.0 else to_state

static func interpolate_player_sample(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var interpolated := to.duplicate(true)
	interpolated.world_x = lerpf(float(from.get("world_x", to.get("world_x", 0.0))), float(to.get("world_x", 0.0)), weight)
	interpolated.y = lerpf(float(from.get("y", to.get("y", 0.0))), float(to.get("y", 0.0)), weight)
	interpolated.vertical_speed = lerpf(float(from.get("vertical_speed", to.get("vertical_speed", 0.0))), float(to.get("vertical_speed", 0.0)), weight)
	interpolated.state = interpolated_player_state(str(from.get("state", "running")), str(to.get("state", "running")), weight)
	interpolated.gravity_direction = int(from.get("gravity_direction", to.get("gravity_direction", 1))) if weight < 1.0 else int(to.get("gravity_direction", 1))
	interpolated.grounded = bool(from.get("grounded", to.get("grounded", false))) if weight < 1.0 else bool(to.get("grounded", false))
	interpolated.blocked = bool(from.get("blocked", to.get("blocked", false))) if weight < 1.0 else bool(to.get("blocked", false))
	return interpolated

static func may_show_results(is_owner: bool, authoritative_snapshot: Dictionary, owner_simulation_finished: bool = false) -> bool:
	return owner_simulation_finished or bool(authoritative_snapshot.get("finished", false))

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
	if not _start_generation.is_empty():
		return
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
	_start_generation = "%s:%d" % [MultiplayerService.get_room_id(), Time.get_ticks_msec()]
	MultiplayerDiagnostics.set_match_generation(_start_generation)
	_start_probe_sent_at.clear()
	_start_peer_offsets.clear()
	_start_probe_retry_count = 0
	_start_probe_retry_elapsed = 0.0
	_record_match_diag("race_start_handshake_started", {"generation": _start_generation, "peers": present_members.size() - 1})
	for member in present_members:
		var peer_id := str(member.get("user_id", ""))
		if peer_id != _local_user_id and not _queue_start_probe(peer_id):
			_status_label.text = tr("Could not synchronize the start with every player. Check connections and retry.")
			_start_generation = ""
			_start_probe_sent_at.clear()
			_start_peer_offsets.clear()
			return
	if _start_probe_sent_at.is_empty():
		_commit_synchronized_start()
	else:
		_status_label.text = tr("Synchronizing the start with every player…")

func _queue_start_probe(peer_id: String) -> bool:
	var sent_at_msec := Time.get_ticks_msec()
	var probe_id := "%s:%d:%d" % [_start_generation, peer_id.hash(), sent_at_msec]
	var queued := MultiplayerService.queue_reliable_peer_message(peer_id, {
		"kind": "race_start_probe",
		"room_id": MultiplayerService.get_room_id(),
		"generation": _start_generation,
		"probe_id": probe_id,
		"host_sent_msec": sent_at_msec,
	})
	if queued:
		_start_probe_sent_at[peer_id] = {"probe_id": probe_id, "sent_at_msec": sent_at_msec}
		_record_match_diag("race_start_probe_queued", {"peer_id": peer_id, "generation": _start_generation, "probe_id": probe_id})
	return queued

func _receive_start_probe(payload: Dictionary) -> void:
	if MultiplayerService.is_room_owner() or str(payload.get("room_id", "")) != MultiplayerService.get_room_id():
		return
	var generation := str(payload.get("generation", ""))
	var probe_id := str(payload.get("probe_id", ""))
	if generation.is_empty() or probe_id.is_empty():
		return
	_start_generation = generation
	MultiplayerDiagnostics.set_match_generation(_start_generation)
	var guest_received_msec := Time.get_ticks_msec()
	var queued := MultiplayerService.queue_reliable_peer_message(_owner_user_id, {
		"kind": "race_start_probe_ack",
		"room_id": MultiplayerService.get_room_id(),
		"generation": generation,
		"probe_id": probe_id,
		"guest_received_msec": guest_received_msec,
	})
	_record_match_diag("race_start_probe_received", {"generation": generation, "probe_id": probe_id, "guest_received_msec": guest_received_msec, "ack_queued": queued})

func _accept_start_probe_ack(peer_user_id: String, payload: Dictionary) -> void:
	if not _is_current_start_generation(payload) or not _start_probe_sent_at.has(peer_user_id) or _start_peer_offsets.has(peer_user_id):
		return
	var probe: Dictionary = _start_probe_sent_at[peer_user_id]
	if str(payload.get("probe_id", "")) != str(probe.get("probe_id", "")):
		return
	var received_at_msec := Time.get_ticks_msec()
	var rtt_msec := maxi(0, received_at_msec - int(probe.get("sent_at_msec", received_at_msec)))
	var guest_clock_offset_msec := estimate_guest_clock_offset_ms(int(payload.get("guest_received_msec", 0)), int(probe.get("sent_at_msec", received_at_msec)), received_at_msec)
	_start_peer_offsets[peer_user_id] = {"offset_msec": guest_clock_offset_msec, "rtt_msec": rtt_msec}
	_record_match_diag("race_start_probe_ack", {"peer_id": peer_user_id, "generation": _start_generation, "rtt_ms": rtt_msec, "guest_clock_offset_ms": guest_clock_offset_msec, "probes_received": _start_peer_offsets.size(), "probes_expected": _start_probe_sent_at.size()})
	if _start_peer_offsets.size() >= _start_probe_sent_at.size():
		_commit_synchronized_start()

func _is_current_start_generation(payload: Dictionary) -> bool:
	return str(payload.get("room_id", "")) == MultiplayerService.get_room_id() and str(payload.get("generation", "")) == _start_generation and not _start_generation.is_empty()

func _commit_synchronized_start() -> void:
	if _start_committed or _start_generation.is_empty():
		return
	_start_committed = true
	_planned_host_start_msec = Time.get_ticks_msec() + 2500
	_planned_local_start_msec = _planned_host_start_msec
	_go_start_at = _network_clock + 2.5
	var committed_peers: Array[String] = []
	for peer_id in _start_probe_sent_at:
		var offset := float((_start_peer_offsets.get(peer_id, {}) as Dictionary).get("offset_msec", 0.0))
		var peer_rtt := int((_start_peer_offsets.get(peer_id, {}) as Dictionary).get("rtt_msec", 0))
		var local_target_msec := _planned_host_start_msec + int(round(offset))
		var queued := MultiplayerService.queue_reliable_peer_message(str(peer_id), {
			"kind": "race_start_commit",
			"room_id": MultiplayerService.get_room_id(),
			"generation": _start_generation,
			"host_start_msec": _planned_host_start_msec,
			"local_start_msec": local_target_msec,
			"estimated_rtt_msec": peer_rtt,
			"start_tick": 0,
		})
		if not queued:
			for committed_peer_id in committed_peers:
				MultiplayerService.queue_reliable_peer_message(committed_peer_id, {"kind": "race_start_cancel", "room_id": MultiplayerService.get_room_id(), "generation": _start_generation})
			_start_committed = false
			_go_start_at = 0.0
			_start_generation = ""
			_start_probe_sent_at.clear()
			_start_peer_offsets.clear()
			_status_label.text = tr("Could not queue the synchronized start for every player. Check connections and retry.")
			return
		committed_peers.append(str(peer_id))
	_record_match_diag("race_start_committed", {"generation": _start_generation, "planned_host_start_msec": _planned_host_start_msec, "start_tick": 0, "peers": _start_probe_sent_at.size()})
	_status_label.text = tr("RUN in 3…")

func _receive_start_commit(payload: Dictionary) -> void:
	if MultiplayerService.is_room_owner() or not _is_current_start_generation(payload):
		return
	_planned_host_start_msec = int(payload.get("host_start_msec", -1))
	_planned_local_start_msec = int(payload.get("local_start_msec", -1))
	_estimated_peer_rtt_msec = clampf(float(payload.get("estimated_rtt_msec", 0)), 0.0, 3000.0)
	if _planned_host_start_msec <= 0 or _planned_local_start_msec <= 0 or int(payload.get("start_tick", -1)) != 0:
		_record_match_diag("race_start_commit_rejected", {"generation": _start_generation, "host_start_msec": _planned_host_start_msec, "local_start_msec": _planned_local_start_msec})
		return
	_go_start_at = _network_clock + maxf(float(_planned_local_start_msec - Time.get_ticks_msec()) / 1000.0, 0.0)
	_start_committed = true
	if _local_prediction != null:
		_local_prediction.clear()
	_visual_correction = Vector2.ZERO
	_seed_start_render_snapshot()
	MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "race_start_commit_ack", "room_id": MultiplayerService.get_room_id(), "generation": _start_generation, "start_tick": 0})
	_record_match_diag("race_start_commit_received", {"generation": _start_generation, "planned_host_start_msec": _planned_host_start_msec, "planned_local_start_msec": _planned_local_start_msec, "remaining_ms": int(maxf(_go_start_at - _network_clock, 0.0) * 1000.0), "start_tick": 0})
	_status_label.text = tr("RUN in %d…") % ceili(maxf(_go_start_at - _network_clock, 0.0))

func _seed_start_render_snapshot() -> void:
	if not _snapshot_buffer.is_empty() or int(_simulation.get("tick")) != 0:
		return
	var initial_state: Dictionary = _simulation.get_snapshot()
	initial_state["match_generation"] = _start_generation
	_snapshot_buffer.append({"tick": 0, "received_at": _network_clock, "state": initial_state})
	_record_match_diag("render_buffer_seeded", {"tick": 0, "roster_size": _match_roster_ids.size()})

func _cancel_synchronized_start(payload: Dictionary) -> void:
	if MultiplayerService.is_room_owner() or not _is_current_start_generation(payload) or _simulation.started:
		return
	_record_match_diag("race_start_cancelled", {"generation": _start_generation})
	_start_generation = ""
	_start_committed = false
	_planned_host_start_msec = -1
	_planned_local_start_msec = -1
	_go_start_at = 0.0
	_status_label.text = tr("Waiting for the host to synchronize the start…")
	MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "race_start_cancel_ack", "room_id": MultiplayerService.get_room_id(), "generation": str(payload.get("generation", ""))})

func _retry_start_probes(delta: float) -> void:
	if _start_generation.is_empty() or _start_committed or not MultiplayerService.is_room_owner():
		return
	_start_probe_retry_elapsed += delta
	if _start_probe_retry_elapsed < 0.75:
		return
	_start_probe_retry_elapsed = 0.0
	var missing: Array[String] = []
	for peer_id in _start_probe_sent_at:
		if not _start_peer_offsets.has(peer_id):
			missing.append(str(peer_id))
	if missing.is_empty():
		return
	if _start_probe_retry_count >= 6:
		_status_label.text = tr("A player did not acknowledge the synchronized start. Check the connection and retry.")
		_record_match_diag("race_start_probe_timeout", {"generation": _start_generation, "missing_peers": missing})
		_start_generation = ""
		_start_probe_sent_at.clear()
		_start_peer_offsets.clear()
		return
	_start_probe_retry_count += 1
	for peer_id in missing:
		_queue_start_probe(peer_id)
	_record_match_diag("race_start_probe_retry", {"generation": _start_generation, "missing_peers": missing, "retry": _start_probe_retry_count})

static func estimate_guest_clock_offset_ms(guest_received_msec: int, host_sent_msec: int, host_received_msec: int) -> float:
	return float(guest_received_msec) - (float(host_sent_msec) + float(host_received_msec)) * 0.5

static func render_target_tick(latest_tick: float, elapsed_since_latest: float, delay_ticks: float, last_render_tick: float, extrapolation_limit_ticks: float = SNAPSHOT_EXTRAPOLATION_LIMIT_TICKS) -> float:
	var estimated_host_tick := latest_tick + maxf(elapsed_since_latest, 0.0) * SIMULATION_TICK_RATE
	var target := estimated_host_tick - maxf(delay_ticks, 0.0)
	if last_render_tick >= 0.0:
		target = maxf(target, last_render_tick)
	return minf(target, latest_tick + maxf(extrapolation_limit_ticks, 0.0))

static func correction_after_authority(rendered_position: Vector2, authoritative_position: Vector2, previous_state: String = "running", authoritative_state: String = "running") -> Vector2:
	const TERMINAL_STATES := ["dead", "finished", "disconnected"]
	var correction := rendered_position - authoritative_position
	if authoritative_state in TERMINAL_STATES:
		return Vector2.ZERO
	return correction.clamp(Vector2(-1000.0, -1000.0), Vector2(1000.0, 1000.0))

static func fade_render_correction(correction: Vector2, delta: float, speed: float) -> Vector2:
	var axis_step := maxf(delta, 0.0) * maxf(speed, 0.0)
	return Vector2(move_toward(correction.x, 0.0, axis_step), move_toward(correction.y, 0.0, axis_step))

static func interpolate_local_render_position(samples: Array, render_tick: float) -> Vector2:
	if samples.is_empty():
		return Vector2.ZERO
	var valid_samples: Array[Dictionary] = []
	for sample in samples:
		if sample is Dictionary:
			valid_samples.append(sample)
	if valid_samples.is_empty():
		return Vector2.ZERO
	var first: Dictionary = valid_samples.front()
	var last: Dictionary = valid_samples.back()
	if render_tick <= float(first.get("tick", 0)):
		return first.get("position", Vector2.ZERO)
	if render_tick >= float(last.get("tick", 0)):
		return last.get("position", Vector2.ZERO)
	var earlier: Dictionary = first
	var later: Dictionary = last
	for index in range(1, valid_samples.size()):
		var candidate: Dictionary = valid_samples[index]
		if float(candidate.get("tick", 0)) >= render_tick:
			earlier = valid_samples[index - 1]
			later = candidate
			break
	var from_position: Vector2 = earlier.get("position", Vector2.ZERO)
	var to_position: Vector2 = later.get("position", from_position)
	var from_tick := float(earlier.get("tick", render_tick))
	var to_tick := float(later.get("tick", from_tick))
	var weight := clampf((render_tick - from_tick) / (to_tick - from_tick), 0.0, 1.0) if to_tick > from_tick else 1.0
	return from_position.lerp(to_position, weight)

func _reset_local_render_history(at_tick: int) -> void:
	_local_render_history.clear()
	_local_render_clock_tick = maxf(float(at_tick) - 0.5, 0.0)
	var player: Dictionary = _simulation.get_player(_local_user_id) if _simulation != null else {}
	if player.is_empty():
		return
	_local_render_history.append({"tick": at_tick, "position": Vector2(float(player.get("world_x", 0.0)), float(player.get("y", 0.0)))})

func _record_local_render_sample() -> void:
	if _simulation == null:
		return
	var at_tick := int(_simulation.get("tick"))
	if not _local_render_history.is_empty() and int(_local_render_history.back().get("tick", -1)) == at_tick:
		return
	var player: Dictionary = _simulation.get_player(_local_user_id)
	if player.is_empty():
		return
	_local_render_history.append({"tick": at_tick, "position": Vector2(float(player.get("world_x", 0.0)), float(player.get("y", 0.0)))})
	while _local_render_history.size() > 8:
		_local_render_history.pop_front()

func _local_render_tick() -> float:
	return _local_render_clock_tick

func _advance_local_render_clock(delta: float) -> void:
	if _simulation == null or _local_render_history.is_empty():
		return
	var history_start_tick := float(_local_render_history.front().get("tick", 0))
	var latest_simulation_tick := float(_simulation.get("tick"))
	_local_render_clock_tick = clampf(_local_render_clock_tick + maxf(delta, 0.0) * SIMULATION_TICK_RATE, history_start_tick, latest_simulation_tick)

static func estimate_shared_start_msec(host_now_msec: int, safety_margin_seconds: float, peer_round_trip_msec: Array) -> float:
	var average_one_way_msec := 0.0
	for rtt in peer_round_trip_msec:
		average_one_way_msec += float(rtt) * 0.5
	if not peer_round_trip_msec.is_empty():
		average_one_way_msec /= float(peer_round_trip_msec.size())
	return float(host_now_msec) + maxf(safety_margin_seconds, 0.0) * 1000.0 + average_one_way_msec

static func stable_visual_offset(user_id: String, user_ids: Array, spacing: float = VISUAL_PLAYER_SLOT_SPACING) -> float:
	var stable_ids: Array[String] = []
	for value in user_ids:
		stable_ids.append(str(value))
	stable_ids.sort()
	var index := stable_ids.find(user_id)
	if index < 0 or stable_ids.size() < 2:
		return 0.0
	return (float(index) - float(stable_ids.size() - 1) * 0.5) * spacing

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

func _member_display_name(user_id: String) -> String:
	for member in MultiplayerService.get_members():
		if member is Dictionary and str(member.get("user_id", "")) == user_id:
			return str(member.get("display_name", tr("Runner")))
	return tr("A player")

func _player_state(user_id: String) -> Dictionary:
	var players: Variant = _snapshot.get("players", [])
	if players is Array:
		for state in players:
			if state is Dictionary and str(state.get("user_id", "")) == user_id:
				var result: Dictionary = state.duplicate(true)
				var authoritative := _authoritative_player_state(user_id)
				result["state"] = effective_player_state(str(result.get("state", "")), str(authoritative.get("state", "")), user_id == _local_user_id and not MultiplayerService.is_room_owner())
				return result
	return _authoritative_player_state(user_id)

func _authoritative_player_state(user_id: String) -> Dictionary:
	if MultiplayerService.is_room_owner():
		return _simulation.get_player(user_id) if _simulation != null else {}
	var overlay: Variant = _terminal_overlays.get(user_id, {})
	if overlay is Dictionary and not overlay.is_empty():
		return (overlay.get("player", {}) as Dictionary).duplicate(true)
	var players: Variant = _authoritative_snapshot.get("players", [])
	if players is Array:
		for player in players:
			if player is Dictionary and str(player.get("user_id", "")) == user_id:
				return player.duplicate(true)
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
		if user_id == _local_user_id and not MultiplayerService.is_room_owner():
			view.position = _local_render_position() + Vector2(float(_visual_slot_by_user.get(user_id, 0.0)), 0.0)
		else:
			view.position = _visual_player_position(state, states)
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
	_bring_local_runner_to_front()
	if _simulation != null and not _snapshot.is_empty():
		var ordered: Array[Dictionary] = []
		var sample_players: Array[Dictionary] = []
		for state in states:
			if not state is Dictionary:
				continue
			var user_id := str(state.get("user_id", ""))
			var view: Node2D = _player_views.get(user_id)
			var final_position := view.position if is_instance_valid(view) else _visual_player_position(state, states)
			ordered.append({"user_id": user_id, "world_x": final_position.x, "state": str(state.get("state", "unknown"))})
			var sprite := view.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D if is_instance_valid(view) else null
			sample_players.append({"user_id": user_id, "simulated": Vector2(float(state.get("world_x", 0.0)), float(state.get("y", 0.0))), "rendered_local": final_position, "screen_position": final_position - Vector2(camera_left, 0.0), "visual_offset_x": float(_visual_slot_by_user.get(user_id, 0.0)), "gravity_direction": int(state.get("gravity_direction", 1)), "state": str(state.get("state", "unknown")), "z_index": view.z_index if is_instance_valid(view) else 0, "sibling_index": view.get_index() if is_instance_valid(view) else -1, "visible": view.visible if is_instance_valid(view) else false, "flip_v": sprite.flip_v if sprite != null else false})
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a.world_x), float(b.world_x)):
				return float(a.world_x) < float(b.world_x)
			return str(a.user_id) < str(b.user_id)
		)
		var order: Array[String] = []
		for item in ordered:
			order.append(str(item.user_id))
		if not _last_diagnostic_visual_order.is_empty() and order != _last_diagnostic_visual_order:
			MultiplayerDiagnostics.record_event("visual_order_changed", {"before": _last_diagnostic_visual_order, "after": order, "positions": ordered}, true)
		_last_diagnostic_visual_order = order
		MultiplayerDiagnostics.record_start_sample({"camera_left": camera_left, "snapshot_render_tick": _snapshot_render_tick, "authority_tick": _last_authoritative_tick, "simulation_tick": int(_simulation.get("tick")), "visual_correction": _visual_correction, "players": sample_players})

func _visual_player_position(state: Dictionary, states: Array) -> Vector2:
	var world_position := Vector2(float(state.get("world_x", 0.0)), float(state.get("y", 0.0)))
	var user_id := str(state.get("user_id", ""))
	var offset := float(_visual_slot_by_user.get(user_id, 0.0))
	if not _visual_slot_by_user.has(user_id):
		var user_ids: Array[String] = []
		for other in states:
			if other is Dictionary:
				user_ids.append(str(other.get("user_id", "")))
		offset = stable_visual_offset(user_id, user_ids)
	return world_position + Vector2(offset, 0.0)

func _bring_local_runner_to_front() -> void:
	# Player order in a snapshot is shared by every peer. Keep the local runner
	# above the other runners in this client's draw order, regardless of who is
	# host or which user ID sorts last.
	var local_view: Variant = _player_views.get(_local_user_id)
	if _course_root != null and is_instance_valid(local_view) and local_view.get_parent() == _course_root:
		_course_root.move_child(local_view, _course_root.get_child_count() - 1)

func _update_hud() -> void:
	var own: Dictionary = _player_state(_local_user_id)
	if own.is_empty():
		return
	var distance := distance_m(float(own.get("world_x", 0.0)), float(_manifest.get("start_x")))
	var ranking_snapshot := _authoritative_snapshot if not _authoritative_snapshot.is_empty() else _snapshot
	var players: Variant = ranking_snapshot.get("players", [])
	var place := calculate_player_place(players, _local_user_id)
	var distance_text := tr("DISTANCE %dm  ·  PLACE %d/%d") % [distance, place, players.size() if players is Array else 0]
	if _distance_label.text != distance_text:
		_distance_label.text = distance_text
	if _simulation.started and str(own.get("state", "")) == "running":
		if bool(own.get("blocked", false)):
			_status_label.text = tr("BLOCKED — FLIP GRAVITY")
		elif _network_clock >= _run_banner_until and _status_label.text != "":
			_status_label.text = ""
	elif str(own.get("state", "")) == "dead":
		if not _return_requester_name.is_empty():
			_update_return_request_notice()
		elif _status_label.text != tr("You were eliminated"):
			_status_label.text = tr("You were eliminated")
	if _authoritative_match_finished():
		_show_results()
		_return_lobby_button.disabled = _return_requested

static func calculate_player_place(players: Variant, user_id: String) -> int:
	if not players is Array:
		return 1
	var own: Dictionary = {}
	for player in players:
		if player is Dictionary and str(player.get("user_id", "")) == user_id:
			own = player
			break
	if own.is_empty():
		return 1
	var place := 1
	for other in players:
		if not other is Dictionary or str(other.get("user_id", "")) == user_id:
			continue
		if _player_precedes(other, own):
			place += 1
	return place

static func _player_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_state := str(left.get("state", "running"))
	var right_state := str(right.get("state", "running"))
	var state_order := {"finished": 0, "running": 1, "dead": 2, "disconnected": 3}
	var left_order := int(state_order.get(left_state, 3))
	var right_order := int(state_order.get(right_state, 3))
	if left_order != right_order:
		return left_order < right_order
	var left_x := float(left.get("world_x", 0.0))
	var right_x := float(right.get("world_x", 0.0))
	if not is_equal_approx(left_x, right_x):
		return left_x > right_x
	return str(left.get("user_id", "")) < str(right.get("user_id", ""))

func _refresh_camera_state() -> void:
	var local_state: Dictionary = _player_state(_local_user_id)
	var local_render := _local_render_position()
	var previous_mode := _camera_mode
	var previous_target := _spectator_target_user_id
	if _authoritative_match_finished():
		_camera_mode = CAMERA_MODE_FINISHED
	elif str(local_state.get("state", "running")) == "running":
		_camera_mode = CAMERA_MODE_LOCAL
		_spectator_target_user_id = ""
	else:
		_camera_mode = CAMERA_MODE_SPECTATING
	var followed_x := local_render.x + float(_visual_slot_by_user.get(_local_user_id, 0.0))
	if _camera_mode == CAMERA_MODE_SPECTATING:
		var players: Variant = _snapshot.get("players", [])
		if players is Array:
			_spectator_target_user_id = choose_spectator_target(players, _spectator_target_user_id)
			for player in players:
				if player is Dictionary and str(player.get("user_id", "")) == _spectator_target_user_id:
					followed_x = _visual_player_position(player, players).x
					break
	_camera_left_cached = maxf(followed_x - CAMERA_LEAD, 0.0)
	if previous_mode != _camera_mode or previous_target != _spectator_target_user_id:
		_record_match_diag("camera_state_changed", {"camera_mode": _camera_mode, "spectator_target": _spectator_target_user_id, "local_state": str(local_state.get("state", "unknown")), "camera_left": _camera_left_cached})

func _camera_left() -> float:
	return _camera_left_cached

func _authoritative_match_finished() -> bool:
	if MultiplayerService.is_room_owner():
		return _simulation != null and bool(_simulation.get("match_finished"))
	return _accepted_finish_revision > 0 and bool(_authoritative_snapshot.get("finished", false))

func _authoritative_result_snapshot() -> Dictionary:
	if MultiplayerService.is_room_owner():
		return _build_authoritative_snapshot()
	return _authoritative_snapshot.duplicate(true)

func _local_render_position() -> Vector2:
	var local_state: Dictionary = _simulation.get_player(_local_user_id) if _simulation != null else {}
	var current := Vector2(float(local_state.get("world_x", 180.0)), float(local_state.get("y", 0.0)))
	if not MultiplayerService.is_room_owner() and not _local_render_history.is_empty():
		current = interpolate_local_render_position(_local_render_history, _local_render_tick())
	return current + _visual_correction

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

func _record_match_diag(event_name: String, details: Dictionary) -> void:
	var important := event_name in ["simulation_started", "race_start_handshake_started", "race_start_probe_ack", "race_start_committed", "race_start_commit_received", "snapshot_stream_started", "camera_state_changed", "player_terminal_queued", "player_terminal_received", "match_terminal_snapshot", "match_finished_queued", "reliable_finish_ack", "results_panel_shown", "match_peer_failed", "flip_input_sent", "flip_input_queued", "flip_result_received", "diagnostic_session_received"]
	MultiplayerDiagnostics.record_event(event_name, details, important)
	var now := Time.get_ticks_msec()
	var signature := event_name + ":" + str(details.get("reason", ""))
	if _diagnostic_event_times.has(signature) and now - int(_diagnostic_event_times[signature]) < 1000:
		return
	_diagnostic_event_times[signature] = now
	var entry := details.duplicate(true)
	entry["event"] = event_name
	entry["room_id"] = MultiplayerService.get_room_id()
	entry["owner"] = MultiplayerService.is_room_owner()
	entry["at_ms"] = now
	var line := "[MP_DIAG] " + JSON.stringify(entry)
	_diagnostic_lines.append(line)
	while _diagnostic_lines.size() > 160:
		_diagnostic_lines.pop_front()
	print(line)
	if is_instance_valid(_diagnostic_text) and is_instance_valid(_diagnostic_panel) and _diagnostic_panel.visible:
		_diagnostic_text.text = "\n".join(_diagnostic_lines)
		_diagnostic_text.scroll_vertical = _diagnostic_text.get_line_count()

func _toggle_diagnostics() -> void:
	if is_instance_valid(_diagnostic_panel):
		_diagnostic_panel.visible = not _diagnostic_panel.visible

func _copy_diagnostics() -> void:
	var report_text := MultiplayerDiagnostics.get_export_text(true)
	DisplayServer.clipboard_set(report_text)
	if is_instance_valid(_diagnostic_text):
		_diagnostic_text.text = report_text
		_diagnostic_text.select_all()
		_diagnostic_text.scroll_vertical = 0
		if not OS.has_feature("web"):
			_diagnostic_status_label.text = tr("Report copied. Debug ID: %s") % str(MultiplayerDiagnostics.get_latest_report().get("diagnostic_session_id", "local only"))

func _save_full_diagnostics() -> void:
	var saved_path := MultiplayerDiagnostics.save_latest_report()
	if OS.has_feature("web"):
		var json_text := MultiplayerDiagnostics.get_export_text(false)
		var base64 := Marshalls.raw_to_base64(json_text.to_utf8_buffer())
		JavaScriptBridge.eval("(()=>{const a=document.createElement('a');a.href='data:application/json;base64,%s';a.download='gravity-run-multiplayer-report.json';a.click()})()" % base64, true)
		_diagnostic_status_label.text = tr("Full report download requested. %s") % saved_path
	else:
		_diagnostic_status_label.text = tr("Full report saved locally: %s") % saved_path

func _mark_diagnostic_problem() -> void:
	MultiplayerDiagnostics.mark_problem("flimmer/lagg")

func _set_diagnostic_opt_in() -> void:
	MultiplayerDiagnostics.opt_in(true)

func _create_diagnostic_session() -> void:
	MultiplayerDiagnostics.start_shared_session(_start_generation)

func _on_diagnostics_status_changed(message: String) -> void:
	if is_instance_valid(_diagnostic_status_label):
		_diagnostic_status_label.text = message

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
	_return_request_notice = Label.new()
	_return_request_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_return_request_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_return_request_notice.add_theme_font_size_override("font_size", 16)
	_return_request_notice.add_theme_color_override("font_color", Color("b8c7dc"))
	_return_request_notice.visible = false
	results_layout.add_child(_return_request_notice)
	_results_list = VBoxContainer.new()
	_results_list.add_theme_constant_override("separation", 5)
	results_layout.add_child(_results_list)
	_return_lobby_button = Button.new()
	_return_lobby_button.text = tr("Return everyone to lobby") if MultiplayerService.is_room_owner() else tr("Ask host to return")
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
	var diagnostics_button := Button.new()
	diagnostics_button.text = tr("Diagnostics")
	diagnostics_button.anchor_left = 1.0
	diagnostics_button.anchor_right = 1.0
	diagnostics_button.offset_left = -150
	diagnostics_button.offset_right = -16
	diagnostics_button.offset_top = 62
	diagnostics_button.offset_bottom = 102
	diagnostics_button.pressed.connect(_toggle_diagnostics)
	hud.add_child(diagnostics_button)
	_diagnostic_panel = PanelContainer.new()
	_diagnostic_panel.anchor_left = 0.5
	_diagnostic_panel.anchor_top = 0.5
	_diagnostic_panel.anchor_right = 0.5
	_diagnostic_panel.anchor_bottom = 0.5
	_diagnostic_panel.offset_left = -360
	_diagnostic_panel.offset_right = 360
	_diagnostic_panel.offset_top = -245
	_diagnostic_panel.offset_bottom = 245
	_diagnostic_panel.visible = false
	_diagnostic_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_diagnostic_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(_diagnostic_panel)
	var diagnostic_layout := VBoxContainer.new()
	diagnostic_layout.add_theme_constant_override("separation", 8)
	_diagnostic_panel.add_child(diagnostic_layout)
	var diagnostic_title := Label.new()
	diagnostic_title.text = tr("MULTIPLAYER DIAGNOSTICS")
	diagnostic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diagnostic_title.add_theme_color_override("font_color", Color("42d6c5"))
	diagnostic_layout.add_child(diagnostic_title)
	_diagnostic_text = TextEdit.new()
	_diagnostic_text.editable = false
	_diagnostic_text.selecting_enabled = true
	_diagnostic_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagnostic_text.add_theme_font_size_override("font_size", 12)
	diagnostic_layout.add_child(_diagnostic_text)
	var diagnostic_actions := HBoxContainer.new()
	diagnostic_layout.add_child(diagnostic_actions)
	var copy_button := Button.new()
	copy_button.text = tr("Copy report")
	copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button.pressed.connect(_copy_diagnostics)
	diagnostic_actions.add_child(copy_button)
	var save_button := Button.new()
	save_button.text = tr("Save full report")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_full_diagnostics)
	diagnostic_actions.add_child(save_button)
	var mark_button := Button.new()
	mark_button.text = tr("Mark lag / flicker")
	mark_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark_button.pressed.connect(_mark_diagnostic_problem)
	diagnostic_actions.add_child(mark_button)
	var opt_in_button := Button.new()
	opt_in_button.text = tr("Enable report upload")
	opt_in_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_in_button.pressed.connect(_set_diagnostic_opt_in)
	diagnostic_actions.add_child(opt_in_button)
	if MultiplayerService.is_room_owner():
		var session_button := Button.new()
		session_button.text = tr("Create shared debug ID")
		session_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		session_button.pressed.connect(_create_diagnostic_session)
		diagnostic_actions.add_child(session_button)
	_diagnostic_status_label = Label.new()
	_diagnostic_status_label.text = MultiplayerDiagnostics.get_status()
	_diagnostic_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostic_layout.add_child(_diagnostic_status_label)
	var close_button := Button.new()
	close_button.text = tr("Close")
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(_toggle_diagnostics)
	diagnostic_actions.add_child(close_button)
func _show_results() -> void:
	if _results_panel.visible:
		return
	# Local prediction must never decide the outcome on a guest. Only the
	# host-authored terminal snapshot may open the multiplayer results screen.
	var result_snapshot := _authoritative_result_snapshot()
	var owner_finished := MultiplayerService.is_room_owner() and _authoritative_match_finished()
	if not _authoritative_match_finished() or not may_show_results(MultiplayerService.is_room_owner(), result_snapshot, owner_finished):
		if not _local_finish_ignored_logged:
			_local_finish_ignored_logged = true
			_record_match_diag("local_finish_ignored", {"local_tick": int(_simulation.get("tick")) if _simulation != null else -1, "local_players": _snapshot.get("players", [])})
		return
	_snapshot = result_snapshot.duplicate(true)
	_log_terminal_snapshot("results_panel_shown", _snapshot)
	MultiplayerDiagnostics.finish_match("finished")
	_results_panel.visible = true
	_status_label.visible = false
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
	var winner_name := ""
	if not states.is_empty():
		var first_state: Dictionary = states[0]
		if str(first_state.get("state", "")) == "finished":
			winner_name = str(first_state.get("display_name", ""))
		else:
			var leading_distance := float(first_state.get("world_x", 0.0))
			var tied_for_lead := false
			for index in range(1, states.size()):
				var candidate: Dictionary = states[index]
				if is_equal_approx(float(candidate.get("world_x", 0.0)), leading_distance):
					tied_for_lead = true
					break
			winner_name = str(first_state.get("display_name", "")) if not tied_for_lead else ""
	var finish_reason := str(result_snapshot.get("finish_reason", _finish_reason))
	if finish_reason == "confirmed_disconnect":
		winner_name = ""
	var winner_text := tr("Winner: %s") % winner_name if not winner_name.is_empty() else tr("No winner")
	var reason_text := tr("Match ended: connection lost") if finish_reason == "confirmed_disconnect" else (tr("Match ended: everyone was eliminated") if finish_reason == "elimination" else tr("Match ended at the finish line"))
	_result_label.text = winner_text + "\n" + reason_text
	_update_return_request_notice()
	for child in _results_list.get_children():
		child.queue_free()
	var previous_place := 0
	var previous_distance := NAN
	for index in range(states.size()):
		var state: Dictionary = states[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank := Label.new()
		rank.custom_minimum_size.x = 48
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var state_distance := float(state.get("world_x", 0.0))
		var place := index + 1
		if index > 0 and is_equal_approx(state_distance, previous_distance) and str(state.get("state", "")) != "finished" and str(states[index - 1].get("state", "")) != "finished":
			place = previous_place
		rank.text = "#%d" % place
		if index < 3:
			var medal := Control.new()
			medal.set_script(ResultMedalScript)
			medal.set("place", place)
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
		previous_place = place
		previous_distance = state_distance
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
			_return_notice_override = tr("Return request sent. Waiting for the host to confirm.")
			_update_return_request_notice()
		else:
			_return_requested = false
			_return_lobby_button.disabled = false
			_return_lobby_button.text = tr("Ask host to return")
			_return_notice_override = tr("Could not send a return request to the host.")
			_update_return_request_notice()

func _update_return_request_notice() -> void:
	if not is_instance_valid(_return_request_notice):
		return
	var message := _return_notice_override
	if message.is_empty() and not _return_requester_name.is_empty():
		message = tr("%s asked to return to the lobby. The host can confirm with the button below.") % _return_requester_name
	_return_request_notice.text = message
	_return_request_notice.visible = not message.is_empty()

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
	_return_lobby_button.text = tr("Ask host to return")
	_return_notice_override = message
	_update_return_request_notice()

func status_label_color() -> void:
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color("ffd166"))

func _show_failure(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message

func _leave_match() -> void:
	_leaving_match = true
	MultiplayerDiagnostics.finish_match("left")
	if not MultiplayerService.is_room_owner() and not _start_generation.is_empty():
		MultiplayerService.queue_reliable_peer_message(_owner_user_id, {"kind": "player_explicit_leave", "room_id": MultiplayerService.get_room_id(), "match_generation": _start_generation})
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
