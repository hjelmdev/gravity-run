extends Node2D

const CaptureScript := preload("res://systems/multiplayer_v2/v2_right_edge_capture.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const TEST_ZIP := "user://right_edge_capture_contract_test.zip"

var failures := 0
var _capture: Node
var _finished := false
var _finish_success := false
var _finish_frames := 0
var _finish_reason := ""
var _provider_call_count := 0
var _provider_round_id := "zip-round"
var _zip_frame_count := 0

func _ready() -> void:
	_capture = CaptureScript.new()
	add_child(_capture)
	_capture.capture_finished.connect(_on_capture_finished)
	_test_static_bounds()
	_test_cave_fragment_diagnostic_math()
	if _capture.readback_count != 0:
		_fail("capture is inactive without starting and performs no readback")
	await _test_cancel_and_restart()
	await _test_capture_and_zip()
	await _test_round_change_cancel()
	await _test_scene_exit_cleanup()
	print("RIGHT_EDGE_CAPTURE_CONTRACT_TEST failures=%d validated_zip_frames=%d zip=%s readbacks_after_clear=%d" % [failures, _zip_frame_count, TEST_ZIP, _capture.readback_count])
	get_tree().quit(1 if failures > 0 else 0)

func _draw() -> void:
	var width := get_viewport_rect().size.x
	var height := get_viewport_rect().size.y
	draw_rect(Rect2(Vector2.ZERO, Vector2(width, height)), Color("06101d"))
	for index in range(16):
		var x := fposmod(float(index * 89) - float(Time.get_ticks_msec()) * 0.5, width)
		draw_circle(Vector2(x, 55.0 + float(index * 41 % maxi(int(height), 1))), 2.0, Color("42d6c5"))
	draw_rect(Rect2(Vector2(width - 80.0, 0.0), Vector2(80.0, height)), Color(0.2, 0.1, 0.3, 0.5))

func _process(_delta: float) -> void:
	queue_redraw()

func _test_static_bounds() -> void:
	var landscape := CaptureScript.calculate_frame_limit(Vector2i(1280, 720), 240, CaptureScript.MAX_RAW_IMAGE_BYTES)
	var portrait := CaptureScript.calculate_frame_limit(Vector2i(540, 1920), 240, CaptureScript.MAX_RAW_IMAGE_BYTES)
	_assert(landscape <= 30 and landscape * 240 * 720 * 4 <= CaptureScript.MAX_RAW_IMAGE_BYTES, "landscape raw-image budget is bounded")
	_assert(portrait <= 30 and portrait * 240 * 1920 * 4 <= CaptureScript.MAX_RAW_IMAGE_BYTES, "portrait raw-image budget is bounded")
	_assert(CaptureScript.calculate_frame_limit(Vector2i.ZERO, 240, CaptureScript.MAX_RAW_IMAGE_BYTES) == 0, "invalid viewport yields zero frames")

func _test_cave_fragment_diagnostic_math() -> void:
	var camera_course := 4799.0
	var fragment_offset := 1.0
	var fragment_width := 1.0
	var logical_height := 540.0
	var samples := BiomeRendererScript.cave_ridge_diagnostic_samples(camera_course, fragment_offset, fragment_width, logical_height)
	_assert(samples.size() == 3, "cave diagnostics expose all three rendered ridge layers")
	for layer in range(samples.size()):
		var sample: Dictionary = samples[layer]
		var expected_parallax := 0.16 + float(layer) * 0.07
		var expected_left_phase := camera_course * expected_parallax + fragment_offset
		var expected_right_phase := expected_left_phase + fragment_width
		_assert(is_equal_approx(float(sample.get("parallax", -1.0)), expected_parallax), "cave diagnostic layer uses the renderer's parallax factor")
		_assert(is_equal_approx(float(sample.get("phase_left", -1.0)), expected_left_phase), "cave diagnostic left phase includes the clipped fragment offset")
		_assert(is_equal_approx(float(sample.get("phase_right", -1.0)), expected_right_phase), "cave diagnostic right phase adds the visible fragment width in renderer space")
		_assert(is_equal_approx(float(sample.get("left_y", -1.0)), BiomeRendererScript._cave_ridge_y(expected_left_phase, logical_height, layer)), "cave diagnostic left vertex matches the renderer")
		_assert(is_equal_approx(float(sample.get("right_y", -1.0)), BiomeRendererScript._cave_ridge_y(expected_right_phase, logical_height, layer)), "cave diagnostic right vertex matches the renderer")

func _test_cancel_and_restart() -> void:
	_reset_completion()
	var context := {"round_id": "zip-round", "session": {"role": "host", "local_peer_id": 1}}
	var started: bool = _capture.start_capture(get_viewport(), context, Callable(self, "_frame_context"))
	_assert(started, "capture starts explicitly")
	_assert(_capture.readback_count == 0, "no readback occurs synchronously at start")
	_assert(not _capture.start_capture(get_viewport(), context, Callable(self, "_frame_context")), "one-in-flight guard rejects a second capture")
	var readback_wait_started := Time.get_ticks_usec()
	while _capture.readback_count < 2 and Time.get_ticks_usec() - readback_wait_started < 500_000:
		await get_tree().process_frame
	_assert(_capture.readback_count >= 1, "capture can be explicitly cancelled after an actual readback")
	_capture.cancel_capture("contract_test")
	await _wait_for_finish()
	_assert(not _finish_success and _finish_frames == 0 and not _capture.has_capture, "cancel clears captured buffers")
	_assert(_capture.readback_count == 0, "immediate cancellation performs no readback")
	_capture.clear_capture()

func _test_capture_and_zip() -> void:
	_reset_completion()
	_provider_call_count = 0
	var context := {"round_id": "zip-round", "mode": "mp", "seed": 100000014, "generator_version": 15, "session": {"role": "host", "local_peer_id": 1}, "capture_audio_diagnostics": true}
	_assert(_capture.start_capture(get_viewport(), context, Callable(self, "_frame_context")), "capture restarts after cancellation")
	SfxController.play_event("coin", "zip-round|capture-test-audio")
	await _wait_for_finish()
	_assert(_finish_success, "capture completes")
	var captured_context: Dictionary = _capture.get("_capture_context")
	var audio_diagnostics: Dictionary = captured_context.get("audio_diagnostics", {})
	_assert(bool(audio_diagnostics.get("enabled", false)) and not bool(captured_context.get("capture_audio_diagnostics", true)), "completed MP visual burst closes its opt-in audio trace into the ZIP context")
	_assert(not audio_diagnostics.get("events", []).is_empty(), "MP ZIP context contains bounded event request timing")
	_assert(_finish_frames > 0 and _finish_frames <= CaptureScript.MAX_FRAMES, "capture respects frame bound")
	_zip_frame_count = _finish_frames
	_assert(_capture.readback_count == _finish_frames, "at most one readback is performed per captured frame")
	_assert(_capture.has_capture and _capture.captured_frame_count == _finish_frames, "completed frames remain available until saved or cleared")
	var result: Dictionary = _capture.save_package()
	_assert(bool(result.get("ok", false)), "ZIP package is created")
	_assert(int(result.get("bytes", CaptureScript.MAX_PACKAGE_BYTES + 1)) <= CaptureScript.MAX_PACKAGE_BYTES, "ZIP package stays within the explicit package byte budget")
	var zip_path := str(result.get("path", ""))
	_assert(not zip_path.is_empty() and FileAccess.file_exists(zip_path), "native package has a readable path")
	if not zip_path.is_empty() and FileAccess.file_exists(zip_path):
		_validate_zip(zip_path, _finish_frames)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	_assert(not _capture.start_capture(get_viewport(), context, Callable(self, "_frame_context")), "completed capture cannot be silently replaced")
	_capture.clear_capture()
	_assert(not _capture.has_capture, "explicit clear releases retained images")

func _test_round_change_cancel() -> void:
	_reset_completion()
	_provider_round_id = "zip-round"
	var context := {"round_id": _provider_round_id, "session": {"role": "host", "local_peer_id": 1}}
	_assert(_capture.start_capture(get_viewport(), context, Callable(self, "_frame_context")), "capture starts for a specific round")
	var started_usec := Time.get_ticks_usec()
	while _capture.readback_count < 1 and Time.get_ticks_usec() - started_usec < 500_000:
		await get_tree().process_frame
	_provider_round_id = "next-round"
	await _wait_for_finish()
	_assert(not _finish_success and not _capture.has_capture, "round change cancels and clears retained capture images")
	_capture.clear_capture()
	_provider_round_id = "zip-round"

func _test_scene_exit_cleanup() -> void:
	var exiting_capture: Node = CaptureScript.new()
	add_child(exiting_capture)
	var context := {"round_id": "zip-round", "session": {"role": "host", "local_peer_id": 1}}
	_assert(exiting_capture.start_capture(get_viewport(), context, Callable(self, "_frame_context")), "temporary capture component starts before scene exit")
	var started_usec := Time.get_ticks_usec()
	while int(exiting_capture.get("readback_count")) < 1 and Time.get_ticks_usec() - started_usec < 500_000:
		await get_tree().process_frame
	_assert(int(exiting_capture.get("readback_count")) >= 1, "temporary component reached an actual readback before exit")
	exiting_capture.queue_free()
	await get_tree().process_frame
	_assert(not is_instance_valid(exiting_capture), "scene exit frees active capture component")
	await get_tree().process_frame

func _validate_zip(path: String, expected_frames: int) -> void:
	var reader := ZIPReader.new()
	var error := reader.open(path)
	_assert(error == OK, "ZIPReader opens package")
	if error != OK:
		return
	var entries := reader.get_files()
	_assert(entries.size() == expected_frames + 1, "ZIP has one PNG per frame plus metadata")
	var metadata_bytes := reader.read_file("metadata.json")
	var metadata_variant: Variant = JSON.parse_string(metadata_bytes.get_string_from_utf8())
	_assert(metadata_variant is Dictionary, "metadata JSON is valid")
	if metadata_variant is Dictionary:
		_assert(int(metadata_variant.get("capture", {}).get("frame_count", -1)) == expected_frames, "metadata frame count matches archive")
		var started_context: Dictionary = metadata_variant.get("capture", {}).get("started_context", {})
		var audio_diagnostics: Dictionary = started_context.get("audio_diagnostics", {})
		_assert(bool(audio_diagnostics.get("enabled", false)) and not audio_diagnostics.get("events", []).is_empty(), "exported ZIP contains bounded SFX event timing from the opt-in capture")
		_assert(int(metadata_variant.get("capture", {}).get("effective_frame_limit", 0)) >= expected_frames, "metadata records the effective resolution-based frame cap")
		var frames: Array = metadata_variant.get("frames", [])
		_assert(frames.size() == expected_frames, "metadata has one timing/camera row per PNG")
		for index in range(expected_frames):
			var entry := "right_edge_%03d.png" % index
			_assert(entries.has(entry), "ZIP contains numbered PNG %s" % entry)
			var image := Image.new()
			var png_error := image.load_png_from_buffer(reader.read_file(entry))
			_assert(png_error == OK and image.get_width() > 0 and image.get_height() > 0, "PNG entry %s decodes" % entry)
			if index < frames.size() and image.get_width() > 0:
				var rect: Array = frames[index].get("strip_rect", [])
				_assert(rect.size() == 4 and int(rect[2]) == image.get_width() and int(rect[3]) == image.get_height(), "PNG dimensions match frame metadata")
	reader.close()

func _frame_context() -> Dictionary:
	_provider_call_count += 1
	return {"round_id": _provider_round_id, "render_callback_index": _provider_call_count, "round_phase": "running", "presentation_tick": float(_provider_call_count), "requested_camera_left": float(_provider_call_count) * 8.333, "applied_canvas_left": float(_provider_call_count) * 8.333, "applied_canvas_right": float(_provider_call_count) * 8.333 + get_viewport_rect().size.x, "presentation_clip_left": float(_provider_call_count) * 8.333, "presentation_clip_right": float(_provider_call_count) * 8.333 + get_viewport_rect().size.x, "biome_fragments": [{"biome": "cave", "course_start": 4800.0, "course_end": 9600.0}], "cave_fallback_ridge_samples": [{"layer": 0, "left_y": 190.0, "right_y": 202.0}]}

func _reset_completion() -> void:
	_finished = false
	_finish_success = false
	_finish_frames = 0
	_finish_reason = ""

func _wait_for_finish() -> void:
	var started_usec := Time.get_ticks_usec()
	while not _finished and Time.get_ticks_usec() - started_usec < 2_000_000:
		await get_tree().process_frame
	_assert(_finished, "capture completes or cancels within bounded test timeout")

func _on_capture_finished(success: bool, frame_count: int, reason: String) -> void:
	_finished = true
	_finish_success = success
	_finish_frames = frame_count
	_finish_reason = reason

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	failures += 1
	push_error(message)
