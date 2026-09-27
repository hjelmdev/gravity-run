extends RefCounted
class_name HazardInteractionRules

const RunnerMotion := preload("res://systems/runner_motion.gd")

enum BarrelImpact { NONE, BARREL_DESTROYED, BARREL_AND_TARGET_DESTROYED }
enum PlayerImpact { NONE, LETHAL, BLOCKED }

const STEP_WALL_THICKNESS := 4.0
const BARREL_WIDTH := 54.0
const BARREL_CHAIN_SPACING := 70.0
const BARREL_FALL_GRAVITY := 1800.0
const BARREL_STEP_FALL_THRESHOLD := 14.0

static func spike_group_intersects_rect(start_x: float, surface_y: float, count: int, spacing: float, width: float, height: float, from_ceiling: bool, rect: Rect2) -> bool:
	for triangle in spike_group_triangles(start_x, surface_y, count, spacing, width, height, from_ceiling):
		if triangle_intersects_rect(triangle, rect):
			return true
	return false

static func spike_group_triangles(start_x: float, surface_y: float, count: int, spacing: float, width: float, height: float, from_ceiling: bool) -> Array[PackedVector2Array]:
	var triangles: Array[PackedVector2Array] = []
	for index in range(maxi(count, 0)):
		var center_x := start_x + float(index) * spacing
		var tip_y := surface_y + height if from_ceiling else surface_y - height
		triangles.append(PackedVector2Array([
			Vector2(center_x - width * 0.5, surface_y),
			Vector2(center_x + width * 0.5, surface_y),
			Vector2(center_x, tip_y),
		]))
	return triangles

static func triangle_intersects_rect(triangle: PackedVector2Array, rect: Rect2) -> bool:
	if triangle.size() != 3:
		return false
	var rectangle := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	var axes := PackedVector2Array([Vector2.RIGHT, Vector2.DOWN])
	for index in range(triangle.size()):
		var edge: Vector2 = triangle[(index + 1) % triangle.size()] - triangle[index]
		axes.append(Vector2(-edge.y, edge.x).normalized())
	for axis in axes:
		if _projections_are_separate(triangle, rectangle, axis):
			return false
	return true

static func circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(closest) <= radius * radius

static func barrel_radius(width: float, height: float) -> float:
	return minf(width, height) * 0.5

static func barrel_center(base_position: Vector2, width: float, height: float, from_ceiling: bool = false) -> Vector2:
	var radius := barrel_radius(width, height)
	return base_position + Vector2(0.0, radius if from_ceiling else -radius)

static func barrel_impact(center: Vector2, radius: float, target_kind: String, target_rect: Rect2 = Rect2(), target_triangles: Array = []) -> BarrelImpact:
	if target_kind == "spikes":
		for triangle in target_triangles:
			if triangle is PackedVector2Array and circle_intersects_triangle(center, radius, triangle):
				return BarrelImpact.BARREL_DESTROYED
		return BarrelImpact.NONE
	if target_kind == "step":
		return BarrelImpact.BARREL_DESTROYED if circle_intersects_rect(center, radius, target_rect) else BarrelImpact.NONE
	if target_kind == "block" and circle_intersects_rect(center, radius, target_rect):
		return BarrelImpact.BARREL_AND_TARGET_DESTROYED
	return BarrelImpact.NONE

static func step_wall_rect(x: float, start_y: float, end_y: float) -> Rect2:
	return Rect2(Vector2(x - STEP_WALL_THICKNESS * 0.5, minf(start_y, end_y)), Vector2(STEP_WALL_THICKNESS, absf(end_y - start_y)))

static func step_moves_away(gravity_direction: int, from_ceiling: bool, start_y: float, end_y: float) -> bool:
	var surface_delta := end_y - start_y
	return (gravity_direction > 0 and not from_ceiling and surface_delta > 0.0) or (gravity_direction < 0 and from_ceiling and surface_delta < 0.0)

static func player_impact(player_rect: Rect2, target_kind: String, target_rect: Rect2 = Rect2(), target_triangles: Array = [], circle_center: Vector2 = Vector2.ZERO, circle_radius: float = 0.0, spike_immune: bool = false, gravity_direction: int = 1, from_ceiling: bool = false, step_start_y: float = 0.0, step_end_y: float = 0.0) -> PlayerImpact:
	match target_kind:
		"spikes":
			if spike_immune:
				return PlayerImpact.NONE
			for triangle in target_triangles:
				if triangle is PackedVector2Array and triangle_intersects_rect(triangle, player_rect):
					return PlayerImpact.LETHAL
		"step":
			if player_rect.intersects(target_rect) and not step_moves_away(gravity_direction, from_ceiling, step_start_y, step_end_y):
				return PlayerImpact.BLOCKED
		"edge":
			if player_rect.intersects(target_rect):
				return PlayerImpact.BLOCKED
		"barrel":
			if circle_intersects_rect(circle_center, circle_radius, player_rect):
				return PlayerImpact.LETHAL
		"block", "rect":
			if player_rect.intersects(target_rect):
				return PlayerImpact.LETHAL
	return PlayerImpact.NONE

static func advance_barrel(state: Dictionary, delta: float, movement: float, floor_y: float, surface_angle: float, floor_supported: bool) -> float:
	var multiplier := maxf(float(state.get("motion_speed_multiplier", 1.0)), 1.0)
	var motion_reference := movement if movement > 0.0 else RunnerMotion.BASE_RUN_SPEED * maxf(delta, 0.0)
	var relative_travel := motion_reference * (multiplier - 1.0)
	state["x"] = float(state.get("x", 0.0)) - relative_travel
	if bool(state.get("is_falling", state.get("falling", false))):
		var fall_velocity := float(state.get("fall_velocity", 0.0)) + BARREL_FALL_GRAVITY * delta
		state["y"] = float(state.get("y", 0.0)) + fall_velocity * delta
		state["fall_velocity"] = fall_velocity
		if floor_supported and float(state["y"]) >= floor_y:
			state["y"] = floor_y
			state["fall_velocity"] = 0.0
			state["is_falling"] = false
			state["falling"] = false
	elif not floor_supported or floor_y - float(state.get("y", 0.0)) > BARREL_STEP_FALL_THRESHOLD:
		state["is_falling"] = true
		state["falling"] = true
		state["fall_velocity"] = 0.0
	elif floor_y - float(state.get("y", 0.0)) >= -BARREL_STEP_FALL_THRESHOLD:
		state["y"] = floor_y
	state["rotation"] = surface_angle
	var radius := minf(float(state.get("width", BARREL_WIDTH)), float(state.get("height", BARREL_WIDTH))) * 0.5
	if radius > 0.0:
		state["roll_angle"] = float(state.get("roll_angle", 0.0)) - relative_travel / radius
	return relative_travel

static func circle_intersects_triangle(center: Vector2, radius: float, triangle: PackedVector2Array) -> bool:
	if triangle.size() != 3:
		return false
	var closest := triangle[0]
	var closest_distance := center.distance_squared_to(closest)
	for index in range(3):
		var first: Vector2 = triangle[index]
		var second: Vector2 = triangle[(index + 1) % 3]
		var edge := second - first
		var amount := clampf((center - first).dot(edge) / maxf(edge.length_squared(), 0.000001), 0.0, 1.0)
		var candidate := first + edge * amount
		var distance := center.distance_squared_to(candidate)
		if distance < closest_distance:
			closest = candidate
			closest_distance = distance
	return closest_distance <= radius * radius or _point_in_triangle(center, triangle)

static func _point_in_triangle(point: Vector2, triangle: PackedVector2Array) -> bool:
	var first := (triangle[1] - triangle[0]).cross(point - triangle[0])
	var second := (triangle[2] - triangle[1]).cross(point - triangle[1])
	var third := (triangle[0] - triangle[2]).cross(point - triangle[2])
	return (first >= 0.0 and second >= 0.0 and third >= 0.0) or (first <= 0.0 and second <= 0.0 and third <= 0.0)

static func _projections_are_separate(first: PackedVector2Array, second: PackedVector2Array, axis: Vector2) -> bool:
	var first_min := first[0].dot(axis)
	var first_max := first_min
	for point in first:
		var projection := point.dot(axis)
		first_min = minf(first_min, projection)
		first_max = maxf(first_max, projection)
	var second_min := second[0].dot(axis)
	var second_max := second_min
	for point in second:
		var projection := point.dot(axis)
		second_min = minf(second_min, projection)
		second_max = maxf(second_max, projection)
	return first_max < second_min or second_max < first_min
