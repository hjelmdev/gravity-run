extends Node

const SectionScript := preload("res://ui/multiplayer_v2/mp_achievement_result_section.gd")
const TEST_PENDING_FILE := "res://.godot/mp_achievement_result_test.cfg"
const TEST_USER := "77000000-0000-4000-8000-000000000099"

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

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	AccountProgress._mp_pending_path = TEST_PENDING_FILE
	if is_instance_valid(AccountProgress._provider):
		AccountProgress._provider.queue_free()
	var provider := FakeProvider.new()
	get_tree().root.add_child(provider)
	AccountProgress._provider = provider
	provider.request_finished.connect(AccountProgress._on_request_finished)
	AuthService.is_authenticated = true
	AuthService.user_id = TEST_USER
	var payload := Marshalls.utf8_to_base64(JSON.stringify({"sub": TEST_USER, "is_anonymous": false})).replace("+", "-").replace("/", "_").trim_suffix("=")
	AuthService.set("_access_token", "test.%s.test" % payload)
	AccountProgress._activate_user(TEST_USER)
	await get_tree().process_frame
	var section := SectionScript.new()
	add_child(section)
	section.call("begin_round", "round-result-a", 2)
	var run_context: Dictionary = AccountProgress.begin_multiplayer_achievement_run("round-result-a", 2)
	var start_context := str(provider.starts.back().context)
	AccountProgress._on_request_finished("mp_achievement_start", true, {"started": true}, "", start_context)
	AccountProgress.complete_multiplayer_achievement_run(run_context, "dead", 321, 7, ["ghost"])
	var record_context := str(provider.records.back().context)
	AchievementService.finish_run()
	section.call("show_terminal_result", "round-result-a", 2)
	AccountProgress._on_request_finished("mp_achievement_record", true, {"new_achievements": [{"achievement_id": "confirmed_test_achievement", "tier": 1}], "achievement_state": {}}, "", record_context)
	_check(bool(section.visible) and int(section.call("unlock_count")) == 1, "late confirmed unlock appears in the actual result section after the provisional run has finished")
	AccountProgress.multiplayer_run_unlocks_received.emit("round-result-a", 2, [{"achievement_id": "confirmed_test_achievement", "tier": 1}])
	_check(int(section.call("unlock_count")) == 1 and section.get_child_count() == 2, "duplicate receipt does not duplicate the unlock row")
	AccountProgress.multiplayer_run_unlocks_received.emit("older-round", 2, [{"achievement_id": "stale", "tier": 1}])
	AccountProgress.multiplayer_run_unlocks_received.emit("round-result-a", 1, [{"achievement_id": "wrong-slot", "tier": 1}])
	_check(int(section.call("unlock_count")) == 1, "stale round and remote participant unlocks are ignored")
	section.call("begin_round", "round-result-b", 2)
	_check(not section.visible and int(section.call("unlock_count")) == 0, "rematch clears prior round unlock presentation")
	AccountProgress._mp_pending_path = AccountProgress.MP_PENDING_PATH
	if FileAccess.file_exists(TEST_PENDING_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PENDING_FILE))
	provider.queue_free()
	for failure in failures:
		push_error(failure)
	print("MP_ACHIEVEMENT_RESULT_SECTION_TEST failures=%d" % failures.size())
	section.queue_free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
