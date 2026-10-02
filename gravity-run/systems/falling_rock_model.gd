extends RefCounted
class_name FallingRockModel
## Shared tick-addressed lifecycle and collision geometry for falling rocks.

const WARNING_TICKS := 36
const FALL_TICKS := 20
const DELIVERY_TICKS := 12
const TRIGGER_LEAD := 1100.0
const WIDTH := 90.0
const HEIGHT := 100.0
const BURIAL_DEPTH := 24.0

static func phase_at(event: Dictionary, activation_tick: int, tick: int) -> String:
	if activation_tick < 0 or tick < activation_tick:
		return "dormant"
	var start_tick := activation_tick
	var fall_start := start_tick + int(event.get("warning_ticks", WARNING_TICKS))
	var impact_tick := fall_start + int(event.get("fall_ticks", FALL_TICKS))
	if tick < fall_start:
		return "warning"
	if tick < impact_tick:
		return "falling"
	return "buried"

static func offscreen_marker_active(phase: String) -> bool:
	return phase in ["warning", "falling"]

static func center_at(event: Dictionary, activation_tick: int, tick: float) -> Vector2:
	var x := float(event.get("x", 0.0))
	var ceiling_y := float(event.get("ceiling_y", 80.0))
	var floor_y := float(event.get("floor_y", 460.0))
	var height := float(event.get("height", HEIGHT))
	var warning := float(event.get("warning_ticks", WARNING_TICKS))
	var fall_ticks := maxf(float(event.get("fall_ticks", FALL_TICKS)), 1.0)
	var fall_start := float(activation_tick) + warning
	var impact_tick := fall_start + fall_ticks
	var top_center := ceiling_y + height * 0.5
	var bottom_center := floor_y - height * 0.5 + float(event.get("burial_depth", BURIAL_DEPTH))
	if activation_tick < 0 or tick < fall_start:
		return Vector2(x, top_center)
	var fraction := clampf((tick - fall_start) / fall_ticks, 0.0, 1.0)
	return Vector2(x, lerpf(top_center, bottom_center, fraction))

static func hitbox_at(event: Dictionary, activation_tick: int, tick: float) -> Rect2:
	var phase := phase_at(event, activation_tick, floori(tick))
	if phase not in ["falling", "buried"]:
		return Rect2()
	var center := center_at(event, activation_tick, tick)
	var width := float(event.get("width", WIDTH))
	var height := float(event.get("height", HEIGHT))
	var rect := Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height))
	if phase == "buried":
		rect.size.y -= float(event.get("burial_depth", BURIAL_DEPTH))
	return rect

static func swept_contact_fraction(event: Dictionary, activation_tick: int, start_tick: int, end_tick: int, start: Vector2, finish: Vector2, body_size: Vector2) -> float:
	if end_tick <= start_tick:
		return -1.0
	var first := -1.0
	const SUBSTEPS := 24
	for index in range(SUBSTEPS):
		var t0 := float(index) / float(SUBSTEPS)
		var t1 := float(index + 1) / float(SUBSTEPS)
		var active_start_tick := float(activation_tick + int(event.get("warning_ticks", WARNING_TICKS)))
		var interval_start_tick := lerpf(float(start_tick), float(end_tick), t0)
		var interval_end_tick := lerpf(float(start_tick), float(end_tick), t1)
		if interval_start_tick < active_start_tick and interval_end_tick >= active_start_tick:
			t0 = maxf(t0, (active_start_tick - float(start_tick)) / float(end_tick - start_tick))
		var rock_tick0 := lerpf(float(start_tick), float(end_tick), t0)
		var rock_tick1 := lerpf(float(start_tick), float(end_tick), t1)
		var rock0 := hitbox_at(event, activation_tick, rock_tick0)
		var rock1 := hitbox_at(event, activation_tick, rock_tick1)
		if rock0.size == Vector2.ZERO and rock1.size == Vector2.ZERO:
			continue
		if rock0.size == Vector2.ZERO:
			rock0 = Rect2(center_at(event, activation_tick, rock_tick0) - Vector2(float(event.get("width", WIDTH)), float(event.get("height", HEIGHT))) * 0.5, Vector2(float(event.get("width", WIDTH)), float(event.get("height", HEIGHT))))
		var player0 := Rect2(start.lerp(finish, t0) - body_size * 0.5, body_size)
		var player1 := Rect2(start.lerp(finish, t1) - body_size * 0.5, body_size)
		var relative_start := player0.position - rock0.position
		var relative_displacement := (player1.position - player0.position) - (rock1.position - rock0.position)
		var relative_target := Rect2(Vector2.ZERO, rock0.size)
		var polygon := PackedVector2Array([relative_target.position, Vector2(relative_target.end.x, relative_target.position.y), relative_target.end, Vector2(relative_target.position.x, relative_target.end.y)])
		var fraction := HazardRules.swept_rect_polygon_fraction(Rect2(relative_start, body_size), relative_displacement, polygon)
		if fraction >= 0.0:
			first = lerpf(t0, t1, fraction)
			break
	return first

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
