extends "res://hazards/hazard.gd"

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var points: PackedVector2Array
	if from_ceiling:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, size.y)])
	else:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, -size.y)])
	draw_colored_polygon(points, Color("ff647c"))
	draw_line(points[0], points[2], Color("ffd0d8"), 3.0)

func intersects_rect(rect: Rect2) -> bool:
	var local_points := PackedVector2Array()
	if from_ceiling:
		local_points = PackedVector2Array([
			Vector2(-size.x * 0.5, 0.0),
			Vector2(size.x * 0.5, 0.0),
			Vector2(0.0, size.y)
		])
	else:
		local_points = PackedVector2Array([
			Vector2(-size.x * 0.5, 0.0),
			Vector2(size.x * 0.5, 0.0),
			Vector2(0.0, -size.y)
		])
	var triangle := PackedVector2Array()
	for point in local_points:
		triangle.append(to_global(point))
	var rectangle := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	])
	var axes := PackedVector2Array([Vector2.RIGHT, Vector2.DOWN])
	for i in range(triangle.size()):
		var edge: Vector2 = triangle[(i + 1) % triangle.size()] - triangle[i]
		axes.append(Vector2(-edge.y, edge.x).normalized())
	for axis in axes:
		if _projections_are_separate(triangle, rectangle, axis):
			return false
	return true

func _projections_are_separate(first: PackedVector2Array, second: PackedVector2Array, axis: Vector2) -> bool:
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
