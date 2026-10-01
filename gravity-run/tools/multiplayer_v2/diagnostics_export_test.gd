extends SceneTree

const Exporter := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")

func _initialize() -> void:
	var report := {"session": {"round_id": "test"}, "frames": [], "events": []}
	for index in 1200:
		report.frames.append({"index": index, "sample": "x".repeat(8192)})
	var started := Time.get_ticks_usec()
	var prepared := Exporter.prepare_report(report)
	assert(prepared.get("export_truncated", false))
	assert(JSON.stringify(prepared).to_utf8_buffer().size() <= Exporter.MAX_EXPORT_BYTES)
	assert(report.frames.size() == 1200, "trimming must not mutate the source snapshot")
	assert(prepared.frames.back().index == 1199, "newest frame must survive trimming")
	assert(prepared.frames.front().index == prepared.export_removed_frames)
	print("1200-frame export preparation ms: ", (Time.get_ticks_usec() - started) / 1000.0)

	var event_report := {"frames": [], "events": [{"name": "presentation_timing_config", "details": {"render_anchor_experiment_enabled": true}}]}
	for index in 40:
		event_report.events.append({"name": "common_course_flow_trace", "details": {"index": index, "sample": "ö".repeat(128 * 1024)}})
	var event_prepared := Exporter.prepare_report(event_report)
	assert(JSON.stringify(event_prepared).to_utf8_buffer().size() <= Exporter.MAX_EXPORT_BYTES, "budget is UTF-8 bytes, not characters")
	assert(event_prepared.events.front().name == "presentation_timing_config", "trim bulky detail windows before timing configuration")
	assert(event_prepared.events.back().details.index == 39)
	assert(event_report.events.size() == 41)

	var metadata_only := {"frames": [], "events": [], "oversized_metadata": "x".repeat(Exporter.MAX_EXPORT_BYTES + 1)}
	var fallback := Exporter.prepare_report(metadata_only)
	assert(fallback.has("export_error"))
	assert(JSON.stringify(fallback).to_utf8_buffer().size() <= Exporter.MAX_EXPORT_BYTES)

	for path in OS.get_cmdline_user_args():
		var actual: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var test_started := Time.get_ticks_usec()
		var compact := Exporter.prepare_report(actual)
		var compact_bytes := JSON.stringify(compact).to_utf8_buffer().size()
		print("Fixture compact bytes: ", compact_bytes, "; prepare ms: ", (Time.get_ticks_usec() - test_started) / 1000.0)
		assert(compact_bytes <= Exporter.MAX_EXPORT_BYTES)
	print("Diagnostics export tests passed.")
	quit(0)
