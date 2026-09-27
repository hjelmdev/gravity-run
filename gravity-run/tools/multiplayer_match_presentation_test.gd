extends Node

const MatchScript := preload("res://ui/multiplayer_match.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const PlayerScene := preload("res://player/player.tscn")

func _ready() -> void:
	var player := PlayerScene.instantiate()
	player.call("set_input_enabled", false)
	add_child(player)
	player.call("set_input_enabled", false)
	assert(not player.get_node("AnimatedSprite2D").is_playing(), "a newly added multiplayer runner should safely stop its run animation")
	player.call("set_running", true)
	assert(player.get_node("AnimatedSprite2D").is_playing(), "the shared player scene should resume its animation")
	player.queue_free()
	var manifest: Resource = ManifestScript.new()
	var events: Array[Dictionary] = [
		{"event_id": "block_a", "kind": "block", "x": 120.0, "y": 460.0, "width": 48.0, "height": 72.0, "from_ceiling": false},
		{"kind": "gap", "x": 200.0, "width": 100.0, "from_ceiling": false},
		{"kind": "gap", "x": 250.0, "width": 100.0, "from_ceiling": false},
		{"event_id": "barrels_a", "kind": "barrels", "x": 350.0, "y": 460.0, "width": 124.0, "height": 54.0, "count": 2, "spacing": 70.0, "motion_speed_multiplier": 1.4, "spawn_lead_distance": 820.0},
		{"event_id": "spikes_a", "kind": "spikes", "x": 500.0, "start_x": 470.0, "y": 460.0, "count": 2, "spacing": 32.0, "from_ceiling": false},
		{"event_id": "step_a", "kind": "step", "x": 650.0, "start_y": 460.0, "end_y": 400.0, "spiked": false, "from_ceiling": false},
		{"event_id": "slope_a", "kind": "slope", "x": 900.0, "start_x": 680.0, "end_x": 1120.0, "start_y": 400.0, "end_y": 460.0, "from_ceiling": false},
	]
	manifest.set("events", events)
	manifest.set("initial_floor_y", 460.0)
	manifest.set("initial_ceiling_y", 80.0)
	var match_view: Node2D = MatchScript.new()
	match_view.set("_manifest", manifest)
	var course_root := Node2D.new()
	match_view.add_child(course_root)
	match_view.set("_course_root", course_root)
	match_view.call("_build_course_view")
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 640.0, false)), 460.0))
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 650.1, false)), 400.0))
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 900.0, false)), 430.0))
	assert(match_view.get("_terrain_events").size() == 2, "multiplayer surface rendering should cache both steps and slopes")
	var course_nodes: Dictionary = match_view.get("_course_nodes")
	assert(course_nodes["block_a"].get_script().resource_path == "res://hazards/block.gd")
	assert(course_nodes["barrels_a_0"].get_script().resource_path == "res://hazards/barrel.gd")
	course_nodes["barrels_a_0"].call("apply_replicated_motion", Vector2(333.0, 460.0), 1.25, 0.0, true)
	assert(is_equal_approx(float(course_nodes["barrels_a_0"].get("roll_angle")), 1.25), "networked barrel visuals must update their own draw state")
	assert(bool(course_nodes["barrels_a_0"].visible), "spawned networked barrels should be visible")
	assert(course_nodes["spikes_a_0"].get_script().resource_path == "res://hazards/spikes.gd")
	assert(course_nodes["step_a"].get_script().resource_path == "res://terrain/ledge.gd")
	assert(course_nodes["slope_a"].get_script().resource_path == "res://terrain/slope.gd")
	assert(course_root.get_child_count() == 9, "manifest events should instantiate the same block, barrel, spike and terrain scenes as singleplayer")
	(course_nodes["barrels_a_0"] as Node).free()
	match_view.set("_snapshot", {"world_hazards": {"barrels": [{"entity_id": "barrels_a_0_0"}], "destroyed_event_ids": []}})
	match_view.call("_sync_course_view")
	assert(MatchScript.distance_m(180.0, 180.0) == 0)
	assert(MatchScript.distance_m(12005.0, 180.0) == 1182)
	match_view.free()
	print("Multiplayer match presentation tests passed.")
	get_tree().quit()
