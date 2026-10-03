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

static func hitbox(event: Dictionary, tick: int, activation_tick: int) -> Rect2:
	if phase_at(event, activation_tick, tick) != DANGEROUS:
		return Rect2()
	var size := Vector2(float(event.get("width", 72.0)), float(event.get("height", 96.0)))
	return Rect2(center(event) - size * 0.5, size)

static func state(event: Dictionary, activation_tick: int, tick: int) -> Dictionary:
	var phase := phase_at(event, activation_tick, tick)
	return {"event_id": str(event.get("event_id", "")), "activation_tick": activation_tick, "tick": tick, "phase": phase, "x": center(event).x, "y": center(event).y, "from_ceiling": bool(event.get("from_ceiling", false)), "visible": phase not in [DORMANT, EXPIRED]}
