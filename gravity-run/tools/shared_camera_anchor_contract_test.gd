extends SceneTree

const CameraScript := preload("res://systems/runner_camera.gd")
var failures := 0

func _initialize() -> void:
	var camera := CameraScript.new() as Camera2D
	camera.configure(Vector2(960.0, 540.0), CameraScript.PLAYER_ANCHOR_X)
	var lifecycle: Array[String] = ["preparing", "countdown", "start", "running", "spectating"]
	var samples: Array[float] = [180.0, 180.0, 180.0, 181.0, 180.0]
	var previous_screen_x := -1.0
	for index in range(samples.size()):
		var world_x: float = samples[index]
		camera.follow(Vector2(world_x, 270.0))
		var camera_left := CameraScript.camera_left_for_world_x(world_x)
		var screen_x := world_x - camera_left
		_check(is_equal_approx(camera_left, camera.left), "%s uses the shared camera-left transform" % lifecycle[index])
		_check(is_equal_approx(screen_x, CameraScript.PLAYER_ANCHOR_X), "%s keeps the runner at the same 180px anchor" % lifecycle[index])
		if previous_screen_x >= 0.0:
			_check(absf(screen_x - previous_screen_x) <= 0.001, "%s introduces no start gliding" % lifecycle[index])
		previous_screen_x = screen_x
	var mp_source := FileAccess.get_file_as_string("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
	_check(mp_source.count("CameraScript.camera_left_for_world_x") == 3, "MP local and spectator camera paths all use the shared helper")
	_check(not mp_source.contains("maxf(float(local_pose.get(\"world_x\""), "MP no longer clamps the shared anchor transition")
	print("SHARED_CAMERA_ANCHOR_CONTRACT_TEST failures=%d stages=%s" % [failures, ",".join(lifecycle)])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
