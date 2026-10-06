extends Node
class_name MultiplayerV2RightEdgeCapture

signal state_changed(state: String, frame_count: int, message: String)
signal capture_finished(success: bool, frame_count: int, message: String)

const MAX_DURATION_USEC := 1_000_000
const MAX_SAMPLE_INTERVAL_USEC := 33_334
const MAX_FRAMES := 30
const MAX_RAW_IMAGE_BYTES := 24 * 1024 * 1024
const MAX_PACKAGE_BYTES := 28 * 1024 * 1024
const STRIP_WIDTH := 240

var _capturing := false
var _cancel_requested := false
var _cancel_reason := ""
var _images: Array[Image] = []
var _frame_metadata: Array[Dictionary] = []
var _capture_context: Dictionary = {}
var _raw_bytes := 0
var _readback_count := 0
var _max_frames_for_run := 0
var completion_reason := ""

var readback_count: int:
	get: return _readback_count
var is_capturing: bool:
	get: return _capturing
var has_capture: bool:
	get: return not _images.is_empty()
var captured_frame_count: int:
	get: return _images.size()

func start_capture(viewport: Viewport, context: Dictionary, frame_context_provider: Callable) -> bool:
	if _capturing or has_capture or not is_instance_valid(viewport) or not frame_context_provider.is_valid():
		return false
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		completion_reason = "viewport_unavailable"
		state_changed.emit("unavailable", 0, tr("The game viewport is not ready for capture."))
		return false
	var strip_width := mini(STRIP_WIDTH, int(viewport_size.x))
	_max_frames_for_run = calculate_frame_limit(Vector2i(viewport_size), strip_width, MAX_RAW_IMAGE_BYTES)
	if _max_frames_for_run <= 0:
		completion_reason = "raw_image_budget"
		state_changed.emit("unavailable", 0, tr("The viewport exceeds the capture memory limit."))
		return false
	completion_reason = ""
	_capture_context = context.duplicate(true)
	_images.clear()
	_frame_metadata.clear()
	_raw_bytes = 0
	_readback_count = 0
	_cancel_requested = false
	_cancel_reason = ""
	_capturing = true
	state_changed.emit("capturing", 0, "Capture started.")
	_capture_burst(viewport, frame_context_provider, strip_width, _max_frames_for_run)
	return true

func cancel_capture(reason := "cancelled") -> void:
	if not _capturing:
		return
	_cancel_requested = true
	_cancel_reason = reason

func clear_capture() -> void:
	_images.clear()
	_frame_metadata.clear()
	_capture_context.clear()
	_raw_bytes = 0
	_readback_count = 0
	completion_reason = ""

func save_package() -> Dictionary:
	if _capturing:
		return {"ok": false, "message": "Capture is still running."}
	if _images.is_empty():
		return {"ok": false, "message": "There are no captured frames to save."}
	var filename := _make_package_filename(_capture_context)
	var path := "user://" + filename
	var package_started := Time.get_ticks_usec()
	var error := _write_package(path)
	if error != OK:
		_remove_user_file(path)
		return {"ok": false, "message": "Could not create the capture ZIP (%s)." % error_string(error)}
	var zip_bytes := FileAccess.get_file_as_bytes(path)
	if zip_bytes.is_empty() or zip_bytes.size() > MAX_PACKAGE_BYTES:
		_remove_user_file(path)
		return {"ok": false, "message": "The capture ZIP exceeded its size limit."}
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(zip_bytes, filename, "application/zip")
		_remove_user_file(path)
		return {"ok": true, "message": "Capture ZIP download started (%d frames, %d bytes)." % [_images.size(), zip_bytes.size()], "bytes": zip_bytes.size(), "elapsed_usec": Time.get_ticks_usec() - package_started}
	return {"ok": true, "message": "Capture ZIP saved: %s (%d frames, %d bytes)." % [ProjectSettings.globalize_path(path), _images.size(), zip_bytes.size()], "path": ProjectSettings.globalize_path(path), "bytes": zip_bytes.size(), "elapsed_usec": Time.get_ticks_usec() - package_started}

static func calculate_frame_limit(viewport_size: Vector2i, strip_width: int, raw_budget: int) -> int:
	if viewport_size.x <= 0 or viewport_size.y <= 0 or strip_width <= 0 or raw_budget <= 0:
		return 0
	var bytes_per_frame := strip_width * viewport_size.y * 4
	if bytes_per_frame <= 0:
		return 0
	return mini(MAX_FRAMES, floori(float(raw_budget) / float(bytes_per_frame)))

func _capture_burst(viewport: Viewport, frame_context_provider: Callable, strip_width: int, frame_limit: int) -> void:
	var started_usec := Time.get_ticks_usec()
	var last_readback_usec := -1
	var last_callback_index := -1
	var cap_reason := ""
	while not _cancel_requested and _images.size() < frame_limit and Time.get_ticks_usec() - started_usec <= MAX_DURATION_USEC:
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		if _cancel_requested:
			break
		if Time.get_ticks_usec() - started_usec > MAX_DURATION_USEC:
			break
		if not is_instance_valid(viewport) or viewport.get_visible_rect().size.x < 1.0:
			_cancel_requested = true
			_cancel_reason = "viewport_unavailable"
			break
		var metadata: Dictionary = frame_context_provider.call()
		if str(metadata.get("round_id", "")) != str(_capture_context.get("round_id", "")):
			_cancel_requested = true
			_cancel_reason = "round_changed"
			break
		var post_draw_usec := Time.get_ticks_usec()
		if last_readback_usec >= 0 and post_draw_usec - last_readback_usec < MAX_SAMPLE_INTERVAL_USEC:
			continue
		var callback_index := int(metadata.get("render_callback_index", -1))
		if callback_index == last_callback_index:
			continue
		last_callback_index = callback_index
		var readback_started_usec := Time.get_ticks_usec()
		var full_image := viewport.get_texture().get_image()
		var readback_done_usec := Time.get_ticks_usec()
		_readback_count += 1
		if full_image == null or full_image.is_empty():
			_cancel_requested = true
			_cancel_reason = "readback_unavailable"
			break
		var full_size := full_image.get_size()
		var current_strip_width := mini(strip_width, full_size.x)
		var strip_rect := Rect2i(full_size.x - current_strip_width, 0, current_strip_width, full_size.y)
		var frame_bytes := current_strip_width * strip_rect.size.y * 4
		var actual_frame_limit := calculate_frame_limit(Vector2i(full_size), current_strip_width, MAX_RAW_IMAGE_BYTES)
		if actual_frame_limit <= 0:
			full_image = null
			cap_reason = "raw_image_budget"
			break
		frame_limit = mini(frame_limit, actual_frame_limit)
		_max_frames_for_run = frame_limit
		if _raw_bytes + frame_bytes > MAX_RAW_IMAGE_BYTES:
			full_image = null
			cap_reason = "raw_image_budget"
			break
		var strip_image := full_image.get_region(strip_rect)
		full_image = null
		var crop_done_usec := Time.get_ticks_usec()
		if strip_image == null or strip_image.is_empty():
			_cancel_requested = true
			_cancel_reason = "crop_unavailable"
			break
		metadata["frame_number"] = _images.size()
		metadata["post_draw_usec"] = post_draw_usec
		metadata["viewport_size"] = [full_size.x, full_size.y]
		metadata["strip_rect"] = [strip_rect.position.x, strip_rect.position.y, strip_rect.size.x, strip_rect.size.y]
		metadata["raw_rgba_bytes"] = frame_bytes
		metadata["readback_usec"] = readback_done_usec - readback_started_usec
		metadata["crop_usec"] = crop_done_usec - readback_done_usec
		metadata["interval_since_previous_usec"] = post_draw_usec - last_readback_usec if last_readback_usec >= 0 else 0
		_images.append(strip_image)
		_frame_metadata.append(metadata)
		_raw_bytes += frame_bytes
		last_readback_usec = post_draw_usec
		state_changed.emit("capturing", _images.size(), "Captured frame %d/%d." % [_images.size(), frame_limit])
	if _cancel_requested:
		var completed_reason := _cancel_reason
		clear_capture()
		_capturing = false
		completion_reason = completed_reason
		state_changed.emit("cancelled", 0, "Capture cancelled: %s." % completed_reason)
		capture_finished.emit(false, 0, completed_reason)
		return
	_capturing = false
	if _images.is_empty():
		completion_reason = "no_frames"
		state_changed.emit("unavailable", 0, tr("No rendered frames were available."))
		capture_finished.emit(false, 0, "no_frames")
		return
	var capped := _images.size() < MAX_FRAMES and (_images.size() >= frame_limit or not cap_reason.is_empty())
	completion_reason = cap_reason if not cap_reason.is_empty() else ("raw_image_budget" if capped else "complete")
	var completion_message := tr("Right-edge capture ready: %d frames. The raw image memory limit was reached.") % _images.size() if capped else tr("Right-edge capture ready: %d frames.") % _images.size()
	state_changed.emit("complete", _images.size(), completion_message)
	capture_finished.emit(true, _images.size(), completion_reason)

func _write_package(path: String) -> Error:
	var writer := ZIPPacker.new()
	var error := writer.open(path)
	if error != OK:
		return error
	var encoded_total := 0
	for index in range(_images.size()):
		var png_bytes := _images[index].save_png_to_buffer()
		if png_bytes.is_empty() or encoded_total + png_bytes.size() > MAX_PACKAGE_BYTES:
			writer.close()
			return ERR_OUT_OF_MEMORY
		encoded_total += png_bytes.size()
		var entry := "right_edge_%03d.png" % index
		error = writer.start_file(entry)
		if error != OK:
			writer.close()
			return error
		error = writer.write_file(png_bytes)
		writer.close_file()
		if error != OK:
			writer.close()
			return error
	var manifest := _package_metadata(encoded_total)
	var json_bytes := JSON.stringify(manifest, "\t").to_utf8_buffer()
	if encoded_total + json_bytes.size() > MAX_PACKAGE_BYTES:
		writer.close()
		return ERR_OUT_OF_MEMORY
	error = writer.start_file("metadata.json")
	if error == OK:
		error = writer.write_file(json_bytes)
		writer.close_file()
	writer.close()
	return error

func _package_metadata(encoded_png_bytes: int) -> Dictionary:
	return {"format": "gravity_run_right_edge_capture_v1", "capture": {"started_context": _capture_context.duplicate(true), "duration_limit_usec": MAX_DURATION_USEC, "frame_limit": MAX_FRAMES, "effective_frame_limit": _max_frames_for_run, "completion_reason": completion_reason, "max_raw_image_bytes": MAX_RAW_IMAGE_BYTES, "max_package_bytes": MAX_PACKAGE_BYTES, "raw_image_bytes": _raw_bytes, "encoded_png_bytes": encoded_png_bytes, "frame_count": _images.size()}, "frames": _frame_metadata.duplicate(true)}

func _remove_user_file(path: String) -> void:
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(global_path)

func _make_package_filename(context: Dictionary) -> String:
	var session := context.get("session", {}) as Dictionary
	var peer := int(session.get("local_peer_id", 0))
	var role := str(session.get("role", "client")).to_lower().validate_filename()
	var stamp := int(Time.get_unix_time_from_system())
	return "multiplayer_right_edge_peer%d_%s_%d.zip" % [peer, role, stamp]

func _exit_tree() -> void:
	if _capturing:
		_cancel_requested = true
		_cancel_reason = "scene_exit"
		_capturing = false
	_images.clear()
	_frame_metadata.clear()
