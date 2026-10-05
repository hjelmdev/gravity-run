extends Node

const Gesture := preload("res://systems/touch_gesture_lifecycle.gd")
const PlayerScene := preload("res://player/player.tscn")
const LocalRunner := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_lifecycle_contract()
	await _test_player_input_integration()
	await _test_match_input_integration()
	await _test_viewport_gui_dispatch()
	print("TOUCH_GESTURE_LIFECYCLE_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _test_lifecycle_contract() -> void:
	var gesture = Gesture.new()
	var events: Array[String] = []
	gesture.diagnostic.connect(func(event_name: String, _details: Dictionary) -> void: events.append(event_name))
	_check(gesture.begin(4, Vector2(100, 100), 1000), "first finger begins gesture")
	var release_token := int(gesture.observe_release(4, Vector2(100, 170)))
	_check(release_token > 0 and gesture.is_active(), "pre-GUI release is retained for normal unhandled evaluation")
	var completed: Dictionary = gesture.consume_release(4)
	_check(not completed.is_empty() and Vector2(completed.get("delta", Vector2.ZERO)) == Vector2(0, 70), "normal unhandled callback consumes matching release")
	_check(not gesture.cancel_if_release_pending(release_token), "late deferred fallback cannot cancel a completed new gesture")
	_check(gesture.begin(7, Vector2(10, 10), 2000), "next swipe begins immediately after completion")
	var gui_release := int(gesture.observe_release(7, Vector2(15, 90)))
	_check(gesture.cancel_if_release_pending(gui_release), "GUI-consumed release fallback cancels stale finger")
	_check(not gesture.is_active() and gesture.begin(8, Vector2(0, 0), 3000), "new gesture works immediately after consumed release")
	_check(not gesture.begin(9, Vector2(5, 5), 3100) and gesture.active_index == 8, "second finger is ignored without breaking the active finger")
	_check(int(gesture.observe_release(9, Vector2(5, 100))) == -1 and gesture.is_active(), "other finger release cannot end legitimate active gesture")
	gesture.cancel("menu_open")
	_check(not gesture.is_active(), "menu transition cancels an in-progress gesture")
	_check(gesture.begin(2, Vector2.ZERO, 4000), "gesture begins after menu cancellation")
	gesture.cancel("focus_lost")
	_check(not gesture.is_active(), "focus loss cancels an in-progress gesture")
	_check(gesture.begin(3, Vector2.ZERO, 5000), "gesture begins after focus recovery")
	_check(gesture.expire(5_005_001) and not gesture.is_active(), "missing lift expires conservatively and cannot strand the next swipe")
	_check(events.has("begin") and events.has("end") and events.has("cancel") and events.has("rejected"), "bounded lifecycle diagnostics cover begin, end, cancel, and rejection")

func _test_player_input_integration() -> void:
	PlayerProfile.flip_control = "swipe"
	var player = PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	player.call("_unhandled_input", _touch(3, true, Vector2(220, 180)))
	var normal_release := _touch(3, false, Vector2(220, 100))
	player.call("_input", normal_release)
	player.call("_unhandled_input", normal_release)
	_check(int(player.gravity_direction) == -1, "real SP Player accepts a normal upward swipe")
	var recorded_names: Array[String] = []
	for event in MultiplayerV2Service.diagnostics.events:
		recorded_names.append(str(event.get("name", "")))
	_check(recorded_names.has("gesture_begin") and recorded_names.has("gesture_end") and recorded_names.has("flip_queued") and recorded_names.has("flip_accepted"), "SP diagnostics record bounded gesture lifecycle and flip outcome events")
	await get_tree().process_frame
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	player.call("_unhandled_input", _touch(4, true, Vector2(100, 100)))
	var gui_release := _touch(4, false, Vector2(get_viewport().get_visible_rect().size.x - 20, 60))
	player.call("_input", gui_release)
	await get_tree().process_frame
	_check(not bool(player._touch_gesture.call("is_active")), "SP release consumed over pause UI clears gesture without needing unhandled release")
	_check(int(player.gravity_direction) == 1, "pause UI touch does not flip gravity")
	player.cooldown_left = 0.2
	player.call("_unhandled_input", _touch(5, true, Vector2(200, 150)))
	var next_release := _touch(5, false, Vector2(200, 100))
	player.call("_input", next_release)
	player.call("_unhandled_input", next_release)
	_check(int(player.gravity_direction) == 1, "cooldown rejection preserves motion rules")
	player.cooldown_left = 0.0
	player.grounded = true
	player.call("_unhandled_input", _touch(6, true, Vector2(300, 200)))
	player.call("_notification", Node.NOTIFICATION_PAUSED)
	_check(not bool(player._touch_gesture.call("is_active")), "SP pause notification resets gesture")
	player.call("_unhandled_input", _touch(7, true, Vector2(300, 200)))
	var post_pause_release := _touch(7, false, Vector2(300, 110))
	player.call("_input", post_pause_release)
	player.call("_unhandled_input", post_pause_release)
	_check(int(player.gravity_direction) == -1 and not bool(player._touch_gesture.call("is_active")), "second SP swipe after pause works without inheriting stale state")
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	player.call("_unhandled_input", _touch(17, true, Vector2(300, 200)))
	var canceled_sp := _touch(17, false, Vector2(300, 20), true)
	player.call("_input", canceled_sp)
	player.call("_unhandled_input", canceled_sp)
	_check(int(player.gravity_direction) == 1 and not bool(player._touch_gesture.call("is_active")), "platform-canceled SP touch resets without evaluating its large swipe delta")
	player.call("_unhandled_input", _touch(18, true, Vector2(300, 200)))
	var after_cancel_sp := _touch(18, false, Vector2(300, 110))
	player.call("_input", after_cancel_sp)
	player.call("_unhandled_input", after_cancel_sp)
	_check(int(player.gravity_direction) == -1, "next real SP swipe works after platform cancellation")
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	PlayerProfile.flip_control = "tap"
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	player.call("_unhandled_input", _touch(8, true, Vector2(get_viewport().get_visible_rect().size.x - 20, 60)))
	_check(int(player.gravity_direction) == 1, "tap on pause/menu control does not flip")
	player.call("_unhandled_input", _touch(8, true, Vector2(300, 200)))
	_check(int(player.gravity_direction) == -1, "tap control still flips on touch-down")
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	PlayerProfile.flip_control = "keyboard"
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_W
	player.call("_unhandled_input", key)
	_check(int(player.gravity_direction) == -1, "keyboard control still flips")
	PlayerProfile.flip_control = "swipe"
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	player.call("set_input_enabled", false)
	player.call("_unhandled_input", _touch(9, true, Vector2(300, 200)))
	var disabled_release := _touch(9, false, Vector2(300, 100))
	player.call("_input", disabled_release)
	player.call("_unhandled_input", disabled_release)
	_check(int(player.gravity_direction) == 1 and not bool(player._touch_gesture.call("is_active")), "blocked SP runner ignores touch and clears any gesture")
	player.queue_free()
	await get_tree().process_frame

func _test_match_input_integration() -> void:
	PlayerProfile.flip_control = "swipe"
	var match_view = MatchScene.instantiate()
	add_child(match_view)
	await get_tree().process_frame
	match_view.set("_runner", LocalRunner.new())
	match_view.get("_runner").configure("touch-test", 1, 250.0, 460.0)
	match_view.set("_round_started", true)
	match_view.set("_debug_open", false)
	match_view.call("_unhandled_input", _touch(11, true, Vector2(200, 180)))
	var release := _touch(11, false, Vector2(200, 100))
	match_view.call("_input", release)
	match_view.call("_unhandled_input", release)
	_check(int(match_view.get("_pending_flip_direction")) == -1 and str(match_view.get("_pending_flip_source")) == "swipe", "actual MP match queues the same upward swipe")
	match_view.set("_debug_panel", PanelContainer.new())
	match_view.set("_debug_toggle", Button.new())
	match_view.call("_unhandled_input", _touch(12, true, Vector2(200, 180)))
	match_view.call("_toggle_debug_panel")
	_check(not bool(match_view._touch_gesture.call("is_active")) and int(match_view.get("_pending_flip_direction")) == 0, "opening MP menu cancels gesture and queued flip")
	match_view.set("_debug_open", false)
	match_view.call("_unhandled_input", _touch(13, true, Vector2(200, 180)))
	var consumed_release := _touch(13, false, Vector2(200, 100))
	match_view.call("_input", consumed_release)
	await get_tree().process_frame
	_check(not bool(match_view._touch_gesture.call("is_active")), "MP release consumed by GUI fallback clears the active finger")
	match_view.call("_unhandled_input", _touch(14, true, Vector2(210, 180)))
	var next_release := _touch(14, false, Vector2(210, 100))
	match_view.call("_input", next_release)
	match_view.call("_unhandled_input", next_release)
	_check(int(match_view.get("_pending_flip_direction")) == -1, "next MP swipe is accepted immediately after GUI-consumed release")
	match_view.set("_pending_flip_direction", 0)
	match_view.call("_unhandled_input", _touch(19, true, Vector2(210, 180)))
	var canceled_mp := _touch(19, false, Vector2(210, 20), true)
	match_view.call("_input", canceled_mp)
	match_view.call("_unhandled_input", canceled_mp)
	_check(int(match_view.get("_pending_flip_direction")) == 0 and not bool(match_view._touch_gesture.call("is_active")), "platform-canceled MP touch resets without queuing a flip")
	match_view.call("_unhandled_input", _touch(20, true, Vector2(210, 180)))
	var after_cancel_mp := _touch(20, false, Vector2(210, 100))
	match_view.call("_input", after_cancel_mp)
	match_view.call("_unhandled_input", after_cancel_mp)
	_check(int(match_view.get("_pending_flip_direction")) == -1, "next real MP swipe works after platform cancellation")
	match_view.set("_pending_flip_direction", 0)
	var mp_runner = match_view.get("_runner")
	mp_runner.player_state.gravity_direction = 1
	mp_runner.player_state.grounded = true
	mp_runner.player_state.cooldown = 0.0
	mp_runner.set_blocked(true)
	match_view.call("_unhandled_input", _touch(16, true, Vector2(210, 180)))
	var blocked_release := _touch(16, false, Vector2(210, 100))
	match_view.call("_input", blocked_release)
	match_view.call("_unhandled_input", blocked_release)
	_check(int(match_view.get("_pending_flip_direction")) == -1, "MP blocked runner can queue gravity escape")
	mp_runner.step(int(match_view.get("_pending_flip_direction")), 460.0, 80.0, true, true, false, 250.0)
	_check(int(mp_runner.player_state.gravity_direction) == -1, "shared MP RunnerMotion accepts a valid blocked-state escape flip")
	match_view.set("_pending_flip_direction", 0)
	match_view.call("_unhandled_input", _touch(15, true, Vector2(210, 180)))
	match_view.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not bool(match_view._touch_gesture.call("is_active")) and int(match_view.get("_pending_flip_direction")) == 0, "MP focus loss clears touch and queued flip")
	match_view.queue_free()
	await get_tree().process_frame

func _test_viewport_gui_dispatch() -> void:
	PlayerProfile.flip_control = "swipe"
	var player = PlayerScene.instantiate()
	add_child(player)
	var match_view = MatchScene.instantiate()
	add_child(match_view)
	match_view.set("_runner", LocalRunner.new())
	match_view.get("_runner").configure("viewport-gui-test", 1, 250.0, 460.0)
	match_view.set("_round_started", true)
	match_view.set("_debug_open", false)
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(overlay)
	var menu := Button.new()
	menu.position = Vector2(10, 10)
	menu.size = Vector2(110, 60)
	menu.text = "Menu"
	overlay.add_child(menu)
	var volume := Button.new()
	volume.position = Vector2(130, 10)
	volume.size = Vector2(110, 60)
	volume.text = "Volume"
	overlay.add_child(volume)
	var delivered: Array[String] = []
	menu.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			delivered.append("menu:%s" % str(event.pressed)))
	volume.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			delivered.append("volume:%s" % str(event.pressed)))
	await get_tree().process_frame
	player.gravity_direction = 1
	player.grounded = true
	player.cooldown_left = 0.0
	get_viewport().push_input(_touch(21, true, Vector2(320, 200)), true)
	await get_tree().process_frame
	_check(bool(player._touch_gesture.call("is_active")) and bool(match_view._touch_gesture.call("is_active")), "actual viewport dispatch begins SP and MP gestures from gameplay area")
	get_viewport().push_input(_touch(21, false, Vector2(40, 40)), true)
	await get_tree().process_frame
	_check(int(player.gravity_direction) == 1, "actual GUI-consumed release over menu does not flip SP gravity")
	_check(not bool(player._touch_gesture.call("is_active")), "actual GUI-consumed release clears the game-area gesture")
	_check(int(match_view.get("_pending_flip_direction")) == 0 and not bool(match_view._touch_gesture.call("is_active")), "actual GUI-consumed release over menu does not queue MP flip and clears its gesture")
	get_viewport().push_input(_touch(23, true, Vector2(40, 40)), true)
	get_viewport().push_input(_touch(23, false, Vector2(40, 40)), true)
	get_viewport().push_input(_touch(22, true, Vector2(160, 40)), true)
	get_viewport().push_input(_touch(22, false, Vector2(160, 40)), true)
	await get_tree().process_frame
	_check(delivered.has("menu:true") and delivered.has("menu:false"), "actual viewport dispatch delivers a menu-button touch sequence to GUI")
	_check(delivered.has("volume:true") and delivered.has("volume:false"), "actual viewport dispatch delivers volume-control touch to GUI")
	_check(int(player.gravity_direction) == 1, "touch on volume control never flips SP gravity")
	_check(not bool(player._touch_gesture.call("is_active")), "touch on volume control leaves no stale SP finger")
	_check(int(match_view.get("_pending_flip_direction")) == 0 and not bool(match_view._touch_gesture.call("is_active")), "touch on menu and volume controls never queues MP gravity flip")
	player.queue_free()
	match_view.queue_free()
	layer.queue_free()
	await get_tree().process_frame

func _touch(index: int, pressed: bool, position: Vector2, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	return event

func _check(condition: bool, description: String) -> void:
	if condition:
		return
	failures += 1
	push_error("TOUCH_GESTURE_LIFECYCLE_TEST: " + description)
