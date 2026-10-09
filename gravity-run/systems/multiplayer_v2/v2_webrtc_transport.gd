extends Node
## V2-only signaling-to-WebRTCMultiplayerPeer bridge.

signal signal_outgoing(message: Dictionary)
signal peer_state_changed(peer_id: int, state: String, message: String)
signal transport_mutation(event: String, details: Dictionary)
signal roster_refresh_requested(reason: String)
signal signal_diagnostic(event_name: String, details: Dictionary)

const STUN_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]
## STUN plus the TURN servers v2_turn_credentials.gd adds (shared by every room).
static var ice_servers: Array = STUN_SERVERS.duplicate(true)
const MAX_PENDING_ICE := 64
const MAX_UNKNOWN_MEMBER_SIGNALS := 32
const UNKNOWN_MEMBER_TTL_MSEC := 4_000

var peer: WebRTCMultiplayerPeer
var room_id := ""
var local_user_id := ""
var owner_user_id := ""
var is_host := false
var local_peer_id := 0
var room_members: Array = []
var _connections: Dictionary = {}
var _attempts: Dictionary = {}
var _connection_generations: Dictionary = {}
var _remote_generations: Dictionary = {}
var _retired_attempts: Dictionary = {}
var _unknown_member_signals: Array[Dictionary] = []
var roster_revision := -1

func configure(room: Dictionary, user_id: String, api_peer: WebRTCMultiplayerPeer) -> void:
	close_all()
	room_id = str(room.get("room_id", ""))
	local_user_id = user_id
	owner_user_id = str(room.get("owner_user_id", ""))
	is_host = owner_user_id == local_user_id
	room_members = room.get("members", []).duplicate(true)
	roster_revision = int(room.get("roster_revision", -1))
	local_peer_id = int(_member_for_user(user_id).get("player_slot", 1))
	peer = api_peer
	_replay_confirmed_signals()

func update_room(room: Dictionary) -> void:
	if str(room.get("room_id", "")) != room_id or peer == null:
		configure(room, local_user_id, peer)
		return
	owner_user_id = str(room.get("owner_user_id", ""))
	is_host = owner_user_id == local_user_id
	room_members = room.get("members", []).duplicate(true)
	roster_revision = int(room.get("roster_revision", roster_revision))
	for user_id in _connections.keys().duplicate():
		if _member_for_user(str(user_id)).is_empty():
			var peer_id := int(_connections.get(user_id, {}).get("peer_id", -1))
			_remove_connection(str(user_id))
			peer_state_changed.emit(peer_id, "removed", "The host removed this player from the lobby.")
	_replay_confirmed_signals()

func begin_connection() -> void:
	if peer == null or room_id.is_empty() or local_user_id.is_empty():
		return
	if is_host:
		peer_state_changed.emit(0, "waiting", "Waiting for guests.")
		return
	_start_guest_offer(owner_user_id)

func handle_signal(envelope: Dictionary) -> void:
	if str(envelope.get("network_mode", "")) != "v2" or str(envelope.get("room_id", "")) != room_id:
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": str(envelope.get("type", "")), "attempt_id": str(envelope.get("attempt_id", "")), "generation": int(envelope.get("connection_generation", -1)), "roster_revision": roster_revision, "queued": false, "reason": "room_or_mode_mismatch"})
		return
	var sender := str(envelope.get("from_user_id", ""))
	var recipient := str(envelope.get("to_user_id", ""))
	var attempt_id := str(envelope.get("attempt_id", ""))
	var generation := int(envelope.get("connection_generation", -1))
	var kind := str(envelope.get("type", ""))
	var body: Variant = envelope.get("body", {})
	var now := int(Time.get_unix_time_from_system())
	if kind not in ["offer", "answer", "ice"]:
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "unsupported_signal_kind"})
		return
	if (is_host and kind == "answer") or (not is_host and kind == "offer"):
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "unexpected_offer_answer_direction"})
		return
	if sender.is_empty() or attempt_id.is_empty() or generation < 1 or not body is Dictionary or (not recipient.is_empty() and recipient != local_user_id):
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "invalid_envelope"})
		return
	if int(envelope.get("sent_at", -1)) > now + 5 or int(envelope.get("expires_at", 0)) < now or int(envelope.get("expires_at", 0)) - int(envelope.get("sent_at", 0)) > 60:
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "expired_or_invalid_ttl"})
		return
	if _member_for_user(sender).is_empty():
		var encoded_size := JSON.stringify(envelope).length()
		if encoded_size <= 40_000 and _unknown_member_signals.size() < MAX_UNKNOWN_MEMBER_SIGNALS:
			_unknown_member_signals.append({"received_at_msec": Time.get_ticks_msec(), "sender": sender, "attempt_id": attempt_id, "generation": generation, "kind": kind, "envelope": envelope.duplicate(true)})
			signal_diagnostic.emit("signal_waiting_for_roster", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": true, "reason": "unknown_sender"})
		else:
			signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "unknown_sender_queue_limit"})
		roster_refresh_requested.emit("unknown_signaling_sender")
		return
	if not is_host and sender != owner_user_id:
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "sender_not_host"})
		return
	var known_remote_generation := int(_remote_generations.get(sender, 0))
	if _is_retired_attempt(sender, attempt_id) or generation < known_remote_generation or (is_host and known_remote_generation > 0 and generation == known_remote_generation and str(_attempts.get(sender, "")) != attempt_id):
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "stale_attempt_or_generation"})
		return
	if not _attempts.has(sender):
		if is_host and kind == "ice":
			var ice_media := str(body.get("media", ""))
			var ice_index := int(body.get("index", -1))
			var ice_candidate := str(body.get("candidate", ""))
			if ice_media.is_empty() or ice_media.length() > 128 or ice_index < 0 or ice_candidate.is_empty() or ice_candidate.length() > 4096:
				signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "invalid_ice_candidate"})
				return
			if _unknown_member_signals.size() < MAX_UNKNOWN_MEMBER_SIGNALS:
				_unknown_member_signals.append({"received_at_msec": Time.get_ticks_msec(), "sender": sender, "attempt_id": attempt_id, "generation": generation, "kind": kind, "envelope": envelope.duplicate(true)})
				signal_diagnostic.emit("signal_waiting_for_offer", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": true, "reason": "ice_before_offer"})
			else:
				signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "pending_signal_queue_limit"})
			return
		if not is_host or kind != "offer":
			return
		var slot := int(_member_for_user(sender).get("player_slot", 1))
		_remote_generations[sender] = generation
		if _new_connection(sender, attempt_id, slot, generation) == null:
			return
	elif str(_attempts[sender]) != attempt_id:
		if not is_host or kind != "offer" or generation <= int(_connections.get(sender, {}).get("generation", 0)):
			return
		_remove_connection(sender)
		_remote_generations[sender] = generation
		var slot := int(_member_for_user(sender).get("player_slot", 1))
		if _new_connection(sender, attempt_id, slot, generation) == null:
			return
	if not is_host and generation != int(_connections.get(sender, {}).get("generation", -1)):
		return
	if not _connections.has(sender):
		signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "connection_missing"})
		return
	signal_diagnostic.emit("signal_accepted", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "member_slot": int(_member_for_user(sender).get("player_slot", -1))})
	var entry: Dictionary = _connections[sender]
	var connection: WebRTCPeerConnection = entry.connection
	match kind:
		"offer", "answer":
			var sdp := str(body.get("sdp", ""))
			var sdp_type := str(body.get("sdp_type", kind))
			var fingerprint := hash(sdp)
			if bool(entry.remote_description_set):
				if int(entry.get("remote_description_fingerprint", 0)) == fingerprint:
					signal_diagnostic.emit("signal_duplicate", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "reason": "description_already_applied"})
					return
				signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "conflicting_description_same_attempt"})
				return
			if sdp.is_empty() or sdp.length() > 32768:
				signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "invalid_sdp_size"})
				_fail(sender, "Invalid WebRTC session description.")
				return
			if connection.set_remote_description(sdp_type, sdp) != OK:
				signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": kind, "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "sdp_apply_failed"})
				_fail(sender, "Invalid WebRTC session description.")
				return
			entry.remote_description_set = true
			entry.remote_description_fingerprint = fingerprint
			_apply_ice(sender)
			_drain_queued_ice(sender, attempt_id, generation)
		"ice":
			var candidate := {"media": str(body.get("media", "")), "index": int(body.get("index", -1)), "candidate": str(body.get("candidate", ""))}
			if candidate.media.is_empty() or candidate.index < 0 or candidate.candidate.is_empty() or candidate.candidate.length() > 4096:
				return
			if bool(entry.remote_description_set):
				connection.add_ice_candidate(candidate.media, candidate.index, candidate.candidate)
			else:
				var candidates: Array = entry.pending_ice
				if candidates.size() < MAX_PENDING_ICE:
					candidates.append(candidate)
				entry.pending_ice = candidates

func create_signal_envelope(recipient: String, kind: String, body: Dictionary, attempt: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var generation := int(_connections.get(recipient, {}).get("generation", 1))
	return {"network_mode": "v2", "protocol_version": 1, "room_id": room_id, "connection_generation": generation, "attempt_id": attempt, "from_user_id": local_user_id, "to_user_id": recipient, "type": kind, "body": body.duplicate(true), "sent_at": now, "expires_at": now + 60}

func restart_peer(user_id: String, initiate_offer: bool) -> void:
	if peer == null or _member_for_user(user_id).is_empty():
		return
	_remove_connection(user_id)
	if is_host or not initiate_offer or user_id != owner_user_id:
		peer_state_changed.emit(int(_member_for_user(user_id).get("player_slot", 0)), "waiting", "Waiting to retry the peer link.")
		return
	_start_guest_offer(user_id)

func rebind_client_peer(api_peer: WebRTCMultiplayerPeer) -> void:
	# Preserve monotonically increasing signaling generations while replacing a
	# WebRTCMultiplayerPeer whose local client ID was reset by the engine.
	for user_id in _connections.keys():
		var entry: Dictionary = _connections[user_id]
		var connection: WebRTCPeerConnection = entry.get("connection")
		var api_peer_id_before := peer.get_unique_id() if peer != null else -1
		transport_mutation.emit("peer_removed", {"user_id": user_id, "peer_id": int(entry.get("peer_id", -1)), "connection_generation": int(entry.get("generation", -1)), "api_peer_id_before": api_peer_id_before, "reason": "client_peer_recreated"})
		transport_mutation.emit("connection_closed", {"user_id": user_id, "peer_id": int(entry.get("peer_id", -1)), "connection_generation": int(entry.get("generation", -1)), "api_peer_id_before": api_peer_id_before, "reason": "client_peer_recreated"})
		if connection != null:
			connection.close()
	_connections.clear()
	_attempts.clear()
	peer = api_peer

func close_all() -> void:
	for entry in _connections.values():
		var connection: WebRTCPeerConnection = entry.get("connection")
		if connection != null:
			connection.close()
	_connections.clear()
	_attempts.clear()
	_connection_generations.clear()
	_remote_generations.clear()
	_retired_attempts.clear()
	_unknown_member_signals.clear()
	room_id = ""
	local_user_id = ""
	owner_user_id = ""
	is_host = false
	local_peer_id = 0
	room_members.clear()
	peer = null
	roster_revision = -1

func _replay_confirmed_signals() -> void:
	if _unknown_member_signals.is_empty():
		return
	var now := Time.get_ticks_msec()
	var pending := _unknown_member_signals.duplicate(true)
	_unknown_member_signals.clear()
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_offer := str(a.get("kind", "")) == "offer"
		var b_offer := str(b.get("kind", "")) == "offer"
		if a_offer != b_offer:
			return a_offer
		return int(a.get("received_at_msec", 0)) < int(b.get("received_at_msec", 0))
	)
	for queued in pending:
		var envelope: Dictionary = queued.get("envelope", {})
		var sender := str(queued.get("sender", ""))
		var age := now - int(queued.get("received_at_msec", 0))
		if age > UNKNOWN_MEMBER_TTL_MSEC:
			signal_diagnostic.emit("signal_rejected", {"direction": "incoming", "kind": str(queued.get("kind", "")), "attempt_id": str(queued.get("attempt_id", "")), "generation": int(queued.get("generation", -1)), "roster_revision": roster_revision, "queued": false, "reason": "unknown_sender_expired"})
			continue
		if _member_for_user(sender).is_empty():
			_unknown_member_signals.append(queued)
			continue
		if is_host and str(queued.get("kind", "")) == "ice" and not _attempts.has(sender):
			_unknown_member_signals.append(queued)
			continue
		signal_diagnostic.emit("signal_replayed", {"direction": "incoming", "kind": str(queued.get("kind", "")), "attempt_id": str(queued.get("attempt_id", "")), "generation": int(queued.get("generation", -1)), "roster_revision": roster_revision, "queued": false, "reason": "membership_confirmed"})
		handle_signal(envelope)

func _drain_queued_ice(user_id: String, attempt_id: String, generation: int) -> void:
	if _unknown_member_signals.is_empty():
		return
	var pending := _unknown_member_signals.duplicate(true)
	_unknown_member_signals.clear()
	for queued in pending:
		if str(queued.get("sender", "")) == user_id and str(queued.get("attempt_id", "")) == attempt_id and int(queued.get("generation", -1)) == generation and str(queued.get("kind", "")) == "ice":
			signal_diagnostic.emit("signal_replayed", {"direction": "incoming", "kind": "ice", "attempt_id": attempt_id, "generation": generation, "roster_revision": roster_revision, "queued": false, "reason": "offer_installed"})
			handle_signal(queued.get("envelope", {}))
		elif Time.get_ticks_msec() - int(queued.get("received_at_msec", 0)) <= UNKNOWN_MEMBER_TTL_MSEC:
			_unknown_member_signals.append(queued)

func _new_connection(user_id: String, attempt: String, peer_id: int, generation: int) -> WebRTCPeerConnection:
	var connection := WebRTCPeerConnection.new()
	if connection.initialize({"iceServers": ice_servers}) != OK:
		_fail(user_id, "WebRTC is unavailable in this build.")
		return null
	if peer == null or peer.add_peer(connection, peer_id) != OK:
		connection.close()
		_fail(user_id, "Could not register the WebRTC peer.")
		return null
	connection.session_description_created.connect(_on_description_created.bind(user_id, attempt))
	connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(user_id, attempt))
	_connections[user_id] = {"connection": connection, "attempt": attempt, "peer_id": peer_id, "generation": generation, "remote_description_set": false, "pending_ice": []}
	transport_mutation.emit("peer_connection_created", {"user_id": user_id, "peer_id": peer_id, "connection_generation": generation, "api_peer_id": peer.get_unique_id() if peer != null else -1})
	_attempts[user_id] = attempt
	peer_state_changed.emit(peer_id, "connecting", "Negotiating WebRTC link.")
	return connection

func _on_description_created(sdp_type: String, sdp: String, user_id: String, attempt: String) -> void:
	if not _connections.has(user_id) or str(_connections[user_id].attempt) != attempt:
		return
	var connection: WebRTCPeerConnection = _connections[user_id].connection
	if connection.set_local_description(sdp_type, sdp) != OK:
		_fail(user_id, "Could not install the local WebRTC description.")
		return
	signal_diagnostic.emit("signal_accepted", {"direction": "outgoing", "kind": sdp_type, "attempt_id": attempt, "generation": int(_connections[user_id].get("generation", -1)), "roster_revision": roster_revision, "queued": true})
	signal_outgoing.emit(create_signal_envelope(user_id, sdp_type, {"sdp_type": sdp_type, "sdp": sdp}, attempt))

func _on_ice_candidate_created(media: String, index: int, candidate: String, user_id: String, attempt: String) -> void:
	if _connections.has(user_id) and str(_connections[user_id].attempt) == attempt:
		signal_diagnostic.emit("signal_accepted", {"direction": "outgoing", "kind": "ice", "attempt_id": attempt, "generation": int(_connections[user_id].get("generation", -1)), "roster_revision": roster_revision, "queued": true})
		signal_outgoing.emit(create_signal_envelope(user_id, "ice", {"media": media, "index": index, "candidate": candidate}, attempt))

func _start_guest_offer(user_id: String) -> void:
	var generation := int(_connection_generations.get(user_id, 0)) + 1
	_connection_generations[user_id] = generation
	var attempt := _new_attempt_id()
	signal_diagnostic.emit("connection_attempt_started", {"direction": "outgoing", "kind": "offer", "attempt_id": attempt, "generation": generation, "roster_revision": roster_revision})
	var connection := _new_connection(user_id, attempt, 1, generation)
	if connection != null:
		var error := connection.create_offer()
		if error != OK:
			_fail(user_id, "Could not create the WebRTC offer (code %d)." % error)

func _remove_connection(user_id: String) -> void:
	if not _connections.has(user_id):
		_attempts.erase(user_id)
		return
	var entry: Dictionary = _connections[user_id]
	var api_peer_id_before := peer.get_unique_id() if peer != null else -1
	var attempt := str(entry.get("attempt", ""))
	var retired: Array = _retired_attempts.get(user_id, [])
	retired.append(attempt)
	while retired.size() > 8:
		retired.pop_front()
	_retired_attempts[user_id] = retired
	var connection: WebRTCPeerConnection = entry.get("connection")
	if peer != null:
		peer.remove_peer(int(entry.get("peer_id", 0)))
	transport_mutation.emit("peer_removed", {"user_id": user_id, "peer_id": int(entry.get("peer_id", -1)), "connection_generation": int(entry.get("generation", -1)), "api_peer_id_before": api_peer_id_before, "reason": "restart_peer"})
	if connection != null:
		connection.close()
		transport_mutation.emit("connection_closed", {"user_id": user_id, "peer_id": int(entry.get("peer_id", -1)), "connection_generation": int(entry.get("generation", -1)), "api_peer_id_before": api_peer_id_before, "reason": "restart_peer"})
	_connections.erase(user_id)
	_attempts.erase(user_id)

func _is_retired_attempt(user_id: String, attempt: String) -> bool:
	return attempt in _retired_attempts.get(user_id, [])

func _apply_ice(user_id: String) -> void:
	var entry: Dictionary = _connections[user_id]
	var connection: WebRTCPeerConnection = entry.connection
	for candidate in entry.pending_ice:
		connection.add_ice_candidate(str(candidate.media), int(candidate.index), str(candidate.candidate))
	entry.pending_ice.clear()

func _member_for_user(user_id: String) -> Dictionary:
	for member in room_members:
		if str(member.get("user_id", "")) == user_id:
			return member
	return {}

func _new_attempt_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _fail(user_id: String, message: String) -> void:
	peer_state_changed.emit(int(_member_for_user(user_id).get("player_slot", 0)), "failed", message)
