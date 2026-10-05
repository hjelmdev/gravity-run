extends Node
## Uses the actual MatchScene process callback/camera/presentation path.
## A deterministic test pose driver feeds one local runner while the match's
## normal _process and camera update remain enabled; no transport is involved.

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/mp-live-process"
const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const CameraScript := preload("res://systems/runner_camera.gd")
const SEED := 100000014
const COURSE_LENGTH := 45000
const SPEED := 500.0
const FPS := 60.0
const FRAMES_PER_SEGMENT := 180
const STRIP_WIDTH := 220

class PoseDriver extends Node:
	var match_node: Node2D
	var clock
	var start_distance := 0.0
	var start_tick := 0

	func begin_segment(distance: float) -> void:
		start_distance = distance
		start_tick = int(round(distance / SPEED * FPS))
		match_node.set("_round_started", true)
		match_node.set("_world_tick", start_tick - 1)
		match_node.set("_local_start_deadline_usec", -1)
		match_node.get("_local_pose_history").clear()
		var runner = match_node.get("_runner")
		runner.active = true
		runner.simulation_tick = start_tick - 1
		var x := float(match_node.get("_manifest").get("start_x")) + start_distance - SPEED / FPS + CameraScript.PLAYER_ANCHOR_X
		var pose := {"world_x": x, "y": 270.0, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "blocked": false, "state": "running"}
		runner.player_state = pose.duplicate(true)
		runner.previous_render_state = pose.duplicate(true)
		runner.current_render_state = pose.duplicate(true)
		clock.reset_round()
		match_node.get("_world").tick = start_tick - 1
		match_node.call("_record_local_pose", start_tick - 1)

	func set_render_step(frame: int) -> void:
		var tick := start_tick + frame
		var distance := start_distance + float(frame) * SPEED / FPS
		var base_x := float(match_node.get("_manifest").get("start_x")) + distance + CameraScript.PLAYER_ANCHOR_X
		var pose := {"world_x": base_x, "y": 270.0, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "blocked": false, "state": "running"}
		var next_pose := pose.duplicate(true)
		next_pose["world_x"] = base_x + SPEED / FPS
		var runner = match_node.get("_runner")
		runner.player_state = next_pose.duplicate(true)
		runner.previous_render_state = pose.duplicate(true)
		runner.current_render_state = next_pose.duplicate(true)
		runner.simulation_tick = tick + 1
		match_node.set("_world_tick", tick + 1)
		match_node.get("_world").tick = tick + 1
		var history: Array = match_node.get("_local_pose_history")
		history.clear()
		history.append(_pose_entry(pose, tick))
		history.append(_pose_entry(next_pose, tick + 1))
		# Align the coordinator's shared clock with the controlled test sample.
		# Match._process then samples this history and performs its normal camera
		# update; the capture never calls camera.follow or presentation setters.
		clock.started_at_usec = Time.get_ticks_usec() - int(round((float(tick) + 1.25) / FPS * 1_000_000.0))

	func _pose_entry(pose: Dictionary, tick: int) -> Dictionary:
		return {"tick": tick, "world_x": float(pose.world_x), "y": float(pose.y), "vertical_speed": 0.0, "velocity_x": SPEED, "gravity_direction": 1, "grounded": true, "blocked": false, "locomotion_state": "running"}

var failures := 0
var frame_rows: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var service := get_tree().root.get_node("MultiplayerV2Service")
	var old_manifest: Resource = service.current_manifest
	var old_session: Dictionary = service.session.duplicate(true)
	var built: Dictionary = Builder.new().build(SEED, COURSE_LENGTH, Generator.GENERATOR_VERSION)
	if built.get("manifest") == null:
		push_error("Could not build current manifest for live-process fixture")
		get_tree().quit(1)
		return
	service.current_manifest = built.manifest
	service.session = {"round_id": "cave-live-process-capture", "local_peer_id": 1, "role": "host"}
	for size in [Vector2i(960, 540), Vector2i(540, 960)]:
		var viewport := _make_viewport(size)
		var match_node := MatchScene.instantiate() as Node2D
		viewport.add_child(match_node)
		var pose_driver := PoseDriver.new()
		pose_driver.name = "ControlledSharedClockPose"
		pose_driver.process_priority = -100
		pose_driver.clock = service._round_coordinator.clock
		viewport.add_child(pose_driver)
		await get_tree().process_frame
		if match_node.get("_course_presentation") == null or match_node.get("_render_camera") == null:
			push_error("Actual match scene lacks camera/presentation at %s" % str(size))
			failures += 1
			viewport.queue_free()
			continue
		if is_instance_valid(match_node.get("_status_label")):
			(match_node.get("_status_label") as Control).visible = false
		pose_driver.match_node = match_node
		match_node.set_process(true)
		match_node.set_physics_process(false)
		for segment in ["entry", "interior", "exit"]:
			pose_driver.begin_segment(_segment_start_distance(segment, size.x))
			await get_tree().process_frame
			await _capture_frames(match_node, viewport, size, segment, pose_driver)
		match_node.set_process(false)
		pose_driver.match_node = null
		viewport.remove_child(pose_driver)
		pose_driver.queue_free()
		match_node.queue_free()
		viewport.queue_free()
		await get_tree().process_frame
	service.current_manifest = old_manifest
	service.session = old_session
	_write_metadata()
	print("CAVE_LIVE_PROCESS_CAPTURE failures=%d seed=%d generator=%d frames=%d process=enabled shared_clock=controlled transport=none" % [failures, SEED, Generator.GENERATOR_VERSION, frame_rows.size()])
	get_tree().quit(1 if failures > 0 else 0)

func _capture_frames(match_node: Node2D, viewport: SubViewport, size: Vector2i, segment: String, pose_driver: PoseDriver) -> void:
	var presentation: Node2D = match_node.get("_course_presentation")
	var previous_index := int(match_node.get("_render_callback_index"))
	var previous_camera_left := NAN
	var previous: Image
	var ratios: Array[float] = []
	for frame in range(FRAMES_PER_SEGMENT):
		var callback_before := int(match_node.get("_render_callback_index"))
		pose_driver.set_render_step(frame)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var callback_index := int(match_node.get("_render_callback_index"))
		if callback_index <= callback_before or callback_index <= previous_index:
			push_error("Actual Match._process callback did not advance before rendered frame %s/%s/%d" % [str(size), segment, frame])
			failures += 1
		previous_index = callback_index
		var camera_left := float(match_node.get("_camera_left"))
		var draw_left := float(presentation.get("_camera_left"))
		var transform := viewport.get_canvas_transform()
		var applied_left := (transform.affine_inverse() * Vector2(0.0, float(size.y) * 0.5)).x
		var applied_right := (transform.affine_inverse() * Vector2(float(size.x), float(size.y) * 0.5)).x
		var right_error := absf(applied_right - (draw_left + float(size.x)))
		var left_error := absf(applied_left - draw_left)
		if absf(camera_left - draw_left) > 0.05 or right_error > 0.25 or left_error > 0.25:
			push_error("MP camera/draw view diverged: viewport=%s segment=%s callback=%d camera=%.3f draw=%.3f applied=[%.3f,%.3f] errors=[%.3f,%.3f]" % [str(size), segment, callback_index, camera_left, draw_left, applied_left, applied_right, left_error, right_error])
			failures += 1
		if is_finite(previous_camera_left) and absf((camera_left - previous_camera_left) - SPEED / FPS) > 0.1:
			push_error("Actual Match._process camera failed controlled 500px/s step: viewport=%s segment=%s callback=%d previous=%.3f current=%.3f" % [str(size), segment, callback_index, previous_camera_left, camera_left])
			failures += 1
		previous_camera_left = camera_left
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Rendered image unavailable at %s/%s/%d" % [str(size), segment, frame])
			failures += 1
			continue
		var strip_x := maxi(size.x - STRIP_WIDTH, 0)
		var strip := image.get_region(Rect2i(strip_x, 0, size.x - strip_x, size.y))
		var strip_path := OUTPUT_DIR.path_join("live_%dx%d_%s_%03d.png" % [size.x, size.y, segment, frame])
		if strip.save_png(strip_path) != OK:
			push_error("Could not save live-process right edge frame: " + strip_path)
			failures += 1
		if previous != null:
			ratios.append(_changed_ratio(previous, strip))
		previous = strip
		if frame % 30 == 0 or frame == FRAMES_PER_SEGMENT - 1:
			var full_path := OUTPUT_DIR.path_join("live_%dx%d_%s_full_%03d.png" % [size.x, size.y, segment, frame])
			if image.save_png(full_path) != OK:
				push_error("Could not save full live-process frame: " + full_path)
				failures += 1
		frame_rows.append({"viewport": "%dx%d" % [size.x, size.y], "segment": segment, "frame": frame, "callback_index": callback_index, "camera_left": camera_left, "presentation_left": draw_left, "applied_left": applied_left, "applied_right": applied_right, "left_error": left_error, "right_error": right_error, "render_fraction": float(match_node.get("_render_fraction")), "shared_clock_presentation_tick": float(match_node.get("_last_presentation_tick")), "runner_x": float(match_node.get("_local_presentation_pose").get("world_x", -1.0)), "strip_path": strip_path})
	var sorted := ratios.duplicate()
	sorted.sort()
	var p50 := float(sorted[int(sorted.size() * 0.50)]) if not sorted.is_empty() else 0.0
	var p95 := float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]) if not sorted.is_empty() else 0.0
	print("CAVE_LIVE_PROCESS_SEQUENCE viewport=%s segment=%s frames=%d p50_changed=%.5f p95_changed=%.5f max_changed=%.5f" % [str(size), segment, FRAMES_PER_SEGMENT, p50, p95, float(sorted.back()) if not sorted.is_empty() else 0.0])

func _segment_start_distance(segment: String, width: int) -> float:
	match segment:
		"entry": return 4800.0 - float(width) - 200.0
		"interior": return 6800.0
		_: return 9600.0 - float(width) - 200.0

func _changed_ratio(previous: Image, current: Image) -> float:
	if previous.get_size() != current.get_size():
		return 1.0
	var changed := 0
	var total := current.get_width() * current.get_height()
	for y in range(current.get_height()):
		for x in range(current.get_width()):
			if previous.get_pixel(x, y) != current.get_pixel(x, y):
				changed += 1
	return float(changed) / float(maxi(total, 1))

func _make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_tree().root.add_child(viewport)
	return viewport

func _write_metadata() -> void:
	var file := FileAccess.open(OUTPUT_DIR.path_join("live_frames.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write live-process metadata")
		failures += 1
		return
	file.store_string(JSON.stringify({"seed": SEED, "generator": Generator.GENERATOR_VERSION, "fps": FPS, "speed": SPEED, "frames_per_segment": FRAMES_PER_SEGMENT, "viewports": ["960x540", "540x960"], "process_enabled": true, "shared_clock_controlled": true, "network_transport": false, "frame_count": frame_rows.size(), "frames": frame_rows}, "\t"))
	file.close()
