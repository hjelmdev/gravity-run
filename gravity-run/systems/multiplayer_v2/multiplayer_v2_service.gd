extends Node
## Isolated V2 session owner. It owns a MultiplayerAPI for a dedicated node branch;
## it never installs a peer on SceneTree's default MultiplayerAPI.

const RpcEndpointScript := preload("res://systems/multiplayer_v2/v2_rpc_endpoint.gd")
const DiagnosticsScript := preload("res://systems/multiplayer_v2/v2_diagnostics.gd")
const LobbyProviderScript := preload("res://systems/multiplayer_v2/v2_lobby_provider.gd")
const IdentityAdapterScript := preload("res://systems/multiplayer_v2/v2_identity_adapter.gd")
const SignalingTransportScript := preload("res://systems/supabase_signaling_transport.gd")
const WebRTCTransportScript := preload("res://systems/multiplayer_v2/v2_webrtc_transport.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const ValidationScript := preload("res://systems/multiplayer_v2/v2_validation.gd")
const RoundCoordinatorScript := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")
const ManifestBuilderScript := preload("res://systems/course_manifest_builder.gd")
const DestructibleRulesScript := preload("res://systems/multiplayer_v2/v2_destructible_rules.gd")
const Motion := preload("res://systems/runner_motion.gd")

signal session_changed(session: Dictionary)
signal transport_state_changed(state: String, message: String)
signal player_sample_received(peer_id: int, sample: Dictionary)
signal input_audit_received(peer_id: int, audit: Dictionary)
signal terminal_report_received(peer_id: int, report: Dictionary)
signal world_interaction_received(peer_id: int, request: Dictionary)
signal control_received(peer_id: int, kind: String, payload: Dictionary)
signal room_changed(room: Dictionary)
signal public_rooms_loaded(rooms: Array, message: String)
signal lobby_request_finished(action: String, success: bool, message: String)
signal signaling_state_changed(connected: bool, message: String)
signal round_prepare_requested(descriptor: Dictionary)
signal round_started(round_id: String, descriptor: Dictionary)
signal round_failed(reason: String)
signal world_event_committed(commit: Dictionary)
signal world_baseline_received(baseline: Dictionary)
signal world_interaction_resolved(request_id: String, accepted: bool, message: String, commit: Dictionary)
signal results_received(result: Dictionary)

const MAX_PLAYERS := 5
const POSITION_RATE_HZ := 30

var session: Dictionary = {}
var diagnostics: MultiplayerV2Diagnostics = DiagnosticsScript.new()
var network_api: MultiplayerAPI
var network_root: Node
var rpc_endpoint: Node
var webrtc_peer: WebRTCMultiplayerPeer
var _sample_accumulator := 0.0
var _sample_period := 1.0 / POSITION_RATE_HZ
var _active := false
var identity_user_id := ""
var identity_is_anonymous := true
var room_state: Dictionary = {}
var _identity_adapter: Node
var _lobby_provider: Node
var _signaling_transport: Node
var _webrtc_transport: Node
var _pending_identity_action := ""
var _pending_identity_arguments: Dictionary = {}
var _pending_lobby_context := ""
var _lobby_contexts: Dictionary = {}
var _lobby_poll_elapsed := 0.0
var _last_sample_by_peer: Dictionary = {}
var _last_seen_tick_by_peer: Dictionary = {}
var _last_sample_state_by_peer: Dictionary = {}
var _last_input_sequence_by_peer: Dictionary = {}
var _last_accepted_flip_tick_by_peer: Dictionary = {}
var _round_id := ""
var _round_roster_revision := 0
var current_manifest: Resource
var _round_coordinator: MultiplayerV2RoundCoordinator = RoundCoordinatorScript.new()
var _clock_ping_elapsed := 0.0
var _heartbeat_elapsed := 0.0
var _local_prepare_pending := false
var _manifest_action_pending := ""
var world_simulation: MultiplayerV2WorldSimulation
var terminal_status: Dictionary = {}
var _interaction_results: Dictionary = {}
var _pending_interactions: Array[Dictionary] = []
const BARREL_CLAIM_BATCH_USEC := 150_000
var _world_event_acks: Dictionary = {}
var _disconnect_since_usec: Dictionary = {}
var _last_heartbeat_usec: Dictionary = {}
var _last_reconnect_attempt_usec: Dictionary = {}
var _result_retry_elapsed := 0.0
var _result_committed := false
var _committed_result: Dictionary = {}
var _result_acks: Dictionary = {}
var _terminal_delivery_pending: Dictionary = {}
var _terminal_delivery_elapsed := 0.0
var _received_terminal_events: Dictionary = {}
var _world_hash_reports: Dictionary = {}
var _world_divergence_reported := false
var _last_host_heartbeat_usec := -1
const DISCONNECT_GRACE_USEC := 10_000_000
const HEARTBEAT_INTERVAL_SECONDS := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_network_branch()
	_create_lobby_services()

func _process(delta: float) -> void:
	if not room_state.is_empty():
		_lobby_poll_elapsed += delta
		if _lobby_poll_elapsed >= 3.0:
			_lobby_poll_elapsed = 0.0
			refresh_room()
	if _active:
		_sample_accumulator = minf(_sample_accumulator + delta, _sample_period * 2.0)
		_clock_ping_elapsed += delta
		if str(session.get("role", "")) == "guest" and not _round_coordinator.clock.is_synchronized() and _clock_ping_elapsed >= 0.5:
			_clock_ping_elapsed = 0.0
			send_control(1, "CLOCK_PING", {"client_sent_usec": Time.get_ticks_usec()})
		_heartbeat_elapsed += delta
		if _heartbeat_elapsed >= HEARTBEAT_INTERVAL_SECONDS:
			_heartbeat_elapsed = fmod(_heartbeat_elapsed, HEARTBEAT_INTERVAL_SECONDS)
			if str(session.get("role", "")) == "guest":
				send_control(1, "HEARTBEAT", {"client_sent_usec": Time.get_ticks_usec()})
			else:
				for target in connected_peer_ids():
					send_control(int(target), "HEARTBEAT", {"host_sent_usec": Time.get_ticks_usec()})
		_round_coordinator.process(Time.get_ticks_usec())
		_drain_interaction_claims()
		_process_result_delivery(delta)
		_process_terminal_delivery(delta)
		if _local_prepare_pending and (_round_coordinator.is_host or _round_coordinator.clock.is_synchronized()):
			_local_prepare_pending = false
			_round_coordinator.mark_local_prepared(Time.get_ticks_usec())
		_check_disconnect_grace()

func _create_network_branch() -> void:
	network_root = Node.new()
	network_root.name = "Network"
	add_child(network_root)
	network_api = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(network_api, network_root.get_path())
	rpc_endpoint = RpcEndpointScript.new()
	rpc_endpoint.name = "Rpc"
	rpc_endpoint.player_sample_received.connect(_on_player_sample_rpc)
	rpc_endpoint.input_audit_received.connect(_on_input_audit_rpc)
	rpc_endpoint.terminal_report_received.connect(_on_terminal_rpc)
	rpc_endpoint.world_interaction_received.connect(_on_world_interaction_rpc)
	rpc_endpoint.control_received.connect(_on_control_rpc)
	network_root.add_child(rpc_endpoint)
	network_api.peer_connected.connect(_on_peer_connected)
	network_api.peer_disconnected.connect(_on_peer_disconnected)

func _create_lobby_services() -> void:
	_identity_adapter = IdentityAdapterScript.new()
	_identity_adapter.name = "Identity"
	_identity_adapter.identity_ready.connect(_on_identity_ready)
	_identity_adapter.identity_failed.connect(_on_identity_failed)
	add_child(_identity_adapter)
	_lobby_provider = LobbyProviderScript.new()
	_lobby_provider.name = "LobbyProvider"
	_lobby_provider.request_finished.connect(_on_lobby_request_finished)
	add_child(_lobby_provider)
	_signaling_transport = SignalingTransportScript.new()
	_signaling_transport.name = "Signaling"
	_signaling_transport.connection_state_changed.connect(_on_signaling_state_changed)
	_signaling_transport.message_received.connect(_on_signaling_message)
	add_child(_signaling_transport)
	_webrtc_transport = WebRTCTransportScript.new()
	_webrtc_transport.name = "WebRTC"
	_webrtc_transport.signal_outgoing.connect(_signaling_transport.send_signal)
	_webrtc_transport.peer_state_changed.connect(_on_peer_state_changed)
	add_child(_webrtc_transport)
	_round_coordinator.control_requested.connect(send_control)
	_round_coordinator.round_started.connect(_on_round_started)
	_round_coordinator.round_failed.connect(func(reason: String) -> void: round_failed.emit(reason))

func has_room() -> bool:
	return not room_state.is_empty()

func is_room_owner() -> bool:
	return has_room() and str(room_state.get("owner_user_id", "")) == identity_user_id

func get_members() -> Array:
	return room_state.get("members", [])

func create_room(display_name: String, is_public: bool = true, seed_value: int = -1, course_length_px: int = 45000) -> void:
	_begin_identity_action("create_room", {"display_name": display_name, "is_public": is_public, "seed": seed_value if seed_value >= 1 else randi_range(1, 2_147_483_647), "course_length_px": course_length_px})

func join_room(room_code: String, display_name: String) -> void:
	_begin_identity_action("join_room", {"room_code": room_code.strip_edges().to_upper(), "display_name": display_name})

func list_public_rooms() -> void:
	_begin_identity_action("list_rooms", {})

func refresh_room() -> void:
	if has_room():
		_begin_identity_action("refresh_room", {"room_id": str(room_state.get("room_id", ""))})

func set_ready(ready: bool) -> void:
	if has_room():
		_begin_identity_action("set_ready", {"room_id": str(room_state.get("room_id", "")), "ready": ready})

func set_skin_id(skin_id: int) -> void:
	if has_room():
		_begin_identity_action("set_skin", {"room_id": str(room_state.get("room_id", "")), "skin_id": posmod(skin_id, 4)})

func request_start() -> void:
	if not is_room_owner():
		lobby_request_finished.emit("prepare_round", false, tr("Only the V2 host can start the round."))
		return
	var blockers := get_start_blockers()
	if not blockers.is_empty():
		lobby_request_finished.emit("prepare_round", false, tr("V2 cannot start yet: %s") % ", ".join(blockers))
		return
	_begin_identity_action("prepare_round", {"room_id": str(room_state.get("room_id", ""))})

func get_start_blockers() -> PackedStringArray:
	var blockers := PackedStringArray()
	if not is_room_owner():
		blockers.append("not_host")
	if str(room_state.get("phase", "")) != "OPEN":
		blockers.append("room_not_open")
	if str(room_state.get("manifest_hash", "")).is_empty() or current_manifest == null:
		blockers.append("manifest_missing")
	var members: Array = room_state.get("members", [])
	if members.is_empty() or members.size() > MAX_PLAYERS:
		blockers.append("player_count")
	for member in members:
		if not bool(member.get("is_connected", true)):
			blockers.append("member_offline:%s" % str(member.get("display_name", "Runner")))
		if not bool(member.get("is_ready", false)):
			blockers.append("member_not_ready:%s" % str(member.get("display_name", "Runner")))
		if str(member.get("loaded_manifest_hash", "")) != str(room_state.get("manifest_hash", "")):
			blockers.append("manifest_unacknowledged:%s" % str(member.get("display_name", "Runner")))
	var connected := connected_peer_ids()
	for member in members:
		if str(member.get("user_id", "")) == identity_user_id:
			continue
		var expected_peer := int(member.get("player_slot", 1))
		if expected_peer not in connected:
			blockers.append("transport_missing:%s" % str(member.get("display_name", "Runner")))
	return blockers

func leave_room() -> void:
	if has_room():
		_begin_identity_action("leave_room", {"room_id": str(room_state.get("room_id", ""))})
		_signaling_transport.disconnect_room()
		_webrtc_transport.close_all()
		close_session("left_room")

func begin_peer_connection() -> void:
	if not has_room():
		return
	if not _active:
		var error := open_host(room_state, 4) if is_room_owner() else configure_client_peer(int(_member_for_user(identity_user_id).get("player_slot", 1)))
		if error != OK:
			lobby_request_finished.emit("connect", false, "Could not initialize V2 WebRTC (code %d)." % error)
			return
		if not is_room_owner():
			activate_client_session(room_state)
	_webrtc_transport.configure(room_state, identity_user_id, webrtc_peer)
	if is_room_owner():
		_webrtc_transport.begin_connection()
	else:
		_signaling_transport.connect_room(str(room_state.get("signaling_topic", "")), _identity_adapter.token())
		_webrtc_transport.begin_connection()

func _begin_identity_action(action: String, arguments: Dictionary) -> void:
	if action in ["create_room", "join_room"] and has_room():
		lobby_request_finished.emit(action, false, tr("Leave the current V2 room first."))
		return
	_pending_identity_action = action
	_pending_identity_arguments = arguments.duplicate(true)
	_pending_lobby_context = "%s:%d" % [action, Time.get_ticks_msec()]
	_identity_adapter.ensure_identity(str(arguments.get("display_name", "Runner")), _pending_lobby_context)

func _on_identity_ready(user_id: String, _token: String, anonymous: bool, context: String) -> void:
	if context != _pending_lobby_context or _pending_identity_action.is_empty():
		return
	identity_user_id = user_id
	identity_is_anonymous = anonymous
	var action := _pending_identity_action
	var arguments := _pending_identity_arguments.duplicate(true)
	_pending_identity_action = ""
	_pending_identity_arguments.clear()
	var token: String = _identity_adapter.token()
	_lobby_contexts[context] = action
	match action:
		"create_room":
			_lobby_provider.create_room(str(arguments.display_name), bool(arguments.is_public), "2", CourseGeneratorScript.GENERATOR_VERSION, int(arguments.seed), int(arguments.course_length_px), token, context)
		"join_room":
			_lobby_provider.join_room(str(arguments.room_code), str(arguments.display_name), "2", CourseGeneratorScript.GENERATOR_VERSION, token, context)
		"list_rooms":
			_lobby_provider.list_rooms(token, context)
		"refresh_room":
			_lobby_provider.refresh_room(str(arguments.room_id), token, context)
		"set_ready":
			_lobby_provider.set_ready(str(arguments.room_id), bool(arguments.ready), token, context)
		"set_skin":
			_lobby_provider.set_skin(str(arguments.room_id), int(arguments.skin_id), token, context)
		"leave_room":
			_lobby_provider.leave_room(str(arguments.room_id), token, context)
		"prepare_round":
			_lobby_provider.start_prepare(str(arguments.room_id), token, context)

func _on_identity_failed(message: String, context: String) -> void:
	if context == _pending_lobby_context:
		_pending_identity_action = ""
		_pending_identity_arguments.clear()
		lobby_request_finished.emit("identity", false, message)

func _on_lobby_request_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	if not _lobby_contexts.has(context):
		return
	_lobby_contexts.erase(context)
	if action in ["set_manifest", "ack_manifest"]:
		_manifest_action_pending = ""
	if action == "list_rooms":
		var rooms: Array = data if data is Array else []
		public_rooms_loaded.emit(rooms, message)
		lobby_request_finished.emit(action, success, message)
		return
	if action == "leave_room":
		room_state.clear()
		room_changed.emit({})
		lobby_request_finished.emit(action, success, message)
		return
	if action == "prepare_round" and success and data is Dictionary:
		var next_room: Dictionary = data.get("room", data)
		room_state = next_room.duplicate(true)
		room_changed.emit(room_state.duplicate(true))
		var peers := PackedInt32Array()
		for peer_id in connected_peer_ids():
			peers.append(int(peer_id))
		_round_id = Crypto.new().generate_random_bytes(16).hex_encode()
		session["round_id"] = _round_id
		session["roster_revision"] = int(room_state.get("lobby_generation", 0))
		var descriptor := {"round_id": _round_id, "room_id": str(room_state.get("room_id", "")), "room_session_id": str(room_state.get("room_session_id", "")), "lobby_generation": int(room_state.get("lobby_generation", 0)), "roster_revision": int(room_state.get("lobby_generation", 0)), "manifest_hash": str(room_state.get("manifest_hash", "")), "seed": int(room_state.get("seed", 1)), "course_length_px": int(room_state.get("course_length_px", 45000)), "players": room_state.get("members", []).duplicate(true)}
		_round_roster_revision = int(descriptor.roster_revision)
		_round_coordinator.prepare_as_host(descriptor, Array(peers), Time.get_ticks_usec())
		round_prepare_requested.emit(descriptor.duplicate(true))
		lobby_request_finished.emit(action, true, "")
		return
	if success and data is Dictionary:
		var next_room: Dictionary = data.get("room", data)
		if next_room is Dictionary and not next_room.is_empty():
			room_state = next_room.duplicate(true)
			room_state["network_mode"] = "v2"
			if action not in ["create_room", "join_room"]:
				_webrtc_transport.update_room(room_state)
			room_changed.emit(room_state.duplicate(true))
			if action in ["set_manifest", "refresh_room"]:
				_ensure_manifest()
			if action in ["create_room", "join_room"]:
				var maximum := maxi(1, int(room_state.get("max_players", 5)) - 1)
				var error := open_host(room_state, maximum) if is_room_owner() else configure_client_peer(int(_member_for_user(identity_user_id).get("player_slot", 1)))
				if error == OK:
					if not is_room_owner():
						activate_client_session(room_state)
					_webrtc_transport.configure(room_state, identity_user_id, webrtc_peer)
					_signaling_transport.connect_room(str(room_state.get("signaling_topic", "")), _identity_adapter.token())
					_webrtc_transport.begin_connection()
					_ensure_manifest()
		elif action in ["set_manifest", "refresh_room", "return_to_lobby"]:
			if action == "return_to_lobby":
				for target in connected_peer_ids():
					send_control(int(target), "RETURN_TO_LOBBY", {"room": room_state.duplicate(true)})
				_ensure_manifest()
			elif action == "ack_manifest":
				room_changed.emit(room_state.duplicate(true))
		lobby_request_finished.emit(action, success, message)
	else:
		lobby_request_finished.emit(action, success, message)

func _on_signaling_state_changed(connected: bool, message: String) -> void:
	signaling_state_changed.emit(connected, message)
	if connected and is_room_owner():
		# Host receives offers for guests and maps their roster slot to the
		# stable Godot peer id in V2WebRTCTransport.handle_signal().
		pass

func _on_signaling_message(message: Dictionary) -> void:
	if not has_room() or str(message.get("network_mode", "")) != "v2" or str(message.get("room_id", "")) != str(room_state.get("room_id", "")):
		return
	if str(message.get("to_user_id", "")) != identity_user_id:
		return
	var sender := str(message.get("from_user_id", ""))
	if _member_for_user(sender).is_empty():
		return
	_webrtc_transport.handle_signal(message)

func _on_peer_state_changed(peer_id: int, state: String, message: String) -> void:
	transport_state_changed.emit(state, "Peer %d: %s" % [peer_id, message])

func _member_for_user(user_id: String) -> Dictionary:
	for member in get_members():
		if str(member.get("user_id", "")) == user_id:
			return member
	return {}

func open_host(session_descriptor: Dictionary, max_clients: int = 4) -> Error:
	if _active:
		return ERR_BUSY
	if max_clients < 1 or max_clients > MAX_PLAYERS - 1:
		return ERR_INVALID_PARAMETER
	webrtc_peer = WebRTCMultiplayerPeer.new()
	# WebRTCMultiplayerPeer takes ICE servers here; player limits are enforced by the V2 room roster.
	var error: Error = webrtc_peer.create_server([])
	if error != OK:
		webrtc_peer = null
		transport_state_changed.emit("failed", "Godot could not create the V2 WebRTC server (code %d)." % error)
		return error
	network_api.multiplayer_peer = webrtc_peer
	session = session_descriptor.duplicate(true)
	session["network_mode"] = "v2"
	session["protocol_version"] = 1
	session["role"] = "host"
	session["local_peer_id"] = 1
	session["build_id"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	session["godot_version"] = Engine.get_version_info()
	_round_id = ""
	_active = true
	diagnostics.begin_session(session)
	transport_state_changed.emit("waiting", "V2 host is waiting for peer links.")
	session_changed.emit(session.duplicate(true))
	return OK

func attach_guest_peer(peer_id: int, connection: WebRTCPeerConnection) -> Error:
	if not _active or str(session.get("role", "")) != "host" or peer_id <= 1 or peer_id > MAX_PLAYERS:
		return ERR_INVALID_PARAMETER
	if connection == null or connection.get_connection_state() != WebRTCPeerConnection.STATE_NEW:
		return ERR_INVALID_PARAMETER
	var error := webrtc_peer.add_peer(connection, peer_id)
	if error == OK:
		diagnostics.record_event("peer_registered", {"peer_id": peer_id})
	return error

func configure_client_peer(assigned_peer_id: int) -> Error:
	if assigned_peer_id < 2 or assigned_peer_id > MAX_PLAYERS:
		return ERR_INVALID_PARAMETER
	webrtc_peer = WebRTCMultiplayerPeer.new()
	var error := webrtc_peer.create_client(assigned_peer_id)
	if error != OK:
		webrtc_peer = null
		return error
	network_api.multiplayer_peer = webrtc_peer
	session["local_peer_id"] = assigned_peer_id
	return OK

func activate_client_session(session_descriptor: Dictionary) -> void:
	session = session_descriptor.duplicate(true)
	session["network_mode"] = "v2"
	session["protocol_version"] = 1
	session["role"] = "guest"
	if not session.has("local_peer_id"):
		session["local_peer_id"] = int(_member_for_user(identity_user_id).get("player_slot", 1)) + 1
	session["build_id"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	session["godot_version"] = Engine.get_version_info()
	_active = true
	diagnostics.begin_session(session)
	_round_id = str(session.get("round_id", ""))
	session_changed.emit(session.duplicate(true))

func set_snapshot_rate(hz: int) -> void:
	if hz not in [30, 60]:
		return
	_sample_period = 1.0 / float(hz)
	diagnostics.session["position_rate_hz"] = hz

func get_snapshot_rate() -> int:
	return roundi(1.0 / _sample_period)

func send_sample(sample: Dictionary) -> void:
	if not _active or rpc_endpoint == null:
		return
	if _sample_accumulator < _sample_period:
		return
	_sample_accumulator = maxf(_sample_accumulator - _sample_period, 0.0)
	var packet := _session_envelope()
	packet.merge(sample, true)
	if str(session.get("role", "")) == "host":
		_on_player_sample_rpc(1, packet)
	else:
		rpc_endpoint.send_sample_to_peer(1, packet)

func send_audit(audit: Dictionary) -> void:
	if _active:
		var packet := _session_envelope()
		packet.merge(audit, true)
		rpc_endpoint.send_audit(packet)

func send_terminal(report: Dictionary) -> void:
	if _active:
		var packet := _session_envelope()
		packet.merge(report, true)
		rpc_endpoint.send_terminal(packet)

func send_interaction(request: Dictionary) -> void:
	if _active:
		var packet := _session_envelope()
		packet.merge(request, true)
		rpc_endpoint.send_interaction(packet)

func send_control(peer_id: int, kind: String, payload: Dictionary) -> void:
	if _active:
		var packet := _session_envelope()
		packet.merge(payload, true)
		rpc_endpoint.send_control(peer_id, kind, packet)

func begin_round(round_id: String, roster_revision: int) -> void:
	_round_id = round_id
	_round_roster_revision = roster_revision
	_sample_accumulator = 0.0
	_last_sample_by_peer.clear()
	_last_seen_tick_by_peer.clear()
	_last_sample_state_by_peer.clear()
	_last_input_sequence_by_peer.clear()
	_last_accepted_flip_tick_by_peer.clear()
	_world_event_acks.clear()
	_world_hash_reports.clear()
	_world_divergence_reported = false
	_result_retry_elapsed = 0.0
	_result_committed = false
	_committed_result.clear()
	_result_acks.clear()
	_terminal_delivery_pending.clear()
	_terminal_delivery_elapsed = 0.0
	_received_terminal_events.clear()
	terminal_status.clear()
	_interaction_results.clear()
	_pending_interactions.clear()
	_disconnect_since_usec.clear()
	_last_heartbeat_usec.clear()
	diagnostics.record_event("round_began", {"round_id": round_id, "roster_revision": roster_revision})

func _on_player_sample_rpc(sender_peer_id: int, sample: Dictionary) -> void:
	if not _active or _round_id.is_empty():
		return
	var packet_error := _packet_session_error(sample, false)
	if not packet_error.is_empty():
		diagnostics.record_event("sample_rejected", {"peer_id": sender_peer_id, "reason": packet_error})
		return
	var owner_peer := int(sample.get("owner_peer_id", -1))
	if str(session.get("role", "")) == "host":
		if sender_peer_id != 1 and owner_peer != sender_peer_id:
			diagnostics.record_event("sample_owner_mismatch", {"sender": sender_peer_id, "owner": owner_peer})
			return
		if not _is_roster_peer(owner_peer):
			return
		var previous_seq := int(_last_sample_by_peer.get(owner_peer, 0))
		var previous_tick := int(_last_seen_tick_by_peer.get(owner_peer, 0))
		var reason := ValidationScript.validate_sample(sample, _round_id, owner_peer, previous_seq, previous_tick)
		if not reason.is_empty():
			diagnostics.record_event("sample_rejected", {"peer_id": owner_peer, "reason": reason})
			return
		_last_sample_by_peer[owner_peer] = int(sample.sample_seq)
		_last_seen_tick_by_peer[owner_peer] = int(sample.simulation_tick)
		_audit_sample_physics(owner_peer, sample)
		_last_sample_state_by_peer[owner_peer] = sample.duplicate(true)
		diagnostics.increment_metric("samples_validated_host")
		player_sample_received.emit(owner_peer, sample.duplicate(true))
		for target in connected_peer_ids():
			if int(target) != owner_peer:
				rpc_endpoint.send_sample_to_peer(int(target), sample)
		return
	if sender_peer_id != 1 or owner_peer == int(session.get("local_peer_id", -1)) or not _is_roster_peer(owner_peer):
		return
	var reason := ValidationScript.validate_sample(sample, _round_id, owner_peer, int(_last_sample_by_peer.get(owner_peer, 0)), int(_last_seen_tick_by_peer.get(owner_peer, 0)))
	if not reason.is_empty():
		return
	_last_sample_by_peer[owner_peer] = int(sample.sample_seq)
	_last_seen_tick_by_peer[owner_peer] = int(sample.simulation_tick)
	_last_sample_state_by_peer[owner_peer] = sample.duplicate(true)
	diagnostics.increment_metric("samples_presented_remote")
	player_sample_received.emit(owner_peer, sample.duplicate(true))

func _audit_sample_physics(peer_id: int, sample: Dictionary) -> void:
	if not _last_sample_state_by_peer.has(peer_id):
		return
	var previous: Dictionary = _last_sample_state_by_peer[peer_id]
	var tick_delta := maxi(0, int(sample.simulation_tick) - int(previous.simulation_tick))
	var distance := float(sample.world_x) - float(previous.world_x)
	var max_distance := Motion.BASE_RUN_SPEED * float(tick_delta) / 60.0 + 48.0
	if distance < -48.0 or distance > max_distance:
		diagnostics.record_event("input_physics_warning", {"peer_id": peer_id, "reason": "horizontal_velocity_outlier", "tick_delta": tick_delta, "distance": distance, "max_distance": max_distance})

func _on_input_audit_rpc(sender_peer_id: int, audit: Dictionary) -> void:
	if not _active or str(session.get("role", "")) != "host" or not _is_roster_peer(sender_peer_id):
		return
	if not _packet_session_error(audit, false).is_empty():
		return
	if int(audit.get("owner_peer_id", -1)) != sender_peer_id or str(audit.get("round_id", "")) != _round_id:
		return
	var sequence := int(audit.get("input_seq", -1))
	var input_tick := int(audit.get("simulation_tick", -1))
	if sequence <= int(_last_input_sequence_by_peer.get(sender_peer_id, 0)) or input_tick < 0 or input_tick > int(_last_seen_tick_by_peer.get(sender_peer_id, input_tick)) + 30:
		diagnostics.record_event("input_audit_rejected", {"peer_id": sender_peer_id, "reason": "stale_or_future_input"})
		return
	_last_input_sequence_by_peer[sender_peer_id] = sequence
	if str(audit.get("kind", "")) == "gravity_flip" and bool(audit.get("accepted", false)):
		var prior_flip_tick := int(_last_accepted_flip_tick_by_peer.get(sender_peer_id, -100000))
		if input_tick - prior_flip_tick < roundi(Motion.FLIP_COOLDOWN_SECONDS * 60.0) - 1:
			diagnostics.record_event("input_physics_warning", {"peer_id": sender_peer_id, "reason": "gravity_cooldown_short", "tick": input_tick})
		_last_accepted_flip_tick_by_peer[sender_peer_id] = input_tick
	input_audit_received.emit(sender_peer_id, audit.duplicate(true))

func _on_terminal_rpc(sender_peer_id: int, report: Dictionary) -> void:
	if not _active or str(session.get("role", "")) != "host" or not _is_roster_peer(sender_peer_id):
		return
	if not _packet_session_error(report, false).is_empty():
		return
	var reason := ValidationScript.validate_terminal(report, _round_id, sender_peer_id)
	if not reason.is_empty():
		diagnostics.record_event("terminal_rejected", {"peer_id": sender_peer_id, "reason": reason})
		return
	_commit_terminal(sender_peer_id, report)

func _on_world_interaction_rpc(sender_peer_id: int, request: Dictionary) -> void:
	if not _active or str(session.get("role", "")) != "host" or not _is_roster_peer(sender_peer_id):
		return
	if not _packet_session_error(request, false).is_empty():
		return
	if str(request.get("round_id", "")) != _round_id or str(request.get("request_id", "")).is_empty():
		return
	_process_world_interaction(sender_peer_id, request)

func _on_control_rpc(sender_peer_id: int, kind: String, payload: Dictionary) -> void:
	if not _active:
		return
	if not _packet_session_error(payload, kind in ["PREPARE_ROUND", "RETURN_TO_LOBBY"]).is_empty():
		return
	if str(session.get("role", "")) == "host":
		if sender_peer_id != 1 and (not _is_roster_peer(sender_peer_id) or kind not in ["PREPARED", "START_ACK", "CLOCK_PING", "HEARTBEAT", "WORLD_EVENT_ACK", "RESULT_ACK", "TERMINAL_ACK", "WORLD_HASH"]):
			return
		_handle_host_control(sender_peer_id, kind, payload)
	else:
		if sender_peer_id != 1:
			return
		_handle_guest_control(kind, payload)

func _handle_host_control(sender_peer_id: int, kind: String, payload: Dictionary) -> void:
	if str(payload.get("round_id", "")) != _round_id and kind not in ["CLOCK_PING", "HEARTBEAT"]:
		return
	match kind:
		"PREPARED":
			_round_coordinator.acknowledge_prepared(sender_peer_id, _round_id, Time.get_ticks_usec())
		"START_ACK":
			_round_coordinator.acknowledge_start(sender_peer_id, _round_id, Time.get_ticks_usec())
		"CLOCK_PING":
			var received := Time.get_ticks_usec()
			send_control(sender_peer_id, "CLOCK_PONG", {"client_sent_usec": int(payload.get("client_sent_usec", 0)), "host_received_usec": received, "host_sent_usec": Time.get_ticks_usec()})
		"HEARTBEAT":
			_last_heartbeat_usec[sender_peer_id] = Time.get_ticks_usec()
		"WORLD_EVENT_ACK":
			var ack_revision := int(payload.get("world_revision", -1))
			_world_event_acks[sender_peer_id] = maxi(int(_world_event_acks.get(sender_peer_id, 0)), ack_revision)
		"RESULT_ACK":
			if str(payload.get("result_id", "")) == str(_committed_result.get("result_id", "")):
				_result_acks[sender_peer_id] = true
		"TERMINAL_ACK":
			var key := "%d:%d" % [int(payload.get("owner_peer_id", -1)), sender_peer_id]
			if _terminal_delivery_pending.has(key) and str(_terminal_delivery_pending[key].report.get("event_id", "")) == str(payload.get("event_id", "")):
				_terminal_delivery_pending.erase(key)
		"WORLD_HASH":
			_receive_world_hash(sender_peer_id, payload)
	control_received.emit(sender_peer_id, kind, payload.duplicate(true))

func _handle_guest_control(kind: String, payload: Dictionary) -> void:
	match kind:
		"PREPARE_ROUND":
			var incoming_generation := int(payload.get("lobby_generation", -1))
			var current_generation := int(room_state.get("lobby_generation", -2))
			if str(payload.get("manifest_hash", "")) != str(room_state.get("manifest_hash", "")) or incoming_generation < current_generation or incoming_generation > current_generation + 1:
				send_control(1, "PREPARE_REJECTED", {"round_id": str(payload.get("round_id", "")), "reason": "room_revision_mismatch"})
				return
			room_state["lobby_generation"] = incoming_generation
			room_state["phase"] = "PREPARING_COURSE"
			_round_id = str(payload.get("round_id", ""))
			session["round_id"] = _round_id
			session["roster_revision"] = incoming_generation
			var descriptor := payload.duplicate(true)
			descriptor.merge({"room_id": str(room_state.get("room_id", "")), "room_session_id": str(room_state.get("room_session_id", "")), "seed": int(room_state.get("seed", 1)), "course_length_px": int(room_state.get("course_length_px", 45000)), "players": room_state.get("members", []).duplicate(true)}, true)
			if _round_coordinator.receive_prepare_as_guest(descriptor):
				round_prepare_requested.emit(descriptor)
		"COMMIT_START":
			if not _round_coordinator.receive_commit_as_guest(payload):
				round_failed.emit("The start commit was invalid or the guest clock is not synchronized.")
		"CANCEL_START":
			_round_coordinator.cancel(str(payload.get("reason", "host_cancelled")))
		"RETURN_TO_LOBBY":
			var next_room: Dictionary = payload.get("room", {})
			if str(next_room.get("room_id", "")) != str(room_state.get("room_id", "")) or int(next_room.get("lobby_generation", -1)) != int(room_state.get("lobby_generation", 0)) + 1:
				return
			room_state = next_room.duplicate(true)
			room_state["network_mode"] = "v2"
			_round_id = ""
			terminal_status.clear()
			_result_committed = false
			_committed_result.clear()
			_result_acks.clear()
			_terminal_delivery_pending.clear()
			room_changed.emit(room_state.duplicate(true))
			_ensure_manifest()
		"CLOCK_PONG":
			_round_coordinator.clock.record_clock_exchange(int(payload.get("client_sent_usec", 0)), int(payload.get("host_received_usec", 0)), int(payload.get("host_sent_usec", 0)), Time.get_ticks_usec())
		"HEARTBEAT":
			_last_host_heartbeat_usec = Time.get_ticks_usec()
		"WORLD_COMMIT":
			var commit: Dictionary = payload
			if world_simulation != null and not commit.is_empty():
				var commit_result := world_simulation.apply_world_commit(commit)
				diagnostics.record_event("world_event_applied", {"result": commit_result, "revision": int(commit.get("world_revision", -1))})
				send_control(1, "WORLD_EVENT_ACK", {"world_revision": world_simulation.entity_ledger.revision})
			world_event_committed.emit(payload.duplicate(true))
			var transition: Dictionary = payload.get("linked_player_transition", {})
			if not transition.is_empty():
				terminal_report_received.emit(int(transition.get("owner_peer_id", -1)), transition)
		"WORLD_BASELINE":
			var baseline: Dictionary = payload.get("world_baseline", {})
			if world_simulation != null and world_simulation.apply_baseline(baseline):
				diagnostics.record_event("world_baseline_applied", {"revision": int(baseline.get("world_revision", -1))})
				send_control(1, "WORLD_EVENT_ACK", {"world_revision": int(baseline.get("world_revision", -1))})
				world_baseline_received.emit(baseline.duplicate(true))
		"WORLD_INTERACTION_RESULT":
			world_interaction_resolved.emit(str(payload.get("request_id", "")), bool(payload.get("accepted", false)), str(payload.get("reason", "")), payload.get("commit", {}))
		"TERMINAL_COMMIT":
			var terminal_owner := int(payload.get("owner_peer_id", -1))
			var terminal_event_id := str(payload.get("event_id", ""))
			if not terminal_event_id.is_empty() and not _received_terminal_events.has(terminal_event_id):
				_received_terminal_events[terminal_event_id] = true
				terminal_report_received.emit(terminal_owner, payload.duplicate(true))
			send_control(1, "TERMINAL_ACK", {"owner_peer_id": terminal_owner, "event_id": terminal_event_id})
		"RESULT_COMMIT":
			var result_id := str(payload.get("result_id", ""))
			var placements: Variant = payload.get("placements", null)
			if not result_id.is_empty() and placements is Array and placements.size() == room_state.get("members", []).size():
				results_received.emit(payload.duplicate(true))
				send_control(1, "RESULT_ACK", {"result_id": result_id})
		"WORLD_HASH":
			pass
		"HOST_ABORT":
			round_failed.emit(str(payload.get("reason", "host_disconnected")))
	control_received.emit(1, kind, payload.duplicate(true))

func mark_local_prepared() -> void:
	if not _active or _round_id.is_empty():
		return
	_local_prepare_pending = true
	if _round_coordinator.is_host or _round_coordinator.clock.is_synchronized():
		_local_prepare_pending = false
		_round_coordinator.mark_local_prepared(Time.get_ticks_usec())

func _on_round_started(round_id: String, descriptor: Dictionary) -> void:
	_round_id = round_id
	_round_roster_revision = int(descriptor.get("roster_revision", 0))
	_round_coordinator.clock.commit_start(Time.get_ticks_usec())
	_set_backend_phase("RUNNING")
	diagnostics.record_event("round_started", {"round_id": round_id, "tick": 0})
	round_started.emit(round_id, descriptor.duplicate(true))
	begin_round(round_id, _round_roster_revision)
	if world_simulation != null and current_manifest != null:
		world_simulation.configure(current_manifest)
		if is_room_owner():
			for target in connected_peer_ids():
				send_control(int(target), "WORLD_BASELINE", {"world_baseline": world_simulation.entity_ledger.baseline()})

func configure_world_simulation(world: MultiplayerV2WorldSimulation) -> void:
	world_simulation = world

func submit_local_terminal(state_name: String, reason: String, tick_value: int, world_x: float, y: float) -> void:
	if state_name not in ["dead", "finished"] or _round_id.is_empty():
		return
	var report := _session_envelope()
	report.merge({"owner_peer_id": int(session.get("local_peer_id", 1)), "simulation_tick": tick_value, "state": state_name, "reason": reason, "world_x": world_x, "y": y, "event_id": "%s:%d:%s" % [_round_id, int(session.get("local_peer_id", 1)), state_name]}, true)
	if str(session.get("role", "")) == "host":
		_commit_terminal(1, report)
	else:
		send_terminal(report)

func submit_local_world_interaction(request: Dictionary) -> void:
	if not _active or _round_id.is_empty():
		return
	if str(session.get("role", "")) == "host":
		_process_world_interaction(1, request)
	else:
		send_interaction(request)

func report_input_audit(audit: Dictionary) -> void:
	if not _active:
		return
	if str(session.get("role", "")) == "host":
		input_audit_received.emit(1, audit.duplicate(true))
	else:
		send_audit(audit)

func _commit_terminal(owner_peer_id: int, report: Dictionary) -> void:
	if terminal_status.has(owner_peer_id):
		return
	var commit := report.duplicate(true)
	commit["confirmed_at_host_usec"] = Time.get_ticks_usec()
	terminal_status[owner_peer_id] = commit
	terminal_report_received.emit(owner_peer_id, commit.duplicate(true))
	for target in connected_peer_ids():
		if int(target) != owner_peer_id:
			send_control(int(target), "TERMINAL_COMMIT", commit)
			_terminal_delivery_pending["%d:%d" % [owner_peer_id, int(target)]] = {"target": int(target), "report": commit.duplicate(true)}
	_maybe_finish_round()

func _maybe_finish_round() -> void:
	if str(session.get("role", "")) != "host" or room_state.is_empty() or _result_committed:
		return
	for member in room_state.get("members", []):
		var owner_peer := int(member.get("player_slot", 1))
		if not terminal_status.has(owner_peer):
			return
	var placements: Array[Dictionary] = []
	for report in terminal_status.values():
		placements.append({"owner_peer_id": int(report.get("owner_peer_id", -1)), "state": str(report.get("state", "dead")), "reason": str(report.get("reason", "")), "finish_tick": int(report.get("simulation_tick", -1)), "world_x": float(report.get("world_x", 0.0))})
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.state) == "finished" and str(b.state) != "finished": return true
		if str(a.state) != "finished" and str(b.state) == "finished": return false
		var a_tick := int(a.finish_tick)
		var b_tick := int(b.finish_tick)
		return a_tick < b_tick if a_tick != b_tick else int(a.owner_peer_id) < int(b.owner_peer_id)
	)
	var result := {"round_id": _round_id, "lobby_generation": _round_roster_revision, "result_revision": 1, "result_id": "%s:%d" % [_round_id, _round_roster_revision], "placements": placements, "world_revision": world_simulation.entity_ledger.revision if world_simulation != null else 0, "reason": "all_terminal"}
	_result_committed = true
	_committed_result = result.duplicate(true)
	_result_retry_elapsed = 0.0
	_set_backend_phase("FINISHED")
	results_received.emit(result)
	for target in connected_peer_ids():
		send_control(int(target), "RESULT_COMMIT", result)

func _process_result_delivery(delta: float) -> void:
	if not _result_committed or str(session.get("role", "")) != "host":
		return
	_result_retry_elapsed += delta
	if _result_retry_elapsed < 2.0:
		return
	_result_retry_elapsed = 0.0
	for target in connected_peer_ids():
		if not bool(_result_acks.get(int(target), false)):
			send_control(int(target), "RESULT_COMMIT", _committed_result)

func _process_terminal_delivery(delta: float) -> void:
	if _terminal_delivery_pending.is_empty() or str(session.get("role", "")) != "host":
		return
	_terminal_delivery_elapsed += delta
	if _terminal_delivery_elapsed < 1.0:
		return
	_terminal_delivery_elapsed = 0.0
	for pending in _terminal_delivery_pending.values():
		send_control(int(pending.target), "TERMINAL_COMMIT", pending.report)

func report_world_hash(world_tick: int, revision: int, state_hash: String) -> void:
	if not _active or world_tick < 0 or state_hash.length() != 64:
		return
	var report := {"world_tick": world_tick, "world_revision": revision, "state_hash": state_hash}
	if str(session.get("role", "")) == "host":
		_store_world_hash(1, report)
	else:
		send_control(1, "WORLD_HASH", report)

func _receive_world_hash(peer_id: int, report: Dictionary) -> void:
	var tick_value := int(report.get("world_tick", -1))
	var revision := int(report.get("world_revision", -1))
	var hash_value := str(report.get("state_hash", ""))
	if tick_value < 0 or revision < 0 or hash_value.length() != 64:
		return
	_store_world_hash(peer_id, {"world_tick": tick_value, "world_revision": revision, "state_hash": hash_value})

func _store_world_hash(peer_id: int, report: Dictionary) -> void:
	var tick_value := int(report.world_tick)
	if not _world_hash_reports.has(tick_value):
		_world_hash_reports[tick_value] = {}
	var tick_reports: Dictionary = _world_hash_reports[tick_value]
	tick_reports[peer_id] = report.duplicate(true)
	_world_hash_reports[tick_value] = tick_reports
	while _world_hash_reports.size() > 600:
		var oldest: int = int(_world_hash_reports.keys().min())
		_world_hash_reports.erase(oldest)
	if str(session.get("role", "")) != "host" or _world_divergence_reported:
		return
	var host_report: Dictionary = tick_reports.get(1, {})
	if host_report.is_empty():
		return
	for other_peer in tick_reports:
		if int(other_peer) == 1:
			continue
		var other: Dictionary = tick_reports[other_peer]
		if int(other.world_revision) != int(host_report.world_revision):
			continue
		if str(other.state_hash) != str(host_report.state_hash):
			_world_divergence_reported = true
			diagnostics.record_event("world_hash_mismatch", {"peer_id": int(other_peer), "tick": tick_value, "revision": int(host_report.world_revision), "host_hash": str(host_report.state_hash), "guest_hash": str(other.state_hash)})
			for target in connected_peer_ids():
				send_control(int(target), "HOST_ABORT", {"reason": "world_state_diverged", "world_tick": tick_value})
			round_failed.emit("V2 world simulation diverged at tick %d." % tick_value)
			_round_coordinator.cancel("world_state_diverged")
			return

func _set_backend_phase(phase: String) -> void:
	if not is_room_owner() or not has_room():
		return
	var context := "phase:%s:%d" % [phase.to_lower(), Time.get_ticks_msec()]
	_pending_lobby_context = context
	_lobby_contexts[context] = "set_phase"
	_lobby_provider.set_phase(str(room_state.get("room_id", "")), phase, _identity_adapter.token(), context)

func return_to_lobby() -> void:
	if is_room_owner() and has_room():
		var context := "return:%d" % Time.get_ticks_msec()
		_pending_lobby_context = context
		_lobby_contexts[context] = "return_to_lobby"
		_lobby_provider.return_to_lobby(str(room_state.get("room_id", "")), _identity_adapter.token(), context)
	_result_committed = false
	_committed_result.clear()
	_result_acks.clear()
	_terminal_delivery_pending.clear()
	transport_state_changed.emit("lobby", "Returned to V2 lobby.")

func _process_world_interaction(owner_peer_id: int, request: Dictionary) -> void:
	var request_id := str(request.get("request_id", ""))
	if request_id.is_empty() or int(request.get("owner_peer_id", -1)) != owner_peer_id or str(request.get("round_id", "")) != _round_id:
		return
	if _interaction_results.has(request_id):
		if owner_peer_id != 1:
			send_control(owner_peer_id, "WORLD_INTERACTION_RESULT", _interaction_results[request_id])
		return
	for pending in _pending_interactions:
		if str(pending.request.get("request_id", "")) == request_id:
			return
	_pending_interactions.append({"owner_peer_id": owner_peer_id, "request": request.duplicate(true), "received_usec": Time.get_ticks_usec()})
	diagnostics.record_event("world_claim_queued", {"peer_id": owner_peer_id, "entity_id": str(request.get("entity_id", "")), "tick": int(request.get("simulation_tick", -1))})

func _drain_interaction_claims() -> void:
	if _pending_interactions.is_empty():
		return
	var now := Time.get_ticks_usec()
	var ready: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for claim in _pending_interactions:
		if now - int(claim.received_usec) >= BARREL_CLAIM_BATCH_USEC:
			ready.append(claim)
		else:
			pending.append(claim)
	_pending_interactions = pending
	if ready.is_empty():
		return
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var request_a: Dictionary = a.request
		var request_b: Dictionary = b.request
		var tick_a := int(request_a.get("simulation_tick", -1))
		var tick_b := int(request_b.get("simulation_tick", -1))
		if tick_a != tick_b:
			return tick_a < tick_b
		var peer_a := int(a.owner_peer_id)
		var peer_b := int(b.owner_peer_id)
		return peer_a < peer_b if peer_a != peer_b else str(request_a.request_id) < str(request_b.request_id)
	)
	for claim in ready:
		_decide_world_interaction(int(claim.owner_peer_id), claim.request)

func _decide_world_interaction(owner_peer_id: int, request: Dictionary) -> void:
	var request_id := str(request.get("request_id", ""))
	if request_id.is_empty() or int(request.get("owner_peer_id", -1)) != owner_peer_id or str(request.get("round_id", "")) != _round_id:
		return
	if _interaction_results.has(request_id):
		if owner_peer_id != 1:
			send_control(owner_peer_id, "WORLD_INTERACTION_RESULT", _interaction_results[request_id])
		return
	var response := {"request_id": request_id, "accepted": false, "reason": "invalid_contact", "commit": {}}
	if world_simulation == null or str(request.get("action", "")) != "lethal_contact":
		response.reason = "world_unavailable"
	else:
		if not world_simulation.entity_ledger.is_active(str(request.get("entity_id", "")), int(request.get("incarnation", 1))):
			response.reason = "already_consumed"
			response["world_revision"] = world_simulation.entity_ledger.revision
			_interaction_results[request_id] = response.duplicate(true)
			if owner_peer_id != 1:
				send_control(owner_peer_id, "WORLD_INTERACTION_RESULT", response)
			return
		var requested_tick := int(request.get("simulation_tick", -1))
		var contact_state := {"world_x": float(request.get("world_x", NAN)), "y": float(request.get("y", NAN)), "gravity_direction": int(request.get("gravity_direction", 1))}
		var in_history := requested_tick >= world_simulation.tick - 120 and requested_tick <= world_simulation.tick
		var finite_position := is_finite(float(contact_state.world_x)) and is_finite(float(contact_state.y)) and int(contact_state.gravity_direction) in [-1, 1]
		var contact := world_simulation.player_contact_at(contact_state, requested_tick) if in_history and finite_position else {}
		if str(contact.get("kind", "")) == "shared_interaction" and str(contact.get("entity_id", "")) == str(request.get("entity_id", "")):
			var transition := {"owner_peer_id": owner_peer_id, "round_id": _round_id, "simulation_tick": int(request.get("simulation_tick", 0)), "state": "dead", "reason": "barrel_contact", "world_x": float(request.get("world_x", 0.0)), "y": float(request.get("y", 0.0)), "event_id": "%s:%d:barrel" % [_round_id, owner_peer_id]}
			response = DestructibleRulesScript.host_commit(world_simulation.entity_ledger, request, transition)
			if bool(response.get("accepted", false)):
				var commit: Dictionary = response.commit
				commit["linked_player_transition"] = transition
				commit["owner_peer_id"] = owner_peer_id
				world_simulation.apply_world_commit(commit)
				terminal_status[owner_peer_id] = transition.duplicate(true)
				terminal_report_received.emit(owner_peer_id, transition.duplicate(true))
				world_event_committed.emit(commit.duplicate(true))
				for target in connected_peer_ids():
					send_control(int(target), "WORLD_COMMIT", commit)
				_maybe_finish_round()
			else:
				response["reason"] = "already_consumed"
				response["world_revision"] = world_simulation.entity_ledger.revision
	_interaction_results[request_id] = response.duplicate(true)
	world_interaction_received.emit(owner_peer_id, request.duplicate(true))
	if owner_peer_id != 1:
		send_control(owner_peer_id, "WORLD_INTERACTION_RESULT", response)

func _ensure_manifest() -> void:
	if room_state.is_empty():
		return
	var expected_seed := int(room_state.get("seed", 1))
	var expected_length := int(room_state.get("course_length_px", 45000))
	var expected_generator := int(room_state.get("generator_version", CourseGeneratorScript.GENERATOR_VERSION))
	if current_manifest == null or current_manifest.seed_value != expected_seed or current_manifest.course_length_px != expected_length or current_manifest.generator_version != expected_generator:
		var builder := ManifestBuilderScript.new()
		var built: Dictionary = builder.build(expected_seed, expected_length, expected_generator)
		if built.get("manifest") == null:
			lobby_request_finished.emit("manifest", false, str(built.get("error", "Could not build course manifest.")))
			return
		current_manifest = built.manifest
	var local_hash := str(current_manifest.manifest_hash)
	var expected_hash := str(room_state.get("manifest_hash", ""))
	if is_room_owner() and expected_hash.is_empty():
		if _manifest_action_pending == "set_manifest":
			return
		_manifest_action_pending = "set_manifest"
		var context := "manifest:%d" % Time.get_ticks_msec()
		_pending_lobby_context = context
		_lobby_contexts[context] = "set_manifest"
		_lobby_provider.set_manifest(str(room_state.room_id), int(room_state.seed), int(room_state.course_length_px), local_hash, _identity_adapter.token(), context)
	elif expected_hash.is_empty():
		# A guest can join before the owner has published the room manifest. This
		# is a normal startup state, not a hash mismatch; a later room refresh
		# will retry once the owner's hash is available.
		return
	elif expected_hash == local_hash:
		if str(_member_for_user(identity_user_id).get("loaded_manifest_hash", "")) != expected_hash:
			if _manifest_action_pending == "ack_manifest":
				return
			_manifest_action_pending = "ack_manifest"
			var context := "ack_manifest:%d" % Time.get_ticks_msec()
			_pending_lobby_context = context
			_lobby_contexts[context] = "ack_manifest"
			_lobby_provider.ack_manifest(str(room_state.room_id), local_hash, _identity_adapter.token(), context)
	else:
		lobby_request_finished.emit("manifest", false, tr("This client generated a different V2 course hash."))

func _is_roster_peer(peer_id: int) -> bool:
	if peer_id == 1 and is_room_owner():
		return true
	for member in room_state.get("members", []):
		var expected := int(member.get("player_slot", 1))
		if expected == peer_id:
			return true
	return false

func _session_envelope() -> Dictionary:
	return {"network_mode": "v2", "protocol_version": 1, "room_id": str(room_state.get("room_id", "")), "room_session_id": str(room_state.get("room_session_id", "")), "lobby_generation": int(room_state.get("lobby_generation", 0)), "round_id": _round_id}

func _packet_session_error(packet: Dictionary, allow_next_generation: bool) -> String:
	if str(packet.get("network_mode", "")) != "v2" or int(packet.get("protocol_version", -1)) != 1:
		return "protocol_mismatch"
	for field in ["room_id", "room_session_id"]:
		if str(packet.get(field, "")) != str(room_state.get(field, "")):
			return "%s_mismatch" % field
	var expected_generation := int(room_state.get("lobby_generation", -1))
	var packet_generation := int(packet.get("lobby_generation", -2))
	if packet_generation != expected_generation and not (allow_next_generation and packet_generation == expected_generation + 1):
		return "lobby_generation_mismatch"
	if not _round_id.is_empty() and str(packet.get("round_id", "")) != _round_id and not allow_next_generation:
		return "round_mismatch"
	return ""

func _on_peer_connected(peer_id: int) -> void:
	diagnostics.increment_metric("peer_connected_events")
	_disconnect_since_usec.erase(peer_id)
	_last_reconnect_attempt_usec.erase(peer_id)
	_last_heartbeat_usec[peer_id] = Time.get_ticks_usec()
	diagnostics.record_event("peer_connected", {"peer_id": peer_id})
	transport_state_changed.emit("connected", "Peer %d connected." % peer_id)
	if is_room_owner() and _active and world_simulation != null and not _round_id.is_empty():
		send_control(peer_id, "WORLD_BASELINE", {"world_baseline": world_simulation.entity_ledger.baseline()})

func _on_peer_disconnected(peer_id: int) -> void:
	diagnostics.increment_metric("peer_disconnected_events")
	_disconnect_since_usec[peer_id] = Time.get_ticks_usec()
	_last_reconnect_attempt_usec[peer_id] = Time.get_ticks_usec()
	_restart_peer_link(peer_id)
	diagnostics.record_event("peer_disconnected", {"peer_id": peer_id})
	transport_state_changed.emit("disconnected", "Peer %d disconnected." % peer_id)

func _restart_peer_link(peer_id: int) -> void:
	if _webrtc_transport == null:
		return
	var user_id := ""
	var initiate_offer := not is_room_owner()
	if peer_id == 1 and not is_room_owner():
		user_id = str(room_state.get("owner_user_id", ""))
	else:
		for member in room_state.get("members", []):
			if int(member.get("player_slot", -1)) == peer_id:
				user_id = str(member.get("user_id", ""))
				break
	if not user_id.is_empty():
		_webrtc_transport.restart_peer(user_id, initiate_offer)

func _check_disconnect_grace() -> void:
	if _round_coordinator.state != RoundCoordinatorScript.State.RUNNING:
		return
	var now := Time.get_ticks_usec()
	var connected := connected_peer_ids()
	if str(session.get("role", "")) == "host":
		for member in room_state.get("members", []):
			var peer_id := int(member.get("player_slot", 1))
			var heartbeat_fresh := now - int(_last_heartbeat_usec.get(peer_id, -1_000_000_000)) < 3_000_000
			if peer_id == 1 or terminal_status.has(peer_id) or (peer_id in connected and heartbeat_fresh):
				_disconnect_since_usec.erase(peer_id)
				continue
			if not _disconnect_since_usec.has(peer_id):
				_disconnect_since_usec[peer_id] = now
				continue
			if now - int(_last_reconnect_attempt_usec.get(peer_id, -1_000_000_000)) >= 2_000_000:
				_last_reconnect_attempt_usec[peer_id] = now
				_restart_peer_link(peer_id)
			if now - int(_disconnect_since_usec[peer_id]) >= DISCONNECT_GRACE_USEC:
				var report := {"round_id": _round_id, "owner_peer_id": peer_id, "simulation_tick": _last_seen_tick_by_peer.get(peer_id, 0), "state": "disconnected", "reason": "connection_grace_expired", "event_id": "%s:%d:disconnected" % [_round_id, peer_id]}
				diagnostics.record_event("peer_marked_disconnected", {"peer_id": peer_id, "grace_usec": now - int(_disconnect_since_usec[peer_id])})
				_commit_terminal(peer_id, report)
	else:
		var host_heartbeat_fresh := _last_host_heartbeat_usec >= 0 and now - _last_host_heartbeat_usec < 3_000_000
		if 1 in connected and host_heartbeat_fresh:
			_disconnect_since_usec.erase(1)
			return
		if not _disconnect_since_usec.has(1):
			_disconnect_since_usec[1] = now
		if now - int(_last_reconnect_attempt_usec.get(1, -1_000_000_000)) >= 2_000_000:
			_last_reconnect_attempt_usec[1] = now
			_restart_peer_link(1)
		if now - int(_disconnect_since_usec[1]) >= DISCONNECT_GRACE_USEC:
			round_failed.emit("The V2 host was disconnected beyond the reconnect grace period.")
			_round_coordinator.cancel("host_disconnected")

func connected_peer_ids() -> PackedInt32Array:
	var connected := PackedInt32Array()
	if webrtc_peer == null:
		return connected
	var peer_states: Dictionary = webrtc_peer.get_peers()
	for peer_id in peer_states:
		var peer_state: Variant = peer_states[peer_id]
		if peer_state is Dictionary and bool(peer_state.get("connected", false)):
			connected.append(int(peer_id))
	return connected

func is_active() -> bool:
	return _active

func close_session(reason: String = "left_room") -> void:
	if webrtc_peer != null:
		webrtc_peer.close()
		webrtc_peer = null
	if network_api != null:
		network_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_active = false
	_sample_accumulator = 0.0
	if not session.is_empty():
		diagnostics.record_event("session_closed", {"reason": reason})
	session.clear()
	session_changed.emit({})
	transport_state_changed.emit("disconnected", reason)

func set_session_as_active_for_testing(descriptor: Dictionary) -> void:
	activate_client_session(descriptor)
