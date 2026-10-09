extends Node2D
class_name SawBlade

const Model := preload("res://systems/saw_blade_model.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var event: Dictionary = {}
var state: Dictionary = {}
var _previous_state: Dictionary = {}
var _surface_query: Callable
var _render_fraction := 1.0
var _render_roll_angle := 0.0
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
	_render_roll_angle = lerpf(float(_previous_state.get("roll_angle", state.get("roll_angle", 0.0))), float(state.get("roll_angle", 0.0)), _render_fraction) if previous_active else float(state.get("roll_angle", 0.0))
	rotation = 0.0 if Model.is_embedded_variant(event) else _render_roll_angle
	queue_redraw()

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
	_render_roll_angle = float(state.get("roll_angle", 0.0))
	rotation = 0.0 if Model.is_embedded_variant(event) else _render_roll_angle
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
	return HazardRules.swept_rect_circle_fraction(start_rect, relative_displacement, previous_center, Model.radius_for_state(state))

func _draw() -> void:
	if not visible:
		return
	var radius := Model.radius_for_state(state)
	if BiomeRenderer.locked_pixel_palette() != null:
		_draw_pixel_saw(radius)
		return
	if Model.is_embedded_variant(event):
		if bool(state.get("falling", false)):
			_draw_full_silhouette(radius, _render_roll_angle)
		else:
			_draw_embedded_silhouette(radius)
		return
	# Keep the v9 full-silhouette drawing path unchanged.
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

func _draw_full_silhouette(radius: float, angle: float) -> void:
	draw_colored_polygon(_circle_polygon(radius, angle), Color("aeb8bf"))
	draw_colored_polygon(_circle_polygon(radius * 0.72, angle), Color("39414a"))
	for index in range(8):
		var tooth_angle := TAU * float(index) / 8.0
		var inner := _rotate_point(Vector2.from_angle(tooth_angle) * radius * 0.32, angle)
		var outer := _rotate_point(Vector2.from_angle(tooth_angle + 0.18) * radius * 1.04, angle)
		var edge := _rotate_point(Vector2.from_angle(tooth_angle - 0.2) * radius * 1.04, angle)
		draw_colored_polygon(PackedVector2Array([inner, outer, edge]), Color("e4e9ed"))
		draw_line(inner, outer, Color("68727b"), 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -7), Vector2(7, -7), Vector2(7, 7), Vector2(-7, 7)]), Color("20262b"))
	draw_circle(Vector2.ZERO, 3.0, Color("ffb253"))

func _draw_embedded_silhouette(radius: float) -> void:
	# Draw only the side exposed above the floor or below the ceiling. The
	# collision stays a full radius-34 circle, while the terrain-facing half is
	# visually occluded by clipping every primitive at the actual support line.
	var visible_below_surface := bool(state.get("ceiling_lane", false))
	var outer_circle := _circle_polygon(radius, _render_roll_angle)
	var clipped_outer := _clip_at_surface(outer_circle, visible_below_surface)
	if clipped_outer.size() >= 3:
		draw_colored_polygon(clipped_outer, Color("aeb8bf"))
	var inner_circle := _circle_polygon(radius * 0.72, _render_roll_angle)
	var clipped_inner := _clip_at_surface(inner_circle, visible_below_surface)
	if clipped_inner.size() >= 3:
		draw_colored_polygon(clipped_inner, Color("39414a"))
	for index in range(8):
		var tooth_angle := TAU * float(index) / 8.0
		var inner := Vector2.from_angle(tooth_angle) * radius * 0.32
		var outer := Vector2.from_angle(tooth_angle + 0.18) * radius * 1.04
		var edge := Vector2.from_angle(tooth_angle - 0.2) * radius * 1.04
		var tooth := PackedVector2Array([_rotate_point(inner, _render_roll_angle), _rotate_point(outer, _render_roll_angle), _rotate_point(edge, _render_roll_angle)])
		var clipped_tooth := _clip_at_surface(tooth, visible_below_surface)
		if clipped_tooth.size() >= 3:
			draw_colored_polygon(clipped_tooth, Color("e4e9ed"))
		var line_start := _rotate_point(inner, _render_roll_angle)
		var line_end := _rotate_point(outer, _render_roll_angle)
		var clipped_segment := _clip_segment_at_surface(line_start, line_end, visible_below_surface)
		if clipped_segment.size() == 2:
			draw_line(clipped_segment[0], clipped_segment[1], Color("68727b"), 1.2, true)
	var hub := PackedVector2Array([_rotate_point(Vector2(-7.0, -7.0), _render_roll_angle), _rotate_point(Vector2(7.0, -7.0), _render_roll_angle), _rotate_point(Vector2(7.0, 7.0), _render_roll_angle), _rotate_point(Vector2(-7.0, 7.0), _render_roll_angle)])
	var clipped_hub := _clip_at_surface(hub, visible_below_surface)
	if clipped_hub.size() >= 3:
		draw_colored_polygon(clipped_hub, Color("20262b"))
	var axle := PackedVector2Array([_rotate_point(Vector2(-3.0, -3.0), _render_roll_angle), _rotate_point(Vector2(3.0, -3.0), _render_roll_angle), _rotate_point(Vector2(3.0, 3.0), _render_roll_angle), _rotate_point(Vector2(-3.0, 3.0), _render_roll_angle)])
	var clipped_axle := _clip_at_surface(axle, visible_below_surface)
	if clipped_axle.size() >= 3:
		draw_colored_polygon(clipped_axle, Color("ffb253"))

func _circle_polygon(radius: float, angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(40):
		points.append(_rotate_point(Vector2.from_angle(TAU * float(index) / 40.0) * radius, angle))
	return points

func _rotate_point(point: Vector2, angle: float) -> Vector2:
	return point.rotated(angle)

func _clip_at_surface(polygon: PackedVector2Array, visible_below_surface: bool) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	if polygon.is_empty():
		return clipped
	for index in range(polygon.size()):
		var current := polygon[index]
		var previous := polygon[(index - 1 + polygon.size()) % polygon.size()]
		var current_distance := _surface_clip_distance(current, visible_below_surface)
		var previous_distance := _surface_clip_distance(previous, visible_below_surface)
		var current_inside := current_distance >= 0.0
		var previous_inside := previous_distance >= 0.0
		if current_inside != previous_inside:
			var denominator := current_distance - previous_distance
			if not is_zero_approx(denominator):
				var fraction := -previous_distance / denominator
				clipped.append(previous.lerp(current, fraction))
		if current_inside:
			clipped.append(current)
	return clipped

func _clip_segment_at_surface(start: Vector2, finish: Vector2, visible_below_surface: bool) -> PackedVector2Array:
	var start_distance := _surface_clip_distance(start, visible_below_surface)
	var finish_distance := _surface_clip_distance(finish, visible_below_surface)
	var start_inside := start_distance >= 0.0
	var finish_inside := finish_distance >= 0.0
	if start_inside and finish_inside:
		return PackedVector2Array([start, finish])
	if not start_inside and not finish_inside:
		return PackedVector2Array()
	var denominator := finish_distance - start_distance
	if is_zero_approx(denominator):
		return PackedVector2Array()
	var intersection := start.lerp(finish, -start_distance / denominator)
	return PackedVector2Array([start, intersection]) if start_inside else PackedVector2Array([intersection, finish])

func _surface_clip_distance(local_point: Vector2, visible_below_surface: bool) -> float:
	if not _surface_query.is_valid():
		return 1.0 if visible_below_surface else -1.0
	var support: Dictionary = _surface_query.call(global_position.x + local_point.x, visible_below_surface)
	if not bool(support.get("supported", false)):
		return 1.0
	var surface_y := float(support.get("y", global_position.y))
	var point_y := global_position.y + local_point.y
	return point_y - surface_y if visible_below_surface else surface_y - point_y

## The pixel-art saw (PixelHazardArt) of a pixel-style biome: a square that turns
## with the roll, clipped at the support line like the vector embedded saw.
func _draw_pixel_saw(radius: float) -> void:
	var embedded := Model.is_embedded_variant(event) and not bool(state.get("falling", false))
	var angle := _render_roll_angle if Model.is_embedded_variant(event) else 0.0
	var art_radius := int(round(radius / PixelHazardArt.ART_SCALE))
	var texture := PixelHazardArt.saw_texture(PixelHazardArt.palette(), radius)
	var size := float(PixelHazardArt.saw_side(art_radius)) * PixelHazardArt.ART_SCALE
	var half := size * 0.5
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	if embedded:
		square = _clip_at_surface(square, bool(state.get("ceiling_lane", false)))
		if square.size() < 3:
			return
	var uvs := PackedVector2Array()
	for point in square:
		uvs.append(point.rotated(-angle) / size + Vector2(0.5, 0.5))
	var colors := PackedColorArray()
	colors.resize(square.size())
	colors.fill(Color.WHITE)
	draw_polygon(square, colors, uvs, texture)
