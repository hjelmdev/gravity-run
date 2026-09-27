extends Node2D

const RunnerMotionScript := preload("res://systems/runner_motion.gd")

signal status_changed(gravity_direction: int, cooldown_left: float)
signal gravity_flipped

const PLAYER_X := 180.0
const PLAYER_SIZE := RunnerMotionScript.SIZE
const SPRITE_SURFACE_GAP := 1.0
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
	effects.call("tick", delta)
	var motion_state := {
		"y": position.y,
		"vertical_speed": vertical_speed,
		"gravity_direction": gravity_direction,
		"grounded": grounded,
		"cooldown": cooldown_left,
	}
	RunnerMotionScript.advance_vertical(motion_state, delta, floor_surface_y, ceiling_surface_y, floor_supported, ceiling_supported)
	position.y = float(motion_state.y)
	vertical_speed = float(motion_state.vertical_speed)
	gravity_direction = int(motion_state.gravity_direction)
	grounded = bool(motion_state.grounded)
	cooldown_left = float(motion_state.cooldown)
	_update_sprite_orientation()
	status_changed.emit(gravity_direction, cooldown_left)

func _update_sprite_orientation() -> void:
	sprite.flip_v = gravity_direction < 0
	sprite.position.y = -float(gravity_direction) * SPRITE_SURFACE_GAP

func _is_pause_button_position(point: Vector2) -> bool:
	var viewport_width := get_viewport_rect().size.x
	return Rect2(viewport_width - 88.0, 52.0, 88.0, 88.0).has_point(point)

func _try_flip(new_direction: int) -> void:
	var motion_state := {
		"gravity_direction": gravity_direction,
		"grounded": grounded,
		"vertical_speed": vertical_speed,
		"cooldown": cooldown_left,
	}
	if not RunnerMotionScript.try_flip(motion_state, new_direction, _flip_cooldown_multiplier):
		return
	gravity_direction = int(motion_state.gravity_direction)
	grounded = bool(motion_state.grounded)
	vertical_speed = float(motion_state.vertical_speed)
	cooldown_left = float(motion_state.cooldown)
	gravity_flipped.emit()
	_update_sprite_orientation()
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

