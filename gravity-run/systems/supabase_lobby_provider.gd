extends Node

const Config := preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)

var _request: HTTPRequest
var _active_action := ""
var _active_context := ""

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "SupabaseLobbyRequest"
	_request.timeout = 20.0
	_request.accept_gzip = false
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)

func create_room(display_name: String, game_version: String, generator_version: int, seed: int, course_length_px: int, token: String, context: String) -> void:
	_call("create_room", "create_multiplayer_room", {
		"p_display_name": display_name,
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
	_call("leave_room", "leave_multiplayer_room", {"p_room_id": room_id}, token, context)

func _call(action: String, rpc_name: String, payload: Dictionary, token: String, context: String) -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, null, tr("Another lobby request is already in progress."), context)
		return
	if token.is_empty():
		request_finished.emit(action, false, null, tr("A multiplayer identity is required."), context)
		return
	_active_action = action
	_active_context = context
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
		request_finished.emit(failed_action, false, null, tr("Could not start the lobby request (code %d).") % error, failed_context)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _active_action
	var context := _active_context
	_active_action = ""
	_active_context = ""
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		request_finished.emit(action, false, null, tr("Network error while contacting the lobby service (code %d).") % result, context)
		return
	if response_code < 200 or response_code >= 300:
		request_finished.emit(action, false, null, _friendly_error(parsed, response_code), context)
		return
	request_finished.emit(action, true, parsed, "", context)

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
