extends Node
## Screenshots of a campaign stage every few hundred ticks, to look at the
## meadow's pixel art in play. Needs a real renderer:
##   godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/pixel_tiles/meadow_capture.tscn -- out_dir 1-3
## The runner cannot die (its hits are ignored), so the whole stage is seen.

const MainScene := preload("res://main.tscn")
const TICK := 1.0 / 60.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://meadow_captures"
	var level_id := StringName(args[1] if args.size() > 1 else "1-3")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Campaign.persist = false
	Campaign.start_level(CampaignCatalog.get_level(level_id))
	var game := MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.set_physics_process(false)
	var effects: Object = game.get("_run_effects")
	for shot in range(12):
		for _i in range(120):
			# Keep the runner alive: an endless bubble.
			effects.set("_invulnerable_left", 10)
			game.call("_physics_process", TICK)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("%s_%02d.png" % [String(level_id), shot])
		get_viewport().get_texture().get_image().save_png(path)
		print("CAPTURED ", path)
	get_tree().quit(0)
