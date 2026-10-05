extends Node
## Captures every rendered frame from the real MP match/camera path.

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/mp-frame-strips"
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

var failures := 0
var samples: Array[Dictionary] = []
var change_ratios: Array[float] = []

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var service := get_tree().root.get_node("MultiplayerV2Service")
	var old_manifest: Resource = service.current_manifest
	var old_session: Dictionary = service.session.duplicate(true)
	var built: Dictionary = Builder.new().build(SEED, COURSE_LENGTH, Generator.GENERATOR_VERSION)
	if built.get("manifest") == null:
		push_error("Could not build shared manifest for actual MP cave capture")
		get_tree().quit(1)
		return
	service.current_manifest = built.manifest
	service.session = {"round_id": "cave-right-edge-capture", "local_peer_id": 1, "role": "host"}
	var viewports: Array[Vector2i] = [Vector2i(960, 540), Vector2i(540, 960)]
	for size in viewports:
		var viewport := _make_viewport(size)
		var match_node := MatchScene.instantiate() as Node2D
		viewport.add_child(match_node)
		await get_tree().process_frame
		match_node.set_process(false)
		match_node.set_physics_process(false)
		if is_instance_valid(match_node.get("_status_label")):
			(match_node.get("_status_label") as Control).visible = false
		if match_node.get("_course_presentation") == null or match_node.get("_render_camera") == null:
			push_error("Real MultiplayerV2Match did not initialize presentation/camera for %s" % str(size))
			failures += 1
			viewport.queue_free()
			await get_tree().process_frame
			continue
		for segment in ["entry", "interior", "exit"]:
			var start_distance := _segment_start_distance(segment, size.x)
			await _capture_segment(match_node, viewport, size, segment, start_distance)
		match_node.queue_free()
		viewport.queue_free()
		await get_tree().process_frame
	service.current_manifest = old_manifest
	service.session = old_session
	_write_summary()
	print("CAVE_MATCH_RIGHT_EDGE_CAPTURE failures=%d seed=%d fps=60 speed=500 frames_per_segment=%d viewports=960x540,540x960 segments=entry,interior,exit saved=every_rendered_frame" % [failures, SEED, FRAMES_PER_SEGMENT])
	get_tree().quit(1 if failures > 0 else 0)

func _segment_start_distance(segment: String, viewport_width: int) -> float:
	match segment:
		"entry": return 4800.0 - float(viewport_width) - 200.0
		"interior": return 6800.0
		_: return 9600.0 - float(viewport_width) - 200.0

func _capture_segment(match_node: Node2D, viewport: SubViewport, size: Vector2i, segment: String, start_distance: float) -> void:
	var previous: Image
	var local_ratios: Array[float] = []
	for frame in range(FRAMES_PER_SEGMENT):
		var distance := start_distance + float(frame) * SPEED / FPS
		var camera_left := float((match_node.get("_manifest") as Resource).get("start_x")) + distance
		var world_x := camera_left + CameraScript.PLAYER_ANCHOR_X
		var pose := {"valid": true, "stale": false, "world_x": world_x, "y": 270.0, "velocity_x": SPEED, "grounded": true, "gravity_direction": 1, "state": "running", "simulation_tick": distance / SPEED * FPS}
		match_node.set("_local_presentation_pose", pose)
		var runner: Object = match_node.get("_runner")
		var runner_state: Dictionary = runner.get("player_state")
		runner_state.merge(pose, true)
		runner.set("player_state", runner_state)
		match_node.call("_update_spectator_camera")
		var actual_camera_left := float(match_node.get("_camera_left"))
		var camera: Camera2D = match_node.get("_render_camera")
		camera.configure(Vector2(size), CameraScript.PLAYER_ANCHOR_X)
		camera.follow(Vector2(actual_camera_left + CameraScript.PLAYER_ANCHOR_X, 0.0), true)
		var presentation: Node2D = match_node.get("_course_presentation")
		presentation.call("set_camera_left", actual_camera_left)
		presentation.call("set_world_state", match_node.get("_world").call("render_state", 0.0))
		presentation.queue_redraw()
		var screen_anchor := viewport.get_canvas_transform() * Vector2(world_x, 270.0)
		if absf(screen_anchor.x - CameraScript.PLAYER_ANCHOR_X) > 0.05:
			push_error("Actual MP camera lost anchor at %s/%s frame %d: %.3f" % [str(size), segment, frame, screen_anchor.x])
			failures += 1
		await RenderingServer.frame_post_draw
		var full := viewport.get_texture().get_image()
		if full == null or full.is_empty() or full.get_size() != size:
			push_error("MP rendered frame unavailable: %s/%s/%d" % [str(size), segment, frame])
			failures += 1
			continue
		var strip_x := maxi(size.x - STRIP_WIDTH, 0)
		var strip := full.get_region(Rect2i(strip_x, 0, size.x - strip_x, size.y))
		var path := OUTPUT_DIR.path_join("mp_%dx%d_%s_%03d.png" % [size.x, size.y, segment, frame])
		if strip.save_png(path) != OK:
			push_error("Could not save MP right-edge frame: " + path)
			failures += 1
		if previous != null:
			var ratio := _changed_ratio(previous, strip)
			local_ratios.append(ratio)
			change_ratios.append(ratio)
		previous = strip
		if frame % 30 == 0 or frame == FRAMES_PER_SEGMENT - 1:
			var full_path := OUTPUT_DIR.path_join("mp_%dx%d_%s_full_%03d.png" % [size.x, size.y, segment, frame])
			if full.save_png(full_path) != OK:
				push_error("Could not save full context frame: " + full_path)
				failures += 1
		samples.append({"viewport": "%dx%d" % [size.x, size.y], "segment": segment, "frame": frame, "course_distance": distance, "camera_left": actual_camera_left, "fractional_camera_x": actual_camera_left - floorf(actual_camera_left), "right_edge_world_x": actual_camera_left + float(size.x), "strip_path": path})
	var sorted := local_ratios.duplicate()
	sorted.sort()
	var p50 := float(sorted[int(sorted.size() * 0.50)]) if not sorted.is_empty() else 0.0
	var p95 := float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]) if not sorted.is_empty() else 0.0
	print("CAVE_MP_SEQUENCE viewport=%s segment=%s frames=%d strip=%dpx speed=%.1f p50_changed=%.5f p95_changed=%.5f max_changed=%.5f" % [str(size), segment, FRAMES_PER_SEGMENT, STRIP_WIDTH, SPEED, p50, p95, float(sorted.back()) if not sorted.is_empty() else 0.0])

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

func _write_summary() -> void:
	var file := FileAccess.open(OUTPUT_DIR.path_join("frames.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write bounded frame metadata")
		failures += 1
		return
	file.store_string(JSON.stringify({"seed": SEED, "generator": Generator.GENERATOR_VERSION, "fps": FPS, "speed": SPEED, "frames_per_segment": FRAMES_PER_SEGMENT, "viewport_sizes": ["960x540", "540x960"], "saved_strip_frames": samples.size(), "samples": samples}, "\t"))
	file.close()
