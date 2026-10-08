extends Node

signal request_finished(action: String, version: int, seed: int, success: bool, data: Variant, error_message: String)

const Config := preload("res://systems/leaderboard_config.gd")

var _fetch_request: HTTPRequest
var _submit_request: HTTPRequest
var _fetch_context := Vector2i.ZERO
var _submit_context := Vector2i.ZERO

func _ready() -> void:
	_fetch_request = HTTPRequest.new()
	_fetch_request.timeout = 15.0
	_fetch_request.accept_gzip = false
	_fetch_request.request_completed.connect(_on_fetch_completed)
	add_child(_fetch_request)
	_submit_request = HTTPRequest.new()
	_submit_request.timeout = 15.0
	_submit_request.accept_gzip = false
	_submit_request.request_completed.connect(_on_submit_completed)
	add_child(_submit_request)

func fetch_scores(version: int, seed: int) -> void:
	if _fetch_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit("fetch", version, seed, false, [], "request_in_progress")
		return
	_fetch_context = Vector2i(version, seed)
	var url := "%s/rest/v1/rpc/get_seed_challenge_leaderboard" % Config.PROJECT_URL
	var payload := JSON.stringify({"p_generator_version": version, "p_seed": seed})
	var error := _fetch_request.request(url, _headers(), HTTPClient.METHOD_POST, payload)
	if error != OK:
		request_finished.emit("fetch", version, seed, false, [], "network_error_%d" % error)

func submit_run(version: int, seed: int, nickname: String, distance_m: int, modified: bool = false) -> void:
	if _submit_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit("submit", version, seed, false, null, "request_in_progress")
		return
	_submit_context = Vector2i(version, seed)
	var url := "%s/rest/v1/rpc/submit_seed_challenge_run" % Config.PROJECT_URL
	var fields := {
		"p_generator_version": version,
		"p_seed": seed,
		"p_nickname": nickname.strip_edges(),
		"p_distance_m": distance_m
	}
	# Only sent for modified runs: servers without the parameter keep working for clean runs.
	if modified:
		fields["p_modified"] = true
	var payload := JSON.stringify(fields)
	var error := _submit_request.request(url, _headers(), HTTPClient.METHOD_POST, payload)
	if error != OK:
		request_finished.emit("submit", version, seed, false, null, "network_error_%d" % error)

func _headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"apikey: %s" % Config.PUBLISHABLE_KEY,
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var auth_service := get_node_or_null("/root/AuthService")
	if auth_service != null and bool(auth_service.get("is_authenticated")):
		var access_token := str(auth_service.call("get_access_token"))
		if access_token.is_empty():
			return headers
		headers.append("Authorization: Bearer %s" % access_token)
	return headers

func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_finish_request("fetch", _fetch_context, result, response_code, body)

func _on_submit_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_finish_request("submit", _submit_context, result, response_code, body)

func _finish_request(action: String, context: Vector2i, result: int, response_code: int, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var error_message := ""
	if not success:
		error_message = _extract_error(parsed, response_code, result)
	request_finished.emit(action, context.x, context.y, success, parsed, error_message)

func _extract_error(parsed: Variant, response_code: int, result: int) -> String:
	if parsed is Dictionary:
		var server_message := str(parsed.get("message", parsed.get("hint", "")))
		if not server_message.is_empty():
			return server_message
	return "network_error_%d" % result if result != HTTPRequest.RESULT_SUCCESS else "http_error_%d" % response_code
