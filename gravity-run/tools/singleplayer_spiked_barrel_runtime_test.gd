extends Node

const MainScene := preload("res://main.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const ManifestBuilder := preload("res://systems/course_manifest_builder.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := MainScene.instantiate() as Node2D
	get_tree().root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await get_tree().process_frame
	var obstacles: Array = game.get("obstacles")
	obstacles.clear()
	var generated_manifest: Resource = ManifestBuilder.new().build(100000003, 100000, CourseGenerator.GENERATOR_VERSION_13).get("manifest")
	var generated_spiked_event: Dictionary = {}
	if generated_manifest != null:
		for event in generated_manifest.events:
			if str(event.get("kind", "")) == "barrels" and bool(event.get("spiked", false)):
				generated_spiked_event = event.duplicate(true)
				generated_spiked_event["course_distance"] = float(event.get("x", 0.0)) - float(generated_manifest.start_x)
				generated_spiked_event["id"] = str(event.get("event_id", ""))
				break
	_check(not generated_spiked_event.is_empty(), "Gen13 challenge seed produces a generated spiked-barrel event for the actual SP spawn path")
	if not generated_spiked_event.is_empty():
		game.call("_spawn_course_event", generated_spiked_event)
		var generated_spawn_is_spiked := false
		for obstacle in obstacles:
			if is_instance_valid(obstacle) and obstacle.has_method("set_spiked"):
				generated_spawn_is_spiked = generated_spawn_is_spiked or bool(obstacle.get("is_spiked"))
		_check(generated_spawn_is_spiked, "actual main._spawn_course_event forwards generated spiked metadata into the existing barrel scene")
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()
	var slopes: Array = game.get("slopes")
	slopes.clear()
	var spike_barrel := BarrelScene.instantiate() as Node2D
	spike_barrel.call("configure", Vector2(54.0, 54.0), false)
	spike_barrel.call("set_spiked", true)
	spike_barrel.position = Vector2(1000.0, 460.0)
	var block := BlockScene.instantiate() as Node2D
	block.call("configure", Vector2(48.0, 72.0), false)
	block.position = Vector2(1000.0, 460.0)
	game.add_child(spike_barrel)
	game.add_child(block)
	obstacles.append(spike_barrel)
	obstacles.append(block)
	game.call("_resolve_obstacle_interactions")
	_check(bool(block.call("is_destroying_now")), "singleplayer spiked barrel destroys the explicitly breakable block")
	_check(not bool(spike_barrel.call("is_destroying_now")), "singleplayer spiked barrel keeps rolling after the block")
	_check(bool(spike_barrel.get("is_spiked")), "SP uses the same existing barrel scene's variant data")
	var ordinary_barrel := BarrelScene.instantiate() as Node2D
	ordinary_barrel.call("configure", Vector2(54.0, 54.0), false)
	ordinary_barrel.position = Vector2(2000.0, 460.0)
	var ordinary_block := BlockScene.instantiate() as Node2D
	ordinary_block.call("configure", Vector2(48.0, 72.0), false)
	ordinary_block.position = Vector2(2000.0, 460.0)
	game.add_child(ordinary_barrel)
	game.add_child(ordinary_block)
	obstacles = game.get("obstacles")
	obstacles.clear()
	obstacles.append(ordinary_barrel)
	obstacles.append(ordinary_block)
	game.call("_resolve_obstacle_interactions")
	_check(bool(ordinary_block.call("is_destroying_now")) and bool(ordinary_barrel.call("is_destroying_now")), "ordinary barrel retains its previous destroy-with-block behavior")
	print("SINGLEPLAYER_SPIKED_BARREL_RUNTIME_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
