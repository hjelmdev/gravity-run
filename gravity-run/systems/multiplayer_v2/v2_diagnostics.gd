extends RefCounted
class_name MultiplayerV2Diagnostics

const MAX_FRAMES := 4096
const MAX_EVENTS := 2000
const MAX_ROUND_TRACES := 4
const ROUND_TRACE_LIMITS := {"presented_frames": 600, "local_steps": 512, "local_poses": 512, "remote_samples": 1536}
const PRESENTED_FRAME_INTERVAL_USEC := 8333 # 120 Hz; four seconds fit within 600 entries.

var session: Dictionary = {}
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var metrics: Dictionary = {}
var terminal_frames: Array[Dictionary] = []
var round_traces: Array[Dictionary] = []
var active_round_trace: Dictionary = {}
var dropped_frames := 0
var dropped_events := 0
var _last_presented_trace_usec := -1

func begin_session(metadata: Dictionary) -> void:
	frames.clear()
	terminal_frames.clear()
	round_traces.clear()
	active_round_trace.clear()
	events.clear()
	metrics.clear()
	dropped_frames = 0
	dropped_events = 0
	_last_presented_trace_usec = -1
	session = metadata.duplicate(true)
	session["network_mode"] = "v2"
	session["started_at_unix"] = Time.get_unix_time_from_system()

func record_frame(frame: Dictionary) -> void:
	if frames.size() >= MAX_FRAMES:
		frames.pop_front()
		dropped_frames += 1
	var captured := frame.duplicate(true)
	captured["round_id"] = str(session.get("round_id", ""))
	captured["at_unix_usec"] = int(Time.get_unix_time_from_system() * 1_000_000.0)
	frames.append(captured)

func record_event(event_name: String, details: Dictionary = {}) -> void:
	if events.size() >= MAX_EVENTS:
		events.pop_front()
		dropped_events += 1
	events.append({"at_usec": Time.get_ticks_usec(), "at_unix_usec": int(Time.get_unix_time_from_system() * 1_000_000.0), "round_id": str(session.get("round_id", "")), "name": event_name, "details": details.duplicate(true)})

func increment_metric(name: String, amount: int = 1) -> void:
	metrics[name] = int(metrics.get(name, 0)) + amount

func observe_max(name: String, value: float) -> void:
	metrics[name] = maxf(float(metrics.get(name, value)), value)

func preserve_terminal_frames() -> void:
	terminal_frames = frames.slice(maxi(0, frames.size() - 120)).duplicate(true)

func begin_round_trace(round_id: String, local_peer_id: int, role: String, start_deadline_usec: int, clock_uncertainty_usec: float) -> void:
	freeze_round_trace("next_round_started")
	_last_presented_trace_usec = -1
	active_round_trace = {"schema_version": 2, "round_id": round_id, "local_peer_id": local_peer_id, "role": role, "start_deadline_usec": start_deadline_usec, "clock_uncertainty_usec": clock_uncertainty_usec, "created_at_unix_usec": int(Time.get_unix_time_from_system() * 1_000_000.0), "presented_frames": [], "local_steps": [], "local_poses": [], "remote_samples": [], "dropped": {}, "decimated": {}}

func record_round_trace(kind: String, entry: Dictionary) -> void:
	if active_round_trace.is_empty() or not active_round_trace.has(kind):
		return
	var samples: Array = active_round_trace[kind]
	if kind == "presented_frames":
		var now_usec := int(entry.get("local_usec", Time.get_ticks_usec()))
		if _last_presented_trace_usec >= 0 and now_usec - _last_presented_trace_usec < PRESENTED_FRAME_INTERVAL_USEC:
			var decimated: Dictionary = active_round_trace.get("decimated", {})
			decimated[kind] = int(decimated.get(kind, 0)) + 1
			active_round_trace["decimated"] = decimated
			return
		_last_presented_trace_usec = now_usec
	var limit := int(ROUND_TRACE_LIMITS.get(kind, 512))
	if samples.size() >= limit:
		active_round_trace.dropped[kind] = int(active_round_trace.dropped.get(kind, 0)) + 1
		return
	samples.append(entry.duplicate(true))
	active_round_trace[kind] = samples

func freeze_round_trace(reason: String) -> void:
	if active_round_trace.is_empty():
		return
	active_round_trace["ended_at_unix_usec"] = int(Time.get_unix_time_from_system() * 1_000_000.0)
	active_round_trace["freeze_reason"] = reason
	round_traces.append(active_round_trace.duplicate(true))
	while round_traces.size() > MAX_ROUND_TRACES:
		round_traces.pop_front()
	active_round_trace.clear()

func export_report() -> Dictionary:
	return {"session": session.duplicate(true), "terminal_frames": terminal_frames.duplicate(true), "round_traces": round_traces.duplicate(true), "active_round_trace": active_round_trace.duplicate(true), "metrics": metrics.duplicate(true), "frames": frames.duplicate(true), "events": events.duplicate(true), "dropped_frames": dropped_frames, "dropped_events": dropped_events, "exported_at_unix": Time.get_unix_time_from_system()}
