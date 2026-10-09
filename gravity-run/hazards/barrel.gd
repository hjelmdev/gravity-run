extends "res://hazards/hazard.gd"

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")

var roll_angle := 0.0
var fall_velocity := 0.0
var is_falling := false
var is_spiked := false
var is_rubber := false
var rubber_target_x := -1.0
var travel_direction := 1
var bounce_count := 0
var bounce_ticks := 0
var retired := false
var motion_speed_multiplier := 1.0
## Presentation only. "mine_cart" draws the barrel as a mine cart (campaign cave
## stages); the collision circle and motion are unchanged.
var skin := ""
var _local_render_motion := false
var _previous_position := Vector2.ZERO
var _previous_rotation := 0.0
var _previous_roll := 0.0

func _process(delta: float) -> void:
	if is_destroying:
		super._process(delta)
	elif _local_render_motion:
		queue_redraw()

func freeze_render_motion() -> void:
	_local_render_motion = false
	queue_redraw()

func configure(new_size: Vector2, attach_to_ceiling: bool) -> void:
	super.configure(new_size, attach_to_ceiling)
	fall_velocity = 0.0
	is_falling = false

func scale_track_height(scale: float) -> void:
	fall_velocity *= scale

func set_motion_speed_multiplier(multiplier: float) -> void:
	motion_speed_multiplier = maxf(multiplier, 1.0)

func set_spiked(value: bool) -> void:
	is_spiked = value
	queue_redraw()

func set_rubber_variant(value: bool, target_x: float = -1.0) -> void:
	is_rubber = value
	rubber_target_x = target_x if value else -1.0
	travel_direction = 1
	bounce_count = 0
	bounce_ticks = 0
	retired = false
	queue_redraw()

func bounce_from_rect(obstacle_rect: Rect2) -> bool:
	if not is_rubber or retired:
		return false
	var state := {"x": position.x, "width": size.x, "height": size.y, "travel_direction": travel_direction, "bounce_count": bounce_count}
	var bounced := HazardRules.bounce_rubber_barrel(state, obstacle_rect)
	position.x = float(state.x)
	travel_direction = int(state.get("travel_direction", travel_direction))
	bounce_count = int(state.get("bounce_count", bounce_count))
	bounce_ticks = int(state.get("bounce_ticks", 0))
	retired = bool(state.get("retired", false))
	queue_redraw()
	return bounced

func apply_replicated_motion(new_position: Vector2, new_roll_angle: float, new_rotation: float, should_be_visible: bool) -> void:
	position = new_position
	roll_angle = new_roll_angle
	rotation = new_rotation
	visible = should_be_visible
	queue_redraw()

func apply_shared_barrel_state(state: Dictionary) -> void:
	position = Vector2(float(state.get("x", position.x)), float(state.get("y", position.y)))
	roll_angle = float(state.get("roll_angle", roll_angle))
	rotation = float(state.get("rotation", rotation))
	is_spiked = bool(state.get("spiked", is_spiked))
	is_rubber = int(state.get("barrel_variant", 0)) == 1
	rubber_target_x = float(state.get("rubber_target_x", rubber_target_x))
	travel_direction = int(state.get("travel_direction", 1))
	bounce_count = int(state.get("bounce_count", 0))
	bounce_ticks = int(state.get("bounce_ticks", 0))
	retired = bool(state.get("retired", false))
	visible = bool(state.get("spawned", false)) and not bool(state.get("destroyed", false))
	queue_redraw()

func advance_motion(delta: float, movement: float, _player_position: Vector2, floor_y_at: Callable, surface_angle_at: Callable, surface_supported_at: Callable = Callable()) -> void:
	if is_destroying:
		return
	if retired:
		return
	_local_render_motion = true
	set_process(true)
	_previous_position = position
	_previous_rotation = rotation
	_previous_roll = roll_angle
	var state := {
		"x": position.x,
		"y": position.y,
		"width": size.x,
		"height": size.y,
		"motion_speed_multiplier": motion_speed_multiplier,
		"travel_direction": travel_direction,
		"bounce_ticks": bounce_ticks,
		"fall_velocity": fall_velocity,
		"is_falling": is_falling,
		"roll_angle": roll_angle,
		"rotation": rotation,
	}
	var reference_movement := movement if movement > 0.0 else RunnerMotion.BASE_RUN_SPEED * maxf(delta, 0.0)
	var projected_x := position.x - reference_movement * (motion_speed_multiplier - 1.0) * float(travel_direction)
	var floor_y := float(floor_y_at.call(projected_x))
	var floor_supported := not surface_supported_at.is_valid() or bool(surface_supported_at.call(projected_x, false))
	HazardRules.advance_barrel(state, delta, movement, floor_y, float(surface_angle_at.call(projected_x, false)), floor_supported)
	position.x = float(state.x)
	position.y = float(state.y)
	fall_velocity = float(state.fall_velocity)
	is_falling = bool(state.is_falling)
	roll_angle = float(state.roll_angle)
	rotation = float(state.rotation)
	travel_direction = int(state.get("travel_direction", travel_direction))
	bounce_ticks = int(state.get("bounce_ticks", bounce_ticks))
	retired = bool(state.get("retired", retired))
	queue_redraw()

func _begin_destruction() -> void:
	var radius := HazardRules.barrel_radius(size.x, size.y)
	var center_y := radius if from_ceiling else -radius
	_spawn_destruction_fragments(Vector2(0.0, center_y), [Color("d98245"), Color("743e35"), Color("f0a45d")], 9, Vector2(radius * 1.5, radius * 1.5))

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var rendered_roll := roll_angle
	var base := Transform2D.IDENTITY
	if _local_render_motion:
		var fraction := Engine.get_physics_interpolation_fraction()
		var rendered_position := _previous_position.lerp(position, fraction)
		base = Transform2D(lerp_angle(_previous_rotation, rotation, fraction) - rotation, (rendered_position - position).rotated(-rotation))
		draw_set_transform_matrix(base)
		rendered_roll = lerpf(_previous_roll, roll_angle, fraction)
	var radius := HazardRules.barrel_radius(size.x, size.y)
	var center_y := radius if from_ceiling else -radius
	var body_color := Color("40b7ae") if is_rubber else Color("d98245")
	var detail_color := Color("143f57") if is_rubber else Color("743e35")
	if retired:
		# A spent rubber barrel is parked, not destroyed or hidden. Muted color and
		# a double band distinguish its stationary state while it remains lethal.
		body_color = Color("397c78")
		detail_color = Color("143f57")
	if is_rubber and bounce_ticks > 0:
		body_color = Color("77e2d3")
	if skin == "meadow":
		# A pixel-art barrel seen end-on, turning with the roll.
		var kind := ("retired" if retired else "rubber") if is_rubber else ("spiked" if is_spiked else "wood")
		var art := MeadowPixelArt.barrel_texture(radius, kind)
		var side := Vector2(art.get_size()) * MeadowPixelArt.ART_SCALE
		draw_set_transform_matrix(base * Transform2D(rendered_roll, Vector2(0.0, center_y)))
		draw_texture_rect(art, Rect2(-side * 0.5, side), false, Color(1.35, 1.35, 1.35) if is_rubber and bounce_ticks > 0 else Color.WHITE)
		draw_set_transform(Vector2.ZERO)
		return
	if skin == "mine_cart":
		_draw_mine_cart(radius, center_y, rendered_roll, is_rubber)
	else:
		draw_circle(Vector2(0.0, center_y), radius, body_color)
		draw_arc(Vector2(0.0, center_y), radius - 8.0, 0.0, TAU, 24, detail_color, 4.0)
		if is_rubber:
			for stripe in range(3):
				var stripe_x := float(stripe - 1) * radius * 0.52
				draw_line(Vector2(stripe_x, center_y - radius * 0.54), Vector2(stripe_x, center_y + radius * 0.54), detail_color, 5.0)
			if retired:
				draw_line(Vector2(-radius * 0.44, center_y - 3.0), Vector2(radius * 0.44, center_y - 3.0), Color("b6e6dc"), 3.0)
				draw_line(Vector2(-radius * 0.44, center_y + 3.0), Vector2(radius * 0.44, center_y + 3.0), Color("b6e6dc"), 3.0)
		var first_start := Vector2(-radius * 0.55, -radius * 0.45).rotated(rendered_roll) + Vector2(0.0, center_y)
		var first_end := Vector2(radius * 0.55, radius * 0.45).rotated(rendered_roll) + Vector2(0.0, center_y)
		var second_start := Vector2(radius * 0.55, -radius * 0.45).rotated(rendered_roll) + Vector2(0.0, center_y)
		var second_end := Vector2(-radius * 0.55, radius * 0.45).rotated(rendered_roll) + Vector2(0.0, center_y)
		if not is_rubber:
			draw_line(first_start, first_end, detail_color, 4.0)
			draw_line(second_start, second_end, detail_color, 4.0)
	if is_spiked:
		for index in range(8):
			var angle := TAU * float(index) / 8.0 + rendered_roll
			var outward := Vector2.RIGHT.rotated(angle)
			draw_colored_polygon(PackedVector2Array([outward * (radius - 2.0) + Vector2(0.0, center_y), outward * (radius + 9.0) + Vector2(0.0, center_y) + outward.rotated(PI * 0.5) * 4.0, outward * (radius + 9.0) + Vector2(0.0, center_y) - outward.rotated(PI * 0.5) * 4.0]), Color("d8c6a2"))
	draw_set_transform(Vector2.ZERO)

func intersects_rect(rect: Rect2) -> bool:
	var radius := HazardRules.barrel_radius(size.x, size.y)
	var center := HazardRules.barrel_center(global_position, size.x, size.y, from_ceiling)
	return HazardRules.circle_intersects_rect(center, radius, rect)

## A mine cart that fits inside the barrel's collision circle: a tapered iron
## body with a rim band and an ore pile, two spinning wheels under it.
func _draw_mine_cart(radius: float, center_y: float, wheel_angle: float, teal: bool) -> void:
	var ground := center_y + radius
	var body_color := Color("3f8f8a") if teal else Color("9b5a3a")
	var rim_color := Color("1c3f4a") if teal else Color("3b2a24")
	var plank_color := body_color.darkened(0.25)
	var top := center_y - radius * 0.38
	var bottom := ground - radius * 0.42
	var body := PackedVector2Array([
		Vector2(-radius * 0.92, top), Vector2(radius * 0.92, top),
		Vector2(radius * 0.68, bottom), Vector2(-radius * 0.68, bottom),
	])
	# Ore pile heaped above the rim.
	var ore := Color("5b6670") if teal else Color("d1a94c")
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius * 0.80, top), Vector2(-radius * 0.5, top - radius * 0.34), Vector2(-radius * 0.15, top - radius * 0.2),
		Vector2(radius * 0.2, top - radius * 0.42), Vector2(radius * 0.58, top - radius * 0.22), Vector2(radius * 0.80, top),
	]), ore)
	draw_colored_polygon(body, body_color)
	draw_line(Vector2(-radius * 0.80, top + (bottom - top) * 0.5), Vector2(radius * 0.80, top + (bottom - top) * 0.5), plank_color, 2.0)
	draw_line(Vector2(-radius * 0.2, top), Vector2(-radius * 0.14, bottom), plank_color, 2.0)
	draw_line(Vector2(radius * 0.3, top), Vector2(radius * 0.25, bottom), plank_color, 2.0)
	draw_rect(Rect2(Vector2(-radius * 0.98, top - 3.0), Vector2(radius * 1.96, 7.0)), rim_color)
	var wheel_radius := radius * 0.24
	for wheel_x in [-radius * 0.46, radius * 0.46]:
		var wheel_center := Vector2(wheel_x, ground - wheel_radius)
		draw_circle(wheel_center, wheel_radius, rim_color)
		draw_circle(wheel_center, wheel_radius * 0.45, Color("b8b2a6"))
		var spoke := Vector2.RIGHT.rotated(wheel_angle) * wheel_radius * 0.9
		draw_line(wheel_center - spoke, wheel_center + spoke, Color("b8b2a6"), 2.0)
