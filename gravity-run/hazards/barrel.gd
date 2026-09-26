extends "res://hazards/hazard.gd"

var roll_angle := 0.0
var fall_velocity := 0.0
var is_falling := false
var motion_speed_multiplier := 1.0
const FALL_GRAVITY := 1800.0
const STEP_FALL_THRESHOLD := 14.0
const STOPPED_PLAYER_REFERENCE_SPEED := 500.0

func configure(new_size: Vector2, attach_to_ceiling: bool) -> void:
	super.configure(new_size, attach_to_ceiling)
	fall_velocity = 0.0
	is_falling = false

func scale_track_height(scale: float) -> void:
	fall_velocity *= scale

func set_motion_speed_multiplier(multiplier: float) -> void:
	motion_speed_multiplier = maxf(multiplier, 1.0)

func advance_motion(delta: float, movement: float, _player_position: Vector2, floor_y_at: Callable, surface_angle_at: Callable, surface_supported_at: Callable = Callable()) -> void:
	if is_destroying:
		return
	# The course is static in world space and the player moves right. A barrel's
	# extra relative speed is therefore represented as leftward world motion.
	var motion_reference := movement
	if movement <= 0.0 and delta > 0.0:
		# The rolling barrel still has autonomous motion while the runner is
		# blocked. Use the same world-speed reference as while running.
		motion_reference = STOPPED_PLAYER_REFERENCE_SPEED * delta
	var relative_travel := motion_reference * (motion_speed_multiplier - 1.0)
	position.x -= relative_travel
	var floor_y := float(floor_y_at.call(position.x))
	var floor_supported := true
	if surface_supported_at.is_valid():
		floor_supported = bool(surface_supported_at.call(position.x, false))
	if is_falling:
		var previous_y := position.y
		fall_velocity += FALL_GRAVITY * delta
		position.y += fall_velocity * delta
		if floor_supported and previous_y <= floor_y and position.y >= floor_y:
			position.y = floor_y
			fall_velocity = 0.0
			is_falling = false
	else:
		var floor_delta := floor_y - position.y
		if not floor_supported or floor_delta > STEP_FALL_THRESHOLD:
			is_falling = true
			fall_velocity = 0.0
		elif floor_delta >= -STEP_FALL_THRESHOLD:
			position.y = floor_y
	rotation = float(surface_angle_at.call(position.x, false))
	var radius := minf(size.x, size.y) * 0.5
	if radius > 0.0:
		# Camera motion changes apparent screen velocity, not the barrel's own
		# angular velocity. Spin only from its world-space travel.
		roll_angle -= relative_travel / radius
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
