extends Node
## Bounded GPU capture of actual main.tscn gameplay for three published Gen17 seeds.

const MainScene := preload("res://main.tscn")

const CASES := [
	{"seed": 100000057, "name": "tidal-pool", "capture_distance": 1120.0, "avoidance": "floor_pool"},
	{"seed": 100000019, "name": "haunted-chaser", "capture_distance": 2200.0, "avoidance": "ghost"},
]

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect := "portrait" if viewport_size.y > viewport_size.x else "landscape"
	var out_dir := ProjectSettings.globalize_path("res://.codex-gen17-review/actual-main")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for fixture in CASES:
		challenge.call("clear_challenge")
		var seed_value := int(fixture.seed)
		if not bool(challenge.call("start_singleplayer_seed_input", str(seed_value))):
			_fail("could not select actual Gen17 seed %d" % seed_value)
			continue
		var game := MainScene.instantiate() as Node
		add_child(game)
		await get_tree().process_frame
		var generator: Object = game.get("course_generator")
		generator.call("ensure_horizon", 7000.0, float(game.call("_run_speed")), 540.0)
		var planned_events: Array = generator.call("get_planned_events")
		var first_target: Dictionary = {}
		var capture_distance: float = float(fixture.capture_distance)
		for planned in planned_events:
			if str(planned.get("kind", "")) == "ghost" and int(planned.get("ghost_variant", 0)) == 1 and str(fixture.name) == "haunted-chaser":
				first_target = planned
				break
			if str(planned.get("kind", "")) == "lava_crack" and int(planned.get("lava_variant", 0)) == 1 and str(fixture.name) == "tidal-pool":
				first_target = planned
				break
		if not first_target.is_empty():
			capture_distance = float(first_target.get("course_distance", capture_distance)) + 350.0
			print("GEN17_ACTUAL_MAIN_TARGET seed=%d encounter=%s course_distance=%.1f event=%s" % [seed_value, str(fixture.name), capture_distance, str(first_target)])
		var reached := false
		for _frame in range(1200):
			await get_tree().physics_frame
			if not is_instance_valid(game):
				break
			_apply_safe_capture_route(game, str(fixture.avoidance))
			if float(game.get("course_distance")) >= capture_distance:
				reached = true
				break
		_check(reached, "actual main.tscn reached requested %s capture distance for seed %d" % [str(fixture.name), seed_value])
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("gen17-sp-%s-%s.png" % [str(fixture.name), aspect])
		var error := image.save_png(path)
		var hazard_count := 0
		for obstacle in game.get("obstacles"):
			if not is_instance_valid(obstacle):
				continue
			var target_match: bool = obstacle.is_in_group("lava_hazards") if str(fixture.name) == "tidal-pool" else obstacle.is_in_group("ghost_hazards")
			if not target_match:
				continue
			var event_value: Variant = obstacle.get("event")
			if event_value is Dictionary:
				var expected_variant := "lava_variant" if str(fixture.name) == "tidal-pool" else "ghost_variant"
				if int(event_value.get(expected_variant, 0)) == 1:
					hazard_count += 1
		var hud_visible := game.get_node_or_null("HUDLayer/HUD") != null
		_check(error == OK and hazard_count > 0 and hud_visible and not bool(game.get("game_over")), "actual Gen17 gameplay view captured alive with HUD and selected live variant (%s)" % str(fixture.name))
		print("GEN17_ACTUAL_MAIN_CAPTURE seed=%d encounter=%s progress_px=%.1f image=%s size=%s hazards=%d hud_visible=%s game_over=%s" % [seed_value, str(fixture.name), float(game.get("course_distance")), path, str(image.get_size()), hazard_count, str(hud_visible), str(bool(game.get("game_over")))])
		game.queue_free()
		await get_tree().process_frame
	challenge.call("clear_challenge")
	print("GEN17_ACTUAL_MAIN_CAPTURE failures=%d viewport=%s" % [failures, str(viewport_size)])
	get_tree().quit(1 if failures > 0 else 0)

func _apply_safe_capture_route(game: Node, route_kind: String) -> void:
	if bool(game.get("game_over")):
		return
	var player: Node = game.get("player")
	if not is_instance_valid(player) or int(player.call("get_gravity_direction")) == -1:
		return
	var trigger_variant := "ghost_variant" if route_kind == "ghost" else "rock_variant" if route_kind == "icicle" else "lava_variant"
	for obstacle in game.get("obstacles"):
		if not is_instance_valid(obstacle):
			continue
		var matches: bool = obstacle.is_in_group("ghost_hazards") if route_kind == "ghost" else obstacle.is_in_group("falling_rocks") if route_kind == "icicle" else obstacle.is_in_group("lava_hazards")
		if not matches:
			continue
		var event: Dictionary = obstacle.get("event")
		if route_kind == "ghost" and int(event.get(trigger_variant, 0)) != 1:
			continue
		if route_kind == "icicle" and int(event.get(trigger_variant, 0)) != 1:
			continue
		var activation_value: Variant = obstacle.get("activation_tick")
		if not activation_value is int:
			continue
		var activation: int = activation_value
		if activation < 0:
			continue
		var wait_ticks := int(event.get("warning_ticks", 54)) + 12 if route_kind != "floor_pool" else 0
		if int(game.get("_singleplayer_simulation_tick")) >= activation + wait_ticks:
			player.call("_try_flip", -1, "capture_route")
		return
	if route_kind == "floor_pool" and float(game.get("course_distance")) >= 900.0:
		player.call("_try_flip", -1, "capture_route")

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)

func _fail(message: String) -> void:
	failures += 1
	push_error("FAIL: " + message)
