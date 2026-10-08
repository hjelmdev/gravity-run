extends RefCounted
class_name LavaHazardModel
## Deterministic shared lava geometry and projectile timing for SP and MP.

const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const TICK_RATE := 60.0
const BASE_RUN_SPEED := Motion.BASE_RUN_SPEED
const GEN15_FAN_REVISION := 1

static func gen15_fan_arcs() -> Array[Dictionary]:
	## Serialized into each Gen15 manifest event so the server and renderer consume
	## the same bounded trajectories. Gen14 retains its original paired profile.
	return [
		{"horizontal_speed": 235.0, "vertical_speed": 390.0, "gravity": 1000.0, "radius": 11.0, "lifetime_ticks": 48},
		{"horizontal_speed": 340.0, "vertical_speed": 490.0, "gravity": 1050.0, "radius": 13.0, "lifetime_ticks": 56},
		{"horizontal_speed": 450.0, "vertical_speed": 580.0, "gravity": 1100.0, "radius": 15.0, "lifetime_ticks": 60},
	]

static func eruption_start_tick(event: Dictionary, course_start_x: float) -> int:
	var lead := maxf(float(event.get("eruption_lead", 1800.0)), 0.0)
	var distance := maxf(float(event.get("x", 0.0)) - course_start_x - lead, 0.0)
	return maxi(0, floori(distance / BASE_RUN_SPEED * TICK_RATE))

static func projectiles_at(event: Dictionary, course_start_x: float, tick: float) -> Array[Dictionary]:
	var start_tick := float(eruption_start_tick(event, course_start_x))
	if tick < start_tick:
		return []
	var period := maxi(int(event.get("eruption_period_ticks", 156)), 1)
	var lifetime := maxi(int(event.get("projectile_lifetime_ticks", 58)), 1)
	var launch_index := floori((tick - start_tick) / float(period))
	var age := tick - (start_tick + float(launch_index * period))
	if age < 0.0 or age > float(lifetime):
		return []
	var result: Array[Dictionary] = []
	if int(event.get("projectile_fan_revision", 0)) == GEN15_FAN_REVISION:
		var arcs := _arc_profiles(event)
		for arc_index in range(arcs.size()):
			var arc: Dictionary = arcs[arc_index]
			if age > float(arc.get("lifetime_ticks", lifetime)):
				continue
			for direction in [-1, 1]:
				result.append(_fan_projectile(event, start_tick + float(launch_index * period), age, direction, launch_index, arc_index, arc))
		return result
	for direction in [-1, 1]:
		result.append(_projectile(event, start_tick + float(launch_index * period), age, direction, launch_index))
	return result

static func projectile_positions_for_interval(event: Dictionary, course_start_x: float, start_tick: int, end_tick: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var activation := eruption_start_tick(event, course_start_x)
	if end_tick < activation:
		return result
	var period := maxi(int(event.get("eruption_period_ticks", 156)), 1)
	var lifetime := maxi(int(event.get("projectile_lifetime_ticks", 58)), 1)
	var first_launch := maxi(floori(float(start_tick - activation) / float(period)), 0)
	var last_launch := maxi(floori(float(end_tick - activation) / float(period)), 0)
	for launch_index in range(first_launch, last_launch + 1):
		var launch_tick := activation + launch_index * period
		if launch_tick > end_tick or launch_tick + lifetime < start_tick:
			continue
		if int(event.get("projectile_fan_revision", 0)) == GEN15_FAN_REVISION:
			var arcs := _arc_profiles(event)
			for arc_index in range(arcs.size()):
				var arc: Dictionary = arcs[arc_index]
				var arc_lifetime := minf(float(lifetime), float(arc.get("lifetime_ticks", lifetime)))
				if float(start_tick) > float(launch_tick) + arc_lifetime or float(end_tick) < float(launch_tick):
					continue
				var age_start := clampf(float(start_tick - launch_tick), 0.0, arc_lifetime)
				var age_end := clampf(float(end_tick - launch_tick), 0.0, arc_lifetime)
				for direction in [-1, 1]:
					result.append({"launch_index": launch_index, "direction": direction, "arc_index": arc_index, "start": _fan_projectile(event, float(launch_tick), age_start, direction, launch_index, arc_index, arc), "end": _fan_projectile(event, float(launch_tick), age_end, direction, launch_index, arc_index, arc)})
		else:
			var age_start := clampf(float(start_tick - launch_tick), 0.0, float(lifetime))
			var age_end := clampf(float(end_tick - launch_tick), 0.0, float(lifetime))
			for direction in [-1, 1]:
				result.append({
					"launch_index": launch_index,
					"direction": direction,
					"start": _projectile(event, float(launch_tick), age_start, direction, launch_index),
					"end": _projectile(event, float(launch_tick), age_end, direction, launch_index),
				})
	return result

static func swept_contact_fraction(event: Dictionary, course_start_x: float, start_tick: int, end_tick: int, start_center: Vector2, end_center: Vector2, player_size: Vector2 = Motion.SIZE) -> float:
	var best := INF
	var player_rect := Rect2(start_center - player_size * 0.5, player_size)
	var body_fraction := HazardRules.swept_rect_polygon_fraction(player_rect, end_center - start_center, volcano_body_polygon_world(event)) if str(event.get("kind", "")) == "volcano" else -1.0
	if body_fraction >= 0.0:
		best = body_fraction
	for interval in projectile_positions_for_interval(event, course_start_x, start_tick, end_tick):
		var first: Dictionary = interval.start
		var last: Dictionary = interval.end
		var projectile_start := Vector2(float(first.x), float(first.y))
		var projectile_end := Vector2(float(last.x), float(last.y))
		var radius := float(first.get("radius", event.get("projectile_radius", 14.0)))
		var fraction := HazardRules.swept_rect_circle_fraction(player_rect, end_center - start_center - (projectile_end - projectile_start), projectile_start, radius)
		if fraction >= 0.0 and fraction < best:
			best = fraction
	return best if best != INF else -1.0

static func crack_rect(event: Dictionary, tick: float = 0.0) -> Rect2:
	var x := float(event.get("x", 0.0))
	var y := float(event.get("y", 0.0))
	var width := maxf(float(event.get("width", 120.0)), 1.0)
	var depth := clampf(float(event.get("hot_depth", 14.0)), 4.0, 30.0)
	var from_ceiling := bool(event.get("from_ceiling", false))
	if int(event.get("lava_variant", 0)) == 1:
		return tidal_pool_rect(event, tick)
	return Rect2(Vector2(x - width * 0.5, y - (2.0 if not from_ceiling else 0.0)), Vector2(width, depth + 2.0))

static func tidal_pool_rect(event: Dictionary, tick: float) -> Rect2:
	var x := float(event.get("x", 0.0))
	var surface_y := float(event.get("y", 460.0))
	var period := maxf(float(event.get("pool_period_ticks", 180)), 1.0)
	var phase := (tick + float(event.get("pool_phase_ticks", 0))) / period
	var wave := 0.5 - 0.5 * cos(TAU * phase)
	var min_depth := clampf(float(event.get("pool_min_depth", 6.0)), 4.0, 24.0)
	var max_depth := clampf(float(event.get("pool_max_depth", 30.0)), min_depth, 36.0)
	var min_width := maxf(float(event.get("pool_min_width", float(event.get("width", 160.0)) * 0.58)), 60.0)
	var max_width := maxf(float(event.get("width", 160.0)), min_width)
	var depth := lerpf(min_depth, max_depth, wave)
	var width := lerpf(min_width, max_width, wave)
	return Rect2(Vector2(x - width * 0.5, surface_y - depth), Vector2(width, depth + 2.0))

static func tidal_pool_envelope(event: Dictionary) -> Rect2:
	var x := float(event.get("x", 0.0))
	var y := float(event.get("y", 460.0))
	var width := maxf(float(event.get("width", 160.0)), float(event.get("pool_min_width", 60.0)))
	var depth := clampf(float(event.get("pool_max_depth", 30.0)), 4.0, 36.0)
	return Rect2(Vector2(x - width * 0.5, y - depth), Vector2(width, depth + 2.0))

static func swept_crack_contact_fraction(event: Dictionary, start_tick: int, end_tick: int, start_center: Vector2, end_center: Vector2, body_size: Vector2 = Motion.SIZE) -> float:
	if int(event.get("lava_variant", 0)) != 1:
		var bounds := crack_rect(event)
		var polygon := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		return HazardRules.swept_rect_polygon_fraction(Rect2(start_center - body_size * 0.5, body_size), end_center - start_center, polygon)
	if end_tick < start_tick:
		return -1.0
	const SUBSTEPS := 12
	for index in range(SUBSTEPS + 1):
		var fraction := float(index) / float(SUBSTEPS)
		var center := start_center.lerp(end_center, fraction)
		var tick := lerpf(float(start_tick), float(end_tick), fraction)
		if Rect2(center - body_size * 0.5, body_size).intersects(tidal_pool_rect(event, tick)):
			return fraction
	return -1.0

static func volcano_body_polygon_local(event: Dictionary) -> PackedVector2Array:
	var floor_y := float(event.get("floor_y", 460.0))
	var width := float(event.get("width", 120.0))
	var height := float(event.get("height", 76.0))
	var left := -width * 0.5
	return PackedVector2Array([
		Vector2(left, floor_y),
		Vector2(-width * 0.34, floor_y - height * 0.60),
		Vector2(-width * 0.12, floor_y - height * 0.72),
		Vector2(0.0, floor_y - height),
		Vector2(width * 0.18, floor_y - height * 0.63),
		Vector2(width * 0.37, floor_y - height * 0.52),
		Vector2(width * 0.5, floor_y),
	])

static func volcano_body_polygon_world(event: Dictionary) -> PackedVector2Array:
	var polygon := volcano_body_polygon_local(event)
	var origin := Vector2(float(event.get("x", 0.0)), 0.0)
	for index in range(polygon.size()):
		polygon[index] += origin
	return polygon

## Conservative world-space union of the lethal volcano body and every point a
## paired projectile can occupy during its full lifetime, including hit radius.
## Placement systems use this same source/apex contract instead of maintaining
## a second ballistic approximation.
static func volcano_collision_envelope(event: Dictionary) -> Rect2:
	var body := volcano_body_polygon_world(event)
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in body:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var floor_y := float(event.get("floor_y", 460.0))
	var width := float(event.get("width", 116.0))
	var height := float(event.get("height", 76.0))
	var source_y := floor_y - height * 0.78
	var origin_offset := width * 0.12
	var trajectories: Array[Dictionary] = []
	if int(event.get("projectile_fan_revision", 0)) == GEN15_FAN_REVISION:
		trajectories = _arc_profiles(event)
	else:
		trajectories = [{"horizontal_speed": maxf(float(event.get("projectile_speed", 330.0)), 0.0), "vertical_speed": maxf(float(event.get("projectile_vertical_speed", 570.0)), 0.0), "gravity": maxf(float(event.get("projectile_gravity", 1200.0)), 1.0), "radius": maxf(float(event.get("projectile_radius", 14.0)), 0.0), "lifetime_ticks": maxf(float(event.get("projectile_lifetime_ticks", 58)), 0.0)}]
	for trajectory in trajectories:
		var lifetime := maxf(float(trajectory.get("lifetime_ticks", 0)) / TICK_RATE, 0.0)
		var radius := maxf(float(trajectory.get("radius", 0.0)), 0.0)
		var horizontal_speed := maxf(float(trajectory.get("horizontal_speed", 0.0)), 0.0)
		var vertical_speed := maxf(float(trajectory.get("vertical_speed", 0.0)), 0.0)
		var gravity := maxf(float(trajectory.get("gravity", 1.0)), 1.0)
		var apex_age := clampf(vertical_speed / gravity, 0.0, lifetime)
		var apex_y := source_y - vertical_speed * apex_age + 0.5 * gravity * apex_age * apex_age
		var end_y := source_y - vertical_speed * lifetime + 0.5 * gravity * lifetime * lifetime
		min_x = minf(min_x, float(event.get("x", 0.0)) - origin_offset - horizontal_speed * lifetime - radius)
		max_x = maxf(max_x, float(event.get("x", 0.0)) + origin_offset + horizontal_speed * lifetime + radius)
		min_y = minf(min_y, minf(source_y, apex_y) - radius)
		max_y = maxf(max_y, maxf(source_y, end_y) + radius)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

static func gen15_ceiling_route_is_supported(event: Dictionary, surface_index: Object, course_start_x: float) -> bool:
	if int(event.get("projectile_fan_revision", 0)) != GEN15_FAN_REVISION or surface_index == null or not surface_index.has_method("surface_at"):
		return false
	var envelope := volcano_collision_envelope(event)
	# Cover the whole possible player corridor, not just projectile centers. The
	# surface index checks gap intervals and terrain boundaries analytically, so
	# narrow gaps or steps cannot fall between a fixed 8px sample grid.
	var runner_half_width := RunnerMotion.SIZE.x * 0.5
	if not surface_index.has_method("interval_is_supported") or not surface_index.has_method("lowest_surface_y_over_interval") or not surface_index.has_method("support_boundaries"):
		return false
	if not bool(surface_index.call("interval_is_supported", envelope.position.x - runner_half_width, envelope.end.x + runner_half_width, true)):
		return false
	var full_span_lowest_ceiling := float(surface_index.call("lowest_surface_y_over_interval", envelope.position.x - runner_half_width, envelope.end.x + runner_half_width, true))
	# The envelope's top is the analytic minimum of every arc. Compare it with
	# the lowest roof anywhere beneath that complete swept corridor, so an arc's
	# interior apex cannot slip between otherwise-safe terrain-edge samples.
	if envelope.position.y < full_span_lowest_ceiling + RunnerMotion.SIZE.y + 24.0:
		return false
	var start_tick := eruption_start_tick(event, course_start_x)
	var arcs := _arc_profiles(event)
	var boundaries: Array = surface_index.call("support_boundaries_between", envelope.position.x - runner_half_width, envelope.end.x + runner_half_width, true, true) if surface_index.has_method("support_boundaries_between") else surface_index.call("support_boundaries", true)
	for projectile in projectiles_at(event, course_start_x, float(start_tick)):
		var arc_index := int(projectile.get("arc_index", -1))
		if arc_index < 0 or arc_index >= arcs.size():
			return false
		var arc: Dictionary = arcs[arc_index]
		var vx := float(projectile.get("vx", 0.0))
		if absf(vx) < 0.0001:
			return false
		var initial_x := float(projectile.get("x", 0.0))
		var initial_y := float(projectile.get("y", 0.0))
		var initial_vy := float(projectile.get("vy", 0.0))
		var radius := float(projectile.get("radius", 0.0))
		var gravity := float(arc.get("gravity", 0.0))
		var lifetime := float(arc.get("lifetime_ticks", 0.0)) / TICK_RATE
		var horizontal_reach := radius + runner_half_width
		var candidate_times: Array[float] = [0.0, lifetime]
		# Clearance can change slope only when one edge of the swept projectile
		# plus runner width crosses a surface boundary. Evaluate those exact times.
		for boundary_value in boundaries:
			var boundary := float(boundary_value)
			if boundary < envelope.position.x - runner_half_width or boundary > envelope.end.x + runner_half_width:
				continue
			for edge_offset in [-horizontal_reach, horizontal_reach]:
				var crossing_time: float = (boundary - float(edge_offset) - initial_x) / vx
				if crossing_time > 0.0 and crossing_time < lifetime:
					candidate_times.append(crossing_time)
		candidate_times.sort()
		for age_seconds in candidate_times:
			var projectile_x := initial_x + vx * age_seconds
			var interval_start := projectile_x - horizontal_reach
			var interval_end := projectile_x + horizontal_reach
			if not bool(surface_index.call("interval_is_supported", interval_start, interval_end, true)):
				return false
			var lowest_ceiling := float(surface_index.call("lowest_surface_y_over_interval", interval_start, interval_end, true))
			var projectile_y := initial_y + initial_vy * age_seconds + 0.5 * gravity * age_seconds * age_seconds
			var projectile_top := projectile_y - radius
			var runner_bottom := lowest_ceiling + RunnerMotion.SIZE.y
			if projectile_top < runner_bottom + 24.0:
				return false
	return true

static func _arc_profiles(event: Dictionary) -> Array[Dictionary]:
	var raw: Variant = event.get("projectile_arcs", gen15_fan_arcs())
	var result: Array[Dictionary] = []
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				result.append(item)
	return result

static func _fan_projectile(event: Dictionary, launch_tick: float, age_ticks: float, direction: int, launch_index: int, arc_index: int, arc: Dictionary) -> Dictionary:
	var age := maxf(age_ticks, 0.0) / TICK_RATE
	var horizontal_speed := float(arc.get("horizontal_speed", 0.0))
	var vertical_speed := float(arc.get("vertical_speed", 0.0))
	var gravity := float(arc.get("gravity", 1.0))
	var radius := float(arc.get("radius", 0.0))
	var origin_x := float(event.get("x", 0.0)) + float(direction) * float(event.get("width", 116.0)) * 0.12
	var source_y := float(event.get("floor_y", 460.0)) - float(event.get("height", 76.0)) * 0.78
	return {"projectile_id": "%s:%d:%d:%d" % [str(event.get("event_id", "volcano")), launch_index, arc_index, direction], "launch_index": launch_index, "arc_index": arc_index, "direction": direction, "tick": launch_tick + age_ticks, "x": origin_x + float(direction) * horizontal_speed * age, "y": source_y - vertical_speed * age + 0.5 * gravity * age * age, "vx": float(direction) * horizontal_speed, "vy": -vertical_speed + gravity * age, "radius": radius}

static func _projectile(event: Dictionary, launch_tick: float, age_ticks: float, direction: int, launch_index: int) -> Dictionary:
	var age := maxf(age_ticks, 0.0) / TICK_RATE
	var radius := float(event.get("projectile_radius", 14.0))
	var origin_x := float(event.get("x", 0.0)) + float(direction) * float(event.get("width", 116.0)) * 0.12
	var floor_y := float(event.get("floor_y", 460.0))
	var source_y := floor_y - float(event.get("height", 76.0)) * 0.78
	var speed := float(event.get("projectile_speed", 330.0))
	var vertical_speed := float(event.get("projectile_vertical_speed", 570.0))
	var gravity := float(event.get("projectile_gravity", 1200.0))
	return {
		"launch_index": launch_index,
		"direction": direction,
		"tick": launch_tick + age_ticks,
		"x": origin_x + float(direction) * speed * age,
		"y": source_y - vertical_speed * age + 0.5 * gravity * age * age,
		"radius": radius,
	}
