extends RefCounted
class_name CourseGenerator
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
const GENERATOR_VERSION := 4
const LEGACY_GENERATOR_VERSION := 3
const CourseHazardProfileScript = preload("res://systems/course_hazard_profile.gd")
const CourseDifficultyProfileScript = preload("res://systems/course_difficulty_profile.gd")

var _rng := RandomNumberGenerator.new()
var _profiles: Array[CourseHazardProfile] = []
var _barrel_profile: CourseHazardProfile
var _events: Array[Dictionary] = []
var _next_event_distance := 1050.0
var _next_spawn_index := 0
var _seed := 0
var _difficulty: Resource
var _spawn_lead_distance := 0.0
var _configuration_failed := false

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
	if generator_version != GENERATOR_VERSION and generator_version != LEGACY_GENERATOR_VERSION:
		push_error("Unsupported course generator version: %d" % generator_version)
		return false
	_profiles.clear()
	_barrel_profile = null
	_difficulty = null
	_profiles.append(_make_profile(&"spike_group", &"spikes", 3.0, BOTH_LANES, Vector2(124.0, 188.0), Vector2i(4, 6), PackedFloat32Array([32.0])))
	_profiles.append(_make_profile(&"block", &"block", 2.3, BOTH_LANES, Vector2(44.0, 64.0), Vector2i(1, 1), PackedFloat32Array([82.0, 132.0, 168.0])))
	var barrel_weight := 1.7 if generator_version == LEGACY_GENERATOR_VERSION else 12.0
	var barrel_profile := _make_profile(&"barrel_chain", &"barrels", barrel_weight, FLOOR_LANE, Vector2(54.0, 194.0), Vector2i(1, 3), PackedFloat32Array([54.0, 76.0]))
	barrel_profile.motion_speed_min = BARREL_SPEED_MULTIPLIER
	barrel_profile.motion_speed_max = BARREL_SPEED_MULTIPLIER
	_profiles.append(barrel_profile)
	_profiles.append(_make_profile(&"floor_gap", &"gap", 0.8, FLOOR_LANE, Vector2(150.0, 190.0), Vector2i(1, 1), PackedFloat32Array([0.0])))
	_profiles.append(_make_profile(&"ceiling_gap", &"gap", 0.8, CEILING_LANE, Vector2(150.0, 190.0), Vector2i(1, 1), PackedFloat32Array([0.0])))
	# Terrain changes are part of the course rhythm, not rare decoration.
	_profiles.append(_make_profile(&"terrain_step", &"step", 1.8, BOTH_LANES, Vector2(36.0, 240.0), Vector2i(1, 1), PackedFloat32Array([72.0, 108.0, 148.0, 184.0])))
	_profiles.append(_make_profile(&"terrain_slope", &"slope", 1.5, BOTH_LANES, Vector2(440.0, 440.0), Vector2i(1, 1), PackedFloat32Array([64.0, 100.0, 140.0, 176.0])))
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
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed
	_events.clear()
	_next_event_distance = 1050.0
	_next_spawn_index = 0

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

func get_switch_clearance_distance(speed: float, track_height: float = 540.0) -> float:
	var travel_distance := maxf(track_height - 112.0 - 44.0, 0.0)
	var travel_time := (-PLAYER_FLIP_SPEED + sqrt(PLAYER_FLIP_SPEED * PLAYER_FLIP_SPEED + 2.0 * PLAYER_GRAVITY * travel_distance)) / PLAYER_GRAVITY
	var margin_scale := float(_difficulty.get("reaction_margin")) if _difficulty != null else 1.0
	var switch_time := maxf(PLAYER_FLIP_COOLDOWN, travel_time) + SWITCH_SAFETY_MARGIN * margin_scale
	return maxf(speed, MAX_RUN_SPEED) * switch_time

func get_density_adjusted_spacing(conservative_spacing: float) -> float:
	var density := float(_difficulty.get("event_density")) if _difficulty != null else 1.0
	return maxf(180.0, conservative_spacing / maxf(density, 0.1))

func is_plan_solvable(events: Array[Dictionary], switch_clearance: float = -1.0) -> bool:
	if events.is_empty():
		return true
	var clearance := switch_clearance if switch_clearance >= 0.0 else get_switch_clearance_distance(MAX_RUN_SPEED)
	var edges: Array[Dictionary] = []
	for event in events:
		for threat in event.get("threats", []):
			var start := float(threat.get("start", 0.0))
			var end := float(threat.get("end", start))
			if end <= start:
				continue
			var mask := int(threat.get("blocked_lanes", 0)) & BOTH_LANES
			if mask == 0:
				continue
			edges.append({"x": start, "floor_delta": 1 if mask & FLOOR_LANE else 0, "ceiling_delta": 1 if mask & CEILING_LANE else 0})
			edges.append({"x": end, "floor_delta": -1 if mask & FLOOR_LANE else 0, "ceiling_delta": -1 if mask & CEILING_LANE else 0})
	if edges.is_empty():
		return true
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["x"]) < float(b["x"]))

	var current_lane := FLOOR_LANE
	var last_threat_end := 0.0
	var floor_count := 0
	var ceiling_count := 0
	var edge_index := 0
	while edge_index < edges.size() - 1:
		var start := float(edges[edge_index]["x"])
		while edge_index < edges.size() and is_equal_approx(float(edges[edge_index]["x"]), start):
			floor_count += int(edges[edge_index]["floor_delta"])
			ceiling_count += int(edges[edge_index]["ceiling_delta"])
			edge_index += 1
		if edge_index >= edges.size():
			break
		var end := float(edges[edge_index]["x"])
		var blocked_mask := (FLOOR_LANE if floor_count > 0 else 0) | (CEILING_LANE if ceiling_count > 0 else 0)
		if blocked_mask == BOTH_LANES:
			return false
		if blocked_mask == 0:
			continue

		var required_lane := CEILING_LANE if blocked_mask & FLOOR_LANE else FLOOR_LANE
		if required_lane != current_lane:
			if start - last_threat_end < clearance:
				return false
			current_lane = required_lane
		last_threat_end = end
	return true

func _append_feasible_event(speed: float, track_height: float) -> void:
	var spacing := BASE_EVENT_SPACING
	var clearance := get_switch_clearance_distance(speed, track_height)
	for _attempt in range(64):
		var profile := _pick_profile()
		if profile == null:
			break
		var candidate := profile.create_event(_rng, _next_event_distance, _difficulty, _preferred_lane())
		var intrinsic_probe: Dictionary = candidate.duplicate()
		intrinsic_probe["course_distance"] = 1000000.0
		intrinsic_probe["threats"] = profile.build_threat_intervals(intrinsic_probe)
		if not is_plan_solvable([intrinsic_probe], clearance):
			# A profile whose own phases leave no route cannot be repaired by
			# shifting it; skip it instead of creating an arbitrary empty stretch.
			spacing += PLAN_RETRY_SPACING
			continue
		for _shift in range(128):
			candidate["course_distance"] = _next_event_distance
			candidate["threats"] = profile.build_threat_intervals(candidate)
			var trial := _events.duplicate()
			trial.append(candidate)
			if is_plan_solvable(trial, clearance):
				_events.append(candidate)
				var widest := 0.0
				for threat in candidate["threats"]:
					widest = maxf(widest, float(threat["end"]) - float(threat["start"]))
				var conservative_spacing := maxf(spacing, widest + clearance)
				_next_event_distance += get_density_adjusted_spacing(conservative_spacing)
				if _barrel_profile != null:
					_try_append_independent_barrel(candidate, clearance)
				return
			_next_event_distance += PLAN_RETRY_SPACING
		spacing += 48.0

	# Use only profiles permitted by the active ruleset for the safe fallback.
	# A hidden fallback hazard would make custom challenges/campaign stages unfair.
	_append_safe_fallback(speed, track_height)

func _try_append_independent_barrel(base_event: Dictionary, clearance: float) -> void:
	var barrel_weight := _barrel_profile.weight * _get_profile_weight_multiplier(_barrel_profile.profile_id)
	if barrel_weight <= 0.0:
		return
	var base_kind := StringName(base_event.get("kind", ""))
	if int(base_event.get("blocked_lanes", 0)) != FLOOR_LANE or base_kind not in [&"block", &"spikes"]:
		return
	var normal_weight := 0.0
	for profile in _profiles:
		normal_weight += profile.weight * _get_profile_weight_multiplier(profile.profile_id)
	if _rng.randf() >= barrel_weight / maxf(normal_weight + barrel_weight, 0.001):
		return
	var base_distance := float(base_event["course_distance"])
	var barrel_event := _barrel_profile.create_event(_rng, base_distance, _difficulty, FLOOR_LANE)
	# Put the extra floor-only barrel chain just beyond the base obstacle so it
	# rolls into that obstacle on screen; its independent roll never replaces it.
	var chain_width := float(barrel_event.get("width", 54.0)) - 54.0
	var separation := float(base_event.get("width", 54.0)) * 0.5 + chain_width * 0.5 + 54.0 + 24.0
	barrel_event["course_distance"] = base_distance + separation
	barrel_event["threats"] = _barrel_profile.build_threat_intervals(barrel_event)
	var trial: Array[Dictionary] = []
	trial.append_array(_events)
	trial.append(barrel_event)
	if is_plan_solvable(trial, clearance):
		_events.append(barrel_event)

func _append_safe_fallback(speed: float, track_height: float) -> void:
	var clearance := get_switch_clearance_distance(speed, track_height)
	var safe_distance := maxf(_next_event_distance, 700.0)
	for profile in _profiles:
		for attempt in range(64):
			var candidate := profile.create_event(_rng, safe_distance, _difficulty, 0)
			candidate["course_distance"] = safe_distance
			candidate["threats"] = profile.build_threat_intervals(candidate)
			if is_plan_solvable(_events + [candidate], clearance):
				_events.append(candidate)
				var widest := 0.0
				for threat in candidate["threats"]:
					widest = maxf(widest, float(threat["end"]) - float(threat["start"]))
				_next_event_distance = safe_distance + get_density_adjusted_spacing(maxf(BASE_EVENT_SPACING, widest + clearance))
				return
			safe_distance += maxf(250.0, clearance * 0.5)
	push_error("The active course ruleset has no solvable fallback encounter.")
	_configuration_failed = true

func _pick_profile() -> CourseHazardProfile:
	var total_weight := 0.0
	for profile in _profiles:
		total_weight += profile.weight * _get_profile_weight_multiplier(profile.profile_id)
	if total_weight <= 0.0:
		return null
	var choice := _rng.randf() * total_weight
	for profile in _profiles:
		choice -= profile.weight * _get_profile_weight_multiplier(profile.profile_id)
		if choice <= 0.0:
			return profile
	return _profiles.back()

func _get_profile_weight_multiplier(profile_id: StringName) -> float:
	if _difficulty == null:
		return 1.0
	var multipliers: Dictionary = _difficulty.get("profile_weight_multipliers")
	return maxf(0.0, float(multipliers.get(String(profile_id), 1.0)))

func _preferred_lane() -> int:
	if _events.is_empty():
		return 0
	var previous_mask := int(_events.back().get("blocked_lanes", 0))
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
