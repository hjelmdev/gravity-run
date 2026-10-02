extends SceneTree

const Rock := preload("res://hazards/falling_rock.gd")
const Model := preload("res://systems/falling_rock_model.gd")

var failures := 0

func _initialize() -> void:
	var surface_y := 100.0
	var width := 90.0
	var mask: Rect2 = Rock.buried_ground_occlusion_mask(surface_y, width)
	_check(is_equal_approx(mask.position.y, surface_y - 8.0), "ground overlay begins eight pixels above the nominal surface")
	_check(mask.end.y > surface_y, "ground overlay covers the rock polygon below the surface")
	_check(mask.position.x < -width * 0.5 and mask.end.x > width * 0.5, "overlay spans the full rock width with edge margin")
	var event := {"x": 2000.0, "floor_y": 460.0, "height": 100.0, "width": width, "burial_depth": 24.0}
	var hitbox: Rect2 = Model.hitbox_at(event, 0, 56.0)
	_check(is_equal_approx(hitbox.position.y, 384.0) and is_equal_approx(hitbox.end.y, 460.0), "buried collision remains the established permanent above-ground rectangle")
	_check(is_equal_approx(mask.size.y, 13.0), "the visual cover stays a shallow presentation layer")
	if failures == 0:
		print("Falling rock burial occlusion tests passed; gameplay hitbox contract is unchanged.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
