extends SceneTree
## Run with a real rendering driver. Captures the normal singleplayer scene;
## requested FPS is an engine cap, not a claim about physical display refresh.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var captures: Array = []
	for cap in [60, 144]:
		Engine.max_fps = cap
		var scene: Node2D = load("res://main.tscn").instantiate()
		root.add_child(scene)
		scene.set_render_diagnostics_enabled(true)
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 3000 and not scene.game_over:
			await process_frame
		captures.append({"fps_cap": cap, "seed": scene._active_seed, "frames": scene._render_diagnostic_frames.duplicate(true)})
		scene.free()
		await process_frame
	var output := FileAccess.open("E:/Utveckling/Gravity Run/.codex-v2-analysis/singleplayer-render-capture.json", FileAccess.WRITE)
	if output == null:
		push_error("Could not save rendering capture")
		quit(1)
		return
	output.store_string(JSON.stringify({"build_id": ProjectSettings.get_setting("application/config/version"), "captures": captures}))
	output.close()
	print("Actual singleplayer rendering captured at requested 60 and 144 FPS caps.")
	quit()
