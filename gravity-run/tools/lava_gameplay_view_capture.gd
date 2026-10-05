extends Node
## Non-interactive visual evidence from the real main.tscn SP route and HUD.

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-lava-review"
const GENERATOR := preload("res://systems/course_generator.gd")
const LAVA_MODEL := preload("res://systems/lava_hazard_model.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const ManifestBuilder := preload("res://systems/course_manifest_builder.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")

var main: Node2D
var failed := false

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for dimensions in [Vector2i(1280, 720), Vector2i(540, 960)]:
		DisplayServer.window_set_size(dimensions)
		await get_tree().process_frame
		await get_tree().process_frame
		for kind in ["lava_crack", "volcano"]:
			await _capture_one(dimensions, kind)
	if is_instance_valid(main):
		main.queue_free()
	ChallengeService.call("clear_challenge")
	get_tree().quit(1 if failed else 0)

func _capture_one(dimensions: Vector2i, kind: String) -> void:
	var seed_value: int = 100000034 if kind == "volcano" else 100000014
	if not bool(ChallengeService.call("start_singleplayer_seed_input", "GR%d-%d" % [GENERATOR.GENERATOR_VERSION_15, seed_value])):
		push_error("Could not configure the documented seeded ordinary SP capture run.")
		failed = true
		return
	seed(seed_value)
	main = load("res://main.tscn").instantiate() as Node2D
	main.set("demo_mode", false)
	main.set_physics_process(false)
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.set_physics_process(false)
	main.get_node("HUDLayer/HUD").visible = true
	main.call("_sync_screen_size")
	var generator: Object = main.get("course_generator")
	generator.call("ensure_horizon", 45000.0, 500.0, 900.0, 1100.0)
	var resolved_events: Array[Dictionary] = main.get("_manifest_builder").call("_resolve_events", generator.call("get_planned_events"), 45000, GENERATOR.GENERATOR_VERSION_15)
	var chosen: Dictionary = {}
	for resolved in resolved_events:
		if str(resolved.get("kind", "")) != kind:
			continue
		var distance := float(resolved.get("x", 180.0)) - 180.0
		for source in generator.call("get_planned_events"):
			if str(source.get("kind", "")) == kind and absf(float(source.get("course_distance", INF)) - distance) < 0.5:
				chosen = source.duplicate(true)
				break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		push_error("Capture seed did not produce %s." % kind)
		failed = true
		main.queue_free()
		await get_tree().process_frame
		return
	var view_width := float(main.get("screen_width"))
	var lead := clampf(view_width * 0.30, 90.0, 330.0)
	var course_distance := maxf(0.0, float(chosen.course_distance) - lead)
	_place_main_at(course_distance)
	var spawn_line := course_distance + GENERATOR.get_viewport_spawn_lead_distance(view_width, 180.0, 440.0)
	var events_to_spawn: Array = generator.call("pop_events_until", spawn_line)
	for source_event in events_to_spawn:
		main.call("_spawn_course_event", source_event)
	var target_hazard: Node2D
	for obstacle in main.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("lava_hazards") and str(obstacle.get("event").get("kind", "")) == kind and is_equal_approx(float(obstacle.get("event").get("x", -1.0)), 180.0 + float(chosen.course_distance)):
			target_hazard = obstacle
	if not is_instance_valid(target_hazard):
		push_error("Actual main.tscn terrain/event stream did not spawn %s." % kind)
		failed = true
	else:
		var event: Dictionary = target_hazard.get("event")
		var event_x := float(event.get("x", 0.0))
		var floor_at_event := float(main.call("_floor_surface_y", event_x))
		var ceiling_at_event := float(main.call("_ceiling_surface_y", event_x))
		var support_is_ceiling := bool(event.get("from_ceiling", false)) if kind == "lava_crack" else false
		var actual_surface := ceiling_at_event if support_is_ceiling else floor_at_event
		var resolved_surface := float(event.get("y", NAN)) if kind == "lava_crack" else float(event.get("floor_y", NAN))
		if kind == "volcano":
			resolved_surface = float(event.get("floor_y", NAN))
		var supported := bool(main.call("_surface_is_solid_at_x", event_x, support_is_ceiling))
		if not supported or not is_equal_approx(resolved_surface, actual_surface):
			push_error("SP lava event is not aligned to actual support: kind=%s resolved=%.2f support=%.2f supported=%s" % [kind, resolved_surface, actual_surface, str(supported)])
			failed = true
		var player: Node2D = main.get("player")
		player.position = Vector2(180.0 + course_distance, float(main.call("_floor_surface_y", float(player.get("world_x")))) - RunnerMotion.SIZE.y * 0.5)
		player.set("world_x", 180.0 + course_distance)
		main.set("_render_player_position", player.position)
		main.get("_presentation").call("reset", player.position)
		main.get("run_state").call("add_distance", course_distance)
		var tick := 100
		if kind == "volcano":
			tick = LAVA_MODEL.eruption_start_tick(event, 180.0) + 24
		target_hazard.call("apply_simulation_tick", tick, 180.0)
		main.set("_singleplayer_simulation_tick", tick)
		main.call("_update_camera")
		main.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var aspect := "landscape" if dimensions.x > dimensions.y else "portrait"
		var path := OUTPUT_DIR.path_join("lava_sp_%s_%s.png" % [kind, aspect])
		if image == null or image.is_empty() or image.save_png(path) != OK:
			push_error("Failed to save actual SP capture %s" % path)
			failed = true
		else:
			print("LAVA_MAIN_CAPTURE gen=15 seed=%d kind=%s viewport=%s course_distance=%.1f y=%.2f resolved=%.2f support=%s path=%s" % [seed_value, kind, str(dimensions), course_distance, actual_surface, resolved_surface, str(supported), path])
		await _capture_mp(dimensions, seed_value, course_distance, tick, kind, aspect)
	main.queue_free()
	await get_tree().process_frame

func _capture_mp(dimensions: Vector2i, seed_value: int, camera_left: float, tick: int, kind: String, aspect: String) -> void:
	var built: Dictionary = ManifestBuilder.new().build(seed_value, 45000, GENERATOR.GENERATOR_VERSION_15)
	if built.get("manifest") == null:
		push_error("MP capture could not build the same Gen15 manifest")
		failed = true
		return
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var camera := Camera2D.new()
	camera.position = Vector2(camera_left + float(dimensions.x) * 0.5, float(dimensions.y) * 0.5)
	viewport.add_child(camera)
	camera.make_current()
	var presentation := Presentation.new() as Node2D
	viewport.add_child(presentation)
	var world := WorldSimulation.new()
	var manifest: Resource = built.manifest
	if not str(world.configure(manifest)).is_empty():
		push_error("MP capture shared-world model rejected its Gen15 manifest")
		failed = true
		viewport.queue_free()
		await get_tree().process_frame
		return
	world.tick = tick
	if not str(presentation.call("load_manifest", manifest)).is_empty():
		push_error("MP presentation rejected the same Gen15 manifest")
		failed = true
		viewport.queue_free()
		await get_tree().process_frame
		return
	presentation.call("set_camera_left", camera_left)
	presentation.call("set_world_state", world.render_state(0.0))
	presentation.queue_redraw()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := OUTPUT_DIR.path_join("lava_mp_%s_%s.png" % [kind, aspect])
	if image == null or image.is_empty() or image.save_png(path) != OK:
		push_error("Failed to save MP capture %s" % path)
		failed = true
	else:
		print("LAVA_MP_CAPTURE gen=15 seed=%d kind=%s tick=%d viewport=%s path=%s" % [seed_value, kind, tick, str(dimensions), path])
	viewport.queue_free()
	await get_tree().process_frame

func _place_main_at(course_distance: float) -> void:
	var player: Node2D = main.get("player")
	main.set("course_distance", course_distance)
	main.set("_render_course_distance", course_distance)
	player.set("world_x", 180.0 + course_distance)
	player.position = Vector2(180.0 + course_distance, 438.0)
	main.set("_render_player_position", player.position)
	main.get("_presentation").call("reset", player.position)
	main.call("_update_camera")
