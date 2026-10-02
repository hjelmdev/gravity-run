extends SceneTree

const Presentation := preload("res://systems/race_course_presentation.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var course: Node2D = Presentation.new()
	root.add_child(course)
	await process_frame
	var accessible := course.get_node_or_null("RockWarningAccessibility") as Button
	_check(accessible != null, "the warning icon has an accessible focus target")
	if accessible == null:
		quit(1)
		return
	_check(accessible.accessibility_name == "Fallande sten" and accessible.tooltip_text == "Fallande sten", "warning symbol retains the localized accessible description and tooltip")
	_check(not accessible.visible, "the accessible symbol stays hidden when no rock is dangerous")
	for viewport_size in [Vector2(960.0, 540.0), Vector2(540.0, 960.0)]:
		var center: Vector2 = Presentation.rock_warning_marker_center(120.0, viewport_size, 460.0)
		_check(is_equal_approx(center.x - 120.0, viewport_size.x - 56.0), "the warning stays at the forward edge for landscape and narrow portrait logical viewports")
	var viewport_width := course.get_viewport_rect().size.x
	var event := {"floor_y": 460.0}
	course.set_world_state({"rocks": [{"event_id": "rock-1", "phase": "warning", "x": 2400.0, "event": event}]})
	course.set_camera_left(1000.0)
	_check(accessible.visible, "the forward-edge symbol is exposed while a warning rock is offscreen")
	_check(is_equal_approx(accessible.position.x + 24.0, 1000.0 + viewport_width - 56.0), "the edge symbol remains on the forward edge, away from the runner")
	course.set_world_state({"rocks": [{"event_id": "rock-1", "phase": "falling", "x": 1200.0, "event": event}]})
	_check(is_equal_approx(accessible.position.x + 24.0, 1200.0), "the accessible target follows the in-world warning sign after the rock enters view")
	course.set_world_state({"rocks": []})
	_check(not accessible.visible, "the warning target disappears after the falling phase ends")
	course.reset()
	_check(course.get_node_or_null("RockWarningAccessibility") == accessible, "loading the next round preserves the accessibility marker")
	if failures == 0:
		print("Rock warning symbol passed: shared warning states position the vector marker and translated tooltip at the edge and impact site.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
