extends Node2D
class_name FallingRock

const Model := preload("res://systems/falling_rock_model.gd")
var event: Dictionary = {}
var simulation_tick := 0
var activation_tick := -1
var _previous_tick := 0
var _phase := "dormant"
var _shake := 0.0
var _render_tick := 0.0
var _render_phase := "dormant"
var _render_hitbox := Rect2()

func apply_world_state(value: Dictionary) -> void:
	if value.has("activation_tick"):
		set_activation_tick(int(value.activation_tick))
	_render_tick = maxf(float(value.get("tick", simulation_tick)), 0.0)
	simulation_tick = int(floor(_render_tick))
	_phase = str(value.get("phase", Model.phase_at(event, activation_tick, simulation_tick)))
	_render_phase = _phase
	_render_hitbox = value.get("rect", Model.hitbox_at(event, activation_tick, _render_tick))
	position = Vector2(float(value.get("x", event.get("x", 0.0))), float(value.get("y", position.y)))
	queue_redraw()

func configure(value: Dictionary) -> void:
	event = value.duplicate(true)
	position.x = float(event.get("x", 0.0))
	add_to_group("falling_rocks")
	set_simulation_tick(simulation_tick)

func set_activation_tick(value: int) -> void:
	if activation_tick >= 0:
		return
	activation_tick = value
	queue_redraw()

func set_simulation_tick(value: int) -> void:
	_previous_tick = simulation_tick
	simulation_tick = maxi(value, 0)
	_phase = Model.phase_at(event, activation_tick, simulation_tick)
	_render_tick = float(simulation_tick)
	_render_phase = _phase
	_render_hitbox = Model.hitbox_at(event, activation_tick, _render_tick)
	position = Model.center_at(event, activation_tick, simulation_tick)
	_shake = 1.8 * sin(float(simulation_tick) * 1.7) if _phase == "warning" else 0.0
	queue_redraw()

func set_render_fraction(fraction: float) -> void:
	_render_tick = lerpf(float(_previous_tick), float(simulation_tick), clampf(fraction, 0.0, 1.0))
	_render_phase = Model.phase_at(event, activation_tick, floori(_render_tick))
	_render_hitbox = Model.hitbox_at(event, activation_tick, _render_tick)
	position = Model.center_at(event, activation_tick, _render_tick)
	queue_redraw()

func get_phase() -> String:
	return _phase

func get_activation_tick() -> int:
	return activation_tick

func get_hitbox_rect() -> Rect2:
	return Model.hitbox_at(event, activation_tick, simulation_tick)

func swept_contact_fraction(previous_rect: Rect2, current_rect: Rect2, start_tick: int, end_tick: int, body_size: Vector2) -> float:
	return Model.swept_contact_fraction(event, activation_tick, start_tick, end_tick, previous_rect.get_center(), current_rect.get_center(), body_size)

func is_destroying_now() -> bool:
	return false

func _draw() -> void:
	if event.is_empty():
		return
	var width := float(event.get("width", Model.WIDTH))
	var height := float(event.get("height", Model.HEIGHT))
	if _render_phase in ["dormant", "warning"]:
		var hanging := Rect2(Vector2(-width * 0.5 + _shake, -height * 0.5), Vector2(width, height))
		draw_colored_polygon(PackedVector2Array([hanging.position + Vector2(0, -height * 0.5), Vector2(hanging.end.x, hanging.position.y + 10), Vector2(hanging.end.x - 5, hanging.end.y - 12), Vector2(hanging.position.x + 4, hanging.end.y)]), Color("7c7770"))
		draw_line(Vector2(-width * 0.24, -height * 0.28), Vector2(-width * 0.06, -height * 0.03), Color("383c40"), 3.0)
		draw_line(Vector2(width * 0.08, -height * 0.12), Vector2(width * 0.28, height * 0.13), Color("383c40"), 3.0)
		if _render_phase == "warning":
			var floor_y := float(event.get("floor_y", 460.0))
			var marker_y := floor_y - Model.BURIAL_DEPTH
			draw_arc(Vector2(0, marker_y - position.y), width * 0.7, PI, TAU, 24, Color("ffb45b"), 3.5)
			draw_line(Vector2(-width * 0.55, marker_y - position.y), Vector2(width * 0.55, marker_y - position.y), Color("ff814f"), 3.0)
	else:
		var rect := _render_hitbox
		var local_rect := Rect2(rect.position - position, rect.size)
		draw_rect(local_rect, Color("676a68"))
		draw_line(local_rect.position + Vector2(width * 0.3, 8), local_rect.position + Vector2(width * 0.46, height * 0.45), Color("30383c"), 3.0)
		if _render_phase == "falling":
			draw_circle(Vector2(0, height * 0.55), width * 0.36, Color(0.68, 0.62, 0.5, 0.28))
		else:
			var floor_y := float(event.get("floor_y", 460.0))
			draw_line(Vector2(-width * 0.52, floor_y - position.y), Vector2(width * 0.52, floor_y - position.y), Color("c79466"), 2.0)
