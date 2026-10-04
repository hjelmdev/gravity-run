extends Node
## Visual-only run of the real main scene with a fixed Gen12 challenge.

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-overnight-review"
const SEED := 100000014
const GENERATOR := preload("res://systems/course_generator.gd")
const RULESET := preload("res://systems/course_generation_ruleset.gd")

func _ready() -> void:
	call_deferred("_capture_real_main")

func _capture_real_main() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	ChallengeService.set("active", true)
	ChallengeService.set("seed_value", SEED)
	ChallengeService.set("generation_version", GENERATOR.GENERATOR_VERSION_12)
	ChallengeService.set("ruleset", RULESET.new())
	seed(SEED)
	var main := load("res://main.tscn").instantiate() as Node2D
	main.set("demo_mode", true)
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.get_node("HUDLayer/HUD").visible = true
	main.get_node("HUDLayer/HUD").call("set_seed", GENERATOR.GENERATOR_VERSION_12, SEED)
	for capture in [
		{"name": "main_runtime_gen12_landscape", "size": Vector2i(1280, 720), "wait": 3.0},
		{"name": "main_runtime_gen12_portrait", "size": Vector2i(540, 960), "wait": 4.0},
	]:
		DisplayServer.window_set_size(capture.size)
		await get_tree().process_frame
		await get_tree().process_frame
		var elapsed := 0.0
		while elapsed < float(capture.wait):
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := OUTPUT_DIR.path_join("%s.png" % str(capture.name))
		var save_result := image.save_png(path) if image != null and not image.is_empty() else ERR_CANT_CREATE
		if save_result != OK:
			push_error("Could not save actual main-scene capture: %s" % path)
			get_tree().quit(1)
			return
		print("MAIN_RUNTIME_CAPTURE path=%s course_distance=%.1f seed=%d" % [path, float(main.get("course_distance")), SEED])
	main.queue_free()
	get_tree().quit(0)
