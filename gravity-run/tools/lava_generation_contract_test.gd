extends SceneTree

const BuilderScript := preload("res://systems/course_manifest_builder.gd")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const BiomeEncounterMix := preload("res://systems/biome_encounter_mix.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder := BuilderScript.new()
	var total_cracks := 0
	var total_volcanoes := 0
	var total_risk_rows := 0
	var total_coins := 0
	var total_legacy_coins := 0
	var rhythm_gap_sum := PackedFloat64Array([0.0, 0.0, 0.0])
	var rhythm_gap_count := PackedInt32Array([0, 0, 0])
	var gen13_hazard_gap_sum := 0.0
	var gen13_hazard_gap_count := 0
	var seeds: Array[int] = [100000003, 100000014, 100000042, 100000777, 100000918]
	for seed_value in seeds:
		var built: Dictionary = builder.build(seed_value, 45000, 14)
		_check(built.get("manifest") != null, "Gen14 manifest must build: %s" % str(built.get("error", "")))
		if built.get("manifest") == null:
			continue
		var manifest = built.manifest
		total_coins += manifest.collectibles.size()
		_check(int(manifest.generator_version) == 14 and int(manifest.manifest_version) == 7, "Gen14 must use manifest v7")
		var repeated: Dictionary = builder.build(seed_value, 45000, 14)
		_check(repeated.get("manifest") != null and repeated.manifest.manifest_hash == manifest.manifest_hash, "same Gen14 seed must preserve manifest hash")
		var support_index := SurfaceIndex.new()
		support_index.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
		for event in manifest.events:
			var distance := float(event.x) - float(manifest.start_x)
			if str(event.kind) in ["lava_crack", "volcano"]:
				_check(BiomeRenderer.biome_id_for_generator(distance, 14) == "lava", "lava gameplay events are restricted to lava biome")
			if str(event.kind) == "lava_crack":
				total_cracks += 1
				_check_safe_lane_support(support_index, event, not bool(event.get("from_ceiling", false)))
			if str(event.kind) == "volcano":
				total_volcanoes += 1
				_check_safe_lane_support(support_index, event, true)
		if seed_value == seeds[0]:
			var lava_events: Array[String] = []
			for event in manifest.events:
				if str(event.kind) in ["lava_crack", "volcano"]:
					lava_events.append("%s@%d" % [str(event.kind), roundi(float(event.x) - float(manifest.start_x))])
			print("seed=%d lava=%s" % [seed_value, ",".join(lava_events)])
		for coin in manifest.collectibles:
			if str(coin.get("formation", "")) == "risk":
				total_risk_rows += 1
			_check(not CoinPlanner._position_blocked(float(coin.world_x), float(coin.world_y), manifest.events), "planned coin must not overlap static event geometry")
		# Legacy v13 must never acquire v14 hazards or the lava cycle.
		var legacy: Dictionary = builder.build(seed_value, 45000, 13)
		_check(legacy.get("manifest") != null, "frozen Gen13 manifest remains buildable")
		if legacy.get("manifest") != null:
			total_legacy_coins += legacy.manifest.collectibles.size()
			for event in legacy.manifest.events:
				_check(str(event.kind) not in ["lava_crack", "volcano"], "Gen13 must not contain Gen14 lava hazards")
			_check(BiomeRenderer.biome_id_for_generator(15000.0, 13) != "lava", "Gen13 biome sequence must not gain lava")
		var gen13_generator := CourseGeneratorScript.new() as CourseGenerator
		gen13_generator.configure_ruleset(builder._make_multiplayer_ruleset(13), 13)
		gen13_generator.reset(seed_value)
		gen13_generator.ensure_horizon(45000.0, 500.0, 900.0, 820.0)
		var gen13_hazards: Array[Dictionary] = []
		for planned in gen13_generator.get_planned_events():
			if str(planned.get("kind", "")) not in ["step", "slope", "gap"]:
				gen13_hazards.append(planned)
		for index in range(gen13_hazards.size() - 1):
			gen13_hazard_gap_sum += float(gen13_hazards[index + 1].course_distance) - float(gen13_hazards[index].course_distance)
			gen13_hazard_gap_count += 1
		var rhythm_generator := CourseGeneratorScript.new() as CourseGenerator
		var rhythm_ruleset: Resource = builder._make_multiplayer_ruleset(14)
		_check(rhythm_generator.configure_ruleset(rhythm_ruleset, 14), "Gen14 rhythm generator uses the shared multiplayer ruleset")
		rhythm_generator.reset(seed_value)
		rhythm_generator.ensure_horizon(45000.0, 500.0, 900.0, 820.0)
		var rhythmic_encounters: Array[Dictionary] = []
		for planned in rhythm_generator.get_planned_events():
			if planned.has("rhythm_phase"):
				rhythmic_encounters.append(planned)
		for index in range(rhythmic_encounters.size() - 1):
			var phase := int(rhythmic_encounters[index].get("rhythm_phase", -1))
			if phase in [0, 1, 2]:
				rhythm_gap_sum[phase] += float(rhythmic_encounters[index + 1].course_distance) - float(rhythmic_encounters[index].course_distance)
				rhythm_gap_count[phase] += 1
		var repeated_rhythm := CourseGeneratorScript.new() as CourseGenerator
		repeated_rhythm.configure_ruleset(builder._make_multiplayer_ruleset(14), 14)
		repeated_rhythm.reset(seed_value)
		repeated_rhythm.ensure_horizon(45000.0, 500.0, 900.0, 820.0)
		_check(_rhythm_signature(rhythm_generator.get_planned_events()) == _rhythm_signature(repeated_rhythm.get_planned_events()), "Gen14 rhythm and encounters are stable when streamed for the same seed")
		_check(BiomeEncounterMix.multiplier(14, "cave", &"falling_rock") == 2.1 and BiomeEncounterMix.multiplier(14, "cave", &"saw_blade") == 1.7 and BiomeEncounterMix.multiplier(14, "cave", &"spike_group") == 0.9, "Gen14 cave overlays preserve the Gen12 cave mixture")
		_check(BiomeEncounterMix.multiplier(14, "haunted", &"haunted_ghost") == 3.2, "Gen14 haunted overlay preserves the characteristic ghost weighting")
	var sample_event := {"event_id":"volcano_test", "kind":"volcano", "x":2000.0, "floor_y":460.0, "ceiling_y":80.0, "width":120.0, "eruption_lead":1800, "eruption_period_ticks":156, "projectile_lifetime_ticks":58, "projectile_speed":330.0, "projectile_vertical_speed":570.0, "projectile_gravity":1200.0, "projectile_radius":14.0}
	var start_tick := LavaModel.eruption_start_tick(sample_event, 180.0)
	_check(start_tick == 2, "eruption tick is derived from shared course distance at base speed")
	var projectiles: Array[Dictionary] = LavaModel.projectiles_at(sample_event, 180.0, float(start_tick + 18))
	_check(projectiles.size() == 2, "one eruption has exactly two paired projectiles")
	if projectiles.size() == 2:
		_check(int(projectiles[0].direction) == -int(projectiles[1].direction), "paired projectiles travel in both directions")
		_check(is_equal_approx(float(projectiles[0].y), float(projectiles[1].y)), "paired trajectories share deterministic height")
	_check(LavaModel.projectiles_at(sample_event, 180.0, float(start_tick - 1)).is_empty(), "no projectile precedes the eruption tick")
	_check(LavaModel.projectiles_at(sample_event, 180.0, float(start_tick + 59)).is_empty(), "projectiles are bounded by lifetime")
	var origin_projectile: Dictionary = LavaModel.projectiles_at(sample_event, 180.0, float(start_tick)).front()
	_check(is_equal_approx(float(origin_projectile.y), float(sample_event.floor_y) - float(sample_event.get("height", 76.0)) * 0.78), "projectile starts at the visible crater opening")
	var minimum_corridor_top := 460.0 - 96.0 * 0.78 - 430.0 * 430.0 / (2.0 * 900.0) - 18.0
	_check(minimum_corridor_top >= 160.0 + RunnerMotion.SIZE.y + 24.0, "the maximum allowed trajectory clears a ceiling runner in a 300px corridor by at least 24px")
	var max_volcano := {"event_id":"volcano_envelope_max", "kind":"volcano", "x":2000.0, "floor_y":460.0, "ceiling_y":160.0, "width":150.0, "height":96.0, "projectile_lifetime_ticks":70, "projectile_speed":420.0, "projectile_vertical_speed":430.0, "projectile_gravity":900.0, "projectile_radius":18.0}
	var shared_envelope: Rect2 = LavaModel.volcano_collision_envelope(max_volcano)
	var shared_source_y := float(max_volcano.floor_y) - float(max_volcano.height) * 0.78
	var shared_apex_y := shared_source_y - float(max_volcano.projectile_vertical_speed) * float(max_volcano.projectile_vertical_speed) / (2.0 * float(max_volcano.projectile_gravity))
	_check(shared_envelope.position.y <= shared_apex_y - float(max_volcano.projectile_radius), "shared coin-exclusion envelope contains the crater-origin maximum apex and radius")
	_check(CoinPlanner._position_blocked(float(max_volcano.x), shared_apex_y, [max_volcano]), "coin placement excludes the corrected upper edge of every allowed volcano arc")
	_check(not CoinPlanner._position_blocked(float(max_volcano.x), float(max_volcano.ceiling_y) + 24.0, [max_volcano]), "the conservative volcano envelope still leaves the supported ceiling route's coin lane clear")
	for phase in [0, 1, 2]:
		_check(rhythm_gap_count[phase] > 0, "representative seeds include every Gen14 rhythm phase")
	var mean_short_gap := ((rhythm_gap_sum[0] / maxf(float(rhythm_gap_count[0]), 1.0)) + (rhythm_gap_sum[1] / maxf(float(rhythm_gap_count[1]), 1.0))) * 0.5
	var mean_recovery_gap := rhythm_gap_sum[2] / maxf(float(rhythm_gap_count[2]), 1.0)
	var gen14_cycle_mean := (rhythm_gap_sum[0] / maxf(float(rhythm_gap_count[0]), 1.0) + rhythm_gap_sum[1] / maxf(float(rhythm_gap_count[1]), 1.0) + mean_recovery_gap) / 3.0
	var gen13_mean_gap := gen13_hazard_gap_sum / maxf(float(gen13_hazard_gap_count), 1.0)
	_check(mean_recovery_gap > mean_short_gap + 80.0, "Gen14 adds measurable encounter groups followed by a longer recovery gap")
	_check(gen14_cycle_mean >= gen13_mean_gap * 0.85 and gen14_cycle_mean <= gen13_mean_gap * 1.15, "Gen14 rhythm varies spacing without a large average density change")
	print("LAVA_GENERATION_CONTRACT_TEST seeds=%d gen14_coins=%d gen13_coins=%d cracks=%d volcanoes=%d risk_rows=%d gen13_gap=%.1f gen14_cycle_gap=%.1f rhythm_short=%.1f recovery=%.1f failures=%d" % [seeds.size(), total_coins, total_legacy_coins, total_cracks, total_volcanoes, total_risk_rows, gen13_mean_gap, gen14_cycle_mean, mean_short_gap, mean_recovery_gap, failures])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _check_safe_lane_support(surface_index: RefCounted, event: Dictionary, ceiling: bool) -> void:
	var center_x := float(event.get("x", 0.0))
	for sample_index in range(17):
		var sample_x := center_x - 500.0 + float(sample_index) * 62.5
		var safe_surface: Dictionary = surface_index.surface_at(sample_x, ceiling)
		_check(bool(safe_surface.get("supported", false)), "generated %s has continuous supported escape lane at x=%.1f" % [str(event.get("kind", "")), sample_x])

func _rhythm_signature(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event in events:
		if event.has("rhythm_phase"):
			result.append("%d:%s:%.2f" % [int(event.rhythm_phase), str(event.kind), float(event.course_distance)])
	return result
