extends Node

const LavaScene := preload("res://hazards/lava_hazard.tscn")
const LavaHazard := preload("res://hazards/lava_hazard.gd")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
const MainScene := preload("res://main.tscn")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const CameraScript := preload("res://systems/runner_camera.gd")

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/crack-captures"
const SEED := 100000014
const COURSE_DISTANCE := 1400.0
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_check_crack_geometry()
	var build: Dictionary = Builder.new().build(SEED, 45000, Generator.GENERATOR_VERSION)
	_check(build.get("manifest") != null, "shared current manifest builds for SP/MP crack capture")
	if build.get("manifest") == null:
		get_tree().quit(1)
		return
	var service := get_tree().root.get_node("MultiplayerV2Service")
	var old_manifest: Resource = service.current_manifest
	var old_session: Dictionary = service.session.duplicate(true)
	service.current_manifest = build.manifest
	service.session = {"round_id": "ceiling-crack-visual-fixture", "local_peer_id": 1, "role": "host"}
	for dimensions in [Vector2i(1280, 720), Vector2i(540, 960)]:
		await _capture_sp(dimensions)
		await _capture_mp(dimensions, build.manifest)
	service.current_manifest = old_manifest
	service.session = old_session
	print("CAVE_CRACK_VISUAL_TEST failures=%d seed=%d contexts=main.tscn,multiplayer_v2_match.tscn viewports=1280x720,540x960" % [failures, SEED])
	get_tree().quit(1 if failures > 0 else 0)

func _check_crack_geometry() -> void:
	for from_ceiling in [false, true]:
		var event := {"kind": "lava_crack", "x": 700.0, "y": 180.0 if from_ceiling else 390.0, "width": 140.0, "hot_depth": 18.0, "visual_depth": 26.0, "from_ceiling": from_ceiling}
		var art: Dictionary = LavaHazard.crack_art_geometry(event)
		var surface := float(event.y)
		var inward := -1.0 if from_ceiling else 1.0
		var glow: Rect2 = art.glow
		_check(is_equal_approx(glow.end.y, surface) if from_ceiling else is_equal_approx(glow.position.y, surface), "crack glow touches and stays on the solid side of %s surface" % ("ceiling" if from_ceiling else "floor"))
		for point in art.zigzag:
			_check((point.y - surface) * inward >= -0.001, "crack zigzag never extends into play corridor")
		for branch in art.branches:
			for point in branch:
				_check((point.y - surface) * inward >= -0.001, "crack branches never extend into play corridor")
		_check(float(art.zigzag[0].y) == surface and float(art.zigzag[art.zigzag.size() - 1].y) == surface, "crack art meets surface at both ends")
		var hitbox: Rect2 = LavaModel.crack_rect(event)
		_check(is_equal_approx(hitbox.size.y, 20.0), "lethal crack depth contract remains unchanged")

func _capture_sp(dimensions: Vector2i) -> void:
	var seed_code := "GR%d-%d" % [Generator.GENERATOR_VERSION_15, SEED]
	if not bool(ChallengeService.call("start_singleplayer_seed_input", seed_code)):
		_check(false, "actual SP capture accepts the documented current-version seed")
		return
	var viewport := _make_viewport(dimensions)
	var main := MainScene.instantiate() as Node2D
	main.set("demo_mode", true)
	main.set_process(false)
	main.set_physics_process(false)
	viewport.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.set_physics_process(false)
	main.call("_sync_screen_size")
	main.get("course_generator").call("ensure_horizon", COURSE_DISTANCE + dimensions.x + 900.0, 500.0, 900.0, 1100.0)
	var floor_x := COURSE_DISTANCE + float(dimensions.x) * 0.62
	var ceiling_x := COURSE_DISTANCE + float(dimensions.x) * 0.40
	_add_crack(main, ceiling_x, float(main.call("_ceiling_surface_y", ceiling_x)), true, 180.0)
	_add_crack(main, floor_x, float(main.call("_floor_surface_y", floor_x)), false, 180.0)
	main.set("course_distance", COURSE_DISTANCE)
	main.set("_render_course_distance", COURSE_DISTANCE)
	var player: Node2D = main.get("player")
	player.set("world_x", COURSE_DISTANCE + CameraScript.PLAYER_ANCHOR_X)
	player.position = Vector2(COURSE_DISTANCE + CameraScript.PLAYER_ANCHOR_X, float(main.call("_floor_surface_y", COURSE_DISTANCE + CameraScript.PLAYER_ANCHOR_X)) - 22.0)
	main.set("_render_player_position", player.position)
	main.call("_update_camera")
	await _save_view(viewport, "sp", dimensions)
	viewport.queue_free()
	await get_tree().process_frame
	ChallengeService.call("clear_challenge")

func _capture_mp(dimensions: Vector2i, manifest: Resource) -> void:
	var viewport := _make_viewport(dimensions)
	var match_node := MatchScene.instantiate() as Node2D
	viewport.add_child(match_node)
	await get_tree().process_frame
	match_node.set_process(false)
	match_node.set_physics_process(false)
	if is_instance_valid(match_node.get("_status_label")):
		(match_node.get("_status_label") as Control).visible = false
	var presentation: Node2D = match_node.get("_course_presentation")
	var ceiling_x := COURSE_DISTANCE + float(dimensions.x) * 0.40
	var floor_x := COURSE_DISTANCE + float(dimensions.x) * 0.62
	_add_crack(presentation, ceiling_x, float(presentation.call("_surface_y_at", ceiling_x, true)), true, float(manifest.start_x))
	_add_crack(presentation, floor_x, float(presentation.call("_surface_y_at", floor_x, false)), false, float(manifest.start_x))
	var world_x := COURSE_DISTANCE + CameraScript.PLAYER_ANCHOR_X
	var pose := {"world_x": world_x, "y": 438.0, "velocity_x": 500.0, "grounded": true, "gravity_direction": 1, "state": "running", "simulation_tick": 84.0}
	match_node.set("_local_presentation_pose", pose)
	var runner: Object = match_node.get("_runner")
	var state: Dictionary = runner.get("player_state")
	state.merge(pose, true)
	runner.set("player_state", state)
	match_node.call("_update_spectator_camera")
	var camera: Camera2D = match_node.get("_render_camera")
	camera.configure(Vector2(dimensions), CameraScript.PLAYER_ANCHOR_X)
	camera.follow(Vector2(COURSE_DISTANCE + CameraScript.PLAYER_ANCHOR_X, 0.0), true)
	presentation.call("set_camera_left", COURSE_DISTANCE)
	presentation.call("set_world_state", match_node.get("_world").call("render_state", 0.0))
	await _save_view(viewport, "mp", dimensions)
	viewport.queue_free()
	await get_tree().process_frame

func _add_crack(parent: Node, world_x: float, surface_y: float, from_ceiling: bool, course_start_x: float) -> void:
	var event := {"kind": "lava_crack", "event_id": "visual_crack_%s_%d" % ["ceiling" if from_ceiling else "floor", int(world_x)], "x": world_x, "y": surface_y, "width": 180.0, "hot_depth": 18.0, "visual_depth": 26.0, "from_ceiling": from_ceiling}
	var crack := LavaScene.instantiate() as Node2D
	crack.name = str(event.event_id)
	parent.add_child(crack)
	crack.call("configure", event, course_start_x)
	crack.call("apply_simulation_tick", 84.0, course_start_x)

func _save_view(viewport: SubViewport, mode: String, dimensions: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := OUTPUT_DIR.path_join("%s_%dx%d.png" % [mode, dimensions.x, dimensions.y])
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_check(false, "actual %s crack scene screenshot saved for %s" % [mode, str(dimensions)])
	else:
		print("CRACK_CAPTURE mode=%s viewport=%s path=%s" % [mode, str(dimensions), path])

func _make_viewport(dimensions: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_tree().root.add_child(viewport)
	return viewport

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
