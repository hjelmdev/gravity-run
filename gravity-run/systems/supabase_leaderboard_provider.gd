extends "res://systems/leaderboard_provider.gd"

const Config = preload("res://systems/leaderboard_config.gd")

var _read_request: HTTPRequest
var _write_request: HTTPRequest

func _ready() -> void:
	_read_request = HTTPRequest.new()
	_read_request.name = "LeaderboardReadRequest"
	_read_request.timeout = 20.0
	# Browsers transparently decompress HTTP responses. Avoid Godot trying to
	# decompress the already-decoded body a second time in Web exports.
	_read_request.accept_gzip = false
	add_child(_read_request)
	_read_request.request_completed.connect(_on_read_completed)

	_write_request = HTTPRequest.new()
	_write_request.name = "LeaderboardWriteRequest"
	_write_request.timeout = 20.0
	_write_request.accept_gzip = false
	add_child(_write_request)
	_write_request.request_completed.connect(_on_write_completed)

func fetch_top_runs() -> void:
	if _read_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		top_runs_received.emit([], tr("A leaderboard request is already in progress."))
		return
	var url := "%s/rest/v1/%s?select=player_name,distance_m,coins,created_at&order=distance_m.desc,created_at.asc&limit=%d" % [Config.PROJECT_URL, Config.TABLE_NAME, Config.MAX_ENTRIES]
	var error := _read_request.request(url, _headers(), HTTPClient.METHOD_GET)
	if error != OK:
		push_warning("Leaderboard GET could not start. Godot error: %d" % error)
		top_runs_received.emit([], tr("Could not start loading the leaderboard (code %d).") % error)

func submit_run(player_name: String, distance_m: int, coins: int, modified: bool = false) -> void:
	if _write_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		submission_finished.emit(false, tr("A score is already being submitted."))
		return
	var fields := {
		"player_name": player_name,
		"distance_m": distance_m,
		"coins": coins,
	}
	# Only sent for modified runs: a table without the column keeps accepting clean runs.
	if modified:
		fields["modified"] = true
	var payload := JSON.stringify(fields)
	var headers := _headers()
	headers.append("Content-Type: application/json")
	headers.append("Prefer: return=minimal")
	var url := "%s/rest/v1/%s" % [Config.PROJECT_URL, Config.TABLE_NAME]
	var error := _write_request.request(url, headers, HTTPClient.METHOD_POST, payload)
	if error != OK:
		push_warning("Leaderboard POST could not start. Godot error: %d" % error)
		submission_finished.emit(false, tr("Could not start submitting the score (code %d).") % error)

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Accept: application/json",
	])

func _on_read_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("Leaderboard GET failed before receiving an HTTP response. HTTPRequest result: %d" % result)
		top_runs_received.emit([], tr("Network error while loading leaderboard (code %d).") % result)
		return
	if response_code < 200 or response_code >= 300:
		top_runs_received.emit([], tr("Supabase returned HTTP %d. Check that the leaderboard table is installed.") % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Array:
		top_runs_received.emit([], tr("The leaderboard returned an unexpected response."))
		return
	var runs: Array = []
	for entry in parsed:
		if entry is Dictionary:
			runs.append(entry)
	top_runs_received.emit(runs, "")

func _on_write_completed(result: int, response_code: int, _headers_received: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("Leaderboard POST failed before receiving an HTTP response. HTTPRequest result: %d" % result)
		submission_finished.emit(false, tr("Network error while submitting score (code %d).") % result)
		return
	if response_code < 200 or response_code >= 300:
		var detail := body.get_string_from_utf8().strip_edges()
		submission_finished.emit(false, tr("Supabase returned HTTP %d%s") % [response_code, ": " + detail if not detail.is_empty() else "."])
		return
	submission_finished.emit(true, "")
