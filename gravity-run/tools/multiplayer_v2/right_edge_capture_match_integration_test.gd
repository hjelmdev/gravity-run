extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")

var failures := 0
var _match: Node

func _ready() -> void:
	Input.emulate_mouse_from_touch = true
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
	var audio_button := _match.get("_audio_timing_capture_button") as Button
	var capture: Node = _match.get("_right_edge_capture")
	_assert(is_instance_valid(start_button) and is_instance_valid(cancel_button), "actual MP diagnostics overlay creates localized capture and cancel controls")
	_assert(is_instance_valid(audio_button), "actual MP diagnostics overlay creates standalone audio timing control")
	_assert(is_instance_valid(capture) and int(capture.get("readback_count")) == 0, "actual MP overlay leaves capture inactive without viewport readback")
	if not is_instance_valid(start_button) or not is_instance_valid(cancel_button) or not is_instance_valid(audio_button) or not is_instance_valid(capture):
		await _finish()
		return
	_match.call("_toggle_debug_panel")
	await get_tree().process_frame
	_match.set("_audio_timing_capture_duration_seconds", 0.05)
	var audio_rect := audio_button.get_global_rect()
	_assert(audio_rect.size.x > 0.0 and audio_rect.size.y > 0.0, "standalone audio control has an input-visible viewport rect")
	_push_touch(audio_rect.get_center())
	_assert(int(_match.get("_pending_flip_direction")) == 0, "audio control touch/release does not queue a gravity flip")
	var touch_dispatched_to_control := bool(_match.get("_audio_timing_capture_active"))
	print("MP_AUDIO_TOUCH_DISPATCHED=%s" % touch_dispatched_to_control)
	if not touch_dispatched_to_control:
		audio_button.pressed.emit()
	_assert(bool(_match.get("_audio_timing_capture_active")) and SfxController.diagnostic_capture_active(), "audio control handler starts bounded audio-only capture")
	_assert(not bool(_match.get("_debug_open")) and int(_match.get("_pending_flip_direction")) == 0, "audio control action closes the overlay without queuing a flip")
	SfxController.play_event("coin", "audio-only-match-test")
	await get_tree().process_frame
	_assert(bool(_match.get("_audio_timing_capture_active")), "audio-only trace continues after the overlay closes so gameplay can resume")
	var audio_started_usec := Time.get_ticks_usec()
	while bool(_match.get("_audio_timing_capture_active")) and Time.get_ticks_usec() - audio_started_usec < 1_000_000:
		await get_tree().process_frame
	_assert(int(capture.get("readback_count")) == 0 and not bool(capture.get("is_capturing")), "audio-only capture does not start screenshot readback")
	var audio_snapshot: Dictionary = _match.get("_audio_timing_capture_snapshot")
	_assert(not bool(_match.get("_audio_timing_capture_active")) and str(audio_snapshot.get("capture_reason", "")) == "duration_complete" and not audio_snapshot.get("events", []).is_empty(), "bounded MP audio capture auto-stops and retains event timing for diagnostics export")
	var user_dir := ProjectSettings.globalize_path("user://")
	var files_before := DirAccess.get_files_at(user_dir)
	_match.call("_save_diagnostics")
	var report_filename := ""
	for filename in DirAccess.get_files_at(user_dir):
		if filename.begins_with("multiplayer_match_") and not files_before.has(filename):
			report_filename = filename
	_assert(not report_filename.is_empty(), "normal Save diagnostics exports the finished audio-only trace")
	if not report_filename.is_empty():
		var report_path := user_dir.path_join(report_filename)
		var parsed_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		_assert(parsed_report is Dictionary, "audio-only diagnostics export is valid JSON")
		if parsed_report is Dictionary:
			var exported_audio: Dictionary = parsed_report.get("sfx_audio_diagnostics", {})
			_assert(bool(exported_audio.get("enabled", false)) and not exported_audio.get("events", []).is_empty(), "normal report includes bounded audio requests")
			_assert(not parsed_report.has("images") and not parsed_report.has("image_frames") and not parsed_report.has("right_edge_capture"), "audio-only diagnostics export contains no screenshot-series payload")
		DirAccess.remove_absolute(report_path)
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
