extends Node

signal peer_state_changed(peer_user_id: String, state: String, message: String)
signal peer_data_received(peer_user_id: String, channel_name: String, payload: Dictionary)

const STUN_URL := "stun:stun.l.google.com:19302"
const MAX_PACKET_BYTES := 65536
const MAX_SNAPSHOT_BUFFERED_BYTES := 32768
const CONNECTION_TIMEOUT_SECONDS := 18.0
const MAX_CONNECTION_RETRIES := 1

var _room_id := ""
var _room_phase := ""
var _local_user_id := ""
var _owner_user_id := ""
var _is_owner := false
var _entries: Dictionary = {}
var _attempt_by_peer: Dictionary = {}
var _retry_count_by_peer: Dictionary = {}
var _started := false

func configure(room: Dictionary, local_user_id: String) -> void:
	var new_room_id := str(room.get("room_id", ""))
	var new_phase := str(room.get("phase", "OPEN"))
	# A match returning to OPEN is still the same room and the same peers. Keep
	# their direct channels alive so the next lobby/match does not renegotiate ICE.
	if new_room_id != _room_id or local_user_id != _local_user_id:
		close_all()
		_started = false
		_retry_count_by_peer.clear()
	_room_id = new_room_id
	_room_phase = new_phase
	_local_user_id = local_user_id
	_owner_user_id = str(room.get("owner_user_id", ""))
	_is_owner = not _owner_user_id.is_empty() and _owner_user_id == _local_user_id

func begin_connection() -> void:
	if _started or _room_id.is_empty() or _local_user_id.is_empty():
		return
	_started = true
	if _is_owner:
		peer_state_changed.emit("", "waiting", "Waiting for players to connect.")
		return
	if _entries.has(_owner_user_id):
		return
	var attempt_id := Crypto.new().generate_random_bytes(16).hex_encode()
	_attempt_by_peer[_owner_user_id] = attempt_id
	var entry := _create_peer_entry(_owner_user_id, attempt_id, true)
	if entry.is_empty():
		return
	_entries[_owner_user_id] = entry
	var offer_error: int = entry.connection.create_offer()
	if offer_error != OK:
		_fail_peer(_owner_user_id, "Could not create a WebRTC offer (code %d)." % offer_error)
	else:
		peer_state_changed.emit(_owner_user_id, "connecting", "Connecting directly to the host…")

func handle_signal(envelope: Dictionary) -> void:
	if str(envelope.get("room_id", "")) != _room_id:
		return
	var sender := str(envelope.get("from_user_id", ""))
	var attempt_id := str(envelope.get("attempt_id", ""))
	var kind := str(envelope.get("type", ""))
	var body: Variant = envelope.get("body", {})
	if sender.is_empty() or attempt_id.is_empty() or not body is Dictionary:
		return
	if not _is_owner and sender != _owner_user_id:
		return
	if _attempt_by_peer.has(sender) and str(_attempt_by_peer[sender]) != attempt_id:
		return
	if kind in ["offer", "ice"] and _is_owner and not _entries.has(sender):
		_attempt_by_peer[sender] = attempt_id
		_entries[sender] = _create_peer_entry(sender, attempt_id, false)
		if _entries[sender].is_empty():
			return
	if not _entries.has(sender):
		return
	var entry: Dictionary = _entries[sender]
	if str(entry.get("attempt_id", "")) != attempt_id:
		return
	var connection: WebRTCPeerConnection = entry.connection
	match kind:
		"offer", "answer":
			var sdp := str(body.get("sdp", ""))
			if sdp.is_empty() or sdp.length() > 32768:
				_fail_peer(sender, "The WebRTC session description was invalid or too large.")
				return
			var sdp_type := str(body.get("sdp_type", kind))
			var error: int = connection.set_remote_description(sdp_type, sdp)
			if error != OK:
				_fail_peer(sender, "Could not apply the remote WebRTC description (code %d)." % error)
			else:
				entry.remote_description_set = true
				_apply_buffered_candidates(sender)
				# Godot emits session_description_created with the answer after
				# set_remote_description("offer", ...); _on_session_description_created
				# applies it locally and forwards it through the signaling channel.
		"ice":
			var candidate := {"media": str(body.get("media", "")), "index": int(body.get("index", -1)), "candidate": str(body.get("candidate", ""))}
			if candidate.media.is_empty() or candidate.index < 0 or candidate.candidate.is_empty() or candidate.candidate.length() > 4096:
				return
			if bool(entry.get("remote_description_set", false)):
				connection.add_ice_candidate(candidate.media, candidate.index, candidate.candidate)
			else:
				var candidates: Array = entry.get("pending_candidates", [])
				if candidates.size() < 64:
					candidates.append(candidate)
					entry.pending_candidates = candidates

func send_to_peer(peer_user_id: String, channel_name: String, payload: Dictionary) -> bool:
	return _send_bytes_to_peer(peer_user_id, channel_name, JSON.stringify(payload).to_utf8_buffer(), channel_name == "snapshot") == OK

func send_to_all(channel_name: String, payload: Dictionary) -> Dictionary:
	var serialization_started_usec := Time.get_ticks_usec()
	var packet := JSON.stringify(payload).to_utf8_buffer()
	var serialized_usec := Time.get_ticks_usec() - serialization_started_usec
	var result := {"sent": 0, "failed": 0, "dropped": 0, "bytes": 0, "packet_bytes": packet.size(), "serialized_usec": serialized_usec}
	if packet.size() > MAX_PACKET_BYTES:
		result.failed = _entries.size()
		return result
	for peer_user_id in _entries.keys():
		var error := _send_bytes_to_peer(str(peer_user_id), channel_name, packet, channel_name == "snapshot")
		if error == ERR_BUSY:
			result.dropped += 1
		elif error != OK:
			result.failed += 1
		else:
			result.sent += 1
			result.bytes += packet.size()
	return result

func _send_bytes_to_peer(peer_user_id: String, channel_name: String, packet: PackedByteArray, drop_congested_snapshot: bool = false) -> int:
	if not _entries.has(peer_user_id) or packet.size() > MAX_PACKET_BYTES:
		return ERR_INVALID_PARAMETER
	var entry: Dictionary = _entries[peer_user_id]
	var channel: WebRTCDataChannel = entry.get("control") if channel_name == "control" else entry.get("snapshot")
	if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_UNAVAILABLE
	if drop_congested_snapshot and channel.get_buffered_amount() > MAX_SNAPSHOT_BUFFERED_BYTES:
		return ERR_BUSY
	channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
	return channel.put_packet(packet)

func connected_peer_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for peer_user_id in _entries:
		var entry: Dictionary = _entries[peer_user_id]
		var control: WebRTCDataChannel = entry.get("control")
		var snapshot: WebRTCDataChannel = entry.get("snapshot")
		if (
			control != null
			and snapshot != null
			and control.get_ready_state() == WebRTCDataChannel.STATE_OPEN
			and snapshot.get_ready_state() == WebRTCDataChannel.STATE_OPEN
		):
			result.append(str(peer_user_id))
	return result

func peer_link_state(peer_user_id: String) -> String:
	if not _entries.has(peer_user_id):
		return "disconnected"
	var entry: Dictionary = _entries[peer_user_id]
	var control: WebRTCDataChannel = entry.get("control")
	var snapshot: WebRTCDataChannel = entry.get("snapshot")
	if control != null and snapshot != null and control.get_ready_state() == WebRTCDataChannel.STATE_OPEN and snapshot.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		return "connected"
	return "connecting"

func close_all() -> void:
	for peer_user_id in _entries.keys():
		_close_entry(_entries[peer_user_id])
	_entries.clear()
	_attempt_by_peer.clear()
	_room_id = ""
	_room_phase = ""
	_owner_user_id = ""
	_is_owner = false
	_started = false

func _process(_delta: float) -> void:
	for peer_user_id in _entries.keys():
		var entry: Dictionary = _entries[peer_user_id]
		var connection: WebRTCPeerConnection = entry.connection
		connection.poll()
		var control: WebRTCDataChannel = entry.get("control")
		var snapshot: WebRTCDataChannel = entry.get("snapshot")
		var channels_open := (
			control != null
			and snapshot != null
			and control.get_ready_state() == WebRTCDataChannel.STATE_OPEN
			and snapshot.get_ready_state() == WebRTCDataChannel.STATE_OPEN
		)
		if not channels_open and float(Time.get_ticks_msec() - int(entry.get("created_at_msec", 0))) / 1000.0 > CONNECTION_TIMEOUT_SECONDS:
			_fail_peer(str(peer_user_id), "Direct connection timed out. Try another network or host.")
			continue
		var state := connection.get_connection_state()
		if state != int(entry.get("last_pc_state", -1)):
			entry.last_pc_state = state
			print("[MP_DIAG] ", JSON.stringify({"event": "webrtc_connection_state", "room_id": _room_id, "peer_id": peer_user_id, "state_code": state, "elapsed_ms": Time.get_ticks_msec() - int(entry.get("created_at_msec", Time.get_ticks_msec()))}))
		if state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED:
			_fail_peer(str(peer_user_id), "Direct peer connection failed. Try another network or host.")
			continue
		for channel_name in ["control", "snapshot"]:
			var channel: WebRTCDataChannel = entry.get(channel_name)
			if channel == null:
				continue
			channel.poll()
			_drain_reliable_queue(entry, channel_name)
			while channel.get_available_packet_count() > 0:
				var packet: PackedByteArray = channel.get_packet()
				if packet.size() > MAX_PACKET_BYTES:
					continue
				var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
				if parsed is Dictionary:
					peer_data_received.emit(str(peer_user_id), channel_name, parsed)
		if channels_open and not bool(entry.get("channels_open_notified", false)):
			entry.channels_open_notified = true
			peer_state_changed.emit(str(peer_user_id), "connected", "Both direct peer channels opened.")
			_retry_count_by_peer.erase(str(peer_user_id))

func _create_peer_entry(peer_user_id: String, attempt_id: String, make_offer: bool) -> Dictionary:
	var connection := WebRTCPeerConnection.new()
	var error: int = connection.initialize({"iceServers": [{"urls": [STUN_URL]}]})
	if error != OK:
		peer_state_changed.emit(peer_user_id, "failed", "WebRTC is unavailable in this build (code %d)." % error)
		return {}
	connection.session_description_created.connect(_on_session_description_created.bind(peer_user_id, attempt_id))
	connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_user_id, attempt_id))
	connection.data_channel_received.connect(_on_data_channel_received.bind(peer_user_id, attempt_id))
	var entry := {
		"connection": connection,
		"attempt_id": attempt_id,
		"created_at_msec": Time.get_ticks_msec(),
		"remote_description_set": false,
		"pending_candidates": [],
		"control": null,
		"snapshot": null,
		"reliable_queue": [],
		"channels_open_notified": false,
		"last_pc_state": -1,
	}
	if make_offer:
		entry.control = connection.create_data_channel("control", {"ordered": true, "protocol": "gravity-run-v1"})
		entry.snapshot = connection.create_data_channel("snapshot", {"ordered": false, "maxRetransmits": 1, "protocol": "gravity-run-v1"})
		if entry.control == null or entry.snapshot == null:
			_close_entry(entry)
			peer_state_changed.emit(peer_user_id, "failed", "Could not create WebRTC data channels.")
			return {}
		entry.control.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
		entry.snapshot.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
	return entry

func _on_session_description_created(sdp_type: String, sdp: String, peer_user_id: String, attempt_id: String) -> void:
	if not _entries.has(peer_user_id) or str(_entries[peer_user_id].get("attempt_id", "")) != attempt_id:
		return
	var entry: Dictionary = _entries[peer_user_id]
	var error: int = entry.connection.set_local_description(sdp_type, sdp)
	if error != OK:
		_fail_peer(peer_user_id, "Could not set local WebRTC description (code %d)." % error)
		return
	_send_signal(peer_user_id, attempt_id, sdp_type, {"sdp_type": sdp_type, "sdp": sdp})

func _on_ice_candidate_created(media: String, index: int, candidate: String, peer_user_id: String, attempt_id: String) -> void:
	_send_signal(peer_user_id, attempt_id, "ice", {"media": media, "index": index, "candidate": candidate})

func _on_data_channel_received(channel: WebRTCDataChannel, peer_user_id: String, attempt_id: String) -> void:
	if not _entries.has(peer_user_id) or str(_entries[peer_user_id].get("attempt_id", "")) != attempt_id:
		channel.close()
		return
	var entry: Dictionary = _entries[peer_user_id]
	match channel.get_label():
		"control": entry.control = channel
		"snapshot": entry.snapshot = channel
		_: channel.close()
	if channel.get_label() in ["control", "snapshot"]:
		channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT

func queue_reliable_to_peer(peer_user_id: String, payload: Dictionary) -> bool:
	if not _entries.has(peer_user_id):
		return false
	var bytes := JSON.stringify(payload).to_utf8_buffer()
	if bytes.size() > 12000:
		return false
	var entry: Dictionary = _entries[peer_user_id]
	var queue: Array = entry.get("reliable_queue", [])
	if queue.size() >= 512:
		return false
	queue.append(bytes)
	entry.reliable_queue = queue
	return true

func _send_signal(peer_user_id: String, attempt_id: String, message_type: String, body: Dictionary) -> void:
	var service := get_node_or_null("/root/MultiplayerService")
	if service == null:
		return
	var envelope: Dictionary = service.create_signal_envelope(peer_user_id, message_type, body, attempt_id)
	if not envelope.is_empty():
		service.publish_signal(envelope)

func _apply_buffered_candidates(peer_user_id: String) -> void:
	if not _entries.has(peer_user_id):
		return
	var entry: Dictionary = _entries[peer_user_id]
	for candidate in entry.get("pending_candidates", []):
		entry.connection.add_ice_candidate(candidate.media, candidate.index, candidate.candidate)
	entry.pending_candidates = []

func _drain_reliable_queue(entry: Dictionary, channel_name: String) -> void:
	if channel_name != "control":
		return
	var channel: WebRTCDataChannel = entry.get("control")
	if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN or channel.get_buffered_amount() > 131072:
		return
	var queue: Array = entry.get("reliable_queue", [])
	while not queue.is_empty() and channel.get_buffered_amount() < 131072:
		var result: int = channel.put_packet(queue[0])
		if result != OK:
			break
		queue.pop_front()
	entry.reliable_queue = queue

func _fail_peer(peer_user_id: String, message: String) -> void:
	print("[MP_DIAG] ", JSON.stringify({"event": "webrtc_failed", "room_id": _room_id, "peer_id": peer_user_id, "message": message, "at_ms": Time.get_ticks_msec()}))
	if _entries.has(peer_user_id):
		_close_entry(_entries[peer_user_id])
		_entries.erase(peer_user_id)
	_attempt_by_peer.erase(peer_user_id)
	var retries := int(_retry_count_by_peer.get(peer_user_id, 0))
	if not _is_owner and not _room_id.is_empty() and retries < MAX_CONNECTION_RETRIES:
		_retry_count_by_peer[peer_user_id] = retries + 1
		_started = false
		peer_state_changed.emit(peer_user_id, "retrying", message)
		call_deferred("_retry_host_connection", peer_user_id)
	else:
		peer_state_changed.emit(peer_user_id, "failed", message)

func _retry_host_connection(peer_user_id: String) -> void:
	if _is_owner or _room_id.is_empty() or peer_user_id != _owner_user_id:
		return
	begin_connection()

func _close_entry(entry: Dictionary) -> void:
	var connection: WebRTCPeerConnection = entry.get("connection")
	if connection != null:
		connection.close()
