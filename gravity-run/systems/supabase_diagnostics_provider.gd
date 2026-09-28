extends Node

const Config := preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)

var _request: HTTPRequest
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.name = "SupabaseDiagnosticsRequest"
	_request.timeout = 20.0
	_request.accept_gzip = false
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)

func set_opt_in(enabled: bool, token: String, context: String) -> void:
	_rpc("opt_in", "set_multiplayer_diagnostic_opt_in", {"p_enabled": enabled}, token, context)

func create_session(room_id: String, match_id: String, token: String, context: String) -> void:
	_rpc("create_session", "create_multiplayer_diagnostic_session", {"p_room_id": room_id, "p_match_id": match_id}, token, context)

func upload_report(session_id: String, match_id: String, report_id: String, schema_version: int, build_id: String, summary: Dictionary, report: Dictionary, token: String, context: String) -> void:
	_rpc("upload_report", "upload_multiplayer_diagnostic_report", {
		"p_session_id": session_id, "p_match_id": match_id, "p_report_id": report_id,
		"p_schema_version": schema_version, "p_build_id": build_id,
		"p_summary": summary, "p_report": report,
	}, token, context)

func list_sessions(token: String, limit: int, context: String) -> void:
	_rpc("list_sessions", "list_my_multiplayer_diagnostic_sessions", {"p_limit": clampi(limit, 1, 20)}, token, context)

func fetch_session(session_id: String, token: String, context: String) -> void:
	_rpc("fetch_session", "get_multiplayer_diagnostic_session_reports", {"p_session_id": session_id}, token, context)

func _rpc(action: String, rpc_name: String, payload: Dictionary, token: String, context: String) -> void:
	if token.is_empty():
		request_finished.emit(action, false, null, "An authenticated multiplayer identity is required.", context)
		return
	_queue.append({"action": action, "rpc_name": rpc_name, "payload": payload, "token": token, "context": context})
	_start_next()

func _start_next() -> void:
	if not _active.is_empty() or _queue.is_empty():
		return
	_active = _queue.pop_front()
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Authorization: Bearer " + str(_active.token),
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, str(_active.rpc_name)]
	var error := _request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(_active.payload))
	if error != OK:
		var failed := _active
		_active = {}
		request_finished.emit(str(failed.action), false, null, "Could not start the diagnostic request (code %d)." % error, str(failed.context))
		call_deferred("_start_next")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed := _active
	_active = {}
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		request_finished.emit(str(completed.get("action", "")), false, null, "Network error during diagnostic request (code %d)." % result, str(completed.get("context", "")))
	elif response_code < 200 or response_code >= 300:
		var detail := str(parsed.get("message", parsed.get("details", parsed))) if parsed is Dictionary else response_text.left(300)
		request_finished.emit(str(completed.get("action", "")), false, null, "Diagnostic service rejected the request (HTTP %d): %s" % [response_code, detail], str(completed.get("context", "")))
	else:
		request_finished.emit(str(completed.get("action", "")), true, parsed, "", str(completed.get("context", "")))
	call_deferred("_start_next")
