extends Node

const ProgressScript := preload("res://systems/account_progress.gd")
const TEST_PENDING_FILE := "res://.godot/mp_achievement_retry_backoff_test.cfg"
const USER_ID := "77000000-0000-4000-8000-000000000098"

class FakeProvider extends Node:
	signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
	var starts: Array[Dictionary] = []
	var records: Array[Dictionary] = []
	var sync_failure_action := ""
	var sync_failure_message := ""
	var _dispatch_depth := 0
	var max_dispatch_depth := 0
	func load_progress(_token: String, _user: String) -> void: pass
	func load_achievements(_token: String, _user: String) -> void: pass
	func start_multiplayer_achievement_run(round_id: String, slot: int, _token: String, context: String) -> void:
		starts.append({"round_id": round_id, "slot": slot, "context": context})
		_maybe_fail("mp_achievement_start", context)
	func record_multiplayer_achievement_run(round_id: String, slot: int, terminal: String, distance: int, flips: int, hazards: Array, _token: String, context: String) -> void:
		records.append({"round_id": round_id, "slot": slot, "terminal": terminal, "distance": distance, "flips": flips, "hazards": hazards.duplicate(), "context": context})
		_maybe_fail("mp_achievement_record", context)
	func _maybe_fail(action: String, context: String) -> void:
		if action != sync_failure_action:
			return
		_dispatch_depth += 1
		max_dispatch_depth = maxi(max_dispatch_depth, _dispatch_depth)
		request_finished.emit(action, false, null, sync_failure_message, context)
		_dispatch_depth -= 1

var failures: Array[String] = []
var _progress: Node
var _provider: FakeProvider

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	AuthService.is_authenticated = true
	AuthService.user_id = USER_ID
	var payload := Marshalls.utf8_to_base64(JSON.stringify({"sub": USER_ID, "is_anonymous": false})).replace("+", "-").replace("/", "_").trim_suffix("=")
	AuthService.set("_access_token", "test.%s.test" % payload)
	_progress = ProgressScript.new()
	_progress._mp_pending_path = TEST_PENDING_FILE
	get_tree().root.add_child(_progress)
	await get_tree().process_frame
	if is_instance_valid(_progress._provider):
		_progress._provider.queue_free()
	_provider = FakeProvider.new()
	get_tree().root.add_child(_provider)
	_progress._provider = _provider
	_provider.request_finished.connect(_progress._on_request_finished)
	_progress._activate_user(USER_ID)

	var first: Dictionary = _progress.begin_multiplayer_achievement_run("retry-401-round", 1)
	var first_start := str(_provider.starts.back().context)
	AuthService.set("_refresh_pending", true) # Keep this isolated test from sending a real auth refresh.
	_progress._on_request_finished("mp_achievement_start", false, null, "Account progress request failed (HTTP 401). token expired", first_start)
	AuthService.set("_refresh_pending", false)
	var first_row := _find_row("retry-401-round")
	_check(not first_row.is_empty() and not bool(first_row.get("started", true)), "401 retains the start receipt and its payload")
	_check(int(first_row.get("retry_after_unix", 0)) > int(Time.get_unix_time_from_system()), "401 is deferred with persisted backoff")
	await get_tree().process_frame
	_check(_provider.starts.size() == 1, "transient 401 does not immediately retry after deferred callback")

	var fresh: Dictionary = _progress.begin_multiplayer_achievement_run("fresh-round-after-401", 1)
	_check(_provider.starts.size() == 2 and _provider.starts.back().round_id == "fresh-round-after-401", "a healthy later round can dispatch while the 401 row is backed off")
	var fresh_start := str(_provider.starts.back().context)
	_progress._on_request_finished("mp_achievement_start", true, {"started": true}, "", fresh_start)
	_progress.complete_multiplayer_achievement_run(fresh, "dead", 432, 5, ["ghost"])
	var fresh_record := str(_provider.records.back().context)
	_progress._on_request_finished("mp_achievement_record", false, null, "Account progress request failed (HTTP 429). rate limited", fresh_record)
	var record_row := _find_row("fresh-round-after-401")
	_check(bool(record_row.get("completed", false)) and int(record_row.get("distance_m", -1)) == 432 and record_row.get("hazards", []) == ["ghost"], "429 retains terminal metrics and hazards for retry")
	_check(int(record_row.get("retry_after_unix", 0)) > int(Time.get_unix_time_from_system()), "429 receives persisted backoff rather than immediate retry")

	_provider.sync_failure_action = "mp_achievement_start"
	_provider.sync_failure_message = "An account progress request is already in progress."
	var busy_first: Dictionary = _progress.begin_multiplayer_achievement_run("busy-round-a", 1)
	var after_busy_a := _find_row("busy-round-a")
	_check(_provider.max_dispatch_depth == 1 and int(after_busy_a.get("retry_after_unix", 0)) > int(Time.get_unix_time_from_system()), "synchronous busy callback is deferred without recursive dispatch")
	var before_fresh_busy := _provider.starts.size()
	var busy_second: Dictionary = _progress.begin_multiplayer_achievement_run("busy-round-b", 1)
	_check(_provider.starts.size() == before_fresh_busy + 1 and _provider.starts.back().round_id == "busy-round-b", "busy backoff on an older row lets a new round get a dispatch turn")
	await get_tree().process_frame
	_check(_provider.starts.size() == before_fresh_busy + 1 and _provider.max_dispatch_depth == 1, "synchronous busy failure stays bounded across deferred frames")

	for context in [first, fresh, busy_first, busy_second]:
		_progress.abandon_multiplayer_achievement_run(context)
	for failure in failures:
		push_error(failure)
	print("MULTIPLAYER_ACHIEVEMENT_RETRY_BACKOFF_TEST failures=%d starts=%d records=%d max_sync_depth=%d" % [failures.size(), _provider.starts.size(), _provider.records.size(), _provider.max_dispatch_depth])
	_cleanup()
	get_tree().quit(1 if not failures.is_empty() else 0)

func _find_row(round_id: String) -> Dictionary:
	for entry in _progress._load_mp_queue_for_user(USER_ID):
		if str(entry.get("runtime_round_id", "")) == round_id:
			return entry
	return {}

func _cleanup() -> void:
	if is_instance_valid(_progress):
		_progress._retry_timer.stop()
		_progress.queue_free()
	if is_instance_valid(_provider):
		_provider.queue_free()
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	AuthService.is_authenticated = false
	AuthService.user_id = ""
	AuthService.set("_access_token", "")
	AuthService.set("_refresh_token", "")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
