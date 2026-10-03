extends SceneTree

const Showcase := preload("res://tools/biome_saw_showcase.tscn")
const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-overnight-review"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var directory := DirAccess.open("E:/Utveckling/Gravity Run")
	if directory == null:
		push_error("Unable to open workspace output parent")
		quit(1)
		return
	if not directory.dir_exists(".codex-overnight-review"):
		directory.make_dir(".codex-overnight-review")
	var failures: Array[String] = []
	for size in [Vector2i(1280, 720), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.add_child(Showcase.instantiate())
		await process_frame
		await process_frame
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			failures.append("GPU viewport capture failed for %s" % str(size))
		else:
			var suffix := "landscape" if size.x > size.y else "portrait"
			var path := OUTPUT_DIR + "/biome-saw-" + suffix + ".png"
			var save_error := image.save_png(path)
			if save_error != OK:
				failures.append("failed to save %s: %s" % [path, error_string(save_error)])
			else:
				print("BIOME_SHOWCASE_CAPTURE %s %s %dx%d" % [suffix, path, size.x, size.y])
		viewport.queue_free()
		await process_frame
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
