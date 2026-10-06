extends Node
## Bounded visual capture from the real singleplayer main scene.

const MAIN_SCENE := preload("res://main.tscn")
const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-ghost-review"
const CASES := [
	{"seed": 100000019, "variant": 0, "size": Vector2i(1280, 720)},
	{"seed": 100000005, "variant": 1, "size": Vector2i(540, 960)},
	{"seed": 100000012, "variant": 2, "size": Vector2i(1280, 720)},
]

var _failed := false

func _ready() -> void:
	call_deferred("_capture_cases")

func _capture_cases() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	for capture in CASES:
		await _capture_one(int(capture.seed), int(capture.variant), capture.size)
	if _failed:
		get_tree().quit(1)
	else:
		print("GHOST_VARIANT_MAIN_CAPTURE PASS cases=%d" % CASES.size())
		get_tree().quit(0)

func _capture_one(seed_value: int, target_variant: int, viewport_size: Vector2i) -> void:
	var code := "GR16-%d" % seed_value
	if not ChallengeService.start_singleplayer_seed_input(code):
		_fail("Could not select seeded run %s: %s" % [code, str(ChallengeService.get("last_error"))])
		return
	DisplayServer.window_set_size(viewport_size)
	var game := MAIN_SCENE.instantiate() as Node2D
	game.set("demo_mode", true)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var hud: Node = game.get_node_or_null("HUDLayer/HUD")
	if hud != null:
		hud.visible = true
		hud.call("set_seed", 16, seed_value)
	var target: Node2D
	var activation_tick := -1
	var timeout_usec := Time.get_ticks_usec() + 12_000_000
	while Time.get_ticks_usec() < timeout_usec:
		await get_tree().process_frame
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards"):
				var event: Dictionary = obstacle.get("event")
				if int(event.get("skin_variant", -1)) == target_variant:
					target = obstacle
					var id := str(event.get("event_id", ""))
					var activation_values: Dictionary = game.get("_singleplayer_ghost_activation_ticks")
					if activation_values.has(id):
						activation_tick = int(activation_values[id])
						break
		if is_instance_valid(target) and activation_tick >= 0:
				break
		if bool(game.get("game_over")):
			break
	if not is_instance_valid(target) or activation_tick < 0:
		_fail("%s did not activate a rendered ghost skin %d before timeout" % [code, target_variant])
		game.queue_free()
		await get_tree().process_frame
		return
	while Time.get_ticks_usec() < timeout_usec and int(game.get("_singleplayer_simulation_tick")) < activation_tick + 48:
		await get_tree().process_frame
	var phase := str(target.get("phase"))
	if phase != "warning":
		_fail("%s capture expected the visible warning phase; got %s" % [code, phase])
		game.queue_free()
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var suffix := "portrait" if viewport_size.y > viewport_size.x else "landscape"
	var output_path := OUTPUT_DIR.path_join("gen16_ghost_v%d_%s_seed%d.png" % [target_variant, suffix, seed_value])
	if image == null or image.is_empty() or image.save_png(output_path) != OK:
		_fail("Could not save real main-scene capture %s" % output_path)
	else:
		print("GHOST_MAIN_CAPTURE code=%s variant=%d phase=%s tick=%d distance=%.1f size=%s path=%s" % [code, target_variant, phase, int(game.get("_singleplayer_simulation_tick")), float(game.get("course_distance")), str(viewport_size), output_path])
	if target_variant == 2 and is_instance_valid(target):
		# Capture the actual shared ghost node in the world, separately from its
		# screen-space warning. Freeze simulation, then move only the review camera.
		game.set_process(false)
		game.set_physics_process(false)
		var camera := game.get("camera") as Camera2D
		camera.enabled = true
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2.ONE
		camera.global_position = target.global_position
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var closeup := get_viewport().get_texture().get_image()
		var closeup_path := OUTPUT_DIR.path_join("gen16_ghost_v2_world_closeup_seed%d.png" % seed_value)
		if closeup == null or closeup.is_empty() or closeup.save_png(closeup_path) != OK:
			_fail("Could not save the in-world ghost capture %s" % closeup_path)
		else:
			print("GHOST_WORLD_CAPTURE code=%s variant=%d world=%s camera=%s path=%s" % [code, target_variant, str(target.global_position), str(camera.global_position), closeup_path])
	game.queue_free()
	await get_tree().process_frame

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
