extends SceneTree
const Builder := preload("res://systems/course_manifest_builder.gd")
const Results := preload("res://systems/race_results.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := root.get_node("MultiplayerV2Service")
	var built: Dictionary = Builder.new().build(1260459445, 45000, 4)
	var roster: Array = []
	var reports: Array = []
	for index in range(5):
		roster.append({"user_id": "visual-%d" % index, "player_slot": index + 1, "display_name": ["Ada", "Benjamin", "Cecilia", "David", "Elin med ett långt namn"][index], "skin_id": index % 4})
		reports.append({"owner_peer_id": index + 1, "state": "dead", "simulation_tick": 200 + index * 100, "world_x": 2000.0 + index * 2500, "reason": "spikes"})
	service.session = {"local_peer_id": 1, "round_id": "visual-round"}
	service.room_state = {"members": roster}
	service.current_manifest = built.manifest
	var view: Node2D = load("res://ui/multiplayer_v2/multiplayer_v2_match.tscn").instantiate()
	root.add_child(view)
	view.set_physics_process(false)
	view._on_results_received(Results.build(roster, reports, float(built.manifest.start_x), "all_terminal", true))
	for size in [Vector2i(960, 540), Vector2i(640, 360)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "E:/Utveckling/Gravity Run/.codex-v2-analysis/results-%dx%d.png" % [size.x, size.y]
		var error := image.save_png(path)
		if error != OK:
			push_error("Could not save visual fixture: %s" % error_string(error))
			quit(1)
			return
	print("Result visual fixture captured desktop and small viewport.")
	view.free()
	quit()
