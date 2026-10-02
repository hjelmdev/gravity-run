extends SceneTree

const Presentation := preload("res://systems/race_course_presentation.gd")
const Pulse := preload("res://systems/rock_warning_pulse.gd")

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
		_check(is_equal_approx(center.x - 120.0, viewport_size.x - 56.0), "the secondary offscreen direction marker stays at the forward edge in landscape and portrait")
		var hud_center: Vector2 = Pulse.screen_center(viewport_size)
		_check(is_equal_approx(hud_center.x, viewport_size.x * 0.5) and is_equal_approx(hud_center.y, viewport_size.y * 0.23), "the short HUD alert stays centered in both landscape and portrait viewports")
		var world_center: Vector2 = Pulse.world_center(120.0, viewport_size)
		_check(is_equal_approx(world_center.x - 120.0, viewport_size.x * 0.5) and is_equal_approx(world_center.y - viewport_size.y * 0.5, hud_center.y), "the shared warning draw coordinate maps to the same on-screen center")
	var viewport_width := course.get_viewport_rect().size.x
	var event := {"floor_y": 460.0}
	course.set_world_state({"rocks": [{"event_id": "rock-1", "phase": "warning", "x": 2400.0, "event": event}]})
	course.set_camera_left(1000.0)
	_check(accessible.visible, "the central alert exposes its accessible target while a warning rock is offscreen")
	var hud_position := Presentation.rock_warning_hud_center(1000.0, course.get_viewport_rect().size)
	_check(is_equal_approx(accessible.position.x + 24.0, hud_position.x) and is_equal_approx(accessible.position.y + 24.0, hud_position.y), "the pulsing warning is centered in the safe HUD area before the rock arrives")
	_check(accessible.text.is_empty(), "the visual warning does not show a redundant text banner")
	var pulse: RefCounted = course.get("_rock_warning_pulse")
	_check(bool(pulse.call("is_active")), "a warning-phase event starts the central pulse")
	pulse.call("advance", 0.2)
	var alpha_before_repeat := float(pulse.call("alpha"))
	course.set_world_state({"rocks": [{"event_id": "rock-1", "phase": "warning", "x": 2400.0, "event": event}]})
	_check(is_equal_approx(float(pulse.call("alpha")), alpha_before_repeat), "repeated snapshots for one event do not restart the pulse")
	pulse.call("reset")
	course.call("_update_rock_warning_accessibility_marker")
	course.set_world_state({"rocks": [{"event_id": "rock-1", "phase": "falling", "x": 1200.0, "event": event}]})
	_check(is_equal_approx(accessible.position.x + 24.0, 1200.0), "after the short central alert, the accessible target follows the in-world warning sign")
	course.set_world_state({"rocks": []})
	_check(not accessible.visible, "the warning target disappears after the falling phase ends")
	course.reset()
	_check(course.get_node_or_null("RockWarningAccessibility") == accessible, "loading the next round preserves the accessibility marker")
	if failures == 0:
		print("Rock warning symbol passed: shared warning states drive the central pulsing vector alert, direction marker, and accessible tooltip.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
