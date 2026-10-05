extends Node

const HubScene := preload("res://ui/game_hub.tscn")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(390, 844)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_tree().root.add_child(viewport)
		var hub := HubScene.instantiate() as Control
		hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(hub)
		await get_tree().process_frame
		await get_tree().process_frame
		var scrolls := hub.find_children("*", "ScrollContainer", true, false)
		var scroll := scrolls[0] as ScrollContainer if not scrolls.is_empty() else null
		var seed_edit := hub.get("_seed_edit") as LineEdit
		var main_menu_button: Button
		var buttons := hub.find_children("*", "Button", true, false)
		if not buttons.is_empty():
			main_menu_button = buttons[buttons.size() - 1] as Button
		_check(scroll != null and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "%s retains vertical scrolling as a small/tall-view fallback" % str(size))
		_check(seed_edit != null and seed_edit.focus_mode == Control.FOCUS_ALL and seed_edit.visible, "%s keeps seed input keyboard/touch reachable" % str(size))
		_check(main_menu_button != null and main_menu_button.visible, "%s keeps the main-menu action present" % str(size))
		if size.x >= 900 and size.y >= 540 and main_menu_button != null:
			var rect := main_menu_button.get_global_rect()
			_check(rect.position.y >= 0.0 and rect.end.y <= float(size.y) + 1.0, "%s fits the main-menu action without scrolling" % str(size))
		_check(not bool(hub.get("_status_label").visible) and not bool(hub.get("_seed_label").visible), "%s omits routine account/technical copy" % str(size))
		hub.queue_free()
		viewport.queue_free()
		await get_tree().process_frame
	print("GAME_HUB_COMPACT_LAYOUT_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
