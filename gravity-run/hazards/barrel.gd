extends "res://hazards/hazard.gd"

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")

var roll_angle := 0.0
var fall_velocity := 0.0
var is_falling := false
var motion_speed_multiplier := 1.0

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
	var state := {
		"x": position.x,
		"y": position.y,
		"width": size.x,
		"height": size.y,
		"motion_speed_multiplier": motion_speed_multiplier,
		"fall_velocity": fall_velocity,
		"is_falling": is_falling,
		"roll_angle": roll_angle,
		"rotation": rotation,
	}
	var reference_movement := movement if movement > 0.0 else RunnerMotion.BASE_RUN_SPEED * maxf(delta, 0.0)
	var projected_x := position.x - reference_movement * (motion_speed_multiplier - 1.0)
	var floor_y := float(floor_y_at.call(projected_x))
	var floor_supported := not surface_supported_at.is_valid() or bool(surface_supported_at.call(projected_x, false))
	HazardRules.advance_barrel(state, delta, movement, floor_y, float(surface_angle_at.call(projected_x, false)), floor_supported)
	position.x = float(state.x)
	position.y = float(state.y)
	fall_velocity = float(state.fall_velocity)
	is_falling = bool(state.is_falling)
	roll_angle = float(state.roll_angle)
	rotation = float(state.rotation)
	queue_redraw()

func _begin_destruction() -> void:
	var radius := HazardRules.barrel_radius(size.x, size.y)
	var center_y := radius if from_ceiling else -radius
	_spawn_destruction_fragments(Vector2(0.0, center_y), [Color("d98245"), Color("743e35"), Color("f0a45d")], 9, Vector2(radius * 1.5, radius * 1.5))

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var radius := HazardRules.barrel_radius(size.x, size.y)
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
	var radius := HazardRules.barrel_radius(size.x, size.y)
	var center := HazardRules.barrel_center(global_position, size.x, size.y, from_ceiling)
	return HazardRules.circle_intersects_rect(center, radius, rect)
