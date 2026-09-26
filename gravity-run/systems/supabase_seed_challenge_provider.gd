extends Node

signal request_finished(action: String, success: bool, data: Variant, error_message: String)

const Config := preload("res://systems/leaderboard_config.gd")

var _request: HTTPRequest
var _action := ""
var _library_request: HTTPRequest
var _library_action := ""

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	_request.accept_gzip = false
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_library_request = HTTPRequest.new()
	_library_request.timeout = 15.0
	_library_request.accept_gzip = false
	_library_request.request_completed.connect(_on_library_request_completed)
	add_child(_library_request)

func create_challenge(generator_version: int, seed: int, ruleset: Dictionary, fingerprint: String, nickname: String, challenge_name: String) -> void:
	_request_rpc("create", "create_named_seed_challenge", {
		"p_generator_version": generator_version,
		"p_seed": seed,
		"p_ruleset_fingerprint": fingerprint,
		"p_ruleset": ruleset,
		"p_nickname": nickname.strip_edges(),
		"p_challenge_name": challenge_name.strip_edges(),
	})

func fetch_challenge(challenge_code: String) -> void:
	_request_rpc("definition", "get_named_seed_challenge", {"p_challenge_code": challenge_code.strip_edges().to_upper()})

func fetch_leaderboard(challenge_code: String) -> void:
	_request_rpc("leaderboard", "get_seed_challenge_leaderboard", {"p_challenge_code": challenge_code.strip_edges().to_upper()})

func submit_run(challenge_code: String, nickname: String, distance_m: int) -> void:
	_request_rpc("submit", "submit_seed_challenge_run", {
		"p_challenge_code": challenge_code.strip_edges().to_upper(),
		"p_nickname": nickname.strip_edges(),
		"p_distance_m": distance_m,
	})

func save_to_library(challenge_code: String) -> void:
	_request_rpc("save_library", "save_seed_challenge_to_library", {"p_challenge_code": challenge_code.strip_edges().to_upper()})

func fetch_library() -> void:
	_request_rpc("fetch_library", "list_my_seed_challenges", {})

func hide_from_library(challenge_code: String) -> void:
	_request_rpc("hide_library", "hide_my_seed_challenge", {"p_challenge_code": challenge_code.strip_edges().to_upper()})

func _request_rpc(action: String, function_name: String, payload: Dictionary) -> void:
	var is_library_request := action.ends_with("_library")
	var request: HTTPRequest = _library_request if is_library_request else _request
	if request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, null, "request_in_progress")
		return
	if is_library_request:
		_library_action = action
	else:
		_action = action
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, function_name]
	var error := request.request(url, _headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		if is_library_request:
			_library_action = ""
		else:
			_action = ""
		request_finished.emit(action, false, null, "network_error_%d" % error)

func _headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"apikey: %s" % Config.PUBLISHABLE_KEY,
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var auth_service := get_node_or_null("/root/AuthService")
	if auth_service != null and bool(auth_service.get("is_authenticated")):
		var access_token := str(auth_service.call("get_access_token"))
		if not access_token.is_empty():
			headers.append("Authorization: Bearer %s" % access_token)
	return headers

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _action
	_action = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var error_message := "" if success else _extract_error(parsed, response_code, result)
	request_finished.emit(action, success, parsed, error_message)

func _on_library_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _library_action
	_library_action = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var error_message := "" if success else _extract_error(parsed, response_code, result)
	request_finished.emit(action, success, parsed, error_message)

func _extract_error(parsed: Variant, response_code: int, result: int) -> String:
	if parsed is Dictionary:
		var server_message := str(parsed.get("message", parsed.get("hint", "")))
		if not server_message.is_empty():
			return server_message
	return "network_error_%d" % result if result != HTTPRequest.RESULT_SUCCESS else "http_error_%d" % response_code
