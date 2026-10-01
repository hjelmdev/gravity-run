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
const RaceResults := preload("res://systems/race_results.gd")
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
signal start_failure_changed(message: String)
signal world_event_committed(commit: Dictionary)
signal world_baseline_received(baseline: Dictionary)
signal world_interaction_resolved(request_id: String, accepted: bool, message: String, commit: Dictionary)
signal results_received(result: Dictionary)
signal lobby_returned
signal membership_removed(reason: String)

const V2_GAME_VERSION := "2.1.20260930.4"
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
var _lobby_request_meta: Dictionary = {}
var _lobby_request_sequence := 0
var _lobby_poll_elapsed := 0.0
var _room_refresh_requested_again := false
var _last_sample_by_peer: Dictionary = {}
var _last_seen_tick_by_peer: Dictionary = {}
var _last_sample_state_by_peer: Dictionary = {}
var _last_input_sequence_by_peer: Dictionary = {}
var _last_accepted_flip_tick_by_peer: Dictionary = {}
var _round_id := ""
var _round_roster_revision := 0
var current_manifest: Resource
var _random_course_each_round := true
var _course_seed_room_id := ""
var _course_seed_lobby_cycle := -1
var _pending_course_seed := -1
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
var _reconnect_generation: Dictionary = {}
var _reconnect_sync_pending: Dictionary = {}
var _reconnect_sync_requests: Dictionary = {}
var _reconnect_sync_since_usec: Dictionary = {}
var _reconnect_sync_elapsed := 0.0
var _sync_request_ids: Dictionary = {}
var _session_confirmed_peers: Dictionary = {}
var _ever_confirmed_peers: Dictionary = {}
var _return_in_flight := false
var _pending_round_failure: Dictionary = {}
var _pending_round_failure_since_usec := -1
var _received_round_failures: Dictionary = {}
var _round_failure_retry_elapsed := 0.0
var _round_abort_pending: Dictionary = {}
var _round_abort_retry_elapsed := 0.0
var _round_abort_return_pending := false
var _round_abort_started_usec := -1
var _result_retry_elapsed := 0.0
var _result_committed := false
var _committed_result: Dictionary = {}
var _result_acks: Dictionary = {}
var _terminal_delivery_pending: Dictionary = {}
var _terminal_delivery_elapsed := 0.0
var _received_terminal_events: Dictionary = {}
var _world_hash_reports: Dictionary = {}
var _world_divergence_reported := false
var _prepare_scene_requested_round_id := ""
var _peer_mapping_verified_sample := false
var _last_host_heartbeat_usec := -1
var _start_attempt_id := ""
var _start_in_flight := false
var _room_refresh_in_flight := false
var last_start_failure := ""
const DISCONNECT_GRACE_USEC := 10_000_000
const HEARTBEAT_INTERVAL_SECONDS := 1.0
const PEER_LIVENESS_TIMEOUT_USEC := 3_000_000
const RECONNECT_RETRY_USEC := 2_000_000

static func liveness_restart_due(now_usec: int, last_contact_usec: int, last_attempt_usec: int) -> bool:
	if last_contact_usec < 0 or now_usec - last_contact_usec < PEER_LIVENESS_TIMEOUT_USEC:
		return false
	if last_attempt_usec >= 0 and now_usec - last_attempt_usec < RECONNECT_RETRY_USEC:
		return false
	# Fresh contact preserves a healthy peer across round transitions; a stale
	# peer can be restarted even if the ICE state still says connected.
	return true

static func reconnect_world_revision_matches(expected_revision: int, actual_revision: int) -> bool:
	return expected_revision >= 0 and actual_revision == expected_revision

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
		diagnostics.session["phase"] = str(room_state.get("phase", ""))
		diagnostics.session["lobby_generation"] = int(room_state.get("lobby_generation", -1))
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
		_process_reconnect_sync(delta)
		_drain_interaction_claims()
		_process_result_delivery(delta)
		_process_terminal_delivery(delta)
		_process_round_failure_delivery(delta)
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
	_lobby_provider.request_timing.connect(_on_lobby_request_timing)
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
	_webrtc_transport.transport_mutation.connect(_on_transport_mutation)
	_webrtc_transport.roster_refresh_requested.connect(_on_signal_roster_refresh_requested)
	_webrtc_transport.signal_diagnostic.connect(_on_signal_diagnostic)
	add_child(_webrtc_transport)
	_round_coordinator.control_requested.connect(send_control)
	_round_coordinator.round_started.connect(_on_round_started)
	_round_coordinator.round_failed.connect(_on_coordinator_round_failed)
	_round_coordinator.all_prepare_received.connect(_on_coordinator_prepare_received)
	var inventory_service := get_node_or_null("/root/InventoryService")
	if inventory_service != null:
		var inventory_callback := Callable(self, "_on_inventory_state_changed")
		if not inventory_service.is_connected("state_changed", inventory_callback):
			inventory_service.connect("state_changed", inventory_callback)

func has_room() -> bool:
	return not room_state.is_empty()

func is_room_owner() -> bool:
	return has_room() and str(room_state.get("owner_user_id", "")) == identity_user_id

func get_members() -> Array:
	return room_state.get("members", [])

func get_active_round_descriptor() -> Dictionary:
	return _round_coordinator.round_descriptor.duplicate(true)

func get_active_round_roster() -> Array:
	var players: Variant = _round_coordinator.round_descriptor.get("players", [])
	return players.duplicate(true) if players is Array and not players.is_empty() else get_members().duplicate(true)

func local_peer_mapping_valid() -> bool:
	if not _active or network_api == null:
		return false
	var local_peer_id := int(session.get("local_peer_id", -1))
	var member_slot := int(_member_for_user(identity_user_id).get("player_slot", -1))
	return local_peer_id == network_api.get_unique_id() and (str(session.get("role", "")) == "host" and local_peer_id == 1 and member_slot == 1 or str(session.get("role", "")) == "guest" and local_peer_id == member_slot and member_slot >= 2 and member_slot <= MAX_PLAYERS)

func create_room(display_name: String, is_public: bool = true, seed_value: int = -1, course_length_px: int = 45000) -> void:
	if not has_room():
		_random_course_each_round = seed_value < 1
	_begin_identity_action("create_room", {"display_name": display_name, "is_public": is_public, "seed": seed_value if seed_value >= 1 else randi_range(1, 2_147_483_647), "course_length_px": course_length_px})

func join_room(room_code: String, display_name: String) -> void:
	_begin_identity_action("join_room", {"room_code": room_code.strip_edges().to_upper(), "display_name": display_name})

func list_public_rooms() -> void:
	_begin_identity_action("list_rooms", {})

func refresh_room() -> void:
	if not has_room():
		return
	if _room_refresh_in_flight:
		_room_refresh_requested_again = true
		return
	_room_refresh_in_flight = true
	_room_refresh_requested_again = false
	_begin_identity_action("refresh_room", {"room_id": str(room_state.get("room_id", "")), "loadout_hash": local_loadout_hash()})

func _on_inventory_state_changed(_state: Dictionary, _stale: bool, _error_message: String) -> void:
	if has_room() and str(room_state.get("phase", "")) == "OPEN":
		refresh_room()

func local_loadout_hash() -> String:
	var signature := "fallback:10000:10000"
	var inventory_service := get_node_or_null("/root/InventoryService")
	var player_profile := get_node_or_null("/root/PlayerProfile")
	if inventory_service != null and player_profile != null:
		var snapshot: Resource = inventory_service.call("create_run_loadout_snapshot", player_profile.call("get_character_stats"))
		if snapshot != null and snapshot.has_method("is_valid") and bool(snapshot.call("is_valid")) and snapshot.has_method("get_loadout_signature"):
			signature = str(snapshot.call("get_loadout_signature"))
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(signature.to_utf8_buffer())
	return hashing.finish().hex_encode()

func set_ready(ready: bool) -> void:
	if has_room() and local_peer_mapping_valid():
		var loadout_hash := local_loadout_hash()
		if loadout_hash.is_empty():
			lobby_request_finished.emit("set_ready", false, tr("Could not verify your current gameplay loadout."))
			return
		_clear_start_failure()
		_begin_identity_action("set_ready", {"room_id": str(room_state.get("room_id", "")), "ready": ready, "lobby_cycle": int(room_state.get("lobby_cycle", 0)), "content_revision": int(room_state.get("content_revision", 0)), "loadout_hash": loadout_hash})

func set_skin_id(skin_id: int) -> void:
	if has_room():
		_begin_identity_action("set_skin", {"room_id": str(room_state.get("room_id", "")), "skin_id": posmod(skin_id, 4)})

func request_start() -> void:
	if _start_in_flight:
		diagnostics.record_event("start_click_ignored", {"attempt_id": _start_attempt_id, "reason": "attempt_already_in_flight"})
		return
	_start_attempt_id = Crypto.new().generate_random_bytes(12).hex_encode()
	_start_in_flight = true
	last_start_failure = ""
	diagnostics.session["attempt_id"] = _start_attempt_id
	diagnostics.record_event("start_attempt_requested", {"attempt_id": _start_attempt_id, "phase": str(room_state.get("phase", "")), "generation": int(room_state.get("lobby_generation", -1)), "room_id": str(room_state.get("room_id", ""))})
	if not is_room_owner():
		_fail_start_attempt("not_host", tr("Only the host can start the round."), false)
		return
	var blockers := get_start_blockers()
	if not blockers.is_empty():
		_fail_start_attempt("blocked:" + ",".join(blockers), tr("Multiplayer cannot start yet: %s") % ", ".join(blockers), false)
		return
	var local_hash := local_loadout_hash()
	if local_hash.is_empty() or str(_member_for_user(identity_user_id).get("loadout_hash", "")) != local_hash:
		refresh_room()
		_fail_start_attempt("local_loadout_changed", tr("Your gameplay loadout changed. Confirm it again before starting."), false)
		return
	_begin_identity_action("prepare_round", {"room_id": str(room_state.get("room_id", "")), "attempt_id": _start_attempt_id})

func _fail_start_attempt(reason: String, display_message: String, notify_peers: bool = true) -> void:
	var attempt_id := _start_attempt_id
	last_start_failure = "%s (attempt %s)" % [reason, attempt_id.left(8)]
	_start_in_flight = false
	diagnostics.record_event("start_attempt_failed", {"attempt_id": attempt_id, "reason": reason, "round_id": _round_id, "phase": str(room_state.get("phase", "")), "generation": int(room_state.get("lobby_generation", -1))})
	start_failure_changed.emit(last_start_failure)
	if notify_peers and is_room_owner():
		for peer_id in connected_peer_ids():
			send_control(int(peer_id), "START_ABORT", {"attempt_id": attempt_id, "reason": reason, "round_id": _round_id, "lobby_generation": int(room_state.get("lobby_generation", 0)), "manifest_hash": str(room_state.get("manifest_hash", ""))})
	lobby_request_finished.emit("prepare_round", false, display_message)

func _clear_start_failure() -> void:
	if last_start_failure.is_empty():
		return
	last_start_failure = ""
	start_failure_changed.emit("")

func get_start_blockers() -> PackedStringArray:
	var blockers := PackedStringArray()
	if not local_peer_mapping_valid():
		blockers.append("local_peer_id_mismatch")
	if not is_room_owner():
		blockers.append("not_host")
	if str(room_state.get("phase", "")) != "OPEN":
		blockers.append("room_not_open")
	if str(room_state.get("manifest_hash", "")).is_empty() or current_manifest == null:
		blockers.append("manifest_missing")
	elif str(current_manifest.manifest_hash) != str(room_state.get("manifest_hash", "")) or _manifest_action_pending == "set_manifest" or (_random_course_each_round and _course_seed_room_id == str(room_state.get("room_id", "")) and int(room_state.get("lobby_cycle", 1)) > _course_seed_lobby_cycle):
		blockers.append("course_update_pending")
	var members: Array = room_state.get("members", [])
	if members.is_empty() or members.size() > MAX_PLAYERS:
		blockers.append("player_count")
	for member in members:
		if int(member.get("returned_for_cycle", 0)) < int(room_state.get("lobby_cycle", 0)):
			blockers.append("member_not_returned:%s" % str(member.get("display_name", "Runner")))
		if not bool(member.get("is_connected", true)):
			blockers.append("member_offline:%s" % str(member.get("display_name", "Runner")))
		if not bool(member.get("is_ready", false)) or int(member.get("ready_cycle", 0)) != int(room_state.get("lobby_cycle", 0)) or int(member.get("ready_content_revision", 0)) != int(room_state.get("content_revision", 0)) or str(member.get("ready_loadout_hash", "")) != str(member.get("loadout_hash", "")):
			blockers.append("member_not_ready:%s" % str(member.get("display_name", "Runner")))
		if str(member.get("loaded_manifest_hash", "")) != str(room_state.get("manifest_hash", "")):
			blockers.append("manifest_unacknowledged:%s" % str(member.get("display_name", "Runner")))
		if int(member.get("player_slot", 1)) != 1 and (not _session_confirmed_peers.has(int(member.get("player_slot", 1))) or _reconnect_sync_pending.has(int(member.get("player_slot", 1)))):
			blockers.append("reconnect_sync_pending:%s" % str(member.get("display_name", "Runner")))
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
			lobby_request_finished.emit("connect", false, tr("Could not initialize WebRTC (code %d).") % error)
			return
		if not is_room_owner():
			activate_client_session(room_state)
			if not _active:
				lobby_request_finished.emit("connect", false, "Could not verify the guest peer slot. Rejoin the room.")
				return
	_webrtc_transport.configure(room_state, identity_user_id, webrtc_peer)
	if is_room_owner():
		_webrtc_transport.begin_connection()
	else:
		_signaling_transport.connect_room(str(room_state.get("signaling_topic", "")), _identity_adapter.token())
		_webrtc_transport.begin_connection()

func _begin_identity_action(action: String, arguments: Dictionary) -> void:
	if action in ["create_room", "join_room"] and has_room():
		lobby_request_finished.emit(action, false, tr("Leave the current room first."))
		return
	_pending_identity_action = action
	_pending_identity_arguments = arguments.duplicate(true)
	_lobby_request_sequence += 1
	_pending_lobby_context = "%s:%d:%d" % [action, Time.get_ticks_msec(), _lobby_request_sequence]
	_lobby_request_meta[_pending_lobby_context] = {
		"started_usec": Time.get_ticks_usec(),
		"attempt_id": str(arguments.get("attempt_id", _start_attempt_id if action == "prepare_round" else "")),
		"room_id": str(room_state.get("room_id", "")),
		"room_session_id": str(room_state.get("room_session_id", "")),
		"generation": int(room_state.get("lobby_generation", -1)),
		"phase": str(room_state.get("phase", ""))
	}
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
			_lobby_provider.create_room(str(arguments.display_name), bool(arguments.is_public), V2_GAME_VERSION, CourseGeneratorScript.GENERATOR_VERSION, int(arguments.seed), int(arguments.course_length_px), token, context)
		"join_room":
			_lobby_provider.join_room(str(arguments.room_code), str(arguments.display_name), V2_GAME_VERSION, CourseGeneratorScript.GENERATOR_VERSION, token, context)
		"list_rooms":
			_lobby_provider.list_rooms(token, context)
		"refresh_room":
			_lobby_provider.refresh_room(str(arguments.room_id), str(arguments.loadout_hash), token, context)
		"set_ready":
			_lobby_provider.set_ready(str(arguments.room_id), bool(arguments.ready), int(arguments.lobby_cycle), int(arguments.content_revision), str(arguments.loadout_hash), token, context)
		"set_skin":
			_lobby_provider.set_skin(str(arguments.room_id), int(arguments.skin_id), token, context)
		"leave_room":
			_lobby_provider.leave_room(str(arguments.room_id), token, context)
		"prepare_round":
			_lobby_provider.start_prepare(str(arguments.room_id), token, context)
		"return_to_lobby":
			if bool(arguments.host):
				_lobby_provider.return_to_lobby(str(arguments.room_id), int(arguments.lobby_cycle), token, context)
			else:
				_lobby_provider.return_member(str(arguments.room_id), int(arguments.lobby_cycle), token, context)
		"kick_member":
			_lobby_provider.kick_member(str(arguments.room_id), str(arguments.user_id), int(arguments.slot), int(arguments.lobby_cycle), token, context)

func _on_identity_failed(message: String, context: String) -> void:
	if context == _pending_lobby_context:
		_pending_identity_action = ""
		_pending_identity_arguments.clear()
		_lobby_request_meta.erase(context)
		if context.begins_with("refresh_room:"):
			_room_refresh_in_flight = false
			var rerun_room_refresh := _room_refresh_requested_again
			_room_refresh_requested_again = false
			if rerun_room_refresh and has_room():
				refresh_room.call_deferred()
		if context.begins_with("return_to_lobby:"):
			_return_in_flight = false
		if _start_in_flight:
			_fail_start_attempt("identity_failed:%s" % message, message, false)
		else:
			lobby_request_finished.emit("identity", false, message)

func _on_lobby_request_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	if not _lobby_contexts.has(context):
		return
	_lobby_contexts.erase(context)
	var request_meta: Dictionary = _lobby_request_meta.get(context, {})
	_lobby_request_meta.erase(context)
	var rerun_room_refresh := action == "refresh_room" and _room_refresh_requested_again
	var local_before_response := room_state.duplicate(true)
	var response_room: Dictionary = {}
	if success and data is Dictionary:
		var candidate: Variant = data.get("room", data)
		if candidate is Dictionary:
			response_room = candidate
	diagnostics.record_event("lobby_rpc_response", {"action": action, "success": success, "context": context, "attempt_id": str(request_meta.get("attempt_id", "")), "request_elapsed_usec": Time.get_ticks_usec() - int(request_meta.get("started_usec", Time.get_ticks_usec())), "generation_at_dispatch": int(request_meta.get("generation", -1)), "phase_at_dispatch": str(request_meta.get("phase", "")), "local_generation_before_apply": int(local_before_response.get("lobby_generation", -1)), "local_phase_before_apply": str(local_before_response.get("phase", "")), "response_generation": int(response_room.get("lobby_generation", -1)), "response_phase": str(response_room.get("phase", ""))})
	if action == "refresh_room":
		_room_refresh_in_flight = false
		_room_refresh_requested_again = false
	if action in ["set_manifest", "ack_manifest"]:
		_manifest_action_pending = ""
	if action == "list_rooms":
		var rooms: Array = data if data is Array else []
		public_rooms_loaded.emit(rooms, message)
		lobby_request_finished.emit(action, success, message)
		return
	if action == "leave_room":
		room_state.clear()
		_round_coordinator.reset_for_lobby()
		_round_id = ""
		room_changed.emit({})
		lobby_request_finished.emit(action, success, message)
		return
	if action == "prepare_round" and success and data is Dictionary:
		var next_room: Dictionary = data.get("room", data)
		if not _accept_room_snapshot(next_room, action, context):
			_fail_start_attempt("stale_prepare_response", tr("Multiplayer ignored an outdated prepare response. The room has a newer state."), false)
			return
		room_state = next_room.duplicate(true)
		_record_room_snapshot_applied(action, local_before_response, response_room)
		room_changed.emit(room_state.duplicate(true))
		var packed_peers := PackedInt32Array()
		for peer_id in connected_peer_ids():
			packed_peers.append(int(peer_id))
		var peers := _typed_peer_ids_from_packed(packed_peers)
		_round_id = Crypto.new().generate_random_bytes(16).hex_encode()
		session["round_id"] = _round_id
		diagnostics.session["round_id"] = _round_id
		session["roster_revision"] = int(room_state.get("lobby_generation", 0))
		var descriptor := {"attempt_id": _start_attempt_id, "round_id": _round_id, "room_id": str(room_state.get("room_id", "")), "room_session_id": str(room_state.get("room_session_id", "")), "lobby_generation": int(room_state.get("lobby_generation", 0)), "roster_revision": int(room_state.get("lobby_generation", 0)), "manifest_hash": str(room_state.get("manifest_hash", "")), "seed": int(room_state.get("seed", 1)), "course_length_px": int(room_state.get("course_length_px", 45000)), "players": room_state.get("members", []).duplicate(true)}
		descriptor["peer_map"] = _peer_map_for_roster(descriptor.players)
		var descriptor_error := _validate_round_descriptor(descriptor)
		if not descriptor_error.is_empty():
			diagnostics.record_event("host_round_descriptor_rejected", {"round_id": _round_id, "reason": descriptor_error, "generation": int(descriptor.lobby_generation), "manifest_hash": str(descriptor.manifest_hash)})
			_fail_start_attempt("round_descriptor:%s" % descriptor_error, tr("Multiplayer could not freeze the round roster: %s") % descriptor_error)
			call_deferred("return_to_lobby")
			return
		_round_roster_revision = int(descriptor.roster_revision)
		diagnostics.record_event("host_prepare_coordinator_call", {"round_id": _round_id, "state_before": _round_coordinator.state, "peer_array_typed": peers.is_typed(), "peer_ids": peers.duplicate()})
		if not _round_coordinator.prepare_as_host(descriptor, peers, Time.get_ticks_usec()):
			diagnostics.record_event("host_prepare_coordinator_rejected", {"round_id": _round_id, "state": _round_coordinator.state, "peer_array_typed": peers.is_typed(), "peer_ids": peers.duplicate()})
			_fail_start_attempt("coordinator:%s" % str(_round_coordinator.state), tr("Multiplayer could not start the round preparation."))
			call_deferred("return_to_lobby")
			return
		diagnostics.record_event("backend_prepare_accepted", {"attempt_id": _start_attempt_id, "round_id": _round_id, "phase": str(room_state.get("phase", "")), "generation": int(descriptor.lobby_generation), "room_session_id": str(descriptor.room_session_id), "manifest_hash": str(descriptor.manifest_hash), "peer_ids": Array(peers)})
		if peers.is_empty():
			_on_coordinator_prepare_received()
		lobby_request_finished.emit(action, true, "")
		return
	if success and data is Dictionary:
		var next_room: Dictionary = data.get("room", data)
		if next_room is Dictionary and not next_room.is_empty():
			if not _accept_room_snapshot(next_room, action, context):
				lobby_request_finished.emit(action, true, "Ignored an outdated room response.")
				if rerun_room_refresh and has_room():
					refresh_room.call_deferred()
				return
			if action == "kick_member":
				for old_member in local_before_response.get("members", []):
					if not old_member is Dictionary or str(old_member.get("user_id", "")) == identity_user_id:
						continue
					if _roster_contains_user(next_room.get("members", []), str(old_member.get("user_id", ""))):
						continue
					var removed_slot := int(old_member.get("player_slot", -1))
					if removed_slot > 1:
						send_control(removed_slot, "KICKED", {"reason": "host_removed_from_lobby"})
			room_state = next_room.duplicate(true)
			room_state["network_mode"] = "v2"
			_record_room_snapshot_applied(action, local_before_response, response_room)
			if action not in ["create_room", "join_room"]:
				_webrtc_transport.update_room(room_state)
			room_changed.emit(room_state.duplicate(true))
			if action in ["return_to_lobby", "return_member"]:
				_complete_lobby_return()
				_ensure_manifest()
			elif action in ["set_manifest", "refresh_room"]:
				_ensure_manifest()
			if action in ["create_room", "join_room"]:
				_round_coordinator.reset_for_lobby()
				_round_id = ""
				var maximum := maxi(1, int(room_state.get("max_players", 5)) - 1)
				var error := open_host(room_state, maximum) if is_room_owner() else configure_client_peer(int(_member_for_user(identity_user_id).get("player_slot", 1)))
				if error == OK:
					if not is_room_owner():
						activate_client_session(room_state)
					_webrtc_transport.configure(room_state, identity_user_id, webrtc_peer)
					_signaling_transport.connect_room(str(room_state.get("signaling_topic", "")), _identity_adapter.token())
					_webrtc_transport.begin_connection()
					_ensure_manifest()
					room_changed.emit(room_state.duplicate(true))
		elif action in ["set_manifest", "refresh_room", "return_to_lobby", "return_member", "kick_member"]:
			if action == "ack_manifest":
				room_changed.emit(room_state.duplicate(true))
		lobby_request_finished.emit(action, success, message)
		if action == "refresh_room" and rerun_room_refresh and has_room():
			refresh_room.call_deferred()
	else:
		if action in ["return_to_lobby", "return_member"]:
			_return_in_flight = false
		if action == "refresh_room" and message.contains("not_room_member"):
			_signaling_transport.disconnect_room()
			_webrtc_transport.close_all()
			room_state.clear()
			_active = false
			room_changed.emit({})
			membership_removed.emit(tr("The host removed you from the multiplayer lobby."))
		var display_message := message
		if action == "prepare_round" and message.contains("room_not_preparable"):
			display_message = tr("The room changed before the race could start. Lobby state refreshed.")
			refresh_room.call_deferred()
		if action == "prepare_round":
			_fail_start_attempt("backend_prepare_rejected:%s" % message, display_message, false)
		else:
			lobby_request_finished.emit(action, success, display_message)
		if action == "refresh_room" and rerun_room_refresh and has_room():
			refresh_room.call_deferred()

func _accept_room_snapshot(next_room: Dictionary, action: String, context: String) -> bool:
	var reason := room_snapshot_rejection_reason(room_state, next_room, action)
	if reason.is_empty():
		return true
	var meta: Dictionary = _lobby_request_meta.get(context, {})
	diagnostics.record_event("room_snapshot_rejected", {
		"action": action,
		"reason": reason,
		"attempt_id": str(meta.get("attempt_id", _start_attempt_id)),
		"current_generation": int(room_state.get("lobby_generation", -1)),
		"response_generation": int(next_room.get("lobby_generation", -1)),
		"current_phase": str(room_state.get("phase", "")),
		"response_phase": str(next_room.get("phase", "")),
		"context": context
	})
	return false

func _on_lobby_request_timing(action: String, context: String, queue_usec: int, request_usec: int) -> void:
	var meta: Dictionary = _lobby_request_meta.get(context, {})
	diagnostics.record_event("lobby_rpc_timing", {"action": action, "context": context, "attempt_id": str(meta.get("attempt_id", _start_attempt_id if action == "prepare_round" else "")), "queue_usec": queue_usec, "http_usec": request_usec, "generation_at_queue": int(meta.get("generation", -1)), "phase_at_queue": str(meta.get("phase", ""))})

static func room_snapshot_rejection_reason(current_room: Dictionary, next_room: Dictionary, action: String = "") -> String:
	if current_room.is_empty() or action in ["create_room", "join_room"]:
		return ""
	if str(current_room.get("room_id", "")) != str(next_room.get("room_id", "")):
		return "room_id_mismatch"
	var current_session := str(current_room.get("room_session_id", ""))
	var response_session := str(next_room.get("room_session_id", ""))
	if not current_session.is_empty() and not response_session.is_empty() and current_session != response_session:
		return "room_session_id_mismatch"
	var current_generation := int(current_room.get("lobby_generation", -1))
	var next_generation := int(next_room.get("lobby_generation", -1))
	if next_generation < current_generation:
		return "older_generation"
	var current_state_revision := int(current_room.get("state_revision", -1))
	var next_state_revision := int(next_room.get("state_revision", -1))
	if current_state_revision >= 0 and next_state_revision >= 0 and next_state_revision < current_state_revision:
		return "older_state_revision"
	if next_generation == current_generation and _phase_order(str(next_room.get("phase", ""))) < _phase_order(str(current_room.get("phase", ""))):
		return "phase_regression"
	return ""

static func _phase_order(phase: String) -> int:
	match phase:
		"OPEN": return 0
		"PREPARING_COURSE": return 1
		"RUNNING": return 2
		"FINISHED", "CLOSED": return 3
		_: return -1

func _on_signaling_state_changed(connected: bool, message: String) -> void:
	diagnostics.record_event("signaling_channel_state", {"connected": connected, "roster_revision": int(room_state.get("roster_revision", -1)), "role": str(session.get("role", ""))})
	signaling_state_changed.emit(connected, message)
	if connected and is_room_owner():
		# Host receives offers for guests and maps their roster slot to the
		# stable Godot peer id in V2WebRTCTransport.handle_signal().
		pass

func _on_signaling_message(message: Dictionary) -> void:
	_webrtc_transport.handle_signal(message)

func _on_peer_state_changed(peer_id: int, state: String, message: String) -> void:
	transport_state_changed.emit(state, "Peer %d: %s" % [peer_id, message])

func _on_transport_mutation(event: String, details: Dictionary) -> void:
	var entry := details.duplicate(true)
	entry["api_peer_id_after"] = network_api.get_unique_id() if network_api != null else -1
	entry["session_peer_id"] = int(session.get("local_peer_id", -1))
	entry["transport_connected"] = int(details.get("peer_id", -1)) in connected_peer_ids()
	diagnostics.record_event(event, entry)

func _member_for_user(user_id: String) -> Dictionary:
	for member in get_members():
		if str(member.get("user_id", "")) == user_id:
			return member
	return {}

func _roster_contains_user(members: Array, user_id: String) -> bool:
	for member in members:
		if member is Dictionary and str(member.get("user_id", "")) == user_id:
			return true
	return false

func open_host(session_descriptor: Dictionary, max_clients: int = 4) -> Error:
	if _active:
		return ERR_BUSY
	if max_clients < 1 or max_clients > MAX_PLAYERS - 1:
		return ERR_INVALID_PARAMETER
	_reset_peer_liveness()
	webrtc_peer = WebRTCMultiplayerPeer.new()
	# Extra channels_config goes here. ICE servers belong to WebRTCPeerConnection.
	var error: Error = webrtc_peer.create_server([])
	if error != OK:
		webrtc_peer = null
		transport_state_changed.emit("failed", tr("Godot could not create the WebRTC server (code %d).") % error)
		return error
	network_api.multiplayer_peer = webrtc_peer
	session = session_descriptor.duplicate(true)
	session["network_mode"] = "v2"
	session["protocol_version"] = 1
	session["role"] = "host"
	session["local_peer_id"] = 1
	_peer_mapping_verified_sample = false
	session["build_id"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	session["godot_version"] = Engine.get_version_info()
	_round_id = ""
	_active = true
	_peer_mapping_verified_sample = false
	_sample_period = 1.0 / POSITION_RATE_HZ
	_sample_accumulator = 0.0
	session["position_rate_hz"] = POSITION_RATE_HZ
	diagnostics.begin_session(session)
	if not _validate_local_peer_mapping("host_session_activated"):
		_active = false
		transport_state_changed.emit("failed", "Host peer ID does not match its room slot; rejoin before starting.")
		return FAILED
	transport_state_changed.emit("waiting", tr("Host is waiting for peer links."))
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
	_reset_peer_liveness()
	webrtc_peer = WebRTCMultiplayerPeer.new()
	var error := webrtc_peer.create_client(assigned_peer_id)
	if error != OK:
		webrtc_peer = null
		return error
	network_api.multiplayer_peer = webrtc_peer
	session["local_peer_id"] = assigned_peer_id
	diagnostics.record_event("client_peer_configured", {"assigned_peer_id": assigned_peer_id, "network_peer_id": network_api.get_unique_id()})
	return OK

func activate_client_session(session_descriptor: Dictionary) -> void:
	var assigned_peer_id := int(session.get("local_peer_id", 0))
	session = session_descriptor.duplicate(true)
	session["network_mode"] = "v2"
	session["protocol_version"] = 1
	session["role"] = "guest"
	if assigned_peer_id <= 1 and network_api != null:
		assigned_peer_id = network_api.get_unique_id()
	session["local_peer_id"] = assigned_peer_id
	session["build_id"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	session["godot_version"] = Engine.get_version_info()
	_active = true
	_peer_mapping_verified_sample = false
	_sample_period = 1.0 / POSITION_RATE_HZ
	_sample_accumulator = 0.0
	session["position_rate_hz"] = POSITION_RATE_HZ
	diagnostics.begin_session(session)
	if not _validate_local_peer_mapping("session_activated"):
		_active = false
		transport_state_changed.emit("failed", "Guest peer ID does not match its assigned room slot; reconnect before readying.")
		return
	_round_id = str(session.get("round_id", ""))
	session_changed.emit(session.duplicate(true))

func get_snapshot_rate() -> int:
	return roundi(1.0 / _sample_period)

func send_sample(sample: Dictionary) -> void:
	if not _active or rpc_endpoint == null:
		return
	if str(session.get("role", "")) == "guest" and _reconnect_sync_pending.has(1):
		return
	if not _peer_mapping_verified_sample:
		if not _validate_local_peer_mapping("first_sample"):
			if _local_transport_is_reconnecting():
				diagnostics.record_event("peer_mapping_deferred_during_reconnect", {"session_peer_id": int(session.get("local_peer_id", -1)), "network_peer_id": network_api.get_unique_id() if network_api != null else -1})
				return
			_report_round_failure("peer_mapping_mismatch")
			return
		_peer_mapping_verified_sample = true
	if _sample_accumulator < _sample_period:
		return
	_sample_accumulator = maxf(_sample_accumulator - _sample_period, 0.0)
	var packet := _session_envelope()
	packet.merge(sample, true)
	if str(session.get("role", "")) == "host":
		_on_player_sample_rpc(1, packet)
	else:
		_send_position_sample(1, packet)

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
	# A data channel may become connected just before the MultiplayerAPI peer.
	# The protocol's bounded retries deliver controls after both are ready.
	if network_api == null or network_api.multiplayer_peer == null or network_api.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _active and connected_peer_ids().has(peer_id):
		if kind in ["PREPARE_ROUND", "PREPARE_RECEIVED", "PREPARE_REJECTED", "PREPARE_FAILED", "PREPARED", "COMMIT_START", "START_ACK", "CANCEL_START", "START_ABORT", "ROUND_FAILED", "ROUND_FAILED_ACK", "ROUND_ABORT", "RECONNECT_SYNC", "RECONNECT_SYNC_ACK", "RECONNECT_SYNC_CONFIRMED", "RECONNECT_SYNC_COMPLETE"]:
			diagnostics.record_event("control_sent", {"kind": kind, "peer_id": peer_id, "attempt_id": str(payload.get("attempt_id", _start_attempt_id)), "round_id": str(payload.get("round_id", _round_id)), "generation": int(payload.get("lobby_generation", room_state.get("lobby_generation", -1))), "manifest_hash": str(payload.get("manifest_hash", ""))})
		var packet := _session_envelope()
		packet.merge(payload, true)
		rpc_endpoint.send_control(peer_id, kind, packet)

func begin_round(round_id: String, roster_revision: int) -> void:
	_round_id = round_id
	diagnostics.terminal_frames.clear()
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
	_received_round_failures.clear()
	_pending_round_failure.clear()
	_pending_round_failure_since_usec = -1
	terminal_status.clear()
	_interaction_results.clear()
	_pending_interactions.clear()
	# Contact and outage state belong to the peer session, not one individual round.
	diagnostics.record_event("round_began", {"round_id": round_id, "roster_revision": roster_revision})

func _send_position_sample(target: int, sample: Dictionary) -> void:
	diagnostics.increment_metric("sample_send_attempts")
	diagnostics.increment_metric("sample_send_attempts_target_%d" % target)
	var error: Error = rpc_endpoint.send_sample_to_peer(target, sample)
	if error == OK:
		diagnostics.increment_metric("sample_send_ok")
	else:
		diagnostics.increment_metric("sample_send_errors")
		if int(diagnostics.metrics.get("sample_send_errors", 0)) == 1:
			diagnostics.record_event("sample_send_error", {"error": error, "target": target, "channel": 0, "mode": "unreliable_ordered", "round_id": _round_id, "sequence": int(sample.get("sample_seq", -1))})

func _on_player_sample_rpc(sender_peer_id: int, sample: Dictionary) -> void:
	var local_host_sample := str(session.get("role", "")) == "host" and sender_peer_id == 1
	diagnostics.increment_metric("samples_local_host" if local_host_sample else "samples_received_network")
	diagnostics.increment_metric("samples_received_owner_%d_sender_%d" % [int(sample.get("owner_peer_id", -1)), sender_peer_id])
	if not _active or _round_id.is_empty():
		return
	var packet_error := _packet_session_error(sample, false)
	if not packet_error.is_empty():
		_record_sample_rejection(sender_peer_id, int(sample.get("owner_peer_id", -1)), {"peer_id": sender_peer_id, "reason": packet_error})
		return
	if _reconnect_sync_pending.has(sender_peer_id):
		_record_sample_rejection(sender_peer_id, int(sample.get("owner_peer_id", -1)), {"peer_id": sender_peer_id, "reason": "reconnect_session_sync_pending"})
		return
	var owner_peer := int(sample.get("owner_peer_id", -1))
	if str(session.get("role", "")) == "host":
		if sender_peer_id != 1 and owner_peer != sender_peer_id:
			_record_sample_rejection(sender_peer_id, owner_peer, {"reason": "owner_mismatch"})
			diagnostics.record_event("sample_owner_mismatch", {"sender": sender_peer_id, "owner": owner_peer})
			return
		if not _is_roster_peer(owner_peer):
			_record_sample_rejection(sender_peer_id, owner_peer, {"reason": "owner_not_in_roster"})
			return
		var previous_seq := int(_last_sample_by_peer.get(owner_peer, 0))
		var previous_tick := int(_last_seen_tick_by_peer.get(owner_peer, 0))
		var reason := ValidationScript.validate_sample(sample, _round_id, owner_peer, previous_seq, previous_tick)
		if not reason.is_empty():
			_record_sample_rejection(sender_peer_id, int(sample.get("owner_peer_id", -1)), {"peer_id": owner_peer, "reason": reason})
			return
		if sender_peer_id != 1:
			_mark_peer_contact(sender_peer_id, "SAMPLE")
		_last_sample_by_peer[owner_peer] = int(sample.sample_seq)
		_last_seen_tick_by_peer[owner_peer] = int(sample.simulation_tick)
		_audit_sample_physics(owner_peer, sample)
		_last_sample_state_by_peer[owner_peer] = sample.duplicate(true)
		diagnostics.increment_metric("samples_validated_host")
		diagnostics.increment_metric("samples_accepted_owner_%d" % owner_peer)
		player_sample_received.emit(owner_peer, sample.duplicate(true))
		for target in connected_peer_ids():
			if int(target) != owner_peer and not _reconnect_sync_pending.has(int(target)):
				_send_position_sample(int(target), sample)
		return
	if sender_peer_id != 1 or owner_peer == int(session.get("local_peer_id", -1)) or not _is_roster_peer(owner_peer):
		_record_sample_rejection(sender_peer_id, owner_peer, {"reason": "invalid_relay_owner"})
		return
	var reason := ValidationScript.validate_sample(sample, _round_id, owner_peer, int(_last_sample_by_peer.get(owner_peer, 0)), int(_last_seen_tick_by_peer.get(owner_peer, 0)))
	if not reason.is_empty():
		_record_sample_rejection(sender_peer_id, owner_peer, {"reason": reason})
		return
	_mark_peer_contact(sender_peer_id, "SAMPLE")
	_last_sample_by_peer[owner_peer] = int(sample.sample_seq)
	_last_seen_tick_by_peer[owner_peer] = int(sample.simulation_tick)
	_last_sample_state_by_peer[owner_peer] = sample.duplicate(true)
	diagnostics.increment_metric("samples_accepted_owner_%d" % owner_peer)
	diagnostics.increment_metric("samples_presented_remote")
	player_sample_received.emit(owner_peer, sample.duplicate(true))

func _record_sample_rejection(sender: int, owner: int, details: Dictionary) -> void:
	diagnostics.increment_metric("samples_rejected_owner_%d_sender_%d" % [owner, sender])
	diagnostics.increment_metric("samples_rejected_reason_%s" % str(details.get("reason", "unknown")))
	if int(diagnostics.metrics.get("samples_rejected_owner_%d_sender_%d" % [owner, sender], 0)) == 1:
		diagnostics.record_event("sample_rejected", details)

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
	if _reconnect_sync_pending.has(sender_peer_id):
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
	_mark_peer_contact(sender_peer_id, "INPUT_AUDIT")
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
	if _reconnect_sync_pending.has(sender_peer_id):
		return
	if not _packet_session_error(report, false).is_empty():
		return
	var reason := ValidationScript.validate_terminal(report, _round_id, sender_peer_id)
	if not reason.is_empty():
		diagnostics.record_event("terminal_rejected", {"peer_id": sender_peer_id, "reason": reason})
		return
	_mark_peer_contact(sender_peer_id, "TERMINAL")
	_commit_terminal(sender_peer_id, report)

func _on_world_interaction_rpc(sender_peer_id: int, request: Dictionary) -> void:
	if not _active or str(session.get("role", "")) != "host" or not _is_roster_peer(sender_peer_id):
		return
	if _reconnect_sync_pending.has(sender_peer_id):
		return
	if not _packet_session_error(request, false).is_empty():
		return
	if str(request.get("round_id", "")) != _round_id or str(request.get("request_id", "")).is_empty():
		return
	_mark_peer_contact(sender_peer_id, "WORLD_INTERACTION")
	_process_world_interaction(sender_peer_id, request)

func _on_control_rpc(sender_peer_id: int, kind: String, payload: Dictionary) -> void:
	if not _active:
		return
	var packet_error := _packet_session_error(payload, kind in ["PREPARE_ROUND", "PREPARE_REJECTED", "PREPARE_FAILED", "RETURN_TO_LOBBY", "START_ABORT", "KICKED"])
	if not packet_error.is_empty():
		diagnostics.record_event("control_rejected", {"peer_id": sender_peer_id, "kind": kind, "reason": packet_error, "attempt_id": str(payload.get("attempt_id", _start_attempt_id)), "round_id": str(payload.get("round_id", "")), "generation": int(payload.get("lobby_generation", -1)), "manifest_hash": str(payload.get("manifest_hash", ""))})
		return
	var sync_control_kinds := ["RECONNECT_SYNC", "RECONNECT_SYNC_ACK", "RECONNECT_SYNC_CONFIRMED", "RECONNECT_SYNC_COMPLETE"]
	if str(session.get("role", "")) == "host":
		if sender_peer_id != 1 and (not _is_roster_peer(sender_peer_id) or kind not in ["PREPARE_RECEIVED", "PREPARED", "PREPARE_REJECTED", "PREPARE_FAILED", "ROUND_FAILED", "ROUND_FAILED_ACK", "START_ACK", "CLOCK_PING", "HEARTBEAT", "WORLD_EVENT_ACK", "RESULT_ACK", "TERMINAL_ACK", "WORLD_HASH", "RECONNECT_SYNC", "RECONNECT_SYNC_CONFIRMED"]):
			diagnostics.record_event("control_rejected", {"peer_id": sender_peer_id, "kind": kind, "reason": "sender_or_kind_not_allowed"})
			return
		if sender_peer_id != 1 and _reconnect_sync_pending.has(sender_peer_id) and kind not in ["RECONNECT_SYNC", "RECONNECT_SYNC_CONFIRMED", "WORLD_EVENT_ACK", "ROUND_FAILED", "ROUND_FAILED_ACK"]:
			diagnostics.record_event("control_rejected", {"peer_id": sender_peer_id, "kind": kind, "reason": "reconnect_session_sync_pending"})
			return
		if sender_peer_id != 1 and not sync_control_kinds.has(kind) and not _reconnect_sync_pending.has(sender_peer_id):
			_mark_peer_contact(sender_peer_id, kind)
		_handle_host_control(sender_peer_id, kind, payload)
	else:
		if sender_peer_id != 1:
			return
		if _reconnect_sync_pending.has(1) and kind not in ["RECONNECT_SYNC_ACK", "RECONNECT_SYNC_COMPLETE", "WORLD_BASELINE", "ROUND_ABORT", "ROUND_FAILED_ACK", "RETURN_TO_LOBBY", "KICKED"]:
			diagnostics.record_event("control_rejected", {"peer_id": sender_peer_id, "kind": kind, "reason": "reconnect_session_sync_pending"})
			return
		if not sync_control_kinds.has(kind) and not _reconnect_sync_pending.has(1):
			_mark_peer_contact(sender_peer_id, kind)
		if kind == "ROUND_ABORT":
			var abort_event_id := str(payload.get("event_id", ""))
			send_control(1, "ROUND_FAILED_ACK", {"event_id": abort_event_id, "round_id": _round_id})
			if not abort_event_id.is_empty() and not _received_round_failures.has(abort_event_id):
				_received_round_failures[abort_event_id] = true
				_pending_round_failure.clear()
				_pending_round_failure_since_usec = -1
				round_failed.emit(str(payload.get("reason", "round_aborted_by_host")))
			return
		if kind == "START_ABORT":
			_start_attempt_id = str(payload.get("attempt_id", ""))
			diagnostics.session["attempt_id"] = _start_attempt_id
			last_start_failure = "%s (attempt %s)" % [str(payload.get("reason", "host_aborted_start")), _start_attempt_id.left(8)]
			diagnostics.record_event("start_attempt_failed", {"attempt_id": _start_attempt_id, "reason": str(payload.get("reason", "host_aborted_start")), "round_id": str(payload.get("round_id", "")), "phase": str(room_state.get("phase", "")), "generation": int(payload.get("lobby_generation", -1)), "reported_by": "host"})
			var incoming_generation := int(payload.get("lobby_generation", -1))
			if incoming_generation > int(room_state.get("lobby_generation", -1)):
				room_state["lobby_generation"] = incoming_generation
				room_state["phase"] = "PREPARING_COURSE"
			start_failure_changed.emit(last_start_failure)
		_handle_guest_control(kind, payload)

func _handle_host_control(sender_peer_id: int, kind: String, payload: Dictionary) -> void:
	if str(payload.get("round_id", "")) != _round_id and kind not in ["CLOCK_PING", "HEARTBEAT"]:
		return
	match kind:
		"RECONNECT_SYNC":
			var request_id := str(payload.get("sync_request_id", ""))
			if request_id.is_empty():
				return
			_sync_request_ids[sender_peer_id] = request_id
			_session_confirmed_peers.erase(sender_peer_id)
			_reconnect_sync_pending[sender_peer_id] = true
			if not _reconnect_sync_since_usec.has(sender_peer_id):
				_reconnect_sync_since_usec[sender_peer_id] = Time.get_ticks_usec()
			_reconnect_sync_requests[sender_peer_id] = payload.duplicate(true)
			var host_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
			if int(payload.get("client_world_revision", 0)) > host_revision:
				diagnostics.record_event("reconnect_sync_rejected", {"peer_id": sender_peer_id, "reason": "client_world_revision_ahead", "client_revision": int(payload.get("client_world_revision", -1)), "host_revision": host_revision, "round_id": _round_id})
				return
			_reconnect_sync_requests[sender_peer_id] = payload.duplicate(true)
			_send_reconnect_sync_response(sender_peer_id, payload)
		"RECONNECT_SYNC_CONFIRMED":
			if str(payload.get("sync_request_id", "")) != str(_sync_request_ids.get(sender_peer_id, "")) or not _sync_request_ids.has(sender_peer_id):
				return
			var host_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
			var guest_revision := int(payload.get("client_world_revision", -1))
			if str(payload.get("round_id", "")) != _round_id or not reconnect_world_revision_matches(host_revision, guest_revision):
				diagnostics.record_event("reconnect_sync_retry", {"peer_id": sender_peer_id, "reason": "world_revision_unconfirmed", "client_revision": guest_revision, "host_revision": host_revision, "client_tick": int(payload.get("client_tick", -1)), "host_tick": world_simulation.tick if world_simulation != null else 0})
				var prior_request: Dictionary = _reconnect_sync_requests.get(sender_peer_id, payload)
				_send_reconnect_sync_response(sender_peer_id, prior_request)
				return
			_note_session_confirmed(sender_peer_id, "host")
			_mark_peer_contact(sender_peer_id, "RECONNECT_SYNC_CONFIRMED")
			_reconnect_sync_pending.erase(sender_peer_id)
			_reconnect_sync_requests.erase(sender_peer_id)
			_reconnect_sync_since_usec.erase(sender_peer_id)
			send_control(sender_peer_id, "RECONNECT_SYNC_COMPLETE", {"sync_request_id": str(_sync_request_ids[sender_peer_id]), "round_id": _round_id, "world_tick": world_simulation.tick if world_simulation != null else 0, "world_revision": host_revision})
		"PREPARE_FAILED":
			if str(payload.get("attempt_id", "")) != _start_attempt_id or str(payload.get("round_id", "")) != _round_id:
				return
			var reason := str(payload.get("reason", "guest_prepare_failed"))
			diagnostics.record_event("prepare_failed_by_guest", {"attempt_id": _start_attempt_id, "round_id": _round_id, "peer_id": sender_peer_id, "phase": str(payload.get("phase", "unknown")), "reason": reason})
			_round_coordinator.cancel("guest_prepare_failed:%s" % reason)
		"ROUND_FAILED":
			var event_id := str(payload.get("event_id", ""))
			if event_id.is_empty() or str(payload.get("round_id", "")) != _round_id:
				return
			send_control(sender_peer_id, "ROUND_FAILED_ACK", {"event_id": event_id, "round_id": _round_id})
			if _received_round_failures.has(event_id):
				diagnostics.record_event("round_failure_duplicate", {"event_id": event_id, "peer_id": sender_peer_id})
				return
			_received_round_failures[event_id] = true
			var reason := str(payload.get("reason", "guest_round_failed"))
			diagnostics.record_event("round_failure_received", {"event_id": event_id, "peer_id": sender_peer_id, "reason": reason, "tick": int(payload.get("simulation_tick", -1))})
			var abort_payload := {"event_id": event_id, "round_id": _round_id, "reason": reason}
			_round_abort_pending.clear()
			for member in room_state.get("members", []):
				var target := int(member.get("player_slot", 1))
				if target != 1:
					_round_abort_pending[target] = abort_payload.duplicate(true)
			_round_abort_retry_elapsed = 1.0
			_round_abort_started_usec = Time.get_ticks_usec()
			_round_abort_return_pending = true
			_round_coordinator.cancel(reason, "running_round", false)
		"ROUND_FAILED_ACK":
			if str(session.get("role", "")) == "host":
				var pending_abort: Dictionary = _round_abort_pending.get(sender_peer_id, {})
				if str(payload.get("round_id", "")) == _round_id and str(payload.get("event_id", "")) == str(pending_abort.get("event_id", "")):
					diagnostics.record_event("round_abort_acknowledged", {"event_id": str(payload.get("event_id", "")), "peer_id": sender_peer_id})
					_round_abort_pending.erase(sender_peer_id)
			elif str(payload.get("round_id", "")) == _round_id and str(payload.get("event_id", "")) == str(_pending_round_failure.get("event_id", "")):
				diagnostics.record_event("round_failure_acknowledged", {"event_id": str(payload.get("event_id", "")), "peer_id": sender_peer_id})
				_pending_round_failure.clear()
				_pending_round_failure_since_usec = -1
		"PREPARE_REJECTED":
			var reason := str(payload.get("reason", "guest_rejected_prepare"))
			diagnostics.record_event("prepare_rejected_by_guest", {"peer_id": sender_peer_id, "round_id": _round_id, "reason": reason})
			_round_coordinator.cancel("guest_prepare_rejected:%s" % reason)
		"PREPARE_RECEIVED":
			diagnostics.record_event("prepare_rpc_ack_received", {"peer_id": sender_peer_id, "round_id": _round_id})
			_round_coordinator.acknowledge_prepare_received(sender_peer_id, _round_id)
		"PREPARED":
			diagnostics.record_event("scene_ready_received", {"peer_id": sender_peer_id, "round_id": _round_id})
			_round_coordinator.acknowledge_prepared(sender_peer_id, _round_id, Time.get_ticks_usec())
		"START_ACK":
			diagnostics.record_event("start_ack_received", {"peer_id": sender_peer_id, "round_id": _round_id})
			_round_coordinator.acknowledge_start(sender_peer_id, _round_id, Time.get_ticks_usec())
		"CLOCK_PING":
			var received := Time.get_ticks_usec()
			send_control(sender_peer_id, "CLOCK_PONG", {"client_sent_usec": int(payload.get("client_sent_usec", 0)), "host_received_usec": received, "host_sent_usec": Time.get_ticks_usec()})
		"HEARTBEAT":
			pass
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
		"RECONNECT_SYNC_ACK":
			if str(payload.get("sync_request_id", "")) != str(_sync_request_ids.get(1, "")) or not _sync_request_ids.has(1):
				return
			var expected_round := str(payload.get("round_id", ""))
			var host_revision := int(payload.get("world_revision", -1))
			var local_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
			var baseline_required := bool(payload.get("baseline_required", false))
			if expected_round != _round_id or (baseline_required and world_simulation == null) or not reconnect_world_revision_matches(host_revision, local_revision):
				diagnostics.record_event("reconnect_sync_ack_rejected", {"round_id": _round_id, "host_round_id": expected_round, "host_revision": host_revision, "local_revision": local_revision, "baseline_required": baseline_required})
				_send_reconnect_sync_request()
				return
			var progress := _local_reconnect_progress()
			diagnostics.record_event("reconnect_sync_ack_accepted", {"round_id": _round_id, "client_tick": int(progress.client_tick), "host_tick": int(payload.get("world_tick", 0)), "world_revision": local_revision})
			send_control(1, "RECONNECT_SYNC_CONFIRMED", {"sync_request_id": str(_sync_request_ids[1]), "round_id": _round_id, "client_tick": int(progress.client_tick), "client_world_tick": int(progress.world_tick), "client_world_revision": local_revision})
		"RECONNECT_SYNC_COMPLETE":
			if str(payload.get("sync_request_id", "")) != str(_sync_request_ids.get(1, "")) or not _sync_request_ids.has(1):
				return
			var host_revision := int(payload.get("world_revision", -1))
			var local_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
			if str(payload.get("round_id", "")) != _round_id or not reconnect_world_revision_matches(host_revision, local_revision):
				diagnostics.record_event("reconnect_sync_complete_rejected", {"round_id": _round_id, "host_round_id": str(payload.get("round_id", "")), "host_revision": host_revision, "local_revision": local_revision})
				_send_reconnect_sync_request()
				return
			_reconnect_sync_pending.erase(1)
			_reconnect_sync_since_usec.erase(1)
			_note_session_confirmed(1, "guest")
			_mark_peer_contact(1, "RECONNECT_SYNC_COMPLETE")
			transport_state_changed.emit("connected", tr("Host session confirmed."))
		"START_ABORT":
			pass
		"PREPARE_ROUND":
			_start_attempt_id = str(payload.get("attempt_id", ""))
			diagnostics.session["attempt_id"] = _start_attempt_id
			diagnostics.session["round_id"] = str(payload.get("round_id", ""))
			diagnostics.record_event("prepare_rpc_received", {"attempt_id": _start_attempt_id, "round_id": str(payload.get("round_id", "")), "generation": int(payload.get("lobby_generation", -1)), "manifest_hash": str(payload.get("manifest_hash", "")), "sender_peer_id": 1})
			var incoming_generation := int(payload.get("lobby_generation", -1))
			var current_generation := int(room_state.get("lobby_generation", -2))
			var reject_reason := ""
			if str(payload.get("manifest_hash", "")) != str(room_state.get("manifest_hash", "")):
				reject_reason = "manifest_hash_mismatch"
			elif incoming_generation < current_generation or incoming_generation > current_generation + 1:
				reject_reason = "room_generation_mismatch"
			else:
				reject_reason = _validate_round_descriptor(payload)
			if not reject_reason.is_empty():
				diagnostics.record_event("prepare_rpc_rejected", {"round_id": str(payload.get("round_id", "")), "reason": reject_reason, "incoming_generation": incoming_generation, "current_generation": current_generation, "incoming_manifest_hash": str(payload.get("manifest_hash", "")), "local_manifest_hash": str(room_state.get("manifest_hash", ""))})
				send_control(1, "PREPARE_REJECTED", {"round_id": str(payload.get("round_id", "")), "reason": reject_reason})
				return
			room_state["lobby_generation"] = incoming_generation
			room_state["phase"] = "PREPARING_COURSE"
			_round_id = str(payload.get("round_id", ""))
			session["round_id"] = _round_id
			diagnostics.session["round_id"] = _round_id
			session["roster_revision"] = incoming_generation
			var descriptor := payload.duplicate(true)
			if _round_coordinator.receive_prepare_as_guest(descriptor):
				diagnostics.record_event("prepare_rpc_accepted", {"round_id": _round_id, "generation": incoming_generation, "manifest_hash": str(payload.get("manifest_hash", "")), "local_peer_id": int(session.get("local_peer_id", -1))})
				send_control(1, "PREPARE_RECEIVED", {"round_id": _round_id})
				if _prepare_scene_requested_round_id != _round_id:
					_prepare_scene_requested_round_id = _round_id
					round_prepare_requested.emit(descriptor)
			else:
				diagnostics.record_event("prepare_rejected_locally", {"round_id": str(payload.get("round_id", "")), "reason": "coordinator_busy", "state": _round_coordinator.state, "current_round_id": _round_coordinator.round_id, "incoming_generation": incoming_generation, "current_generation": _round_coordinator.lobby_generation})
				send_control(1, "PREPARE_REJECTED", {"round_id": str(payload.get("round_id", "")), "reason": "coordinator_busy"})
		"COMMIT_START":
			var commit_accepted := _round_coordinator.receive_commit_as_guest(payload)
			diagnostics.record_event("commit_start_received", {"round_id": str(payload.get("round_id", "")), "accepted": commit_accepted, "coordinator_state": _round_coordinator.state, "clock_synchronized": _round_coordinator.clock.is_synchronized(), "start_at_host_usec": int(payload.get("start_at_host_usec", -1))})
			if not commit_accepted:
				round_failed.emit("The start commit was invalid or the guest clock is not synchronized.")
		"CANCEL_START":
			_round_coordinator.cancel(str(payload.get("reason", "host_cancelled")), "host_cancelled", false)
		"ROUND_FAILED_ACK":
			if str(payload.get("round_id", "")) == _round_id and str(payload.get("event_id", "")) == str(_pending_round_failure.get("event_id", "")):
				diagnostics.record_event("round_failure_acknowledged", {"event_id": str(payload.get("event_id", "")), "peer_id": 1})
				_pending_round_failure.clear()
				_pending_round_failure_since_usec = -1
		"KICKED":
			var reason := tr("The host removed you from the multiplayer lobby.")
			_signaling_transport.disconnect_room()
			_webrtc_transport.close_all()
			room_state.clear()
			_active = false
			room_changed.emit({})
			membership_removed.emit(reason)
		"RETURN_TO_LOBBY":
			diagnostics.record_event("legacy_room_return_packet_ignored", {"generation": int(room_state.get("lobby_generation", -1)), "reason": "individual_return_required"})
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
			_accept_result_commit(payload)
		"WORLD_HASH":
			pass
		"HOST_ABORT":
			round_failed.emit(str(payload.get("reason", "host_disconnected")))
	control_received.emit(1, kind, payload.duplicate(true))

func _accept_result_commit(payload: Dictionary) -> bool:
	var result_id := str(payload.get("result_id", ""))
	var placements: Variant = payload.get("placements", null)
	var roster := get_active_round_roster()
	if _round_id.is_empty() or str(payload.get("round_id", "")) != _round_id or result_id.is_empty() or not placements is Array or placements.size() != roster.size() or int(payload.get("result_revision", -1)) < 1:
		return false
	var seen: Dictionary = {}
	for row in placements:
		if not row is Dictionary:
			return false
		var peer_id := int(row.get("owner_peer_id", -1))
		if seen.has(peer_id) or int(row.get("place", 0)) < 1 or int(row.get("place", 0)) > roster.size():
			return false
		var found := false
		for member in roster:
			if int(member.get("player_slot", -2)) == peer_id:
				found = true
		if not found:
			return false
		seen[peer_id] = true
	if _result_committed and result_id != str(_committed_result.get("result_id", "")):
		return false
	if not _result_committed:
		_result_committed = true
		_committed_result = payload.duplicate(true)
		_round_coordinator.finish_round()
		room_state["phase"] = "FINISHED"
		results_received.emit(_committed_result.duplicate(true))
	send_control(1, "RESULT_ACK", {"result_id": result_id})
	return true

func mark_local_prepared() -> void:
	if not _active or _round_id.is_empty():
		return
	if not _validate_local_peer_mapping("scene_ready"):
		_round_coordinator.cancel("peer_mapping_mismatch")
		return
	diagnostics.record_event("local_scene_ready", {"round_id": _round_id, "manifest_hash": str(current_manifest.manifest_hash) if current_manifest != null else "", "player_nodes": get_active_round_roster().size(), "world_entities": world_simulation.entity_ledger.entities.size() if world_simulation != null else 0})
	_local_prepare_pending = true
	if _round_coordinator.is_host or _round_coordinator.clock.is_synchronized():
		_local_prepare_pending = false
		_round_coordinator.mark_local_prepared(Time.get_ticks_usec())

func _on_round_started(round_id: String, descriptor: Dictionary) -> void:
	_start_in_flight = false
	_round_id = round_id
	_round_roster_revision = int(descriptor.get("roster_revision", 0))
	_round_coordinator.clock.commit_start(Time.get_ticks_usec())
	_set_backend_phase("RUNNING")
	diagnostics.record_event("round_started", {"round_id": round_id, "tick": 0, "seed": int(descriptor.get("seed", room_state.get("seed", 1))), "manifest_hash": str(descriptor.get("manifest_hash", room_state.get("manifest_hash", "")))})
	round_started.emit(round_id, descriptor.duplicate(true))
	begin_round(round_id, _round_roster_revision)
	if world_simulation != null and current_manifest != null:
		world_simulation.configure(current_manifest)
		if is_room_owner():
			for target in connected_peer_ids():
				send_control(int(target), "WORLD_BASELINE", {"world_baseline": world_simulation.entity_ledger.baseline()})

func configure_world_simulation(world: MultiplayerV2WorldSimulation) -> void:
	world_simulation = world

func submit_local_terminal(state_name: String, reason: String, tick_value: int, world_x: float, y: float, gravity_direction: int = 1) -> void:
	if state_name not in ["dead", "finished"] or _round_id.is_empty():
		return
	if not _validate_local_peer_mapping("terminal"):
		_round_coordinator.cancel("peer_mapping_mismatch")
		return
	var report := _session_envelope()
	report.merge({"owner_peer_id": int(session.get("local_peer_id", 1)), "simulation_tick": tick_value, "state": state_name, "reason": reason, "world_x": world_x, "y": y, "gravity_direction": gravity_direction, "event_id": "%s:%d:%s" % [_round_id, int(session.get("local_peer_id", 1)), state_name]}, true)
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
	commit["owner_peer_id"] = owner_peer_id
	var latest: Dictionary = _last_sample_state_by_peer.get(owner_peer_id, {})
	if not commit.has("world_x"):
		commit["world_x"] = float(latest.get("world_x", current_manifest.start_x if current_manifest != null else 0.0))
	if not commit.has("y"):
		commit["y"] = float(latest.get("y", 0.0))
	if not commit.has("gravity_direction"):
		commit["gravity_direction"] = int(latest.get("gravity_direction", 1))
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
	var roster := get_active_round_roster()
	if roster.is_empty():
		return
	for member in roster:
		if not terminal_status.has(int(member.get("player_slot", 1))):
			return
	var start_x := float(current_manifest.start_x) if current_manifest != null else 0.0
	var result := RaceResults.build(roster, terminal_status.values(), start_x, "all_terminal", true)
	result.merge({"round_id": _round_id, "lobby_generation": int(room_state.get("lobby_generation", 0)), "result_revision": 1, "result_id": "%s:%d" % [_round_id, _round_roster_revision], "world_revision": world_simulation.entity_ledger.revision if world_simulation != null else 0}, true)
	_round_coordinator.finish_round()
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

func _process_round_failure_delivery(delta: float) -> void:
	if str(session.get("role", "")) == "guest" and not _pending_round_failure.is_empty():
		_round_failure_retry_elapsed += delta
		if _round_failure_retry_elapsed >= 1.0:
			_round_failure_retry_elapsed = 0.0
			var payload: Dictionary = _pending_round_failure.duplicate(true)
			diagnostics.record_event("round_failure_send_attempt", {"event_id": str(payload.get("event_id", "")), "transport_connected": 1 in connected_peer_ids(), "network_peer_id": network_api.get_unique_id() if network_api != null else -1, "round_id": _round_id})
			send_control(1, "ROUND_FAILED", payload)
		if _pending_round_failure_since_usec >= 0 and Time.get_ticks_usec() - _pending_round_failure_since_usec >= DISCONNECT_GRACE_USEC:
			diagnostics.record_event("round_failure_delivery_expired", {"event_id": str(_pending_round_failure.get("event_id", "")), "grace_usec": DISCONNECT_GRACE_USEC})
			_pending_round_failure.clear()
			_pending_round_failure_since_usec = -1
	if str(session.get("role", "")) != "host" or not _round_abort_return_pending:
		return
	_round_abort_retry_elapsed += delta
	if _round_abort_retry_elapsed < 1.0:
		return
	_round_abort_retry_elapsed = 0.0
	var now := Time.get_ticks_usec()
	for peer_id_value in _round_abort_pending.keys():
		var peer_id := int(peer_id_value)
		if peer_id in connected_peer_ids():
			send_control(peer_id, "ROUND_ABORT", _round_abort_pending[peer_id])
		if _round_abort_started_usec >= 0 and now - _round_abort_started_usec >= DISCONNECT_GRACE_USEC:
			_round_abort_pending.erase(peer_id)
	if _round_abort_pending.is_empty():
		_round_abort_return_pending = false
		return_to_lobby()

func _local_reconnect_progress() -> Dictionary:
	var latest_frame: Dictionary = diagnostics.frames.back() if not diagnostics.frames.is_empty() else {}
	var world_tick := world_simulation.tick if world_simulation != null else int(latest_frame.get("world_tick", 0))
	var world_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
	return {"round_id": _round_id, "client_tick": int(latest_frame.get("tick", 0)), "world_tick": world_tick, "world_revision": world_revision, "client_world_revision": world_revision, "sync_request_id": str(_sync_request_ids.get(1, ""))}

func _send_reconnect_sync_request() -> void:
	if not _active or str(session.get("role", "")) != "guest" or not _reconnect_sync_pending.has(1) or not connected_peer_ids().has(1):
		return
	var progress := _local_reconnect_progress()
	diagnostics.record_event("reconnect_sync_requested", {"round_id": _round_id, "client_tick": int(progress.client_tick), "world_tick": int(progress.world_tick), "world_revision": int(progress.world_revision), "api_peer_id": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1))})
	send_control(1, "RECONNECT_SYNC", progress)

func _send_reconnect_sync_response(peer_id: int, request: Dictionary) -> void:
	if world_simulation != null and not _round_id.is_empty():
		send_control(peer_id, "WORLD_BASELINE", {"world_baseline": world_simulation.entity_ledger.baseline()})
	var host_tick := world_simulation.tick if world_simulation != null else 0
	var host_revision := world_simulation.entity_ledger.revision if world_simulation != null else 0
	diagnostics.record_event("reconnect_sync_response_sent", {"peer_id": peer_id, "round_id": _round_id, "client_tick": int(request.get("client_tick", -1)), "client_world_tick": int(request.get("world_tick", -1)), "client_world_revision": int(request.get("world_revision", -1)), "host_tick": host_tick, "host_world_revision": host_revision})
	send_control(peer_id, "RECONNECT_SYNC_ACK", {"sync_request_id": str(request.get("sync_request_id", "")), "round_id": _round_id, "world_tick": host_tick, "world_revision": host_revision, "baseline_required": world_simulation != null and not _round_id.is_empty()})

func _process_reconnect_sync(delta: float) -> void:
	if _reconnect_sync_pending.is_empty():
		_reconnect_sync_elapsed = 0.0
		return
	_reconnect_sync_elapsed += delta
	if _reconnect_sync_elapsed < 1.0:
		return
	_reconnect_sync_elapsed = 0.0
	if str(session.get("role", "")) == "guest":
		_send_reconnect_sync_request()
		return
	for peer_id_value in _reconnect_sync_requests.keys():
		var peer_id := int(peer_id_value)
		if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and _reconnect_sync_pending.has(peer_id) and Time.get_ticks_usec() - int(_reconnect_sync_since_usec.get(peer_id, Time.get_ticks_usec())) >= DISCONNECT_GRACE_USEC:
			if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and not terminal_status.has(peer_id):
				var failure_report := {"round_id": _round_id, "owner_peer_id": peer_id, "simulation_tick": _last_seen_tick_by_peer.get(peer_id, 0), "state": "disconnected", "reason": "reconnect_sync_timeout", "event_id": "%s:%d:sync-timeout" % [_round_id, peer_id]}
				diagnostics.record_event("reconnect_sync_timed_out", {"peer_id": peer_id, "round_id": _round_id, "elapsed_usec": Time.get_ticks_usec() - int(_reconnect_sync_since_usec.get(peer_id, Time.get_ticks_usec()))})
				_commit_terminal(peer_id, failure_report)
			_reconnect_sync_pending.erase(peer_id)
			_reconnect_sync_requests.erase(peer_id)
			_reconnect_sync_since_usec.erase(peer_id)
			continue
		if _reconnect_sync_pending.has(peer_id) and connected_peer_ids().has(peer_id):
			_send_reconnect_sync_response(peer_id, _reconnect_sync_requests[peer_id])

func _report_round_failure(reason: String) -> void:
	if str(session.get("role", "")) != "guest" or _round_coordinator.state != RoundCoordinatorScript.State.RUNNING:
		return
	var event_id := "%s:%d:failed:%s" % [_round_id, int(session.get("local_peer_id", -1)), Crypto.new().generate_random_bytes(8).hex_encode()]
	_pending_round_failure = {"event_id": event_id, "round_id": _round_id, "attempt_id": _start_attempt_id, "peer_id": int(session.get("local_peer_id", -1)), "reason": reason}
	_pending_round_failure_since_usec = Time.get_ticks_usec()
	_round_failure_retry_elapsed = 1.0
	diagnostics.record_event("round_failure_persisted", _pending_round_failure.duplicate(true))
	_round_coordinator.state = RoundCoordinatorScript.State.CANCELLED
	round_failed.emit(reason)

func _mark_peer_contact(peer_id: int, source: String) -> void:
	var now := Time.get_ticks_usec()
	if str(session.get("role", "")) == "guest" and peer_id == 1 and network_api != null and network_api.get_unique_id() != int(session.get("local_peer_id", -1)):
		diagnostics.record_event("reconnect_session_rejected", {"peer_id": peer_id, "source": source, "api_peer_id": network_api.get_unique_id(), "session_peer_id": int(session.get("local_peer_id", -1)), "disconnect_age_usec": now - int(_disconnect_since_usec.get(peer_id, now))})
		return
	_last_heartbeat_usec[peer_id] = now
	if str(session.get("role", "")) == "guest" and peer_id == 1:
		_last_host_heartbeat_usec = now
	if _disconnect_since_usec.has(peer_id):
		diagnostics.record_event("peer_contact_restored", {"peer_id": peer_id, "source": source, "outage_usec": now - int(_disconnect_since_usec[peer_id]), "api_peer_id": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1))})
		transport_state_changed.emit("connected", "Peer %d session contact restored." % peer_id)
	_disconnect_since_usec.erase(peer_id)
	_last_reconnect_attempt_usec.erase(peer_id)

func _reset_peer_liveness() -> void:
	_disconnect_since_usec.clear()
	_last_heartbeat_usec.clear()
	_last_reconnect_attempt_usec.clear()
	_reconnect_generation.clear()
	_reconnect_sync_pending.clear()
	_reconnect_sync_requests.clear()
	_reconnect_sync_since_usec.clear()
	_reconnect_sync_elapsed = 0.0
	_sync_request_ids.clear()
	_session_confirmed_peers.clear()
	_ever_confirmed_peers.clear()
	_last_host_heartbeat_usec = -1

func _local_transport_is_reconnecting() -> bool:
	if str(session.get("role", "")) != "guest":
		return false
	return not connected_peer_ids().has(1) or _disconnect_since_usec.has(1)

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
			round_failed.emit(tr("Multiplayer world simulation diverged at tick %d.") % tick_value)
			_round_coordinator.cancel("world_state_diverged")
			return

func _set_backend_phase(phase: String) -> void:
	if not is_room_owner() or not has_room():
		return
	var context := "phase:%s:%d" % [phase.to_lower(), Time.get_ticks_msec()]
	_pending_lobby_context = context
	_lobby_contexts[context] = "set_phase"
	_lobby_provider.set_phase(str(room_state.get("room_id", "")), phase, _identity_adapter.token(), context)

func _on_coordinator_round_failed(reason: String) -> void:
	_start_in_flight = false
	last_start_failure = "%s (attempt %s)" % [reason, _start_attempt_id.left(8)]
	start_failure_changed.emit(last_start_failure)
	diagnostics.record_event("round_prepare_or_start_failed", {"attempt_id": _start_attempt_id, "reason": reason, "role": str(session.get("role", "")), "round_id": _round_id})
	round_failed.emit(reason)
	if is_room_owner() and has_room() and str(room_state.get("phase", "")) in ["PREPARING_COURSE", "RUNNING"]:
		call_deferred("return_to_lobby")

func _record_room_snapshot_applied(action: String, local_before: Dictionary, response_room: Dictionary) -> void:
	diagnostics.record_event("room_snapshot_applied", {"action": action, "local_generation_before_apply": int(local_before.get("lobby_generation", -1)), "local_phase_before_apply": str(local_before.get("phase", "")), "response_generation": int(response_room.get("lobby_generation", -1)), "response_phase": str(response_room.get("phase", "")), "local_generation_after_apply": int(room_state.get("lobby_generation", -1)), "local_phase_after_apply": str(room_state.get("phase", ""))})

func report_local_prepare_failure(reason: String, phase: String = "scene") -> void:
	var failure := reason if not reason.is_empty() else "unspecified_prepare_failure"
	diagnostics.record_event("local_prepare_failed", {"attempt_id": _start_attempt_id, "round_id": _round_id, "phase": phase, "reason": failure, "coordinator_state": _round_coordinator.state})
	_round_coordinator.cancel("local_prepare_failed:%s" % failure, phase)

func _on_coordinator_prepare_received() -> void:
	diagnostics.record_event("all_prepare_rpcs_received", {"round_id": _round_id})
	if _prepare_scene_requested_round_id != _round_id:
		_prepare_scene_requested_round_id = _round_id
		round_prepare_requested.emit(_round_coordinator.round_descriptor.duplicate(true))

static func _peer_map_for_roster(roster: Array) -> Dictionary:
	var peer_map := {}
	for member_value in roster:
		if member_value is Dictionary:
			var member: Dictionary = member_value
			# JSON numbers can arrive as floats (for example 1.0); all protocol
			# peer IDs are integers, so normalize before constructing map keys.
			peer_map[str(int(member.get("player_slot", -1)))] = str(member.get("user_id", ""))
	return peer_map

static func _typed_peer_ids_from_packed(packed_peers: PackedInt32Array) -> Array[int]:
	var typed_peers: Array[int] = []
	for peer_id in packed_peers:
		typed_peers.append(int(peer_id))
	return typed_peers

static func should_apply_return_to_lobby(current_room: Dictionary, incoming_room: Dictionary) -> bool:
	if str(incoming_room.get("room_id", "")) != str(current_room.get("room_id", "")):
		return false
	if str(incoming_room.get("room_session_id", "")) != str(current_room.get("room_session_id", "")):
		return false
	if str(incoming_room.get("phase", "")) != "OPEN":
		return false
	return int(incoming_room.get("lobby_generation", -1)) >= int(current_room.get("lobby_generation", -1))

func current_diagnostic_state() -> Dictionary:
	var direct_peers := Array(connected_peer_ids())
	var logical_peers: Array[int] = []
	for member in room_state.get("members", []):
		logical_peers.append(int(member.get("player_slot", -1)))
	var pending_direct_peers: Array[int] = []
	for peer_value in _reconnect_sync_pending.keys():
		if _is_direct_session_peer(int(peer_value)):
			pending_direct_peers.append(int(peer_value))
	return {
		"room": {"room_id": str(room_state.get("room_id", "")), "room_session_id": str(room_state.get("room_session_id", "")), "phase": str(room_state.get("phase", "")), "lobby_generation": int(room_state.get("lobby_generation", -1)), "manifest_hash": str(room_state.get("manifest_hash", ""))},
		"active_peers": direct_peers.duplicate(),
		"direct_transport_peers": direct_peers,
		"logical_roster_peers": logical_peers,
		"round_id": _round_id,
		"attempt_id": _start_attempt_id,
		"coordinator_state": _round_coordinator.state,
		"coordinator_state_name": _coordinator_state_name(_round_coordinator.state),
		"local_peer_id": int(session.get("local_peer_id", -1)),
		"role": str(session.get("role", "")),
		"confirmed_peers": _session_confirmed_peers.keys(),
		"sync_pending_peers": pending_direct_peers,
		"build_id": str(ProjectSettings.get_setting("application/config/version", ""))
	}

static func _coordinator_state_name(value: int) -> String:
	match value:
		RoundCoordinatorScript.State.IDLE: return "IDLE"
		RoundCoordinatorScript.State.PREPARING: return "PREPARING"
		RoundCoordinatorScript.State.COMMITTING: return "COMMITTING"
		RoundCoordinatorScript.State.RUNNING: return "RUNNING"
		RoundCoordinatorScript.State.CANCELLED: return "CANCELLED"
		RoundCoordinatorScript.State.FINISHED: return "FINISHED"
	return "UNKNOWN"

func _validate_round_descriptor(descriptor: Dictionary) -> String:
	if str(descriptor.get("attempt_id", "")).is_empty():
		return "attempt_id_missing"
	var round := str(descriptor.get("round_id", ""))
	var members: Variant = descriptor.get("players", null)
	var peer_map: Variant = descriptor.get("peer_map", null)
	if round.is_empty():
		return "round_id_missing"
	if str(descriptor.get("room_id", "")).is_empty():
		return "room_id_missing"
	if str(descriptor.get("room_session_id", "")).is_empty():
		return "room_session_id_missing"
	if not members is Array or members.is_empty():
		return "player_roster_missing"
	if not peer_map is Dictionary or peer_map.size() != members.size():
		return "peer_map_size_mismatch"
	for member_value in members:
		if not member_value is Dictionary:
			return "invalid_roster_member"
		var member: Dictionary = member_value
		var peer_id := int(member.get("player_slot", -1))
		if peer_id < 1 or peer_id > MAX_PLAYERS:
			return "invalid_player_slot:%s" % str(member.get("display_name", "runner"))
		if str(member.get("user_id", "")).is_empty():
			return "user_id_missing_for_slot:%d" % peer_id
		if str(peer_map.get(str(peer_id), "")) != str(member.get("user_id", "")):
			return "peer_map_mismatch_for_slot:%d" % peer_id
	return ""

func _validate_local_peer_mapping(stage: String) -> bool:
	if not _active or network_api == null:
		return false
	var network_peer_id := network_api.get_unique_id()
	var local_peer_id := int(session.get("local_peer_id", -1))
	var member := _member_for_user(identity_user_id)
	var member_slot := int(member.get("player_slot", -1))
	var valid := local_peer_id == network_peer_id and (str(session.get("role", "")) == "host" and local_peer_id == 1 and member_slot == 1 or str(session.get("role", "")) == "guest" and local_peer_id == member_slot and member_slot >= 2 and member_slot <= MAX_PLAYERS)
	diagnostics.record_event("peer_mapping_check", {"stage": stage, "valid": valid, "session_peer_id": local_peer_id, "network_peer_id": network_peer_id, "member_slot": member_slot})
	return valid

func return_to_lobby() -> void:
	if not has_room() or _return_in_flight or str(room_state.get("phase", "")) not in ["FINISHED", "PREPARING_COURSE", "RUNNING", "OPEN"]:
		return
	_return_in_flight = true
	_begin_identity_action("return_to_lobby", {"room_id": str(room_state.get("room_id", "")), "lobby_cycle": int(room_state.get("lobby_cycle", 1)), "host": is_room_owner()})

func kick_member(user_id: String, slot: int) -> void:
	if not is_room_owner() or not has_room() or slot < 2 or user_id.is_empty():
		return
	_begin_identity_action("kick_member", {"room_id": str(room_state.get("room_id", "")), "user_id": user_id, "slot": slot, "lobby_cycle": int(room_state.get("lobby_cycle", 0))})

func _complete_lobby_return() -> void:
	_return_in_flight = false
	_round_coordinator.reset_for_lobby()
	_round_id = ""
	_start_in_flight = false
	_prepare_scene_requested_round_id = ""
	terminal_status.clear()
	_result_committed = false
	_committed_result.clear()
	_result_acks.clear()
	_terminal_delivery_pending.clear()
	world_simulation = null
	diagnostics.session["round_id"] = ""
	diagnostics.record_event("return_to_lobby_applied", {"generation": int(room_state.get("lobby_generation", -1)), "attempt_id": _start_attempt_id})
	lobby_returned.emit()

func _on_signal_roster_refresh_requested(reason: String) -> void:
	if not has_room():
		return
	diagnostics.record_event("signal_roster_refresh_requested", {"reason": reason, "roster_revision": int(room_state.get("roster_revision", -1))})
	refresh_room()

func _on_signal_diagnostic(event_name: String, details: Dictionary) -> void:
	diagnostics.record_event(event_name, details)

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

func _seed_for_lobby_manifest() -> int:
	var room_seed := int(room_state.get("seed", 1))
	if not is_room_owner() or str(room_state.get("phase", "")) != "OPEN":
		return room_seed
	diagnostics.session["course_seed_mode"] = "random_each_round" if _random_course_each_round else "fixed"
	var room_id := str(room_state.get("room_id", ""))
	var cycle := int(room_state.get("lobby_cycle", 1))
	if _course_seed_room_id != room_id:
		_course_seed_room_id = room_id
		_course_seed_lobby_cycle = cycle
		_pending_course_seed = -1
	elif cycle > _course_seed_lobby_cycle:
		_course_seed_lobby_cycle = cycle
		if _random_course_each_round:
			# Choose once per new lobby cycle, excluding the previous seed.
			# Retain it while publishing/retrying; polling must not reroll it.
			_pending_course_seed = randi_range(1, 2_147_483_646)
			if _pending_course_seed >= room_seed:
				_pending_course_seed += 1
			diagnostics.record_event("course_seed_rotated", {"lobby_cycle": cycle, "previous_seed": room_seed, "seed": _pending_course_seed})
	if _pending_course_seed == room_seed:
		_pending_course_seed = -1
	return _pending_course_seed if _pending_course_seed >= 1 else room_seed

func _ensure_manifest() -> void:
	if room_state.is_empty():
		return
	var expected_seed := _seed_for_lobby_manifest()
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
	if is_room_owner() and expected_hash != local_hash:
		if _manifest_action_pending == "set_manifest":
			return
		_manifest_action_pending = "set_manifest"
		var context := "manifest:%d" % Time.get_ticks_msec()
		_pending_lobby_context = context
		_lobby_contexts[context] = "set_manifest"
		room_changed.emit(room_state.duplicate(true))
		_lobby_provider.set_manifest(str(room_state.room_id), expected_seed, expected_length, local_hash, _identity_adapter.token(), context)
	elif expected_hash.is_empty():
		# A guest can join before the owner has published the room manifest. This
		# is a normal startup state, not a hash mismatch; a later room refresh
		# will retry once the owner's hash is available.
		return
	elif expected_hash == local_hash:
		var confirmed_course := {"seed": expected_seed, "generator_version": expected_generator, "course_length_px": expected_length, "manifest_hash": local_hash}
		session.merge(confirmed_course, true)
		diagnostics.session.merge(confirmed_course, true)
		if str(_member_for_user(identity_user_id).get("loaded_manifest_hash", "")) != expected_hash:
			if _manifest_action_pending == "ack_manifest":
				return
			_manifest_action_pending = "ack_manifest"
			var context := "ack_manifest:%d" % Time.get_ticks_msec()
			_pending_lobby_context = context
			_lobby_contexts[context] = "ack_manifest"
			_lobby_provider.ack_manifest(str(room_state.room_id), local_hash, _identity_adapter.token(), context)
	else:
		lobby_request_finished.emit("manifest", false, tr("This client generated a different course hash (local %s, room %s; seed %d, generator %d, length %d px).") % [local_hash.left(12), expected_hash.left(12), expected_seed, expected_generator, expected_length])

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

func _begin_session_sync(peer_id: int, reason: String) -> void:
	if not _is_direct_session_peer(peer_id):
		_reconnect_sync_pending.erase(peer_id)
		_reconnect_sync_requests.erase(peer_id)
		_reconnect_sync_since_usec.erase(peer_id)
		_session_confirmed_peers.erase(peer_id)
		diagnostics.record_event("logical_peer_session_sync_ignored", {"peer_id": peer_id, "role": str(session.get("role", "")), "reason": reason})
		return
	var now := Time.get_ticks_usec()
	_reconnect_sync_pending[peer_id] = true
	_reconnect_sync_requests.erase(peer_id)
	_reconnect_sync_since_usec[peer_id] = now
	_session_confirmed_peers.erase(peer_id)
	_sync_request_ids[peer_id] = "%d:%d:%s" % [int(session.get("local_peer_id", 1)), now, Crypto.new().generate_random_bytes(4).hex_encode()]
	diagnostics.record_event("session_sync_started", {"peer_id": peer_id, "reason": reason, "sync_request_id": _sync_request_ids[peer_id], "generation": int(room_state.get("lobby_generation", -1))})
	if not is_room_owner() and peer_id == 1:
		call_deferred("_send_reconnect_sync_request")

func _is_direct_session_peer(peer_id: int) -> bool:
	var role := str(session.get("role", ""))
	if role == "host":
		return peer_id >= 2 and peer_id <= MAX_PLAYERS and _is_roster_peer(peer_id)
	return role == "guest" and peer_id == 1

func _on_peer_connected(peer_id: int) -> void:
	diagnostics.increment_metric("peer_connected_events")
	if not _is_direct_session_peer(peer_id):
		_begin_session_sync(peer_id, "logical_roster_peer_event")
		return
	var is_reconnect := bool(_ever_confirmed_peers.get(peer_id, false)) or _disconnect_since_usec.has(peer_id)
	_begin_session_sync(peer_id, "reconnect" if is_reconnect else "initial_connection")
	diagnostics.record_event("peer_transport_connected_unconfirmed", {"peer_id": peer_id, "connection_kind": "reconnect" if is_reconnect else "first_connection", "outage_usec": Time.get_ticks_usec() - int(_disconnect_since_usec.get(peer_id, Time.get_ticks_usec())), "api_peer_id": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1))})
	transport_state_changed.emit("connecting", "Peer %d transport connected; validating its first session." % peer_id if not is_reconnect else "Peer %d transport reconnected; validating its session." % peer_id)

func _note_session_confirmed(peer_id: int, local_role: String) -> void:
	if not _is_direct_session_peer(peer_id):
		diagnostics.record_event("logical_peer_session_confirmation_ignored", {"peer_id": peer_id, "role": local_role})
		return
	var was_confirmed := bool(_ever_confirmed_peers.get(peer_id, false))
	_session_confirmed_peers[peer_id] = true
	_ever_confirmed_peers[peer_id] = true
	var event_name := "reconnected_session_confirmed" if was_confirmed else "initial_session_confirmed"
	diagnostics.record_event(event_name, {"peer_id": peer_id, "round_id": _round_id, "role": local_role, "connection_kind": "reconnect" if was_confirmed else "first_connection", "confirmed_at_usec": Time.get_ticks_usec()})

func _on_peer_disconnected(peer_id: int) -> void:
	diagnostics.increment_metric("peer_disconnected_events")
	if not _is_direct_session_peer(peer_id):
		_reconnect_sync_pending.erase(peer_id)
		_session_confirmed_peers.erase(peer_id)
		diagnostics.record_event("logical_peer_disconnect_ignored", {"peer_id": peer_id, "role": str(session.get("role", ""))})
		return
	_session_confirmed_peers.erase(peer_id)
	var now := Time.get_ticks_usec()
	if not _disconnect_since_usec.has(peer_id):
		_disconnect_since_usec[peer_id] = now
	_reconnect_sync_pending[peer_id] = true
	_reconnect_sync_requests.erase(peer_id)
	_reconnect_sync_since_usec[peer_id] = now
	diagnostics.record_event("peer_disconnected", {"peer_id": peer_id, "outage_started_usec": int(_disconnect_since_usec[peer_id]), "api_peer_id": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1))})
	transport_state_changed.emit("reconnecting", "Peer %d disconnected; reconnect grace started." % peer_id)

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
		var transport_connected := peer_id in connected_peer_ids()
		var now := Time.get_ticks_usec()
		diagnostics.record_event("restart_requested", {"peer_id": peer_id, "reason": "session_liveness_timeout", "caller": "multiplayer_v2_service._check_disconnect_grace", "transport_connected": transport_connected, "contact_age_usec": now - int(_last_heartbeat_usec.get(peer_id, now)), "disconnect_age_usec": now - int(_disconnect_since_usec.get(peer_id, now)), "deadline_usec": int(_disconnect_since_usec.get(peer_id, now)) + DISCONNECT_GRACE_USEC, "reconnect_generation": int(_reconnect_generation.get(peer_id, 0)), "api_peer_id_before": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1))})
		_webrtc_transport.restart_peer(user_id, initiate_offer)

func _recreate_guest_network_peer(reason: String) -> void:
	var assigned_peer_id := int(session.get("local_peer_id", -1))
	var api_peer_before := network_api.get_unique_id() if network_api != null else -1
	diagnostics.record_event("client_peer_recreation_requested", {"reason": reason, "assigned_peer_id": assigned_peer_id, "api_peer_id_before": api_peer_before, "disconnect_age_usec": Time.get_ticks_usec() - int(_disconnect_since_usec.get(1, Time.get_ticks_usec())), "reconnect_generation": int(_reconnect_generation.get(1, 0))})
	if assigned_peer_id < 2 or assigned_peer_id > MAX_PLAYERS or _webrtc_transport == null:
		return
	if webrtc_peer != null:
		webrtc_peer.close()
	var replacement := WebRTCMultiplayerPeer.new()
	var error := replacement.create_client(assigned_peer_id)
	if error != OK:
		diagnostics.record_event("client_peer_recreation_failed", {"reason": reason, "error": error, "assigned_peer_id": assigned_peer_id, "api_peer_id_before": api_peer_before})
		return
	webrtc_peer = replacement
	if network_api != null:
		network_api.multiplayer_peer = replacement
	_webrtc_transport.rebind_client_peer(replacement)
	diagnostics.record_event("client_peer_recreated", {"reason": reason, "assigned_peer_id": assigned_peer_id, "api_peer_id_before": api_peer_before, "api_peer_id_after": network_api.get_unique_id() if network_api != null else -1, "session_peer_id": int(session.get("local_peer_id", -1)), "reconnect_generation": int(_reconnect_generation.get(1, 0))})
	if network_api == null or network_api.get_unique_id() != assigned_peer_id:
		return
	_webrtc_transport.begin_connection()

func _check_disconnect_grace() -> void:
	if not _active:
		return
	var now := Time.get_ticks_usec()
	var connected := connected_peer_ids()
	if str(session.get("role", "")) == "host":
		for member in room_state.get("members", []):
			var peer_id := int(member.get("player_slot", 1))
			if peer_id == 1 or terminal_status.has(peer_id):
				continue
			var last_contact := int(_last_heartbeat_usec.get(peer_id, -1))
			var contact_fresh := last_contact >= 0 and now - last_contact < 3_000_000
			if peer_id in connected and _reconnect_sync_pending.has(peer_id):
				var sync_started := int(_reconnect_sync_since_usec.get(peer_id, now))
				if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and now - sync_started >= DISCONNECT_GRACE_USEC:
					diagnostics.record_event("reconnect_sync_timed_out", {"peer_id": peer_id, "round_id": _round_id, "elapsed_usec": now - sync_started})
					if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and not terminal_status.has(peer_id):
						var failure_report := {"round_id": _round_id, "owner_peer_id": peer_id, "simulation_tick": _last_seen_tick_by_peer.get(peer_id, 0), "state": "disconnected", "reason": "reconnect_sync_timeout", "event_id": "%s:%d:sync-timeout" % [_round_id, peer_id]}
						_commit_terminal(peer_id, failure_report)
					_reconnect_sync_pending.erase(peer_id)
					_reconnect_sync_requests.erase(peer_id)
					_reconnect_sync_since_usec.erase(peer_id)
				continue
			if peer_id in connected and contact_fresh:
				continue
			if not _disconnect_since_usec.has(peer_id):
				_disconnect_since_usec[peer_id] = last_contact + 3_000_000 if last_contact >= 0 else now
			if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and now - int(_disconnect_since_usec[peer_id]) >= DISCONNECT_GRACE_USEC:
				var report := {"round_id": _round_id, "owner_peer_id": peer_id, "simulation_tick": _last_seen_tick_by_peer.get(peer_id, 0), "state": "disconnected", "reason": "connection_grace_expired", "event_id": "%s:%d:disconnected" % [_round_id, peer_id]}
				diagnostics.record_event("peer_marked_disconnected", {"peer_id": peer_id, "grace_usec": now - int(_disconnect_since_usec[peer_id])})
				_commit_terminal(peer_id, report)
	else:
		var host_contact := int(_last_heartbeat_usec.get(1, -1))
		var host_contact_fresh := host_contact >= 0 and now - host_contact < 3_000_000
		if 1 in connected and host_contact_fresh and not _reconnect_sync_pending.has(1):
			return
		if not _disconnect_since_usec.has(1):
			_disconnect_since_usec[1] = host_contact + 3_000_000 if host_contact >= 0 else now
		var api_peer_mismatch := network_api != null and network_api.get_unique_id() != int(session.get("local_peer_id", -1))
		if connected.has(1) and not _reconnect_sync_pending.has(1) and not host_contact_fresh:
			_begin_session_sync(1, "liveness_timeout")
		var sync_expired := _reconnect_sync_pending.has(1) and now - int(_reconnect_sync_since_usec.get(1, now)) >= DISCONNECT_GRACE_USEC
		var initial_transport_expired := not connected.has(1) and host_contact < 0 and now - int(_disconnect_since_usec.get(1, now)) >= DISCONNECT_GRACE_USEC
		var retry_transport := not connected.has(1) or api_peer_mismatch or sync_expired
		if retry_transport and (liveness_restart_due(now, host_contact, int(_last_reconnect_attempt_usec.get(1, -1))) or ((sync_expired or initial_transport_expired) and now - int(_last_reconnect_attempt_usec.get(1, -2_000_000)) >= RECONNECT_RETRY_USEC)):
			_last_reconnect_attempt_usec[1] = now
			_reconnect_generation[1] = int(_reconnect_generation.get(1, 0)) + 1
			if api_peer_mismatch:
				_recreate_guest_network_peer("api_peer_id_reset")
			else:
				_restart_peer_link(1)
		if _round_coordinator.state == RoundCoordinatorScript.State.RUNNING and now - int(_disconnect_since_usec[1]) >= DISCONNECT_GRACE_USEC:
			_round_coordinator.cancel(tr("The host was disconnected beyond the reconnect grace period."), "disconnect_grace_expired", false)

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
	_reset_peer_liveness()
	_pending_round_failure.clear()
	_pending_round_failure_since_usec = -1
	_round_abort_pending.clear()
	_round_abort_return_pending = false
	_return_in_flight = false
	if not session.is_empty():
		diagnostics.record_event("session_closed", {"reason": reason})
	session.clear()
	session_changed.emit({})
	transport_state_changed.emit("disconnected", reason)

func set_session_as_active_for_testing(descriptor: Dictionary) -> void:
	activate_client_session(descriptor)
