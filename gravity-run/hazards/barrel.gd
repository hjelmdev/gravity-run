extends "res://hazards/hazard.gd"

var roll_angle := 0.0
var roll_speed := 180.0
const ROLL_SPEED_MIN := 160.0
const ROLL_SPEED_MAX := 200.0

func configure(new_size: Vector2, attach_to_ceiling: bool) -> void:
	super.configure(new_size, attach_to_ceiling)
	roll_speed = randf_range(ROLL_SPEED_MIN, ROLL_SPEED_MAX)

func advance_motion(delta: float, movement: float, _player_position: Vector2, floor_y_at: Callable, surface_angle_at: Callable) -> void:
	if is_destroying:
		return
	var travel := movement + roll_speed * delta
	position.x -= travel
	position.y = float(floor_y_at.call(position.x))
	rotation = float(surface_angle_at.call(position.x, false))
	var radius := minf(size.x, size.y) * 0.5
	if radius > 0.0:
		roll_angle -= travel / radius
	queue_redraw()

func _begin_destruction() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center_y := radius if from_ceiling else -radius
	_spawn_destruction_fragments(Vector2(0.0, center_y), [Color("d98245"), Color("743e35"), Color("f0a45d")], 9, Vector2(radius * 1.5, radius * 1.5))

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var radius := minf(size.x, size.y) * 0.5
	var center_y := radius if from_ceiling else -radius
	draw_circle(Vector2(0.0, center_y), radius, Color("d98245"))
	draw_arc(Vector2(0.0, center_y), radius - 8.0, 0.0, TAU, 24, Color("743e35"), 4.0)
	var first_start := Vector2(-radius * 0.55, -radius * 0.45).rotated(roll_angle) + Vector2(0.0, center_y)
	var first_end := Vector2(radius * 0.55, radius * 0.45).rotated(roll_angle) + Vector2(0.0, center_y)
	var second_start := Vector2(radius * 0.55, -radius * 0.45).rotated(roll_angle) + Vector2(0.0, center_y)
	var second_end := Vector2(-radius * 0.55, radius * 0.45).rotated(roll_angle) + Vector2(0.0, center_y)
	draw_line(first_start, first_end, Color("743e35"), 4.0)
	draw_line(second_start, second_end, Color("743e35"), 4.0)

func intersects_rect(rect: Rect2) -> bool:
	var radius := minf(size.x, size.y) * 0.5
	var center_y := radius if from_ceiling else -radius
	var center := to_global(Vector2(0.0, center_y))
	var closest_point := Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	return center.distance_squared_to(closest_point) <= radius * radius
