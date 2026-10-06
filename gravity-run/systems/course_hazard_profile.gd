extends Resource
class_name CourseHazardProfile
## Data and route forecast for one generated encounter.
## Lane bits: floor = 1, ceiling = 2. Custom profiles may override
## build_threat_intervals() to describe moving/multi-stage hazards.

const FLOOR_LANE := 1
const CEILING_LANE := 2

@export var profile_id: StringName
@export var event_kind: StringName
@export var runtime_scene: PackedScene
@export_range(0.0, 100.0, 0.1) var weight := 1.0
@export_flags("Floor", "Ceiling") var allowed_lanes := FLOOR_LANE | CEILING_LANE
@export var width_range := Vector2(48.0, 64.0)
@export var count_range := Vector2i(1, 1)
@export var height_options: PackedFloat32Array = PackedFloat32Array([72.0])
@export var threat_padding := 17.0
## Horizontal speed relative to the scrolling course. The range is sampled
## once per event, so runtime motion and feasibility forecasts use the same
## value. Equal min/max keeps the hazard deterministic until variation is tuned.
@export_range(1.0, 4.0, 0.05) var motion_speed_min := 1.0
@export_range(1.0, 4.0, 0.05) var motion_speed_max := 1.0
var spawn_lead_distance := 0.0
## Optional normalized event-space forecasts. Each Vector3 is (start offset,
## end offset, blocked lane mask); -1 uses the event's chosen lane. A moving
## hazard can provide multiple windows, including pauses and lane changes.
@export var threat_windows: Array[Vector3] = []

func create_event(rng: RandomNumberGenerator, course_distance: float, difficulty: Resource = null, preferred_lane: int = 0) -> Dictionary:
	var event_motion_speed_multiplier := rng.randf_range(
		minf(motion_speed_min, motion_speed_max),
		maxf(motion_speed_min, motion_speed_max)
	)
	var lane_alternation := float(difficulty.get("lane_alternation")) if difficulty != null else 0.0
	var lane_mask := _choose_lane(rng, preferred_lane, lane_alternation)
	var count := rng.randi_range(count_range.x, count_range.y)
	var width := rng.randf_range(width_range.x, width_range.y)
	var height := height_options[rng.randi_range(0, height_options.size() - 1)] if not height_options.is_empty() else width
	var spiked_step := false
	var slope_direction := 0.0
	match event_kind:
		&"spikes":
			width = float((count - 1) * 32 + 28)
			height = 32.0
		&"barrels":
			width = 54.0 + float(count - 1) * 70.0
			height = 54.0 if rng.randf() < 0.5 else 76.0
		&"gap":
			width = rng.randf_range(width_range.x, width_range.y)
			height = 0.0
		&"step":
			spiked_step = rng.randf() < 0.45
			width = 240.0 if spiked_step else 36.0
			if spiked_step:
				count = rng.randi_range(4, 6)
			height = height_options[rng.randi_range(0, height_options.size() - 1)] if not height_options.is_empty() else 84.0
		&"slope":
			width = width_range.x
			slope_direction = -1.0 if rng.randi_range(0, 1) == 0 else 1.0
		&"rock":
			if str(profile_id) == "cave_icicle":
				lane_mask = CEILING_LANE
				width = 64.0
				height = 116.0
			else:
				lane_mask = FLOOR_LANE
				width = 90.0
				height = 100.0
		&"ghost":
			width = 72.0
			height = 96.0
		&"lava_crack":
			lane_mask = _choose_lane(rng, preferred_lane, lane_alternation)
			width = rng.randf_range(width_range.x, width_range.y)
			height = 14.0
		&"volcano":
			lane_mask = FLOOR_LANE
			width = rng.randf_range(width_range.x, width_range.y)
			height = 76.0
	if difficulty != null:
		var size_scale := float(difficulty.get("hazard_size"))
		match event_kind:
			&"spikes":
				count = clampi(roundi(float(count) * size_scale), 2, 10)
				width = float((count - 1) * 32 + 28)
				height *= size_scale
			&"barrels":
				count = clampi(roundi(float(count) * size_scale), 1, 6)
				width = 54.0 + float(count - 1) * 70.0
				height *= size_scale
			&"step":
				if spiked_step:
					count = clampi(roundi(float(count) * size_scale), 2, 10)
					width = float((count - 1) * 32 + 28)
				height *= size_scale
			_:
				width *= size_scale
				height *= size_scale

	var event := {
		"id": profile_id,
		"kind": event_kind,
		"course_distance": course_distance,
		"blocked_lanes": lane_mask,
		"from_ceiling": bool(lane_mask & CEILING_LANE) and not bool(lane_mask & FLOOR_LANE),
		"width": width,
		"height": height,
		"count": count,
		"spiked_step": spiked_step,
		"slope_direction": slope_direction,
		"motion_speed_multiplier": event_motion_speed_multiplier,
		"profile": self,
	}
	if event_kind == &"rock":
		event.merge({"trigger_lead": 1100.0, "warning_ticks": 36, "fall_ticks": 20, "burial_depth": 24.0}, true)
	elif event_kind == &"ghost":
		event.merge({"trigger_lead": 2500.0, "warning_ticks": 120, "danger_ticks": 500, "fade_ticks": 45}, true)
	elif event_kind == &"lava_crack":
		event.merge({"hot_depth": 14.0, "blocked_lanes": lane_mask}, true)
	elif event_kind == &"volcano":
		event.merge({"eruption_lead": 1800.0, "eruption_period_ticks": 156, "projectile_lifetime_ticks": 58, "projectile_speed": 330.0, "projectile_vertical_speed": 430.0, "projectile_gravity": 900.0, "projectile_radius": 14.0, "blocked_lanes": FLOOR_LANE}, true)
	event["threats"] = build_threat_intervals(event)
	return event

func build_threat_intervals(event: Dictionary) -> Array[Dictionary]:
	var intervals: Array[Dictionary] = []
	var center := float(event["course_distance"])
	var speed_multiplier := maxf(float(event.get("motion_speed_multiplier", 1.0)), 1.0)
	# A faster hazard reaches the player before its nominal course distance.
	# Events are instantiated at a fixed lead ahead of the viewport, so account
	# for that offset as well as compressing each physical threat width by speed.
	var forecast_center := center - spawn_lead_distance * (1.0 - 1.0 / speed_multiplier)
	if str(event.get("id", "")) == "cave_icicle":
		var fall_start := center - float(event.get("trigger_lead", 1250.0)) + float(event.get("warning_ticks", 48)) * 500.0 / 60.0
		var fall_end := fall_start + float(event.get("fall_ticks", 30)) * 500.0 / 60.0
		var lodged_end := fall_end + float(event.get("lodged_ticks", 240)) * 500.0 / 60.0
		intervals.append({"start": fall_start - float(event.get("width", 52.0)) * 0.5 - 70.0, "end": fall_end + float(event.get("width", 52.0)) * 0.5 + 70.0, "blocked_lanes": FLOOR_LANE})
		if bool(event.get("floor_supported", true)):
			intervals.append({"start": fall_end - float(event.get("width", 52.0)) * 0.5 - 70.0, "end": lodged_end + float(event.get("width", 52.0)) * 0.5 + 70.0, "blocked_lanes": FLOOR_LANE})
		return intervals
	if StringName(event.get("kind", "")) == &"rock":
		var half_width := float(event.get("width", 90.0)) * 0.5 + 60.0
		intervals.append({"start": forecast_center - half_width, "end": forecast_center + half_width, "blocked_lanes": FLOOR_LANE})
		return intervals
	if StringName(event.get("kind", "")) == &"saw":
		# v9 blades all eventually occupy the floor and retain their frozen
		# forecast. v10 ceiling rollers reserve the ceiling lane; only the rare
		# authored gap-drop reserves a later floor window as well.
		var variant := str(event.get("saw_variant", "legacy_floor_then_drop"))
		if variant == "ceiling_embedded":
			intervals.append({"start": forecast_center + 520.0, "end": forecast_center + 1160.0, "blocked_lanes": CEILING_LANE})
		elif variant == "ceiling_gap_drop":
			# The gen10 drop gap is close enough to the spawn point that the saw
			# reaches the floor before supported runners meet it. The ceiling route
			# remains the escape lane throughout.
			intervals.append({"start": forecast_center + 560.0, "end": forecast_center + 1350.0, "blocked_lanes": FLOOR_LANE})
		else:
			intervals.append({"start": forecast_center + 560.0, "end": forecast_center + 1100.0, "blocked_lanes": FLOOR_LANE})
		return intervals
	if StringName(event.get("kind", "")) == &"ghost":
		if str(event.get("id", "")) == "haunted_chaser":
			var trigger := center - float(event.get("trigger_lead", 1700.0))
			var danger_start := trigger + float(event.get("warning_ticks", 54)) * 500.0 / 60.0
			var danger_end := danger_start + float(event.get("danger_ticks", 150)) * 500.0 / 60.0
			var chase_start := trigger - float(event.get("chase_start_lag", 220.0))
			var chase_end := chase_start + float(event.get("chase_speed", 760.0)) * float(event.get("danger_ticks", 150)) / 60.0
			intervals.append({"start": minf(danger_start, chase_start) - float(event.get("width", 72.0)) * 0.5 - 70.0, "end": maxf(danger_end, chase_end) + float(event.get("width", 72.0)) * 0.5 + 70.0, "blocked_lanes": FLOOR_LANE})
			return intervals
		var half_width := float(event.get("width", 72.0)) * 0.5 + threat_padding
		intervals.append({"start": forecast_center - half_width, "end": forecast_center + half_width, "blocked_lanes": int(event.get("blocked_lanes", FLOOR_LANE))})
		return intervals
	if StringName(event.get("kind", "")) == &"lava_crack":
		var half_width := float(event.get("width", 120.0)) * 0.5 + threat_padding
		intervals.append({"start": forecast_center - half_width, "end": forecast_center + half_width, "blocked_lanes": int(event.get("blocked_lanes", FLOOR_LANE))})
		return intervals
	if StringName(event.get("kind", "")) == &"volcano":
		# The envelope grows only in the Gen15 fan variant. The ceiling remains
		# the authored safe lane, validated against every arc and runner clearance.
		var reach := 540.0 if int(event.get("projectile_fan_revision", 0)) == 1 else 470.0
		intervals.append({"start": forecast_center - reach, "end": forecast_center + reach, "blocked_lanes": FLOOR_LANE})
		return intervals
	if not threat_windows.is_empty():
		for window in threat_windows:
			var mask := int(round(window.z))
			if mask < 0:
				mask = int(event["blocked_lanes"])
			intervals.append({
				"start": forecast_center + window.x / speed_multiplier,
				"end": forecast_center + window.y / speed_multiplier,
				"blocked_lanes": mask,
			})
		return intervals
	var half_width := (float(event["width"]) * 0.5 + threat_padding) / speed_multiplier
	intervals.append({
		"start": forecast_center - half_width,
		"end": forecast_center + half_width,
		"blocked_lanes": int(event["blocked_lanes"]),
	})
	return intervals

func _choose_lane(rng: RandomNumberGenerator, preferred_lane: int = 0, alternation_chance: float = 0.0) -> int:
	var choices: Array[int] = []
	if allowed_lanes & FLOOR_LANE:
		choices.append(FLOOR_LANE)
	if allowed_lanes & CEILING_LANE:
		choices.append(CEILING_LANE)
	if choices.is_empty():
		return FLOOR_LANE
	if choices.size() == 2 and preferred_lane in choices and rng.randf() < alternation_chance:
		return preferred_lane
	return choices[rng.randi_range(0, choices.size() - 1)]
