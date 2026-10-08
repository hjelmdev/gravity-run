extends Node
## Screenshots of a campaign stage's scripted features. The runner is carried to
## just before a feature, then a bot that follows the feature's safe side runs
## through it while frames are saved. Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/campaign/feature_capture.tscn -- out_dir stage_id [feature_index] [tick,tick,...]
## With feature_index -1 the runner is carried to a course distance given as a
## fifth argument and generated encounters stay on (it just runs on the floor).
## Otherwise generated encounters are switched off so the bot only has the feature to deal with.
## Default ticks: 60,100,130,160,190,230,280. Progress is faked in memory only.

const MainScene := preload("res://main.tscn")
const TICK := 1.0 / 60.0

var out_dir := "user://feature_captures"
var stage_id := &"2-4"
var feature_index := 0
var frames: Array[int] = [60, 100, 130, 160, 190, 230, 280]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		stage_id = StringName(args[1])
	if args.size() > 2:
		feature_index = int(args[2])
	if args.size() > 3:
		frames.clear()
		for part in args[3].split(","):
			frames.append(int(part))
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _run() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	var level := CampaignCatalog.get_level(stage_id)
	var feature: Dictionary = level.features[feature_index] if feature_index >= 0 else {"kind": "none", "at": 0.0}
	Campaign.start_level(level)
	var game := MainScene.instantiate() as Node
	add_child(game)
	await _frames(2)
	game.set_physics_process(false)
	var player: Node = game.get_node("Player")
	var span := CampaignFeatures.span_of(feature)
	# Far enough ahead for the feature to wake up the way it does in a real run.
	var start := maxf(span.x - 1000.0, 0.0)
	if feature_index >= 0:
		# Only the feature itself is on the track, so the bot cannot die elsewhere.
		game.get("_campaign_run").set("generated_events_enabled", false)
	else:
		start = float(OS.get_cmdline_user_args()[4])
	if str(feature.kind) == "darkness":
		start = span.x + 200.0
	player.call("advance_world_x", start)
	var last := 0
	for tick in range(1, (frames.max() if not frames.is_empty() else 1) + 1):
		_bot(game, player, feature)
		game.call("_physics_process", TICK)
		if tick % 2 == 0:
			game.call("_process", TICK)
		if tick in frames:
			await _frames(2)
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join("%s_%s_%d_t%03d.png" % [stage_id, feature.kind, feature_index, tick])
			get_viewport().get_texture().get_image().save_png(path)
			print("CAPTURED ", path, " course=", int(game.get("course_distance")), " dead=", bool(game.get("game_over")))
		last = tick
		if bool(game.get("game_over")):
			print("RUNNER DIED at tick ", last)
			break
	game.queue_free()
	await _frames(2)
	Campaign.reset_progress()
	get_tree().quit(0)

func _bot(game: Node, player: Node, feature: Dictionary) -> void:
	var course := float(player.get("world_x")) - 180.0
	var required := 0
	for other in (game.get("_campaign_level") as CampaignLevel).features:
		required = CampaignFeatures.required_side_at(other, course)
		if required != 0:
			break
	var target := required if required != 0 else 1
	if target != int(player.call("get_gravity_direction")) and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", target)
