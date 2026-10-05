extends RefCounted
class_name LavaHazardModel
## Deterministic shared lava geometry and projectile timing for SP and MP.

const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const TICK_RATE := 60.0
const BASE_RUN_SPEED := Motion.BASE_RUN_SPEED

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
		for direction in [-1, 1]:
			var age_start := clampf(float(start_tick - launch_tick), 0.0, float(lifetime))
			var age_end := clampf(float(end_tick - launch_tick), 0.0, float(lifetime))
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
		var radius := float(event.get("projectile_radius", 14.0))
		var fraction := HazardRules.swept_rect_circle_fraction(player_rect, end_center - start_center - (projectile_end - projectile_start), projectile_start, radius)
		if fraction >= 0.0 and fraction < best:
			best = fraction
	return best if best != INF else -1.0

static func crack_rect(event: Dictionary) -> Rect2:
	var x := float(event.get("x", 0.0))
	var y := float(event.get("y", 0.0))
	var width := maxf(float(event.get("width", 120.0)), 1.0)
	var depth := clampf(float(event.get("hot_depth", 14.0)), 4.0, 30.0)
	var from_ceiling := bool(event.get("from_ceiling", false))
	return Rect2(Vector2(x - width * 0.5, y - (2.0 if not from_ceiling else 0.0)), Vector2(width, depth + 2.0))

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
	var lifetime := maxf(float(event.get("projectile_lifetime_ticks", 58)) / TICK_RATE, 0.0)
	var radius := maxf(float(event.get("projectile_radius", 14.0)), 0.0)
	var horizontal_speed := maxf(float(event.get("projectile_speed", 330.0)), 0.0)
	var vertical_speed := maxf(float(event.get("projectile_vertical_speed", 570.0)), 0.0)
	var gravity := maxf(float(event.get("projectile_gravity", 1200.0)), 1.0)
	var source_y := floor_y - height * 0.78
	var apex_age := clampf(vertical_speed / gravity, 0.0, lifetime)
	var apex_y := source_y - vertical_speed * apex_age + 0.5 * gravity * apex_age * apex_age
	var end_y := source_y - vertical_speed * lifetime + 0.5 * gravity * lifetime * lifetime
	var origin_offset := width * 0.12
	min_x = minf(min_x, float(event.get("x", 0.0)) - origin_offset - horizontal_speed * lifetime - radius)
	max_x = maxf(max_x, float(event.get("x", 0.0)) + origin_offset + horizontal_speed * lifetime + radius)
	min_y = minf(min_y, minf(source_y, apex_y) - radius)
	max_y = maxf(max_y, maxf(source_y, end_y) + radius)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

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
