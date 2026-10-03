extends RefCounted
class_name GhostWarningPulse

const DURATION_SECONDS := 1.35
const MAX_TRACKED_EVENT_IDS := 128
const GHOST_TEXTURE: Texture2D = preload("res://hazards/ghost.svg")

var _elapsed := -1.0
var _seen_event_ids: Dictionary = {}
var _seen_order: Array[String] = []
var _floor_warning := false
var _ceiling_warning := false

func reset() -> void:
	_elapsed = -1.0
	_seen_event_ids.clear()
	_seen_order.clear()
	_floor_warning = false
	_ceiling_warning = false

func observe_warning(event_id: String, from_ceiling: bool) -> bool:
	if event_id.is_empty() or _seen_event_ids.has(event_id):
		return false
	_seen_event_ids[event_id] = true
	_seen_order.append(event_id)
	while _seen_order.size() > MAX_TRACKED_EVENT_IDS:
		_seen_event_ids.erase(_seen_order.pop_front())
	if _elapsed < 0.0:
		_elapsed = 0.0
		_floor_warning = false
		_ceiling_warning = false
	if from_ceiling:
		_ceiling_warning = true
	else:
		_floor_warning = true
	return true

func advance(delta: float) -> bool:
	if _elapsed < 0.0:
		return false
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= DURATION_SECONDS:
		_elapsed = -1.0
		_floor_warning = false
		_ceiling_warning = false
	return true

func is_active() -> bool:
	return _elapsed >= 0.0

func alpha() -> float:
	if not is_active():
		return 0.0
	var progress := clampf(_elapsed / DURATION_SECONDS, 0.0, 1.0)
	var envelope := clampf(minf(progress / 0.10, (1.0 - progress) / 0.16), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * cos(progress * TAU * 2.0)
	return envelope * (0.62 + pulse * 0.30)

func scale() -> float:
	if not is_active():
		return 1.0
	var pulse := 0.5 + 0.5 * cos((_elapsed / DURATION_SECONDS) * TAU * 2.0)
	return 0.95 + pulse * 0.06

func draw(canvas: CanvasItem, center: Vector2) -> void:
	if not is_active():
		return
	var opacity := alpha()
	var size := 44.0 * scale()
	canvas.draw_texture_rect(GHOST_TEXTURE, Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(0.78, 0.80, 1.0, opacity))
	if _floor_warning:
		_draw_direction(canvas, center + Vector2(36.0, 0.0), 1.0, opacity)
	if _ceiling_warning:
		_draw_direction(canvas, center + Vector2(-36.0, 0.0), -1.0, opacity)

func _draw_direction(canvas: CanvasItem, center: Vector2, direction: float, opacity: float) -> void:
	var tint := Color(0.80, 0.72, 1.0, opacity)
	var tip := center + Vector2(0.0, 12.0 * direction)
	var left := center + Vector2(-7.0, -2.0 * direction)
	var right := center + Vector2(7.0, -2.0 * direction)
	canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), tint)
	canvas.draw_line(center + Vector2(0.0, -11.0 * direction), center + Vector2(0.0, 2.0 * direction), tint, 2.0, true)
