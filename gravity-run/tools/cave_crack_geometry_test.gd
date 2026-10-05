extends SceneTree

const LavaHazard := preload("res://hazards/lava_hazard.gd")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
var failures := 0

func _initialize() -> void:
	for from_ceiling in [false, true]:
		var event := {"kind": "lava_crack", "x": 700.0, "y": 180.0 if from_ceiling else 390.0, "width": 140.0, "hot_depth": 18.0, "visual_depth": 26.0, "from_ceiling": from_ceiling}
		var geometry: Dictionary = LavaHazard.crack_art_geometry(event)
		var surface := float(event.y)
		var inward := -1.0 if from_ceiling else 1.0
		var glow: Rect2 = geometry.glow
		_check(is_equal_approx(glow.end.y, surface) if from_ceiling else is_equal_approx(glow.position.y, surface), "glow reaches the solid surface without entering the corridor")
		for point in geometry.zigzag:
			_check((float(point.y) - surface) * inward >= -0.001, "main crack zigzag stays in solid terrain")
		for branch in geometry.branches:
			for point in branch:
				_check((float(point.y) - surface) * inward >= -0.001, "crack branch stays in solid terrain")
		_check(is_equal_approx(float(geometry.zigzag[0].y), surface) and is_equal_approx(float(geometry.zigzag[-1].y), surface), "crack touches the surface at both edges")
		var hitbox: Rect2 = LavaModel.crack_rect(event)
		_check(is_equal_approx(hitbox.size.y, 20.0), "existing lethal crack rectangle depth is unchanged")
		_check(is_equal_approx(hitbox.position.y, surface - (0.0 if from_ceiling else 2.0)), "existing lethal crack rectangle origin is unchanged")
	print("CAVE_CRACK_GEOMETRY_TEST failures=%d lanes=floor,ceiling art=inset contact=unchanged" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
