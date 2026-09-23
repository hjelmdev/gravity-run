extends Node2D

signal status_changed(gravity_direction: int, cooldown_left: float)

const PLAYER_X := 180.0
const PLAYER_SIZE := Vector2(34.0, 44.0)
const SPRITE_SURFACE_GAP := 1.0
const PLAYER_SPEED_Y := 680.0
const GRAVITY_ACCELERATION := 1900.0
const COOLDOWN_SECONDS := 0.42

var vertical_speed := 0.0
var gravity_direction := 1
var grounded := true
var cooldown_left := 0.0
var input_enabled := true
@onready var effects: Node = $PlayerEffects
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func reset_to_floor(floor_surface_y: float) -> void:
	position = Vector2(PLAYER_X, floor_surface_y - PLAYER_SIZE.y * 0.5)
	vertical_speed = 0.0
	gravity_direction = 1
	grounded = true
	cooldown_left = 0.0
	input_enabled = true
	_update_sprite_orientation()
	sprite.play("run")
	effects.call("clear_effects")
	status_changed.emit(gravity_direction, cooldown_left)

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

func advance(delta: float, floor_surface_y: float, ceiling_surface_y: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	effects.call("tick", delta)
	vertical_speed += float(gravity_direction) * GRAVITY_ACCELERATION * delta
	position.y += vertical_speed * delta
	var floor_y := floor_surface_y - PLAYER_SIZE.y * 0.5
	var ceiling_y := ceiling_surface_y + PLAYER_SIZE.y * 0.5
	if gravity_direction > 0:
		if grounded:
			position.y = floor_y
			vertical_speed = 0.0
		elif vertical_speed >= 0.0 and position.y >= floor_y:
			position.y = floor_y
			vertical_speed = 0.0
			grounded = true
	else:
		if grounded:
			position.y = ceiling_y
			vertical_speed = 0.0
		elif vertical_speed <= 0.0 and position.y <= ceiling_y:
			position.y = ceiling_y
			vertical_speed = 0.0
			grounded = true
	_update_sprite_orientation()
	status_changed.emit(gravity_direction, cooldown_left)

func _update_sprite_orientation() -> void:
	sprite.flip_v = gravity_direction < 0
	sprite.position.y = -float(gravity_direction) * SPRITE_SURFACE_GAP

func _try_flip(new_direction: int) -> void:
	if not grounded or cooldown_left > 0.0 or new_direction == gravity_direction:
		return
	gravity_direction = new_direction
	_update_sprite_orientation()
	grounded = false
	vertical_speed = float(gravity_direction) * PLAYER_SPEED_Y
	cooldown_left = COOLDOWN_SECONDS
	status_changed.emit(gravity_direction, cooldown_left)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_UP or event.keycode == KEY_W:
		_try_flip(-1)
	elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
		_try_flip(1)

