extends RefCounted
class_name GhostHazardModel

const DORMANT := "dormant"
const WARNING := "warning"
const DANGEROUS := "dangerous"
const FADING := "fading"
const EXPIRED := "expired"

static func trigger_x(event: Dictionary) -> float:
	return float(event.get("x", 0.0)) - float(event.get("trigger_lead", 2500.0))

static func phase_at(event: Dictionary, activation_tick: int, tick: int) -> String:
	if activation_tick < 0 or tick < activation_tick:
		return DORMANT
	var elapsed := tick - activation_tick
	var warning_ticks := int(event.get("warning_ticks", 120))
	var danger_ticks := int(event.get("danger_ticks", 500))
	var fade_ticks := int(event.get("fade_ticks", 45))
	if elapsed < warning_ticks:
		return WARNING
	if elapsed < warning_ticks + danger_ticks:
		return DANGEROUS
	if elapsed < warning_ticks + danger_ticks + fade_ticks:
		return FADING
	return EXPIRED

static func center(event: Dictionary) -> Vector2:
	var x := float(event.get("x", 0.0))
	var height := float(event.get("height", 96.0))
	var ceiling := bool(event.get("from_ceiling", false))
	var surface := float(event.get("ceiling_y", 80.0)) if ceiling else float(event.get("floor_y", 460.0))
	var y := surface + height * 0.5 if ceiling else surface - height * 0.5
	return Vector2(x, y)

static func center_at(event: Dictionary, activation_tick: int, tick: float) -> Vector2:
	if int(event.get("ghost_variant", 0)) != 1 or activation_tick < 0:
		return center(event)
	var danger_start := float(activation_tick + int(event.get("warning_ticks", 54)))
	var elapsed_danger := maxf(tick - danger_start, 0.0)
	var x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 1700.0)) - float(event.get("chase_start_lag", 220.0))
	x += float(event.get("chase_speed", 760.0)) * elapsed_danger / 60.0
	var height := float(event.get("height", 96.0))
	var floor_y := float(event.get("floor_y", 460.0))
	return Vector2(x, floor_y - height * 0.5)

static func hitbox(event: Dictionary, tick: int, activation_tick: int) -> Rect2:
	if phase_at(event, activation_tick, tick) != DANGEROUS:
		return Rect2()
	var size := Vector2(float(event.get("width", 72.0)), float(event.get("height", 96.0)))
	return Rect2(center_at(event, activation_tick, tick) - size * 0.5, size)

static func state(event: Dictionary, activation_tick: int, tick: int) -> Dictionary:
	var phase := phase_at(event, activation_tick, tick)
	var pose := center_at(event, activation_tick, float(tick))
	return {"event_id": str(event.get("event_id", "")), "activation_tick": activation_tick, "tick": tick, "phase": phase, "x": pose.x, "y": pose.y, "from_ceiling": bool(event.get("from_ceiling", false)), "visible": phase not in [DORMANT, EXPIRED]}

static func swept_contact_fraction(event: Dictionary, activation_tick: int, start_tick: int, end_tick: int, start_center: Vector2, end_center: Vector2, body_size: Vector2) -> float:
	if activation_tick < 0 or end_tick < start_tick:
		return -1.0
	var danger_start := float(activation_tick + int(event.get("warning_ticks", 120)))
	var danger_end := danger_start + float(int(event.get("danger_ticks", 500)))
	var duration := maxf(float(end_tick - start_tick), 0.0001)
	const SUBSTEPS := 24
	for index in range(SUBSTEPS):
		var global_t0 := float(index) / float(SUBSTEPS)
		var global_t1 := float(index + 1) / float(SUBSTEPS)
		var time0 := lerpf(float(start_tick), float(end_tick), global_t0)
		var time1 := lerpf(float(start_tick), float(end_tick), global_t1)
		if time1 < danger_start or time0 >= danger_end:
			continue
		var active0 := maxf(time0, danger_start)
		var active1 := minf(time1, danger_end)
		if active1 < active0:
			continue
		var t0 := clampf((active0 - float(start_tick)) / duration, 0.0, 1.0)
		var t1 := clampf((active1 - float(start_tick)) / duration, 0.0, 1.0)
		var player0 := start_center.lerp(end_center, t0)
		var player1 := start_center.lerp(end_center, t1)
		var ghost0 := center_at(event, activation_tick, active0)
		var ghost1 := center_at(event, activation_tick, active1)
		var ghost_size := Vector2(float(event.get("width", 72.0)), float(event.get("height", 96.0)))
		var relative_player := Rect2(player0 - ghost0 - body_size * 0.5 + ghost_size * 0.5, body_size)
		var relative_polygon := PackedVector2Array([Vector2.ZERO, Vector2(ghost_size.x, 0.0), ghost_size, Vector2(0.0, ghost_size.y)])
		var local_fraction := HazardRules.swept_rect_polygon_fraction(relative_player, (player1 - player0) - (ghost1 - ghost0), relative_polygon)
		if local_fraction >= 0.0:
			return lerpf(t0, t1, local_fraction)
	return -1.0

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
