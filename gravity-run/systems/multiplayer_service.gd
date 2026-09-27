extends Node

const Config := preload("res://systems/leaderboard_config.gd")
const LobbyProvider := preload("res://systems/supabase_lobby_provider.gd")
const SignalingTransport := preload("res://systems/supabase_signaling_transport.gd")
const WebRTCTransport := preload("res://systems/webrtc_match_transport.gd")
const PROTOCOL_VERSION := 2
const GAME_VERSION := "2"
const DEFAULT_COURSE_LENGTH_PX := 45000

signal room_changed(room: Dictionary)
signal public_rooms_loaded(rooms: Array, message: String)
signal request_finished(action: String, success: bool, message: String)
signal signaling_message_received(message: Dictionary)
signal signaling_message_outgoing(message: Dictionary)
signal signaling_state_changed(state: String, message: String)
signal peer_connection_state_changed(peer_user_id: String, state: String, message: String)
signal peer_data_received(peer_user_id: String, channel_name: String, payload: Dictionary)
signal race_countdown_received(start_at_unix: float)

var room_state: Dictionary = {}
var identity_user_id := ""
var identity_is_anonymous := false
var signaling_connected := false

var _identity_token := ""
var _identity_expires_at := 0
var _identity_request: HTTPRequest
var _lobby_provider: Node
var _signaling_transport: Node
var _webrtc_transport: Node
var _pending_identity_action := ""
var _pending_identity_arguments: Dictionary = {}
var _pending_member_signals: Array[Dictionary] = []
var _lobby_poll_elapsed := 0.0
var course_manifest: Resource
var race_start_at_unix := 0.0
var _room_generation := 0
var _identity_started_msec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_identity_request = HTTPRequest.new()
	_identity_request.name = "MultiplayerAnonymousAuth"
	_identity_request.timeout = 20.0
	_identity_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_identity_request.request_completed.connect(_on_identity_request_completed)
	add_child(_identity_request)
	_lobby_provider = LobbyProvider.new()
	_lobby_provider.name = "SupabaseLobbyProvider"
	_lobby_provider.request_finished.connect(_on_lobby_request_finished)
	add_child(_lobby_provider)
	_signaling_transport = SignalingTransport.new()
	_signaling_transport.name = "SupabaseSignalingTransport"
	_signaling_transport.connection_state_changed.connect(set_signaling_connected)
	_signaling_transport.message_received.connect(receive_signal)
	signaling_message_outgoing.connect(_signaling_transport.send_signal)
	room_changed.connect(_on_room_changed_for_signaling)
	add_child(_signaling_transport)
	_webrtc_transport = WebRTCTransport.new()
	_webrtc_transport.name = "WebRTCMatchTransport"
	_webrtc_transport.peer_state_changed.connect(_on_peer_connection_state_changed)
	_webrtc_transport.peer_data_received.connect(func(peer_id: String, channel: String, payload: Dictionary) -> void: peer_data_received.emit(peer_id, channel, payload))
	signaling_message_received.connect(_webrtc_transport.handle_signal)
	add_child(_webrtc_transport)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	_sync_account_identity()

func _process(delta: float) -> void:
	if not room_state.is_empty():
		_lobby_poll_elapsed += delta
		# Roster/readiness/countdown changes should not wait several seconds.
		# Keep match polling less frequent, where snapshots already carry motion.
		var poll_interval := 1.0 if str(room_state.get("phase", "OPEN")) == "COUNTDOWN" else 15.0
		if _lobby_poll_elapsed >= poll_interval:
			_lobby_poll_elapsed = 0.0
			refresh_room()

func has_room() -> bool:
	return not room_state.is_empty()

func is_room_owner() -> bool:
	return has_room() and str(room_state.get("owner_user_id", "")) == identity_user_id

func get_room_id() -> String:
	return str(room_state.get("room_id", ""))

func get_signaling_topic() -> String:
	return str(room_state.get("signaling_topic", ""))

func get_access_token_for_network() -> String:
	return _current_token()

func begin_peer_connection() -> void:
	if has_room():
		_webrtc_transport.configure(room_state, identity_user_id)
		_webrtc_transport.begin_connection()

func send_peer_message(peer_user_id: String, channel_name: String, payload: Dictionary) -> bool:
	return _webrtc_transport.send_to_peer(peer_user_id, channel_name, payload) if _webrtc_transport != null else false

func send_peer_message_to_all(channel_name: String, payload: Dictionary) -> Dictionary:
	return _webrtc_transport.send_to_all(channel_name, payload) if _webrtc_transport != null else {"sent": 0, "failed": 0, "dropped": 0, "bytes": 0, "packet_bytes": 0, "serialized_usec": 0}

func get_connected_peer_ids() -> PackedStringArray:
	return _webrtc_transport.connected_peer_ids() if _webrtc_transport != null else PackedStringArray()

func get_peer_link_state(peer_user_id: String) -> String:
	return _webrtc_transport.peer_link_state(peer_user_id) if _webrtc_transport != null else "unavailable"

func can_start_race() -> bool:
	if not has_room() or not is_room_owner() or str(room_state.get("phase", "")) != "OPEN":
		return false
	var present_members: Array[Dictionary] = []
	for member in get_members():
		if member is Dictionary and bool(member.get("is_connected", true)):
			present_members.append(member)
	if present_members.is_empty() or present_members.size() > int(room_state.get("max_players", 4)) or str(room_state.get("manifest_hash", "")).is_empty():
		return false
	var expected_peers := {}
	for member in present_members:
		if not member is Dictionary or not bool(member.get("is_ready", false)) or str(member.get("loaded_manifest_hash", "")) != str(room_state.get("manifest_hash", "")):
			return false
		var member_id := str(member.get("user_id", ""))
		if member_id != identity_user_id:
			expected_peers[member_id] = true
	var connected := {}
	for peer_id in get_connected_peer_ids():
		connected[peer_id] = true
	for peer_id in expected_peers:
		if not connected.has(peer_id):
			return false
	return true

func queue_reliable_peer_message(peer_user_id: String, payload: Dictionary) -> bool:
	return _webrtc_transport.queue_reliable_to_peer(peer_user_id, payload) if _webrtc_transport != null else false

func get_members() -> Array:
	var members: Variant = room_state.get("members", [])
	return members if members is Array else []

func create_room(display_name: String = "", is_public: bool = false) -> void:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var seed_value := random.randi_range(1, 2147483647)
	_begin_action("create_room", {
		"display_name": _resolved_display_name(display_name),
		"is_public": is_public,
		"game_version": GAME_VERSION,
		"generator_version": ChallengeService.generation_version,
		"seed": seed_value,
		"course_length_px": DEFAULT_COURSE_LENGTH_PX,
	})

func join_room(room_code: String, display_name: String = "") -> void:
	_begin_action("join_room", {
		"room_code": room_code.strip_edges().to_upper(),
		"display_name": _resolved_display_name(display_name),
		"game_version": GAME_VERSION,
		"generator_version": ChallengeService.generation_version,
		"protocol_version": PROTOCOL_VERSION,
	})

func load_public_rooms() -> void:
	_begin_action("list_public_rooms", {})

func refresh_room() -> void:
	if not has_room():
		return
	_lobby_provider.refresh_room(get_room_id(), _current_token(), _lobby_context())

func set_ready(ready: bool) -> void:
	if has_room():
		_lobby_provider.set_ready(get_room_id(), ready, _current_token(), _lobby_context())

func set_skin_id(skin_id: int) -> void:
	if has_room():
		_lobby_provider.set_skin(get_room_id(), posmod(skin_id, 4), _current_token(), _lobby_context())

func publish_manifest(manifest_hash: String, seed_value: int, length_px: int) -> void:
	if has_room() and is_room_owner():
		_lobby_provider.set_manifest(get_room_id(), seed_value, length_px, manifest_hash, _current_token(), _lobby_context())

func acknowledge_manifest(manifest_hash: String) -> void:
	if has_room():
		_lobby_provider.acknowledge_manifest(get_room_id(), manifest_hash, _current_token(), _lobby_context())

func request_start() -> void:
	if can_start_race():
		_lobby_provider.start_countdown(get_room_id(), _current_token(), _lobby_context())
	else:
		request_finished.emit("start_countdown", false, tr("All players must be ready, have the same course, and have a direct connection to the host."))

func leave_room() -> void:
	if not has_room():
		return
	# Det lokala UI:t får aldrig bli gisslan för en stale/missing room på
	# serversidan. Spara request-parametrarna innan vi nollställer rummet.
	var room_id := get_room_id()
	var token := _current_token()
	var context := _lobby_context()
	_clear_local_room()
	_lobby_provider.leave_room(room_id, token, context)

func return_to_lobby() -> void:
	if has_room():
		_lobby_provider.return_to_lobby(get_room_id(), _current_token(), _lobby_context())

func advance_match_phase(phase: String) -> void:
	if has_room() and is_room_owner():
		_lobby_provider.advance_match_phase(get_room_id(), phase, _current_token(), _lobby_context())

func set_signaling_connected(connected: bool, message: String = "") -> void:
	if signaling_connected == connected and message.is_empty():
		return
	signaling_connected = connected
	signaling_state_changed.emit("connected" if connected else "disconnected", message)
	# The lobby peer channel carries the host's authoritative course manifest.
	# Connect before anyone can be ready; otherwise guests cannot load that
	# manifest until ready, while ready itself is gated on loading it.
	if connected and has_room():
		_webrtc_transport.begin_connection()
		refresh_room()
		_broadcast_room_state_hint()

func publish_signal(message: Dictionary) -> void:
	if not has_room():
		return
	# The Realtime transport receives this only after the lobby RPC issued a
	# room-scoped signaling topic to the current member.
	signaling_message_outgoing.emit(message)

func create_signal_envelope(recipient_user_id: String, message_type: String, body: Dictionary, attempt_id: String = "") -> Dictionary:
	if not has_room() or recipient_user_id.is_empty() or message_type.is_empty():
		return {}
	var resolved_attempt_id := attempt_id
	if resolved_attempt_id.is_empty():
		resolved_attempt_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var now := int(Time.get_unix_time_from_system())
	return {
		"protocol_version": PROTOCOL_VERSION,
		"room_id": get_room_id(),
		"attempt_id": resolved_attempt_id,
		"from_user_id": identity_user_id,
		"to_user_id": recipient_user_id,
		"type": message_type,
		"body": body.duplicate(true),
		"sent_at": now,
		"expires_at": now + 60,
	}

func receive_signal(message: Dictionary) -> void:
	if not has_room() or not _valid_signal_envelope(message, false):
		return
	if not _is_room_member_id(str(message.get("from_user_id", ""))):
		if _pending_member_signals.size() < 32:
			_pending_member_signals.append(message.duplicate(true))
			refresh_room()
		return
	if str(message.get("type", "")) == "room_state_changed":
		refresh_room()
		return
	signaling_message_received.emit(message)

func _begin_action(action: String, arguments: Dictionary) -> void:
	if has_room():
		request_finished.emit(action, false, tr("Leave the current room before joining another."))
		return
	if action in ["create_room", "join_room"]:
		_room_generation += 1
	print("[MP_DIAG] ", JSON.stringify({"event": "lobby_action_requested", "action": action, "generation": _room_generation, "auth_cached": not _current_token().is_empty(), "at_ms": Time.get_ticks_msec()}))
	_pending_identity_action = action
	_pending_identity_arguments = arguments
	if _sync_account_identity():
		_dispatch_pending_action()
		return
	if not identity_user_id.is_empty() and not _identity_token.is_empty() and Time.get_unix_time_from_system() < _identity_expires_at - 60:
		_dispatch_pending_action()
		return
	if _identity_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, tr("A multiplayer identity request is already in progress."))
		_pending_identity_action = ""
		_pending_identity_arguments.clear()
		return
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var payload := {"data": {"display_name": str(arguments.get("display_name", "Runner"))}}
	_identity_started_msec = Time.get_ticks_msec()
	var error := _identity_request.request("%s/auth/v1/signup" % Config.PROJECT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request_finished.emit(action, false, tr("Could not start guest multiplayer sign-in (code %d).") % error)
		_pending_identity_action = ""
		_pending_identity_arguments.clear()

func _dispatch_pending_action() -> void:
	var action := _pending_identity_action
	var arguments := _pending_identity_arguments.duplicate(true)
	_pending_identity_action = ""
	_pending_identity_arguments.clear()
	if action.is_empty():
		return
	match action:
		"create_room":
			_lobby_provider.create_room(
				str(arguments.display_name), bool(arguments.is_public), str(arguments.game_version), int(arguments.generator_version),
				int(arguments.seed), int(arguments.course_length_px), _current_token(), _lobby_context()
			)
		"join_room":
			_lobby_provider.join_room(
				str(arguments.room_code), str(arguments.display_name), str(arguments.game_version),
				int(arguments.generator_version), int(arguments.protocol_version), _current_token(), _lobby_context()
			)
		"list_public_rooms":
			_lobby_provider.list_public_rooms(_current_token(), _lobby_context())

func _on_identity_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _pending_identity_action
	print("[MP_DIAG] ", JSON.stringify({"event": "anonymous_auth_done", "action": action, "http": response_code, "result": result, "elapsed_ms": maxi(0, Time.get_ticks_msec() - _identity_started_msec), "at_ms": Time.get_ticks_msec()}))
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or not parsed is Dictionary:
		var message := tr("Guest multiplayer sign-in failed (HTTP %d).") % response_code
		if parsed is Dictionary and "anonymous" in str(parsed.get("msg", parsed.get("message", ""))).to_lower():
			message = tr("Guest multiplayer is unavailable. Enable anonymous sign-ins in Supabase Auth settings.")
		request_finished.emit(action, false, message)
		_pending_identity_action = ""
		_pending_identity_arguments.clear()
		return
	var user: Variant = parsed.get("user", {})
	if not user is Dictionary or str(parsed.get("access_token", "")).is_empty() or str(user.get("id", "")).is_empty():
		request_finished.emit(action, false, tr("Supabase returned an incomplete guest multiplayer session."))
		_pending_identity_action = ""
		_pending_identity_arguments.clear()
		return
	_identity_token = str(parsed.access_token)
	_identity_expires_at = int(Time.get_unix_time_from_system()) + int(parsed.get("expires_in", 3600))
	identity_user_id = str(user.id)
	identity_is_anonymous = true
	_dispatch_pending_action()

func _on_lobby_request_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	if context != _lobby_context():
		return
	if action == "list_public_rooms":
		public_rooms_loaded.emit(data if success and data is Array else [], message if not success else "")
		return
	# Ignore replies from a request that was already in flight when the player
	# left; otherwise a stale refresh/ready response can put the old room back.
	if action not in ["create_room", "join_room", "leave_room"] and not has_room():
		return
	if not success:
		if action == "leave_room" and ("room_not_found" in message.to_lower() or "room_not_member" in message.to_lower()):
			request_finished.emit(action, true, tr("You left the room."))
			return
		if has_room() and ("room_not_found" in message.to_lower() or "room_not_member" in message.to_lower()):
			_clear_local_room()
			request_finished.emit(action, false, tr("The room is no longer available. You have been returned to the lobby menu."))
			return
		if action == "set_ready" and "room_not_open" in message.to_lower():
			refresh_room()
		request_finished.emit(action, false, message)
		return
	if action == "leave_room":
		request_finished.emit(action, true, tr("You left the room."))
		return
	if data is Dictionary:
		var resolved_room: Variant = data.get("room", data) if action == "start_countdown" else data
		if resolved_room is Dictionary:
			room_state = resolved_room.duplicate(true)
			print("[MP_DIAG] ", JSON.stringify({"event": "room_state_received", "action": action, "room_id": get_room_id(), "phase": str(room_state.get("phase", "")), "members": get_members().size(), "generation": _room_generation, "at_ms": Time.get_ticks_msec()}))
			room_changed.emit(room_state.duplicate(true))
			if action == "start_countdown":
				var start_at := float(data.get("start_at_unix", 0.0))
				if start_at <= 0.0:
					start_at = Time.get_unix_time_from_system() + 5.0
				race_start_at_unix = start_at
				race_countdown_received.emit(start_at)
			if action == "refresh_room" and not _pending_member_signals.is_empty():
				var pending_signals := _pending_member_signals.duplicate(true)
				_pending_member_signals.clear()
				for pending_signal in pending_signals:
					receive_signal(pending_signal)
	if success and action in ["create_room", "join_room", "set_ready", "set_skin", "set_manifest", "ack_manifest", "start_countdown", "advance_match_phase", "return_to_lobby"]:
		_broadcast_room_state_hint()
	if action == "start_countdown":
		var start_at := race_start_at_unix if race_start_at_unix > 0.0 else Time.get_unix_time_from_system() + 5.0
		send_peer_message_to_all("control", {"kind": "race_start", "room_id": get_room_id(), "start_at_unix": start_at})
	request_finished.emit(action, true, "")

func _clear_local_room() -> void:
	_room_generation += 1
	room_state.clear()
	course_manifest = null
	race_start_at_unix = 0.0
	_lobby_poll_elapsed = 0.0
	_pending_member_signals.clear()
	if _webrtc_transport != null:
		_webrtc_transport.close_all()
	room_changed.emit(room_state.duplicate(true))

func _on_room_changed_for_signaling(room: Dictionary) -> void:
	if room.is_empty():
		_signaling_transport.disconnect_room()
		_webrtc_transport.close_all()
	else:
		_signaling_transport.connect_room(str(room.get("signaling_topic", "")), _current_token())
		_webrtc_transport.configure(room, identity_user_id)
		if signaling_connected:
			_webrtc_transport.begin_connection()

func _on_peer_connection_state_changed(peer_user_id: String, state: String, message: String) -> void:
	print("[MP_DIAG] ", JSON.stringify({"event": "peer_state", "room_id": get_room_id(), "generation": _room_generation, "peer_id": peer_user_id, "state": state, "message": message, "at_ms": Time.get_ticks_msec()}))
	peer_connection_state_changed.emit(peer_user_id, state, message)

func _on_auth_state_changed(_is_authenticated: bool, _email: String) -> void:
	if has_room():
		return
	_identity_token = ""
	_identity_expires_at = 0
	identity_user_id = ""
	identity_is_anonymous = false
	_sync_account_identity()

func _sync_account_identity() -> bool:
	if not AuthService.is_authenticated or AuthService.get_access_token().is_empty():
		return false
	identity_user_id = AuthService.user_id
	_identity_token = AuthService.get_access_token()
	_identity_expires_at = int(Time.get_unix_time_from_system()) + 3600
	identity_is_anonymous = false
	return true

func _current_token() -> String:
	if not identity_is_anonymous and AuthService.is_authenticated and AuthService.user_id == identity_user_id:
		return AuthService.get_access_token()
	return _identity_token

func _resolved_display_name(requested: String) -> String:
	var display_name := requested.strip_edges()
	if display_name.is_empty() and PlayerAccountProfile.has_profile:
		display_name = str(PlayerAccountProfile.nickname).strip_edges()
	if display_name.is_empty():
		display_name = str(PlayerProfile.leaderboard_name).strip_edges()
	if display_name.is_empty():
		display_name = "Runner"
	return display_name.left(16)

func _valid_signal_envelope(message: Dictionary, require_room_member: bool = true) -> bool:
	if int(message.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return false
	if str(message.get("room_id", "")) != get_room_id():
		return false
	if str(message.get("to_user_id", "")) != identity_user_id:
		return false
	if str(message.get("from_user_id", "")) == identity_user_id:
		return false
	if require_room_member and not _is_room_member_id(str(message.get("from_user_id", ""))):
		return false
	if not message.get("body", {}) is Dictionary:
		return false
	if str(message.get("attempt_id", "")).is_empty() or str(message.get("type", "")).is_empty():
		return false
	var expires_at := int(message.get("expires_at", 0))
	return expires_at > int(Time.get_unix_time_from_system()) and expires_at < int(Time.get_unix_time_from_system()) + 120

func _is_room_member_id(user_id: String) -> bool:
	for member in get_members():
		if member is Dictionary and str(member.get("user_id", "")) == user_id:
			return true
	return false

func _broadcast_room_state_hint() -> void:
	if not has_room() or not signaling_connected:
		return
	for member in get_members():
		if not member is Dictionary:
			continue
		var peer_id := str(member.get("user_id", ""))
		if peer_id.is_empty() or peer_id == identity_user_id:
			continue
		var envelope := create_signal_envelope(peer_id, "room_state_changed", {"room_id": get_room_id()})
		if not envelope.is_empty():
			publish_signal(envelope)

func _lobby_context() -> String:
	return "%s:%d" % [identity_user_id, _room_generation]
