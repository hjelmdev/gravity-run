extends "res://hazards/hazard.gd"

const SPIKE_DEPTH := 24.0
const SPIKE_COLOR := Color("ff647c")
const WALL_THICKNESS := 4.0

var start_surface_y := 0.0
var end_surface_y := 0.0
var has_spikes := false

func configure_step(start_y: float, end_y: float, attach_to_ceiling: bool, spiked: bool) -> void:
	start_surface_y = start_y
	end_surface_y = end_y
	from_ceiling = attach_to_ceiling
	has_spikes = spiked
	if has_spikes:
		add_to_group("spikes")
	queue_redraw()

func is_terrain_step() -> bool:
	return true

func is_ceiling_slope() -> bool:
	return from_ceiling

func get_start_x() -> float:
	return global_position.x

func get_end_x() -> float:
	return global_position.x

func get_start_y() -> float:
	return start_surface_y

func get_end_y() -> float:
	return end_surface_y

func get_surface_y_at(_x: float) -> float:
	return end_surface_y

func get_surface_angle_at(_x: float) -> float:
	return 0.0

func spikes_point_left() -> bool:
	return (end_surface_y < start_surface_y) != from_ceiling

func scale_track_height(scale: float) -> void:
	start_surface_y = 56.0 + (start_surface_y - 56.0) * scale
	end_surface_y = 56.0 + (end_surface_y - 56.0) * scale
	queue_redraw()

func get_wall_rect() -> Rect2:
	var top := minf(start_surface_y, end_surface_y)
	return Rect2(Vector2(global_position.x - WALL_THICKNESS * 0.5, top), Vector2(WALL_THICKNESS, absf(end_surface_y - start_surface_y)))

func intersects_wall(rect: Rect2) -> bool:
	return get_wall_rect().intersects(rect)

func _draw() -> void:
	if has_spikes:
		_draw_side_spikes()

func _spike_triangles_local() -> Array[PackedVector2Array]:
	var triangles: Array[PackedVector2Array] = []
	var top := minf(start_surface_y, end_surface_y) - global_position.y
	var height := absf(end_surface_y - start_surface_y)
	var count := maxi(2, int(ceil(height / 28.0)))
	var segment := height / float(count)
	var points_left := spikes_point_left()
	var spike_direction := -1.0 if points_left else 1.0
	for i in range(count):
		var center_y := top + (float(i) + 0.5) * segment
		triangles.append(PackedVector2Array([
			Vector2(0.0, center_y - segment * 0.5),
			Vector2(0.0, center_y + segment * 0.5),
			Vector2(spike_direction * SPIKE_DEPTH, center_y)
		]))
	return triangles

func _draw_side_spikes() -> void:
	for triangle in _spike_triangles_local():
		draw_colored_polygon(triangle, SPIKE_COLOR)
		draw_polyline(PackedVector2Array([triangle[0], triangle[2], triangle[1]]), Color("ffd0d8"), 2.0, true)

func intersects_spikes(rect: Rect2) -> bool:
	if not has_spikes:
		return false
	for local_triangle in _spike_triangles_local():
		var triangle := PackedVector2Array()
		for point in local_triangle:
			triangle.append(to_global(point))
		if _triangle_intersects_rect(triangle, rect):
			return true
	return false

func _triangle_intersects_rect(triangle: PackedVector2Array, rect: Rect2) -> bool:
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
