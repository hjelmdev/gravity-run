extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(918273645, 45000, 4)
	_check(built.get("manifest") is Resource, "the fixture manifest should build")
	if built.get("manifest") is Resource:
		var view: Node2D = Presentation.new()
		root.add_child(view)
		var error := str(view.call("load_manifest", built.manifest))
		_check(error.is_empty(), "shared presentation should accept the V1/V2 race manifest: %s" % error)
		var event_nodes: Dictionary = view.get("event_nodes")
		_check(event_nodes.size() > 40, "presentation should instantiate the shared hazard and terrain scenes")
		_check(view.get("terrain_events").size() > 0, "presentation should retain shared terrain definitions")
		view.call("set_camera_left", 1200.0)
		_check(is_equal_approx(float(view.get("_camera_left")), 1200.0), "presentation should follow the match camera")
		view.call("set_world_state", {"entities": {"test_event": {"state": "destroyed"}}})
		view.queue_free()
	if failures == 0:
		print("Race course presentation tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
