extends Node
## Renders reference screenshots of the campaign (map, a stage, Rullaren and
## the result screen). Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/campaign/campaign_capture.tscn -- out_dir
## Progress is faked in memory only (Campaign.persist = false).

const MainScene := preload("res://main.tscn")
const WorldMapScript := preload("res://ui/campaign/world_map.gd")
const TICK := 1.0 / 60.0

var out_dir := "user://campaign_captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
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
	var meadow := CampaignCatalog.get_world(&"meadow")
	var masks := [0b111, 0b011, 0b001]
	for i in range(3):
		Campaign.start_level(meadow.levels[i])
		Campaign.record_completion(40 + i * 7, masks[i])
	Campaign.clear_active()
	PlayerProfile.selected_character_id = &"fox"
	var hub := (load("res://ui/game_hub.tscn") as PackedScene).instantiate()
	add_child(hub)
	await _frames(10)
	await _save("00_game_hub")
	hub.queue_free()
	await _frames(2)
	# World map.
	var map := WorldMapScript.new() as Control
	add_child(map)
	await _frames(20)
	await _save("01_world_map")
	map.call("_select", 2)
	await _frames(8)
	await _save("02_world_map_walking")
	map.call("_change_world", 1)
	await _frames(6)
	await _save("03_world_map_locked_world")
	map.queue_free()
	await _frames(2)

	# Stage 1-1 shortly after the start (intro callout, bar, flag far away).
	Campaign.start_level(meadow.levels[0])
	var game := MainScene.instantiate() as Node
	add_child(game)
	await _frames(2)
	game.set_physics_process(false)
	await _step(game, 90)
	await _save("04_stage_intro")
	await _step(game, 6000)
	await _frames(10)
	await _save("11_stage_failed")
	game.queue_free()
	await _frames(2)

	# A short stage that shows a star pickup, the finish line and the result.
	var level := CampaignLevel.new()
	level.level_id = &"1-1"
	level.world_id = &"meadow"
	level.title = "First Steps"
	level.seed_value = 4242
	level.ruleset = CampaignCatalog.make_ruleset(&"T-1", &"classic", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 3400.0
	level.presentation_biome = &"meadow"
	level.stars = PackedVector2Array([Vector2(1180.0, 426.0), Vector2(1900.0, 426.0), Vector2(2300.0, 426.0)])
	Campaign.start_level(level)
	game = MainScene.instantiate() as Node
	add_child(game)
	await _frames(2)
	game.set_physics_process(false)
	await _step(game, 70)
	await _save("05_stage_star_ahead")
	await _step(game, 250)
	await _save("06_finish_line")
	await _step(game, 200)
	await _frames(30)
	await _save("07_stage_clear")
	game.queue_free()
	await _frames(2)

	# Rullaren.
	Campaign.start_level(meadow.levels[6])
	game = MainScene.instantiate() as Node
	add_child(game)
	await _frames(2)
	game.set_physics_process(false)
	await _step(game, 120, true)
	await _save("08_boss_intro")
	await _step(game, 160, true)
	await _save("09_boss_barrels")
	await _step_until_plate(game)
	await _save("10_boss_plate_hit")
	game.queue_free()
	await _frames(2)
	Campaign.reset_progress()
	get_tree().quit(0)

func _step(game: Node, ticks: int, boss_bot: bool = false) -> void:
	for i in range(ticks):
		if bool(game.get("game_over")):
			break
		if boss_bot:
			_boss_bot(game)
		game.call("_physics_process", TICK)
		if i % 4 == 0:
			await get_tree().process_frame

func _step_until_plate(game: Node) -> void:
	var run: Node = game.get("_campaign_run")
	var boss: RullarenBoss = run.get("boss")
	for i in range(2000):
		_boss_bot(game)
		game.call("_physics_process", TICK)
		if boss.hp < RullarenBoss.MAX_HP:
			break
		if i % 4 == 0:
			await get_tree().process_frame
	await _step(game, 8, true)

func _boss_bot(game: Node) -> void:
	var run: Node = game.get("_campaign_run")
	if not is_instance_valid(run) or run.get("boss") == null:
		return
	var boss: RullarenBoss = run.get("boss")
	var player: Node = game.get_node("Player")
	var course := float(player.get("world_x")) - 180.0
	var target := 0
	var probe := course
	while probe <= course + 340.0:
		var side := boss.required_side_at(probe)
		if side != 0:
			target = side
			break
		probe += 20.0
	if target != 0 and target != int(player.call("get_gravity_direction")) and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", target)
