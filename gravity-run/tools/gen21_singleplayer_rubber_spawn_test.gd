extends Node
## Verifies Gen21 rubber metadata reaches the actual single-player main adapter.

const MainScene := preload("res://main.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const LedgeScene := preload("res://terrain/ledge.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Generator := preload("res://systems/course_generator.gd")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed_value := 100000007
	var manifest: Variant = Builder.new().build(seed_value, 45000, Generator.GENERATOR_VERSION_21).get("manifest")
	_check(manifest != null, "Gen21 seed builds for the actual single-player spawn test")
	if manifest == null:
		_finish()
		return
	var source: Dictionary = {}
	for event in manifest.events:
		if str(event.get("kind", "")) == "barrels" and int(event.get("barrel_variant", 0)) == 1:
			source = event.duplicate(true)
			break
	_check(not source.is_empty(), "selected generated run contains a rubber barrel")
	if source.is_empty():
		_finish()
		return
	var game := MainScene.instantiate() as Node
	get_tree().root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await get_tree().process_frame
	var definition: Resource = RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", Generator.GENERATOR_VERSION_21)
	definition.set("ruleset", Builder.new().call("_make_multiplayer_ruleset", Generator.GENERATOR_VERSION_21))
	var generator: Variant = game.get("course_generator")
	_check(bool(generator.call("configure_run_definition", definition)), "actual SP generator accepts Gen21")
	var course_distance := float(source.x) - float(manifest.start_x)
	generator.call("ensure_horizon", course_distance + 1800.0, 500.0)
	var adapter_event := source.duplicate(true)
	adapter_event["course_distance"] = course_distance
	adapter_event["id"] = str(source.get("event_id", ""))
	game.set("_active_seed_version", Generator.GENERATOR_VERSION_21)
	game.call("_spawn_course_event", adapter_event)
	var rubber_nodes: Array = []
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("barrels") and bool(obstacle.get("is_rubber")):
			rubber_nodes.append(obstacle)
	var expected_x := 180.0 + course_distance + Generator.get_viewport_spawn_lead_distance(float(game.get("screen_width")), 180.0, 440.0) * (float(source.get("motion_speed_multiplier", 1.0)) - 1.0)
	_check(rubber_nodes.size() == 1, "single-player adapter creates exactly one rubber barrel")
	if not rubber_nodes.is_empty():
		var barrel: Node2D = rubber_nodes[0]
		_check(is_equal_approx(barrel.position.x, expected_x), "SP applies the canonical Gen21 barrel spawn lead")
		_check(is_equal_approx(float(barrel.get("rubber_target_x")), float(source.get("rubber_target_x", NAN))), "SP preserves the designated target block identity")
	_verify_non_target_block_contacts(game)
	_check(int(game.get("_active_seed_version")) == Generator.GENERATOR_VERSION_21, "adapter does not silently substitute another generator")
	print("GEN21_SINGLEPLAYER_RUBBER_SPAWN seed=%d source=%s target_x=%.1f expected_x=%.1f spawned=%d failures=%d" % [seed_value, str(source.get("event_id", "")), float(source.get("rubber_target_x", NAN)), expected_x, rubber_nodes.size(), failures.size()])
	game.queue_free()
	_finish()

func _verify_non_target_block_contacts(game: Node) -> void:
	var obstacles: Array = game.get("obstacles")
	var slopes: Array = game.get("slopes")
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()
	for slope in slopes:
		if is_instance_valid(slope):
			slope.queue_free()
	slopes.clear()
	var target_x := 1200.0
	var floor_y := 484.0
	var radius := 27.0
	# Hit an extra block before the designated pairing and overlap a step at the
	# same time. Gen21 rubber precedence is block-first in both SP and MP.
	var target_block := _add_test_block(game, target_x, floor_y)
	var extra_before := _add_test_block(game, 800.0, floor_y)
	var ledge := LedgeScene.instantiate() as Node2D
	ledge.call("configure_step", floor_y - 84.0, floor_y, false, false)
	ledge.position = Vector2(800.0, 0.0)
	game.add_child(ledge)
	slopes.append(ledge)
	var before_barrel := _add_test_rubber_barrel(game, 800.0 + 33.0, floor_y, target_x)
	game.call("_resolve_obstacle_interactions")
	_check(int(before_barrel.get("bounce_count")) == 1 and int(before_barrel.get("travel_direction")) == -1, "SP rubber barrel bounces from an active non-target block before its metadata target")
	_check(is_equal_approx(float(before_barrel.position.x), 800.0 + 24.0 + radius + 1.0), "SP simultaneous step/block hit chooses the same block contact face as MP")
	_check(not bool(extra_before.get("is_destroying")) and not bool(target_block.get("is_destroying")) and is_instance_valid(ledge), "SP non-target block, designated block, and overlapping step all remain intact")
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()
	for slope in slopes:
		if is_instance_valid(slope):
			slope.queue_free()
	slopes.clear()
	# Also verify a block after the target. The authored target is metadata, not a
	# collision whitelist in either direction along the barrel's route.
	var target_after := _add_test_block(game, target_x, floor_y)
	var extra_after := _add_test_block(game, 1600.0, floor_y)
	var after_barrel := _add_test_rubber_barrel(game, 1600.0 + 33.0, floor_y, target_x)
	game.call("_resolve_obstacle_interactions")
	_check(int(after_barrel.get("bounce_count")) == 1 and is_equal_approx(float(after_barrel.position.x), 1600.0 + 24.0 + radius + 1.0), "SP rubber barrel also bounces from an active non-target block after its metadata target")
	_check(not bool(target_after.get("is_destroying")) and not bool(extra_after.get("is_destroying")), "SP target and later non-target block remain active after bounce")

func _add_test_block(game: Node, x: float, floor_y: float) -> Node2D:
	var block := BlockScene.instantiate() as Node2D
	block.call("configure", Vector2(48.0, 72.0), false)
	block.position = Vector2(x, floor_y)
	game.add_child(block)
	(game.get("obstacles") as Array).append(block)
	return block

func _add_test_rubber_barrel(game: Node, x: float, floor_y: float, target_x: float) -> Node2D:
	var barrel := BarrelScene.instantiate() as Node2D
	barrel.call("configure", Vector2(54.0, 54.0), false)
	barrel.call("set_rubber_variant", true, target_x)
	barrel.position = Vector2(x, floor_y)
	game.add_child(barrel)
	(game.get("obstacles") as Array).append(barrel)
	return barrel

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	print("GEN21_SINGLEPLAYER_RUBBER_SPAWN_TEST failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
