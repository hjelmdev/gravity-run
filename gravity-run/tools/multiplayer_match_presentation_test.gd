extends Node

const MatchScript := preload("res://ui/multiplayer_match.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")

func _ready() -> void:
	var manifest: Resource = ManifestScript.new()
	var events: Array[Dictionary] = [
		{"kind": "gap", "x": 200.0, "width": 100.0, "from_ceiling": false},
		{"kind": "gap", "x": 250.0, "width": 100.0, "from_ceiling": false},
	]
	manifest.set("events", events)
	var match_view: Node2D = MatchScript.new()
	match_view.set("_manifest", manifest)
	var floor_intervals: Array = match_view.call("_solid_surface_intervals", false, 0.0, 400.0)
	assert(floor_intervals.size() == 2)
	assert(floor_intervals[0].is_equal_approx(Vector2(0.0, 150.0)))
	assert(floor_intervals[1].is_equal_approx(Vector2(300.0, 400.0)))
	var ceiling_intervals: Array = match_view.call("_solid_surface_intervals", true, 0.0, 400.0)
	assert(ceiling_intervals.size() == 1 and ceiling_intervals[0].is_equal_approx(Vector2(0.0, 400.0)))
	assert(MatchScript.distance_m(180.0, 180.0) == 0)
	assert(MatchScript.distance_m(12005.0, 180.0) == 1182)
	match_view.free()
	print("Multiplayer match presentation tests passed.")
	get_tree().quit()
