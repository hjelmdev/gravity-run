extends SceneTree
## Compare main-style incremental Gen20 coin planning with the full MP manifest.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Planner := preload("res://systems/shared_coin_planner.gd")
const Biomes := preload("res://biomes/biome_renderer.gd")
const START_X := 180.0
const COURSE_LENGTH := 45000
const COIN_HAZARD_LOOKAHEAD := 4500.0
const SEEDS: Array[int] = [
	100000001, 100000003, 100000006, 100000014,
	100000019, 100000030, 100000042, 100000057,
	100000100, 100000107, 1580534762, 918273645,
]

func _initialize() -> void:
	var failures := 0
	var builder := Builder.new()
	for seed_value in SEEDS:
		var built: Dictionary = builder.build(seed_value, COURSE_LENGTH, 20)
		var manifest: Variant = built.get("manifest")
		if manifest == null:
			push_error("Gen20 MP manifest failed seed=%d: %s" % [seed_value, str(built.get("error", ""))])
			failures += 1
			continue
		var ruleset: Resource = builder.call("_make_multiplayer_ruleset", 20)
		var definition: Resource = RunDefinition.new()
		definition.set("scenario_id", &"endless")
		definition.set("seed_value", seed_value)
		definition.set("generator_version", 20)
		definition.set("ruleset", ruleset)
		var generator := Generator.new() as CourseGenerator
		if not generator.configure_run_definition(definition):
			push_error("Gen20 SP-style generator configure failed seed=%d" % seed_value)
			failures += 1
			continue
		var planner := Planner.new()
		planner.reset(seed_value, START_X, int(ruleset.get("coin_revision")), float(ruleset.get("coin_density")))
		var streamed: Array[Dictionary] = []
		var end_world_x := START_X + float(COURSE_LENGTH)
		var horizon := minf(2360.0, float(COURSE_LENGTH))
		generator.ensure_horizon(START_X + horizon + COIN_HAZARD_LOOKAHEAD + 200.0, 500.0, 540.0, Generator.EVENT_SPAWN_LEAD_DISTANCE)
		var initial_resolved: Array[Dictionary] = builder.call("resolve_runtime_events", generator.get_planned_events(), ceili(horizon + COIN_HAZARD_LOOKAHEAD), 20, Biomes.start_biome_offset_for_seed(seed_value, 20))
		streamed.append_array(planner.extend(minf(START_X + horizon, end_world_x), initial_resolved, 460.0, 80.0, 0))
		while horizon < float(COURSE_LENGTH):
			horizon = minf(horizon + 2000.0, float(COURSE_LENGTH))
			generator.ensure_horizon(START_X + horizon + COIN_HAZARD_LOOKAHEAD + 200.0, 500.0, 540.0, Generator.EVENT_SPAWN_LEAD_DISTANCE)
			var biome_offset := Biomes.start_biome_offset_for_seed(seed_value, 20)
			var resolved: Array[Dictionary] = builder.call("resolve_runtime_events", generator.get_planned_events(), ceili(horizon + COIN_HAZARD_LOOKAHEAD), 20, biome_offset)
			streamed.append_array(planner.extend(minf(START_X + horizon, end_world_x), resolved, 460.0, 80.0, 0))
		var expected: Array = manifest.collectibles
		if streamed != expected:
			var mismatch := 0
			while mismatch < mini(streamed.size(), expected.size()) and streamed[mismatch] == expected[mismatch]:
				mismatch += 1
			push_error("Gen20 coin prefix mismatch seed=%d index=%d stream=%d MP=%d actual=%s expected=%s" % [seed_value, mismatch, streamed.size(), expected.size(), str(streamed[mismatch]) if mismatch < streamed.size() else "EOF", str(expected[mismatch]) if mismatch < expected.size() else "EOF"])
			failures += 1
		print("GEN20_COIN_STREAM seed=%d coins_sp=%d coins_mp=%d equal=%s" % [seed_value, streamed.size(), expected.size(), str(streamed == expected)])
	print("GEN20_COIN_STREAM_PARITY failures=%d seeds=%d" % [failures, SEEDS.size()])
	quit(1 if failures > 0 else 0)
