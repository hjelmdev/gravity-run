extends Node

signal report_changed(message: String)

const SCHEMA_VERSION := 1
const MAX_CLIPBOARD_BYTES := 80 * 1024
const MAX_LOCAL_BYTES := 2 * 1024 * 1024
const MAX_WINDOWS := 180
const MAX_DETAIL_SAMPLES := 600
const MAX_START_SAMPLES := 720
const MAX_EVENTS := 1200
const MAX_INCIDENTS := 3
const DETAIL_INTERVAL_USEC := 50000
const WINDOW_USEC := 1000000
const LOCAL_FILE := "user://multiplayer_diagnostics.json"

var _capture: Dictionary = {}
var _reports: Array[Dictionary] = []
var _window_gap_ms: Array[float] = []
var _window_started_usec := 0
var _last_process_usec := 0
var _last_detail_usec := 0
var _last_probe_usec := 0
var _window_frames := 0
var _window_transitions := {"33": 0, "50": 0, "100": 0, "250": 0}
var _window_godot_delta_ms := 0.0
var _window_timing: Dictionary = {}
var _window_gaps_by_phase: Dictionary = {}
var _process_gaps_by_phase: Dictionary = {}
var _last_metrics: Dictionary = {}
var _ordinary_event_last_msec: Dictionary = {}
var _incident_capture: Dictionary = {}
var _started_usec := 0
var _js_probe_installed := false
var _id_to_label: Dictionary = {}
var _last_start_sample_usec := 0
var _race_started_usec := 0
var _test_layout_preference := "unknown"
var _instances_preference: Variant = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_local()
	_load_test_context()
	set_process(true)

func _process(delta: float) -> void:
	if _capture.is_empty():
		return
	var now := Time.get_ticks_usec()
	var previous_process_usec := _last_process_usec
	if _last_process_usec > 0:
		var gap_ms := float(now - _last_process_usec) / 1000.0
		_window_gap_ms.append(gap_ms)
		_window_frames += 1
		_window_godot_delta_ms += delta * 1000.0
		for threshold in [33.3, 50.0, 100.0, 250.0]:
			if gap_ms > threshold:
				var key := str(int(threshold))
				_window_transitions[key] = int(_window_transitions.get(key, 0)) + 1
		var phase := str(_capture.get("phase", "unknown"))
		var phase_gaps: Array = _process_gaps_by_phase.get(phase, [])
		phase_gaps.append(gap_ms)
		while phase_gaps.size() > 3600:
			phase_gaps.pop_front()
		_process_gaps_by_phase[phase] = phase_gaps
		var window_phase_gaps: Array = _window_gaps_by_phase.get(phase, [])
		window_phase_gaps.append(gap_ms)
		_window_gaps_by_phase[phase] = window_phase_gaps
	_last_process_usec = now
	if now - _last_detail_usec >= DETAIL_INTERVAL_USEC:
		_last_detail_usec = now
		var detail := {
			"t_ms": int((now - _started_usec) / 1000),
			"process_gap_ms": _window_gap_ms.back() if not _window_gap_ms.is_empty() else null,
			"engine_delta_ms": delta * 1000.0,
			"phase": str(_capture.get("phase", "unknown")),
			"metrics": _last_metrics.duplicate(true),
		}
		var safe_detail: Dictionary = _sanitize(detail)
		_capture.detail_samples.append(safe_detail)
		while _capture.detail_samples.size() > MAX_DETAIL_SAMPLES:
			_capture.detail_samples.pop_front()
			_capture.loss.detail_samples_dropped = int(_capture.loss.get("detail_samples_dropped", 0)) + 1
		if not _incident_capture.is_empty():
			_incident_capture.samples.append(safe_detail.duplicate(true))
			_incident_capture.remaining_usec -= now - previous_process_usec
			if _incident_capture.remaining_usec <= 0:
				_capture.incidents.append(_incident_capture.duplicate(true))
				_incident_capture = {}
	if now - _window_started_usec >= WINDOW_USEC:
		_flush_window(now)
	if OS.has_feature("web") and now - _last_probe_usec >= WINDOW_USEC:
		_last_probe_usec = now
		_read_browser_probe()

func begin_match(metadata: Dictionary) -> void:
	if not _capture.is_empty():
		finish_match("superseded")
	_started_usec = Time.get_ticks_usec()
	_race_started_usec = 0
	_last_start_sample_usec = 0
	_window_started_usec = _started_usec
	_last_process_usec = 0
	_last_detail_usec = 0
	_last_probe_usec = 0
	_window_gap_ms.clear()
	_window_frames = 0
	_window_transitions = {"33": 0, "50": 0, "100": 0, "250": 0}
	_window_godot_delta_ms = 0.0
	_window_timing.clear()
	_window_gaps_by_phase.clear()
	_process_gaps_by_phase.clear()
	_last_metrics.clear()
	_incident_capture.clear()
	_id_to_label.clear()
	var safe_roster: Array = []
	var roster: Variant = metadata.get("roster", [])
	if roster is Array:
		for index in range(roster.size()):
			if roster[index] is Dictionary:
				var person: Dictionary = roster[index]
				var identity := str(person.get("user_id", ""))
				var label := "p%d" % index
				_id_to_label[identity] = label
				safe_roster.append({"player_label": label, "skin_id": int(person.get("skin_id", 0))})
	_capture = {
		"schema_version": SCHEMA_VERSION,
		"build_id": str(ProjectSettings.get_setting("application/config/version", "unversioned")),
		"godot_version": Engine.get_version_info(),
		"platform": OS.get_name(),
		"client_instance_id": _get_client_instance_id(),
		"report_id": _new_uuid(),
		"match_id": str(metadata.get("match_generation", "")),
		"diagnostic_session_id": str(metadata.get("match_generation", "")),
		"match_generation": str(metadata.get("match_generation", "")),
		"course_identity": str(metadata.get("course_identity", "")),
		"role": str(metadata.get("role", "unknown")),
		"player_label": str(metadata.get("player_label", "unknown")),
		"roster": safe_roster,
		"test_layout": "unknown",
		"device_label": "unknown",
		"instances_on_device": _instances_preference,
		"snapshot_rate_hz": 30,
		"simulation_tick_rate_hz": 60,
		"capture_start_utc": Time.get_datetime_string_from_system(true),
		"capture_start_monotonic_usec": _started_usec,
		"capture_end_utc": "",
		"terminal_state": "running",
		"windows": [],
		"detail_samples": [],
		"start_samples": [],
		"events": [],
		"incidents": [],
		"browser_samples": [],
		"totals": {"process_frames": 0, "snapshot_received": 0, "snapshot_accepted": 0, "snapshot_rejected": 0, "transport_polls": 0, "transport_packets": 0, "transport_packets_control": 0, "transport_packets_snapshot": 0},
		"loss": {"detail_samples_dropped": 0, "start_samples_dropped": 0, "events_dropped": 0, "windows_dropped": 0, "incidents_dropped": 0},
	}
	_capture.test_layout = _test_layout_preference
	_js_probe_installed = false
	_install_browser_probe()
	if OS.has_feature("web"):
		# PerformanceObserver can deliver buffered tasks from before this race.
		# Anchor and clear it at capture start so reports describe this match only.
		JavaScriptBridge.eval("(()=>{const p=window.__gravityRunMpProbe;if(p){p.captureStart=performance.now();p.last=p.captureStart;p.long=[];p.gaps=[];p.events=[]}})()", true)
	_add_event("capture_started", metadata, true)
	report_changed.emit("Local multiplayer diagnostics recording started.")

func set_phase(phase: String) -> void:
	if not _capture.is_empty():
		_capture.phase = phase

func set_match_generation(generation: String) -> void:
	if not _capture.is_empty():
		_capture.match_generation = generation.left(96)
		_capture.match_id = generation.left(96)
		_capture.diagnostic_session_id = generation.left(96)

func set_metrics(metrics: Dictionary) -> void:
	if not _capture.is_empty():
		_last_metrics = metrics.duplicate(true)

func increment_total(name: String, amount: int = 1) -> void:
	if not _capture.is_empty():
		_capture.totals[name] = int(_capture.totals.get(name, 0)) + amount

func record_timing(name: String, duration_usec: int, details: Dictionary = {}) -> void:
	if _capture.is_empty():
		return
	var timings: Dictionary = _capture.get("timings", {})
	var entry: Dictionary = timings.get(name, {"count": 0, "total_usec": 0, "max_usec": 0, "samples_usec": []})
	entry.count = int(entry.get("count", 0)) + 1
	entry.total_usec = int(entry.get("total_usec", 0)) + maxi(duration_usec, 0)
	entry.max_usec = maxi(int(entry.get("max_usec", 0)), maxi(duration_usec, 0))
	var samples: Array = entry.get("samples_usec", [])
	samples.append(maxi(duration_usec, 0))
	while samples.size() > 300:
		samples.pop_front()
	entry.samples_usec = samples
	if not details.is_empty():
		entry.last = _sanitize(details)
	timings[name] = entry
	_capture.timings = timings
	var window_entry: Dictionary = _window_timing.get(name, {"count": 0, "total_usec": 0, "max_usec": 0, "samples_usec": []})
	window_entry.count = int(window_entry.count) + 1
	window_entry.total_usec = int(window_entry.total_usec) + maxi(duration_usec, 0)
	window_entry.max_usec = maxi(int(window_entry.max_usec), maxi(duration_usec, 0))
	var window_samples: Array = window_entry.samples_usec
	window_samples.append(maxi(duration_usec, 0))
	window_entry.samples_usec = window_samples
	_window_timing[name] = window_entry

func set_test_context(layout: String, instances_on_device: Variant = null) -> void:
	var allowed := ["unknown", "split_host", "three_windows", "separate_devices", "other"]
	_test_layout_preference = layout if allowed.has(layout) else "unknown"
	_instances_preference = instances_on_device if instances_on_device == null else clampi(int(instances_on_device), 1, 5)
	if not _capture.is_empty():
		_capture.test_layout = _test_layout_preference
		_capture.instances_on_device = _instances_preference
	var config := ConfigFile.new()
	config.load("user://multiplayer_diagnostics_client.cfg")
	config.set_value("diagnostics", "test_layout", _test_layout_preference)
	config.set_value("diagnostics", "instances_on_device", -1 if _instances_preference == null else _instances_preference)
	config.save("user://multiplayer_diagnostics_client.cfg")

func get_test_layout() -> String:
	return _test_layout_preference

func get_instances_on_device() -> Variant:
	return _instances_preference

func _load_test_context() -> void:
	var config := ConfigFile.new()
	if config.load("user://multiplayer_diagnostics_client.cfg") != OK:
		return
	var layout := str(config.get_value("diagnostics", "test_layout", "unknown"))
	var saved_instances: Variant = config.get_value("diagnostics", "instances_on_device", -1)
	var allowed := ["unknown", "split_host", "three_windows", "separate_devices", "other"]
	_test_layout_preference = layout if allowed.has(layout) else "unknown"
	_instances_preference = clampi(int(saved_instances), 1, 5) if int(saved_instances) > 0 else null

func record_event(event_name: String, details: Dictionary = {}, important: bool = false) -> void:
	_add_event(event_name, details, important)

func record_start_sample(sample: Dictionary) -> void:
	if _capture.is_empty() or str(_capture.get("phase", "")) not in ["startup", "running"]:
		return
	var now := Time.get_ticks_usec()
	if _race_started_usec > 0 and now - _race_started_usec > 3000000:
		return
	if _last_start_sample_usec > 0 and now - _last_start_sample_usec < DETAIL_INTERVAL_USEC:
		return
	_last_start_sample_usec = now
	if _capture.start_samples.size() >= MAX_START_SAMPLES:
		_capture.loss.start_samples_dropped = int(_capture.loss.get("start_samples_dropped", 0)) + 1
		return
	_capture.start_samples.append({"t_ms": _elapsed_ms(), "sample": _sanitize(sample)})

func mark_simulation_started(details: Dictionary = {}) -> void:
	_race_started_usec = Time.get_ticks_usec()
	_add_event("simulation_started", details, true)

func mark_problem(label: String) -> void:
	if _capture.is_empty():
		return
	if not _incident_capture.is_empty():
		if _capture.incidents.size() < MAX_INCIDENTS:
			_capture.incidents.append(_incident_capture.duplicate(true))
		_incident_capture = {}
	if _capture.incidents.size() >= MAX_INCIDENTS:
		_capture.loss.incidents_dropped = int(_capture.loss.get("incidents_dropped", 0)) + 1
		return
	var before: Array = []
	for sample in _capture.detail_samples:
		if int(sample.get("t_ms", 0)) >= _elapsed_ms() - 5000:
			before.append(sample.duplicate(true))
	_incident_capture = {"label": label.left(32), "started_t_ms": _elapsed_ms(), "partial": false, "pre_samples": before, "samples": [], "remaining_usec": 5000000}
	_add_event("incident_marked", {"label": label}, true)
	report_changed.emit("Incident marked: " + label)

func finish_match(state: String) -> void:
	if _capture.is_empty():
		return
	if not _incident_capture.is_empty():
		_incident_capture.partial = true
		_capture.incidents.append(_incident_capture.duplicate(true))
		_incident_capture = {}
	_flush_window(Time.get_ticks_usec(), true)
	_capture.capture_end_utc = Time.get_datetime_string_from_system(true)
	_capture.capture_end_monotonic_usec = Time.get_ticks_usec()
	_capture.terminal_state = state
	_add_event("capture_finished", {"terminal_state": state}, true)
	_enforce_capture_memory_budget()
	var completed := _capture.duplicate(true)
	_capture.clear()
	_reports.append(completed)
	while _reports.size() > 2:
		_reports.pop_front()
		_save_loss_marker()
	var full_json := JSON.stringify(_reports)
	if full_json.to_utf8_buffer().size() > MAX_LOCAL_BYTES:
		completed = _reduce_local_report(completed)
		_reports[_reports.size() - 1] = completed
	_save_local()
	report_changed.emit("Multiplayer report saved locally.")

func get_status() -> String:
	if _capture.is_empty():
		return "No active multiplayer diagnostic capture."
	return "Recording multiplayer diagnostics locally."

func get_latest_report() -> Dictionary:
	return _reports.back().duplicate(true) if not _reports.is_empty() else {}

func get_export_text(compact: bool = true) -> String:
	var report := _capture.duplicate(true) if not _capture.is_empty() else get_latest_report()
	if report.is_empty():
		return "No multiplayer diagnostic report yet."
	if compact:
		return _build_clipboard_text(report)
	return JSON.stringify(report, "\t")

func _build_clipboard_text(report: Dictionary) -> String:
	var candidate := _reduce_for_export(report)
	var json_text := JSON.stringify(candidate)
	var reductions := 0
	while json_text.to_utf8_buffer().size() > MAX_CLIPBOARD_BYTES - 32 and reductions < 64:
		reductions += 1
		if not candidate.report.detail_samples.is_empty():
			candidate.report.detail_samples = candidate.report.detail_samples.slice(maxi(0, candidate.report.detail_samples.size() / 2))
		elif not candidate.report.start_samples.is_empty():
			candidate.report.start_samples = candidate.report.start_samples.slice(0, candidate.report.start_samples.size() / 2)
		elif not candidate.report.incidents.is_empty():
			if not _halve_incident_samples(candidate.report.incidents):
				candidate.report.incidents.pop_back()
		elif not candidate.report.browser_samples.is_empty():
			candidate.report.browser_samples = candidate.report.browser_samples.slice(maxi(0, candidate.report.browser_samples.size() / 2))
		elif candidate.report.events.size() > 8:
			candidate.report.events = _prioritize_events(candidate.report.events).slice(0, maxi(8, candidate.report.events.size() / 2))
		elif candidate.report.windows.size() > 4:
			candidate.report.windows = candidate.report.windows.slice(maxi(0, candidate.report.windows.size() / 2))
		else:
			candidate.report.loss.clipboard_metadata_only = true
			candidate.report.detail_samples.clear()
			candidate.report.start_samples.clear()
			candidate.report.incidents.clear()
			candidate.report.browser_samples.clear()
			candidate.report.events = _prioritize_events(candidate.report.events).slice(0, 8)
			candidate.report.windows.clear()
		candidate.report.loss["clipboard_reduced"] = true
		json_text = JSON.stringify(candidate)
	if json_text.to_utf8_buffer().size() > MAX_CLIPBOARD_BYTES - 32:
		candidate.report = _minimal_report_for_export(candidate.report, "clipboard")
		json_text = JSON.stringify(candidate)
	return "GRAVITY_RUN_MP_REPORT v1\n" + json_text

func _minimal_report_for_export(source: Dictionary, destination: String) -> Dictionary:
	var minimal := {}
	for key in ["schema_version", "build_id", "godot_version", "platform", "client_instance_id", "report_id", "match_id", "diagnostic_session_id", "match_generation", "course_identity", "role", "player_label", "test_layout", "device_label", "instances_on_device", "snapshot_rate_hz", "simulation_tick_rate_hz", "capture_start_utc", "capture_start_monotonic_usec", "capture_end_utc", "capture_end_monotonic_usec", "terminal_state", "totals"]:
		if source.has(key):
			minimal[key] = source[key]
	minimal["loss"] = source.get("loss", {}).duplicate(true) if source.get("loss", {}) is Dictionary else {}
	minimal.loss["%s_metadata_only" % destination] = true
	minimal.loss["%s_omitted_sections" % destination] = ["roster", "windows", "detail_samples", "start_samples", "events", "incidents", "browser_samples", "timings"]
	return minimal

func _halve_incident_samples(incidents: Array) -> bool:
	var incident_index := incidents.size() - 1
	while incident_index >= 0:
		var incident: Dictionary = incidents[incident_index]
		if not incident.get("samples", []).is_empty() or not incident.get("pre_samples", []).is_empty():
			incident.samples = incident.get("samples", []).slice(maxi(0, incident.get("samples", []).size() / 2))
			incident.pre_samples = incident.get("pre_samples", []).slice(maxi(0, incident.get("pre_samples", []).size() / 2))
			incidents[incident_index] = incident
			return true
		incident_index -= 1
	return false

func save_latest_report() -> String:
	var report := _capture.duplicate(true) if not _capture.is_empty() else get_latest_report()
	if report.is_empty():
		return ""
	var file_path := "user://multiplayer-report-%s.json" % str(report.get("report_id", "unknown"))
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report, "\t"))
	return file_path

func _flush_window(now_usec: int, final_window: bool = false) -> void:
	if _capture.is_empty() or (_window_frames == 0 and not final_window):
		return
	var duration_ms := float(now_usec - _window_started_usec) / 1000.0
	var gaps := _window_gap_ms.duplicate()
	gaps.sort()
	var counts := _window_transitions.duplicate(true)
	var window := {
		"t_start_ms": int((_window_started_usec - _started_usec) / 1000),
		"duration_ms": duration_ms,
		"process_intervals": gaps.size(),
		"mean_process_rate_hz": float(gaps.size()) / maxf(duration_ms / 1000.0, 0.001),
		"process_gap_p50_ms": _percentile(gaps, 0.50),
		"process_gap_p95_ms": _percentile(gaps, 0.95),
		"process_gap_p99_ms": _percentile(gaps, 0.99),
		"process_gap_max_ms": float(gaps.back()) if not gaps.is_empty() else null,
		"gaps_over_ms": counts,
		"engine_delta_sum_ms": _window_godot_delta_ms,
		"phase": str(_capture.get("phase", "unknown")),
		"phase_gap_stats": _phase_gap_stats(),
		"work_usec": _flush_timing_stats(),
	}
	_capture.windows.append(window)
	while _capture.windows.size() > MAX_WINDOWS:
		_capture.windows.pop_front()
		_capture.loss.windows_dropped = int(_capture.loss.get("windows_dropped", 0)) + 1
	_capture.totals.process_frames = int(_capture.totals.get("process_frames", 0)) + _window_frames
	_window_gap_ms.clear()
	_window_frames = 0
	_window_transitions = {"33": 0, "50": 0, "100": 0, "250": 0}
	_window_godot_delta_ms = 0.0
	_window_timing.clear()
	_window_gaps_by_phase.clear()
	_window_started_usec = now_usec
	_enforce_capture_memory_budget()

func _enforce_capture_memory_budget() -> void:
	if _capture.is_empty():
		return
	var guard_started_usec := Time.get_ticks_usec()
	var reductions := 0
	var bytes := JSON.stringify(_capture).to_utf8_buffer().size()
	while bytes > MAX_LOCAL_BYTES - 512 and reductions < 64:
		reductions += 1
		if not _capture.detail_samples.is_empty():
			_capture.detail_samples = _capture.detail_samples.slice(0, _capture.detail_samples.size() / 2)
			_capture.loss.capture_detail_samples_reduced = true
		elif not _capture.start_samples.is_empty():
			_capture.start_samples = _capture.start_samples.slice(0, _capture.start_samples.size() / 2)
			_capture.loss.capture_start_samples_reduced = true
		elif not _capture.incidents.is_empty():
			if not _halve_incident_samples(_capture.incidents):
				_capture.incidents.pop_back()
			_capture.loss.capture_incidents_reduced = true
		elif not _capture.browser_samples.is_empty():
			_capture.browser_samples = _capture.browser_samples.slice(0, _capture.browser_samples.size() / 2)
			_capture.loss.capture_browser_samples_reduced = true
		elif _capture.events.size() > 8:
			_capture.events = _prioritize_events(_capture.events).slice(0, maxi(8, _capture.events.size() / 2))
			_capture.loss.capture_events_reduced = true
		elif _capture.windows.size() > 4:
			_capture.windows = _capture.windows.slice(0, _capture.windows.size() / 2)
			_capture.loss.capture_windows_reduced = true
		else:
			_capture = _minimal_report_for_export(_capture, "local_capture")
		bytes = JSON.stringify(_capture).to_utf8_buffer().size()
	if _capture.get("totals", {}) is Dictionary:
		_capture.totals["diagnostics_memory_guard_usec"] = int(_capture.totals.get("diagnostics_memory_guard_usec", 0)) + Time.get_ticks_usec() - guard_started_usec

func _phase_gap_stats() -> Dictionary:
	var result := {}
	for phase in _window_gaps_by_phase:
		var gaps: Array = _window_gaps_by_phase[phase]
		gaps.sort()
		result[phase] = {"intervals": gaps.size(), "p50_ms": _percentile(gaps, 0.50), "p95_ms": _percentile(gaps, 0.95), "max_ms": gaps.back() if not gaps.is_empty() else null}
	return result

func _flush_timing_stats() -> Dictionary:
	var result := {}
	for name in _window_timing:
		var entry: Dictionary = _window_timing[name]
		var samples: Array = entry.get("samples_usec", []).duplicate()
		samples.sort()
		result[name] = {"count": entry.get("count", 0), "total_usec": entry.get("total_usec", 0), "max_usec": entry.get("max_usec", 0), "p95_usec": _percentile(samples, 0.95)}
	return result

func _add_event(event_name: String, details: Dictionary, important: bool) -> void:
	if _capture.is_empty():
		return
	if not important:
		var reason := str(details.get("reason", ""))
		var signature := event_name + ":" + reason
		var now_msec := Time.get_ticks_msec()
		if now_msec - int(_ordinary_event_last_msec.get(signature, 0)) < 1000:
			return
		_ordinary_event_last_msec[signature] = now_msec
	var clean: Variant = _sanitize(details)
	var event := {"t_ms": _elapsed_ms(), "event": event_name.left(80), "important": important, "details": clean}
	_capture.events.append(event)
	while _capture.events.size() > MAX_EVENTS:
		var expendable := -1
		for index in range(_capture.events.size()):
			if not bool(_capture.events[index].get("important", false)):
				expendable = index
				break
		if expendable >= 0:
			_capture.events.remove_at(expendable)
		else:
			_capture.events.pop_front()
		_capture.loss.events_dropped = int(_capture.loss.get("events_dropped", 0)) + 1

func _sanitize(value: Variant, depth: int = 0, parent_key: String = "") -> Variant:
	if depth > 8:
		return "[depth_limit]"
	if value is Dictionary:
		var result := {}
		for key in value:
			var name := str(key).to_lower()
			if name in ["token", "access_token", "refresh_token", "email", "sdp", "ice", "candidate", "ip", "url", "signaling_topic", "password", "authorization", "display_name"]:
				continue
			if name in ["user_id", "peer_id", "owner_user_id", "uploaded_by", "player_id", "spectator_target", "spectator_target_user_id"]:
				result[str(key).left(80)] = _safe_player_label(str(value[key]))
			else:
				result[str(key).left(80)] = _sanitize(value[key], depth + 1, name)
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			if result.size() >= 200:
				break
			if parent_key in ["before", "after"] and item is String:
				result.append(_safe_player_label(str(item)))
			else:
				result.append(_sanitize(item, depth + 1, parent_key))
		return result
	if value is String:
		return value.left(512)
	return value

func _safe_player_label(identity: String) -> String:
	return str(_id_to_label.get(identity, "unknown_player"))

func _reduce_for_export(report: Dictionary) -> Dictionary:
	var copy := report.duplicate(true)
	for key in ["detail_samples", "start_samples", "incidents", "browser_samples", "timings"]:
		if not copy.has(key):
			copy[key] = [] if key != "timings" else {}
	copy["detail_samples"] = copy.detail_samples.slice(maxi(0, copy.detail_samples.size() - 120))
	copy["start_samples"] = copy.start_samples.slice(maxi(0, copy.start_samples.size() - 120))
	copy["events"] = _prioritize_events(copy.get("events", [])).slice(maxi(0, copy.get("events", []).size() - 240))
	copy["windows"] = copy.get("windows", []).slice(maxi(0, copy.get("windows", []).size() - 120))
	copy["incidents"] = copy.incidents.slice(0, MAX_INCIDENTS)
	copy["browser_samples"] = copy.browser_samples.slice(maxi(0, copy.browser_samples.size() - 60))
	copy["timings"] = _compact_timings(copy.timings)
	return {"report": copy}

func _compact_timings(timings: Dictionary) -> Dictionary:
	var output := {}
	for name in timings:
		var item: Dictionary = timings[name]
		var samples: Array = item.get("samples_usec", []).duplicate()
		samples.sort()
		output[name] = {"count": item.get("count", 0), "total_usec": item.get("total_usec", 0), "max_usec": item.get("max_usec", 0), "p95_usec": _percentile(samples, 0.95), "last": item.get("last", {})}
	return output

func _reduce_local_report(report: Dictionary) -> Dictionary:
	var copy := report.duplicate(true)
	copy.detail_samples = copy.get("detail_samples", []).slice(maxi(0, copy.get("detail_samples", []).size() - 120))
	copy.start_samples = copy.get("start_samples", []).slice(0, 120)
	copy.events = _prioritize_events(copy.get("events", [])).slice(0, 300)
	copy["local_report_reduced"] = true
	return copy

func _prioritize_events(events: Array) -> Array:
	var important: Array = []
	var ordinary: Array = []
	for event in events:
		if bool(event.get("important", false)):
			important.append(event)
		else:
			ordinary.append(event)
	important.append_array(ordinary)
	return important

func _save_local() -> void:
	var local := {"reports": _reports, "saved_at": Time.get_datetime_string_from_system(true)}
	var serialized := JSON.stringify(local)
	var reductions := 0
	while serialized.to_utf8_buffer().size() > MAX_LOCAL_BYTES and reductions < 4:
		reductions += 1
		for index in range(_reports.size()):
			var report: Dictionary = _reports[index]
			report.detail_samples = report.get("detail_samples", []).slice(maxi(0, report.get("detail_samples", []).size() / 2))
			report.start_samples = report.get("start_samples", []).slice(0, report.get("start_samples", []).size() / 2)
			report.events = _prioritize_events(report.get("events", [])).slice(0, maxi(48, report.get("events", []).size() / 2))
			report["local_report_reduced"] = true
			_reports[index] = report
		local.reports = _reports
		serialized = JSON.stringify(local)
	if serialized.to_utf8_buffer().size() > MAX_LOCAL_BYTES:
		return
	var file := FileAccess.open(LOCAL_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(serialized)

func _load_local() -> void:
	if not FileAccess.file_exists(LOCAL_FILE):
		return
	var file := FileAccess.open(LOCAL_FILE, FileAccess.READ)
	if file == null or file.get_length() > MAX_LOCAL_BYTES:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for report in parsed.get("reports", []):
			if report is Dictionary:
				_reports.append(report)

func _save_loss_marker() -> void:
	if not _reports.is_empty():
		_reports.back().loss.reports_pruned_locally = int(_reports.back().loss.get("reports_pruned_locally", 0)) + 1

func _install_browser_probe() -> void:
	if not OS.has_feature("web") or _js_probe_installed:
		return
	var js := """
	if(!window.__gravityRunMpProbe){
	 const p=window.__gravityRunMpProbe={start:performance.now(),captureStart:performance.now(),last:null,gaps:[],events:[],long:[],status:'ok',observer:false};
	 const ev=(type)=>{p.events.push({type,t:performance.now()});if(p.events.length>80)p.events.shift()};
	 ['visibilitychange','focus','blur','pagehide','pageshow','freeze','resume'].forEach(n=>addEventListener(n,()=>ev(n),true));
	 try{if(window.PerformanceObserver){const o=new PerformanceObserver(l=>{for(const e of l.getEntries()){p.long.push({s:e.startTime,d:e.duration,c:e.attribution&&e.attribution.length?String(e.attribution[0].containerType||'unknown'):'unknown'});if(p.long.length>120)p.long.shift()}});o.observe({type:'longtask',buffered:true});p.observer=true}}catch(e){p.status='longtask_unsupported'}
	 const frame=(t)=>{if(p.last!==null){p.gaps.push(t-p.last);if(p.gaps.length>240)p.gaps.shift()}p.last=t;requestAnimationFrame(frame)};requestAnimationFrame(frame);
	}
	"""
	JavaScriptBridge.eval(js, true)
	_js_probe_installed = true

func _read_browser_probe() -> void:
	if not OS.has_feature("web") or _capture.is_empty():
		return
	var before := Time.get_ticks_usec()
	var raw: Variant = JavaScriptBridge.eval("(()=>{const p=window.__gravityRunMpProbe;if(!p)return JSON.stringify({status:'missing'});const now=performance.now(),s=[...p.gaps].sort((a,b)=>a-b),entries=p.long.filter(x=>x.s>=p.captureStart&&x.s<=now),l=entries.map(x=>x.d).sort((a,b)=>a-b);const q=(a,x)=>a.length?a[Math.min(a.length-1,Math.floor((a.length-1)*x))]:null;let parent=null;try{const d=window.parent.document;parent={visibility:d.visibilityState,hidden:d.hidden,focused:d.hasFocus(),context:'same_origin_parent'}}catch(e){parent={status:'cross_origin_or_unavailable'}}const v={status:p.status,js_performance_now_ms:now,visibility:document.visibilityState,hidden:document.hidden,focused:document.hasFocus(),document:'game_iframe_or_top',parent:parent,user_agent:navigator.userAgent,cross_origin_isolated:crossOriginIsolated,raf_samples:s.length,raf_gap_p50_ms:q(s,.5),raf_gap_p95_ms:q(s,.95),raf_gap_max_ms:s.length?s[s.length-1]:null,longtask_supported:p.observer,longtask_count:entries.length,longtask_p95_ms:q(l,.95),longtask_max_ms:l.length?l[l.length-1]:null,longtask_samples:entries.map(x=>({start_ms:x.s-p.captureStart,duration_ms:x.d,container:x.c})),viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},events:p.events.slice(-20)};p.gaps=[];p.long=[];return JSON.stringify(v)})()", true)
	var after := Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(str(raw))
	if parsed is Dictionary:
		parsed.bridge_before_usec = before
		parsed.bridge_after_usec = after
		parsed.bridge_uncertainty_usec = after - before
		parsed.local_to_browser_clock_offset_ms = float(before + after) * 0.0005 - float(parsed.get("js_performance_now_ms", 0.0))
		parsed.local_to_browser_clock_error_bound_ms = float(after - before) * 0.0005
		_capture.browser_samples.append({"t_ms": _elapsed_ms(), "probe": _sanitize(parsed)})
		while _capture.browser_samples.size() > 180:
			_capture.browser_samples.pop_front()

func _elapsed_ms() -> int:
	return maxi(0, int((Time.get_ticks_usec() - _started_usec) / 1000))

func _percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty():
		return null
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)]

func _get_client_instance_id() -> String:
	var config := ConfigFile.new()
	var path := "user://multiplayer_diagnostics_client.cfg"
	if config.load(path) == OK:
		var existing := str(config.get_value("diagnostics", "client_instance_id", ""))
		if _valid_uuid(existing):
			return existing
	var new_id := _new_uuid()
	config.set_value("diagnostics", "client_instance_id", new_id)
	config.save(path)
	return new_id

func _new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return "00000000-0000-4000-8000-000000000000"
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func _valid_uuid(value: String) -> bool:
	var normalized := value.replace("-", "").replace("{", "").replace("}", "")
	if normalized.length() != 32:
		return false
	for character in normalized:
		if not character.to_lower() in "0123456789abcdef":
			return false
	return true
