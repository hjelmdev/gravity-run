extends Node

const MainScene := preload("res://main.tscn")
const CASES := [
	{"seed": 100000019, "variant": 0},
	{"seed": 100000005, "variant": 1},
	{"seed": 100000012, "variant": 2},
]
const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-ghost-review"
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for capture in CASES:
		await _capture_one(int(capture.seed), int(capture.variant))
	print("GEN16_GHOST_WORLD_CAPTURE_TEST failures=%d cases=%d" % [failures, CASES.size()])
	get_tree().quit(1 if failures > 0 else 0)

func _capture_one(seed_value: int, skin_variant: int) -> void:
	var code := "GR16-%d" % seed_value
	_check(ChallengeService.start_singleplayer_seed_input(code), "%s selects its deterministic ghost seed" % code)
	DisplayServer.window_set_size(Vector2i(960, 540))
	var game := MainScene.instantiate() as Node2D
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var generator: Object = game.get("course_generator")
	generator.call("ensure_horizon", 24000.0, 500.0, 540.0, 820.0)
	var source_event: Dictionary = {}
	for event in generator.call("get_planned_events"):
		if str(event.get("kind", "")) == "ghost" and int(event.get("skin_variant", -1)) == skin_variant:
			source_event = event.duplicate(true)
			break
	_check(not source_event.is_empty(), "%s generated skin variant %d" % [code, skin_variant])
	if not source_event.is_empty():
		game.call("_spawn_course_event", source_event)
		var target: Node2D
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards") and int(obstacle.get("skin_variant")) == skin_variant:
				target = obstacle
				break
		_check(is_instance_valid(target), "%s actual main spawn adapter creates variant %d" % [code, skin_variant])
		if is_instance_valid(target):
			target.call("set_activation_tick", 0)
			target.call("set_simulation_tick", 60)
			var source_distance := float(source_event.get("course_distance", 0.0))
			var runner := game.get("player") as Node2D
			if is_instance_valid(runner):
				var runner_world_x := target.global_position.x - 360.0
				var floor_y := float(game.call("_floor_surface_y", runner_world_x))
				runner.global_position = Vector2(runner_world_x, floor_y - 22.0)
				runner.set("world_x", runner.global_position.x)
				game.set("_render_player_position", runner.global_position)
				game.set("_render_course_distance", runner.global_position.x - 420.0)
				game.set("course_distance", runner.global_position.x - 420.0)
			var camera := game.get("camera") as Camera2D
			game.call("_update_camera")
			camera.force_update_scroll()
			await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			var path := OUTPUT_DIR.path_join("gen16_ghost_v%d_actual_world_seed%d.png" % [skin_variant, seed_value])
			DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
			_check(image != null and not image.is_empty() and image.save_png(path) == OK, "%s world image for variant %d is saved" % [code, skin_variant])
			print("GEN16_GHOST_WORLD_CAPTURE seed=%d variant=%d source_distance=%.1f event=%s world=%s path=%s" % [seed_value, skin_variant, source_distance, str(source_event.get("id", "")), str(target.global_position), path])
	game.queue_free()
	await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
