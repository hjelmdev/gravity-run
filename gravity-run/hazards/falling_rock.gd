extends Node2D
class_name FallingRock

const Model := preload("res://systems/falling_rock_model.gd")
const WarningIcon := preload("res://systems/rock_warning_icon.gd")
const ImpactDebris := preload("res://hazards/rock_impact_debris.gd")
const GroundRenderer := preload("res://systems/course_surface_renderer.gd")
const VISUAL_GROUND_OCCLUSION_DEPTH := 8.0
var event: Dictionary = {}
var simulation_tick := 0
var activation_tick := -1
var _previous_tick := 0
var _phase := "dormant"
var _shake := 0.0
var _render_tick := 0.0
var _render_phase := "dormant"
var _render_hitbox := Rect2()
var _impact_debris_spawned := false

func apply_world_state(value: Dictionary) -> void:
	if value.has("activation_tick"):
		set_activation_tick(int(value.activation_tick))
	_render_tick = maxf(float(value.get("tick", simulation_tick)), 0.0)
	simulation_tick = int(floor(_render_tick))
	var next_phase := str(value.get("phase", Model.phase_at(event, activation_tick, simulation_tick)))
	if _phase == "falling" and next_phase == "buried":
		_spawn_impact_debris_once()
	_phase = next_phase
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
	var next_phase := Model.phase_at(event, activation_tick, simulation_tick)
	if _phase == "falling" and next_phase == "buried":
		_spawn_impact_debris_once()
	_phase = next_phase
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

static func buried_ground_occlusion_mask(surface_local_y: float, rock_width: float, depth: float = VISUAL_GROUND_OCCLUSION_DEPTH) -> Rect2:
	var mask_depth := maxf(depth, 0.0)
	return Rect2(Vector2(-rock_width * 0.68, surface_local_y - mask_depth), Vector2(rock_width * 1.36, mask_depth + 5.0))

func _spawn_impact_debris_once() -> void:
	if _impact_debris_spawned or not is_inside_tree():
		return
	_impact_debris_spawned = true
	var effect := ImpactDebris.new() as Node2D
	effect.name = "RockImpactDebris"
	get_parent().add_child(effect)
	effect.global_position = Vector2(global_position.x, float(event.get("floor_y", 460.0)) - Model.BURIAL_DEPTH)

func _draw() -> void:
	if event.is_empty():
		return
	var width := float(event.get("width", Model.WIDTH))
	var height := float(event.get("height", Model.HEIGHT))
	if _render_phase in ["dormant", "warning"]:
		var hanging := Rect2(Vector2(-width * 0.5 + _shake, -height * 0.5), Vector2(width, height))
		_draw_stone_silhouette(hanging)
		if _render_phase == "warning":
			var floor_y := float(event.get("floor_y", 460.0))
			var sign_center := Vector2(0.0, floor_y - 68.0 - position.y)
			WarningIcon.draw(self, sign_center, 52.0)
	else:
		var rect := _render_hitbox
		var local_rect := Rect2(rect.position - position, rect.size)
		_draw_stone_silhouette(local_rect)
		if _render_phase == "falling":
			draw_circle(Vector2(0, height * 0.55), width * 0.36, Color(0.68, 0.62, 0.5, 0.28))
		else:
			var floor_y := float(event.get("floor_y", 460.0))
			var surface_y := floor_y - position.y
			# The visible ground is drawn after the stone so its surface clearly
			# occludes the lower polygon. This is presentation-only; the model hitbox
			# remains the full permanent buried rectangle.
			draw_rect(buried_ground_occlusion_mask(surface_y, width), GroundRenderer.FILL_COLOR)
			var edge_color := GroundRenderer.EDGE_COLOR
			edge_color.a = 0.82
			draw_line(Vector2(-width * 0.76, surface_y), Vector2(-width * 0.68, surface_y), edge_color, 2.0, true)
			draw_line(Vector2(width * 0.68, surface_y), Vector2(width * 0.76, surface_y), edge_color, 2.0, true)
			var crack_color := Color("b28c69", 0.82)
			draw_polyline(PackedVector2Array([Vector2(-width * 0.94, surface_y - 2.0), Vector2(-width * 0.82, surface_y + 1.0), Vector2(-width * 0.72, surface_y + 6.0)]), crack_color, 2.0, true)
			draw_polyline(PackedVector2Array([Vector2(width * 0.94, surface_y - 2.0), Vector2(width * 0.82, surface_y + 1.0), Vector2(width * 0.72, surface_y + 6.0)]), crack_color, 2.0, true)

func _draw_stone_silhouette(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var origin := rect.position
	var size := rect.size
	var points := PackedVector2Array([
		origin + Vector2(0.00 * size.x, 0.20 * size.y),
		origin + Vector2(0.13 * size.x, 0.04 * size.y),
		origin + Vector2(0.34 * size.x, 0.12 * size.y),
		origin + Vector2(0.52 * size.x, 0.00 * size.y),
		origin + Vector2(0.81 * size.x, 0.08 * size.y),
		origin + Vector2(1.00 * size.x, 0.22 * size.y),
		origin + Vector2(0.94 * size.x, 0.68 * size.y),
		origin + Vector2(0.73 * size.x, 0.96 * size.y),
		origin + Vector2(0.48 * size.x, 0.84 * size.y),
		origin + Vector2(0.20 * size.x, 1.00 * size.y),
		origin + Vector2(0.04 * size.x, 0.77 * size.y),
	])
	draw_colored_polygon(points, Color("747773"))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color("454a49"), 2.0, true)
	draw_line(origin + Vector2(size.x * 0.29, size.y * 0.29), origin + Vector2(size.x * 0.42, size.y * 0.55), Color("353c3f"), 2.5)
	draw_line(origin + Vector2(size.x * 0.42, size.y * 0.55), origin + Vector2(size.x * 0.34, size.y * 0.69), Color("353c3f"), 2.5)
	draw_line(origin + Vector2(size.x * 0.64, size.y * 0.20), origin + Vector2(size.x * 0.53, size.y * 0.42), Color("353c3f"), 2.0)
