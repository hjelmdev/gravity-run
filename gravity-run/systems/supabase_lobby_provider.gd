extends Node

const Config := preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)

var _request: HTTPRequest
var _active_action := ""
var _active_context := ""
var _pending_calls: Array[Dictionary] = []
var _active_started_msec := 0
var _active_call: Dictionary = {}

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "SupabaseLobbyRequest"
	_request.timeout = 20.0
	_request.accept_gzip = false
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)

func create_room(display_name: String, is_public: bool, game_version: String, generator_version: int, seed: int, course_length_px: int, token: String, context: String) -> void:
	_call("create_room", "create_multiplayer_room_with_visibility", {
		"p_display_name": display_name,
		"p_is_public": is_public,
		"p_game_version": game_version,
		"p_generator_version": generator_version,
		"p_seed": seed,
		"p_course_length_px": course_length_px,
	}, token, context)

func join_room(room_code: String, display_name: String, game_version: String, generator_version: int, protocol_version: int, token: String, context: String) -> void:
	_call("join_room", "join_multiplayer_room", {
		"p_room_code": room_code,
		"p_display_name": display_name,
		"p_game_version": game_version,
		"p_generator_version": generator_version,
		"p_protocol_version": protocol_version,
	}, token, context)

func refresh_room(room_id: String, token: String, context: String) -> void:
	_call("refresh_room", "refresh_multiplayer_room", {"p_room_id": room_id}, token, context)

func set_ready(room_id: String, ready: bool, token: String, context: String) -> void:
	_call("set_ready", "set_multiplayer_ready", {"p_room_id": room_id, "p_ready": ready}, token, context)

func set_skin(room_id: String, skin_id: int, token: String, context: String) -> void:
	_call("set_skin", "set_multiplayer_skin", {"p_room_id": room_id, "p_skin_id": skin_id}, token, context)

func set_manifest(room_id: String, seed: int, length_px: int, manifest_hash: String, token: String, context: String) -> void:
	_call("set_manifest", "set_multiplayer_manifest", {
		"p_room_id": room_id,
		"p_seed": seed,
		"p_course_length_px": length_px,
		"p_manifest_hash": manifest_hash,
	}, token, context)

func acknowledge_manifest(room_id: String, manifest_hash: String, token: String, context: String) -> void:
	_call("ack_manifest", "ack_multiplayer_manifest", {
		"p_room_id": room_id,
		"p_manifest_hash": manifest_hash,
	}, token, context)

func start_countdown(room_id: String, token: String, context: String) -> void:
	_call("start_countdown", "start_multiplayer_countdown", {"p_room_id": room_id}, token, context)

func leave_room(room_id: String, token: String, context: String) -> void:
	# A leave invalidates queued work for the old room; do not let stale ready or
	# refresh mutations run after the member has left.
	_pending_calls.clear()
	_call("leave_room", "leave_multiplayer_room", {"p_room_id": room_id}, token, context)

func list_public_rooms(token: String, context: String) -> void:
	_call("list_public_rooms", "list_public_multiplayer_rooms", {}, token, context)

func return_to_lobby(room_id: String, token: String, context: String) -> void:
	_call("return_to_lobby", "return_multiplayer_room_to_lobby", {"p_room_id": room_id}, token, context)

func advance_match_phase(room_id: String, phase: String, token: String, context: String) -> void:
	_call("advance_match_phase", "advance_multiplayer_match_phase", {"p_room_id": room_id, "p_next_phase": phase}, token, context)

func _call(action: String, rpc_name: String, payload: Dictionary, token: String, context: String) -> void:
	if token.is_empty():
		request_finished.emit(action, false, null, tr("A multiplayer identity is required."), context)
		return
	var call := {
		"action": action,
		"rpc_name": rpc_name,
		"payload": payload.duplicate(true),
		"token": token,
		"context": context,
		"queued_at_msec": Time.get_ticks_msec(),
		"retry_count": 0,
	}
	# Refreshes are best-effort reads: retain at most one queued refresh and let
	# user mutations (especially leave) run first instead of rejecting them.
	if action == "refresh_room":
		for queued in _pending_calls:
			if str(queued.get("action", "")) == "refresh_room" and str(queued.get("context", "")) == context:
				return
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or not _pending_calls.is_empty():
		if _pending_calls.size() >= 64:
			request_finished.emit(action, false, null, tr("The multiplayer request queue is full. Wait a moment and retry."), context)
			return
		if action == "leave_room":
			_pending_calls.push_front(call)
		elif action in ["refresh_room", "list_public_rooms"]:
			_pending_calls.append(call)
		else:
			var first_background := _pending_calls.size()
			for index in range(_pending_calls.size()):
				if str(_pending_calls[index].get("action", "")) in ["refresh_room", "list_public_rooms"]:
					first_background = index
					break
			_pending_calls.insert(first_background, call)
		return
	_start_call(call)

func _start_call(call: Dictionary) -> void:
	var action := str(call.get("action", ""))
	var rpc_name := str(call.get("rpc_name", ""))
	var payload: Dictionary = call.get("payload", {})
	var token := str(call.get("token", ""))
	var context := str(call.get("context", ""))
	_active_action = action
	_active_context = context
	_active_call = call.duplicate(true)
	_active_started_msec = Time.get_ticks_msec()
	print("[MP_DIAG] ", JSON.stringify({"event": "lobby_rpc_start", "action": action, "context": context, "queue_wait_ms": _active_started_msec - int(call.get("queued_at_msec", _active_started_msec)), "at_ms": _active_started_msec}))
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Authorization: Bearer " + token,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, rpc_name]
	var error := _request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		var failed_action := _active_action
		var failed_context := _active_context
		_active_action = ""
		_active_context = ""
		_log_rpc_result(failed_action, failed_context, "request_start_failed", error)
		request_finished.emit(failed_action, false, null, tr("Could not start the lobby request (code %d).") % error, failed_context)
		call_deferred("_dispatch_pending_call")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _active_action
	var context := _active_context
	_active_action = ""
	_active_context = ""
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		_log_rpc_result(action, context, "network_error_%d" % result, response_code)
		_schedule_safe_retry()
		request_finished.emit(action, false, null, tr("Network error while contacting the lobby service (code %d).") % result, context)
		call_deferred("_dispatch_pending_call")
		return
	if response_code < 200 or response_code >= 300:
		_log_rpc_result(action, context, "http_error", response_code)
		if response_code >= 500:
			_schedule_safe_retry()
		request_finished.emit(action, false, null, _friendly_error(parsed, response_code), context)
		call_deferred("_dispatch_pending_call")
		return
	_log_rpc_result(action, context, "ok", response_code)
	request_finished.emit(action, true, parsed, "", context)
	call_deferred("_dispatch_pending_call")

func _dispatch_pending_call() -> void:
	if _pending_calls.is_empty() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_start_call(_pending_calls.pop_front())

func _log_rpc_result(action: String, context: String, outcome: String, response_code: int) -> void:
	var elapsed_msec := maxi(0, Time.get_ticks_msec() - _active_started_msec)
	print("[MP_DIAG] ", JSON.stringify({"event": "lobby_rpc_done", "action": action, "context": context, "outcome": outcome, "http": response_code, "elapsed_ms": elapsed_msec}))


func _schedule_safe_retry() -> void:
	var action := str(_active_call.get("action", ""))
	if action not in ["refresh_room", "set_ready", "set_skin", "ack_manifest", "leave_room", "advance_match_phase", "return_to_lobby"]:
		return
	var retry_count := int(_active_call.get("retry_count", 0))
	if retry_count >= 2:
		return
	var retry_call := _active_call.duplicate(true)
	retry_call.retry_count = retry_count + 1
	retry_call.queued_at_msec = Time.get_ticks_msec()
	var delay_seconds := 1.0 if retry_count == 0 else 2.0
	var timer := get_tree().create_timer(delay_seconds, true, false, true)
	timer.timeout.connect(_queue_safe_retry.bind(retry_call), CONNECT_ONE_SHOT)

func _queue_safe_retry(call: Dictionary) -> void:
	if str(call.get("action", "")) not in ["refresh_room", "set_ready", "set_skin", "ack_manifest", "leave_room", "advance_match_phase", "return_to_lobby"]:
		return
	for queued in _pending_calls:
		if str(queued.get("action", "")) == str(call.get("action", "")) and str(queued.get("context", "")) == str(call.get("context", "")):
			return
	if _pending_calls.size() >= 64:
		return
	var first_background := _pending_calls.size()
	for index in range(_pending_calls.size()):
		if str(_pending_calls[index].get("action", "")) in ["refresh_room", "list_public_rooms"]:
			first_background = index
			break
	_pending_calls.insert(first_background, call)
	_dispatch_pending_call()

func _friendly_error(response: Variant, response_code: int) -> String:
	var detail := ""
	if response is Dictionary:
		detail = str(response.get("message", response.get("details", ""))).to_lower()
	for code in ["room_not_found", "room_not_open", "room_full", "version_mismatch", "not_room_owner", "not_room_member", "not_enough_players", "players_not_ready", "manifest_hash_mismatch", "manifest_not_available", "invalid_display_name"]:
		if code in detail:
			return tr("Lobby request rejected: %s") % code.replace("_", " ")
	if response_code == 401 or response_code == 403 or "not_authenticated" in detail:
		return tr("Your multiplayer session expired. Rejoin the room.")
	return tr("Lobby request failed (HTTP %d).") % response_code
