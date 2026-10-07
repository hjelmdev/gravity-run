extends RefCounted
class_name CourseManifestBuilder

const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseRulesetScript := preload("res://systems/course_generation_ruleset.gd")
const CourseRunDefinitionScript := preload("res://systems/course_run_definition.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const SawBladeModel := preload("res://systems/saw_blade_model.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const LavaHazardModel := preload("res://systems/lava_hazard_model.gd")
const CourseSurfaceIndexScript := preload("res://systems/course_surface_index.gd")
const RunnerMotionScript := preload("res://systems/runner_motion.gd")

const PLAYER_START_X := 180.0
const WORLD_WIDTH := 960.0
const WORLD_HEIGHT := 540.0
const FLOOR_START_Y := WORLD_HEIGHT - 80.0
const CEILING_START_Y := 80.0
const SLOPE_WIDTH := CourseGenerator.SLOPE_WIDTH
const SPIKE_GROUP_SPACING := CourseGenerator.SPIKE_GROUP_SPACING
const STEP_SPIKE_CLEARANCE := CourseGenerator.STEP_SPIKE_CLEARANCE
const GEN19_PURSUIT_MIN_TRIGGER_GAP := 4000.0

func build(seed_value: int, course_length_px: int, generator_version: int = CourseGenerator.GENERATOR_VERSION) -> Dictionary:
	if seed_value <= 0:
		return {"manifest": null, "error": "A positive deterministic seed is required."}
	if course_length_px < 10000 or course_length_px > 1000000:
		return {"manifest": null, "error": "The course length is outside supported limits."}
	var ruleset := _make_multiplayer_ruleset(generator_version)
	var definition := CourseRunDefinitionScript.new() as Resource
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", generator_version)
	definition.set("ruleset", ruleset)
	var definition_error := str(definition.call("validate"))
	if not definition_error.is_empty():
		return {"manifest": null, "error": definition_error}

	var generator := CourseGeneratorScript.new() as CourseGenerator
	if not generator.configure_run_definition(definition):
		return {"manifest": null, "error": "Could not configure deterministic multiplayer course generation."}
	generator.ensure_horizon(float(course_length_px), 500.0, CourseGenerator.REFERENCE_TRACK_HEIGHT, CourseGenerator.EVENT_SPAWN_LEAD_DISTANCE)
	var source_events: Array[Dictionary] = generator.get_planned_events()
	var manifest := ManifestScript.new() as MultiplayerCourseManifest
	manifest.generator_version = generator_version
	manifest.manifest_version = 13 if generator_version >= CourseGenerator.GENERATOR_VERSION_20 else (12 if generator_version >= CourseGenerator.GENERATOR_VERSION_19 else (11 if generator_version >= CourseGenerator.GENERATOR_VERSION_18 else (10 if generator_version >= CourseGenerator.GENERATOR_VERSION_17 else (9 if generator_version >= CourseGenerator.GENERATOR_VERSION_16 else (8 if generator_version >= CourseGenerator.GENERATOR_VERSION_15 else (7 if generator_version >= CourseGenerator.GENERATOR_VERSION_14 else (6 if generator_version >= CourseGenerator.GENERATOR_VERSION_12 else (5 if generator_version >= CourseGenerator.GENERATOR_VERSION_10 else (4 if generator_version >= CourseGenerator.GENERATOR_VERSION_9 else (3 if generator_version >= CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION else 2))))))))))
	manifest.course_identity = str(definition.call("get_course_identity"))
	manifest.seed_value = seed_value
	manifest.course_length_px = course_length_px
	manifest.start_x = PLAYER_START_X
	manifest.finish_x = PLAYER_START_X + float(course_length_px)
	manifest.ruleset_fingerprint = str(ruleset.call("get_fingerprint"))
	var biome_start_offset := BiomeRendererScript.start_biome_offset_for_seed(seed_value, generator_version)
	manifest.events = _resolve_events(source_events, course_length_px, generator_version, biome_start_offset)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_17:
		manifest.events = filter_unsafe_gen17_biome_events(manifest.events)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_18:
		manifest.events = filter_unsafe_gen18_flybys(manifest.events)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_19:
		manifest.events = filter_unsafe_gen19_pursuits(manifest.events)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_15:
		manifest.events = filter_unsafe_gen15_volcanoes(manifest.events, manifest.start_x)
	if generator_version >= CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION:
		manifest.collectibles = CoinPlanner.plan(seed_value, manifest.start_x, manifest.finish_x, manifest.events, FLOOR_START_Y, CEILING_START_Y, int(ruleset.get("coin_revision")), float(ruleset.get("coin_density")))
	manifest.manifest_hash = manifest.calculate_hash()
	var manifest_error := str(manifest.call("validate"))
	if not manifest_error.is_empty():
		return {"manifest": null, "error": manifest_error}
	return {"manifest": manifest, "error": ""}

func resolve_runtime_events(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float = 0.0) -> Array[Dictionary]:
	var resolved := _resolve_events(source_events, course_length_px, generator_version, biome_start_offset)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_17:
		resolved = filter_unsafe_gen17_biome_events(resolved)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_18:
		resolved = filter_unsafe_gen18_flybys(resolved)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_19:
		resolved = filter_unsafe_gen19_pursuits(resolved)
	# Keep new Gen20 runtime coin planning on the same eligible volcano set as
	# the MP manifest. This is explicitly versioned to preserve older SP seeds.
	if generator_version >= CourseGenerator.GENERATOR_VERSION_20:
		resolved = filter_unsafe_gen15_volcanoes(resolved, PLAYER_START_X)
	return resolved

func filter_unsafe_gen19_pursuits(events: Array[Dictionary]) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	var last_pursuit_trigger := -INF
	# A second lane-locked chase must not snapshot the escape lane while the
	# previous one is still dangerous. At the model's maximum 800px/s this spacing
	# separates triggers by 300 ticks, beyond the 90+200 tick warning/danger window.
	# Other hazard types and the frozen Gen17/18 paths are retained unchanged.
	for event in events:
		if str(event.get("kind", "")) != "ghost" or int(event.get("ghost_variant", 0)) != 3:
			filtered.append(event)
			continue
		var trigger_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 2500.0))
		var spacing_ok := trigger_x - last_pursuit_trigger >= GEN19_PURSUIT_MIN_TRIGGER_GAP
		var start_lag := float(event.get("pursuit_start_lag", 330.0))
		var warning_ticks := float(event.get("warning_ticks", 90))
		var delta := float(event.get("pursuit_speed_delta", 220.0))
		var relative_at_lock := -start_lag + delta * warning_ticks / 60.0
		var exit_offset := 180.0 + float(event.get("width", 72.0)) * 0.5 + 600.0
		var exit_ticks := maxf((exit_offset - relative_at_lock) / maxf(delta, 1.0) * 60.0, 0.0)
		var max_speed := CourseGenerator.GHOST_FLYBY_MAX_RUN_SPEED
		var route_start := trigger_x - start_lag - float(event.get("width", 72.0)) * 0.5 - 70.0
		var route_end := trigger_x + max_speed * warning_ticks / 60.0 + (max_speed + delta) * exit_ticks / 60.0 + float(event.get("width", 72.0)) * 0.5 + 70.0
		var visible_ticks := warning_ticks - maxf(start_lag - (180.0 - float(event.get("width", 72.0)) * 0.5), 0.0) / maxf(delta, 1.0) * 60.0
		var route_geometry_valid := visible_ticks >= 36.0 and is_finite(route_start) and is_finite(route_end) and route_end > route_start
		var both_supported := route_geometry_valid and bool(surface_index.call("interval_is_supported", route_start, route_end, false)) and bool(surface_index.call("interval_is_supported", route_start, route_end, true))
		var stable_lanes := route_geometry_valid and _gen18_surface_stays_near(surface_index, route_start, route_end, false, float(event.get("floor_y", FLOOR_START_Y))) and _gen18_surface_stays_near(surface_index, route_start, route_end, true, float(event.get("ceiling_y", CEILING_START_Y)))
		if spacing_ok and both_supported and stable_lanes:
			filtered.append(event)
			last_pursuit_trigger = trigger_x
		else:
			var fallback := _gen19_supported_single_lane_fallback(event, events, surface_index)
			if not fallback.is_empty():
				filtered.append(fallback)
	return filtered

func _gen19_supported_single_lane_fallback(source: Dictionary, events: Array[Dictionary], surface_index: RefCounted) -> Dictionary:
	# A rejected both-lane chase may become a small floor block only where a
	# verified, stable ceiling route exists for the complete contact/flip window.
	# This deterministic filler is a lighter existing encounter, not a new hazard.
	var x := float(source.get("x", 0.0))
	const HALF_CONTACT := 48.0
	const CLEARANCE := 500.0
	var region_left := x - CLEARANCE
	var region_right := x + CLEARANCE
	var floor_sample: Dictionary = surface_index.call("surface_at", x, false)
	var ceiling_sample: Dictionary = surface_index.call("surface_at", x, true)
	if not bool(floor_sample.get("supported", false)) or not bool(ceiling_sample.get("supported", false)):
		return {}
	if float(floor_sample.get("y", FLOOR_START_Y)) - float(ceiling_sample.get("y", CEILING_START_Y)) < RunnerMotionScript.SIZE.y + 76.0:
		return {}
	if not bool(surface_index.call("interval_is_supported", region_left, region_right, true)):
		return {}
	if not _gen18_surface_stays_near(surface_index, region_left, region_right, true, float(ceiling_sample.y)):
		return {}
	if not bool(surface_index.call("interval_is_supported", x - HALF_CONTACT, x + HALF_CONTACT, false)):
		return {}
	if not _gen18_surface_stays_near(surface_index, x - HALF_CONTACT, x + HALF_CONTACT, false, float(floor_sample.y)):
		return {}
	for other in events:
		if str(other.get("event_id", "")) == str(source.get("event_id", "")):
			continue
		var other_kind := str(other.get("kind", ""))
		if other_kind in ["step", "slope", "gap"]:
			continue
		var other_x := float(other.get("x", 0.0))
		var mask := int(other.get("blocked_lanes", 0))
		if mask == 0:
			mask = CourseGenerator.CEILING_LANE if bool(other.get("from_ceiling", false)) else CourseGenerator.FLOOR_LANE
		var extent := float(other.get("width", 72.0)) * 0.5 + 50.0
		if other_kind == "ghost":
			if int(other.get("ghost_variant", 0)) in [2, 3]:
				mask = CourseGenerator.BOTH_LANES
				extent = maxf(extent, 900.0)
			elif int(other.get("ghost_variant", 0)) == 1:
				extent = maxf(extent, 700.0)
		if (mask & CourseGenerator.CEILING_LANE) != 0 and absf(other_x - x) <= CLEARANCE + extent:
			return {}
		if (mask & CourseGenerator.FLOOR_LANE) != 0 and absf(other_x - x) <= HALF_CONTACT + extent:
			return {}
	var fallback := {
		"event_id": str(source.get("event_id", "")),
		"kind": "block",
		"x": x,
		"y": float(floor_sample.y),
		"width": 44.0,
		"height": 72.0,
		"from_ceiling": false,
		"blocked_lanes": CourseGenerator.FLOOR_LANE,
		"gen19_supported_fallback": true,
		"gen19_replaced_kind": "ghost_pursuit",
	}
	fallback["threats"] = [{"start": x - HALF_CONTACT, "end": x + HALF_CONTACT, "blocked_lanes": CourseGenerator.FLOOR_LANE}]
	return fallback

func filter_unsafe_gen18_flybys(events: Array[Dictionary]) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	for event in events:
		if str(event.get("kind", "")) != "ghost" or int(event.get("ghost_variant", 0)) != 2:
			filtered.append(event)
			continue
		var trigger_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 1500.0))
		var start_lag := float(event.get("flyby_start_lag", 130.0))
		var warning_ticks := float(event.get("warning_ticks", 72))
		var danger_ticks := float(event.get("danger_ticks", 120))
		var danger_end := trigger_x + 800.0 * warning_ticks / 60.0 + (800.0 + float(event.get("flyby_speed_delta", 500.0))) * danger_ticks / 60.0
		var padding := float(event.get("width", 72.0)) * 0.5 + 70.0
		var route_start := trigger_x - start_lag - padding
		var route_end := danger_end + padding
		var safe_both := bool(surface_index.call("interval_is_supported", route_start, route_end, false)) and bool(surface_index.call("interval_is_supported", route_start, route_end, true))
		# Ghost pose is intentionally lane-locked after its warning; reject corridors
		# where a long step/slope would leave that fixed pose far from the actual lane.
		var lane_pose_stable := _gen18_surface_stays_near(surface_index, route_start, route_end, false, float(event.get("floor_y", FLOOR_START_Y))) and _gen18_surface_stays_near(surface_index, route_start, route_end, true, float(event.get("ceiling_y", CEILING_START_Y)))
		if safe_both and lane_pose_stable:
			filtered.append(event)
	return filtered

func _gen18_surface_stays_near(surface_index: RefCounted, start_x: float, end_x: float, ceiling: bool, reference_y: float) -> bool:
	const MAX_LANE_POSE_DELTA := 40.0
	var checks: Array[float] = [start_x, end_x]
	var boundaries: Array = surface_index.call("support_boundaries", ceiling)
	var in_range: Array[float] = []
	for boundary_value in boundaries:
		var boundary := float(boundary_value)
		if boundary > start_x and boundary < end_x:
			in_range.append(boundary)
	in_range.sort()
	var previous := start_x
	for boundary in in_range:
		checks.append((previous + boundary) * 0.5)
		checks.append(boundary)
		checks.append(boundary - 0.00002)
		checks.append(boundary + 0.00002)
		previous = boundary
	checks.append((previous + end_x) * 0.5)
	for x in checks:
		var sample: Dictionary = surface_index.call("surface_at", x, ceiling)
		if not bool(sample.get("supported", false)) or absf(float(sample.get("y", INF)) - reference_y) > MAX_LANE_POSE_DELTA:
			return false
	return true

func filter_unsafe_gen15_volcanoes(events: Array[Dictionary], course_start_x: float) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	for event in events:
		if str(event.get("kind", "")) == "volcano" and not LavaHazardModel.gen15_ceiling_route_is_supported(event, surface_index, course_start_x):
			continue
		filtered.append(event)
	return filtered

func filter_unsafe_gen17_biome_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	for event in events:
		var keep := true
		var kind := str(event.get("kind", ""))
		var event_x := float(event.get("x", 0.0))
		if kind == "ghost" and int(event.get("ghost_variant", 0)) == 1:
			var start_x := event_x - float(event.get("trigger_lead", 1700.0)) - float(event.get("chase_start_lag", 220.0)) - float(event.get("width", 72.0)) * 0.5
			var end_x := event_x - float(event.get("trigger_lead", 1700.0)) - float(event.get("chase_start_lag", 220.0)) + float(event.get("chase_speed", 760.0)) * float(event.get("danger_ticks", 150)) / 60.0 + float(event.get("width", 72.0)) * 0.5
			keep = bool(surface_index.call("interval_is_supported", start_x, end_x, true)) and bool(surface_index.call("interval_is_supported", start_x, end_x, false))
		elif kind == "rock" and int(event.get("rock_variant", 0)) == 1:
			keep = bool(surface_index.call("surface_at", event_x, true).get("supported", false))
		elif kind == "lava_crack" and int(event.get("lava_variant", 0)) == 1:
			var half_width := float(event.get("width", 160.0)) * 0.5 + 44.0
			keep = bool(surface_index.call("interval_is_supported", event_x - half_width, event_x + half_width, true))
		if keep:
			filtered.append(event)
	return filtered

func _make_multiplayer_ruleset(generator_version: int) -> Resource:
	var ruleset := CourseRulesetScript.new() as Resource
	ruleset.set("ruleset_id", &"multiplayer_race")
	if generator_version in [CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20]:
		ruleset.set("revision", 16)
		ruleset.set("event_density", 2.5)
		ruleset.set("coin_revision", 2)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_17:
		ruleset.set("revision", 14)
		ruleset.set("event_density", 1.9)
		ruleset.set("coin_revision", 2)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_18:
		ruleset.set("revision", 15)
		ruleset.set("event_density", 2.5)
		ruleset.set("coin_revision", 2)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_16:
		ruleset.set("revision", 13)
		ruleset.set("event_density", 1.9)
		ruleset.set("coin_revision", 2)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_15:
		ruleset.set("revision", 12)
		ruleset.set("event_density", 1.55)
		ruleset.set("coin_revision", 2)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_14:
		ruleset.set("revision", 11)
		ruleset.set("event_density", 1.55)
		ruleset.set("coin_revision", 2)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_13:
		ruleset.set("revision", 10)
		ruleset.set("event_density", 1.55)
		ruleset.set("coin_revision", 2)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_12:
		ruleset.set("revision", 9)
		ruleset.set("event_density", 1.55)
		ruleset.set("coin_revision", 2)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_11:
		ruleset.set("revision", 8)
		ruleset.set("event_density", 1.55)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_10:
		ruleset.set("revision", 7)
		ruleset.set("event_density", 1.55)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_9:
		ruleset.set("revision", 6)
		ruleset.set("event_density", 1.55)
	elif generator_version == CourseGenerator.GENERATOR_VERSION_8:
		ruleset.set("revision", 5)
		ruleset.set("event_density", 1.5)
	elif generator_version >= CourseGenerator.ROCK_SAFE_GENERATOR_VERSION:
		ruleset.set("revision", 4)
		ruleset.set("event_density", 1.5)
	elif generator_version >= CourseGenerator.GENERATOR_VERSION_6:
		ruleset.set("revision", 3)
		ruleset.set("event_density", 1.5)
	elif generator_version >= CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION:
		ruleset.set("revision", 2)
		ruleset.set("event_density", 1.5)
	elif generator_version == CourseGenerator.PREVIOUS_GENERATOR_VERSION:
		ruleset.set("revision", 1)
		ruleset.set("event_density", 1.25)
	else:
		ruleset.set("revision", 1)
		ruleset.set("event_density", 1.25)
	# Match the default singleplayer encounter catalog; keep mode-specific rules above it.
	ruleset.set("include_all_profiles", true)
	return ruleset

func _resolve_events(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float = 0.0) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	var floor_y := FLOOR_START_Y
	var ceiling_y := CEILING_START_Y
	var event_index := 0
	for source in source_events:
		var course_distance := float(source.get("course_distance", 0.0))
		if course_distance > float(course_length_px):
			break
		var event_x := PLAYER_START_X + course_distance
		var kind := str(source.get("kind", ""))
		var from_ceiling := bool(source.get("from_ceiling", false))
		var floor_surface_y := _surface_y_at(resolved, event_x, false)
		var ceiling_surface_y := _surface_y_at(resolved, event_x, true)
		var surface_y := _surface_y_at(resolved, event_x, from_ceiling)
		var event_prefix := "event_%05d" % event_index
		match kind:
			"spikes":
				var count := int(source.get("count", 4))
				var group_spacing := float((count - 1) * SPIKE_GROUP_SPACING)
				var width := group_spacing + CourseGenerator.SPIKE_WIDTH
				resolved.append({
					"event_id": event_prefix,
					"kind": "spikes",
					"x": event_x,
					"start_x": event_x - group_spacing * 0.5,
					"y": surface_y,
					"count": count,
					"spacing": SPIKE_GROUP_SPACING,
					"width": width,
					"from_ceiling": from_ceiling,
				})
			"block":
				var block_width := float(source.get("width", 48.0))
				var block_height := float(source.get("height", 72.0))
				var required_clearance := block_height + 56.0
				if generator_version in [CourseGenerator.GENERATOR_VERSION_18, CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20] and _gen18_small_block_has_supported_runner_clearance(resolved, source_events, course_distance, block_width, block_height):
					required_clearance = block_height + float(RunnerMotionScript.SIZE.y) + 4.0
				if floor_surface_y - ceiling_surface_y < required_clearance:
					event_index += 1
					continue
				resolved.append({
					"event_id": event_prefix,
					"kind": "block",
					"x": event_x,
					"y": surface_y,
					"width": block_width,
					"height": block_height,
					"from_ceiling": from_ceiling,
				})
			"barrels":
				var barrel_height := float(source.get("height", HazardRules.BARREL_WIDTH))
				if floor_surface_y - ceiling_surface_y < barrel_height + 56.0:
					event_index += 1
					continue
				var barrel_record := {
					"event_id": event_prefix,
					"kind": "barrels",
					"x": event_x,
					"y": surface_y,
					"width": float(source.get("width", HazardRules.BARREL_WIDTH + (int(source.get("count", 1)) - 1) * HazardRules.BARREL_CHAIN_SPACING)),
					"height": barrel_height,
					"count": int(source.get("count", 1)),
					"spacing": HazardRules.BARREL_CHAIN_SPACING,
					"motion_speed_multiplier": float(source.get("motion_speed_multiplier", 1.0)),
					"spawn_lead_distance": CourseGenerator.EVENT_SPAWN_LEAD_DISTANCE,
				}
				if generator_version >= CourseGenerator.GENERATOR_VERSION_12 and bool(source.get("spiked", false)):
					barrel_record["spiked"] = true
				resolved.append(barrel_record)
			"gap":
				resolved.append({
					"event_id": event_prefix,
					"kind": "gap",
					"x": event_x,
					"width": float(source.get("width", 160.0)),
					"from_ceiling": from_ceiling,
				})
			"step":
				var start_y := ceiling_y if from_ceiling else floor_y
				var change := float(source.get("height", 84.0))
				var low_limit := 40.0 if from_ceiling else 330.0
				var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
				var end_y := start_y + change if from_ceiling else start_y - change
				end_y = clampf(end_y, low_limit, high_limit)
				if absf(end_y - start_y) < 40.0:
					end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
				resolved.append({
					"event_id": event_prefix,
					"kind": "step",
					"x": event_x,
					"start_y": start_y,
					"end_y": end_y,
					"from_ceiling": from_ceiling,
					"spiked": bool(source.get("spiked_step", false)),
				})
				if bool(source.get("spiked_step", false)):
					var spike_count := int(source.get("count", 4))
					var spike_width := float((spike_count - 1) * SPIKE_GROUP_SPACING)
					var points_left := (end_y < start_y) != from_ceiling
					var spike_start_x := event_x + STEP_SPIKE_CLEARANCE if points_left else event_x - spike_width - STEP_SPIKE_CLEARANCE
					resolved.append({
						"event_id": event_prefix + "_spikes",
						"kind": "spikes",
						"x": spike_start_x,
						"start_x": spike_start_x,
						"y": end_y if points_left else start_y,
						"count": spike_count,
						"spacing": SPIKE_GROUP_SPACING,
						"width": spike_width + CourseGenerator.SPIKE_WIDTH,
						"from_ceiling": from_ceiling,
					})
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y
			"slope":
				var start_y := ceiling_y if from_ceiling else floor_y
				var low_limit := 40.0 if from_ceiling else 330.0
				var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
				var direction := float(source.get("slope_direction", 1.0))
				var end_y := clampf(start_y + direction * float(source.get("height", 65.0)), low_limit, high_limit)
				if absf(end_y - start_y) < 40.0:
					end_y = clampf(start_y - direction * 45.0, low_limit, high_limit)
				resolved.append({
					"event_id": event_prefix,
					"kind": "slope",
					"x": event_x,
					"start_x": event_x - SLOPE_WIDTH * 0.5,
					"end_x": event_x + SLOPE_WIDTH * 0.5,
					"start_y": start_y,
					"end_y": end_y,
					"from_ceiling": from_ceiling,
				})
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y
			"rock":
				var icicle := int(source.get("rock_variant", 0)) == 1
				var near_terrain := false
				for terrain_source in source_events:
					var terrain_kind := str(terrain_source.get("kind", ""))
					var terrain_distance := float(terrain_source.get("course_distance", 0.0))
					if terrain_kind not in ["step", "slope", "gap"] or (icicle and terrain_kind == "gap" and not bool(terrain_source.get("from_ceiling", false))):
						continue
					if absf(terrain_distance - course_distance) < 420.0:
						near_terrain = true
						break
				for prior in resolved:
					var prior_kind := str(prior.get("kind", ""))
					var prior_x := float(prior.get("x", 0.0))
					if prior_kind in ["step", "slope"] and absf(prior_x - event_x) < 420.0:
						near_terrain = true
						break
				var icicle_width := float(source.get("width", 52.0)) if icicle else 0.0
				var floor_supported := not icicle or not _has_floor_gap_over_interval(source_events, course_distance, icicle_width)
				if near_terrain or floor_surface_y - ceiling_surface_y < 260.0:
					event_index += 1
					continue
				var rock_event := {
					"event_id": event_prefix,
					"kind": "rock",
					"x": event_x,
					"width": float(source.get("width", 90.0)),
					"height": float(source.get("height", 100.0)),
					"floor_y": floor_surface_y,
					"ceiling_y": ceiling_surface_y,
					"trigger_lead": float(source.get("trigger_lead", 1100.0)),
					"warning_ticks": int(source.get("warning_ticks", 36)),
					"fall_ticks": int(source.get("fall_ticks", 20)),
					"burial_depth": float(source.get("burial_depth", 24.0)),
					"from_ceiling": true,
				}
				if icicle:
					rock_event.merge({"rock_variant": 1, "floor_supported": floor_supported, "lodged_ticks": int(source.get("lodged_ticks", 240))}, true)
				resolved.append(rock_event)
			"saw":
				var from_ceiling_saw := bool(source.get("from_ceiling", false))
				var saw_variant := str(source.get("saw_variant", "legacy_floor_then_drop"))
				var saw_floor_y := _surface_y_at(resolved, event_x, false)
				var saw_ceiling_y := _surface_y_at(resolved, event_x, true)
				if saw_floor_y - saw_ceiling_y < 260.0:
					event_index += 1
					continue
				var start_offset := SawBladeModel.START_OFFSET
				var gap_offset := SawBladeModel.ROOF_GAP_OFFSET
				var gap_width := SawBladeModel.ROOF_GAP_WIDTH
				if saw_variant == "ceiling_gap_drop":
					gap_offset = SawBladeModel.V10_DROP_ROOF_GAP_OFFSET
					gap_width = SawBladeModel.V10_DROP_ROOF_GAP_WIDTH
				var saw_x := event_x + start_offset
				var saw_record := {
					"event_id": event_prefix,
					"kind": "saw",
					"x": event_x,
					"spawn_x": saw_x,
					"spawn_lead": SawBladeModel.SPAWN_LEAD,
					"start_offset": start_offset,
					"floor_y": saw_floor_y,
					"ceiling_y": saw_ceiling_y,
					"from_ceiling": from_ceiling_saw,
				}
				if source.has("saw_variant"):
					saw_record["saw_variant"] = saw_variant
					saw_record["saw_radius"] = float(source.get("saw_radius", SawBladeModel.RADIUS))
				if from_ceiling_saw and saw_variant in ["legacy_floor_then_drop", "ceiling_gap_drop"]:
					var roof_gap_x := event_x + gap_offset
					resolved.append({"event_id": event_prefix + "_roof_gap", "kind": "gap", "x": roof_gap_x, "width": gap_width, "from_ceiling": true})
					saw_record["roof_gap_x"] = roof_gap_x
					saw_record["roof_gap_width"] = gap_width
				resolved.append(saw_record)
			"ghost":
				if generator_version < CourseGenerator.GENERATOR_VERSION_11 or BiomeRendererScript.biome_id_for_generator(course_distance + biome_start_offset, generator_version) != "haunted":
					event_index += 1
					continue
				var ghost_width := float(source.get("width", 72.0))
				var ghost_height := float(source.get("height", 96.0))
				if floor_surface_y - ceiling_surface_y < ghost_height + 72.0:
					event_index += 1
					continue
				var ghost_event := {
					"event_id": event_prefix,
					"kind": "ghost",
					"x": event_x,
					"width": ghost_width,
					"height": ghost_height,
					"floor_y": floor_surface_y,
					"ceiling_y": ceiling_surface_y,
					"from_ceiling": from_ceiling,
					"blocked_lanes": int(source.get("blocked_lanes", CourseGenerator.FLOOR_LANE)),
					"trigger_lead": float(source.get("trigger_lead", 2500.0)),
					"warning_ticks": int(source.get("warning_ticks", 120)),
					"danger_ticks": int(source.get("danger_ticks", 500)),
					"fade_ticks": int(source.get("fade_ticks", 45)),
				}
				if generator_version >= CourseGenerator.GENERATOR_VERSION_16:
					ghost_event["skin_variant"] = int(source.get("skin_variant", 0))
				if generator_version >= CourseGenerator.GENERATOR_VERSION_17:
					for key in ["ghost_variant", "chase_speed", "chase_start_lag"]:
						if source.has(key):
							ghost_event[key] = source[key]
				if generator_version >= CourseGenerator.GENERATOR_VERSION_18:
					for key in ["flyby_start_lag", "flyby_speed_delta"]:
						if source.has(key):
							ghost_event[key] = source[key]
				if generator_version >= CourseGenerator.GENERATOR_VERSION_19:
					for key in ["pursuit_start_lag", "pursuit_speed_delta"]:
						if source.has(key):
							ghost_event[key] = source[key]
				resolved.append(ghost_event)
			"lava_crack":
				if generator_version < CourseGenerator.GENERATOR_VERSION_14 or BiomeRendererScript.biome_id_for_generator(course_distance + biome_start_offset, generator_version) != "lava":
					event_index += 1
					continue
				if floor_surface_y - ceiling_surface_y < 190.0:
					event_index += 1
					continue
				var crack_event := {
					"event_id": event_prefix,
					"kind": "lava_crack",
					"x": event_x,
					"y": surface_y,
					"width": clampf(float(source.get("width", 120.0)), 96.0, 150.0) if generator_version < CourseGenerator.GENERATOR_VERSION_15 else clampf(float(source.get("width", 164.0)), 150.0, 180.0),
					"hot_depth": clampf(float(source.get("hot_depth", 14.0)), 8.0, 20.0) if generator_version < CourseGenerator.GENERATOR_VERSION_15 else clampf(float(source.get("hot_depth", 18.0)), 12.0, 24.0),
					"from_ceiling": from_ceiling,
					"blocked_lanes": CourseGenerator.CEILING_LANE if from_ceiling else CourseGenerator.FLOOR_LANE,
				}
				if generator_version >= CourseGenerator.GENERATOR_VERSION_15:
					crack_event["lava_crack_revision"] = int(source.get("lava_crack_revision", 1))
					crack_event["visual_depth"] = clampf(float(source.get("visual_depth", 32.0)), 24.0, 44.0)
				if generator_version >= CourseGenerator.GENERATOR_VERSION_17 and int(source.get("lava_variant", 0)) == 1:
					for key in ["lava_variant", "pool_min_depth", "pool_max_depth", "pool_period_ticks", "pool_phase_ticks"]:
						if source.has(key):
							crack_event[key] = source[key]
				resolved.append(crack_event)
			"volcano":
				if generator_version < CourseGenerator.GENERATOR_VERSION_14 or BiomeRendererScript.biome_id_for_generator(course_distance + biome_start_offset, generator_version) != "lava":
					event_index += 1
					continue
				if floor_surface_y - ceiling_surface_y < 300.0:
					event_index += 1
					continue
				var volcano_event := {
					"event_id": event_prefix,
					"kind": "volcano",
					"x": event_x,
					"floor_y": floor_surface_y,
					"ceiling_y": ceiling_surface_y,
					"width": clampf(float(source.get("width", 120.0)), 100.0, 150.0),
					"height": clampf(float(source.get("height", 76.0)), 56.0, 96.0),
					"eruption_lead": int(source.get("eruption_lead", 1800)),
					"eruption_period_ticks": int(source.get("eruption_period_ticks", 156)),
					"projectile_lifetime_ticks": int(source.get("projectile_lifetime_ticks", 58)) if generator_version < CourseGenerator.GENERATOR_VERSION_15 else 60,
					"projectile_speed": float(source.get("projectile_speed", 330.0)),
					"projectile_vertical_speed": float(source.get("projectile_vertical_speed", 570.0)),
					"projectile_gravity": float(source.get("projectile_gravity", 1200.0)),
					"projectile_radius": float(source.get("projectile_radius", 14.0)),
					"blocked_lanes": CourseGenerator.FLOOR_LANE,
				}
				if generator_version >= CourseGenerator.GENERATOR_VERSION_15:
					volcano_event["projectile_fan_revision"] = int(source.get("projectile_fan_revision", LavaHazardModel.GEN15_FAN_REVISION))
					var arcs: Variant = source.get("projectile_arcs", LavaHazardModel.gen15_fan_arcs())
					volcano_event["projectile_arcs"] = (arcs as Array).duplicate(true) if arcs is Array else []
					volcano_event["projectile_speed"] = 450.0
					volcano_event["projectile_vertical_speed"] = 580.0
					volcano_event["projectile_gravity"] = 1100.0
					volcano_event["projectile_radius"] = 15.0
				resolved.append(volcano_event)
			_:
				push_error("Unsupported multiplayer course event kind '%s'." % kind)
		event_index += 1
	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.x), float(b.x)):
			return float(a.x) < float(b.x)
		return str(a.event_id) < str(b.event_id)
	)
	return resolved

func _surface_y_at(events: Array[Dictionary], x: float, ceiling: bool) -> float:
	var surface_y := CEILING_START_Y if ceiling else FLOOR_START_Y
	for event in events:
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				if x >= float(event.get("x", 0.0)):
					surface_y = float(event.get("end_y", surface_y))
			"slope":
				var start_x := float(event.get("start_x", 0.0))
				var end_x := float(event.get("end_x", start_x))
				if x < start_x:
					break
				if x <= end_x and end_x > start_x:
					return lerpf(float(event.get("start_y", surface_y)), float(event.get("end_y", surface_y)), (x - start_x) / (end_x - start_x))
				surface_y = float(event.get("end_y", surface_y))
	return surface_y

func _has_floor_gap_over_interval(source_events: Array[Dictionary], course_distance: float, width: float) -> bool:
	for source in source_events:
		if str(source.get("kind", "")) != "gap" or bool(source.get("from_ceiling", false)):
			continue
		var center := float(source.get("course_distance", 0.0))
		var half_width := float(source.get("width", 0.0)) * 0.5
		var gap_left := center - half_width
		var gap_right := center + half_width
		if gap_right >= course_distance - width * 0.5 and gap_left <= course_distance + width * 0.5:
			return true
	return false

func _gen18_small_block_has_supported_runner_clearance(resolved_events: Array[Dictionary], source_events: Array[Dictionary], course_distance: float, block_width: float, block_height: float) -> bool:
	# Permit only the smallest authored blocks in exceptionally narrow but flat,
	# supported corridors. Leave four pixels beyond the real runner body and
	# require both surfaces to remain continuous across the block plus runner width.
	if block_height > 82.0 or block_width <= 0.0:
		return false
	var half_span := (block_width + RunnerMotionScript.SIZE.x) * 0.5
	var start_x := PLAYER_START_X + course_distance - half_span
	var end_x := PLAYER_START_X + course_distance + half_span
	for ceiling in [false, true]:
		if _has_gap_over_interval(source_events, course_distance, block_width + RunnerMotionScript.SIZE.x, bool(ceiling)):
			return false
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(resolved_events, FLOOR_START_Y, CEILING_START_Y)
	if not bool(surface_index.call("interval_is_supported", start_x, end_x, false)) or not bool(surface_index.call("interval_is_supported", start_x, end_x, true)):
		return false
	var sample_xs: Array[float] = [start_x, end_x]
	for ceiling in [false, true]:
		for boundary in surface_index.call("support_boundaries", bool(ceiling)):
			var boundary_x := float(boundary)
			if boundary_x >= start_x and boundary_x <= end_x:
				sample_xs.append(boundary_x)
	var minimum_span := INF
	for sample_x in sample_xs:
		var floor_info: Dictionary = surface_index.call("surface_at", sample_x, false)
		var ceiling_info: Dictionary = surface_index.call("surface_at", sample_x, true)
		minimum_span = minf(minimum_span, float(floor_info.get("y", FLOOR_START_Y)) - float(ceiling_info.get("y", CEILING_START_Y)))
	return minimum_span >= block_height + float(RunnerMotionScript.SIZE.y) + 4.0

func _has_gap_over_interval(source_events: Array[Dictionary], course_distance: float, width: float, ceiling: bool) -> bool:
	for source in source_events:
		if str(source.get("kind", "")) != "gap" or bool(source.get("from_ceiling", false)) != ceiling:
			continue
		var center := float(source.get("course_distance", 0.0))
		var half_width := float(source.get("width", 0.0)) * 0.5
		if center + half_width >= course_distance - width * 0.5 and center - half_width <= course_distance + width * 0.5:
			return true
	return false
