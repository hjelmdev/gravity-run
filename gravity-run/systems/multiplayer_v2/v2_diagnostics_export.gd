extends RefCounted
class_name MultiplayerV2DiagnosticsExport

const MAX_EXPORT_BYTES := 8 * 1024 * 1024

static func save_report(report: Dictionary, filename: String) -> String:
	var export_report := prepare_report(report)
	var json_text := JSON.stringify(export_report, "\t")
	if OS.has_feature("web"):
		var encoded := Marshalls.raw_to_base64(json_text.to_utf8_buffer())
		var safe_filename := filename.replace("'", "")
		JavaScriptBridge.eval("(()=>{const bytes=Uint8Array.from(atob('%s'),c=>c.charCodeAt(0));const url=URL.createObjectURL(new Blob([bytes],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='%s';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)})()" % [encoded, safe_filename], true)
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
	var export_report := report.duplicate(true)
	var json_text := JSON.stringify(export_report, "\t")
	var original_bytes := json_text.to_utf8_buffer().size()
	var removed_frames := 0
	var removed_events := 0
	var frames: Array = export_report.get("frames", [])
	var events: Array = export_report.get("events", [])
	while json_text.to_utf8_buffer().size() > MAX_EXPORT_BYTES and not frames.is_empty():
		frames.pop_front()
		removed_frames += 1
		json_text = JSON.stringify(export_report, "\t")
	while json_text.to_utf8_buffer().size() > MAX_EXPORT_BYTES and not events.is_empty():
		events.pop_front()
		removed_events += 1
		json_text = JSON.stringify(export_report, "\t")
	if removed_frames > 0 or removed_events > 0:
		export_report["export_truncated"] = true
		export_report["export_original_bytes"] = original_bytes
		export_report["export_removed_frames"] = removed_frames
		export_report["export_removed_events"] = removed_events
		json_text = JSON.stringify(export_report, "\t")
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

static func make_filename(report: Dictionary, view: String) -> String:
	var session: Dictionary = report.get("session", {})
	var role := str(session.get("role", "client")).to_lower().validate_filename()
	var peer := int(session.get("local_peer_id", 0))
	var round_id := str(session.get("round_id", "no-round"))
	if round_id.is_empty():
		round_id = "no-round"
	return "multiplayer_v2_%s_peer%d_%s_%s_%d.json" % [view.validate_filename(), peer, role, round_id.substr(0, 12).validate_filename(), Time.get_unix_time_from_system()]
