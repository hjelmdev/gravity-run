extends Node

const Config = preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String)

var _request: HTTPRequest
var _active_action := ""

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "SupabaseProfileRequest"
	_request.timeout = 20.0
	_request.accept_gzip = false
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)

func load_profile(access_token: String) -> void:
	_call_rpc("load_profile", "get_my_player_profile", {}, access_token)

func save_nickname(nickname: String, access_token: String) -> void:
	_call_rpc("save_nickname", "set_my_player_nickname", {"p_nickname": nickname}, access_token)

func _call_rpc(action: String, function_name: String, payload: Dictionary, access_token: String) -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, null, tr("A profile request is already running."))
		return
	_active_action = action
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, function_name]
	var error := _request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_active_action = ""
		request_finished.emit(action, false, null, tr("Could not start the profile request (code %d).") % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _active_action
	_active_action = ""
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		request_finished.emit(action, false, null, tr("Network error while contacting the profile service (code %d).") % result)
		return
	if response_code < 200 or response_code >= 300:
		request_finished.emit(action, false, null, _friendly_error(parsed, response_code))
		return
	request_finished.emit(action, true, parsed, "")

func _friendly_error(response: Variant, response_code: int) -> String:
	var detail := ""
	if response is Dictionary:
		detail = str(response.get("message", response.get("details", ""))).to_lower()
	if "nickname_taken" in detail or "duplicate key" in detail or response_code == 409:
		return tr("That nickname is already taken. Choose another one.")
	if "invalid_nickname" in detail:
		return tr("Use 3–16 letters, numbers, or underscores for your nickname.")
	if response_code == 401 or response_code == 403:
		return tr("Your session expired. Please sign in again.")
	return tr("Profile request failed (HTTP %d).") % response_code
