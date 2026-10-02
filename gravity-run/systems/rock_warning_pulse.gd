extends RefCounted
class_name RockWarningPulse

const DURATION_SECONDS := 0.84
const MAX_TRACKED_EVENT_IDS := 128
const PULSE_COUNT := 3.0

var _elapsed := -1.0
var _seen_event_ids: Dictionary = {}
var _seen_order: Array[String] = []

static func screen_center(viewport_size: Vector2) -> Vector2:
	return Vector2(viewport_size.x * 0.5, viewport_size.y * 0.23)

static func world_center(camera_left: float, viewport_size: Vector2) -> Vector2:
	return Vector2(maxf(camera_left, 0.0) + viewport_size.x * 0.5, viewport_size.y * 0.73)

func reset() -> void:
	_elapsed = -1.0
	_seen_event_ids.clear()
	_seen_order.clear()

func observe_warning_events(warnings: Array) -> bool:
	var started := false
	for warning_value in warnings:
		if not warning_value is Dictionary:
			continue
		var warning: Dictionary = warning_value
		if str(warning.get("phase", "")) != "warning":
			continue
		var event_id := str(warning.get("event_id", ""))
		if event_id.is_empty() or _seen_event_ids.has(event_id):
			continue
		_seen_event_ids[event_id] = true
		_seen_order.append(event_id)
		while _seen_order.size() > MAX_TRACKED_EVENT_IDS:
			_seen_event_ids.erase(_seen_order.pop_front())
		if _elapsed < 0.0:
			_elapsed = 0.0
			started = true
	return started

func advance(delta: float) -> bool:
	if _elapsed < 0.0:
		return false
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= DURATION_SECONDS:
		_elapsed = -1.0
		return true
	return true

func is_active() -> bool:
	return _elapsed >= 0.0

func alpha() -> float:
	if not is_active():
		return 0.0
	var progress := clampf(_elapsed / DURATION_SECONDS, 0.0, 1.0)
	var envelope := clampf(minf(progress / 0.10, (1.0 - progress) / 0.16), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * cos(progress * TAU * PULSE_COUNT)
	return envelope * (0.60 + pulse * 0.34)

func scale() -> float:
	if not is_active():
		return 1.0
	var progress := clampf(_elapsed / DURATION_SECONDS, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * cos(progress * TAU * PULSE_COUNT)
	return 0.94 + pulse * 0.08

func seen_event_count() -> int:
	return _seen_event_ids.size()
