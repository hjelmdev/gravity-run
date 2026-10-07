extends Node
## Exercise generated Gen20 barrel metadata through the actual main-scene SP adapter.

const MainScene := preload("res://main.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Generator := preload("res://systems/course_generator.gd")
const PLAYER_X := 180.0
const BARREL_SPACING := 42.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed_value := 100000006
	var result: Dictionary = Builder.new().build(seed_value, 45000, 20)
	var manifest: Variant = result.get("manifest")
	_check(manifest != null, "Gen20 manifest builds for the actual SP spawn fixture")
	if manifest == null:
		_finish()
		return
	var source_event: Dictionary = {}
	for event in manifest.events:
		if str(event.get("kind", "")) == "barrels" and not bool(event.get("spiked", false)):
			source_event = event.duplicate(true)
			break
	_check(not source_event.is_empty(), "selected manifest contains an ordinary generated barrel")
	if source_event.is_empty():
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
	definition.set("generator_version", 20)
	definition.set("ruleset", Builder.new().call("_make_multiplayer_ruleset", 20))
	var generator: Variant = game.get("course_generator")
	_check(bool(generator.call("configure_run_definition", definition)), "actual SP generator accepts the same Gen20 run definition")
	var course_distance := float(source_event.x) - float(manifest.start_x)
	generator.call("ensure_horizon", course_distance + 1600.0, 500.0)
	var adapter_event := source_event.duplicate(true)
	adapter_event["course_distance"] = course_distance
	adapter_event["id"] = str(source_event.get("event_id", ""))
	game.set("_active_seed_version", 20)
	game.call("_spawn_course_event", adapter_event)
	var barrel_nodes: Array = []
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("barrels"):
			barrel_nodes.append(obstacle)
	var expected_count := int(source_event.get("count", 1))
	_check(barrel_nodes.size() == expected_count, "normal spawn horizon creates each generated chain member exactly once")
	for barrel in barrel_nodes:
		_check(not bool(barrel.get("is_spiked")), "ordinary generated metadata does not turn the SP scene into a spiked barrel")
	var chain_width := float(expected_count - 1) * BARREL_SPACING
	var multiplier := float(source_event.get("motion_speed_multiplier", 1.0))
	var spawn_lead := Generator.get_viewport_spawn_lead_distance(float(game.get("screen_width")), PLAYER_X, 440.0)
	var early_offset := maxf(spawn_lead - Generator.EVENT_SPAWN_LEAD_DISTANCE, 0.0) * (multiplier - 1.0)
	var first_expected_x := PLAYER_X + course_distance + early_offset - chain_width * 0.5
	if not barrel_nodes.is_empty():
		_check(is_equal_approx(float(barrel_nodes[0].position.x), first_expected_x), "SP adapter preserves the accepted Gen20 world placement and viewport spawn correction")
	print("GEN20_SINGLEPLAYER_BARREL_SPAWN seed=%d source_event=%s course_distance=%.1f expected=%d spawned=%d failures=%d" % [seed_value, str(source_event.get("event_id", "")), course_distance, expected_count, barrel_nodes.size(), failures.size()])
	game.queue_free()
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	print("GEN20_SINGLEPLAYER_BARREL_SPAWN_TEST failures=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
