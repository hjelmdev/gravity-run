extends RefCounted
class_name CourseGenerator

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const BiomeEncounterMixScript := preload("res://systems/biome_encounter_mix.gd")
const LavaHazardModelScript := preload("res://systems/lava_hazard_model.gd")
const RunnerMotionScript := preload("res://systems/runner_motion.gd")
## Deterministic, data-driven encounter planning with a route-feasibility check.
## New hazard profiles register their own blocked-lane forecasts; the planner
## rejects overlapping/no-exit patterns and spaces lane changes conservatively.

const FLOOR_LANE := 1
const CEILING_LANE := 2
const BOTH_LANES := FLOOR_LANE | CEILING_LANE
const SLOPE_WIDTH := 440.0
const SPIKE_GROUP_SPACING := 32.0
const STEP_SPIKE_CLEARANCE := 32.0
const SPIKE_WIDTH := 28.0
const SPIKE_HEIGHT := 32.0
const BASE_EVENT_SPACING := 390.0
# Base game tops out at 500 px/s. Reserve for a future 1.5x speed effect too.
const MAX_RUN_SPEED := 750.0
const GHOST_FLYBY_MAX_RUN_SPEED := 800.0
## Deterministic planning geometry shared across viewport sizes and devices.
const REFERENCE_TRACK_HEIGHT := 900.0
const EVENT_SPAWN_LEAD_DISTANCE := 820.0
const EVENT_SPAWN_MARGIN := 48.0
const PLAYER_FLIP_SPEED := 680.0
const PLAYER_GRAVITY := 1900.0
const PLAYER_FLIP_COOLDOWN := 0.42
const SWITCH_SAFETY_MARGIN := 0.12
const PLAN_RETRY_SPACING := 48.0
const BARREL_SPEED_MULTIPLIER := 1.4
const V7_MIN_ROCK_DISTANCE := 2000.0
const ROCK_SAFE_GENERATOR_VERSION := 7
const GENERATOR_VERSION_8 := 8
const GENERATOR_VERSION_9 := 9
const GENERATOR_VERSION_10 := 10
const GENERATOR_VERSION_11 := 11
const GENERATOR_VERSION_12 := 12
const GENERATOR_VERSION_13 := 13
const GENERATOR_VERSION_14 := 14
const GENERATOR_VERSION_15 := 15
const GENERATOR_VERSION_16 := 16
const GENERATOR_VERSION_17 := 17
const GENERATOR_VERSION_18 := 18
const GENERATOR_VERSION_19 := 19
const GENERATOR_VERSION_20 := 20
const GENERATOR_VERSION_21 := 21
const GEN19_PURSUIT_MIN_TRIGGER_GAP := 4000.0
const GEN14_RHYTHM_SPACING_DELTAS := [-120.0, -120.0, 240.0]
const GEN14_RHYTHM_BASE_SPACING_SCALE := 1.22
const GEN16_RHYTHM_SPACING_DELTAS := [-90.0, -90.0, 180.0]
const GEN16_RHYTHM_BASE_SPACING_SCALE := 0.98
const GEN20_RHYTHM_SPACING_DELTAS := [-60.0, -60.0, 120.0]
const GEN20_NARROW_RHYTHM_BASE_SPACING_SCALE := 0.82
const GEN20_NARROW_SPAN_MAX := 300.0
const GEN20_ORDINARY_BARREL_EXTRA_SEPARATION := 500.0
const GEN20_SPIKED_BARREL_CHANCE := 0.25
const COURSE_FLOOR_START_Y := 460.0
const COURSE_CEILING_START_Y := 80.0
const GEN20_SLOPE_WIDTH := 440.0
const PREVIOUS_CURRENT_GENERATOR_VERSION := GENERATOR_VERSION_19
const GENERATOR_VERSION := GENERATOR_VERSION_21
const PUBLISHED_SHARED_GENERATOR_VERSION := 5
const LEGACY_GENERATOR_VERSION := 3
const PREVIOUS_GENERATOR_VERSION := 4
const GENERATOR_VERSION_6 := 6
const CourseHazardProfileScript = preload("res://systems/course_hazard_profile.gd")
const CourseDifficultyProfileScript = preload("res://systems/course_difficulty_profile.gd")

var _rng := RandomNumberGenerator.new()
var _profiles: Array[CourseHazardProfile] = []
var _barrel_profile: CourseHazardProfile
var _events: Array[Dictionary] = []
var _next_event_distance := 1050.0
var _next_spawn_index := 0
var _rhythm_event_index := 0
var _seed := 0
var _generator_version := GENERATOR_VERSION
var _biome_start_offset := 0.0
var _difficulty: Resource
var _spawn_lead_distance := 0.0
var _configuration_failed := false
var _spiked_barrel_corridors: Array[Dictionary] = []
var _gen16_barrel_meeting_windows: Array[Dictionary] = []
var _committed_sweep: Dictionary = {}
var _pending_sweep_events: Array[Dictionary] = []
# Indexes over committed events for checks that run for every candidate shift.
var _max_pursuit_trigger := -INF
var _lava_crack_events: Array[Dictionary] = []
# Spiked-barrel corridors and Gen16 meeting windows ordered by their end x, so
# overlap tests only visit entries that can still reach the candidate.
var _corridors_by_end: Array[Dictionary] = []
var _corridor_ends := PackedFloat64Array()
var _meeting_windows_by_end: Array[Dictionary] = []
var _meeting_window_ends := PackedFloat64Array()
# Cumulative lane state for _is_narrow_supported_corridor over an event prefix.
var _narrow_prefix := {}
# Ceiling-lane threat intervals of committed events, ordered by interval end.
var _ceiling_threat_ends := PackedFloat64Array()
var _ceiling_threat_starts := PackedFloat64Array()
var _indexed_events: Array = []
var _indexed_event_count := 0
var _indexed_windows: Array = []
var _indexed_corridors: Array = []
var _generation_stats := {"candidate_attempts": 0, "route_rejections": 0, "biome_rejections": 0, "pursuit_profile_fallbacks": 0, "accepted_events": 0, "fallback_events": 0}

## Spawn course events fully beyond the viewport so their geometry enters smoothly.
## The canonical lead remains a lower bound for stable planning on small screens.
static func get_viewport_spawn_lead_distance(viewport_width: float, player_x: float, largest_event_width: float = 440.0) -> float:
	return maxf(EVENT_SPAWN_LEAD_DISTANCE, viewport_width - player_x + largest_event_width * 0.5 + EVENT_SPAWN_MARGIN)

func configure_ruleset(ruleset: Resource, generator_version: int = GENERATOR_VERSION, additional_profiles: Array[CourseHazardProfile] = []) -> bool:
	_configuration_failed = false
	if not configure_default_profiles(generator_version):
		_configuration_failed = true
		return false
	for profile in additional_profiles:
		register_profile(profile)
	var validation_error := ""
	if ruleset == null or not ruleset.has_method("validate") or not ruleset.has_method("create_difficulty_profile"):
		validation_error = "A valid course-generation ruleset is required."
	else:
		validation_error = str(ruleset.call("validate", _profiles))
	if not validation_error.is_empty():
		push_error(validation_error)
		_profiles.clear()
		_difficulty = null
		_configuration_failed = true
		return false
	var selected_profiles: Array[CourseHazardProfile] = []
	for profile in _profiles:
		var selected: bool = bool(ruleset.get("include_all_profiles")) or ruleset.get("included_profile_ids").has(String(profile.profile_id))
		var multipliers: Dictionary = ruleset.get("profile_weight_multipliers")
		var weight_multiplier := float(multipliers.get(String(profile.profile_id), 1.0))
		if selected and weight_multiplier > 0.0:
			selected_profiles.append(profile)
	_profiles.clear()
	_barrel_profile = null
	for profile in selected_profiles:
		if generator_version >= 4 and profile.event_kind == &"barrels":
			_barrel_profile = profile
		else:
			_profiles.append(profile)
	if _profiles.is_empty():
		push_error("The active ruleset must include at least one non-barrel encounter.")
		_configuration_failed = true
		return false
	_difficulty = ruleset.call("create_difficulty_profile")
	return true

func configure_run_definition(definition: Resource, additional_profiles: Array[CourseHazardProfile] = []) -> bool:
	_configuration_failed = false
	if definition == null or not definition.has_method("validate"):
		push_error("A CourseRunDefinition is required to configure a deterministic run.")
		_configuration_failed = true
		return false
	var validation_error := str(definition.call("validate"))
	if not validation_error.is_empty():
		push_error(validation_error)
		_configuration_failed = true
		return false
	if not configure_ruleset(definition.get("ruleset"), int(definition.get("generator_version")), additional_profiles):
		return false
	reset(int(definition.get("seed_value")))
	return true

func set_difficulty_profile(profile: Resource) -> void:
	_difficulty = profile

func configure_default_profiles(generator_version: int = GENERATOR_VERSION) -> bool:
	_configuration_failed = false
	_generator_version = generator_version
	if generator_version not in [GENERATOR_VERSION, GENERATOR_VERSION_20, GENERATOR_VERSION_19, GENERATOR_VERSION_18, GENERATOR_VERSION_17, GENERATOR_VERSION_16, GENERATOR_VERSION_15, GENERATOR_VERSION_14, GENERATOR_VERSION_13, GENERATOR_VERSION_12, GENERATOR_VERSION_11, GENERATOR_VERSION_10, GENERATOR_VERSION_9, GENERATOR_VERSION_8, ROCK_SAFE_GENERATOR_VERSION, GENERATOR_VERSION_6, PUBLISHED_SHARED_GENERATOR_VERSION, PREVIOUS_GENERATOR_VERSION, LEGACY_GENERATOR_VERSION]:
		push_error("Unsupported course generator version: %d" % generator_version)
		return false
	_profiles.clear()
	_barrel_profile = null
	_difficulty = null
	var spikes_weight := 3.35 if generator_version >= GENERATOR_VERSION_9 else 3.0
	_profiles.append(_make_profile(&"spike_group", &"spikes", spikes_weight, BOTH_LANES, Vector2(124.0, 188.0), Vector2i(4, 6), PackedFloat32Array([32.0])))
	_profiles.append(_make_profile(&"block", &"block", 2.3, BOTH_LANES, Vector2(44.0, 64.0), Vector2i(1, 1), PackedFloat32Array([82.0, 132.0, 168.0])))
	var barrel_weight := 1.7 if generator_version == LEGACY_GENERATOR_VERSION else (13.0 if generator_version >= GENERATOR_VERSION_9 else 12.0)
	var barrel_profile := _make_profile(&"barrel_chain", &"barrels", barrel_weight, FLOOR_LANE, Vector2(HazardRules.BARREL_WIDTH, 194.0), Vector2i(1, 3), PackedFloat32Array([HazardRules.BARREL_WIDTH, 76.0]))
	barrel_profile.motion_speed_min = BARREL_SPEED_MULTIPLIER
	barrel_profile.motion_speed_max = BARREL_SPEED_MULTIPLIER
	_profiles.append(barrel_profile)
	_profiles.append(_make_profile(&"floor_gap", &"gap", 0.8, FLOOR_LANE, Vector2(150.0, 190.0), Vector2i(1, 1), PackedFloat32Array([0.0])))
	_profiles.append(_make_profile(&"ceiling_gap", &"gap", 0.8, CEILING_LANE, Vector2(150.0, 190.0), Vector2i(1, 1), PackedFloat32Array([0.0])))
	# Terrain changes are part of the course rhythm, not rare decoration.
	_profiles.append(_make_profile(&"terrain_step", &"step", 1.8, BOTH_LANES, Vector2(36.0, 240.0), Vector2i(1, 1), PackedFloat32Array([72.0, 108.0, 148.0, 184.0])))
	_profiles.append(_make_profile(&"terrain_slope", &"slope", 1.5, BOTH_LANES, Vector2(440.0, 440.0), Vector2i(1, 1), PackedFloat32Array([64.0, 100.0, 140.0, 176.0])))
	if generator_version >= PUBLISHED_SHARED_GENERATOR_VERSION:
		var rock_weight := 1.8 if generator_version >= GENERATOR_VERSION_9 else (1.6 if generator_version >= ROCK_SAFE_GENERATOR_VERSION else (1.0 if generator_version >= GENERATOR_VERSION_6 else 0.22))
		_profiles.append(_make_profile(&"falling_rock", &"rock", rock_weight, FLOOR_LANE, Vector2(90.0, 90.0), Vector2i(1, 1), PackedFloat32Array([100.0])))
		if generator_version >= GENERATOR_VERSION_9:
			_profiles.append(_make_profile(&"saw_blade", &"saw", 0.65, BOTH_LANES, Vector2(64.0, 64.0), Vector2i(1, 1), PackedFloat32Array([60.0])))
		if generator_version >= GENERATOR_VERSION_11:
			_profiles.append(_make_profile(&"haunted_ghost", &"ghost", 0.85, BOTH_LANES, Vector2(72.0, 96.0), Vector2i(1, 1), PackedFloat32Array([96.0])))
		if generator_version >= GENERATOR_VERSION_14:
			var crack_width := Vector2(150.0, 176.0) if generator_version >= GENERATOR_VERSION_15 else Vector2(104.0, 136.0)
			_profiles.append(_make_profile(&"lava_crack", &"lava_crack", 1.2, BOTH_LANES, crack_width, Vector2i(1, 1), PackedFloat32Array([18.0])))
			_profiles.append(_make_profile(&"lava_volcano", &"volcano", 0.85, FLOOR_LANE, Vector2(104.0, 136.0), Vector2i(1, 1), PackedFloat32Array([72.0])))
		if generator_version >= GENERATOR_VERSION_17:
			_profiles.append(_make_profile(&"haunted_chaser", &"ghost", 0.7, FLOOR_LANE, Vector2(72.0, 72.0), Vector2i(1, 1), PackedFloat32Array([96.0])))
			_profiles.append(_make_profile(&"cave_icicle", &"rock", 0.95, CEILING_LANE, Vector2(72.0, 72.0), Vector2i(1, 1), PackedFloat32Array([112.0])))
			_profiles.append(_make_profile(&"lava_tidal_pool", &"lava_crack", 0.9, FLOOR_LANE, Vector2(150.0, 180.0), Vector2i(1, 1), PackedFloat32Array([22.0])))
	return true

func get_profile_catalog(generator_version: int = GENERATOR_VERSION) -> Array[CourseHazardProfile]:
	configure_default_profiles(generator_version)
	return _profiles.duplicate()

func register_profile(profile: CourseHazardProfile) -> void:
	if profile == null or profile.profile_id == StringName() or profile.weight <= 0.0:
		return
	_profiles.append(profile)

func reset(seed: int = 0) -> void:
	_seed = seed
	_biome_start_offset = BiomeRenderer.start_biome_offset_for_seed(seed, _generator_version)
	_generation_stats = {"candidate_attempts": 0, "route_rejections": 0, "biome_rejections": 0, "pursuit_profile_fallbacks": 0, "accepted_events": 0, "fallback_events": 0}
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	_events.clear()
	_invalidate_committed_sweep()
	_spiked_barrel_corridors.clear()
	_gen16_barrel_meeting_windows.clear()
	_next_event_distance = 1400.0 if _generator_version >= PUBLISHED_SHARED_GENERATOR_VERSION else 1050.0
	_next_spawn_index = 0
	_rhythm_event_index = 0

func ensure_horizon(horizon_distance: float, _current_speed: float, _track_height: float = REFERENCE_TRACK_HEIGHT, _spawn_lead_distance: float = EVENT_SPAWN_LEAD_DISTANCE) -> void:
	_spawn_lead_distance = EVENT_SPAWN_LEAD_DISTANCE
	for profile in _profiles:
		profile.spawn_lead_distance = _spawn_lead_distance
	if _profiles.is_empty():
		if _configuration_failed:
			return
		configure_default_profiles()
		for profile in _profiles:
			profile.spawn_lead_distance = _spawn_lead_distance
	while _next_event_distance < horizon_distance and not _configuration_failed:
		_append_feasible_event(MAX_RUN_SPEED, REFERENCE_TRACK_HEIGHT)

func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while _next_spawn_index < _events.size() and float(_events[_next_spawn_index]["course_distance"]) <= spawn_line_distance:
		ready.append(_events[_next_spawn_index])
		_next_spawn_index += 1
	return ready

func get_planned_events() -> Array[Dictionary]:
	return _events.duplicate()

func get_generation_stats() -> Dictionary:
	return _generation_stats.duplicate(true)

func get_switch_clearance_distance(speed: float, track_height: float = 540.0) -> float:
	var travel_distance := maxf(track_height - 112.0 - 44.0, 0.0)
	var travel_time := (-PLAYER_FLIP_SPEED + sqrt(PLAYER_FLIP_SPEED * PLAYER_FLIP_SPEED + 2.0 * PLAYER_GRAVITY * travel_distance)) / PLAYER_GRAVITY
	var margin_scale := float(_difficulty.get("reaction_margin")) if _difficulty != null else 1.0
	var switch_time := maxf(PLAYER_FLIP_COOLDOWN, travel_time) + SWITCH_SAFETY_MARGIN * margin_scale
	return maxf(speed, MAX_RUN_SPEED) * switch_time

func _get_rock_switch_clearance_distance(track_height: float) -> float:
	var travel_distance := maxf(track_height - 112.0 - 44.0, 0.0)
	var travel_time := (-PLAYER_FLIP_SPEED + sqrt(PLAYER_FLIP_SPEED * PLAYER_FLIP_SPEED + 2.0 * PLAYER_GRAVITY * travel_distance)) / PLAYER_GRAVITY
	var margin_scale := float(_difficulty.get("reaction_margin")) if _difficulty != null else 1.0
	return MAX_RUN_SPEED * (PLAYER_FLIP_COOLDOWN * 2.0 + travel_time + SWITCH_SAFETY_MARGIN * margin_scale)

func get_density_adjusted_spacing(conservative_spacing: float) -> float:
	var density := float(_difficulty.get("event_density")) if _difficulty != null else 1.0
	return maxf(180.0, conservative_spacing / maxf(density, 0.1))

func is_plan_solvable(events: Array[Dictionary], switch_clearance: float = -1.0) -> bool:
	if events.is_empty():
		return true
	var clearance := switch_clearance if switch_clearance >= 0.0 else get_switch_clearance_distance(MAX_RUN_SPEED)
	var edges: Array[Dictionary] = []
	for event in events:
		_append_plan_edges(edges, event, clearance)
	if edges.is_empty():
		return true
	edges.sort_custom(_edge_x_less)
	var state := _new_sweep_state()
	state["clearance"] = clearance
	return bool(_sweep_plan_edges(edges, 0, state).get("solvable", true))

## Route edges for one event. The sweep only depends on the sorted edge x values
## and the multiset of edges in each equal-x group, so edges can be cached per
## committed plan and merged with a candidate's edges without changing results.
func _append_plan_edges(edges: Array[Dictionary], event: Dictionary, clearance: float) -> void:
	for threat in event.get("threats", []):
		var start := float(threat.get("start", 0.0))
		var end := float(threat.get("end", start))
		if end <= start:
			continue
		var mask := int(threat.get("blocked_lanes", 0)) & BOTH_LANES
		if mask == 0:
			continue
		var edge_clearance := float(threat.get("switch_clearance", 0.0))
		edges.append({"x": start, "floor_delta": 1 if mask & FLOOR_LANE else 0, "ceiling_delta": 1 if mask & CEILING_LANE else 0, "switch_clearance": edge_clearance})
		edges.append({"x": end, "floor_delta": -1 if mask & FLOOR_LANE else 0, "ceiling_delta": -1 if mask & CEILING_LANE else 0, "switch_clearance": 0.0})
	if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) in [2, 3]:
		# Candidate events are checked before manifest resolution, when their
		# canonical position is course_distance rather than world-space x.
		var event_x := float(event.get("course_distance", event.get("x", 0.0)))
		var trigger_x := event_x - float(event.get("trigger_lead", 1500.0))
		var warning_ticks := int(event.get("warning_ticks", 72))
		var danger_ticks := int(event.get("danger_ticks", 96))
		var speed_delta := float(event.get("pursuit_speed_delta", event.get("flyby_speed_delta", 500.0)))
		var danger_start := trigger_x + GHOST_FLYBY_MAX_RUN_SPEED * float(warning_ticks) / 60.0
		var danger_end := danger_start + (GHOST_FLYBY_MAX_RUN_SPEED + speed_delta) * float(danger_ticks) / 60.0
		var event_id := str(event.get("event_id", "%s@%.3f" % [str(event.get("id", "ghost")), float(event.get("course_distance", event.get("x", 0.0)))]))
		edges.append({"x": trigger_x, "special": "ghost_snapshot", "event_id": event_id})
		edges.append({"x": danger_start, "special": "ghost_lock", "event_id": event_id, "switch_clearance": clearance})
		edges.append({"x": danger_end, "special": "ghost_release", "event_id": event_id})

static func _edge_x_less(a: Dictionary, b: Dictionary) -> bool:
	return float(a["x"]) < float(b["x"])

static func _new_sweep_state() -> Dictionary:
	return {"current_lane": FLOOR_LANE, "last_threat_end": 0.0, "floor_count": 0, "ceiling_count": 0, "ghost_target_lanes": {}}

## Runs the lane sweep from edge_index with the given state. When checkpoints is
## an Array, the state before each equal-x group is recorded as
## [group_start_index, group_start_x, state_copy] so a later trial can resume.
func _sweep_plan_edges(edges: Array[Dictionary], edge_index: int, state: Dictionary, checkpoints: Variant = null) -> Dictionary:
	var current_lane := int(state["current_lane"])
	var last_threat_end := float(state["last_threat_end"])
	var floor_count := int(state["floor_count"])
	var ceiling_count := int(state["ceiling_count"])
	var ghost_target_lanes: Dictionary = (state["ghost_target_lanes"] as Dictionary).duplicate()
	while edge_index < edges.size() - 1:
		var start := float(edges[edge_index]["x"])
		if checkpoints is Array:
			(checkpoints as Array).append([edge_index, start, {"current_lane": current_lane, "last_threat_end": last_threat_end, "floor_count": floor_count, "ceiling_count": ceiling_count, "ghost_target_lanes": ghost_target_lanes.duplicate()}])
		var transition_clearance := float(state["clearance"])
		while edge_index < edges.size() and is_equal_approx(float(edges[edge_index]["x"]), start):
			var edge: Dictionary = edges[edge_index]
			var special := str(edge.get("special", ""))
			var event_id := str(edge.get("event_id", ""))
			if special == "ghost_snapshot":
				ghost_target_lanes[event_id] = current_lane
			elif special == "ghost_lock":
				var target_lane := int(ghost_target_lanes.get(event_id, 0))
				if target_lane == FLOOR_LANE:
					floor_count += 1
				elif target_lane == CEILING_LANE:
					ceiling_count += 1
			elif special == "ghost_release":
				var target_lane := int(ghost_target_lanes.get(event_id, 0))
				if target_lane == FLOOR_LANE:
					floor_count -= 1
				elif target_lane == CEILING_LANE:
					ceiling_count -= 1
			floor_count += int(edge.get("floor_delta", 0))
			ceiling_count += int(edge.get("ceiling_delta", 0))
			transition_clearance = maxf(transition_clearance, float(edges[edge_index].get("switch_clearance", 0.0)))
			edge_index += 1
		if edge_index >= edges.size():
			break
		var end := float(edges[edge_index]["x"])
		var blocked_mask := (FLOOR_LANE if floor_count > 0 else 0) | (CEILING_LANE if ceiling_count > 0 else 0)
		if blocked_mask == BOTH_LANES:
			return {"solvable": false, "fail_x": start}
		if blocked_mask == 0:
			continue

		var required_lane := CEILING_LANE if blocked_mask & FLOOR_LANE else FLOOR_LANE
		if required_lane != current_lane:
			if start - last_threat_end < transition_clearance:
				return {"solvable": false, "fail_x": start}
			current_lane = required_lane
		last_threat_end = end
	return {"solvable": true}

## Equivalent to is_plan_solvable(_events + [candidate], clearance), but reuses
## a sorted edge list and per-group sweep checkpoints for the committed plan.
## Without this the generator re-sorted every edge since the run started for
## every candidate shift, which grew into multi-frame stalls on long web runs.
func _is_trial_solvable(candidate: Dictionary, clearance: float) -> bool:
	var candidate_edges: Array[Dictionary] = []
	_append_plan_edges(candidate_edges, candidate, clearance)
	if candidate_edges.is_empty():
		if _events.is_empty():
			return true
	_ensure_committed_sweep(clearance)
	if candidate_edges.is_empty():
		return bool(_committed_sweep.get("solvable", true))
	candidate_edges.sort_custom(_edge_x_less)
	var committed: Array[Dictionary] = _committed_sweep["edges"]
	var checkpoints: Array = _committed_sweep["checkpoints"]
	var first_candidate_x := float(candidate_edges[0]["x"])
	# Resume before the last committed group that starts safely before every
	# candidate edge (well outside is_equal_approx tolerance), so all earlier
	# groups and their interval ends are untouched by the candidate.
	var margin := maxf(64.0, absf(first_candidate_x) * 0.001)
	var low := 0
	var high := checkpoints.size() - 1
	var resume := -1
	while low <= high:
		var mid := (low + high) >> 1
		if float(checkpoints[mid][1]) < first_candidate_x - margin:
			resume = mid
			low = mid + 1
		else:
			high = mid - 1
	var resume_index := 0
	var resume_state := _new_sweep_state()
	if resume >= 0:
		resume_index = int(checkpoints[resume][0])
		resume_state = (checkpoints[resume][2] as Dictionary)
		if not bool(_committed_sweep.get("solvable", true)) and float(_committed_sweep.get("fail_x", INF)) < float(checkpoints[resume][1]):
			return false
	var state := resume_state.duplicate()
	state["clearance"] = clearance
	# Merge the committed tail with the candidate edges. Order inside an equal-x
	# group does not affect the sweep, so any stable merge is equivalent.
	var tail: Array[Dictionary] = []
	var committed_index := resume_index
	var candidate_index := 0
	while committed_index < committed.size() or candidate_index < candidate_edges.size():
		if candidate_index >= candidate_edges.size() or (committed_index < committed.size() and float(committed[committed_index]["x"]) <= float(candidate_edges[candidate_index]["x"])):
			tail.append(committed[committed_index])
			committed_index += 1
		else:
			tail.append(candidate_edges[candidate_index])
			candidate_index += 1
	if resume_index == 0 and tail.is_empty():
		return true
	return bool(_sweep_plan_edges(tail, 0, state).get("solvable", true))

func _invalidate_committed_sweep() -> void:
	_committed_sweep = {}
	_pending_sweep_events.clear()
	_max_pursuit_trigger = -INF
	_lava_crack_events.clear()
	_corridors_by_end.clear()
	_corridor_ends = PackedFloat64Array()
	_meeting_windows_by_end.clear()
	_meeting_window_ends = PackedFloat64Array()
	_narrow_prefix = {}
	_ceiling_threat_ends = PackedFloat64Array()
	_ceiling_threat_starts = PackedFloat64Array()
	_indexed_events = _events
	_indexed_event_count = _events.size()

func _ensure_committed_sweep(clearance: float) -> void:
	var cache_matches := not _committed_sweep.is_empty() and float(_committed_sweep.get("clearance", NAN)) == clearance and is_same(_committed_sweep.get("events"), _events)
	if cache_matches and int(_committed_sweep.get("event_count", -1)) == _events.size():
		_pending_sweep_events.clear()
		return
	if cache_matches and int(_committed_sweep.get("event_count", -1)) + _pending_sweep_events.size() == _events.size():
		_extend_committed_sweep(clearance)
		return
	_pending_sweep_events.clear()
	var edges: Array[Dictionary] = []
	for event in _events:
		_append_plan_edges(edges, event, clearance)
	edges.sort_custom(_edge_x_less)
	var checkpoints: Array = []
	var state := _new_sweep_state()
	state["clearance"] = clearance
	var result := _sweep_plan_edges(edges, 0, state, checkpoints)
	_committed_sweep = {"clearance": clearance, "event_count": _events.size(), "events": _events, "edges": edges, "checkpoints": checkpoints, "solvable": bool(result.get("solvable", true)), "fail_x": float(result.get("fail_x", INF))}

## Adds the edges of events accepted since the last sweep. New events sit near
## the generation frontier, so the committed sweep is resumed from the last
## checkpoint safely before their first edge instead of being rebuilt.
func _extend_committed_sweep(clearance: float) -> void:
	var new_edges: Array[Dictionary] = []
	for event in _pending_sweep_events:
		_append_plan_edges(new_edges, event, clearance)
	_pending_sweep_events.clear()
	var committed: Array[Dictionary] = _committed_sweep["edges"]
	var checkpoints: Array = _committed_sweep["checkpoints"]
	if new_edges.is_empty():
		_committed_sweep["event_count"] = _events.size()
		return
	new_edges.sort_custom(_edge_x_less)
	var first_new_x := float(new_edges[0]["x"])
	var margin := maxf(64.0, absf(first_new_x) * 0.001)
	var low := 0
	var high := checkpoints.size() - 1
	var resume := -1
	while low <= high:
		var mid := (low + high) >> 1
		if float(checkpoints[mid][1]) < first_new_x - margin:
			resume = mid
			low = mid + 1
		else:
			high = mid - 1
	var resume_index := 0
	var state := _new_sweep_state()
	if resume >= 0:
		resume_index = int(checkpoints[resume][0])
		state = (checkpoints[resume][2] as Dictionary).duplicate()
	state["clearance"] = clearance
	var merged: Array[Dictionary] = committed.slice(0, resume_index)
	var committed_index := resume_index
	var new_index := 0
	while committed_index < committed.size() or new_index < new_edges.size():
		if new_index >= new_edges.size() or (committed_index < committed.size() and float(committed[committed_index]["x"]) <= float(new_edges[new_index]["x"])):
			merged.append(committed[committed_index])
			committed_index += 1
		else:
			merged.append(new_edges[new_index])
			new_index += 1
	var kept_checkpoints: Array = checkpoints.slice(0, maxi(resume, 0))
	var previously_failed := not bool(_committed_sweep.get("solvable", true))
	var previous_fail_x := float(_committed_sweep.get("fail_x", INF))
	var tail_checkpoints: Array = []
	var result := _sweep_plan_edges(merged, resume_index, state, tail_checkpoints)
	kept_checkpoints.append_array(tail_checkpoints)
	var solvable := bool(result.get("solvable", true))
	var fail_x := float(result.get("fail_x", INF))
	if previously_failed and resume >= 0 and previous_fail_x < float(checkpoints[resume][1]):
		solvable = false
		fail_x = previous_fail_x
	_committed_sweep = {"clearance": clearance, "event_count": _events.size(), "events": _events, "edges": merged, "checkpoints": kept_checkpoints, "solvable": solvable, "fail_x": fail_x}

func _append_feasible_event(speed: float, track_height: float) -> void:
	var spacing := BASE_EVENT_SPACING
	var clearance := get_switch_clearance_distance(speed, track_height)
	for _attempt in range(64):
		_generation_stats["candidate_attempts"] = int(_generation_stats.get("candidate_attempts", 0)) + 1
		var candidate_biome := _biome_id_at(_next_event_distance) if _generator_version >= GENERATOR_VERSION_12 else ""
		var profile := _pick_profile(_next_event_distance)
		if profile == null:
			break
		var candidate := profile.create_event(_rng, _next_event_distance, _difficulty, _preferred_lane())
		_apply_generator_timing(candidate)
		if _generator_version in [GENERATOR_VERSION_19, GENERATOR_VERSION_20, GENERATOR_VERSION_21] and _gen19_pursuit_trigger_is_too_close(candidate):
			var replacement_profile := _pick_gen19_non_pursuit_profile(_next_event_distance)
			if replacement_profile != null:
				profile = replacement_profile
				candidate = profile.create_event(_rng, _next_event_distance, _difficulty, _preferred_lane())
				_apply_generator_timing(candidate)
				_generation_stats["pursuit_profile_fallbacks"] = int(_generation_stats.get("pursuit_profile_fallbacks", 0)) + 1
		if str(candidate.get("kind", "")) == "ghost" and _biome_id_at(float(candidate.get("course_distance", 0.0))) != "haunted":
			_generation_stats["biome_rejections"] = int(_generation_stats.get("biome_rejections", 0)) + 1
			# Gen19 retries a haunted-only pick at the same deterministic slot.
			# Older generator contracts keep their historical skip behavior.
			if _generator_version not in [GENERATOR_VERSION_19, GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
				_next_event_distance += PLAN_RETRY_SPACING
				spacing += PLAN_RETRY_SPACING
			continue
		var candidate_is_rock := str(candidate.get("kind", "")) == "rock"
		if candidate_is_rock and _generator_version >= ROCK_SAFE_GENERATOR_VERSION:
			_next_event_distance = maxf(_next_event_distance, V7_MIN_ROCK_DISTANCE)
			candidate["course_distance"] = _next_event_distance
		var candidate_clearance := maxf(clearance, _get_rock_switch_clearance_distance(track_height)) if candidate_is_rock else clearance
		var intrinsic_probe: Dictionary = candidate.duplicate()
		intrinsic_probe["course_distance"] = 1000000.0
		intrinsic_probe["threats"] = profile.build_threat_intervals(intrinsic_probe)
		_apply_rock_switch_clearance(intrinsic_probe, candidate_clearance if candidate_is_rock else 0.0)
		if not is_plan_solvable([intrinsic_probe], clearance):
			_generation_stats["route_rejections"] = int(_generation_stats.get("route_rejections", 0)) + 1
			# A profile whose own phases leave no route cannot be repaired by
			# shifting it; skip it instead of creating an arbitrary empty stretch.
			spacing += PLAN_RETRY_SPACING
			continue
		for _shift in range(128):
			if _generator_version >= GENERATOR_VERSION_12 and _biome_id_at(_next_event_distance) != candidate_biome:
				_generation_stats["biome_rejections"] = int(_generation_stats.get("biome_rejections", 0)) + 1
				break
			candidate["course_distance"] = _next_event_distance
			if _candidate_crosses_spiked_barrel_corridor(candidate):
				_next_event_distance += PLAN_RETRY_SPACING
				continue
			candidate["threats"] = profile.build_threat_intervals(candidate)
			_apply_rock_switch_clearance(candidate, candidate_clearance if candidate_is_rock else 0.0)
			if _is_trial_solvable(candidate, clearance):
				var phase := _rhythm_event_index % GEN14_RHYTHM_SPACING_DELTAS.size()
				if _generator_version >= GENERATOR_VERSION_14:
					candidate["rhythm_phase"] = phase
				_insert_generated_event(candidate)
				_generation_stats["accepted_events"] = int(_generation_stats.get("accepted_events", 0)) + 1
				var widest := 0.0
				for threat in candidate["threats"]:
					widest = maxf(widest, float(threat["end"]) - float(threat["start"]))
				var conservative_spacing := maxf(spacing, widest + candidate_clearance)
				if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and _is_narrow_supported_corridor(float(candidate.get("course_distance", 0.0))):
					conservative_spacing = maxf(BASE_EVENT_SPACING, conservative_spacing * GEN20_NARROW_RHYTHM_BASE_SPACING_SCALE + GEN20_RHYTHM_SPACING_DELTAS[phase])
					_rhythm_event_index += 1
				elif _generator_version in [GENERATOR_VERSION_16, GENERATOR_VERSION_17, GENERATOR_VERSION_18, GENERATOR_VERSION_19]:
					conservative_spacing = maxf(BASE_EVENT_SPACING, conservative_spacing * GEN16_RHYTHM_BASE_SPACING_SCALE + GEN16_RHYTHM_SPACING_DELTAS[phase])
					_rhythm_event_index += 1
				elif _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
					conservative_spacing = maxf(BASE_EVENT_SPACING, conservative_spacing * GEN16_RHYTHM_BASE_SPACING_SCALE + GEN16_RHYTHM_SPACING_DELTAS[phase])
					_rhythm_event_index += 1
				elif _generator_version >= GENERATOR_VERSION_14:
					conservative_spacing = maxf(BASE_EVENT_SPACING, conservative_spacing * GEN14_RHYTHM_BASE_SPACING_SCALE + GEN14_RHYTHM_SPACING_DELTAS[phase])
					_rhythm_event_index += 1
				_next_event_distance += get_density_adjusted_spacing(conservative_spacing)
				if _barrel_profile != null:
					_try_append_independent_barrel(candidate, clearance)
				return
			_next_event_distance += PLAN_RETRY_SPACING
		spacing += 48.0

	# Use only profiles permitted by the active ruleset for the safe fallback.
	# A hidden fallback hazard would make custom challenges/campaign stages unfair.
	_append_safe_fallback(speed, track_height)

func _apply_rock_switch_clearance(event: Dictionary, required_distance: float) -> void:
	if str(event.get("kind", "")) != "rock" or required_distance <= 0.0:
		return
	var threats: Array = event.get("threats", [])
	for threat_value in threats:
		if threat_value is Dictionary:
			threat_value["switch_clearance"] = required_distance

func _apply_generator_timing(event: Dictionary) -> void:
	if _generator_version >= GENERATOR_VERSION_15:
		if str(event.get("kind", "")) == "lava_crack":
			event["lava_crack_revision"] = 1
			event["visual_depth"] = 32.0
		elif str(event.get("kind", "")) == "volcano":
			event["projectile_fan_revision"] = 1
			event["projectile_arcs"] = LavaHazardModelScript.gen15_fan_arcs()
	if _generator_version == GENERATOR_VERSION_16 and str(event.get("kind", "")) == "ghost":
		event["trigger_lead"] = 1250.0
		event["warning_ticks"] = 60
		event["danger_ticks"] = 300
		event["skin_variant"] = posmod(posmod(_seed, 3) + posmod(roundi(float(event.get("course_distance", 0.0)) / BASE_EVENT_SPACING), 3), 3)
	if _generator_version == GENERATOR_VERSION_17:
		match str(event.get("id", "")):
			"haunted_ghost":
				event.merge({"ghost_variant": 0, "trigger_lead": 1250.0, "warning_ticks": 60, "danger_ticks": 300, "fade_ticks": 45, "skin_variant": posmod(posmod(_seed, 3) + posmod(roundi(float(event.get("course_distance", 0.0)) / BASE_EVENT_SPACING), 3), 3)}, true)
			"haunted_chaser":
				event.merge({"ghost_variant": 1, "trigger_lead": 1700.0, "warning_ticks": 54, "danger_ticks": 210, "fade_ticks": 30, "chase_speed": 760.0, "chase_start_lag": 220.0, "skin_variant": posmod(posmod(_seed, 3) + posmod(roundi(float(event.get("course_distance", 0.0)) / BASE_EVENT_SPACING), 3), 3), "blocked_lanes": FLOOR_LANE, "from_ceiling": false}, true)
			"cave_icicle":
				event.merge({"rock_variant": 1, "from_ceiling": true, "blocked_lanes": FLOOR_LANE, "trigger_lead": 1250.0, "warning_ticks": 48, "fall_ticks": 30, "lodged_ticks": 240, "burial_depth": 18.0, "width": 64.0, "height": 116.0}, true)
			"lava_tidal_pool":
				event.merge({"lava_variant": 1, "blocked_lanes": FLOOR_LANE, "from_ceiling": false, "pool_min_depth": 6.0, "pool_max_depth": 30.0, "pool_period_ticks": 180, "pool_phase_ticks": posmod(_seed + roundi(float(event.get("course_distance", 0.0))), 180)}, true)
	if _generator_version in [GENERATOR_VERSION_18, GENERATOR_VERSION_19, GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
		match str(event.get("id", "")):
			"haunted_ghost":
				event.merge({"ghost_variant": 0, "trigger_lead": 1250.0, "warning_ticks": 60, "danger_ticks": 300, "fade_ticks": 45, "skin_variant": posmod(posmod(_seed, 3) + posmod(roundi(float(event.get("course_distance", 0.0)) / BASE_EVENT_SPACING), 3), 3)}, true)
			"haunted_chaser":
				var chaser_cell := roundi(float(event.get("course_distance", 0.0)) / BASE_EVENT_SPACING)
				var starts_from_ceiling := posmod(_seed + chaser_cell, 2) == 0
				if _generator_version == GENERATOR_VERSION_18:
					event.merge({"ghost_variant": 2, "trigger_lead": 1500.0, "warning_ticks": 72, "danger_ticks": 120, "fade_ticks": 30, "flyby_start_lag": 130.0, "flyby_speed_delta": 500.0, "skin_variant": posmod(posmod(_seed, 3) + posmod(chaser_cell, 3), 3), "blocked_lanes": BOTH_LANES, "from_ceiling": starts_from_ceiling}, true)
				else:
					# Gen19 pursuit is distinct from both the frozen Gen17 chaser and
					# Gen18 flyby. It stays just behind through warning, then locks the
					# captured lane and overtakes out of view.
					event.merge({"ghost_variant": 3, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "fade_ticks": 60, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "skin_variant": posmod(posmod(_seed, 3) + posmod(chaser_cell, 3), 3), "blocked_lanes": BOTH_LANES, "from_ceiling": starts_from_ceiling}, true)
			"cave_icicle":
				event.merge({"rock_variant": 1, "from_ceiling": true, "blocked_lanes": FLOOR_LANE, "trigger_lead": 1250.0, "warning_ticks": 48, "fall_ticks": 30, "lodged_ticks": 240, "burial_depth": 18.0, "width": 64.0, "height": 116.0}, true)
			"lava_tidal_pool":
				event.merge({"lava_variant": 1, "blocked_lanes": FLOOR_LANE, "from_ceiling": false, "pool_min_depth": 6.0, "pool_max_depth": 30.0, "pool_period_ticks": 180, "pool_phase_ticks": posmod(_seed + roundi(float(event.get("course_distance", 0.0))), 180)}, true)
	if str(event.get("kind", "")) == "saw" and _generator_version >= GENERATOR_VERSION_10:
		var variant_roll := _rng.randf()
		var variant := "floor_embedded"
		if variant_roll >= 0.55 and variant_roll < 0.90:
			variant = "ceiling_embedded"
		elif variant_roll >= 0.90:
			variant = "ceiling_gap_drop"
		event["saw_variant"] = variant
		event["saw_radius"] = 34.0
		var from_ceiling := variant != "floor_embedded"
		event["from_ceiling"] = from_ceiling
		event["blocked_lanes"] = CEILING_LANE if from_ceiling else FLOOR_LANE
		var saw_profile: CourseHazardProfile = event.get("profile")
		if saw_profile != null:
			event["threats"] = saw_profile.build_threat_intervals(event)
	if str(event.get("kind", "")) == "rock" and _generator_version >= ROCK_SAFE_GENERATOR_VERSION and not (_generator_version in [GENERATOR_VERSION_17, GENERATOR_VERSION_18, GENERATOR_VERSION_19, GENERATOR_VERSION_20, GENERATOR_VERSION_21] and str(event.get("id", "")) == "cave_icicle"):
		event["trigger_lead"] = 1800.0
		event["warning_ticks"] = 90
		event["fall_ticks"] = 42
		if _generator_version >= GENERATOR_VERSION_8:
			event["trigger_lead"] = 1600.0
			event["warning_ticks"] = 104

func _try_append_independent_barrel(base_event: Dictionary, clearance: float) -> void:
	var base_distance := float(base_event.get("course_distance", 0.0))
	var barrel_weight := _get_versioned_profile_weight(_barrel_profile, base_distance)
	if barrel_weight <= 0.0:
		return
	var base_kind := StringName(base_event.get("kind", ""))
	if int(base_event.get("blocked_lanes", 0)) != FLOOR_LANE or base_kind not in [&"block", &"spikes"]:
		return
	var normal_weight := 0.0
	for profile in _profiles:
		normal_weight += _get_versioned_profile_weight(profile, base_distance)
	if _rng.randf() >= barrel_weight / maxf(normal_weight + barrel_weight, 0.001):
		return
	var barrel_event := _barrel_profile.create_event(_rng, base_distance, _difficulty, FLOOR_LANE)
	# Put the extra floor-only barrel chain just beyond the base obstacle so it
	# rolls into that obstacle on screen; its independent roll never replaces it.
	var chain_width := float(barrel_event.get("width", HazardRules.BARREL_WIDTH)) - HazardRules.BARREL_WIDTH
	var separation := float(base_event.get("width", HazardRules.BARREL_WIDTH)) * 0.5 + chain_width * 0.5 + HazardRules.BARREL_WIDTH + 24.0
	var is_spiked := false
	var is_rubber := false
	if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and base_kind == &"block":
		is_spiked = _gen20_spiked_barrel_roll(base_event) < GEN20_SPIKED_BARREL_CHANCE
	if _generator_version == GENERATOR_VERSION_21 and base_kind == &"block" and not is_spiked:
		is_rubber = _rng.randf() < 0.28
	if is_rubber:
		# The rubber variant is a single ball placed before its paired block. Its
		# canonical spawn lead gives it time to hit the block shortly before the
		# runner reaches that point; after the bounce it rolls back toward the
		# runner. The source event may overlap the target's authored interval because
		# the barrel itself is a moving entity, not a second static obstacle.
		barrel_event["count"] = 1
		barrel_event["width"] = HazardRules.BARREL_WIDTH
		separation = 12.0
		barrel_event["rubber_target_course_distance"] = base_distance
	if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and not is_spiked:
		# Keep a normal barrel alive long enough to become a runner encounter before
		# it reaches a later floor obstacle. Collision/destruction rules stay shared.
		if not is_rubber:
			separation += GEN20_ORDINARY_BARREL_EXTRA_SEPARATION
	barrel_event["course_distance"] = base_distance + separation
	barrel_event["threats"] = _barrel_profile.build_threat_intervals(barrel_event)
	if is_rubber:
		barrel_event["barrel_variant"] = 1
	if _generator_version >= GENERATOR_VERSION_16 and not (_generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and is_spiked) and _gen16_barrel_meeting_conflicts_with_ceiling(barrel_event):
		_generation_stats["route_rejections"] = int(_generation_stats.get("route_rejections", 0)) + 1
		return
	var spiked_corridor: Dictionary = {}
	if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and is_spiked:
		spiked_corridor = _try_make_supported_spiked_corridor(barrel_event, base_event)
		if not spiked_corridor.is_empty():
			barrel_event["spiked"] = true
		else:
			is_spiked = false
			separation += GEN20_ORDINARY_BARREL_EXTRA_SEPARATION
			barrel_event["course_distance"] = base_distance + separation
			barrel_event["threats"] = _barrel_profile.build_threat_intervals(barrel_event)
			barrel_event.erase("barrel_variant")
			if _gen16_barrel_meeting_conflicts_with_ceiling(barrel_event):
				_generation_stats["route_rejections"] = int(_generation_stats.get("route_rejections", 0)) + 1
				return
	elif _generator_version not in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and _generator_version >= GENERATOR_VERSION_12 and base_kind == &"block" and _rng.randf() < 0.25:
		if _generator_version < GENERATOR_VERSION_13:
			barrel_event["spiked"] = true
		else:
			spiked_corridor = _try_make_supported_spiked_corridor(barrel_event, base_event)
			if not spiked_corridor.is_empty():
				barrel_event["spiked"] = true
	if _is_trial_solvable(barrel_event, clearance):
		_insert_generated_event(barrel_event)
		if _generator_version >= GENERATOR_VERSION_16:
			var new_windows := _barrel_meeting_windows(barrel_event)
			_sync_window_indexes()
			_gen16_barrel_meeting_windows.append_array(new_windows)
			for window in new_windows:
				var window_end := float(window.end)
				var at := _meeting_window_ends.bsearch(window_end, false)
				_meeting_window_ends.insert(at, window_end)
				_meeting_windows_by_end.insert(at, window)
		if not spiked_corridor.is_empty():
			_sync_window_indexes()
			_spiked_barrel_corridors.append(spiked_corridor)
			var corridor_end := float(spiked_corridor.get("end_x", -INF))
			var corridor_at := _corridor_ends.bsearch(corridor_end, false)
			_corridor_ends.insert(corridor_at, corridor_end)
			_corridors_by_end.insert(corridor_at, spiked_corridor)

func _barrel_meeting_windows(barrel_event: Dictionary) -> Array[Dictionary]:
	var windows: Array[Dictionary] = []
	var start_x := 180.0
	var lead := float(barrel_event.get("spawn_lead_distance", EVENT_SPAWN_LEAD_DISTANCE))
	var multiplier := float(barrel_event.get("motion_speed_multiplier", BARREL_SPEED_MULTIPLIER))
	var course_distance := float(barrel_event.get("course_distance", 0.0))
	var count := clampi(int(barrel_event.get("count", 1)), 1, 6)
	var spacing := float(barrel_event.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
	var spawn_time := maxf(0.0, (course_distance - lead) / RunnerMotionScript.BASE_RUN_SPEED)
	var barrel_velocity := RunnerMotionScript.BASE_RUN_SPEED * (multiplier - 1.0)
	var barrel_height := float(barrel_event.get("height", HazardRules.BARREL_WIDTH))
	var encounter_radius := RunnerMotionScript.SIZE.x * 0.5 + HazardRules.barrel_radius(HazardRules.BARREL_WIDTH, barrel_height)
	for barrel_index in range(count):
		var chain_offset := -float(count - 1) * spacing * 0.5 + float(barrel_index) * spacing
		var barrel_start_x: float = start_x + course_distance + lead * (multiplier - 1.0) + chain_offset
		for runner_speed in [250.0, 500.0, 750.0]:
			var runner_spawn_x: float = start_x + runner_speed * spawn_time
			var center_distance := barrel_start_x - runner_spawn_x
			var relative_speed := maxf(runner_speed + barrel_velocity, 1.0)
			var entry_time: float = spawn_time + maxf(center_distance - encounter_radius, 0.0) / relative_speed
			var exit_time: float = spawn_time + (center_distance + encounter_radius) / relative_speed
			var entry_x: float = start_x + runner_speed * entry_time - start_x
			var exit_x: float = start_x + runner_speed * exit_time - start_x
			# Threat intervals are already expanded for the runner body; retain the
			# complete actual barrel-contact interval without adding an unmeasured
			# full flip-cooldown margin that would reject unrelated encounters.
			windows.append({"start": entry_x, "end": exit_x, "speed": runner_speed, "barrel_index": barrel_index})
	return windows

func _gen20_spiked_barrel_roll(base_event: Dictionary) -> float:
	# Keep the new role choice local to this base event. Consuming the shared
	# course RNG here would perturb later terrain/profile choices in Gen20.
	var event_distance := roundi(float(base_event.get("course_distance", 0.0)) * 1000.0)
	var event_key := str(base_event.get("event_id", base_event.get("id", ""))).hash()
	var mixed := int(_seed) * 31 + event_distance * 17 + event_key
	return float(posmod(mixed, 100000)) / 100000.0

func _gen16_barrel_meeting_conflicts_with_ceiling(barrel_event: Dictionary) -> bool:
	# Same test as scanning every committed event's ceiling threats, using the
	# end-ordered index: only threats ending at/after the window start can match.
	_sync_event_indexes()
	for window in _barrel_meeting_windows(barrel_event):
		for threat_index in range(_ceiling_threat_ends.bsearch(float(window.start), true), _ceiling_threat_ends.size()):
			if _ceiling_threat_starts[threat_index] <= float(window.end):
				return true
	return false

func _try_make_supported_spiked_corridor(barrel_event: Dictionary, base_event: Dictionary) -> Dictionary:
	var multiplier := maxf(float(barrel_event.get("motion_speed_multiplier", 1.0)), 1.0)
	var count := maxi(int(barrel_event.get("count", 1)), 1)
	var spacing := float(barrel_event.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
	# Match V2WorldSimulation's first chain element at its actual spawn pose. It
	# moves toward decreasing world X and must reach the block before any hole.
	var spawn_x := float(barrel_event.get("course_distance", 0.0)) + EVENT_SPAWN_LEAD_DISTANCE * (multiplier - 1.0) - float(count - 1) * spacing * 0.5
	var target_x := float(base_event.get("course_distance", 0.0)) + float(base_event.get("width", HazardRules.BARREL_WIDTH)) * 0.5 + HazardRules.barrel_radius(float(barrel_event.get("width", HazardRules.BARREL_WIDTH)), float(barrel_event.get("height", HazardRules.BARREL_WIDTH)))
	if not is_finite(spawn_x) or not is_finite(target_x) or spawn_x <= target_x:
		return {}
	var corridor := {"start_x": target_x, "end_x": spawn_x}
	for event in _events:
		if _floor_unsupported_corridor_overlap(event, corridor):
			return {}
	return corridor

func _candidate_crosses_spiked_barrel_corridor(candidate: Dictionary) -> bool:
	if _generator_version < GENERATOR_VERSION_13:
		return false
	var safety_candidate := candidate
	if _generator_version >= GENERATOR_VERSION_16:
		var profile: Variant = candidate.get("profile")
		if profile != null and profile.has_method("build_threat_intervals"):
			safety_candidate = candidate.duplicate(true)
			safety_candidate["threats"] = profile.build_threat_intervals(safety_candidate)
	# Both corridor tests need corridor end >= some candidate start; entries
	# ending earlier cannot match, so start at the first possible one.
	var reach := INF
	if str(safety_candidate.get("kind", "")) == "gap" and not bool(safety_candidate.get("from_ceiling", false)):
		var gap_left := float(safety_candidate.get("course_distance", 0.0)) - float(safety_candidate.get("width", 0.0)) * 0.5
		reach = minf(reach, minf(gap_left, gap_left + float(safety_candidate.get("width", 0.0))) - 1.0)
	if _generator_version >= GENERATOR_VERSION_16:
		for threat_value in _candidate_threats_for_overlap(safety_candidate):
			if threat_value is Dictionary:
				reach = minf(reach, float((threat_value as Dictionary).get("start", INF)) - RunnerMotionScript.SIZE.x - 1.0)
	_sync_window_indexes()
	var first_corridor := 0 if is_nan(reach) else _corridor_ends.bsearch(reach, true)
	for corridor_index in range(first_corridor, _corridors_by_end.size()):
		var corridor: Dictionary = _corridors_by_end[corridor_index]
		if _floor_unsupported_corridor_overlap(safety_candidate, corridor):
			return true
		if _generator_version >= GENERATOR_VERSION_16 and _opposing_hazard_overlaps_spiked_barrel_corridor(safety_candidate, corridor):
			return true
	if _generator_version >= GENERATOR_VERSION_16 and _candidate_overlaps_gen16_barrel_meeting_window(safety_candidate):
		return true
	if _generator_version >= GENERATOR_VERSION_16 and _candidate_creates_too_short_lava_lane_return(safety_candidate):
		return true
	return false

func _candidate_creates_too_short_lava_lane_return(candidate: Dictionary) -> bool:
	# A floor crack followed closely by a ceiling crack requires two legal
	# lane changes around the pair. Reserve one full flight plus the real flip
	# cooldown and reaction margin between their padded contact windows.
	if str(candidate.get("kind", "")) != "lava_crack":
		return false
	var candidate_threats: Array = candidate.get("threats", [])
	if candidate_threats.is_empty():
		return false
	var return_gap := get_switch_clearance_distance(MAX_RUN_SPEED, REFERENCE_TRACK_HEIGHT) + MAX_RUN_SPEED * PLAYER_FLIP_COOLDOWN
	for candidate_value in candidate_threats:
		if not candidate_value is Dictionary:
			continue
		var candidate_threat: Dictionary = candidate_value
		var candidate_mask := int(candidate_threat.get("blocked_lanes", 0)) & BOTH_LANES
		if candidate_mask != FLOOR_LANE and candidate_mask != CEILING_LANE:
			continue
		_sync_event_indexes()
		for existing in _lava_crack_events:
			var existing_mask := int(existing.get("blocked_lanes", 0)) & BOTH_LANES
			if existing_mask != FLOOR_LANE and existing_mask != CEILING_LANE or existing_mask == candidate_mask:
				continue
			var existing_threats: Array = existing.get("threats", [])
			for existing_value in existing_threats:
				if not existing_value is Dictionary:
					continue
				var existing_threat: Dictionary = existing_value
				var interval_gap := maxf(
					float(candidate_threat.get("start", 0.0)) - float(existing_threat.get("end", 0.0)),
					float(existing_threat.get("start", 0.0)) - float(candidate_threat.get("end", 0.0))
				)
				if interval_gap < return_gap:
					return true
	return false

func _opposing_hazard_overlaps_spiked_barrel_corridor(candidate: Dictionary, corridor: Dictionary) -> bool:
	# A rolling barrel's supported travel corridor needs an available lane for
	# the runner to leave the floor obstacle and return after the barrel passes.
	# The ordinary event-space forecast is calibrated around base speed; Gen16
	# conservatively rejects an opposing-lane hazard whose full padded footprint
	# intrudes into that corridor, including the barrel/runner transition margins.
	var profile: Variant = candidate.get("profile")
	var threats: Array = candidate.get("threats", [])
	if threats.is_empty() and profile != null and profile.has_method("build_threat_intervals"):
		threats = profile.build_threat_intervals(candidate)
	if threats.is_empty():
		return false
	var corridor_start: float = float(corridor.get("start_x", INF)) - RunnerMotionScript.SIZE.x
	var corridor_end: float = float(corridor.get("end_x", -INF)) + RunnerMotionScript.SIZE.x
	for threat_value in threats:
		if not threat_value is Dictionary:
			continue
		var threat: Dictionary = threat_value
		if (int(threat.get("blocked_lanes", 0)) & CEILING_LANE) == 0:
			continue
		if float(threat.get("start", INF)) <= corridor_end and float(threat.get("end", -INF)) >= corridor_start:
			return true
	return false

func _candidate_threats_for_overlap(candidate: Dictionary) -> Array:
	var threats: Array = candidate.get("threats", [])
	var profile: Variant = candidate.get("profile")
	if threats.is_empty() and profile != null and profile.has_method("build_threat_intervals"):
		threats = profile.build_threat_intervals(candidate)
	return threats

func _candidate_overlaps_gen16_barrel_meeting_window(candidate: Dictionary) -> bool:
	var threats: Array = candidate.get("threats", [])
	var profile: Variant = candidate.get("profile")
	if threats.is_empty() and profile != null and profile.has_method("build_threat_intervals"):
		threats = profile.build_threat_intervals(candidate)
	# A window can only overlap a threat that starts at or before its end.
	var reach := INF
	for threat_value in threats:
		if threat_value is Dictionary:
			reach = minf(reach, float((threat_value as Dictionary).get("start", INF)))
	if is_nan(reach) or reach == INF:
		return false
	_sync_window_indexes()
	for window_index in range(_meeting_window_ends.bsearch(reach - 1.0, true), _meeting_windows_by_end.size()):
		var window: Dictionary = _meeting_windows_by_end[window_index]
		for threat_value in threats:
			if not threat_value is Dictionary:
				continue
			var threat: Dictionary = threat_value
			if (int(threat.get("blocked_lanes", 0)) & CEILING_LANE) != 0 and float(threat.get("start", INF)) <= float(window.end) and float(threat.get("end", -INF)) >= float(window.start):
				return true
	return false

func _gen19_pursuit_trigger_is_too_close(candidate: Dictionary) -> bool:
	if str(candidate.get("kind", "")) != "ghost" or int(candidate.get("ghost_variant", 0)) != 3:
		return false
	var trigger_x := float(candidate.get("course_distance", 0.0)) - float(candidate.get("trigger_lead", 0.0))
	# Any committed pursuit closer than the gap (or ahead of it) rejects the
	# candidate, which is the same as testing the furthest committed trigger.
	_sync_event_indexes()
	return trigger_x - _max_pursuit_trigger < GEN19_PURSUIT_MIN_TRIGGER_GAP

func _pick_gen19_non_pursuit_profile(course_distance: float) -> CourseHazardProfile:
	var biome := _biome_id_at(course_distance)
	var eligible: Array[CourseHazardProfile] = []
	var total_weight := 0.0
	for profile in _profiles:
		if profile.profile_id == &"haunted_chaser":
			continue
		if profile.event_kind == &"ghost" and biome != "haunted":
			continue
		var weight := _get_versioned_profile_weight(profile, course_distance)
		if weight <= 0.0:
			continue
		eligible.append(profile)
		total_weight += weight
	if eligible.is_empty() or total_weight <= 0.0:
		return null
	var choice := _rng.randf() * total_weight
	for profile in eligible:
		choice -= _get_versioned_profile_weight(profile, course_distance)
		if choice <= 0.0:
			return profile
	return eligible.back()

func _floor_unsupported_corridor_overlap(event: Dictionary, corridor: Dictionary) -> bool:
	if str(event.get("kind", "")) != "gap" or bool(event.get("from_ceiling", false)):
		return false
	var gap_left := float(event.get("course_distance", 0.0)) - float(event.get("width", 0.0)) * 0.5
	var gap_right := gap_left + float(event.get("width", 0.0))
	# Treat exact surface boundaries as unsupported too, matching CourseSurfaceIndex.
	return gap_left <= float(corridor.get("end_x", -INF)) + 0.001 and gap_right >= float(corridor.get("start_x", INF)) - 0.001

func _append_safe_fallback(speed: float, track_height: float) -> void:
	var clearance := get_switch_clearance_distance(speed, track_height)
	var safe_distance := maxf(_next_event_distance, 700.0)
	for profile in _profiles:
		if _get_versioned_profile_weight(profile, safe_distance) <= 0.0:
			continue
		for attempt in range(64):
			var candidate := profile.create_event(_rng, safe_distance, _difficulty, 0)
			_apply_generator_timing(candidate)
			candidate["course_distance"] = safe_distance
			candidate["threats"] = profile.build_threat_intervals(candidate)
			if _candidate_crosses_spiked_barrel_corridor(candidate):
				safe_distance += PLAN_RETRY_SPACING
				continue
			if _is_trial_solvable(candidate, clearance):
				if _generator_version >= GENERATOR_VERSION_14:
					candidate["rhythm_phase"] = _rhythm_event_index % GEN14_RHYTHM_SPACING_DELTAS.size()
				_insert_generated_event(candidate)
				_generation_stats["accepted_events"] = int(_generation_stats.get("accepted_events", 0)) + 1
				_generation_stats["fallback_events"] = int(_generation_stats.get("fallback_events", 0)) + 1
				var widest := 0.0
				for threat in candidate["threats"]:
					widest = maxf(widest, float(threat["end"]) - float(threat["start"]))
				var fallback_spacing := maxf(BASE_EVENT_SPACING, widest + clearance)
				if _generator_version >= GENERATOR_VERSION_14:
					if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21] and _is_narrow_supported_corridor(safe_distance):
						fallback_spacing = maxf(BASE_EVENT_SPACING, fallback_spacing * GEN20_NARROW_RHYTHM_BASE_SPACING_SCALE + GEN20_RHYTHM_SPACING_DELTAS[_rhythm_event_index % GEN20_RHYTHM_SPACING_DELTAS.size()])
					elif _generator_version in [GENERATOR_VERSION_16, GENERATOR_VERSION_17, GENERATOR_VERSION_18, GENERATOR_VERSION_19]:
						fallback_spacing = maxf(BASE_EVENT_SPACING, fallback_spacing * GEN16_RHYTHM_BASE_SPACING_SCALE + GEN16_RHYTHM_SPACING_DELTAS[_rhythm_event_index % GEN16_RHYTHM_SPACING_DELTAS.size()])
					elif _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
						fallback_spacing = maxf(BASE_EVENT_SPACING, fallback_spacing * GEN16_RHYTHM_BASE_SPACING_SCALE + GEN16_RHYTHM_SPACING_DELTAS[_rhythm_event_index % GEN16_RHYTHM_SPACING_DELTAS.size()])
					else:
						fallback_spacing = maxf(BASE_EVENT_SPACING, fallback_spacing + GEN14_RHYTHM_SPACING_DELTAS[_rhythm_event_index % GEN14_RHYTHM_SPACING_DELTAS.size()])
					_rhythm_event_index += 1
				_next_event_distance = safe_distance + get_density_adjusted_spacing(fallback_spacing)
				return
			safe_distance += maxf(250.0, clearance * 0.5)
	push_error("The active course ruleset has no solvable fallback encounter.")
	_configuration_failed = true

func _pick_profile(course_distance: float = -1.0) -> CourseHazardProfile:
	var pick_distance := _next_event_distance if course_distance < 0.0 else course_distance
	var total_weight := 0.0
	for profile in _profiles:
		total_weight += _get_versioned_profile_weight(profile, pick_distance)
	if total_weight <= 0.0:
		return null
	var choice := _rng.randf() * total_weight
	for profile in _profiles:
		choice -= _get_versioned_profile_weight(profile, pick_distance)
		if choice <= 0.0:
			return profile
	return _profiles.back()

func _get_versioned_profile_weight(profile: CourseHazardProfile, course_distance: float) -> float:
	if profile == null:
		return 0.0
	var base_weight := profile.weight * _get_profile_weight_multiplier(profile.profile_id)
	if base_weight <= 0.0 or _generator_version < GENERATOR_VERSION_12:
		return base_weight
	var biome := _biome_id_at(course_distance)
	return base_weight * BiomeEncounterMixScript.multiplier(_generator_version, biome, profile.profile_id)

func _biome_id_at(course_distance: float) -> String:
	return BiomeRenderer.biome_id_for_generator(course_distance + _biome_start_offset, _generator_version)

func _is_narrow_supported_corridor(course_distance: float) -> bool:
	if _generator_version not in [GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
		return false
	var floor_y := COURSE_FLOOR_START_Y
	var ceiling_y := COURSE_CEILING_START_Y
	var floor_supported := true
	var ceiling_supported := true
	# Events whose effect on every later query is already final (gaps fully
	# behind, steps passed, slopes completed) are folded into a cached lane
	# state, so each query only walks events near its own distance.
	var start_index := 0
	var prefix := _narrow_prefix
	if not prefix.is_empty():
		var prefix_count := int(prefix["count"])
		if prefix_count > 0 and prefix_count <= _events.size() and is_same(_events[prefix_count - 1], prefix["last"]) and course_distance >= float(prefix["built_at"]):
			start_index = prefix_count
			floor_y = float(prefix["floor_y"])
			ceiling_y = float(prefix["ceiling_y"])
	var folding := true
	for event_index in range(start_index, _events.size()):
		var event: Dictionary = _events[event_index]
		var kind := str(event.get("kind", ""))
		var x := float(event.get("course_distance", 0.0))
		var from_ceiling := bool(event.get("from_ceiling", false))
		if folding:
			var settled_point := -INF
			if kind == "gap":
				settled_point = x + absf(float(event.get("width", 0.0)) * 0.5) + 0.001
			elif kind == "step":
				settled_point = x
			elif kind == "slope":
				settled_point = x + GEN20_SLOPE_WIDTH * 0.5
			folding = settled_point <= course_distance
		if kind == "gap":
			var half_width := float(event.get("width", 0.0)) * 0.5
			if absf(course_distance - x) <= half_width:
				if from_ceiling:
					ceiling_supported = false
				else:
					floor_supported = false
			continue
		if kind == "step":
			if x > course_distance:
				continue
			var start_y := ceiling_y if from_ceiling else floor_y
			var change := float(event.get("height", 84.0))
			var low_limit := 40.0 if from_ceiling else 330.0
			var high_limit := 220.0 if from_ceiling else 500.0
			var end_y := start_y + change if from_ceiling else start_y - change
			end_y = clampf(end_y, low_limit, high_limit)
			if absf(end_y - start_y) < 40.0:
				end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
			if from_ceiling:
				ceiling_y = end_y
			else:
				floor_y = end_y
		elif kind == "slope":
			var half_width := GEN20_SLOPE_WIDTH * 0.5
			var start_x := x - half_width
			var end_x := x + half_width
			if course_distance <= start_x:
				continue
			var start_y := ceiling_y if from_ceiling else floor_y
			var low_limit := 40.0 if from_ceiling else 330.0
			var high_limit := 220.0 if from_ceiling else 500.0
			var direction := float(event.get("slope_direction", 1.0))
			var end_y := clampf(start_y + direction * float(event.get("height", 65.0)), low_limit, high_limit)
			if absf(end_y - start_y) < 40.0:
				end_y = clampf(start_y - direction * 45.0, low_limit, high_limit)
			var progress := clampf((course_distance - start_x) / GEN20_SLOPE_WIDTH, 0.0, 1.0)
			var slope_y := lerpf(start_y, end_y, progress)
			if course_distance < end_x:
				if from_ceiling:
					ceiling_y = slope_y
				else:
					floor_y = slope_y
				break
			if from_ceiling:
				ceiling_y = end_y
			else:
				floor_y = end_y
		if folding:
			_narrow_prefix = {"count": event_index + 1, "last": event, "floor_y": floor_y, "ceiling_y": ceiling_y, "built_at": course_distance}
	return floor_supported and ceiling_supported and floor_y - ceiling_y <= GEN20_NARROW_SPAN_MAX

func _index_committed_event(event: Dictionary) -> void:
	var profile: Variant = event.get("profile")
	var threats: Array = event.get("threats", [])
	if threats.is_empty() and profile != null and profile.has_method("build_threat_intervals"):
		threats = profile.build_threat_intervals(event)
	for threat_value in threats:
		if not threat_value is Dictionary or (int((threat_value as Dictionary).get("blocked_lanes", 0)) & CEILING_LANE) == 0:
			continue
		var threat_end := float((threat_value as Dictionary).get("end", -INF))
		var at := _ceiling_threat_ends.bsearch(threat_end, false)
		_ceiling_threat_ends.insert(at, threat_end)
		_ceiling_threat_starts.insert(at, float((threat_value as Dictionary).get("start", INF)))
	if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3:
		_max_pursuit_trigger = maxf(_max_pursuit_trigger, float(event.get("course_distance", 0.0)) - float(event.get("trigger_lead", 0.0)))
	if str(event.get("kind", "")) == "lava_crack":
		_lava_crack_events.append(event)

## The event indexes describe exactly this _events array and length. If the
## array is replaced or edited from outside (white-box tests do), rebuild them.
func _sync_event_indexes() -> void:
	if is_same(_indexed_events, _events) and _indexed_event_count == _events.size():
		return
	_max_pursuit_trigger = -INF
	_lava_crack_events.clear()
	_ceiling_threat_ends = PackedFloat64Array()
	_ceiling_threat_starts = PackedFloat64Array()
	for event in _events:
		_index_committed_event(event)
	_indexed_events = _events
	_indexed_event_count = _events.size()

func _sync_window_indexes() -> void:
	if not (is_same(_indexed_windows, _gen16_barrel_meeting_windows) and _meeting_windows_by_end.size() == _gen16_barrel_meeting_windows.size()):
		_meeting_windows_by_end.clear()
		_meeting_window_ends = PackedFloat64Array()
		for window in _gen16_barrel_meeting_windows:
			var window_end := float(window.end)
			var at := _meeting_window_ends.bsearch(window_end, false)
			_meeting_window_ends.insert(at, window_end)
			_meeting_windows_by_end.insert(at, window)
		_indexed_windows = _gen16_barrel_meeting_windows
	if not (is_same(_indexed_corridors, _spiked_barrel_corridors) and _corridors_by_end.size() == _spiked_barrel_corridors.size()):
		_corridors_by_end.clear()
		_corridor_ends = PackedFloat64Array()
		for corridor in _spiked_barrel_corridors:
			var corridor_end := float(corridor.get("end_x", -INF))
			var at := _corridor_ends.bsearch(corridor_end, false)
			_corridor_ends.insert(at, corridor_end)
			_corridors_by_end.insert(at, corridor)
		_indexed_corridors = _spiked_barrel_corridors

func _insert_generated_event(event: Dictionary) -> void:
	_pending_sweep_events.append(event)
	_sync_event_indexes()
	_index_committed_event(event)
	if _generator_version not in [GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
		_events.append(event)
		_indexed_event_count = _events.size()
		return
	var distance := float(event.get("course_distance", 0.0))
	# Gen20+ keeps _events sorted by course distance, so the first entry beyond
	# this distance is found from the end (new events land near the frontier).
	var index := _events.size()
	while index > 0 and float(_events[index - 1].get("course_distance", 0.0)) > distance:
		index -= 1
	_events.insert(index, event)
	_indexed_event_count = _events.size()
	if index < _next_spawn_index:
		_next_spawn_index += 1

func _get_profile_weight_multiplier(profile_id: StringName) -> float:
	if _difficulty == null:
		return 1.0
	var multipliers: Dictionary = _difficulty.get("profile_weight_multipliers")
	return maxf(0.0, float(multipliers.get(String(profile_id), 1.0)))

func _preferred_lane() -> int:
	if _events.is_empty():
		return 0
	var previous_event: Dictionary = _events.back()
	if _generator_version in [GENERATOR_VERSION_20, GENERATOR_VERSION_21]:
		for index in range(_events.size() - 1, -1, -1):
			if float(_events[index].get("course_distance", 0.0)) <= _next_event_distance + 0.001:
				previous_event = _events[index]
				break
	var previous_mask := int(previous_event.get("blocked_lanes", 0))
	if previous_mask == FLOOR_LANE:
		return CEILING_LANE
	if previous_mask == CEILING_LANE:
		return FLOOR_LANE
	return 0

func _make_profile(id: StringName, kind: StringName, profile_weight: float, lanes: int, widths: Vector2, counts: Vector2i, heights: PackedFloat32Array) -> CourseHazardProfile:
	var profile := CourseHazardProfileScript.new() as CourseHazardProfile
	profile.profile_id = id
	profile.event_kind = kind
	profile.weight = profile_weight
	profile.allowed_lanes = lanes
	profile.width_range = widths
	profile.count_range = counts
	profile.height_options = heights
	return profile
