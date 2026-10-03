extends SceneTree

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-overnight-review"
const TARGET_DISTANCES := [4700.0, 4790.0, 4800.0, 4810.0, 4900.0, 9500.0, 9590.0, 9600.0, 9610.0, 9700.0, 14390.0, 14400.0, 14410.0]
const MAX_WAIT_SECONDS := 100.0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var portrait := OS.get_environment("BIOME_CAPTURE_PORTRAIT") == "1"
	var capture_size := Vector2i(540, 960) if portrait else Vector2i(1280, 720)
	var capture_suffix := "-portrait" if portrait else ""
	if not OS.get_environment("BIOME_CAPTURE_TARGET").is_empty() and OS.get_environment("BIOME_CAPTURE_SEEK") != "1":
		capture_suffix += "-live-demo"
	DisplayServer.window_set_size(capture_size)
	var challenge := root.get_node("ChallengeService")
	challenge.set("active", true)
	challenge.set("seed_value", 100000014)
	challenge.set("generation_version", 9)
	var ruleset_script: Script = load("res://systems/course_generation_ruleset.gd")
	var ruleset := ruleset_script.new() as Resource
	ruleset.set("revision", 6)
	ruleset.set("event_density", 1.55)
	challenge.set("ruleset", ruleset)
	seed(100000014)
	var scene := load("res://main.tscn").instantiate() as Node2D
	scene.set("demo_mode", true)
	root.add_child(scene)
	var hud: CanvasLayer = scene.get_node("HUDLayer")
	hud.visible = true
	scene.get_node("HUDLayer/HUD").visible = true
	var output_names: Array[String] = []
	var capture_targets: Array = TARGET_DISTANCES.duplicate()
	if not OS.get_environment("BIOME_CAPTURE_TARGET").is_empty():
		capture_targets = [float(OS.get_environment("BIOME_CAPTURE_TARGET"))]
	var started := Time.get_ticks_usec()
	var capture_index := 0
	var previous_distance := -1.0
	var restart_count := 0
	var seek_samples := OS.get_environment("BIOME_CAPTURE_SEEK") == "1"
	if seek_samples:
		scene.set_physics_process(false)
	while capture_index < capture_targets.size() and float(Time.get_ticks_usec() - started) / 1000000.0 < MAX_WAIT_SECONDS:
		await process_frame
		if seek_samples:
			var target_player_x := 180.0 + float(capture_targets[capture_index])
			scene.get("player").position.x = target_player_x
			scene.get("player").set("world_x", target_player_x)
			scene.set("course_distance", float(capture_targets[capture_index]))
			var target_horizon := float(capture_targets[capture_index]) + float(scene.get("screen_width")) + 1400.0
			scene.get("course_generator").call("ensure_horizon", target_horizon, 500.0, float(scene.get("screen_height")), 820.0)
			scene.get("_presentation").reset(scene.get("player").position)
			scene.call("_process", 0.0)
			await process_frame
		var distance := float(scene.get("course_distance"))
		if previous_distance >= 0.0 and distance + 100.0 < previous_distance:
			restart_count += 1
			if OS.get_environment("BIOME_CAPTURE_ROTATE_SEED") == "1":
				challenge.set("seed_value", int(challenge.get("seed_value")) + 1)
				print("SP_CAPTURE_NEXT_DEMO_SEED=%d" % int(challenge.get("seed_value")))
		previous_distance = distance
		var target := float(capture_targets[capture_index])
		if distance < target:
			continue
		await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("SP root viewport capture returned no GPU pixels")
			quit(1)
			return
		var theme := BiomeRenderer.biome_id_at(distance)
		var path := OUTPUT_DIR.path_join("sp-v9%s-distance-%05d.png" % [capture_suffix, int(target)])
		var save_error := image.save_png(path)
		if save_error != OK:
			push_error("SP capture save failed: %s" % path)
			quit(1)
			return
		output_names.append(path.get_file())
		print("SP_MAIN_SCENE_GPU_CAPTURE mode=%s target=%.0f actual=%.1f biome=%s generated_events=%d restart_count=%d" % ["seek_fixture" if seek_samples else "live_demo", target, distance, theme, scene.course_generator.get_planned_events().size(), restart_count])
		capture_index += 1
	if capture_index != capture_targets.size():
		push_error("SP capture only reached %d/%d target distances; current=%.1f restarts=%d" % [capture_index, capture_targets.size(), float(scene.get("course_distance")), restart_count])
		quit(1)
		return
	print("SP_NORMAL_SCENE_CAPTURE_FILES " + ",".join(output_names))
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	quit(0)
