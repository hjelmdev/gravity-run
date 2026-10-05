extends SceneTree

const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-biome-feedback-review"

class BackdropProbe extends Node2D:
	const Renderer := preload("res://biomes/biome_renderer.gd")
	var course_distance := 0.0
	func _draw() -> void:
		Renderer.draw_backdrop(self, 0.0, Vector2(1280.0, 540.0), course_distance)

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var failures: Array[String] = []
	for distance in [4799.0, 4800.0, 4801.0, 9599.0, 9600.0, 9601.0]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 540)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.transparent_bg = false
		root.add_child(viewport)
		var probe := BackdropProbe.new()
		probe.course_distance = distance
		viewport.add_child(probe)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := OUTPUT_DIR.path_join("cave-boundary-%.0f.png" % distance)
		if image == null or image.is_empty() or image.save_png(path) != OK:
			failures.append("failed to capture backdrop at %.0f" % distance)
		else:
			print("CAVE_BACKDROP_GPU_CAPTURE distance=%.0f file=%s size=%s" % [distance, path, str(image.get_size())])
		viewport.queue_free()
		await process_frame
	if failures.is_empty():
		print("CAVE_BACKDROP_GPU_CAPTURE PASS captures=6, shared draw_backdrop across classic/cave/haunted clipping boundaries")
	else:
		for failure in failures:
			push_error(failure)
	quit(1 if not failures.is_empty() else 0)
