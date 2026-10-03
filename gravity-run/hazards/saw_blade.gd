extends Node2D
class_name SawBlade

const Model := preload("res://systems/saw_blade_model.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var event: Dictionary = {}
var state: Dictionary = {}
var _previous_state: Dictionary = {}
var _surface_query: Callable
var _render_fraction := 1.0
var from_ceiling := false
var _course_start_x := 0.0
var _simulation_tick := 0

func configure(value: Dictionary, surface_query: Callable, course_start_x: float, initial_tick := 0) -> void:
	event = value.duplicate(true)
	_surface_query = surface_query
	_course_start_x = course_start_x
	_simulation_tick = maxi(initial_tick, 0)
	state = Model.initial_state(event, course_start_x, _simulation_tick, -1)
	_previous_state = state.duplicate(true)
	add_to_group("saw_blades")
	set_process(false)
	_update_pose()

func set_simulation_tick(tick: int) -> void:
	_simulation_tick = maxi(tick, 0)
	_previous_state = state.duplicate(true)
	state = Model.advance(event, state, tick, _surface_query)
	_update_pose()
	queue_redraw()
	_render_fraction = 1.0

func set_activation_tick(activation_tick: int) -> void:
	var current_tick := maxi(_simulation_tick, 0)
	state = Model.initial_state(event, _course_start_x, 0, maxi(activation_tick, 0))
	state = Model.advance(event, state, current_tick, _surface_query)
	_previous_state = state.duplicate(true)
	_update_pose()
	queue_redraw()

func set_render_fraction(fraction: float) -> void:
	_render_fraction = clampf(fraction, 0.0, 1.0)
	if not bool(state.get("active", false)) or bool(state.get("removed", false)):
		return
	var previous_active := bool(_previous_state.get("active", false)) and not bool(_previous_state.get("removed", false))
	var current := Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
	var previous := Vector2(float(_previous_state.get("x", current.x)), float(_previous_state.get("y", current.y))) if previous_active else current
	global_position = previous.lerp(current, _render_fraction)
	rotation = lerpf(float(_previous_state.get("roll_angle", state.get("roll_angle", 0.0))), float(state.get("roll_angle", 0.0)), _render_fraction) if previous_active else float(state.get("roll_angle", 0.0))

func apply_world_state(value: Dictionary) -> void:
	var incoming: Variant = value.get("state", value)
	if not incoming is Dictionary:
		return
	_previous_state = state.duplicate(true)
	state = incoming.duplicate(true)
	_render_fraction = 1.0
	_update_pose()
	queue_redraw()

func _update_pose() -> void:
	from_ceiling = bool(state.get("ceiling_lane", false))
	global_position = Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
	rotation = float(state.get("roll_angle", 0.0))
	visible = bool(state.get("active", false)) and not bool(state.get("removed", false))

func get_hitbox_rect() -> Rect2:
	return Model.hitbox(state)

func is_destroying_now() -> bool:
	return false

func swept_contact_fraction(start_rect: Rect2, finish_rect: Rect2, _start_tick: int, _end_tick: int, _body_size: Vector2) -> float:
	if not bool(state.get("active", false)) or bool(state.get("removed", false)):
		return -1.0
	var current_center := Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0)))
	var previous_center := current_center
	if bool(_previous_state.get("active", false)) and not bool(_previous_state.get("removed", false)):
		previous_center = Vector2(float(_previous_state.get("x", current_center.x)), float(_previous_state.get("y", current_center.y)))
	var relative_displacement := finish_rect.position - start_rect.position - (current_center - previous_center)
	return HazardRules.swept_rect_circle_fraction(start_rect, relative_displacement, previous_center, Model.RADIUS)

func _draw() -> void:
	if not visible:
		return
	# One simple, bounded vector silhouette; collision is the fixed radius above.
	draw_circle(Vector2.ZERO, Model.RADIUS, Color("aeb8bf"))
	draw_circle(Vector2.ZERO, Model.RADIUS * 0.72, Color("39414a"))
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var inner := Vector2.from_angle(angle) * Model.RADIUS * 0.32
		var outer := Vector2.from_angle(angle + 0.18) * Model.RADIUS * 1.04
		var edge := Vector2.from_angle(angle - 0.2) * Model.RADIUS * 1.04
		draw_colored_polygon(PackedVector2Array([inner, outer, edge]), Color("e4e9ed"))
		draw_line(inner, outer, Color("68727b"), 1.2, true)
	draw_circle(Vector2.ZERO, 7.0, Color("20262b"))
	draw_circle(Vector2.ZERO, 3.0, Color("ffb253"))
