extends Node2D

const RunnerMotionScript := preload("res://systems/runner_motion.gd")
const SkinPalette := preload("res://player/skin_palette.gd")
const TouchGestureLifecycleScript := preload("res://systems/touch_gesture_lifecycle.gd")

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
var _touch_gesture: RefCounted = TouchGestureLifecycleScript.new()
var _skin_id := -1
var _character_offset_y := 0.0
## Absolute horizontal course coordinate, independent of camera and viewport.
var world_x := PLAYER_X
@onready var effects: Node = $PlayerEffects
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_touch_gesture.diagnostic.connect(_on_touch_gesture_diagnostic)
	set_process(false)

func reset_to_floor(floor_surface_y: float) -> void:
	_touch_gesture.cancel("round_reset")
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
	if input_enabled != enabled:
		_record_input_diagnostic("input_blocked_state", {"blocked": not enabled, "reason": "input_enabled_changed"})
	if not enabled:
		_touch_gesture.cancel("input_disabled")
	input_enabled = enabled
	set_running(enabled)

func set_running(running: bool) -> void:
	if not is_instance_valid(sprite):
		return
	if running:
		sprite.play("run")
	else:
		sprite.stop()

func set_skin_id(skin_id: int) -> void:
	var resolved_skin := posmod(skin_id, SkinPalette.SKIN_COUNT)
	if resolved_skin == _skin_id:
		return
	_skin_id = resolved_skin
	if is_instance_valid(sprite):
		# Hue shift 0 is the authored palette, so skip the shader entirely.
		sprite.material = null if _skin_id == 0 else SkinPalette.make_material(_skin_id)

## Swaps the runner's art. The hitbox (PLAYER_SIZE) is the same for everyone.
func apply_character(definition: Resource) -> void:
	if definition == null or not is_instance_valid(sprite):
		return
	var frames: SpriteFrames = definition.get("sprite_frames")
	if frames == null:
		return
	if sprite.sprite_frames != frames:
		var was_playing := sprite.is_playing()
		sprite.sprite_frames = frames
		if was_playing or input_enabled:
			sprite.play("run")
	var pixel_scale := float(definition.get("pixel_scale"))
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	_character_offset_y = float((definition.get("sprite_offset") as Vector2).y)
	_update_sprite_orientation()

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
	if not is_instance_valid(sprite):
		return
	sprite.flip_v = gravity_direction < 0
	sprite.offset.y = _character_offset_y * float(gravity_direction)
	sprite.position.y = -float(gravity_direction) * SPRITE_SURFACE_GAP

func _is_pause_button_position(point: Vector2) -> bool:
	var viewport_width := get_viewport_rect().size.x
	return Rect2(viewport_width - 88.0, 52.0, 88.0, 88.0).has_point(point)

func _try_flip(new_direction: int, input_source: String = "") -> void:
	if not input_source.is_empty():
		_record_input_diagnostic("flip_queued", {"source": input_source, "direction": new_direction, "cooldown": cooldown_left, "grounded": grounded})
	var motion_state := {
		"gravity_direction": gravity_direction,
		"grounded": grounded,
		"vertical_speed": vertical_speed,
		"cooldown": cooldown_left,
	}
	if not RunnerMotionScript.try_flip(motion_state, new_direction, _flip_cooldown_multiplier):
		if not input_source.is_empty():
			_record_input_diagnostic("flip_rejected", {"source": input_source, "reason": "cooldown" if cooldown_left > 0.0 else "airborne_or_same_direction", "cooldown": cooldown_left, "grounded": grounded})
		return
	gravity_direction = int(motion_state.gravity_direction)
	grounded = bool(motion_state.grounded)
	vertical_speed = float(motion_state.vertical_speed)
	cooldown_left = float(motion_state.cooldown)
	gravity_flipped.emit()
	if not input_source.is_empty():
		_record_input_diagnostic("flip_accepted", {"source": input_source, "direction": gravity_direction})
	_update_sprite_orientation()
	status_changed.emit(gravity_direction, cooldown_left)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.canceled:
		_touch_gesture.call("cancel_finger", event.index, "platform_cancel")
		return
	if event is InputEventScreenTouch and not event.pressed:
		var token := int(_touch_gesture.call("observe_release", event.index, event.position))
		if token >= 0:
			call_deferred("_cancel_unhandled_touch_release", token)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		_touch_gesture.cancel("input_disabled")
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			_touch_gesture.call("cancel_finger", event.index, "platform_cancel")
			return
		if PlayerProfile.flip_control not in ["swipe", "tap"]:
			_touch_gesture.cancel("touch_control_mode_changed")
			return
		if event.pressed:
			if _is_pause_button_position(event.position):
				_record_input_diagnostic("gesture_rejected", {"reason": "pause_control", "finger": event.index})
			elif PlayerProfile.flip_control == "tap":
				if not _touch_gesture.is_active():
					_try_flip(-gravity_direction, "tap")
			else:
				_touch_gesture.call("begin", event.index, event.position, Time.get_ticks_usec())
				set_process(true)
		else:
			var completion: Dictionary = _touch_gesture.call("consume_release", event.index)
			if completion.is_empty():
				return
			var swipe_delta: Vector2 = completion.get("delta", Vector2.ZERO)
			if absf(swipe_delta.y) >= SWIPE_DISTANCE_MIN and absf(swipe_delta.y) > absf(swipe_delta.x) * 1.2:
				_try_flip(-1 if swipe_delta.y < 0.0 else 1, "swipe")
			else:
				_record_input_diagnostic("gesture_rejected", {"reason": "below_swipe_threshold", "dx": swipe_delta.x, "dy": swipe_delta.y})
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if PlayerProfile.flip_control == "mouse":
			_try_flip(-gravity_direction, "mouse")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if PlayerProfile.flip_control != "keyboard":
			return
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			_try_flip(-1, "keyboard")
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_try_flip(1, "keyboard")

func _cancel_unhandled_touch_release(token: int) -> void:
	_touch_gesture.call("cancel_if_release_pending", token, "gui_consumed_release")

func _process(_delta: float) -> void:
	_touch_gesture.call("expire", Time.get_ticks_usec())
	if not _touch_gesture.is_active():
		set_process(false)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_PAUSED]:
		_touch_gesture.cancel("focus_or_tree_pause")

func _on_touch_gesture_diagnostic(event_name: String, details: Dictionary) -> void:
	_record_input_diagnostic("gesture_%s" % event_name, details)

func _record_input_diagnostic(event_name: String, details: Dictionary) -> void:
	var service := get_node_or_null("/root/MultiplayerV2Service")
	if service == null:
		return
	var diagnostics: Variant = service.get("diagnostics")
	if diagnostics != null and diagnostics.has_method("record_event"):
		diagnostics.call("record_event", event_name, details)
