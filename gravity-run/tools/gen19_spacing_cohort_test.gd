extends SceneTree
## Matched bounded spatial comparison. Counts accepted resolved event centers and
## source candidates; it does not estimate perceived reaction time.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const VERSIONS := [18, 19]
const FIRST_SEED := 100000001
const SEED_COUNT := 20
const COURSE_LENGTH := 45000
const SAMPLE_STEP := 100.0
const NARROW_SPAN := 300.0
const HAZARDS := ["spikes", "block", "barrels", "rock", "ghost", "saw", "lava_crack", "volcano"]

func _initialize() -> void:
	var totals := {18: _empty_totals(), 19: _empty_totals()}
	var failures := 0
	for offset in range(SEED_COUNT):
		var seed_value := FIRST_SEED + offset
		for version in VERSIONS:
			var built: Dictionary = Builder.new().build(seed_value, COURSE_LENGTH, version)
			var manifest: Variant = built.get("manifest")
			if manifest == null:
				failures += 1
				push_error("cohort manifest failed seed=%d gen=%d: %s" % [seed_value, version, str(built.get("error", ""))])
				continue
			var source_result := _source_events(seed_value, version)
			var source: Array = source_result.get("events", [])
			if source.is_empty():
				failures += 1
				push_error("source event generation failed seed=%d gen=%d" % [seed_value, version])
				continue
			var surface := SurfaceIndex.new()
			surface.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
			var narrow_intervals: Array[Vector2] = []
			var active_narrow := false
			var narrow_start := float(manifest.start_x)
			var narrow_length := 0.0
			for sample_index in range(ceili(float(COURSE_LENGTH) / SAMPLE_STEP)):
				var left := float(manifest.start_x) + float(sample_index) * SAMPLE_STEP
				var sample_x := left + SAMPLE_STEP * 0.5
				var floor_sample: Dictionary = surface.surface_at(sample_x, false)
				var ceiling_sample: Dictionary = surface.surface_at(sample_x, true)
				var narrow := bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false)) and float(floor_sample.y) - float(ceiling_sample.y) <= NARROW_SPAN
				if narrow:
					narrow_length += SAMPLE_STEP
					if not active_narrow:
						active_narrow = true
						narrow_start = left
				elif active_narrow:
					narrow_intervals.append(Vector2(narrow_start, left))
					active_narrow = false
			if active_narrow:
				narrow_intervals.append(Vector2(narrow_start, float(manifest.finish_x)))
			var hazard_positions: Array[float] = []
			var narrow_positions: Array[float] = []
			var accepted_hazards := 0
			var accepted_pursuits := 0
			var barrels := 0
			var hazards_by_biome: Dictionary = {}
			var narrow_by_biome: Dictionary = {}
			var pursuit_fallbacks := 0
			for event in manifest.events:
				var kind := str(event.get("kind", ""))
				if kind not in HAZARDS:
					continue
				accepted_hazards += 1
				if bool(event.get("gen19_supported_fallback", false)):
					pursuit_fallbacks += 1
				var x := float(event.get("x", 0.0))
				var biome := BiomeRenderer.biome_id_for_seed(seed_value, x - float(manifest.start_x), version)
				hazards_by_biome[biome] = int(hazards_by_biome.get(biome, 0)) + 1
				hazard_positions.append(x)
				if kind == "barrels":
					barrels += int(event.get("count", 1))
				if kind == "ghost" and int(event.get("ghost_variant", 0)) == 3:
					accepted_pursuits += 1
				var floor_sample: Dictionary = surface.surface_at(x, false)
				var ceiling_sample: Dictionary = surface.surface_at(x, true)
				if bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false)) and float(floor_sample.y) - float(ceiling_sample.y) <= NARROW_SPAN:
					narrow_positions.append(x)
					narrow_by_biome[biome] = int(narrow_by_biome.get(biome, 0)) + 1
			hazard_positions.sort()
			narrow_positions.sort()
			var source_pursuits := 0
			for event in source:
				if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3:
					source_pursuits += 1
			var row: Dictionary = totals[version]
			var source_stats: Dictionary = source_result.get("stats", {})
			for key in ["candidate_attempts", "route_rejections", "biome_rejections", "barrel_approach_rejections", "pursuit_profile_fallbacks", "accepted_events", "fallback_events"]:
				row[key] += int(source_stats.get(key, 0))
			for source_event in source:
				var source_kind := str(source_event.get("kind", ""))
				row.source_kinds[source_kind] = int(row.source_kinds.get(source_kind, 0)) + 1
			for resolved_event in manifest.events:
				var resolved_kind := str(resolved_event.get("kind", ""))
				row.accepted_kinds[resolved_kind] = int(row.accepted_kinds.get(resolved_kind, 0)) + 1
			row.source_events += source.size()
			row.accepted_hazards += accepted_hazards
			row.coins += manifest.collectibles.size()
			row.narrow_km += narrow_length / 1000.0
			row.narrow_events += narrow_positions.size()
			row.pursuit_candidates += source_pursuits
			row.accepted_pursuits += accepted_pursuits
			row.rejected_pursuits += maxi(source_pursuits - accepted_pursuits, 0)
			row.barrels += barrels
			row.pursuit_fallbacks += pursuit_fallbacks
			for biome in hazards_by_biome:
				row.hazards_by_biome[biome] = int(row.hazards_by_biome.get(biome, 0)) + int(hazards_by_biome[biome])
			for biome in narrow_by_biome:
				row.narrow_by_biome[biome] = int(row.narrow_by_biome.get(biome, 0)) + int(narrow_by_biome[biome])
			var max_gap := _max_gap(hazard_positions, float(manifest.start_x), float(manifest.finish_x))
			if max_gap > float(row.max_gap):
				row.max_gap = max_gap
				row.max_gap_seed = seed_value
			var narrow_gap := _max_gap_in_intervals(narrow_positions, narrow_intervals)
			if narrow_gap > float(row.max_narrow_gap):
				row.max_narrow_gap = narrow_gap
				row.max_narrow_gap_seed = seed_value
	for version in VERSIONS:
		var row: Dictionary = totals[version]
		var course_km := float(SEED_COUNT * COURSE_LENGTH) / 1000.0
		print("GEN19_SPACING_COHORT gen=%d seeds=%d course_km=%.1f source_events=%d accepted_hazards=%d hazards_per_1000px=%.4f narrow_supported_km=%.2f narrow_center_events=%d per_narrow_1000px=%.4f narrow_max_center_gap_px=%.1f narrow_gap_seed=%d coins=%d coins_per_1000px=%.4f pursuit_candidates=%d accepted_pursuits=%d filtered_pursuits=%d pursuit_fallbacks=%d barrels=%d max_center_gap_px=%.1f max_gap_seed=%d failures=%d" % [version, SEED_COUNT, course_km, row.source_events, row.accepted_hazards, float(row.accepted_hazards) / course_km, row.narrow_km, row.narrow_events, float(row.narrow_events) / row.narrow_km if row.narrow_km > 0.0 else 0.0, row.max_narrow_gap, row.max_narrow_gap_seed, row.coins, float(row.coins) / course_km, row.pursuit_candidates, row.accepted_pursuits, row.rejected_pursuits, row.pursuit_fallbacks, row.barrels, row.max_gap, row.max_gap_seed, failures])
		print("GEN19_GENERATOR_ATTRIBUTION gen=%d attempts=%d route_rejections=%d biome_rejections=%d barrel_approach_rejections=%d pursuit_profile_fallbacks=%d accepted=%d fallback=%d" % [version, row.candidate_attempts, row.route_rejections, row.biome_rejections, row.barrel_approach_rejections, row.pursuit_profile_fallbacks, row.accepted_events, row.fallback_events])
		print("GEN19_KIND_ATTRIBUTION gen=%d source=%s manifest=%s" % [version, JSON.stringify(row.source_kinds), JSON.stringify(row.accepted_kinds)])
		print("GEN19_BIOME_ATTRIBUTION gen=%d hazards=%s narrow_hazard_centers=%s" % [version, JSON.stringify(row.hazards_by_biome), JSON.stringify(row.narrow_by_biome)])
	print("GEN19_SPACING_COHORT classification=accepted_manifest_event_centers; narrow=100px samples with both supports and vertical span<=300px; max gaps are spatial proxies, not reaction time")
	quit(1 if failures > 0 else 0)

func _source_events(seed_value: int, version: int) -> Dictionary:
	var builder := Builder.new()
	var ruleset: Resource = builder.call("_make_multiplayer_ruleset", version)
	var definition: Resource = RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", version)
	definition.set("ruleset", ruleset)
	var generator: RefCounted = Generator.new()
	if not bool(generator.call("configure_run_definition", definition)):
		return {"events": [], "stats": {}}
	generator.call("ensure_horizon", float(COURSE_LENGTH), 500.0, 900.0, 820.0)
	return {"events": generator.call("get_planned_events"), "stats": generator.call("get_generation_stats")}

func _empty_totals() -> Dictionary:
	return {"source_events": 0, "accepted_hazards": 0, "coins": 0, "narrow_km": 0.0, "narrow_events": 0, "pursuit_candidates": 0, "accepted_pursuits": 0, "rejected_pursuits": 0, "pursuit_fallbacks": 0, "barrels": 0, "max_gap": 0.0, "max_gap_seed": 0, "max_narrow_gap": 0.0, "max_narrow_gap_seed": 0, "candidate_attempts": 0, "route_rejections": 0, "biome_rejections": 0, "barrel_approach_rejections": 0, "pursuit_profile_fallbacks": 0, "accepted_events": 0, "fallback_events": 0, "source_kinds": {}, "accepted_kinds": {}, "hazards_by_biome": {}, "narrow_by_biome": {}}

func _max_gap(positions: Array[float], start_x: float, finish_x: float) -> float:
	var maximum := 0.0
	var prior := start_x
	for x in positions:
		maximum = maxf(maximum, x - prior)
		prior = x
	return maxf(maximum, finish_x - prior)

func _max_gap_in_intervals(positions: Array[float], intervals: Array[Vector2]) -> float:
	var maximum := 0.0
	for interval in intervals:
		var prior := interval.x
		for x in positions:
			if x < interval.x or x > interval.y:
				continue
			maximum = maxf(maximum, x - prior)
			prior = x
		maximum = maxf(maximum, interval.y - prior)
	return maximum
