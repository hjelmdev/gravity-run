extends RefCounted
class_name MultiplayerV2Diagnostics

const MAX_FRAMES := 4096
const MAX_EVENTS := 2000

var session: Dictionary = {}
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var metrics: Dictionary = {}
var dropped_frames := 0
var dropped_events := 0

func begin_session(metadata: Dictionary) -> void:
	frames.clear()
	events.clear()
	metrics.clear()
	dropped_frames = 0
	dropped_events = 0
	session = metadata.duplicate(true)
	session["network_mode"] = "v2"
	session["started_at_unix"] = Time.get_unix_time_from_system()

func record_frame(frame: Dictionary) -> void:
	if frames.size() >= MAX_FRAMES:
		frames.pop_front()
		dropped_frames += 1
	frames.append(frame.duplicate(true))

func record_event(event_name: String, details: Dictionary = {}) -> void:
	if events.size() >= MAX_EVENTS:
		events.pop_front()
		dropped_events += 1
	events.append({"at_usec": Time.get_ticks_usec(), "at_unix_usec": int(Time.get_unix_time_from_system() * 1_000_000.0), "round_id": str(session.get("round_id", "")), "name": event_name, "details": details.duplicate(true)})

func increment_metric(name: String, amount: int = 1) -> void:
	metrics[name] = int(metrics.get(name, 0)) + amount

func observe_max(name: String, value: float) -> void:
	metrics[name] = maxf(float(metrics.get(name, value)), value)

func export_report() -> Dictionary:
	return {"session": session.duplicate(true), "metrics": metrics.duplicate(true), "frames": frames.duplicate(true), "events": events.duplicate(true), "dropped_frames": dropped_frames, "dropped_events": dropped_events, "exported_at_unix": Time.get_unix_time_from_system()}
