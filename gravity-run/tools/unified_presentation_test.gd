extends SceneTree

const Presentation := preload("res://systems/runner_presentation.gd")
const CameraScript := preload("res://systems/runner_camera.gd")
const Motion := preload("res://systems/runner_motion.gd")
const Simulation := preload("res://systems/multiplayer_simulation.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var camera := CameraScript.new()
	root.add_child(camera)
	camera.configure(Vector2(960, 540), 180.0)
	for speed in [475.0, 500.0, 507.35, 525.0]:
		for fps in [30, 50, 60, 75, 90, 120, 144, 165, 239, 240]:
			var sampler := Presentation.new()
			sampler.reset(Vector2(180, 438))
			var tick := 0
			var previous_x := 180.0
			for frame in range(1, fps * 3):
				var time: float = float(frame) / fps
				var expected_tick := int(floor(time * 60.0 + 0.000001))
				while tick < expected_tick:
					tick += 1
					sampler.push(Vector2(180.0 + speed * tick / 60.0, 438))
				var pose := sampler.sample(time * 60.0 - tick)
				camera.follow(pose)
				_check(absf(pose.x - (180.0 + speed * maxf(time - 1.0 / 60.0, 0.0))) < 0.002, "time-normalized motion at %d Hz and %.2f speed" % [fps, speed])
				_check(pose.x >= previous_x, "monotonic camera")
				_check(absf(pose.x - camera.left - 180.0) < 0.001, "same sampled pose for camera and player")
				previous_x = pose.x
			sampler.push(sampler.current)
			_check(sampler.sample(0.3) == sampler.current, "blocked player does not drift")
			sampler.reset(Vector2(180, 438))
			_check(sampler.sample(0.5) == Vector2(180, 438), "restart cannot interpolate old round")
	_test_irregular_frames(camera)
	var built: Dictionary = Builder.new().build(918273645, 45000, 4)
	var simulation := Simulation.new()
	_check(simulation.configure(built.manifest, [{"user_id": "host", "run_speed_percent": 10147}]).is_empty(), "host fixture")
	simulation.start()
	simulation.advance_frame(2.5 / 60.0, false)
	var raw := simulation.get_snapshot()
	var rendered := simulation.get_render_snapshot()
	_check(absf(float(raw.players[0].world_x) - float(rendered.players[0].world_x) - Motion.BASE_RUN_SPEED * 1.0147 / 120.0) < 0.001, "host interpolation captures last tick during catch-up")
	_check(simulation.get_snapshot() == raw, "presentation never changes authority")
	var scene: Node2D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	var player: Node2D = scene.get_node("Player")
	var collision_before: Rect2 = player.get_player_rect()
	scene.set_render_diagnostics_enabled(true)
	scene.call("_spawn_obstacle_scene", load("res://hazards/block.tscn"), 48.0, 72.0, false, 360.0)
	scene.call("_spawn_obstacle_scene", load("res://hazards/barrel.tscn"), 54.0, 54.0, false, 600.0, 1.4)
	scene._process(1.0 / 144.0)
	_check(scene._render_diagnostic_frames.size() == 1, "singleplayer diagnostics capture render pose")
	var render_frame: Dictionary = scene._render_diagnostic_frames.back()
	_check(render_frame.has("camera_canvas_transform") and render_frame.has("track_surface"), "singleplayer diagnostics capture the applied canvas transform and terrain sample")
	_check(render_frame.has("pose_sampled_usec") and int(render_frame.get("diagnostic_capture_usec", -1)) >= 0, "singleplayer diagnostics bracket pose sampling and their own capture cost")
	var target_nodes: Array = render_frame.get("reference_nodes", [])
	var static_targets: Array = target_nodes.filter(func(target: Dictionary) -> bool: return str(target.get("kind", "")) == "static_hazard")
	var barrel_targets: Array = target_nodes.filter(func(target: Dictionary) -> bool: return str(target.get("kind", "")) == "barrel")
	_check(not static_targets.is_empty(), "singleplayer diagnostics sample a static hazard transform")
	_check(not barrel_targets.is_empty() and barrel_targets[0].has("rendered_canvas_center"), "singleplayer diagnostics sample the barrel's interpolated canvas position")
	if not static_targets.is_empty():
		var static_canvas: Array = static_targets[0].get("canvas_origin", [])
		var expected_canvas: Array = static_targets[0].get("expected_canvas_origin", [])
		_check(static_canvas.size() == 2 and expected_canvas.size() == 2 and Vector2(static_canvas[0], static_canvas[1]).distance_to(Vector2(expected_canvas[0], expected_canvas[1])) < 0.01, "static hazard canvas position agrees with the shared camera transform")
	_check(scene.camera.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and not scene.camera.position_smoothing_enabled, "singleplayer camera cannot add a second interpolation/smoothing loop")
	_check(player.get_player_rect() == collision_before, "singleplayer render offset must preserve collision rect")
	_check(scene.get_node("Camera2D").get_script() == CameraScript, "singleplayer uses shared camera")
	scene.free()
	camera.free()
	_test_v2_scene(built.manifest)
	print("Unified presentation tests: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _test_irregular_frames(camera: Camera2D) -> void:
	var sampler := Presentation.new()
	sampler.reset(Vector2(180, 438))
	var time := 0.0
	var tick := 0
	var last_screen := 0.0
	var frame_pattern := [0.004, 0.009, 0.032, 0.006, 0.020, 0.014]
	for frame in range(600):
		var delta: float = frame_pattern[frame % frame_pattern.size()]
		time += delta
		var next_tick := int(floor(time * 60.0 + 0.000001))
		while tick < next_tick:
			tick += 1
			sampler.push(Vector2(180 + 507.35 * tick / 60.0, 438))
		var pose := sampler.sample(time * 60.0 - tick)
		camera.follow(pose)
		var screen := 8000.0 - float(camera.left)
		if frame > 2:
			_check(absf((last_screen - screen) / delta - 507.35) < 0.15, "stationary obstacle has constant render speed through irregular frames and catch-up ticks")
		last_screen = screen

func _test_v2_scene(manifest: Resource) -> void:
	var service := root.get_node("MultiplayerV2Service")
	service.session = {"local_peer_id": 1, "round_id": "presentation-fixture"}
	service.current_manifest = manifest
	service.room_state = {"members": [{"player_slot": 1, "display_name": "Host"}, {"player_slot": 2, "display_name": "Guest A"}, {"player_slot": 3, "display_name": "Guest B"}]}
	var match_scene: Node2D = load("res://ui/multiplayer_v2/multiplayer_v2_match.tscn").instantiate()
	root.add_child(match_scene)
	match_scene.set_process(false)
	match_scene.set_physics_process(false)
	_check(not match_scene._profiling_enabled, "expensive V2 profiling is opt-in by default")
	match_scene._profiling_enabled = true
	match_scene._course_presentation.set_render_profile_enabled(true)
	_check(match_scene._render_camera.get_script() == CameraScript, "V2 uses shared Camera2D")
	_check(match_scene._course_root.position == Vector2.ZERO, "V2 course is never translated twice")
	match_scene._runner.player_state.world_x = 1500.0
	match_scene._runner.current_render_state.world_x = 1500.0
	match_scene._runner.previous_render_state.world_x = 1491.666667
	for peer in [2, 3]:
		for tick in range(60, 181, 2):
			match_scene._on_remote_sample(peer, {"round_id": "presentation-fixture", "owner_peer_id": peer, "sample_seq": tick, "simulation_tick": tick, "world_x": 180.0 + tick * 500.0 / 60.0, "y": 438.0 - peer * 30.0, "velocity_x": 500.0, "velocity_y": 0.0, "locomotion_state": "running"})
		match_scene._remote_tracks[peer].advance(2.0)
	match_scene._process(1.0 / 144.0)
	_check(match_scene._player_views[2].visible and match_scene._player_views[3].visible, "both remote runners remain visible inside local camera")
	_check(match_scene._player_views[2].position.y != match_scene._player_views[3].position.y, "remote poses retain different vertical positions")
	for peer in [2, 3]:
		var remote_pose: Dictionary = match_scene._remote_track_sample(peer)
		_check(is_equal_approx(match_scene._player_views[peer].position.x, float(remote_pose.get("world_x", -1.0))), "peer %d render x equals sampled collision world x" % peer)
	var track_computations_before_cache_reads := int(match_scene._presentation_work_counts.track_pose_computations)
	var cached_pose_a: Dictionary = match_scene._remote_track_sample(2)
	var cached_pose_b: Dictionary = match_scene._remote_track_sample(2)
	_check(cached_pose_a == cached_pose_b and int(match_scene._presentation_work_counts.track_pose_computations) == track_computations_before_cache_reads, "remote pose is computed once and reused throughout the render frame")
	match_scene._on_terminal_report(1, {"state": "dead", "world_x": 1500.0, "y": 438.0})
	match_scene._process(1.0 / 144.0)
	var target := int(match_scene._spectator_peer_id)
	_check(target > 1, "host death selects a valid living remote runner")
	_check(absf(match_scene._player_views[target].position.x - match_scene._camera_left - match_scene.CAMERA_PLAYER_X) < 0.01, "spectator camera follows the unshifted displayed pose")
	match_scene._on_terminal_report(2, {"state": "finished", "world_x": 1900.0, "y": 408.0})
	match_scene._process(1.0 / 144.0)
	_check(is_equal_approx(match_scene._player_views[2].position.x, 1900.0), "remote terminal pose freezes at confirmed collision position without slot offset")
	_check(match_scene._spectator_peer_id == 3, "spectator moves to remaining running guest")
	_check(match_scene._runner.render_state(0.1).world_x == match_scene._runner.render_state(0.9).world_x, "terminal local V2 runner does not oscillate between ticks")
	match_scene.free()
	service.session = {}
	service.room_state = {}
	service.current_manifest = null
	service.world_simulation = null
