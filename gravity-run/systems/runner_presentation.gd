extends RefCounted
class_name RunnerPresentation
## Samples belong to simulation time. Rendering never writes back to physics.

var previous := Vector2.ZERO
var current := Vector2.ZERO

func reset(at_position: Vector2) -> void:
	previous = at_position
	current = at_position

func push(at_position: Vector2) -> void:
	previous = current
	current = at_position

func sample(fraction: float) -> Vector2:
	return previous.lerp(current, clampf(fraction, 0.0, 1.0))

static func interpolate_states(from: Dictionary, to: Dictionary, fraction: float) -> Dictionary:
	var result := to.duplicate(true)
	var amount := clampf(fraction, 0.0, 1.0)
	for key in ["world_x", "y", "vertical_speed"]:
		result[key] = lerpf(float(from.get(key, to.get(key, 0.0))), float(to.get(key, 0.0)), amount)
	return result
