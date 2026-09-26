extends SceneTree
## Confirms camera/player motion does not alter a barrel's own spin rate.

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var barrel_scene := load("res://hazards/barrel.tscn") as PackedScene
	var barrel := barrel_scene.instantiate() as Node2D
	root.add_child(barrel)
	await process_frame
	barrel.call("configure", Vector2(54.0, 54.0), false)
	barrel.call("set_motion_speed_multiplier", 1.4)
	barrel.position = Vector2(1000.0, 460.0)
	barrel.call("advance_motion", 1.0, 500.0, Vector2.ZERO, Callable(self, "_floor_y"), Callable(self, "_surface_angle"))
	var running_spin := float(barrel.get("roll_angle"))
	var running_world_x := barrel.position.x
	barrel.position = Vector2(1000.0, 460.0)
	barrel.set("roll_angle", 0.0)
	barrel.call("advance_motion", 1.0, 0.0, Vector2.ZERO, Callable(self, "_floor_y"), Callable(self, "_surface_angle"))
	_check(is_equal_approx(float(barrel.get("roll_angle")), running_spin), "barrel spin should be the same with a moving or stationary camera")
	_check(is_equal_approx(running_world_x, 800.0), "barrel world motion should match its configured relative speed while the player runs")
	_check(is_equal_approx(barrel.position.x, 800.0), "a blocked player should not stop the barrel's own world motion")
	if failures == 0:
		print("Barrel motion tests passed.")
	barrel.queue_free()
	quit(1 if failures > 0 else 0)

func _floor_y(_x: float) -> float:
	return 460.0

func _surface_angle(_x: float, _ceiling: bool) -> float:
	return 0.0

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
