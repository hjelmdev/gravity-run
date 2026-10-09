extends Node
## Dedicated RPC client. All V2 calls have their own Supabase function prefix.

const Config := preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
signal request_timing(action: String, context: String, queue_usec: int, request_usec: int)

var _request: HTTPRequest
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "MultiplayerV2LobbyRequest"
	_request.timeout = 20.0
	_request.accept_gzip = false
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.request_completed.connect(_on_completed)
	add_child(_request)

func create_room(display_name: String, is_public: bool, game_version: String, generator_version: int, seed_value: int, course_length_px: int, token: String, context: String) -> void:
	_call("create_room", "multiplayer_v2_create_room", {"p_display_name": display_name, "p_is_public": is_public, "p_game_version": game_version, "p_generator_version": generator_version, "p_seed": seed_value, "p_course_length_px": course_length_px}, token, context)

func join_room(room_code: String, display_name: String, game_version: String, generator_version: int, token: String, context: String) -> void:
	_call("join_room", "multiplayer_v2_join_room", {"p_room_code": room_code, "p_display_name": display_name, "p_game_version": game_version, "p_generator_version": generator_version, "p_v2_protocol_version": 2}, token, context)

func list_rooms(token: String, context: String) -> void:
	_call("list_rooms", "multiplayer_v2_list_public_rooms", {}, token, context)

func refresh_room(room_id: String, loadout_hash: String, token: String, context: String) -> void:
	_call("refresh_room", "multiplayer_v2_refresh_room", {"p_room_id": room_id, "p_loadout_hash": loadout_hash}, token, context)

func set_ready(room_id: String, ready: bool, cycle: int, content_revision: int, loadout_hash: String, token: String, context: String) -> void:
	_call("set_ready", "multiplayer_v2_set_ready", {"p_room_id": room_id, "p_ready": ready, "p_expected_cycle": cycle, "p_expected_content_revision": content_revision, "p_loadout_hash": loadout_hash}, token, context)

func set_equipment(room_id: String, enabled: bool, cycle: int, token: String, context: String) -> void:
	_call("set_equipment", "multiplayer_v2_set_equipment", {"p_room_id": room_id, "p_enabled": enabled, "p_expected_cycle": cycle}, token, context)

func set_skin(room_id: String, skin_id: int, token: String, context: String) -> void:
	_call("set_skin", "multiplayer_v2_set_skin", {"p_room_id": room_id, "p_skin_id": skin_id}, token, context)

func leave_room(room_id: String, token: String, context: String) -> void:
	_queue.clear()
	_call("leave_room", "multiplayer_v2_leave_room", {"p_room_id": room_id}, token, context)

func set_manifest(room_id: String, seed_value: int, length_px: int, hash_value: String, token: String, context: String) -> void:
	_call("set_manifest", "multiplayer_v2_set_manifest", {"p_room_id": room_id, "p_seed": seed_value, "p_course_length_px": length_px, "p_manifest_hash": hash_value}, token, context)

func ack_manifest(room_id: String, hash_value: String, token: String, context: String) -> void:
	_call("ack_manifest", "multiplayer_v2_ack_manifest", {"p_room_id": room_id, "p_manifest_hash": hash_value}, token, context)

func start_prepare(room_id: String, token: String, context: String) -> void:
	_call("prepare_round", "multiplayer_v2_prepare_round", {"p_room_id": room_id}, token, context)

func set_phase(room_id: String, phase: String, token: String, context: String) -> void:
	_call("set_phase", "multiplayer_v2_set_phase", {"p_room_id": room_id, "p_phase": phase}, token, context)

func return_to_lobby(room_id: String, cycle: int, token: String, context: String) -> void:
	_call("return_to_lobby", "multiplayer_v2_return_to_lobby", {"p_room_id": room_id, "p_expected_cycle": cycle}, token, context)

func return_member(room_id: String, cycle: int, token: String, context: String) -> void:
	_call("return_member", "multiplayer_v2_return_member", {"p_room_id": room_id, "p_expected_cycle": cycle}, token, context)

func kick_member(room_id: String, user_id: String, slot: int, cycle: int, token: String, context: String) -> void:
	_call("kick_member", "multiplayer_v2_kick_member", {"p_room_id": room_id, "p_target_user_id": user_id, "p_target_slot": slot, "p_expected_cycle": cycle}, token, context)

func _call(action: String, rpc_name: String, payload: Dictionary, token: String, context: String) -> void:
	if token.is_empty():
		request_finished.emit(action, false, null, tr("A multiplayer identity is required."), context)
		return
	var call := {"action": action, "rpc_name": rpc_name, "payload": payload, "token": token, "context": context, "queued_at_usec": Time.get_ticks_usec()}
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		if _queue.size() < 64:
			_queue.append(call)
		else:
			request_finished.emit(action, false, null, tr("The multiplayer lobby request queue is full."), context)
		return
	_start(call)

func _start(call: Dictionary) -> void:
	call["started_at_usec"] = Time.get_ticks_usec()
	_active = call
	var headers := PackedStringArray(["apikey: " + Config.PUBLISHABLE_KEY, "Authorization: Bearer " + str(call.token), "Content-Type: application/json", "Accept: application/json"])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, str(call.rpc_name)]
	var error := _request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(call.payload))
	if error != OK:
		request_timing.emit(str(call.action), str(call.context), int(call.started_at_usec) - int(call.queued_at_usec), 0)
		request_finished.emit(str(call.action), false, null, tr("Could not start a multiplayer lobby request (code %d).") % error, str(call.context))
		_active.clear()
		_dispatch_next.call_deferred()

func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var call := _active
	_active = {}
	var completed_at_usec := Time.get_ticks_usec()
	request_timing.emit(str(call.get("action", "")), str(call.get("context", "")), int(call.get("started_at_usec", completed_at_usec)) - int(call.get("queued_at_usec", completed_at_usec)), completed_at_usec - int(call.get("started_at_usec", completed_at_usec)))
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var detail := str(parsed.get("message", parsed.get("details", ""))) if parsed is Dictionary else ""
		var message := tr("multiplayer lobby request failed (HTTP %d).") % response_code
		if result != HTTPRequest.RESULT_SUCCESS:
			message = tr("Network error contacting the multiplayer lobby service (code %d).") % result
		elif not detail.is_empty():
			message = detail
		request_finished.emit(str(call.get("action", "")), false, parsed, message, str(call.get("context", "")))
	else:
		request_finished.emit(str(call.get("action", "")), true, parsed, "", str(call.get("context", "")))
	_dispatch_next.call_deferred()

func _dispatch_next() -> void:
	if _queue.is_empty() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_start(_queue.pop_front())
