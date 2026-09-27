extends RefCounted
class_name CourseSurfaceRenderer

const FILL_COLOR := Color("202d40")
const EDGE_COLOR := Color("42d6c5")
const SAMPLE_SPACING := 16.0

static func draw_track(canvas: CanvasItem, view_left: float, view_size: Vector2, gap_intervals: Array[Dictionary], terrain_boundaries: Array[float], step_positions: Array[float], surface_y_at: Callable, canvas_origin_x: float) -> void:
	_draw_surface(canvas, true, view_left, view_size, gap_intervals, terrain_boundaries, step_positions, surface_y_at, canvas_origin_x)
	_draw_surface(canvas, false, view_left, view_size, gap_intervals, terrain_boundaries, step_positions, surface_y_at, canvas_origin_x)

static func _draw_surface(canvas: CanvasItem, ceiling: bool, view_left: float, view_size: Vector2, all_gaps: Array[Dictionary], terrain_boundaries: Array[float], step_positions: Array[float], surface_y_at: Callable, canvas_origin_x: float) -> void:
	var view_right := view_left + view_size.x
	var gaps: Array[Dictionary] = []
	for gap in all_gaps:
		if bool(gap.get("ceiling", false)) != ceiling:
			continue
		var start_x := float(gap.get("start", 0.0))
		var end_x := float(gap.get("end", 0.0))
		if end_x > view_left and start_x < view_right:
			gaps.append({"start": start_x, "end": end_x})
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
	var cursor := view_left
	for gap in gaps:
		var gap_start := clampf(float(gap.start), view_left, view_right)
		var gap_end := clampf(float(gap.end), view_left, view_right)
		if gap_end <= cursor:
			continue
		if gap_start > cursor:
			_draw_segment(canvas, ceiling, cursor, gap_start, canvas_origin_x, view_size, terrain_boundaries, step_positions, surface_y_at)
		cursor = maxf(cursor, gap_end)
	if cursor < view_right:
		_draw_segment(canvas, ceiling, cursor, view_right, canvas_origin_x, view_size, terrain_boundaries, step_positions, surface_y_at)

static func _draw_segment(canvas: CanvasItem, ceiling: bool, start_x: float, end_x: float, canvas_origin_x: float, view_size: Vector2, terrain_boundaries: Array[float], step_positions: Array[float], surface_y_at: Callable) -> void:
	if end_x - start_x < 0.5:
		return
	var xs: Array[float] = [start_x]
	var x := ceilf(start_x / SAMPLE_SPACING) * SAMPLE_SPACING
	while x < end_x:
		if x > start_x:
			xs.append(x)
		x += SAMPLE_SPACING
	for boundary in terrain_boundaries:
		if boundary > start_x and boundary < end_x:
			xs.append(boundary)
	for step_x in step_positions:
		if step_x > start_x and step_x < end_x:
			xs.append(step_x)
	xs.append(end_x)
	xs.sort()
	var points := PackedVector2Array()
	var previous_x := -INF
	for point_x in xs:
		if is_equal_approx(point_x, previous_x):
			continue
		previous_x = point_x
		var is_step := false
		for step_x in step_positions:
			if is_equal_approx(step_x, point_x):
				is_step = true
				break
		if is_step:
			points.append(Vector2(point_x - canvas_origin_x, float(surface_y_at.call(point_x - 0.01, ceiling))))
			points.append(Vector2(point_x - canvas_origin_x, float(surface_y_at.call(point_x + 0.01, ceiling))))
		else:
			points.append(Vector2(point_x - canvas_origin_x, float(surface_y_at.call(point_x, ceiling))))
	var fill := PackedVector2Array()
	if ceiling:
		fill.append(Vector2(start_x - canvas_origin_x, 0.0))
		fill.append_array(points)
		fill.append(Vector2(end_x - canvas_origin_x, 0.0))
	else:
		fill.append_array(points)
		fill.append(Vector2(end_x - canvas_origin_x, view_size.y))
		fill.append(Vector2(start_x - canvas_origin_x, view_size.y))
	canvas.draw_colored_polygon(fill, FILL_COLOR)
	canvas.draw_polyline(points, EDGE_COLOR, 3.0, true)
