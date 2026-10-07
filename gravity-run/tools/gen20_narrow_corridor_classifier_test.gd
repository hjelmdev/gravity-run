extends SceneTree
## Check the Gen20 narrow-corridor selector against the canonical resolved
## surface index. Samples are only a proxy for classifier parity, not safety.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const START_X := 180.0
const COURSE_LENGTH := 45000.0
const STEP := 100.0
const SEEDS: Array[int] = [100000006, 100000014, 100000019, 100000030]

func _initialize() -> void:
	var builder := Builder.new()
	var failures := 0
	for seed_value in SEEDS:
		var ruleset: Resource = builder.call("_make_multiplayer_ruleset", 20)
		var definition: Resource = RunDefinition.new()
		definition.set("scenario_id", &"endless")
		definition.set("seed_value", seed_value)
		definition.set("generator_version", 20)
		definition.set("ruleset", ruleset)
		var generator := Generator.new() as CourseGenerator
		if not generator.configure_run_definition(definition):
			push_error("Gen20 source generator failed seed=%d" % seed_value)
			failures += 1
			continue
		generator.ensure_horizon(START_X + COURSE_LENGTH + 5000.0, 500.0, 540.0, Generator.EVENT_SPAWN_LEAD_DISTANCE)
		var biome_offset := BiomeRenderer.start_biome_offset_for_seed(seed_value, 20)
		var resolved: Array[Dictionary] = builder.call("resolve_runtime_events", generator.get_planned_events(), ceili(COURSE_LENGTH + 5000.0), 20, biome_offset)
		var surface := SurfaceIndex.new()
		surface.configure(resolved, 460.0, 80.0)
		var mismatches := 0
		var first_mismatch := -1.0
		for course_x in range(0, int(COURSE_LENGTH), int(STEP)):
			var world_x := START_X + float(course_x)
			var floor_sample: Dictionary = surface.surface_at(world_x, false)
			var ceiling_sample: Dictionary = surface.surface_at(world_x, true)
			var canonical_narrow := bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false)) and float(floor_sample.get("y", 460.0)) - float(ceiling_sample.get("y", 80.0)) <= Generator.GEN20_NARROW_SPAN_MAX
			var classified := bool(generator.call("_is_narrow_supported_corridor", float(course_x)))
			if canonical_narrow != classified:
				mismatches += 1
				if first_mismatch < 0.0:
					first_mismatch = float(course_x)
		if mismatches > 0:
			failures += 1
			push_error("narrow classifier differs from CourseSurfaceIndex seed=%d samples=%d first_course_x=%.1f" % [seed_value, mismatches, first_mismatch])
		print("GEN20_NARROW_CLASSIFIER seed=%d mismatches=%d samples=%d" % [seed_value, mismatches, int(COURSE_LENGTH / STEP)])
	print("GEN20_NARROW_CLASSIFIER_TEST failures=%d seeds=%d" % [failures, SEEDS.size()])
	quit(1 if failures > 0 else 0)
