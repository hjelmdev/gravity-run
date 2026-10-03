extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")
const OverlayScript := preload("res://tools/multiplayer_v2/overnight_mp_capture_overlay.gd")
const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-overnight-review"
const TARGET_DISTANCES := [4700.0, 4790.0, 4800.0, 4810.0, 4900.0, 9500.0, 9590.0, 9600.0, 9610.0, 9700.0, 14390.0, 14400.0, 14410.0]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var portrait := OS.get_environment("BIOME_CAPTURE_PORTRAIT") == "1"
	var capture_size := Vector2i(540, 960) if portrait else Vector2i(1280, 720)
	var capture_suffix := "-portrait" if portrait else ""
	var built: Dictionary = Builder.new().build(100000014, 45000, 9)
	var manifest: Resource = built.get("manifest")
	if manifest == null:
		push_error("V9 manifest failed: %s" % str(built.get("error", "")))
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = capture_size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var presentation := PresentationScript.new() as RaceCoursePresentation
	viewport.add_child(presentation)
	var load_error := str(presentation.load_manifest(manifest))
	if not load_error.is_empty():
		push_error("MP race presentation failed to load v9 manifest: " + load_error)
		quit(1)
		return
	var world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	var configure_error := str(world.configure(manifest))
	if not configure_error.is_empty():
		push_error("MP world simulation failed to configure: " + configure_error)
		quit(1)
		return
	var overlay := OverlayScript.new() as Node2D
	viewport.add_child(overlay)
	var output_names: Array[String] = []
	for distance in TARGET_DISTANCES:
		# The production match camera is course-relative (runner world_x minus
		# the 180 px spawn anchor), so keep capture coordinates identical.
		var camera_left := float(distance)
		var tick := int(round(float(distance) / 500.0 * 60.0))
		world.step_to(tick)
		presentation.call("set_camera_left", camera_left)
		presentation.position.x = -camera_left
		presentation.call("set_world_state", world.render_state(0.5))
		var biome_name := BiomeRenderer.biome_id_at(float(distance))
		var player_y := float(presentation.call("_surface_y_at", camera_left + float(manifest.get("start_x")) + 197.0, false)) - 22.0
		overlay.call("set_capture_state", player_y, float(distance), biome_name)
		await process_frame
		await process_frame
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("MP viewport capture had no image at distance %.0f" % float(distance))
			quit(1)
			return
		var path := OUTPUT_DIR.path_join("mp-v9%s-distance-%05d.png" % [capture_suffix, int(distance)])
		var save_error := image.save_png(path)
		if save_error != OK:
			push_error("MP capture save failed: %s" % path)
			quit(1)
			return
		output_names.append(path.get_file())
		print("MP_NORMAL_PRESENTATION_CAPTURE distance=%.0f biome=%s tick=%d camera=%.1f" % [float(distance), biome_name, tick, camera_left])
	print("MP_NORMAL_PRESENTATION_CAPTURE_FILES " + ",".join(output_names))
	viewport.queue_free()
	await process_frame
	quit(0)
