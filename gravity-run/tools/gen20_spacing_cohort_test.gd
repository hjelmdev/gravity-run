extends SceneTree
## Matched bounded spatial comparison. Counts accepted resolved event centers and
## source candidates; it does not estimate perceived reaction time.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const VERSIONS := [19, 20]
const FIRST_SEED := 100000001
const SEED_COUNT := 20
const COURSE_LENGTH := 45000
const SAMPLE_STEP := 100.0
const NARROW_SPAN := 300.0
const HAZARDS := ["spikes", "block", "barrels", "rock", "ghost", "saw", "lava_crack", "volcano"]
var gen19_narrow_intervals_by_seed: Dictionary = {}
var gen20_narrow_intervals_by_seed: Dictionary = {}
var hazard_positions_by_version_and_seed: Dictionary = {19: {}, 20: {}}
var max_gap_by_version_and_seed: Dictionary = {19: {}, 20: {}}
var narrow_gap_by_version_and_seed: Dictionary = {19: {}, 20: {}}

func _initialize() -> void:
	var totals := {19: _empty_totals(), 20: _empty_totals()}
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
			if version == 19:
				gen19_narrow_intervals_by_seed[seed_value] = narrow_intervals.duplicate()
			elif version == 20:
				gen20_narrow_intervals_by_seed[seed_value] = narrow_intervals.duplicate()
			var hazard_positions: Array[float] = []
			var narrow_positions: Array[float] = []
			var matched_gen19_narrow_positions: Array[float] = []
			var matched_gen19_narrow_supported_positions: Array[float] = []
			var accepted_hazards := 0
			var accepted_pursuits := 0
			var barrels := 0
			var spiked_barrels := 0
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
					if bool(event.get("spiked", false)):
						spiked_barrels += int(event.get("count", 1))
				if kind == "ghost" and int(event.get("ghost_variant", 0)) == 3:
					accepted_pursuits += 1
				var floor_sample: Dictionary = surface.surface_at(x, false)
				var ceiling_sample: Dictionary = surface.surface_at(x, true)
				if bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false)) and float(floor_sample.y) - float(ceiling_sample.y) <= NARROW_SPAN:
					narrow_positions.append(x)
					narrow_by_biome[biome] = int(narrow_by_biome.get(biome, 0)) + 1
				if _inside_intervals(x, gen19_narrow_intervals_by_seed.get(seed_value, [])):
					matched_gen19_narrow_positions.append(x)
					if bool(floor_sample.get("supported", false)) and bool(ceiling_sample.get("supported", false)) and float(floor_sample.y) - float(ceiling_sample.y) <= NARROW_SPAN:
						matched_gen19_narrow_supported_positions.append(x)
			hazard_positions.sort()
			narrow_positions.sort()
			hazard_positions_by_version_and_seed[version][seed_value] = hazard_positions.duplicate()
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
			row.matched_gen19_narrow_events += matched_gen19_narrow_positions.size()
			row.matched_gen19_narrow_supported_events += matched_gen19_narrow_supported_positions.size()
			row.pursuit_candidates += source_pursuits
			row.accepted_pursuits += accepted_pursuits
			row.rejected_pursuits += maxi(source_pursuits - accepted_pursuits, 0)
			row.barrels += barrels
			row.spiked_barrels += spiked_barrels
			row.pursuit_fallbacks += pursuit_fallbacks
			for biome in hazards_by_biome:
				row.hazards_by_biome[biome] = int(row.hazards_by_biome.get(biome, 0)) + int(hazards_by_biome[biome])
			for biome in narrow_by_biome:
				row.narrow_by_biome[biome] = int(row.narrow_by_biome.get(biome, 0)) + int(narrow_by_biome[biome])
			var max_gap := _max_gap(hazard_positions, float(manifest.start_x), float(manifest.finish_x))
			max_gap_by_version_and_seed[version][seed_value] = max_gap
			if max_gap > float(row.max_gap):
				row.max_gap = max_gap
				row.max_gap_seed = seed_value
			var narrow_gap := _max_gap_in_intervals(narrow_positions, narrow_intervals)
			narrow_gap_by_version_and_seed[version][seed_value] = narrow_gap
			if narrow_gap > float(row.max_narrow_gap):
				row.max_narrow_gap = narrow_gap
				row.max_narrow_gap_seed = seed_value
	var common_narrow_km := 0.0
	var common_gen19_centers := 0
	var common_gen20_centers := 0
	for offset in range(SEED_COUNT):
		var seed_value := FIRST_SEED + offset
		var shared_intervals := _intersect_intervals(gen19_narrow_intervals_by_seed.get(seed_value, []), gen20_narrow_intervals_by_seed.get(seed_value, []))
		for interval in shared_intervals:
			common_narrow_km += (interval.y - interval.x) / 1000.0
			for x in hazard_positions_by_version_and_seed[19].get(seed_value, []):
				if x >= interval.x and x <= interval.y:
					common_gen19_centers += 1
			for x in hazard_positions_by_version_and_seed[20].get(seed_value, []):
				if x >= interval.x and x <= interval.y:
					common_gen20_centers += 1
	print("GEN20_COMMON_SUPPORTED_NARROW gen19_km=%.2f gen19_centers=%d gen19_per1000=%.4f gen20_centers=%d gen20_per1000=%.4f" % [common_narrow_km, common_gen19_centers, float(common_gen19_centers) / common_narrow_km if common_narrow_km > 0.0 else 0.0, common_gen20_centers, float(common_gen20_centers) / common_narrow_km if common_narrow_km > 0.0 else 0.0])
	var overall_improved := 0
	var overall_sum_delta := 0.0
	var narrow_improved := 0
	var narrow_sum_delta := 0.0
	for offset in range(SEED_COUNT):
		var seed_value := FIRST_SEED + offset
		var overall_delta := float(max_gap_by_version_and_seed[19].get(seed_value, 0.0)) - float(max_gap_by_version_and_seed[20].get(seed_value, 0.0))
		var narrow_delta := float(narrow_gap_by_version_and_seed[19].get(seed_value, 0.0)) - float(narrow_gap_by_version_and_seed[20].get(seed_value, 0.0))
		overall_sum_delta += overall_delta
		narrow_sum_delta += narrow_delta
		if overall_delta > 0.0:
			overall_improved += 1
		if narrow_delta > 0.0:
			narrow_improved += 1
	print("GEN20_PAIRED_GAPS seeds=%d overall_improved=%d overall_mean_reduction_px=%.1f narrow_improved=%d narrow_mean_reduction_px=%.1f" % [SEED_COUNT, overall_improved, overall_sum_delta / float(SEED_COUNT), narrow_improved, narrow_sum_delta / float(SEED_COUNT)])
	for version in VERSIONS:
		var row: Dictionary = totals[version]
		var course_km := float(SEED_COUNT * COURSE_LENGTH) / 1000.0
		print("GEN20_MATCHED_NARROW_COHORT gen=%d gen19_narrow_support_km=%.2f events_inside_baseline_narrow=%d still_narrow_supported=%d" % [version, totals[19].narrow_km, row.matched_gen19_narrow_events, row.matched_gen19_narrow_supported_events])
		print("GEN19_SPACING_COHORT gen=%d seeds=%d course_km=%.1f source_events=%d accepted_hazards=%d hazards_per_1000px=%.4f narrow_supported_km=%.2f narrow_center_events=%d per_narrow_1000px=%.4f narrow_max_center_gap_px=%.1f narrow_gap_seed=%d coins=%d coins_per_1000px=%.4f pursuit_candidates=%d accepted_pursuits=%d filtered_pursuits=%d pursuit_fallbacks=%d barrels=%d spiked_barrels=%d max_center_gap_px=%.1f max_gap_seed=%d failures=%d" % [version, SEED_COUNT, course_km, row.source_events, row.accepted_hazards, float(row.accepted_hazards) / course_km, row.narrow_km, row.narrow_events, float(row.narrow_events) / row.narrow_km if row.narrow_km > 0.0 else 0.0, row.max_narrow_gap, row.max_narrow_gap_seed, row.coins, float(row.coins) / course_km, row.pursuit_candidates, row.accepted_pursuits, row.rejected_pursuits, row.pursuit_fallbacks, row.barrels, row.spiked_barrels, row.max_gap, row.max_gap_seed, failures])
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
	return {"source_events": 0, "accepted_hazards": 0, "coins": 0, "narrow_km": 0.0, "narrow_events": 0, "matched_gen19_narrow_events": 0, "matched_gen19_narrow_supported_events": 0, "pursuit_candidates": 0, "accepted_pursuits": 0, "rejected_pursuits": 0, "pursuit_fallbacks": 0, "barrels": 0, "spiked_barrels": 0, "max_gap": 0.0, "max_gap_seed": 0, "max_narrow_gap": 0.0, "max_narrow_gap_seed": 0, "candidate_attempts": 0, "route_rejections": 0, "biome_rejections": 0, "barrel_approach_rejections": 0, "pursuit_profile_fallbacks": 0, "accepted_events": 0, "fallback_events": 0, "source_kinds": {}, "accepted_kinds": {}, "hazards_by_biome": {}, "narrow_by_biome": {}}

func _inside_intervals(x: float, intervals: Array) -> bool:
	for interval in intervals:
		if interval is Vector2 and x >= interval.x and x <= interval.y:
			return true
	return false

func _intersect_intervals(left: Array, right: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for a in left:
		for b in right:
			if not (a is Vector2 and b is Vector2):
				continue
			var start := maxf(a.x, b.x)
			var finish := minf(a.y, b.y)
			if finish > start:
				result.append(Vector2(start, finish))
	return result

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
