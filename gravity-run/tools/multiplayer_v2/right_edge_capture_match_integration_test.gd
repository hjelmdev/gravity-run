extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")

var failures := 0
var _match: Node
var _finished := false
var _finish_success := false

func _ready() -> void:
	var built: Dictionary = Builder.new().build(100000014, 12000, 15)
	_assert(built.get("manifest") != null, "fixture builds a real supported multiplayer manifest")
	if built.get("manifest") == null:
		await _finish()
		return
	MultiplayerV2Service.current_manifest = built.manifest
	MultiplayerV2Service.session = {"role": "host", "round_id": "capture-match-test", "local_peer_id": 1}
	MultiplayerV2Service.room_state = {"phase": "RUNNING", "room_id": "fixture-room", "lobby_generation": 1, "members": []}
	_match = MatchScene.instantiate()
	add_child(_match)
	call_deferred("_exercise_match_overlay")

func _exercise_match_overlay() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var start_button := _match.get("_right_edge_start_button") as Button
	var cancel_button := _match.get("_right_edge_cancel_button") as Button
	var capture: Node = _match.get("_right_edge_capture")
	_assert(is_instance_valid(start_button) and is_instance_valid(cancel_button), "actual MP diagnostics overlay creates localized capture and cancel controls")
	_assert(is_instance_valid(capture) and int(capture.get("readback_count")) == 0, "actual MP overlay leaves capture inactive without viewport readback")
	if not is_instance_valid(start_button) or not is_instance_valid(cancel_button) or not is_instance_valid(capture):
		await _finish()
		return
	_match.call("_toggle_debug_panel")
	await get_tree().process_frame
	var start_rect := start_button.get_global_rect()
	_assert(start_rect.size.x > 0.0 and start_rect.size.y > 0.0, "start control has an input-visible viewport rect")
	_push_touch(start_rect.get_center())
	_assert(bool(capture.get("is_capturing")), "real overlay start click starts the production burst")
	_assert(not bool(_match.get("_debug_open")), "starting closes the diagnostics overlay before capture")
	_assert(cancel_button.visible, "a small cancel action remains reachable while the overlay is closed")
	_assert(int(capture.get("readback_count")) == 0, "overlay start handler does not synchronously stall for readback")
	_assert(int(_match.get("_pending_flip_direction")) == 0, "diagnostics touch/click does not queue a gravity flip")
	await get_tree().process_frame
	capture.capture_finished.connect(_on_capture_finished)
	var cancel_rect := cancel_button.get_global_rect()
	_assert(cancel_rect.size.x > 0.0 and cancel_rect.size.y > 0.0, "cancel control has an input-visible viewport rect")
	_push_touch(cancel_rect.get_center())
	var started_usec := Time.get_ticks_usec()
	while not _finished and Time.get_ticks_usec() - started_usec < 1_000_000:
		await get_tree().process_frame
	_assert(_finished and not _finish_success, "actual overlay cancel ends the same production capture cleanly")
	_assert(not bool(capture.get("is_capturing")) and not bool(capture.get("has_capture")), "cancel leaves no retained capture buffers")
	_assert(int(_match.get("_pending_flip_direction")) == 0, "cancel interaction still does not queue gravity input")
	_test_localized_budget_status(capture)
	await _finish()

func _test_localized_budget_status(capture: Node) -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("sv")
	capture.set("completion_reason", "raw_image_budget")
	_match.call("_on_right_edge_capture_state_changed", "complete", 7, "localiserat statusmeddelande")
	var status := _match.get("_right_edge_capture_status") as Label
	var expected_notice := TranslationServer.translate("The raw image memory limit was reached.")
	_assert(is_instance_valid(status) and String(status.text).contains(expected_notice), "Swedish cap notice is selected from the structured completion reason, independent of localized message text")
	capture.set("completion_reason", "complete")
	TranslationServer.set_locale(previous_locale)

func _push_touch(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.position = position
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventScreenTouch.new()
	event.index = 7
	event.position = position
	event.pressed = false
	get_viewport().push_input(event)

func _on_capture_finished(success: bool, _frame_count: int, _reason: String) -> void:
	_finished = true
	_finish_success = success

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _finish() -> void:
	if is_instance_valid(_match):
		_match.queue_free()
	MultiplayerV2Service.current_manifest = null
	MultiplayerV2Service.world_simulation = null
	MultiplayerV2Service.session.clear()
	MultiplayerV2Service.room_state.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	print("RIGHT_EDGE_CAPTURE_MATCH_INTEGRATION_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
