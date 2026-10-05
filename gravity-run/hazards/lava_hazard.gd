extends Node2D
class_name LavaHazard

const Model := preload("res://systems/lava_hazard_model.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var event: Dictionary = {}
var simulation_tick := 0.0
var course_start_x := 0.0

func _enter_tree() -> void:
	add_to_group("lava_hazards")

func configure(event_data: Dictionary, start_x := 180.0) -> void:
	event = event_data.duplicate(true)
	course_start_x = start_x
	position = Vector2(float(event.get("x", 0.0)), 0.0)
	set_meta("event_id", str(event.get("event_id", "")))
	queue_redraw()

func apply_simulation_tick(tick: float, start_x := -1.0) -> void:
	simulation_tick = maxf(tick, 0.0)
	if start_x >= 0.0:
		course_start_x = start_x
	queue_redraw()

func apply_world_state(state: Dictionary) -> void:
	apply_simulation_tick(float(state.get("tick", simulation_tick)), float(state.get("course_start_x", course_start_x)))

func is_destroying_now() -> bool:
	return false

func get_hitbox_rect() -> Rect2:
	return Model.crack_rect(event) if str(event.get("kind", "")) == "lava_crack" else Rect2()

func is_lethal_at(player_rect: Rect2, tick: int, start_x := -1.0) -> bool:
	if str(event.get("kind", "")) == "lava_crack":
		return player_rect.intersects(Model.crack_rect(event))
	var origin := course_start_x if start_x < 0.0 else start_x
	var center := player_rect.get_center()
	return Model.swept_contact_fraction(event, origin, tick, tick, center, center, player_rect.size) >= 0.0

func swept_contact_fraction(start_rect: Rect2, finish_rect: Rect2, start_tick: int, end_tick: int, player_size: Vector2 = Vector2.ZERO) -> float:
	if str(event.get("kind", "")) == "lava_crack":
		var bounds: Rect2 = Model.crack_rect(event)
		var polygon := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		return HazardRules.swept_rect_polygon_fraction(start_rect, finish_rect.position - start_rect.position, polygon)
	var size := player_size if player_size != Vector2.ZERO else start_rect.size
	return Model.swept_contact_fraction(event, course_start_x, start_tick, end_tick, start_rect.get_center(), finish_rect.get_center(), size)

func freeze_render_motion() -> void:
	pass

func _draw() -> void:
	if event.is_empty():
		return
	if str(event.get("kind", "")) == "lava_crack":
		_draw_crack()
	elif str(event.get("kind", "")) == "volcano":
		_draw_volcano()

func _draw_crack() -> void:
	var rect: Rect2 = Model.crack_rect(event)
	var local_x := rect.position.x - position.x
	var top := rect.position.y
	var height := rect.size.y
	var width := rect.size.x
	var glow := Color("ff380d")
	glow.a = 0.30
	draw_rect(Rect2(local_x, top - 2.0, width, height + 4.0), glow)
	var points := PackedVector2Array()
	var segments := 8
	for index in range(segments + 1):
		var x := local_x + width * float(index) / float(segments)
		var y := top + height * (0.25 if index % 2 == 0 else 0.78)
		points.append(Vector2(x, y))
	draw_polyline(points, Color("ff4a17"), 5.0, true)
	draw_polyline(points, Color("ffc35b"), 1.5, true)

func _draw_volcano() -> void:
	var floor_y := float(event.get("floor_y", 460.0))
	var width := float(event.get("width", 120.0))
	var height := float(event.get("height", 76.0))
	var body := Model.volcano_body_polygon_local(event)
	draw_colored_polygon(body, Color("211719"))
	draw_polyline(body, Color("5a3430"), 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-width * 0.14, floor_y - height * 0.78), Vector2(width * 0.14, floor_y - height * 0.78), Vector2(width * 0.22, floor_y - height * 0.57), Vector2(-width * 0.20, floor_y - height * 0.57)]), Color("ff4b13"))
	draw_line(Vector2(-width * 0.13, floor_y - height * 0.70), Vector2(width * 0.13, floor_y - height * 0.70), Color("ffd068"), 3.0, true)
	for projectile in Model.projectiles_at(event, course_start_x, simulation_tick):
		var center := Vector2(float(projectile.get("x", 0.0)) - position.x, float(projectile.get("y", 0.0)))
		var radius := float(projectile.get("radius", 14.0))
		draw_circle(center, radius * 1.35, Color(1.0, 0.20, 0.04, 0.26))
		draw_circle(center, radius, Color("ff5a18"))
		draw_circle(center + Vector2(-radius * 0.18, -radius * 0.20), radius * 0.48, Color("ffd05a"))
