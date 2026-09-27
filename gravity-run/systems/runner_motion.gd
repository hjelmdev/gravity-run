extends RefCounted
class_name RunnerMotion
## Shared runner movement primitives used by both local play and race simulation.

const BASE_RUN_SPEED := 500.0
const SIZE := Vector2(34.0, 44.0)
const FLIP_SPEED := 680.0
const GRAVITY_ACCELERATION := 1900.0
const FLIP_COOLDOWN_SECONDS := 0.42
const SURFACE_SNAP_DISTANCE := 38.0
const DETACH_DISTANCE := 12.0

static func speed_for_multiplier(multiplier: float = 1.0) -> float:
	return BASE_RUN_SPEED * maxf(multiplier, 0.0)

static func distance_for_delta(delta: float, multiplier: float = 1.0, blocked: bool = false) -> float:
	return 0.0 if blocked else speed_for_multiplier(multiplier) * maxf(delta, 0.0)

static func try_flip(state: Dictionary, new_direction: int, cooldown_multiplier: float = 1.0) -> bool:
	if not bool(state.get("grounded", false)) or float(state.get("cooldown", 0.0)) > 0.0:
		return false
	if new_direction not in [-1, 1] or new_direction == int(state.get("gravity_direction", 1)):
		return false
	state["gravity_direction"] = new_direction
	state["grounded"] = false
	state["vertical_speed"] = float(new_direction) * FLIP_SPEED
	state["cooldown"] = FLIP_COOLDOWN_SECONDS * clampf(cooldown_multiplier, 0.5, 2.0)
	return true

static func advance_vertical(state: Dictionary, delta: float, floor_surface_y: float, ceiling_surface_y: float, floor_supported: bool = true, ceiling_supported: bool = true) -> void:
	state["cooldown"] = maxf(float(state.get("cooldown", 0.0)) - delta, 0.0)
	var y := float(state.get("y", 0.0))
	var gravity_direction := int(state.get("gravity_direction", 1))
	var floor_contact_y := floor_surface_y - SIZE.y * 0.5
	var ceiling_contact_y := ceiling_surface_y + SIZE.y * 0.5
	var contact_y := floor_contact_y if gravity_direction > 0 else ceiling_contact_y
	if bool(state.get("grounded", false)) and float(gravity_direction) * (contact_y - y) > DETACH_DISTANCE:
		state["grounded"] = false
		state["vertical_speed"] = 0.0
	var vertical_speed := float(state.get("vertical_speed", 0.0)) + float(gravity_direction) * GRAVITY_ACCELERATION * delta
	y += vertical_speed * delta
	if gravity_direction > 0:
		if not floor_supported:
			state["grounded"] = false
		elif bool(state.get("grounded", false)):
			y = floor_contact_y
			vertical_speed = 0.0
		elif vertical_speed >= 0.0 and y >= floor_contact_y and y - floor_contact_y <= SURFACE_SNAP_DISTANCE:
			y = floor_contact_y
			vertical_speed = 0.0
			state["grounded"] = true
	else:
		if not ceiling_supported:
			state["grounded"] = false
		elif bool(state.get("grounded", false)):
			y = ceiling_contact_y
			vertical_speed = 0.0
		elif vertical_speed <= 0.0 and y <= ceiling_contact_y and ceiling_contact_y - y <= SURFACE_SNAP_DISTANCE:
			y = ceiling_contact_y
			vertical_speed = 0.0
			state["grounded"] = true
	state["y"] = y
	state["vertical_speed"] = vertical_speed
