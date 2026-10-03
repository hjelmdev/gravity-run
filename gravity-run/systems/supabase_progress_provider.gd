extends Node

const Config = preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)

var _progress_request: HTTPRequest
var _run_request: HTTPRequest
var _leaderboard_request: HTTPRequest
var _monthly_leaderboard_request: HTTPRequest
var _achievements_request: HTTPRequest
var _mp_start_request: HTTPRequest
var _mp_record_request: HTTPRequest
var _progress_context := ""
var _run_context := ""
var _achievement_context := ""
var _mp_context := ""

func _ready() -> void:
	_progress_request = _make_request("AccountProgressRead")
	_run_request = _make_request("AccountProgressWrite")
	_leaderboard_request = _make_request("TotalDistanceLeaderboard")
	_monthly_leaderboard_request = _make_request("MonthlyDistanceLeaderboard")
	_achievements_request = _make_request("AccountAchievementsRead")
	_mp_start_request = _make_request("MultiplayerAchievementStart")
	_mp_record_request = _make_request("MultiplayerAchievementRecord")
	_progress_request.request_completed.connect(_on_rpc_completed.bind("load_progress"))
	_run_request.request_completed.connect(_on_rpc_completed.bind("record_run"))
	_leaderboard_request.request_completed.connect(_on_leaderboard_completed)
	_monthly_leaderboard_request.request_completed.connect(_on_monthly_leaderboard_completed)
	_achievements_request.request_completed.connect(_on_achievements_completed)
	_mp_start_request.request_completed.connect(_on_mp_completed.bind("mp_achievement_start"))
	_mp_record_request.request_completed.connect(_on_mp_completed.bind("mp_achievement_record"))

func start_multiplayer_achievement_run(round_id: String, player_slot: int, access_token: String, context: String) -> void:
	_start_rpc(_mp_start_request, "mp_achievement_start", "start_my_multiplayer_v2_achievement_run", {"p_runtime_round_id": round_id, "p_player_slot": player_slot}, access_token, context)

func record_multiplayer_achievement_run(round_id: String, player_slot: int, terminal_state: String, distance_m: int, gravity_flips: int, hazards: Array, access_token: String, context: String) -> void:
	_start_rpc(_mp_record_request, "mp_achievement_record", "record_my_multiplayer_v2_achievement_run", {"p_runtime_round_id": round_id, "p_player_slot": player_slot, "p_terminal_state": terminal_state, "p_distance_m": distance_m, "p_gravity_flips": gravity_flips, "p_hazards": hazards}, access_token, context)

func load_progress(access_token: String, user_id: String) -> void:
	_start_rpc(_progress_request, "load_progress", "get_my_account_progress", {}, access_token, user_id)

func record_run(run_id: String, distance_m: int, coins: int, gravity_flips: int, hazards_encountered: Array, loot_pickup_indexes: Array, access_token: String, user_id: String) -> void:
	_start_rpc(_run_request, "record_run", "record_player_run_v2", {
		"p_run_id": run_id,
		"p_distance_m": distance_m,
		"p_coins_earned": coins,
		"p_gravity_flips": gravity_flips,
		"p_hazards_encountered": hazards_encountered,
		"p_loot_pickup_indexes": loot_pickup_indexes,
	}, access_token, user_id + "|" + run_id)

func fetch_total_distance_leaderboard() -> void:
	_request_public_leaderboard(_leaderboard_request, "total_distance_leaderboard", "get_total_distance_leaderboard", "Could not start loading total-distance leaderboard (code %d).")

func fetch_monthly_distance_leaderboard() -> void:
	_request_public_leaderboard(_monthly_leaderboard_request, "monthly_distance_leaderboard", "get_monthly_distance_leaderboard", "Could not start loading monthly leaderboard (code %d).")

func load_achievements(access_token: String, user_id: String) -> void:
	_start_rpc(_achievements_request, "load_achievements", "get_my_achievements", {}, access_token, user_id)

func _request_public_leaderboard(request: HTTPRequest, action: String, rpc_name: String, start_error: String) -> void:
	if request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, [], tr("A leaderboard request is already in progress."), "")
		return
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, rpc_name]
	var error := request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify({"p_limit": Config.MAX_ENTRIES}))
	if error != OK:
		request_finished.emit(action, false, [], tr(start_error) % error, "")

func _make_request(request_name: String) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.name = request_name
	request.timeout = 20.0
	request.accept_gzip = false
	add_child(request)
	return request

func _start_rpc(request: HTTPRequest, action: String, function_name: String, payload: Dictionary, access_token: String, context: String) -> void:
	if request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, null, tr("An account progress request is already in progress."), context)
		return
	if action == "load_progress":
		_progress_context = context
	elif action == "load_achievements":
		_achievement_context = context
	elif action in ["mp_achievement_start", "mp_achievement_record"]:
		_mp_context = context
	else:
		_run_context = context
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, function_name]
	var error := request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request_finished.emit(action, false, null, tr("Could not start the account progress request (code %d).") % error, context)

func _on_rpc_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, action: String) -> void:
	var context := _progress_context if action == "load_progress" else _achievement_context if action == "load_achievements" else _run_context
	_handle_completed(action, result, response_code, body, context)

func _on_leaderboard_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_handle_completed("total_distance_leaderboard", result, response_code, body, "")

func _on_monthly_leaderboard_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_handle_completed("monthly_distance_leaderboard", result, response_code, body, "")

func _on_achievements_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# AccountProgress checks the originating user before applying account data.
	# Preserve the user context captured when this request was started.
	_handle_completed("load_achievements", result, response_code, body, _achievement_context)

func _on_mp_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, action: String) -> void:
	_handle_completed(action, result, response_code, body, _mp_context)

func _handle_completed(action: String, result: int, response_code: int, body: PackedByteArray, context: String) -> void:
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		request_finished.emit(action, false, null, tr("Network error while saving account progress (code %d).") % result, context)
		return
	if response_code < 200 or response_code >= 300:
		var detail := str(parsed.get("message", parsed.get("details", ""))) if parsed is Dictionary else ""
		request_finished.emit(action, false, null, tr("Account progress request failed (HTTP %d). %s") % [response_code, detail], context)
		return
	if action in ["total_distance_leaderboard", "monthly_distance_leaderboard"] and not parsed is Array:
		request_finished.emit(action, false, [], tr("The distance leaderboard returned an unexpected response."), context)
		return
	if action in ["load_progress", "record_run", "load_achievements", "mp_achievement_start", "mp_achievement_record"] and not parsed is Dictionary:
		request_finished.emit(action, false, null, tr("The account progress service returned an unexpected response."), context)
		return
	request_finished.emit(action, true, parsed, "", context)
