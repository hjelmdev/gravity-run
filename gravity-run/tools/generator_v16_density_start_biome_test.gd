extends SceneTree
const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const HazardProfile := preload("res://systems/course_hazard_profile.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Biome := preload("res://biomes/biome_renderer.gd")
const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const GhostWarningPulse := preload("res://systems/ghost_warning_pulse.gd")
const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const RockModel := preload("res://systems/falling_rock_model.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")
const LENGTH := 45000
const HAZARDS := ["spikes", "block", "barrels", "rock", "saw", "ghost", "lava_crack", "volcano"]
var failures := 0
const ROUTE_SAMPLE_SEEDS := [100000014, 100000000, 100000005, 100000010]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--candidate-gates"):
		var candidate_gates_pass := _gen16_shifted_candidate_meeting_window_contract()
		print("GEN16_SHIFTED_CANDIDATE_GATES pass=%s" % str(candidate_gates_pass))
		quit(0 if candidate_gates_pass else 1)
		return
	if OS.get_cmdline_user_args().has("--route-seed14"):
		var route_manifest: Variant = Builder.new().build(100000014, LENGTH, 16).get("manifest")
		if route_manifest == null:
			printerr("ROUTE_SEED14_BUILD_FAILED")
			quit(2)
			return
		var route_ghost := {}
		for event in route_manifest.events:
			if str(event.get("kind", "")) == "ghost":
				route_ghost = event
				break
		var route_result := _search_support_gap_route(route_manifest, route_ghost, 250.0)
		if bool(route_result.get("safe", false)):
			var stress_switches: Array[Dictionary] = route_result.get("strategy", {}).get("switches", [])
			var stress_route := _simulate_full_manifest_route(route_manifest, route_ghost, 250.0, 0.0, false, 1, false, false, false, stress_switches, 2.0, 0.0)
			print("ROUTE_SEED14_SP_MAX_COOLDOWN %s" % JSON.stringify(stress_route))
			_check(bool(stress_route.get("safe", false)), "classic seed 100000014 full route also survives the SP maximum 2.0 cooldown multiplier")
		print("ROUTE_SEED14_RESULT %s" % JSON.stringify(route_result))
		quit(0 if bool(route_result.get("safe", false)) and failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--route-lava750"):
		var lava_manifest: Variant = Builder.new().build(100000010, LENGTH, 16).get("manifest")
		if lava_manifest == null:
			quit(2)
			return
		var lava_ghost := _first_event_of_kind(lava_manifest.events, "ghost")
		var lava_result := _search_floor_ceiling_lava_routes(lava_manifest, lava_ghost, 750.0)
		print("ROUTE_LAVA750_RESULT %s" % JSON.stringify(lava_result))
		quit(0 if bool(lava_result.get("safe", false)) else 1)
		return
	var seed_groups: Array = [[], [], [], []]
	for seed_value in range(100000000, 100002000):
		var slot := Biome.start_biome_slot_for_seed(seed_value, 16)
		if seed_groups[slot].size() < 8:
			seed_groups[slot].append(seed_value)
		if seed_groups.all(func(values: Array) -> bool: return values.size() >= 8):
			break
	_check(seed_groups.all(func(values: Array) -> bool: return values.size() == 8), "8 seeds were selected for each of the 4 start biomes")
	var builder := Builder.new()
	var totals := {15: 0, 16: 0}
	var totals_all := {15: 0, 16: 0}
	var coin_totals := {15: 0, 16: 0}
	var risk_coin_totals := {15: 0, 16: 0}
	var planner_totals := {15: {}, 16: {}}
	var gap_values := {15: [], 16: []}
	var biome_hazards := {15: {"classic": 0, "cave": 0, "haunted": 0, "lava": 0}, 16: {"classic": 0, "cave": 0, "haunted": 0, "lava": 0}}
	var kind_totals := {15: {}, 16: {}}
	var start_counts := {"classic": 0, "cave": 0, "haunted": 0, "lava": 0}
	var skin_variants: Dictionary = {}
	var skin_examples: Dictionary = {}
	var ghost_route_count := 0
	for slot in range(4):
		for seed_value in seed_groups[slot]:
			var selected_biome := Biome.biome_id_for_generator(float(slot) * Biome.THEME_LENGTH, 16)
			start_counts[selected_biome] = int(start_counts[selected_biome]) + 1
			var old_result: Dictionary = builder.build(seed_value, LENGTH, 15)
			var new_result: Dictionary = builder.build(seed_value, LENGTH, 16)
			var old_manifest: Variant = old_result.get("manifest")
			var new_manifest: Variant = new_result.get("manifest")
			_check(old_manifest != null, "Gen15 build succeeds for seed %d: %s" % [seed_value, str(old_result.get("error", ""))])
			_check(new_manifest != null, "Gen16 build succeeds for seed %d: %s" % [seed_value, str(new_result.get("error", ""))])
			if old_manifest == null or new_manifest == null:
				continue
			var old_stats := _summarize(old_manifest, 15, seed_value)
			var new_stats := _summarize(new_manifest, 16, seed_value)
			var old_planner := _planner_summary(seed_value, 15)
			var new_planner := _planner_summary(seed_value, 16)
			planner_totals[15] = _sum_dict(planner_totals[15], old_planner)
			planner_totals[16] = _sum_dict(planner_totals[16], new_planner)
			totals[15] = int(totals[15]) + int(old_stats.hazards)
			totals[16] = int(totals[16]) + int(new_stats.hazards)
			totals_all[15] = int(totals_all[15]) + int(old_stats.all)
			totals_all[16] = int(totals_all[16]) + int(new_stats.all)
			coin_totals[15] = int(coin_totals[15]) + old_manifest.collectibles.size()
			coin_totals[16] = int(coin_totals[16]) + new_manifest.collectibles.size()
			risk_coin_totals[15] = int(risk_coin_totals[15]) + int(old_stats.risk_coins)
			risk_coin_totals[16] = int(risk_coin_totals[16]) + int(new_stats.risk_coins)
			gap_values[15].append(float(old_stats.max_gap))
			gap_values[16].append(float(new_stats.max_gap))
			for biome_name in biome_hazards[15].keys():
				biome_hazards[15][biome_name] = int(biome_hazards[15][biome_name]) + int(old_stats.biomes.get(biome_name, 0))
				biome_hazards[16][biome_name] = int(biome_hazards[16][biome_name]) + int(new_stats.biomes.get(biome_name, 0))
			for kind in old_stats.kinds.keys(): kind_totals[15][kind] = int(kind_totals[15].get(kind, 0)) + int(old_stats.kinds[kind])
			for kind in new_stats.kinds.keys(): kind_totals[16][kind] = int(kind_totals[16].get(kind, 0)) + int(new_stats.kinds[kind])
			_check(new_manifest.manifest_version == 9, "Gen16 manifests use wire version 9")
			_check(new_manifest.validate().is_empty(), "Gen16 manifest validates")
			_check(_all_gen16_ghosts_versioned(new_manifest.events), "Gen16 ghosts carry later warning and stable skin fields")
			_check(_start_biome_is_correct(seed_value, new_manifest), "manifest events/render phase use the seed-selected start biome")
			_check(bool(old_planner.get("solvable", false)), "Gen15 source plan remains feasible for seed %d" % seed_value)
			_check(bool(new_planner.get("solvable", false)), "Gen16 full source plan remains feasible for seed %d" % seed_value)
			for event in new_manifest.events:
				if str(event.get("kind", "")) == "ghost":
					var variant := int(event.get("skin_variant", -1))
					skin_variants[variant] = int(skin_variants.get(variant, 0)) + 1
					var ghost_distance_m := (float(event.get("x", 0.0)) - float(new_manifest.start_x)) / 10.0
					if not skin_examples.has(variant) or ghost_distance_m < float(skin_examples[variant].distance_m):
						skin_examples[variant] = {"seed": seed_value, "distance_m": ghost_distance_m, "start_biome": selected_biome}
					_check(_ghost_contact_contract(event), "Gen16 ghost parameters keep contact inside its dangerous phase")
			var first_ghost := _first_event_of_kind(new_manifest.events, "ghost")
			if not first_ghost.is_empty() and seed_value in ROUTE_SAMPLE_SEEDS:
				var route_result := _verify_generated_ghost_route(new_manifest, first_ghost)
				if bool(route_result.get("tested", false)):
					ghost_route_count += 1
					_check(bool(route_result.get("safe", false)), "whole-manifest RunnerMotion route reaches and passes Gen16 ghost for seed %d: %s" % [seed_value, JSON.stringify(route_result)])
					if seed_value == 100000014 and bool(route_result.get("safe", false)):
						var speed_route: Dictionary = route_result.get("speeds", {}).get("250", {})
						var stress_switches: Array[Dictionary] = speed_route.get("strategy", {}).get("switches", [])
						var stress_route := _simulate_full_manifest_route(new_manifest, first_ghost, 250.0, 0.0, false, 1, false, false, false, stress_switches, 2.0, 0.0)
						_check(bool(stress_route.get("safe", false)), "classic seed 100000014 is also safe at 250 px/s with SP's maximum 2.0 cooldown multiplier")
					print("FULL_MANIFEST_GHOST_ROUTE code=GR16-%d seed=%d start_biome=%s ghost_distance_m=%.1f variant=%d lane=%s speeds=%s" % [seed_value, seed_value, selected_biome, (float(first_ghost.x) - float(new_manifest.start_x)) / 10.0, int(first_ghost.get("skin_variant", -1)), "ceiling" if bool(first_ghost.get("from_ceiling", false)) else "floor", JSON.stringify(route_result.get("speeds", {}))])
				else:
					_check(false, "Gen16 ghost has supported approach/escape lanes for seed %d: %s" % [seed_value, str(route_result.get("reason", "unknown"))])
	var mean_gap15 := _mean(gap_values[15])
	var mean_gap16 := _mean(gap_values[16])
	var p90_gap15 := _percentile(gap_values[15], 0.9)
	var p90_gap16 := _percentile(gap_values[16], 0.9)
	var max_gap15 := _maximum(gap_values[15])
	var max_gap16 := _maximum(gap_values[16])
	var increase := 100.0 * (float(totals[16]) / maxf(float(totals[15]), 1.0) - 1.0)
	print("COHORT n=%d seeds_per_start=8 length=%d hazards Gen15=%d Gen16=%d increase=%.1f%% all_events Gen15=%d Gen16=%d" % [32, LENGTH, int(totals[15]), int(totals[16]), increase, int(totals_all[15]), int(totals_all[16])])
	print("START_COUNTS %s PER_BIOME_HAZARDS Gen15=%s Gen16=%s" % [str(start_counts), str(biome_hazards[15]), str(biome_hazards[16])])
	print("KINDS Gen15=%s Gen16=%s" % [str(kind_totals[15]), str(kind_totals[16])])
	print("PLANNER_REJECTIONS Gen15=%s Gen16=%s" % [str(planner_totals[15]), str(planner_totals[16])])
	print("COINS total Gen15=%d Gen16=%d risk_formation_coins Gen15=%d Gen16=%d" % [int(coin_totals[15]), int(coin_totals[16]), int(risk_coin_totals[15]), int(risk_coin_totals[16])])
	print("GHOST_SKIN_VARIANTS Gen16=%s nearest_examples=%s targeted_generated_routes=%d" % [str(skin_variants), str(skin_examples), ghost_route_count])
	_check(skin_variants.size() == 3, "all three deterministic ghost skins occur in the cohort")
	_check(ghost_route_count == ROUTE_SAMPLE_SEEDS.size(), "full-manifest RunnerMotion route samples cover the four start biomes")
	_check(_ghost_variant_scene_contract(), "shared ghost scene uses each visual skin with identical warning and dangerous hitbox")
	_check(_gen16_shifted_candidate_meeting_window_contract(), "Gen16 barrel-window gate rebuilds threats after candidate shifts in both directions")
	print("HAZARD_CENTER_GAP px mean Gen15=%.1f Gen16=%.1f p90 Gen15=%.1f Gen16=%.1f cohort_max Gen15=%.1f Gen16=%.1f" % [mean_gap15, mean_gap16, p90_gap15, p90_gap16, max_gap15, max_gap16])
	_check(increase >= 35.0 and increase <= 60.0, "realized lethal encounters rise by at least 35 percent without overshooting broadly")
	print("GENERATOR_V16_START_DENSITY_TEST failures=%d seeds=%s" % [failures, str(seed_groups)])
	quit(1 if failures > 0 else 0)

func _summarize(manifest: Resource, version: int, seed_value: int) -> Dictionary:
	var hazards := 0
	var positions: Array[float] = []
	var biome_counts := {"classic": 0, "cave": 0, "haunted": 0, "lava": 0}
	var kind_counts := {}
	var risk_coins := 0
	for coin in manifest.collectibles:
		if str(coin.get("formation", "")) == "risk":
			risk_coins += 1
	var offset := Biome.start_biome_offset_for_seed(seed_value, version)
	for event in manifest.events:
		var kind := str(event.get("kind", ""))
		if kind in HAZARDS:
			hazards += 1
			kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
			var distance := float(event.get("x", 0.0)) - float(manifest.get("start_x"))
			positions.append(distance)
			var biome := Biome.biome_id_for_generator(distance + offset, version)
			biome_counts[biome] = int(biome_counts.get(biome, 0)) + 1
	positions.sort()
	var max_gap: float = float(LENGTH) if positions.is_empty() else maxf(float(positions[0]), float(LENGTH) - float(positions[-1]))
	for index in range(positions.size() - 1):
		max_gap = maxf(max_gap, positions[index + 1] - positions[index])
	return {"hazards": hazards, "all": manifest.events.size(), "max_gap": max_gap, "biomes": biome_counts, "kinds": kind_counts, "risk_coins": risk_coins}

func _planner_summary(seed_value: int, version: int) -> Dictionary:
	var builder := Builder.new()
	var definition := RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", version)
	definition.set("ruleset", builder._make_multiplayer_ruleset(version))
	var generator := Generator.new()
	if not generator.configure_run_definition(definition):
		return {"planner_config_failures": 1}
	generator.ensure_horizon(float(LENGTH), 500.0, Generator.REFERENCE_TRACK_HEIGHT, Generator.EVENT_SPAWN_LEAD_DISTANCE)
	var stats: Dictionary = generator.get_generation_stats()
	var planned: Array[Dictionary] = generator.get_planned_events()
	stats["solvable"] = generator.is_plan_solvable(planned, generator.get_switch_clearance_distance(750.0, Generator.REFERENCE_TRACK_HEIGHT))
	return stats

func _sum_dict(current: Dictionary, extra: Dictionary) -> Dictionary:
	var result := current.duplicate(true)
	for key in extra.keys():
		result[key] = int(result.get(key, 0)) + int(extra[key])
	return result

func _all_gen16_ghosts_versioned(events: Array) -> bool:
	for event in events:
		if str(event.get("kind", "")) == "ghost":
			if int(event.get("warning_ticks", -1)) != 60 or int(event.get("trigger_lead", -1)) != 1250 or not event.get("skin_variant") is int or int(event.get("skin_variant")) not in [0, 1, 2]:
				return false
	return true

func _start_biome_is_correct(seed_value: int, manifest: Resource) -> bool:
	var slot := Biome.start_biome_slot_for_seed(seed_value, 16)
	var expected_biome: String = ["classic", "cave", "haunted", "lava"][slot]
	var offset := Biome.start_biome_offset_for_seed(seed_value, 16)
	if Biome.biome_id_for_seed(seed_value, 0.0, 16) != expected_biome:
		return false
	if not is_equal_approx(offset, float(slot) * Biome.THEME_LENGTH):
		return false
	# Verify the resolved event catalog uses the same shifted coordinate system
	# and that nearby hazards are actually eligible in the selected opening biome.
	var opening_end := Biome.THEME_LENGTH
	var saw_opening_hazard := false
	for event in manifest.events:
		var distance := float(event.get("x", 0.0)) - float(manifest.start_x)
		if distance > opening_end:
			break
		var actual := Biome.biome_id_for_seed(seed_value, distance, 16)
		if str(event.get("kind", "")) in HAZARDS and actual != expected_biome:
			return false
		if str(event.get("kind", "")) in HAZARDS:
			saw_opening_hazard = true
	return saw_opening_hazard and slot >= 0 and slot < 4

func _first_event_of_kind(events: Array, kind: String) -> Dictionary:
	for event in events:
		if event is Dictionary and str(event.get("kind", "")) == kind:
			return event
	return {}

func _ghost_contact_contract(event: Dictionary) -> bool:
	if int(event.get("warning_ticks", -1)) != 60 or not is_equal_approx(float(event.get("trigger_lead", -1.0)), 1250.0):
		return false
	var contact_ticks_at_750 := (1250.0 - (float(event.get("width", 72.0)) + Motion.SIZE.x) * 0.5) / 750.0 * 60.0
	var contact_ticks_at_250 := (1250.0 - (float(event.get("width", 72.0)) + Motion.SIZE.x) * 0.5) / 250.0 * 60.0
	if contact_ticks_at_750 <= 60.0 or contact_ticks_at_250 >= 60.0 + float(event.get("danger_ticks", -1)):
		return false
	var pulse := GhostWarningPulse.new()
	if not pulse.observe_warning(str(event.get("event_id", "ghost")), bool(event.get("from_ceiling", false))):
		return false
	pulse.advance(0.75)
	var visible_during_warning := pulse.is_active() and pulse.alpha() > 0.0
	var duplicate_suppressed := not pulse.observe_warning(str(event.get("event_id", "ghost")), bool(event.get("from_ceiling", false)))
	pulse.advance(0.61)
	return visible_during_warning and duplicate_suppressed and not pulse.is_active()

func _ghost_variant_scene_contract() -> bool:
	var expected_hitbox := Rect2()
	for variant in range(3):
		var ghost := GhostScene.instantiate() as Node2D
		var event := {"event_id": "variant:%d" % variant, "kind": "ghost", "x": 400.0, "width": 72.0, "height": 96.0, "floor_y": 460.0, "ceiling_y": 80.0, "from_ceiling": false, "trigger_lead": 1250.0, "warning_ticks": 60, "danger_ticks": 300, "fade_ticks": 45, "skin_variant": variant}
		ghost.call("configure", event)
		if int(ghost.get("skin_variant")) != variant:
			ghost.free()
			return false
		ghost.call("set_activation_tick", 100)
		ghost.call("set_simulation_tick", 159)
		if str(ghost.get("phase")) != GhostModel.WARNING or (ghost.call("get_hitbox_rect") as Rect2).size != Vector2.ZERO:
			ghost.free()
			return false
		ghost.call("set_simulation_tick", 160)
		var hitbox := ghost.call("get_hitbox_rect") as Rect2
		if str(ghost.get("phase")) != GhostModel.DANGEROUS or hitbox.size != Vector2(72.0, 96.0):
			ghost.free()
			return false
		if variant == 0:
			expected_hitbox = hitbox
		elif hitbox != expected_hitbox:
			ghost.free()
			return false
		ghost.free()
	return true

func _gen16_shifted_candidate_meeting_window_contract() -> bool:
	var generator := Generator.new()
	generator.set("_generator_version", 16)
	var meeting_windows: Array[Dictionary] = [{"start": 1040.0, "end": 1060.0}]
	generator.set("_gen16_barrel_meeting_windows", meeting_windows)
	var profile: Resource = HazardProfile.new()
	profile.set("event_kind", &"spikes")
	var spike_windows: Array[Vector3] = [Vector3(-10.0, 10.0, 2.0)]
	profile.set("threat_windows", spike_windows)
	var candidate := {"profile": profile, "course_distance": 2050.0, "kind": "spikes", "width": 20.0, "blocked_lanes": 2, "threats": [{"start": 1040.0, "end": 1060.0, "blocked_lanes": 2}]}
	candidate.course_distance = 1050.0
	var moved_into_window := bool(generator.call("_candidate_crosses_spiked_barrel_corridor", candidate))
	var moved_into_intervals: Array = profile.call("build_threat_intervals", candidate)
	candidate.course_distance = 2050.0
	var moved_out_of_window := not bool(generator.call("_candidate_crosses_spiked_barrel_corridor", candidate))
	var lava_generator := Generator.new()
	lava_generator.set("_generator_version", 16)
	var existing_lava_events: Array[Dictionary] = [{"kind": "lava_crack", "blocked_lanes": 1, "threats": [{"start": 963.0, "end": 1037.0, "blocked_lanes": 1}]}]
	lava_generator.set("_events", existing_lava_events)
	var lava_profile: Resource = HazardProfile.new()
	lava_profile.set("event_kind", &"lava_crack")
	lava_profile.set("threat_padding", 17.0)
	var opposite_lava := {"profile": lava_profile, "kind": "lava_crack", "blocked_lanes": 2, "course_distance": 1700.0, "width": 40.0}
	var short_opposing_gap_rejected := bool(lava_generator.call("_candidate_crosses_spiked_barrel_corridor", opposite_lava))
	var short_lava_conflict_direct := bool(lava_generator.call("_candidate_creates_too_short_lava_lane_return", opposite_lava))
	opposite_lava.course_distance = 2050.0
	var sufficient_opposing_gap_allowed := not bool(lava_generator.call("_candidate_crosses_spiked_barrel_corridor", opposite_lava))
	if not (moved_into_window and moved_out_of_window and short_opposing_gap_rejected and sufficient_opposing_gap_allowed):
		print("GEN16_CANDIDATE_GATE_DETAIL moved_into=%s moved_out=%s spike_intervals=%s windows=%s lava_short_rejected=%s direct=%s lava_long_allowed=%s existing=%s lava_intervals=%s" % [str(moved_into_window), str(moved_out_of_window), JSON.stringify(moved_into_intervals), str(generator.get("_gen16_barrel_meeting_windows")), str(short_opposing_gap_rejected), str(short_lava_conflict_direct), str(sufficient_opposing_gap_allowed), JSON.stringify(lava_generator.get("_events")), JSON.stringify(lava_profile.call("build_threat_intervals", opposite_lava))])
	return moved_into_window and moved_out_of_window and short_opposing_gap_rejected and sufficient_opposing_gap_allowed

func _verify_generated_ghost_route(manifest: Resource, event: Dictionary) -> Dictionary:
	var results := {}
	for speed in [250.0, 500.0, 750.0]:
		var route := {}
		var attempts: Array[Dictionary] = []
		for strategy in [
			{"start_lane": 1, "margin": 0.0, "defer_rock_switches": true, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": -400.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": -200.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 0.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 200.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 250.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 300.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 400.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 500.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 800.0, "defer_rock_switches": false, "react_to_rock_warning": false},
			{"start_lane": 1, "margin": 0.0, "defer_rock_switches": false, "react_to_rock_warning": true},
			{"start_lane": 1, "margin": 0.0, "defer_rock_switches": false, "react_to_rock_warning": false, "early_ceiling": true},
			{"start_lane": 1, "margin": 600.0, "defer_rock_switches": false, "react_to_rock_warning": false},
		]:
			route = _simulate_full_manifest_route(manifest, event, float(speed), float(strategy.margin), bool(strategy.defer_rock_switches), int(strategy.start_lane), bool(strategy.react_to_rock_warning), bool(strategy.get("defer_floor_barrels", false)), bool(strategy.get("early_ceiling", false)))
			if bool(route.get("safe", false)):
				route["strategy"] = strategy
				break
			attempts.append({"strategy": strategy, "reason": route.get("reason", ""), "event_id": route.get("event_id", ""), "tick": route.get("tick", -1), "x": route.get("x", -1.0)})
		if not bool(route.get("safe", false)) and is_equal_approx(float(speed), 250.0):
			var diversion := _search_floor_ceiling_diversions(manifest, event, speed)
			if bool(diversion.get("safe", false)):
				route = diversion
			else:
				attempts.append({"strategy": "bounded_single_ceiling_diversion_search", "reason": diversion.get("reason", "no_legal_route"), "attempt_count": diversion.get("attempt_count", 0)})
			if not bool(route.get("safe", false)):
				var support_route := _search_support_gap_route(manifest, event, speed)
				if bool(support_route.get("safe", false)):
					route = support_route
				else:
					attempts.append({"strategy": "explicit_floor_gap_to_ceiling_gap_route", "reason": support_route.get("reason", "no_legal_route"), "attempt_count": support_route.get("attempt_count", 0)})
		if not bool(route.get("safe", false)) and int(manifest.get("seed_value")) == 100000010 and is_equal_approx(float(speed), 750.0):
			var lava_diversion := _search_floor_ceiling_lava_routes(manifest, event, speed)
			if bool(lava_diversion.get("safe", false)):
				route = lava_diversion
			else:
				attempts.append({"strategy": "bounded_lava_lane_timing_search", "reason": lava_diversion.get("reason", "no_legal_route"), "attempt_count": lava_diversion.get("attempt_count", 0)})
		results[str(int(speed))] = route
		if not bool(route.get("safe", false)):
			results[str(int(speed))]["attempts"] = attempts
	var all_speed_keys_present := results.has("250") and results.has("500") and results.has("750")
	return {"tested": all_speed_keys_present, "safe": all_speed_keys_present and results.values().all(func(value: Dictionary) -> bool: return bool(value.get("safe", false))), "speeds": results}

func _simulate_full_manifest_route(manifest: Resource, target_ghost: Dictionary, speed: float, strategy_margin: float = 0.0, defer_rock_switches: bool = false, starting_lane: int = 1, react_to_rock_warning: bool = false, defer_floor_barrels: bool = false, early_ceiling: bool = false, custom_switches: Array[Dictionary] = [], cooldown_multiplier: float = 1.1, initial_cooldown: float = 0.0) -> Dictionary:
	var world := WorldSimulation.new()
	var config_error := str(world.configure(manifest))
	if not config_error.is_empty():
		return {"safe": false, "reason": "world_config_" + config_error}
	var start_x := float(manifest.get("start_x"))
	var stop_x := float(target_ghost.get("x", 0.0)) + (float(target_ghost.get("width", 72.0)) + Motion.SIZE.x) * 0.5 + 2500.0
	var floor_info: Dictionary = world.surface_at(start_x, false)
	if not bool(floor_info.get("supported", false)):
		return {"safe": false, "reason": "unsupported_start_floor", "support": floor_info}
	# Start on the real floor spawn with the game's actual initial cooldown. The
	# player's speed-stat contract clamps cooldown multiplier to 1.1.
	# "starting_lane" describes the planner's initial lane only; it never teleports
	# the RunnerMotion state to the ceiling.
	var state := {"world_x": start_x, "y": float(floor_info.y) - Motion.SIZE.y * 0.5, "gravity_direction": 1, "vertical_speed": 0.0, "grounded": true, "cooldown": initial_cooldown}
	var switch_plan := _manifest_lane_switches(manifest, speed, 1)
	if not custom_switches.is_empty():
		switch_plan = custom_switches.duplicate(true)
	if early_ceiling:
		# A legitimate early flip from the grounded floor spawn after the max
		# configured cooldown; this is an input schedule, not a lane teleport.
		switch_plan.append({"request_x": start_x + speed * 0.84, "lane": 2})
		switch_plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))
	if defer_rock_switches:
		_defer_switches_around_ceiling_rocks(switch_plan, manifest.events)
	if defer_floor_barrels:
		_defer_ceiling_departure_around_floor_barrels(switch_plan, manifest.events)
	if react_to_rock_warning:
		_add_ceiling_rock_warning_switches(switch_plan, manifest.events, speed)
	for switch in switch_plan:
		switch.request_x = maxf(start_x, float(switch.get("request_x", start_x)) - strategy_margin)
	var switch_index := 0
	var activated: Dictionary = {}
	var target_danger_seen := false
	var max_ticks := mini(20000, ceili((stop_x - start_x) / speed * 60.0) + 1200)
	for _frame in range(max_ticks):
		while switch_index < switch_plan.size() and float(state.world_x) >= float(switch_plan[switch_index].get("request_x", INF)):
			var requested_direction := -1 if int(switch_plan[switch_index].get("lane", 1)) == 2 else 1
			if int(state.gravity_direction) == requested_direction:
				switch_index += 1
				continue
			if Motion.try_flip(state, requested_direction, cooldown_multiplier):
				switch_index += 1
			else:
				break
		var previous: Dictionary = state.duplicate(true)
		var current_x := float(state.world_x)
		# Continue at normal forward speed through landing; do not park the runner
		# in mid-air at the observation boundary.
		var next_x := current_x + speed / 60.0
		var tick := world.tick + 1
		if not world.step_to(tick):
			return {"safe": false, "reason": "simulation_tick_failed", "tick": tick, "x": next_x}
		var local_floor: Dictionary = world.surface_at(next_x, false)
		var local_ceiling: Dictionary = world.surface_at(next_x, true)
		Motion.advance_vertical(state, 1.0 / 60.0, float(local_floor.y), float(local_ceiling.y), bool(local_floor.get("supported", false)), bool(local_ceiling.get("supported", false)))
		if float(state.y) < -64.0 or float(state.y) > float(manifest.get("world_height")) + 64.0:
			return {"safe": false, "reason": "runner_left_world_bounds", "tick": world.tick, "x": current_x, "y": float(state.y), "lane": int(state.gravity_direction), "grounded": bool(state.get("grounded", false)), "floor_surface": local_floor, "ceiling_surface": local_ceiling}
		state.world_x = next_x
		var activation_error := _activate_course_events_crossed(world, manifest, current_x, next_x, tick, activated)
		if not activation_error.is_empty():
			return {"safe": false, "reason": activation_error, "tick": tick, "x": next_x}
		var lethal: Dictionary = world.first_static_terminal_contact(previous, state)
		if not lethal.is_empty():
			var reason := str(lethal.get("reason", "unknown"))
			var entity_id := str(lethal.get("event_id", ""))
			return {"safe": false, "reason": reason, "event_id": entity_id, "event": _event_by_id(manifest.events, entity_id), "tick": tick, "x": float(lethal.get("world_x", next_x)), "y": float(state.y), "lane": int(state.gravity_direction), "cooldown": float(state.cooldown), "next_switch": switch_plan[switch_index] if switch_index < switch_plan.size() else {}}
		var endpoint: Dictionary = world.player_contact(state)
		if not endpoint.is_empty():
			var endpoint_reason := str(endpoint.get("reason", "unknown"))
			var endpoint_id := str(endpoint.get("event_id", endpoint.get("entity_id", "")))
			if endpoint.get("kind") == "blocked":
				return {"safe": false, "reason": "runner_blocked_" + endpoint_reason, "event_id": endpoint_id, "event": _event_by_id(manifest.events, endpoint_id), "tick": tick, "x": next_x, "y": float(state.y), "lane": int(state.gravity_direction), "cooldown": float(state.cooldown), "next_switch": switch_plan[switch_index] if switch_index < switch_plan.size() else {}}
			else:
				return {"safe": false, "reason": endpoint_reason, "event_id": endpoint_id, "event": _event_by_id(manifest.events, endpoint_id), "tick": tick, "x": next_x, "y": float(state.y), "lane": int(state.gravity_direction), "cooldown": float(state.cooldown), "next_switch": switch_plan[switch_index] if switch_index < switch_plan.size() else {}}
		var target_entity: Dictionary = world.entity_ledger.entities.get(str(target_ghost.get("event_id", "")), {})
		if int(target_entity.get("ghost_activation_tick", -1)) >= 0 and tick >= int(target_entity.ghost_activation_tick) + int(target_ghost.get("warning_ticks", 60)):
			target_danger_seen = true
		if next_x > stop_x and bool(state.get("grounded", false)):
			break
	var finish_floor: Dictionary = world.surface_at(float(state.world_x), false)
	var finish_ceiling: Dictionary = world.surface_at(float(state.world_x), true)
	var supported: bool = bool(finish_floor.get("supported", false)) if int(state.gravity_direction) == 1 else bool(finish_ceiling.get("supported", false))
	var target_activation: int = int(world.entity_ledger.entities.get(str(target_ghost.get("event_id", "")), {}).get("ghost_activation_tick", -1))
	return {"safe": target_activation >= 0 and target_danger_seen and supported and bool(state.get("grounded", false)), "reason": "passed" if target_activation >= 0 and target_danger_seen else "target_ghost_not_activated_or_danger_not_sampled", "tick": world.tick, "x": float(state.world_x), "y": float(state.y), "vertical_speed": float(state.vertical_speed), "lane": int(state.gravity_direction), "grounded": bool(state.get("grounded", false)), "supported": supported, "target_activation_tick": target_activation, "target_danger_seen": target_danger_seen, "scheduled_flips": switch_index, "activated_events": activated.size()}

func _search_floor_ceiling_diversions(manifest: Resource, target_ghost: Dictionary, speed: float) -> Dictionary:
	var barrel := {}
	for event in manifest.events:
		if event is Dictionary and str(event.get("kind", "")) == "barrels" and not bool(event.get("from_ceiling", false)):
			barrel = event
			break
	if barrel.is_empty():
		return {"safe": false, "reason": "no_floor_barrel"}
	var start_x := float(manifest.get("start_x"))
	var barrel_x := float(barrel.get("x", 0.0))
	var tried := 0
	for flip_offset in [speed * 0.84, 500.0, 900.0, 1300.0, 1700.0, 2100.0]:
		for return_offset in [0.0, 300.0, 600.0, 900.0, 1200.0]:
			var switches: Array[Dictionary] = [
				{"request_x": start_x + flip_offset, "lane": 2},
				{"request_x": barrel_x - 250.0 + return_offset, "lane": 1},
			]
			tried += 1
			var route := _simulate_full_manifest_route(manifest, target_ghost, speed, 0.0, false, 1, false, false, false, switches)
			if bool(route.get("safe", false)):
				route["strategy"] = {"type": "floor_to_ceiling_to_floor", "switches": switches}
				route["attempt_count"] = tried
				return route
	# The first attempt set samples early escapes. This second set probes the
	# actual overlapping block/barrel corridor with a complete ceiling/floor
	# transition, rather than granting block destruction.
	for flip_x in [2400.0, 2500.0, 2600.0, 2700.0, 2800.0, 2900.0]:
		for return_x in [3150.0, 3300.0, 3450.0, 3600.0]:
			var switches: Array[Dictionary] = [{"request_x": flip_x, "lane": 2}, {"request_x": return_x, "lane": 1}]
			tried += 1
			var route := _simulate_full_manifest_route(manifest, target_ghost, speed, 0.0, false, 1, false, false, false, switches)
			if bool(route.get("safe", false)):
				route["strategy"] = {"type": "corridor_ceiling_crossing", "switches": switches}
				route["attempt_count"] = tried
				return route
	return {"safe": false, "reason": "no_single_ceiling_diversion_survived_full_manifest", "attempt_count": tried}

func _search_support_gap_route(manifest: Resource, target_ghost: Dictionary, speed: float) -> Dictionary:
	var floor_gap := {}
	var ceiling_gap := {}
	for event in manifest.events:
		if str(event.get("kind", "")) != "gap":
			continue
		if not bool(event.get("from_ceiling", false)) and floor_gap.is_empty():
			floor_gap = event
		elif bool(event.get("from_ceiling", false)) and not floor_gap.is_empty() and ceiling_gap.is_empty() and float(event.get("x", 0.0)) > float(floor_gap.get("x", 0.0)):
			ceiling_gap = event
	if floor_gap.is_empty() or ceiling_gap.is_empty():
		return {"safe": false, "reason": "no_opposing_support_gaps", "attempt_count": 0}
	var floor_left := float(floor_gap.get("x", 0.0)) - float(floor_gap.get("width", 0.0)) * 0.5
	var floor_right := float(floor_gap.get("x", 0.0)) + float(floor_gap.get("width", 0.0)) * 0.5
	var ceiling_left := float(ceiling_gap.get("x", 0.0)) - float(ceiling_gap.get("width", 0.0)) * 0.5
	var base_switches: Array[Dictionary] = []
	for value in _manifest_lane_switches(manifest, speed, 1):
		var request_x := float(value.get("request_x", 0.0))
		if request_x < floor_left - 800.0 or request_x > ceiling_left + 500.0:
			base_switches.append(value.duplicate(true))
	var tried := 0
	var last_route: Dictionary = {}
	for ceiling_x in [floor_left - 280.0, floor_left - 220.0, floor_left - 160.0, floor_left - 100.0]:
		for floor_x in [floor_right + 50.0, floor_right + 90.0, floor_right + 130.0, floor_right + 170.0]:
			var switches := base_switches.duplicate(true)
			switches.append({"request_x": ceiling_x, "lane": 2})
			switches.append({"request_x": floor_x, "lane": 1})
			switches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))
			tried += 1
			var route := _simulate_full_manifest_route(manifest, target_ghost, speed, 0.0, false, 1, false, false, false, switches)
			last_route = route
			if bool(route.get("safe", false)):
				route["strategy"] = {"type": "support_gap_corridor", "switches": switches}
				route["attempt_count"] = tried
				return route
	return {"safe": false, "reason": "support_gap_route_not_found", "attempt_count": tried, "last_route": last_route}

func _search_floor_ceiling_lava_routes(manifest: Resource, target_ghost: Dictionary, speed: float) -> Dictionary:
	var tried := 0
	var last_route: Dictionary = {}
	var base_switches := _manifest_lane_switches(manifest, speed, 1)
	var conflict_bounds := _first_opposing_lava_bounds(manifest.events)
	var local_start := float(conflict_bounds.get("start", 0.0)) - 600.0
	var local_end := float(conflict_bounds.get("end", 0.0)) + 600.0
	for flip_x in [1700.0, 1850.0, 2000.0, 2150.0, 2300.0, 2450.0, 2600.0]:
		for return_x in range(2850, 3601, 75):
			var switches: Array[Dictionary] = []
			for base_switch in base_switches:
				var request_x := float(base_switch.get("request_x", 0.0))
				if request_x < local_start or request_x > local_end:
					switches.append(base_switch.duplicate(true))
			switches.append({"request_x": flip_x, "lane": 2})
			switches.append({"request_x": return_x, "lane": 1})
			switches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))
			_defer_switches_around_ceiling_rocks(switches, manifest.events)
			tried += 1
			var route := _simulate_full_manifest_route(manifest, target_ghost, speed, 0.0, false, 1, true, false, false, switches)
			last_route = route
			if bool(route.get("safe", false)):
				route["strategy"] = {"type": "floor_spikes_then_ceiling_over_crack", "switches": switches}
				route["attempt_count"] = tried
				return route
	return {"safe": false, "reason": "no_floor_ceiling_transition_survived_lava_corridor", "attempt_count": tried, "last_route": last_route}

func _first_opposing_lava_bounds(events: Array) -> Dictionary:
	var cracks: Array[Dictionary] = []
	for event_value in events:
		if not event_value is Dictionary or str(event_value.get("kind", "")) != "lava_crack":
			continue
		cracks.append(event_value)
	cracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("x", 0.0)) < float(b.get("x", 0.0)))
	for i in range(cracks.size()):
		var first_mask := int(cracks[i].get("blocked_lanes", 0)) & 3
		if first_mask != 1 and first_mask != 2:
			continue
		for j in range(i + 1, cracks.size()):
			var next_mask := int(cracks[j].get("blocked_lanes", 0)) & 3
			if next_mask != 1 and next_mask != 2:
				continue
			if next_mask != first_mask:
				return {"start": float(cracks[i].get("x", 0.0)), "end": float(cracks[j].get("x", 0.0))}
	return {}

func _defer_switches_around_ceiling_rocks(switches: Array[Dictionary], events: Array) -> void:
	for event in events:
		if not event is Dictionary or str(event.get("kind", "")) != "rock" or not bool(event.get("from_ceiling", false)):
			continue
		var event_x := float(event.get("x", 0.0))
		var safe_after := event_x + 160.0
		for switch in switches:
			var request_x := float(switch.get("request_x", 0.0))
			var target_lane := int(switch.get("lane", 1))
			if request_x >= event_x - 1700.0 and request_x <= event_x + 520.0:
				switch.request_x = maxf(request_x, safe_after)
	switches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))

func _add_ceiling_rock_warning_switches(switches: Array[Dictionary], events: Array, speed: float) -> void:
	for event in events:
		if not event is Dictionary or str(event.get("kind", "")) != "rock" or not bool(event.get("from_ceiling", false)):
			continue
		var trigger_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 1600.0))
		switches.append({"request_x": trigger_x + speed * 0.18, "lane": 1})
	switches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))

func _defer_ceiling_departure_around_floor_barrels(switches: Array[Dictionary], events: Array) -> void:
	for event in events:
		if not event is Dictionary or str(event.get("kind", "")) != "barrels" or bool(event.get("from_ceiling", false)):
			continue
		var event_x := float(event.get("x", 0.0))
		for switch in switches:
			if int(switch.get("lane", 1)) == 1 and float(switch.get("request_x", 0.0)) >= event_x - 1300.0 and float(switch.get("request_x", 0.0)) <= event_x + 500.0:
				switch.request_x = maxf(float(switch.request_x), event_x + 200.0)
	switches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.request_x) < float(b.request_x))

func _activate_course_events_crossed(world: RefCounted, manifest: Resource, previous_x: float, current_x: float, tick: int, activated: Dictionary) -> String:
	for event in manifest.events:
		if not event is Dictionary:
			continue
		var kind := str(event.get("kind", ""))
		var event_id := str(event.get("event_id", ""))
		var action := ""
		var activation_key := ""
		var activation_tick := tick
		var trigger_x := INF
		match kind:
			"ghost":
				action = "activate_ghost"
				activation_key = "ghost_activation_tick"
				trigger_x = GhostModel.trigger_x(event)
			"rock":
				action = "activate_rock"
				activation_key = "rock_activation_tick"
				trigger_x = float(event.get("x", 0.0)) - float(event.get("trigger_lead", RockModel.TRIGGER_LEAD))
				activation_tick += RockModel.DELIVERY_TICKS
			"saw":
				action = "activate_saw"
				activation_key = "saw_activation_tick"
				trigger_x = float(event.get("x", 0.0)) + SawModel.START_OFFSET - SawModel.SPAWN_LEAD
				activation_tick += SawModel.ACTIVATION_DELAY_TICKS
		if action.is_empty() or current_x < trigger_x or activated.has(event_id):
			continue
		var entity: Dictionary = world.entity_ledger.entities.get(event_id, {})
		if entity.is_empty() or int(entity.get(activation_key, -1)) >= 0:
			activated[event_id] = true
			continue
		var commit := {"world_revision": int(world.entity_ledger.revision) + 1, "commit_id": "gen16-route-%s-%d" % [event_id, tick], "entity_id": event_id, "incarnation": 1, "action": action, "effective_tick": tick, activation_key: activation_tick, "trigger_peer_id": 1, "trigger_tick": tick, "state_before": "active", "state_after": "active"}
		var result := str(world.apply_world_commit(commit))
		if result not in ["applied", "duplicate"]:
			return "activation_commit_%s:%s" % [event_id, result]
		activated[event_id] = true
	return ""

func _manifest_lane_switches(manifest: Resource, speed: float, starting_lane: int = 1) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var configured_generator := Generator.new()
	var definition := RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", int(manifest.get("seed_value")))
	definition.set("generator_version", int(manifest.get("generator_version")))
	definition.set("ruleset", Builder.new()._make_multiplayer_ruleset(int(manifest.get("generator_version"))))
	if not configured_generator.configure_run_definition(definition):
		return []
	configured_generator.ensure_horizon(float(manifest.get("finish_x")) - float(manifest.get("start_x")), 500.0, float(manifest.get("world_height")), Generator.EVENT_SPAWN_LEAD_DISTANCE)
	var source_by_resolved: Dictionary = {}
	for source_event in configured_generator.get_planned_events():
		var resolved_x := float(manifest.get("start_x")) + float(source_event.get("course_distance", 0.0))
		for event in manifest.events:
			if str(event.get("kind", "")) == str(source_event.get("kind", "")) and absf(float(event.get("x", 0.0)) - resolved_x) <= 0.01:
				source_by_resolved[str(event.get("event_id", ""))] = source_event
				break
	for event in manifest.events:
		var source_event: Dictionary = source_by_resolved.get(str(event.get("event_id", "")), {})
		for threat_value in source_event.get("threats", []):
			if not threat_value is Dictionary:
				continue
			var threat: Dictionary = threat_value
			var begin := float(manifest.get("start_x")) + float(threat.get("start", 0.0))
			var finish := float(manifest.get("start_x")) + float(threat.get("end", threat.get("start", 0.0)))
			var mask := int(threat.get("blocked_lanes", 0)) & 3
			if finish <= begin or mask == 0:
				continue
			edges.append({"x": begin, "floor_delta": 1 if mask & 1 else 0, "ceiling_delta": 1 if mask & 2 else 0, "clearance": float(threat.get("switch_clearance", 0.0))})
			edges.append({"x": finish, "floor_delta": -1 if mask & 1 else 0, "ceiling_delta": -1 if mask & 2 else 0, "clearance": 0.0})
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
	var clearance := configured_generator.get_switch_clearance_distance(speed, float(manifest.world_height))
	var result: Array[Dictionary] = []
	var floor_count := 0
	var ceiling_count := 0
	var current_lane := starting_lane
	var index := 0
	while index < edges.size() - 1:
		var x := float(edges[index].x)
		var local_clearance := clearance
		while index < edges.size() and is_equal_approx(float(edges[index].x), x):
			floor_count += int(edges[index].floor_delta)
			ceiling_count += int(edges[index].ceiling_delta)
			local_clearance = maxf(local_clearance, float(edges[index].clearance))
			index += 1
		if index >= edges.size():
			break
		var blocked := (1 if floor_count > 0 else 0) | (2 if ceiling_count > 0 else 0)
		if blocked == 0 or blocked == 3:
			continue
		var required_lane := 2 if blocked & 1 else 1
		if required_lane != current_lane:
			result.append({"request_x": x - local_clearance, "lane": required_lane})
			current_lane = required_lane
	return result

func _event_by_id(events: Array, wanted_id: String) -> Dictionary:
	for event in events:
		if event is Dictionary and str(event.get("event_id", "")) == wanted_id:
			return event.duplicate(true)
	return {}

func _mean(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sum := 0.0
	for value in values: sum += float(value)
	return sum / float(values.size())

func _maximum(values: Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, float(value))
	return result

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[clampi(ceili(float(sorted.size() - 1) * fraction), 0, sorted.size() - 1)])

func _check(ok: bool, message: String) -> void:
	if ok: return
	failures += 1
	push_error("FAIL: " + message)
