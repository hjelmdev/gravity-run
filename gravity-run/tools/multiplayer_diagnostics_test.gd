extends Node

const DiagnosticsScript := preload("res://systems/multiplayer_diagnostics.gd")

func _ready() -> void:
	var recorder := DiagnosticsScript.new()
	var large_report := {
		"schema_version": 1,
		"report_id": "report-test",
		"match_id": "match-test",
		"diagnostic_session_id": "session-test",
		"client_instance_id": "client-test",
		"role": "guest",
		"player_label": "p1",
		"build_id": "test",
		"terminal_state": "finished",
		"roster": [{"player_label": "p0"}, {"player_label": "p1"}, {"player_label": "p2"}],
		"totals": {"snapshot_accepted": 50},
		"windows": [],
		"detail_samples": [],
		"start_samples": [],
		"events": [],
		"incidents": [],
		"browser_samples": [],
		"timings": {},
		"loss": {},
	}
	for index in 180:
		large_report.windows.append({"t_start_ms": index * 1000, "padding": "w".repeat(100)})
	for index in 120:
		large_report.detail_samples.append({"t_ms": index * 50, "metrics": {"padding": "d".repeat(400)}})
	for index in 720:
		var players: Array = []
		for player_index in 3:
			players.append({"player_label": "p%d" % player_index, "world_x": index * 3.0})
		large_report.start_samples.append({"t_ms": index * 50, "sample": {"players": players, "padding": "s".repeat(250)}})
	for index in 1200:
		large_report.events.append({"t_ms": index * 25, "event": "ordinary_event", "important": index % 300 == 0, "details": {"padding": "e".repeat(100)}})
	large_report.incidents = [{"label": "flicker", "pre_samples": large_report.start_samples.slice(0, 100), "samples": large_report.start_samples.slice(0, 100)}]
	for index in 60:
		large_report.browser_samples.append({"t_ms": index * 1000, "probe": {"padding": "b".repeat(100)}})
	var output := recorder._build_clipboard_text(large_report)
	assert(output.begins_with("GRAVITY_RUN_MP_REPORT v1\n"), "clipboard report has a versioned header")
	print("Diagnostics clipboard bytes: ", output.to_utf8_buffer().size())
	assert(output.to_utf8_buffer().size() <= DiagnosticsScript.MAX_CLIPBOARD_BYTES, "clipboard report never exceeds its hard size limit")
	var parsed: Variant = JSON.parse_string(output.trim_prefix("GRAVITY_RUN_MP_REPORT v1\n"))
	assert(parsed is Dictionary, "reduced clipboard report remains valid JSON")
	assert(parsed.report.loss.get("clipboard_reduced", false), "reduction is explicitly marked")
	assert(parsed.report.loss.get("clipboard_metadata_only", false), "extreme reduction records omitted sections")
	recorder._capture = {"match_generation": "room-test:1234", "match_id": "room-test:1234", "diagnostic_session_id": ""}
	recorder.set_match_generation("room-test:1234")
	assert(recorder._capture.diagnostic_session_id == "room-test:1234" and recorder._capture.match_id == "room-test:1234", "local reports from every client use the shared match generation as their debug ID, without a server session")
	recorder._id_to_label = {"host-uuid": "p0", "guest-uuid": "p1"}
	var sanitized_identities: Dictionary = recorder._sanitize({"email": "private@example.com", "access_token": "secret", "player_id": "guest-uuid", "spectator_target": "host-uuid", "before": ["host-uuid", "guest-uuid"], "after": ["guest-uuid", "host-uuid"], "position": 2})
	assert(sanitized_identities == {"player_id": "p1", "spectator_target": "p0", "before": ["p0", "p1"], "after": ["p1", "p0"], "position": 2}, "diagnostics must redact player/spectator IDs and visual-order ID arrays")
	var full_start_trace: Array = []
	for index in 1024:
		full_start_trace.append({"at_ms": index, "event": "trace_%d" % index})
	var sanitized_trace: Dictionary = recorder._sanitize({"events": full_start_trace.slice(0, 240), "start_trace": full_start_trace})
	assert(sanitized_trace.events.size() == 240 and sanitized_trace.start_trace.size() == 1024, "export sanitization must preserve the explicitly bounded match and ten-second startup traces")
	assert(sanitized_trace.start_trace.back().event == "trace_1023", "startup trace export must retain the end of the captured window")
	recorder._capture = {"totals": {"transport_packets": 0, "transport_packets_control": 0, "transport_packets_snapshot": 0}}
	recorder.increment_total("transport_packets")
	recorder.increment_total("transport_packets_snapshot")
	assert(recorder._capture.totals.transport_packets == 1 and recorder._capture.totals.transport_packets_snapshot == 1 and recorder._capture.totals.transport_packets_control == 0, "packet totals distinguish decoded packets from polling and split channels")
	recorder._capture = {"phase": "running", "detail_samples": [], "start_samples": [], "incidents": [], "browser_samples": [], "events": [], "windows": [], "loss": {}, "totals": {"process_frames": 0}}
	for index in 500:
		recorder._capture.detail_samples.append({"padding": "m".repeat(5000)})
	recorder._window_frames = 1
	recorder._started_usec = Time.get_ticks_usec() - 1000000
	recorder._window_started_usec = recorder._started_usec
	recorder._flush_window(Time.get_ticks_usec())
	assert(recorder._capture.detail_samples.size() == 500 and not recorder._capture.loss.has("capture_detail_samples_reduced"), "active match window flush must not serialize or reduce the full capture")
	var frozen_large_capture: Dictionary = recorder._enforce_capture_memory_budget(recorder._capture)
	assert(JSON.stringify(frozen_large_capture).to_utf8_buffer().size() <= DiagnosticsScript.MAX_LOCAL_BYTES, "post-match frozen capture remains within the 2 MiB memory budget")
	assert(frozen_large_capture.loss.get("capture_detail_samples_reduced", false), "post-match reduction is explicitly marked")
	recorder._capture = {"phase": "running", "start_samples": [], "loss": {}, "totals": {}}
	recorder._started_usec = Time.get_ticks_usec()
	recorder._race_started_usec = recorder._started_usec
	recorder._last_start_sample_usec = 0
	for index in DiagnosticsScript.MAX_START_SAMPLES + 5:
		recorder.record_start_sample({"frame": index, "camera_left": float(index), "players": []})
	assert(recorder._capture.start_samples.size() == DiagnosticsScript.MAX_START_SAMPLES, "frame-dense start diagnostics stay within the configured hard cap")
	assert(recorder._capture.loss.start_samples_dropped == 5, "overflow is counted while retaining the latest frame samples")
	assert(recorder._capture.start_samples.back().sample.frame == DiagnosticsScript.MAX_START_SAMPLES - 1, "the startup capture preserves the first frames instead of replacing them with later samples")
	recorder._race_started_usec -= 4000000
	recorder.record_start_sample({"frame": "outside_capture_window"})
	assert(recorder._capture.start_samples.size() == DiagnosticsScript.MAX_START_SAMPLES, "frame-dense capture stops after its three-second race window")
	recorder._capture = {"phase": "running", "start_samples": [], "detail_samples": [], "incidents": [], "events": [], "loss": {}, "totals": {}}
	recorder._started_usec = Time.get_ticks_usec() - 4000000
	recorder._race_started_usec = recorder._started_usec
	recorder._frame_sample_ring.clear()
	for index in 4:
		recorder.record_start_sample({"frame": index})
	recorder.mark_problem("flicker_test")
	assert(recorder._incident_capture.pre_frame_samples.size() == 4, "marking an incident must preserve recent frame-level samples from before the mark")
	assert(recorder._frame_sample_ring.is_empty(), "incident marking must rotate, not deep-copy/sanitize, its pre-event frame ring")
	recorder.record_start_sample({"frame": 4, "user_id": "guest-uuid"})
	assert(recorder._incident_capture.frame_samples.size() == 1, "incident capture must continue collecting frame-level samples after the mark")
	assert(recorder._incident_capture.frame_samples[0].sample.user_id == "guest-uuid", "raw frame samples stay local until report finalization")
	recorder._capture.incidents.append(recorder._incident_capture)
	var frozen_incident: Dictionary = recorder._capture.duplicate(true)
	recorder._sanitize_incident_frames(frozen_incident)
	assert(frozen_incident.incidents[0].frame_samples[0].sample.user_id == "p1", "frozen incident samples are anonymized after the race")
	recorder._capture = {"phase": "results", "schema_version": 1, "report_id": "deferred-report-test", "match_generation": "test-generation", "terminal_state": "running", "windows": [], "detail_samples": [], "start_samples": [{"t_ms": 0, "sample": {"user_id": "guest-uuid", "frame_id": 0}}], "events": [], "incidents": [], "browser_samples": [], "timings": {}, "totals": {"process_frames": 0}, "loss": {}}
	recorder._started_usec = Time.get_ticks_usec()
	recorder._window_started_usec = recorder._started_usec
	recorder.finish_match("finished")
	assert(recorder._capture.is_empty() and recorder._reports.is_empty() and recorder._pending_report_finalizations == 1, "finish freezes the capture immediately and defers report work")
	assert(recorder.get_export_text().contains("saved after the match"), "active report export is refused instead of serializing the live capture")
	await get_tree().process_frame
	assert(recorder._pending_report_finalizations == 0 and recorder.get_latest_report().terminal_state == "finished", "deferred finalization saves the finished report after the results transition")
	assert(recorder.get_latest_report().start_samples[0].sample.user_id == "p1", "deferred finalization anonymizes retained startup data")
	print("Multiplayer diagnostics size/privacy tests passed.")
	recorder.free()
	get_tree().quit()
