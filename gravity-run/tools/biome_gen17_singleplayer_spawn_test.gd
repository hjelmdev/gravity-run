extends Node
## Actual main-scene adapter coverage for generated Gen17 variants.

const MainScene := preload("res://main.tscn")
const Generator := preload("res://systems/course_generator.gd")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge := get_tree().root.get_node("ChallengeService")
	var cases := [
		{"seed": 100000019, "profile": "haunted_chaser", "group": "ghost_hazards", "variant_key": "ghost_variant"},
		{"seed": 100000002, "profile": "cave_icicle", "group": "falling_rocks", "variant_key": "rock_variant"},
		{"seed": 100000057, "profile": "lava_tidal_pool", "group": "lava_hazards", "variant_key": "lava_variant"},
	]
	for case in cases:
		challenge.call("clear_challenge")
		_check(bool(challenge.call("start_singleplayer_seed_input", str(case.seed))), "numeric seed %d selects the active Gen17 singleplayer path" % int(case.seed))
		var game := MainScene.instantiate() as Node
		get_tree().root.add_child(game)
		await get_tree().process_frame
		game.set_physics_process(false)
		_check(int(game.get("_active_seed")) == int(case.seed) and int(game.get("_active_seed_version")) == Generator.GENERATOR_VERSION_17, "actual main scene starts seed %d with Gen17" % int(case.seed))
		var generator: Variant = game.get("course_generator")
		generator.call("ensure_horizon", 45000.0, 500.0)
		var source_event: Dictionary = {}
		for event in generator.call("get_planned_events"):
			if str(event.get("id", "")) == str(case.profile):
				source_event = event
				break
		_check(not source_event.is_empty(), "seed %d generates profile %s in actual SP course generator" % [int(case.seed), str(case.profile)])
		if not source_event.is_empty():
			game.call("_spawn_course_event", source_event)
			var found: Node2D
			for candidate in game.get("obstacles"):
				if is_instance_valid(candidate) and candidate.is_in_group(str(case.group)):
					found = candidate
					break
			if str(case.group) == "lava_hazards":
				for candidate in game.get("obstacles"):
					if is_instance_valid(candidate) and candidate.is_in_group("lava_hazards") and int(candidate.get("event").get("lava_variant", 0)) == 1:
						found = candidate
						break
			_check(is_instance_valid(found), "generated %s reaches its production main.gd spawn path" % str(case.profile))
			if is_instance_valid(found):
				var resolved: Dictionary = found.get("event")
				_check(int(resolved.get(str(case.variant_key), 0)) == 1, "SP production adapter preserves %s variant payload" % str(case.profile))
				if str(case.profile) == "haunted_chaser":
					_check(is_equal_approx(float(found.global_position.x), 180.0 + float(source_event.get("course_distance", 0.0))), "SP chaser uses canonical event coordinate")
				elif str(case.profile) == "cave_icicle":
					_check(bool(resolved.get("from_ceiling", false)) and resolved.has("floor_supported"), "SP icicle resolves shared roof/floor support before scene configuration")
				else:
					_check(int(resolved.get("pool_period_ticks", 0)) == 180 and int(found.get("simulation_tick")) == int(game.get("_singleplayer_simulation_tick")), "SP pool starts on canonical simulation tick and phase period")
		game.queue_free()
		await get_tree().process_frame
	if failures == 0:
		print("BIOME_GEN17_SINGLEPLAYER_SPAWN_TEST passed: actual main scene generated chaser/icicle/tidal-pool adapters.")
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
