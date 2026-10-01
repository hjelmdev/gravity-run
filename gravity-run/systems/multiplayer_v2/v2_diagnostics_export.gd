extends RefCounted
class_name MultiplayerV2DiagnosticsExport

const MAX_EXPORT_BYTES := 8 * 1024 * 1024

static func save_report(report: Dictionary, filename: String) -> String:
	var export_report := prepare_report(report)
	var json_text := JSON.stringify(export_report)
	if OS.has_feature("web"):
		# Transfer bytes directly; do not create/evaluate a multi-megabyte
		# base64 JavaScript program and decode it character by character.
		var safe_filename := filename.validate_filename()
		JavaScriptBridge.download_buffer(json_text.to_utf8_buffer(), safe_filename, "application/json")
		var suffix := " (trimmed to fit the 8 MiB limit)" if bool(export_report.get("export_truncated", false)) else ""
		return "Download requested: %s%s" % [safe_filename, suffix]
	var path := "user://%s" % filename
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save diagnostics: %s" % error_string(FileAccess.get_open_error())
	file.store_string(json_text)
	file.close()
	var suffix := " (trimmed to fit the 8 MiB limit)" if bool(export_report.get("export_truncated", false)) else ""
	return "Diagnostics saved locally: %s%s" % [ProjectSettings.globalize_path(path), suffix]

static func prepare_report(report: Dictionary) -> Dictionary:
	# Only replace top-level arrays; the diagnostic snapshot's nested samples
	# are immutable here. Avoid another deep copy of thousands of flow rows.
	var export_report := report.duplicate(false)
	var json_text := JSON.stringify(export_report)
	var original_bytes := json_text.to_utf8_buffer().size()
	if original_bytes <= MAX_EXPORT_BYTES:
		return export_report
	# Reserve room for truncation metadata. Binary searches serialize at most
	# O(log N) candidates, rather than once per discarded frame/event.
	var budget := MAX_EXPORT_BYTES - 2048
	var removed_frames := _trim_array_to_budget(export_report, "frames", budget)
	var removed_events := 0
	if _report_bytes(export_report) > budget:
		removed_events = _trim_detail_events_to_budget(export_report, budget)
	if _report_bytes(export_report) > budget:
		removed_events += _trim_array_to_budget(export_report, "events", budget)
	if removed_frames > 0 or removed_events > 0:
		export_report["export_truncated"] = true
		export_report["export_original_bytes"] = original_bytes
		export_report["export_removed_frames"] = removed_frames
		export_report["export_removed_events"] = removed_events
		json_text = JSON.stringify(export_report)
	if json_text.to_utf8_buffer().size() > MAX_EXPORT_BYTES:
		export_report = {
			"session": report.get("session", {}).duplicate(true),
			"export_truncated": true,
			"export_original_bytes": original_bytes,
			"export_removed_frames": report.get("frames", []).size(),
			"export_removed_events": report.get("events", []).size(),
			"export_error": "Report metadata exceeded the export size limit."
		}
	return export_report

static func _report_bytes(report: Dictionary) -> int:
	return JSON.stringify(report).to_utf8_buffer().size()

static func _trim_array_to_budget(report: Dictionary, key: String, budget: int) -> int:
	var samples: Array = report.get(key, [])
	if samples.is_empty() or _report_bytes(report) <= budget:
		return 0
	var low := 0
	var high := samples.size()
	while low < high:
		var mid := (low + high) / 2
		report[key] = samples.slice(mid)
		if _report_bytes(report) <= budget:
			high = mid
		else:
			low = mid + 1
	report[key] = samples.slice(low)
	return low

static func _trim_detail_events_to_budget(report: Dictionary, budget: int) -> int:
	var samples: Array = report.get("events", [])
	var detail_count := 0
	for event in samples:
		if str(event.get("name", "")) in ["common_course_flow_trace", "barrel_render_trace"]:
			detail_count += 1
	var low := 0
	var high := detail_count
	while low < high:
		var mid := (low + high) / 2
		report["events"] = _without_oldest_details(samples, mid)
		if _report_bytes(report) <= budget:
			high = mid
		else:
			low = mid + 1
	report["events"] = _without_oldest_details(samples, low)
	return low

static func _without_oldest_details(samples: Array, count: int) -> Array:
	var retained: Array = []
	for event in samples:
		if count > 0 and str(event.get("name", "")) in ["common_course_flow_trace", "barrel_render_trace"]:
			count -= 1
		else:
			retained.append(event)
	return retained

static func make_filename(report: Dictionary, view: String) -> String:
	var session: Dictionary = report.get("session", {})
	var role := str(session.get("role", "client")).to_lower().validate_filename()
	var peer := int(session.get("local_peer_id", 0))
	var round_id := str(session.get("round_id", "no-round"))
	if round_id.is_empty():
		round_id = "no-round"
	return "multiplayer_%s_peer%d_%s_%s_%d.json" % [view.validate_filename(), peer, role, round_id.substr(0, 12).validate_filename(), Time.get_unix_time_from_system()]
