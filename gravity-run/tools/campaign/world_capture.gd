extends Node
## Screenshots of one campaign world: its map and each stage a few seconds in
## (and further along with a simple dodge bot). Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/campaign/world_capture.tscn -- out_dir world_id [ticks]
## Progress is faked in memory only (Campaign.persist = false).

const MainScene := preload("res://main.tscn")
const WorldMapScript := preload("res://ui/campaign/world_map.gd")
const TICK := 1.0 / 60.0

var out_dir := "user://world_captures"
var world_id := &"cave"
var ticks := 420

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		world_id = StringName(args[1])
	if args.size() > 2:
		ticks = int(args[2])
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	print("CAPTURED ", out_dir.path_join(name + ".png"))

func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _run() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	# Open every world before this one.
	for world in CampaignCatalog.worlds():
		if world.world_id == world_id:
			break
		for level in world.levels:
			Campaign.start_level(level)
			Campaign.record_completion(10, 0b111)
	Campaign.clear_active()
	var target := CampaignCatalog.get_world(world_id)
	if not target.levels.is_empty():
		Campaign.start_level(target.levels[0])
		Campaign.clear_active()
	var map := WorldMapScript.new() as Control
	add_child(map)
	await _frames(4)
	map.call("_change_world", CampaignCatalog.worlds().find(target) - int(map.get("_world_index")))
	await _frames(20)
	await _save("%s_map" % world_id)
	map.queue_free()
	await _frames(2)
	for level in target.levels:
		Campaign.start_level(level)
		var game := MainScene.instantiate() as Node
		add_child(game)
		await _frames(2)
		game.set_physics_process(false)
		await _step(game, 90)
		await _save("%s_%s_a" % [world_id, level.level_id])
		await _step(game, ticks)
		await _save("%s_%s_b" % [world_id, level.level_id])
		game.queue_free()
		await _frames(2)
		Campaign.clear_active()
	Campaign.reset_progress()
	get_tree().quit(0)

func _step(game: Node, count: int) -> void:
	for i in range(count):
		if bool(game.get("game_over")):
			break
		game.call("_physics_process", TICK)
		if i % 4 == 0:
			await get_tree().process_frame
