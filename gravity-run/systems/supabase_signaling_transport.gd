extends Node

const Config := preload("res://systems/leaderboard_config.gd")
const HEARTBEAT_SECONDS := 25.0
const MAX_RECONNECT_DELAY := 20.0

signal connection_state_changed(connected: bool, message: String)
signal message_received(message: Dictionary)

var _socket := WebSocketPeer.new()
var _topic := ""
var _token := ""
var _join_ref := "1"
var _next_ref := 2
var _heartbeat_elapsed := 0.0
var _reconnect_elapsed := 0.0
var _reconnect_delay := 1.0
var _joining := false
var _connected := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if _topic.is_empty():
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_join_channel()
			_reconnect_elapsed = 0.0
			while _socket.get_available_packet_count() > 0:
				_handle_packet(_socket.get_packet().get_string_from_utf8())
			if _connected:
				_heartbeat_elapsed += delta
				if _heartbeat_elapsed >= HEARTBEAT_SECONDS:
					_heartbeat_elapsed = 0.0
					_send_frame("phoenix", "heartbeat", {}, str(_next_ref))
					_next_ref += 1
		WebSocketPeer.STATE_CLOSED:
			_set_connected(false, tr("Lobby signaling disconnected."))
			_joining = false
			_reconnect_elapsed += delta
			if _reconnect_elapsed >= _reconnect_delay:
				_reconnect_elapsed = 0.0
				_reconnect_delay = minf(_reconnect_delay * 1.7, MAX_RECONNECT_DELAY)
			_open_socket()

func connect_room(topic: String, access_token: String) -> void:
	if topic.is_empty() or access_token.is_empty():
		disconnect_room()
		_set_connected(false, tr("Lobby signaling is missing a room or session."))
		return
	if topic == _topic and access_token == _token and _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return
	disconnect_room()
	_topic = topic
	_token = access_token
	_reconnect_delay = 1.0
	_open_socket()

func disconnect_room() -> void:
	_topic = ""
	_token = ""
	_joining = false
	_heartbeat_elapsed = 0.0
	_reconnect_elapsed = 0.0
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close(1000, "leaving room")
	_set_connected(false, "")

func send_signal(message: Dictionary) -> void:
	if not _connected or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var broadcast := {
		"event": "signal",
		"type": "broadcast",
		"payload": message,
	}
	_send_frame(_topic_name(), "broadcast", broadcast, str(_next_ref))
	_next_ref += 1

func _open_socket() -> void:
	if _topic.is_empty() or _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		return
	_socket = WebSocketPeer.new()
	_socket.outbound_buffer_size = 256 * 1024
	var base_url := Config.PROJECT_URL.replace("https://", "wss://").replace("http://", "ws://")
	var url := "%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [base_url, _uri_encode(Config.PUBLISHABLE_KEY)]
	var error := _socket.connect_to_url(url)
	if error != OK:
		_set_connected(false, tr("Could not open lobby signaling socket (code %d).") % error)
		_reconnect_elapsed = 0.0

func _handle_packet(packet_text: String) -> void:
	var parsed: Variant = JSON.parse_string(packet_text)
	if not parsed is Dictionary:
		return
	var event_name := str(parsed.get("event", ""))
	var payload: Variant = parsed.get("payload", {})
	if event_name == "phx_reply" and payload is Dictionary:
		var status := str(payload.get("status", ""))
		if status == "ok" and _joining:
			_joining = false
			_reconnect_delay = 1.0
			_set_connected(true, "")
		elif status == "error":
			_joining = false
			_set_connected(false, tr("Supabase rejected private lobby signaling."))
			_socket.close(4003, "private channel rejected")
		return
	if event_name == "broadcast" and payload is Dictionary:
		var inner: Variant = payload.get("payload", {})
		if str(payload.get("event", "")) == "signal" and inner is Dictionary:
			message_received.emit(inner)

func _join_channel() -> void:
	if _joining or _connected or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_joining = true
	var config := {
		"broadcast": {"ack": false, "self": false},
		"presence": {"enabled": false},
		"private": true,
	}
	var payload := {"config": config, "access_token": _token}
	_send_frame(_topic_name(), "phx_join", payload, _join_ref, _join_ref)

func _send_frame(topic_name: String, event_name: String, payload: Dictionary, reference: String, join_reference: String = "") -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := {
		"topic": topic_name,
		"event": event_name,
		"payload": payload,
		"ref": reference,
	}
	if not join_reference.is_empty():
		frame["join_ref"] = join_reference
	var result := _socket.send_text(JSON.stringify(frame))
	if result != OK:
		_set_connected(false, tr("Could not send lobby signaling (code %d).") % result)

func _topic_name() -> String:
	return "realtime:" + _topic

func _set_connected(value: bool, message: String) -> void:
	if _connected == value and message.is_empty():
		return
	_connected = value
	connection_state_changed.emit(value, message)

func _uri_encode(value: String) -> String:
	var encoded := ""
	for byte_value in value.to_utf8_buffer():
		var character := String.chr(byte_value)
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_.~":
			encoded += character
		else:
			encoded += "%%%02X" % byte_value
	return encoded
