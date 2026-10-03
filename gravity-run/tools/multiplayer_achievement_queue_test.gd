extends Node

const ProgressScript := preload("res://systems/account_progress.gd")
const TEST_PENDING_FILE := "res://.godot/mp_achievement_queue_test.cfg"
const USER_A := "77000000-0000-4000-8000-000000000001"
const USER_B := "77000000-0000-4000-8000-000000000002"

class FakeProvider extends Node:
	signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
	var starts: Array[Dictionary] = []
	var records: Array[Dictionary] = []
	func load_progress(_token: String, _user: String) -> void: pass
	func load_achievements(_token: String, _user: String) -> void: pass
	func start_multiplayer_achievement_run(round_id: String, slot: int, _token: String, context: String) -> void:
		starts.append({"round_id": round_id, "slot": slot, "context": context})
	func record_multiplayer_achievement_run(round_id: String, slot: int, terminal: String, distance: int, flips: int, hazards: Array, _token: String, context: String) -> void:
		records.append({"round_id": round_id, "slot": slot, "terminal": terminal, "distance": distance, "flips": flips, "hazards": hazards.duplicate(), "context": context})

var failures: Array[String] = []
var _progress: Node
var _provider: FakeProvider

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# This isolated file is test-owned; clear crash residue before the regression.
	var test_queue_path := ProjectSettings.globalize_path(TEST_PENDING_FILE)
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(test_queue_path)
	var match_source := FileAccess.get_file_as_string("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
	var started_hook := match_source.find("func _on_round_started(")
	var next_hook := match_source.find("\nfunc ", started_hook + 5)
	var started_body := match_source.substr(started_hook, next_hook - started_hook) if started_hook >= 0 and next_hook > started_hook else ""
	_check(started_body.contains("AccountProgress.begin_multiplayer_achievement_run"), "receipt start is called only from the real round-start callback")
	_check(match_source.contains("_finish_mp_achievement_run(result)"), "metrics are submitted only from the terminal results callback")
	AuthService.is_authenticated = false
	_progress = ProgressScript.new()
	_progress._mp_pending_path = TEST_PENDING_FILE
	get_tree().root.add_child(_progress)
	await get_tree().process_frame
	if is_instance_valid(_progress._provider):
		_progress._provider.queue_free()
	_provider = FakeProvider.new()
	get_tree().root.add_child(_provider)
	_progress._provider = _provider
	_set_auth(USER_A, false)
	_progress._activate_user(USER_A)
	var context: Dictionary = _progress.begin_multiplayer_achievement_run("runtime-round-stable-a1", 1)
	_check(not context.is_empty(), "signed-in account starts MP receipt at true round start")
	var legacy_payload := Marshalls.utf8_to_base64(JSON.stringify({"sub": USER_A})).replace("+", "-").replace("/", "_").trim_suffix("=")
	_check(not _progress._jwt_is_anonymous("test.%s.test" % legacy_payload), "valid signed-in JWTs without the optional anonymous claim remain eligible")
	_check(_provider.starts.size() == 1, "start RPC is dispatched for signed-in participant")
	if _provider.starts.is_empty():
		_cleanup()
		push_error("achievement queue test setup failed: starts=%d inflight=%s queue=%s" % [_provider.starts.size(), str(_progress._mp_inflight_context), JSON.stringify(_progress._load_mp_queue_for_user(USER_A))])
		get_tree().quit(1)
		return
	_check(str(_provider.starts[0].round_id) == "runtime-round-stable-a1", "start RPC uses stable runtime round id")
	var callback_context := str(_provider.starts[0].context)
	_set_auth(USER_B, false)
	_progress._activate_user(USER_B)
	_progress._on_request_finished("mp_achievement_start", true, {"started": true}, "", callback_context)
	var old_queue: Array[Dictionary] = _progress._load_mp_queue_for_user(USER_A)
	_check(old_queue.size() == 1 and bool(old_queue[0].get("started", false)), "late start ACK persists only to its captured original account")
	_check(_progress._load_mp_queue_for_user(USER_B).is_empty(), "account switch does not transfer the old receipt")
	_check(_provider.records.is_empty(), "old account receipt is not sent while another account is active")
	_set_auth(USER_A, false)
	_progress._activate_user(USER_A)
	_check(_provider.records.is_empty(), "unfinished started receipt does not dispatch a terminal record")
	var next_context: Dictionary = _progress.begin_multiplayer_achievement_run("runtime-round-rematch-b2", 1)
	_check(_provider.starts.size() == 2 and _provider.starts[1].round_id == "runtime-round-rematch-b2", "an unfinished prior round does not block a rematch start receipt")
	if _provider.starts.size() < 2:
		_cleanup()
		push_error("rematch start not dispatched")
		get_tree().quit(1)
		return
	var next_start_context := str(_provider.starts[1].context)
	_progress._on_request_finished("mp_achievement_start", true, {"started": true}, "", next_start_context)
	_progress.complete_multiplayer_achievement_run(next_context, "dead", 321, 7, ["ghost", "spike_group"])
	_check(_provider.records.size() == 1, "completed rematch dispatches despite unfinished older round")
	var record: Dictionary = _provider.records[0]
	_check(record.round_id == "runtime-round-rematch-b2" and record.slot == 1 and record.distance == 321 and record.flips == 7, "retry preserves round, player slot and terminal metrics")
	_check(record.hazards == ["ghost", "spike_group"], "retry preserves deduplicated encountered hazards")
	_progress._on_request_finished("mp_achievement_record", true, {"progress": {"wallet_coins": 19, "total_distance_m": 321, "best_distance_m": 321}, "achievement_state": {"total_distance_m": 321}, "new_achievements": []}, "", str(record.context))
	var remaining_rows: Array[Dictionary] = _progress._load_mp_queue_for_user(USER_A)
	_check(remaining_rows.size() == 1 and remaining_rows[0].runtime_round_id == "runtime-round-stable-a1", "successful receipt ACK removes only its durable MP queue row")
	_progress.abandon_multiplayer_achievement_run(context)
	_check(_progress._load_mp_queue_for_user(USER_A).is_empty(), "explicit abort abandons the unfinished receipt without submitting metrics")
	_check(_progress.total_distance_m == 321 and _progress.best_distance_m == 321 and _progress.wallet_coins == 19, "metrics receipt refreshes account progress from server response")
	var permanent_context: Dictionary = _progress.begin_multiplayer_achievement_run("runtime-round-permanent-c3", 1)
	var permanent_start_context := str(_provider.starts.back().context)
	_progress._on_request_finished("mp_achievement_start", true, {"started": true}, "", permanent_start_context)
	_progress.complete_multiplayer_achievement_run(permanent_context, "dead", 100, 1, [])
	var permanent_record: Dictionary = _provider.records.back()
	_progress._on_request_finished("mp_achievement_record", false, null, "Account progress request failed (HTTP 400). multiplayer_receipt_conflict", str(permanent_record.context))
	var after_permanent: Dictionary = _progress.begin_multiplayer_achievement_run("runtime-round-after-error-d4", 1)
	_check(_provider.starts.back().round_id == "runtime-round-after-error-d4", "permanent old receipt failure does not starve a later round")
	_progress.abandon_multiplayer_achievement_run(after_permanent)
	var sp_config := ConfigFile.new()
	sp_config.load("user://gravity_run_pending_runs.cfg")
	_check(sp_config.get_value("pending", USER_A, []).is_empty(), "MP receipts never enter the SP wallet/run queue")
	_set_auth(USER_A, true)
	_progress._activate_user(USER_A)
	var anonymous_context: Dictionary = _progress.begin_multiplayer_achievement_run("anonymous-round", 1)
	_check(anonymous_context.is_empty(), "anonymous guest cannot queue an account receipt")
	for failure in failures:
		push_error(failure)
	_cleanup()
	print("MULTIPLAYER_ACHIEVEMENT_QUEUE_TEST failures=%d start_calls=%d record_calls=%d" % [failures.size(), _provider.starts.size(), _provider.records.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _set_auth(user_id: String, anonymous: bool) -> void:
	AuthService.is_authenticated = true
	AuthService.user_id = user_id
	var payload := Marshalls.utf8_to_base64(JSON.stringify({"sub": user_id, "is_anonymous": anonymous})).replace("+", "-").replace("/", "_").trim_suffix("=")
	AuthService.set("_access_token", "test.%s.test" % payload)
	AuthService.set("_refresh_token", "test-refresh")

func _cleanup() -> void:
	if is_instance_valid(_progress):
		_progress._retry_timer.stop()
		_progress.queue_free()
	if is_instance_valid(_provider):
		_provider.queue_free()
	var absolute_path := ProjectSettings.globalize_path(TEST_PENDING_FILE)
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(absolute_path)
	AuthService.is_authenticated = false
	AuthService.user_id = ""
	AuthService.set("_access_token", "")
	AuthService.set("_refresh_token", "")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
