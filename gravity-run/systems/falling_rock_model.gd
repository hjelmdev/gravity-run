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
	if int(event.get("rock_variant", 0)) == 1:
		if tick < fall_start:
			return "warning"
		if tick < impact_tick or (not bool(event.get("floor_supported", true)) and tick < fall_start + int(event.get("fall_ticks", FALL_TICKS)) * 2):
			return "falling"
		if not bool(event.get("floor_supported", true)):
			return "expired"
		if tick < impact_tick + int(event.get("lodged_ticks", 240)):
			return "lodged"
		return "expired"
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
	if int(event.get("rock_variant", 0)) == 1 and bool(event.get("from_ceiling", false)):
		ceiling_y = float(event.get("ceiling_y", 80.0))
		top_center = ceiling_y + height * 0.5
		if not bool(event.get("floor_supported", true)):
			bottom_center = floor_y + height * 1.2
			fall_ticks *= 2.0
	if activation_tick < 0 or tick < fall_start:
		return Vector2(x, top_center)
	var fraction := clampf((tick - fall_start) / fall_ticks, 0.0, 1.0)
	return Vector2(x, lerpf(top_center, bottom_center, fraction))

static func hitbox_at(event: Dictionary, activation_tick: int, tick: float) -> Rect2:
	var phase := phase_at(event, activation_tick, floori(tick))
	var icicle := int(event.get("rock_variant", 0)) == 1
	if (icicle and phase not in ["falling", "lodged"]) or (not icicle and phase not in ["falling", "buried"]):
		return Rect2()
	var center := center_at(event, activation_tick, tick)
	var width := float(event.get("width", WIDTH))
	var height := float(event.get("height", HEIGHT))
	var rect := Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height))
	if phase == "buried" or phase == "lodged":
		rect.size.y -= float(event.get("burial_depth", BURIAL_DEPTH))
	return rect

static func swept_contact_fraction(event: Dictionary, activation_tick: int, start_tick: int, end_tick: int, start: Vector2, finish: Vector2, body_size: Vector2) -> float:
	if end_tick <= start_tick:
		return -1.0
	if int(event.get("rock_variant", 0)) == 1:
		return _swept_icicle_contact_fraction(event, activation_tick, start_tick, end_tick, start, finish, body_size)
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

static func _swept_icicle_contact_fraction(event: Dictionary, activation_tick: int, start_tick: int, end_tick: int, start: Vector2, finish: Vector2, body_size: Vector2) -> float:
	if activation_tick < 0:
		return -1.0
	var active_start := float(activation_tick + int(event.get("warning_ticks", WARNING_TICKS)))
	var active_end := active_start + maxf(float(event.get("fall_ticks", FALL_TICKS)), 1.0)
	if bool(event.get("floor_supported", true)):
		active_end += maxf(float(event.get("lodged_ticks", 240)), 0.0)
	else:
		active_end += maxf(float(event.get("fall_ticks", FALL_TICKS)), 1.0)
	var duration := float(end_tick - start_tick)
	if float(end_tick) <= active_start or float(start_tick) >= active_end:
		return -1.0
	var first := -1.0
	const SUBSTEPS := 24
	for index in range(SUBSTEPS):
		var requested_t0 := float(index) / float(SUBSTEPS)
		var requested_t1 := float(index + 1) / float(SUBSTEPS)
		var tick0 := lerpf(float(start_tick), float(end_tick), requested_t0)
		var tick1 := lerpf(float(start_tick), float(end_tick), requested_t1)
		var clipped_tick0 := maxf(tick0, active_start)
		# Expiration is exclusive. Sampling just before the boundary retains the
		# final visible collision pose and never sweeps the icicle toward (0, 0).
		var clipped_tick1 := minf(tick1, active_end - 0.0001)
		if clipped_tick1 < clipped_tick0:
			continue
		var t0 := clampf((clipped_tick0 - float(start_tick)) / duration, 0.0, 1.0)
		var t1 := clampf((clipped_tick1 - float(start_tick)) / duration, 0.0, 1.0)
		var rock0 := hitbox_at(event, activation_tick, clipped_tick0)
		var rock1 := hitbox_at(event, activation_tick, clipped_tick1)
		if rock0.size == Vector2.ZERO or rock1.size == Vector2.ZERO:
			continue
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
