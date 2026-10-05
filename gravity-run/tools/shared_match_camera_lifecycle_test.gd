extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const CourseGenerator := preload("res://systems/course_generator.gd")
const CameraScript := preload("res://systems/runner_camera.gd")

class FixtureTrack extends RefCounted:
	var pose: Dictionary = {}
	func set_shared_presentation_tick(_tick: float) -> void:
		pass
	func advance_presentation(_delta: float) -> Dictionary:
		return pose
	func consume_transition() -> String:
		return ""
	func sample_at_render_time() -> Dictionary:
		return pose.duplicate(true)

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := get_tree().root.get_node("MultiplayerV2Service")
	var old_manifest: Resource = service.current_manifest
	var old_session: Dictionary = service.session.duplicate(true)
	var manifest_result: Dictionary = Builder.new().build(100000034, 45000, CourseGenerator.GENERATOR_VERSION)
	_check(manifest_result.get("manifest") != null, "current shared manifest builds for actual match-scene camera fixture")
	if manifest_result.get("manifest") == null:
		get_tree().quit(1)
		return
	service.current_manifest = manifest_result.manifest
	service.session = {"round_id": "camera-lifecycle-fixture", "local_peer_id": 1, "role": "host"}
	for size in [Vector2i(960, 540), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.transparent_bg = false
		get_tree().root.add_child(viewport)
		var match_node := MatchScene.instantiate() as Node2D
		viewport.add_child(match_node)
		await get_tree().process_frame
		_check(match_node.get("_runner") != null and match_node.get("_render_camera") != null, "actual MultiplayerV2Match scene prepares camera at %s" % str(size))
		if match_node.get("_runner") == null or match_node.get("_render_camera") == null:
			viewport.queue_free()
			continue
		# Keep the scene's real simulation/camera methods under test, but stop its
		# autonomous frame loop from racing this deterministic stage fixture.
		match_node.set_process(false)
		match_node.set_physics_process(false)
		var stages: Array[String] = ["preparing", "countdown"]
		for stage in stages:
			_set_runner_running_pose(match_node, 5000.25 if stage == "preparing" else 5008.583333)
			await _assert_local_camera(match_node, size, 5000.25 if stage == "preparing" else 5008.583333, stage)
		# Exercise the connected signal handler on the actual scene, not a transform helper.
		service.round_started.emit("camera-lifecycle-fixture", {"seed": 100000034})
		_set_runner_running_pose(match_node, 5016.916667)
		await _assert_local_camera(match_node, size, 5016.916667, "running")
		var runner: Object = match_node.get("_runner")
		var local_state: Dictionary = runner.get("player_state")
		local_state["state"] = "dead"
		runner.set("player_state", local_state)
		var remote := FixtureTrack.new()
		remote.pose = {"valid": true, "stale": false, "world_x": 5025.25, "y": 270.0, "grounded": false, "gravity_direction": 1, "simulation_tick": 16.0}
		match_node.get("_remote_tracks")[2] = remote
		match_node.get("_remote_terminal")[2] = "running"
		match_node.call("_update_spectator_camera")
		_check(int(match_node.get("_spectator_peer_id")) == 2, "actual match selects the live peer while spectating at %s" % str(size))
		await _assert_camera_target(match_node, size, 5025.25, "spectating")
		match_node.queue_free()
		await get_tree().process_frame
		viewport.queue_free()
		await get_tree().process_frame
	service.current_manifest = old_manifest
	service.session = old_session

	print("SHARED_MATCH_CAMERA_LIFECYCLE_TEST failures=%d viewports=960x540,540x960 stages=preparing,countdown,running,spectating scene=multiplayer_v2_match.tscn" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _assert_local_camera(match_node: Node, size: Vector2i, world_x: float, stage: String) -> void:
	match_node.call("_update_spectator_camera")
	await _assert_camera_target(match_node, size, world_x, stage)

func _set_runner_running_pose(match_node: Node, world_x: float) -> void:
	var runner: Object = match_node.get("_runner")
	var state: Dictionary = runner.get("player_state").duplicate(true)
	state.merge({"world_x": world_x, "y": 270.0, "velocity_x": 500.0, "grounded": true, "gravity_direction": 1, "state": "running"}, true)
	runner.set("player_state", state)
	match_node.set("_local_presentation_pose", state.duplicate(true))
	runner.set("previous_render_state", state.duplicate(true))
	runner.set("current_render_state", state.duplicate(true))

func _assert_camera_target(match_node: Node, size: Vector2i, world_x: float, stage: String) -> void:
	var camera := match_node.get("_render_camera") as Camera2D
	camera.configure(Vector2(size), CameraScript.PLAYER_ANCHOR_X)
	camera.follow(Vector2(float(match_node.get("_camera_left")) + CameraScript.PLAYER_ANCHOR_X, 0.0), true)
	await match_node.get_tree().process_frame
	var screen_x := world_x - float(match_node.get("_camera_left"))
	_check(is_equal_approx(screen_x, CameraScript.PLAYER_ANCHOR_X), "%s scene camera holds actual pose at the shared 180px anchor (%s)" % [stage, str(size)])
	var transformed := match_node.get_viewport().get_canvas_transform() * Vector2(world_x, 270.0)
	_check(absf(transformed.x - CameraScript.PLAYER_ANCHOR_X) <= 0.02, "%s viewport canvas maps world position to the shared anchor (%s)" % [stage, str(size)])

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
