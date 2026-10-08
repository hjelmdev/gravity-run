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
	manifest.manifest_version = 14 if generator_version >= CourseGenerator.GENERATOR_VERSION_21 else (13 if generator_version >= CourseGenerator.GENERATOR_VERSION_20 else (12 if generator_version >= CourseGenerator.GENERATOR_VERSION_19 else (11 if generator_version >= CourseGenerator.GENERATOR_VERSION_18 else (10 if generator_version >= CourseGenerator.GENERATOR_VERSION_17 else (9 if generator_version >= CourseGenerator.GENERATOR_VERSION_16 else (8 if generator_version >= CourseGenerator.GENERATOR_VERSION_15 else (7 if generator_version >= CourseGenerator.GENERATOR_VERSION_14 else (6 if generator_version >= CourseGenerator.GENERATOR_VERSION_12 else (5 if generator_version >= CourseGenerator.GENERATOR_VERSION_10 else (4 if generator_version >= CourseGenerator.GENERATOR_VERSION_9 else (3 if generator_version >= CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION else 2)))))))))))
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

## Singleplayer re-resolves the course several times per second while the
## generator keeps appending ahead of the runner. Records for source events far
## behind the generation frontier can no longer change (every look-ahead in the
## resolver is under ~500 px and new source events land at most ~1 000 px behind
## the frontier), so they are cached with the loop state and only the tail is
## resolved again. The result is identical to a full resolve; the cost no longer
## grows with how long the run has lasted.
const RUNTIME_FINAL_BEHIND_FRONTIER := 3000.0
var _runtime_cache: Dictionary = {}
## Kill switch for the incremental runtime path (full resolve when false).
var runtime_caches_enabled := true
var _runtime_epoch := 0
var _runtime_record_sources := PackedInt32Array()
var _runtime_break_index := 0
var _runtime_frontier := -INF
var _runtime_stable_records := 0

func resolve_runtime_events(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float = 0.0) -> Array[Dictionary]:
	if not runtime_caches_enabled:
		return _filter_runtime_full(_resolve_events_unsorted(source_events, course_length_px, generator_version, biome_start_offset), generator_version)
	var resolved := _resolve_runtime_raw(source_events, course_length_px, generator_version, biome_start_offset)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_17:
		return _filter_runtime_window(resolved, generator_version, course_length_px)
	_sort_resolved(resolved)
	return resolved

func _filter_runtime_full(resolved: Array[Dictionary], generator_version: int) -> Array[Dictionary]:
	_sort_resolved(resolved)
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

func clear_runtime_cache() -> void:
	_runtime_cache = {}
	_runtime_window = {}

## --- Windowed safety filters for the runtime ------------------------------
## Every filter decision only looks at records within RUNTIME_FILTER_CONTEXT px
## of the event (the longest is a Gen19 pursuit route, about 2 600 px ahead).
## Records far enough behind the generation frontier are therefore "settled":
## their per-stage decisions are memoised and their final output is kept, and
## each call only sorts and filters a fixed-size window around the frontier.
## Lane surfaces before the window are carried in as the index's initial y.
const RUNTIME_FILTER_CONTEXT := 10000.0
const RUNTIME_FILTER_SLACK := 2000.0
var _runtime_window: Dictionary = {}

func _new_runtime_window(generator_version: int) -> Dictionary:
	return {
		"version": generator_version,
		"epoch": _runtime_epoch,
		"cut": -INF,
		"settled": [] as Array[Dictionary],
		"settled_x": PackedFloat64Array(),
		"settled_src": PackedInt32Array(),
		"floor_after": PackedFloat64Array(),
		"ceiling_after": PackedFloat64Array(),
		"output": [] as Array[Dictionary],
		"output_x": PackedFloat64Array(),
		"memo": [{}, {}, {}, {}],
		"pursuit_x": PackedFloat64Array(),
		"pursuit_trigger": PackedFloat64Array(),
		"pending": [] as Array[Dictionary],
		"pending_src": {},
		"stable_seen": 0,
		"disabled": false,
	}

static func _record_min_coordinate(record: Dictionary) -> float:
	var x := float(record.get("x", 0.0))
	var result := x - absf(float(record.get("width", 0.0))) * 0.5
	if record.has("start_x"):
		result = minf(result, float(record["start_x"]))
	if record.has("end_x"):
		result = minf(result, float(record["end_x"]))
	return minf(result, x)

static func _record_max_coordinate(record: Dictionary) -> float:
	var x := float(record.get("x", 0.0))
	var result := x + absf(float(record.get("width", 0.0))) * 0.5
	if record.has("start_x"):
		result = maxf(result, float(record["start_x"]))
	if record.has("end_x"):
		result = maxf(result, float(record["end_x"]))
	return maxf(result, x)

static func _approx_tolerance(x: float) -> float:
	return maxf(absf(x) * 0.0001, 0.01) + 1.0

func _filter_runtime_window(raw: Array[Dictionary], generator_version: int, course_length_px: int) -> Array[Dictionary]:
	var w := _runtime_window
	if w.is_empty() or int(w["version"]) != generator_version or int(w["epoch"]) != _runtime_epoch:
		w = _new_runtime_window(generator_version)
		_runtime_window = w
	if bool(w["disabled"]):
		return _filter_runtime_full(raw, generator_version)
	var stable := mini(_runtime_stable_records, raw.size())
	var break_index := _runtime_break_index
	var pending: Array[Dictionary] = w["pending"]
	var pending_src: Dictionary = w["pending_src"]
	var seen := int(w["stable_seen"])
	if stable > seen:
		for index in range(seen, stable):
			pending.append(raw[index])
			pending_src[str(raw[index].get("event_id", ""))] = _runtime_record_sources[index]
		w["stable_seen"] = stable
	var settled: Array[Dictionary] = w["settled"]
	var settled_x: PackedFloat64Array = w["settled_x"]
	var settled_src: PackedInt32Array = w["settled_src"]
	var length_x := PLAYER_START_X + float(course_length_px)
	var cut := float(w["cut"])
	var cut_eff := minf(cut, length_x - RUNTIME_FILTER_CONTEXT - RUNTIME_FILTER_SLACK)
	var window_start := cut_eff - RUNTIME_FILTER_CONTEXT - RUNTIME_FILTER_SLACK
	var first_window := settled_x.bsearch(window_start, true) if is_finite(window_start) else 0
	var window: Array[Dictionary] = []
	for index in range(first_window, settled.size()):
		if settled_src[index] < break_index:
			window.append(settled[index])
	var unsettled: Array[Dictionary] = []
	for record in pending:
		if int(pending_src.get(str(record.get("event_id", "")), 1 << 30)) < break_index:
			unsettled.append(record)
	unsettled.append_array(raw.slice(stable))
	_sort_resolved(unsettled)
	if not unsettled.is_empty() and not settled.is_empty():
		var first_unsettled_x := float(unsettled[0].get("x", 0.0))
		if first_unsettled_x <= settled_x[settled_x.size() - 1] + _approx_tolerance(first_unsettled_x):
			w["disabled"] = true
			return _filter_runtime_full(raw, generator_version)
	window.append_array(unsettled)
	var floor_start := FLOOR_START_Y
	var ceiling_start := CEILING_START_Y
	if first_window > 0:
		floor_start = (w["floor_after"] as PackedFloat64Array)[first_window - 1]
		ceiling_start = (w["ceiling_after"] as PackedFloat64Array)[first_window - 1]
	var pursuit_x: PackedFloat64Array = w["pursuit_x"]
	var initial_trigger := -INF
	if is_finite(window_start):
		var pursuit_index := pursuit_x.bsearch(window_start, true) - 1
		if pursuit_index >= 0:
			initial_trigger = (w["pursuit_trigger"] as PackedFloat64Array)[pursuit_index]
	var stage_ids: Array[int] = [0]
	if generator_version >= CourseGenerator.GENERATOR_VERSION_18:
		stage_ids.append(1)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_19:
		stage_ids.append(2)
	if generator_version >= CourseGenerator.GENERATOR_VERSION_20:
		stage_ids.append(3)
	var memos: Array = w["memo"]
	var fresh: Array = [{}, {}, {}, {}]
	var kept_pursuits: Array = []
	var stage_input := window
	for stage_id in stage_ids:
		var surface_index := CourseSurfaceIndexScript.new()
		surface_index.configure(stage_input, floor_start, ceiling_start, false)
		var memo: Dictionary = memos[stage_id]
		var stage_fresh: Dictionary = fresh[stage_id]
		var output: Array[Dictionary] = []
		var last_trigger := initial_trigger
		for event in stage_input:
			var event_x := float(event.get("x", 0.0))
			var key := str(event.get("event_id", ""))
			var fate: Variant = null
			if event_x < cut_eff:
				var memo_entry: Variant = memo.get(key)
				if memo_entry != null and is_same(memo_entry[0], event):
					fate = memo_entry[1]
			if fate == null:
				match stage_id:
					0:
						fate = _gen17_biome_event_keeps(event, surface_index)
					1:
						fate = _gen18_flyby_keeps(event, surface_index)
					2:
						fate = _gen19_pursuit_fate(event, stage_input, surface_index, last_trigger)
					3:
						fate = _gen15_volcano_keeps(event, surface_index, PLAYER_START_X)
				stage_fresh[key] = [event, fate]
			if stage_id == 2:
				var pursuit_fate: Dictionary = fate
				if pursuit_fate.has("record"):
					output.append(pursuit_fate["record"])
				if pursuit_fate.has("trigger"):
					last_trigger = float(pursuit_fate["trigger"])
					kept_pursuits.append([event_x, last_trigger])
			elif bool(fate):
				output.append(event)
		stage_input = output
	var output_x: PackedFloat64Array = w["output_x"]
	var settled_output: Array[Dictionary] = w["output"]
	var output_start := output_x.bsearch(window_start, true) if is_finite(window_start) else 0
	var result: Array[Dictionary] = settled_output.slice(0, output_start)
	result.append_array(stage_input)
	_settle_runtime_window(w, raw, stable, unsettled, stage_input, fresh, kept_pursuits, length_x)
	return result

func _settle_runtime_window(w: Dictionary, raw: Array[Dictionary], stable: int, unsettled: Array[Dictionary], final_output: Array[Dictionary], fresh: Array, kept_pursuits: Array, length_x: float) -> void:
	var cut := float(w["cut"])
	var bound := minf(length_x, PLAYER_START_X + _runtime_frontier - RUNTIME_FINAL_BEHIND_FRONTIER)
	for index in range(stable, raw.size()):
		bound = minf(bound, _record_min_coordinate(raw[index]))
	var target := bound - RUNTIME_FILTER_CONTEXT - RUNTIME_FILTER_SLACK
	if not (target > cut):
		return
	var count := 0
	while count < unsettled.size() and float(unsettled[count].get("x", 0.0)) < target:
		count += 1
	# Keep a clear gap so the settled prefix always sorts before the rest.
	while count > 0 and count < unsettled.size() and float(unsettled[count].get("x", 0.0)) - float(unsettled[count - 1].get("x", 0.0)) <= _approx_tolerance(float(unsettled[count].get("x", 0.0))):
		count -= 1
	if count == 0:
		return
	var new_cut := target
	if count < unsettled.size():
		new_cut = minf(target, (float(unsettled[count - 1].get("x", 0.0)) + float(unsettled[count].get("x", 0.0))) * 0.5)
	var settled: Array[Dictionary] = w["settled"]
	var settled_x: PackedFloat64Array = w["settled_x"]
	var settled_src: PackedInt32Array = w["settled_src"]
	var floor_after: PackedFloat64Array = w["floor_after"]
	var ceiling_after: PackedFloat64Array = w["ceiling_after"]
	var pending_src: Dictionary = w["pending_src"]
	var floor_y := floor_after[floor_after.size() - 1] if floor_after.size() > 0 else FLOOR_START_Y
	var ceiling_y := ceiling_after[ceiling_after.size() - 1] if ceiling_after.size() > 0 else CEILING_START_Y
	for index in range(count):
		var record: Dictionary = unsettled[index]
		var key := str(record.get("event_id", ""))
		var kind := str(record.get("kind", ""))
		if kind in ["step", "slope", "gap"]:
			var x := float(record.get("x", 0.0))
			if _record_max_coordinate(record) - x >= RUNTIME_FILTER_SLACK or x - _record_min_coordinate(record) >= RUNTIME_FILTER_SLACK:
				w["disabled"] = true
				return
			if kind != "gap":
				if bool(record.get("from_ceiling", false)):
					ceiling_y = float(record.get("end_y", ceiling_y))
				else:
					floor_y = float(record.get("end_y", floor_y))
		settled.append(record)
		settled_x.append(float(record.get("x", 0.0)))
		settled_src.append(int(pending_src.get(key, -1)))
		pending_src.erase(key)
		floor_after.append(floor_y)
		ceiling_after.append(ceiling_y)
	w["settled_x"] = settled_x
	w["settled_src"] = settled_src
	w["floor_after"] = floor_after
	w["ceiling_after"] = ceiling_after
	var memos: Array = w["memo"]
	for stage_id in range(4):
		var memo: Dictionary = memos[stage_id]
		for entry in (fresh[stage_id] as Dictionary).values():
			var entry_x := float((entry[0] as Dictionary).get("x", 0.0))
			if entry_x >= cut and entry_x < new_cut:
				memo[str((entry[0] as Dictionary).get("event_id", ""))] = entry
	var settled_output: Array[Dictionary] = w["output"]
	var output_x: PackedFloat64Array = w["output_x"]
	for record in final_output:
		var record_x := float(record.get("x", 0.0))
		if record_x >= cut and record_x < new_cut:
			settled_output.append(record)
			output_x.append(record_x)
	w["output_x"] = output_x
	var pursuit_x: PackedFloat64Array = w["pursuit_x"]
	var pursuit_trigger: PackedFloat64Array = w["pursuit_trigger"]
	for pursuit in kept_pursuits:
		if float(pursuit[0]) >= cut and float(pursuit[0]) < new_cut:
			pursuit_x.append(float(pursuit[0]))
			pursuit_trigger.append(float(pursuit[1]))
	w["pursuit_x"] = pursuit_x
	w["pursuit_trigger"] = pursuit_trigger
	var remaining: Array[Dictionary] = []
	for record in (w["pending"] as Array):
		if pending_src.has(str(record.get("event_id", ""))):
			remaining.append(record)
	w["pending"] = remaining
	w["cut"] = new_cut

func _resolve_runtime_raw(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float) -> Array[Dictionary]:
	var cache := _runtime_cache
	var length := float(course_length_px)
	var resume_index := 0
	var identical_prefix := 0
	var cached_count := 0
	var checkpoints: Array = []
	var cache_matches := not cache.is_empty() and int(cache.get("version", -1)) == generator_version and float(cache.get("offset", NAN)) == biome_start_offset
	if cache_matches:
		var cached_sources: Array = cache["sources"]
		cached_count = cached_sources.size()
		var limit := mini(cached_count, source_events.size())
		while identical_prefix < limit and is_same(cached_sources[identical_prefix], source_events[identical_prefix]):
			identical_prefix += 1
		resume_index = identical_prefix
		# The full loop stops at the first source beyond the requested length.
		if identical_prefix > 0 and length < float(cache["prefix_max_distance"]):
			for index in range(identical_prefix):
				if float(source_events[index].get("course_distance", 0.0)) > length:
					resume_index = index
					break
	# Any loss of the cached prefix (new run, other seed/version, or a changed
	# source list) invalidates everything derived from it, including the window.
	if not cache_matches or identical_prefix < cached_count:
		_runtime_epoch += 1
	var state: Dictionary = {}
	var prefix: Array[Dictionary] = []
	var record_sources := PackedInt32Array()
	if resume_index > 0:
		# checkpoints[i] is the loop state before source i, so resume there.
		var cached_checkpoints: Array = cache["checkpoints"]
		state = cached_checkpoints[resume_index]
		prefix.assign((cache["resolved"] as Array).slice(0, int(state["resolved_count"])))
		record_sources = (cache["record_sources"] as PackedInt32Array).slice(0, int(state["resolved_count"]))
		checkpoints = cached_checkpoints.slice(0, resume_index)
	var resolved := _resolve_event_range(source_events, course_length_px, generator_version, biome_start_offset, resume_index, state, prefix, checkpoints)
	for source_index in range(resume_index, checkpoints.size()):
		var first_record := int(checkpoints[source_index]["resolved_count"])
		var end_record := int(checkpoints[source_index + 1]["resolved_count"]) if source_index + 1 < checkpoints.size() else resolved.size()
		for _record in range(first_record, end_record):
			record_sources.append(source_index)
	_runtime_record_sources = record_sources
	_runtime_break_index = checkpoints.size() - 1 if checkpoints.size() > 0 and checkpoints.size() <= source_events.size() and float(source_events[checkpoints.size() - 1].get("course_distance", 0.0)) > length else source_events.size()
	# Decide how much of this result is final for future calls.
	var prefix_max := float(cache.get("prefix_max_distance", -INF)) if identical_prefix > 0 else -INF
	var frontier := prefix_max
	for index in range(identical_prefix, source_events.size()):
		frontier = maxf(frontier, float(source_events[index].get("course_distance", 0.0)))
	_runtime_frontier = frontier
	var final_count := mini(identical_prefix, resume_index)
	var processed := mini(checkpoints.size(), source_events.size())
	var final_max := prefix_max if final_count > 0 else -INF
	while final_count < processed:
		var distance := float(source_events[final_count].get("course_distance", 0.0))
		if distance > length or distance > frontier - RUNTIME_FINAL_BEHIND_FRONTIER:
			break
		final_max = maxf(final_max, distance)
		final_count += 1
	# A shorter request (spawn lookups) must not shrink a longer cached prefix.
	var keep_previous := identical_prefix >= cached_count and cached_count > final_count
	var stable_records := prefix.size()
	if final_count < checkpoints.size() and not keep_previous:
		var final_state: Dictionary = checkpoints[final_count]
		var final_records := int(final_state["resolved_count"])
		_runtime_cache = {
			"version": generator_version,
			"offset": biome_start_offset,
			"sources": source_events.slice(0, final_count),
			"checkpoints": checkpoints.slice(0, final_count + 1),
			"resolved": resolved.slice(0, final_records),
			"record_sources": record_sources.slice(0, final_records),
			"prefix_max_distance": final_max,
		}
		stable_records = final_records
	elif not keep_previous:
		_runtime_cache = {}
		stable_records = 0
	_runtime_stable_records = stable_records
	return resolved

func filter_unsafe_gen19_pursuits(events: Array[Dictionary]) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	var last_pursuit_trigger := -INF
	for event in events:
		var fate := _gen19_pursuit_fate(event, events, surface_index, last_pursuit_trigger)
		if fate.has("record"):
			filtered.append(fate["record"])
		if fate.has("trigger"):
			last_pursuit_trigger = float(fate["trigger"])
	return filtered

## Decision for one event in filter_unsafe_gen19_pursuits. Returns "record" when
## something is emitted (the event or its fallback) and "trigger" when a kept
## pursuit updates the spacing state.
func _gen19_pursuit_fate(event: Dictionary, events: Array[Dictionary], surface_index: RefCounted, last_pursuit_trigger: float) -> Dictionary:
	# A second lane-locked chase must not snapshot the escape lane while the
	# previous one is still dangerous. At the model's maximum 800px/s this spacing
	# separates triggers by 300 ticks, beyond the 90+200 tick warning/danger window.
	# Other hazard types and the frozen Gen17/18 paths are retained unchanged.
	if str(event.get("kind", "")) != "ghost" or int(event.get("ghost_variant", 0)) != 3:
		return {"record": event}
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
		return {"record": event, "trigger": trigger_x}
	var fallback := _gen19_supported_single_lane_fallback(event, events, surface_index)
	if not fallback.is_empty():
		return {"record": fallback}
	return {}

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
		if _gen18_flyby_keeps(event, surface_index):
			filtered.append(event)
	return filtered

func _gen18_flyby_keeps(event: Dictionary, surface_index: RefCounted) -> bool:
	if str(event.get("kind", "")) != "ghost" or int(event.get("ghost_variant", 0)) != 2:
		return true
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
	return safe_both and lane_pose_stable

func _gen18_surface_stays_near(surface_index: RefCounted, start_x: float, end_x: float, ceiling: bool, reference_y: float) -> bool:
	const MAX_LANE_POSE_DELTA := 40.0
	var checks: Array[float] = [start_x, end_x]
	# Boundaries are stored sorted and unique, so the strict in-range subset is
	# already in ascending order.
	var in_range: Array[float] = surface_index.call("support_boundaries_between", start_x, end_x, ceiling, false)
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
		if _gen15_volcano_keeps(event, surface_index, course_start_x):
			filtered.append(event)
	return filtered

func _gen15_volcano_keeps(event: Dictionary, surface_index: RefCounted, course_start_x: float) -> bool:
	return not (str(event.get("kind", "")) == "volcano" and not LavaHazardModel.gen15_ceiling_route_is_supported(event, surface_index, course_start_x))

func filter_unsafe_gen17_biome_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var surface_index := CourseSurfaceIndexScript.new()
	surface_index.configure(events, FLOOR_START_Y, CEILING_START_Y)
	var filtered: Array[Dictionary] = []
	for event in events:
		if _gen17_biome_event_keeps(event, surface_index):
			filtered.append(event)
	return filtered

func _gen17_biome_event_keeps(event: Dictionary, surface_index: RefCounted) -> bool:
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
	return keep

func _make_multiplayer_ruleset(generator_version: int) -> Resource:
	var ruleset := CourseRulesetScript.new() as Resource
	ruleset.set("ruleset_id", &"multiplayer_race")
	if generator_version in [CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20, CourseGenerator.GENERATOR_VERSION_21]:
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
	var fresh: Array[Dictionary] = []
	var resolved: Array[Dictionary] = _resolve_event_range(source_events, course_length_px, generator_version, biome_start_offset, 0, {}, fresh)
	_sort_resolved(resolved)
	return resolved

func _resolve_events_unsorted(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float) -> Array[Dictionary]:
	var fresh: Array[Dictionary] = []
	return _resolve_event_range(source_events, course_length_px, generator_version, biome_start_offset, 0, {}, fresh)

static func _sort_resolved(resolved: Array[Dictionary]) -> void:
	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.x), float(b.x)):
			return float(a.x) < float(b.x)
		return str(a.event_id) < str(b.event_id)
	)

## Resolves source events from start_index onward, continuing from a state and
## resolved prefix captured earlier. Returns the resolved records in processing
## order (unsorted). When checkpoints is an Array, the loop state before each
## source index is appended to it so a later call can resume there.
func _resolve_event_range(source_events: Array[Dictionary], course_length_px: int, generator_version: int, biome_start_offset: float = 0.0, start_index: int = 0, start_state: Dictionary = {}, start_resolved: Array[Dictionary] = [], checkpoints: Variant = null) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = start_resolved
	# Surface lookups only read step/slope records of one lane. Keeping those in
	# small per-lane lists (in the same order) gives identical results without
	# rescanning every resolved hazard for every event, which made long runs
	# quadratic and caused growing frame stalls when the runtime re-resolved.
	var surface_lanes := {"synced": 0, "floor": [] as Array[Dictionary], "ceiling": [] as Array[Dictionary]}
	var floor_y := float(start_state.get("floor_y", FLOOR_START_Y))
	var ceiling_y := float(start_state.get("ceiling_y", CEILING_START_Y))
	var event_index := int(start_state.get("event_index", 0))
	for source_index in range(start_index, source_events.size()):
		var source: Dictionary = source_events[source_index]
		if checkpoints is Array:
			(checkpoints as Array).append({"resolved_count": resolved.size(), "floor_y": floor_y, "ceiling_y": ceiling_y, "event_index": event_index})
		var course_distance := float(source.get("course_distance", 0.0))
		if course_distance > float(course_length_px):
			break
		var event_x := PLAYER_START_X + course_distance
		var kind := str(source.get("kind", ""))
		var from_ceiling := bool(source.get("from_ceiling", false))
		_sync_surface_lanes(surface_lanes, resolved)
		var floor_surface_y := _surface_y_at(surface_lanes["floor"], event_x, false)
		var ceiling_surface_y := _surface_y_at(surface_lanes["ceiling"], event_x, true)
		var surface_y := _surface_y_at(surface_lanes["ceiling"] if from_ceiling else surface_lanes["floor"], event_x, from_ceiling)
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
				if generator_version in [CourseGenerator.GENERATOR_VERSION_18, CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20, CourseGenerator.GENERATOR_VERSION_21] and _gen18_small_block_has_supported_runner_clearance(resolved, source_events, course_distance, block_width, block_height):
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
				if generator_version == CourseGenerator.GENERATOR_VERSION_21 and int(source.get("barrel_variant", 0)) == 1:
					barrel_record["barrel_variant"] = 1
					barrel_record["rubber_target_x"] = PLAYER_START_X + float(source.get("rubber_target_course_distance", NAN))
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
				_sync_surface_lanes(surface_lanes, resolved)
				var saw_floor_y := _surface_y_at(surface_lanes["floor"], event_x, false)
				var saw_ceiling_y := _surface_y_at(surface_lanes["ceiling"], event_x, true)
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
	return resolved

func _sync_surface_lanes(lanes: Dictionary, resolved: Array[Dictionary]) -> void:
	var index := int(lanes["synced"])
	while index < resolved.size():
		var event: Dictionary = resolved[index]
		var kind := str(event.get("kind", ""))
		if kind == "step" or kind == "slope":
			(lanes["ceiling"] if bool(event.get("from_ceiling", false)) else lanes["floor"]).append(event)
		index += 1
	lanes["synced"] = index

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
