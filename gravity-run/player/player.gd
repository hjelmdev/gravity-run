extends Node2D

signal status_changed(gravity_direction: int, cooldown_left: float)
signal gravity_flipped

const PLAYER_X := 180.0
const PLAYER_SIZE := Vector2(34.0, 44.0)
const SPRITE_SURFACE_GAP := 1.0
const PLAYER_SPEED_Y := 680.0
const GRAVITY_ACCELERATION := 1900.0
const COOLDOWN_SECONDS := 0.42
const SWIPE_DISTANCE_MIN := 48.0

var vertical_speed := 0.0
var gravity_direction := 1
var grounded := true
var cooldown_left := 0.0
var input_enabled := true
var _flip_cooldown_multiplier := 1.0
var active_touch_index := -1
var touch_start_position := Vector2.ZERO
## Absolute horizontal course coordinate, independent of camera and viewport.
var world_x := PLAYER_X
@onready var effects: Node = $PlayerEffects
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func reset_to_floor(floor_surface_y: float) -> void:
	world_x = PLAYER_X
	position = Vector2(world_x, floor_surface_y - PLAYER_SIZE.y * 0.5)
	vertical_speed = 0.0
	gravity_direction = 1
	grounded = true
	cooldown_left = 0.0
	input_enabled = true
	_flip_cooldown_multiplier = 1.0
	_update_sprite_orientation()
	sprite.play("run")
	effects.call("clear_effects")
	status_changed.emit(gravity_direction, cooldown_left)

func advance_world_x(distance: float) -> void:
	world_x += maxf(distance, 0.0)
	position.x = world_x

func set_loadout_snapshot(snapshot: Resource) -> void:
	_flip_cooldown_multiplier = 1.0
	if snapshot == null or not snapshot.has_method("is_valid") or not bool(snapshot.call("is_valid")):
		return
	var stats: Variant = snapshot.call("get_resolved_stats")
	if stats is Dictionary:
		_flip_cooldown_multiplier = clampf(float(stats.get("flip_cooldown_percent", 10000)) / 10000.0, 0.5, 2.0)

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	set_running(enabled)

func set_running(running: bool) -> void:
	if running:
		sprite.play("run")
	else:
		sprite.stop()

func get_player_rect() -> Rect2:
	return Rect2(global_position - PLAYER_SIZE * 0.5, PLAYER_SIZE)

func get_gravity_direction() -> int:
	return gravity_direction

func get_cooldown_left() -> float:
	return cooldown_left

func get_speed_multiplier() -> float:
	return float(effects.call("get_speed_multiplier"))

func is_spike_immune() -> bool:
	return bool(effects.call("is_spike_immune"))

func advance(delta: float, floor_surface_y: float, ceiling_surface_y: float, floor_supported: bool = true, ceiling_supported: bool = true) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	effects.call("tick", delta)
	var floor_contact_y := floor_surface_y - PLAYER_SIZE.y * 0.5
	var ceiling_contact_y := ceiling_surface_y + PLAYER_SIZE.y * 0.5
	var contact_y := floor_contact_y if gravity_direction > 0 else ceiling_contact_y
	# A step can move the supporting surface away in the direction of gravity.
	# Detach before integration so the character falls across the gap instead of
	# being snapped instantly to the new surface height.
	if grounded and float(gravity_direction) * (contact_y - position.y) > 12.0:
		grounded = false
		vertical_speed = 0.0
	vertical_speed += float(gravity_direction) * GRAVITY_ACCELERATION * delta
	position.y += vertical_speed * delta
	var floor_y := floor_contact_y
	var ceiling_y := ceiling_contact_y
	if gravity_direction > 0:
		if not floor_supported:
			grounded = false
		elif grounded:
			position.y = floor_y
			vertical_speed = 0.0
		elif vertical_speed >= 0.0 and position.y >= floor_y and position.y - floor_y <= 38.0:
			position.y = floor_y
			vertical_speed = 0.0
			grounded = true
	else:
		if not ceiling_supported:
			grounded = false
		elif grounded:
			position.y = ceiling_y
			vertical_speed = 0.0
		elif vertical_speed <= 0.0 and position.y <= ceiling_y and ceiling_y - position.y <= 38.0:
			position.y = ceiling_y
			vertical_speed = 0.0
			grounded = true
	_update_sprite_orientation()
	status_changed.emit(gravity_direction, cooldown_left)

func _update_sprite_orientation() -> void:
	sprite.flip_v = gravity_direction < 0
	sprite.position.y = -float(gravity_direction) * SPRITE_SURFACE_GAP

func _is_pause_button_position(point: Vector2) -> bool:
	var viewport_width := get_viewport_rect().size.x
	return Rect2(viewport_width - 88.0, 52.0, 88.0, 88.0).has_point(point)

func _try_flip(new_direction: int) -> void:
	if not grounded or cooldown_left > 0.0 or new_direction == gravity_direction:
		return
	gravity_direction = new_direction
	gravity_flipped.emit()
	_update_sprite_orientation()
	grounded = false
	vertical_speed = float(gravity_direction) * PLAYER_SPEED_Y
	cooldown_left = COOLDOWN_SECONDS * _flip_cooldown_multiplier
	status_changed.emit(gravity_direction, cooldown_left)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventScreenTouch:
		if PlayerProfile.flip_control not in ["swipe", "tap"]:
			return
		if event.pressed:
			if active_touch_index == -1 and not _is_pause_button_position(event.position):
				if PlayerProfile.flip_control == "tap":
					_try_flip(-gravity_direction)
				else:
					active_touch_index = event.index
					touch_start_position = event.position
		elif event.index == active_touch_index:
			var swipe_delta: Vector2 = event.position - touch_start_position
			active_touch_index = -1
			if absf(swipe_delta.y) >= SWIPE_DISTANCE_MIN and absf(swipe_delta.y) > absf(swipe_delta.x) * 1.2:
				_try_flip(-1 if swipe_delta.y < 0.0 else 1)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if PlayerProfile.flip_control == "mouse":
			_try_flip(-gravity_direction)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if PlayerProfile.flip_control != "keyboard":
			return
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			_try_flip(-1)
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_try_flip(1)

