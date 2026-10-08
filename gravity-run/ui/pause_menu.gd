extends CanvasLayer

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"
const INVENTORY_SCREEN_SCENE := preload("res://ui/inventory_screen.tscn")
const ActionIconScript := preload("res://ui/action_icon.gd")
const MusicVolumeControlScript := preload("res://ui/music_volume_control.gd")

var pause_button: Button
var pause_overlay: Control
var resume_button: Button
var menu_layout: VBoxContainer
var pause_panel: PanelContainer
var portrait_forced_pause := false
var manual_pause_requested := false
var _inventory_screen: Control
var _inventory_return_to_pause := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_button()
	_build_pause_overlay()

func _process(_delta: float) -> void:
	if not OS.has_feature("web"):
		return
	var phone_in_portrait := bool(JavaScriptBridge.eval("window.parent.document.documentElement.classList.contains('phone-portrait')"))
	portrait_forced_pause = phone_in_portrait
	_apply_pause_state()

func _unhandled_input(event: InputEvent) -> void:
	if bool(get_parent().get("game_over")):
		return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_inventory_screen):
		_close_inventory()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and not is_instance_valid(_inventory_screen):
		_open_inventory("character")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not manual_pause_requested)
		get_viewport().set_input_as_handled()

func _build_pause_button() -> void:
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = ""
	pause_button.tooltip_text = tr("Pause")
	pause_button.focus_mode = Control.FOCUS_ALL
	pause_button.custom_minimum_size = Vector2(40.0, 40.0)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -52.0
	pause_button.offset_top = 6.0
	pause_button.offset_right = -12.0
	pause_button.offset_bottom = 46.0
	var pause_icon := Control.new()
	pause_icon.name = "PauseIcon"
	pause_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_button.add_child(pause_icon)
	for bar_index in range(2):
		var bar := ColorRect.new()
		bar.name = "PauseBar%d" % bar_index
		bar.color = Color("edf3ff")
		bar.position = Vector2(14.0 + float(bar_index) * 8.0, 12.0)
		bar.size = Vector2(4.0, 16.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pause_icon.add_child(bar)
	pause_button.pressed.connect(_set_paused.bind(true))
	add_child(pause_button)
	var character_button := _make_hud_action("inventory", tr("Character / Inventory"), "character")
	character_button.offset_left = -148.0
	character_button.offset_right = -108.0
	add_child(character_button)
	var shop_button := _make_hud_action("shop", tr("Shop"), "shop")
	shop_button.offset_left = -100.0
	shop_button.offset_right = -60.0
	add_child(shop_button)

func _make_hud_action(icon_name: String, accessible_name: String, mode: String) -> Button:
	var button := Button.new()
	button.text = ""
	button.tooltip_text = accessible_name
	button.accessibility_name = accessible_name
	button.custom_minimum_size = Vector2(40.0, 40.0)
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	button.offset_top = 6.0
	button.offset_bottom = 46.0
	var icon := Control.new()
	icon.set_script(ActionIconScript)
	icon.set("icon_name", icon_name)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_left = 0.5
	icon.anchor_right = 0.5
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -15
	icon.offset_right = 15
	icon.offset_top = -15
	icon.offset_bottom = 15
	button.add_child(icon)
	button.pressed.connect(_open_inventory.bind(mode))
	return button

func _build_pause_overlay() -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	add_child(pause_overlay)

	var dimmer := ColorRect.new()
	dimmer.name = "GrayFilter"
	dimmer.color = Color(0.48, 0.51, 0.58, 0.68)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	pause_panel = PanelContainer.new()
	var pause_size := get_viewport().get_visible_rect().size
	pause_panel.custom_minimum_size = Vector2(minf(360.0, pause_size.x - 24.0), minf(450.0, pause_size.y - 24.0))
	pause_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(pause_panel)

	var pause_scroll := ScrollContainer.new()
	pause_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pause_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_panel.add_child(pause_scroll)
	menu_layout = VBoxContainer.new()
	menu_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_layout.add_theme_constant_override("separation", 14)
	pause_scroll.add_child(menu_layout)
	_show_pause_actions()

func _show_pause_actions() -> void:
	_clear_menu_layout()

	var title := Label.new()
	title.text = tr("PAUSED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	menu_layout.add_child(title)

	var hint := Label.new()
	hint.text = tr("Game paused")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("b9c8dc"))
	menu_layout.add_child(hint)
	resume_button = Button.new()
	resume_button.text = tr("Resume")
	resume_button.custom_minimum_size = Vector2(0.0, 44.0)
	resume_button.pressed.connect(_set_paused.bind(false))
	menu_layout.add_child(resume_button)
	var character_button := Button.new()
	character_button.text = tr("Character / Inventory")
	character_button.custom_minimum_size = Vector2(0.0, 40.0)
	character_button.pressed.connect(_open_inventory.bind("character"))
	menu_layout.add_child(character_button)
	var shop_button := Button.new()
	shop_button.text = tr("Shop")
	shop_button.custom_minimum_size = Vector2(0.0, 40.0)
	shop_button.pressed.connect(_open_inventory.bind("shop"))
	menu_layout.add_child(shop_button)

	var options_button := Button.new()
	options_button.text = tr("Options")
	options_button.custom_minimum_size = Vector2(0.0, 44.0)
	options_button.pressed.connect(_show_control_options)
	menu_layout.add_child(options_button)

	if get_parent().has_method("save_render_diagnostics"):
		var diagnostics_button := Button.new()
		diagnostics_button.text = tr("Smoothness diagnostics")
		diagnostics_button.custom_minimum_size.y = 40
		diagnostics_button.pressed.connect(_show_smoothness_diagnostics)
		menu_layout.add_child(diagnostics_button)

	var menu_button := Button.new()
	menu_button.text = tr("Return to game hub")
	menu_button.custom_minimum_size = Vector2(0.0, 44.0)
	menu_button.pressed.connect(_quit_to_main_menu)
	menu_layout.add_child(menu_button)

func _show_smoothness_diagnostics() -> void:
	_clear_menu_layout()
	var capture := CheckButton.new()
	capture.text = tr("Record smoothness")
	capture.button_pressed = bool(get_parent().get("render_diagnostics_enabled"))
	capture.toggled.connect(func(enabled: bool) -> void: get_parent().call("set_render_diagnostics_enabled", enabled))
	menu_layout.add_child(capture)
	var hint := Label.new()
	hint.text = tr("Enable recording, resume and play, then return here to save.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_layout.add_child(hint)
	var notice := Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var save := Button.new()
	save.text = tr("Save diagnostics")
	save.custom_minimum_size.y = 44
	save.pressed.connect(func() -> void: notice.text = str(get_parent().call("save_render_diagnostics")))
	menu_layout.add_child(save)
	menu_layout.add_child(notice)
	var resume := Button.new()
	resume.text = tr("Resume")
	resume.custom_minimum_size.y = 44
	resume.pressed.connect(_set_paused.bind(false))
	menu_layout.add_child(resume)
	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size.y = 44
	back.pressed.connect(_show_pause_actions)
	menu_layout.add_child(back)

func _show_control_options() -> void:
	_clear_menu_layout()
	var title := Label.new()
	title.text = tr("OPTIONS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	menu_layout.add_child(title)

	var is_touch_device := DisplayServer.is_touchscreen_available()
	var hint := Label.new()
	hint.text = tr("Mobile gravity control") if is_touch_device else tr("Desktop gravity control")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("b9c8dc"))
	menu_layout.add_child(hint)

	var control_options: Array[Dictionary] = []
	if is_touch_device:
		control_options.append({"mode": "swipe", "label": tr("Swipe up / down")})
		control_options.append({"mode": "tap", "label": tr("Tap screen to flip")})
	else:
		control_options.append({"mode": "keyboard", "label": tr("Swap with W / S")})
		control_options.append({"mode": "mouse", "label": tr("Swap with mouse click")})
	for option in control_options:
		var mode := str(option["mode"])
		var button := Button.new()
		button.text = ("[x]  " if PlayerProfile.flip_control == mode else "") + str(option["label"])
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.pressed.connect(_select_control.bind(mode))
		menu_layout.add_child(button)
	var music_volume_control: Control = MusicVolumeControlScript.new()
	menu_layout.add_child(music_volume_control)

	var back_button := Button.new()
	var language_row := HBoxContainer.new()
	language_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var language_button := Button.new()
	language_button.text = "‹   %s   ›" % ("Svenska" if PlayerProfile.language == "sv" else "English")
	language_button.custom_minimum_size = Vector2(0.0, 44.0)
	language_button.pressed.connect(_cycle_language)
	language_row.add_child(language_button)
	menu_layout.add_child(language_row)

	back_button.text = tr("Back to pause menu")
	back_button.custom_minimum_size = Vector2(0.0, 44.0)
	back_button.pressed.connect(_show_pause_actions)
	menu_layout.add_child(back_button)
	back_button.grab_focus()

func _cycle_language() -> void:
	PlayerProfile.set_language("en" if PlayerProfile.language == "sv" else "sv")
	_show_control_options()

func _select_control(mode: String) -> void:
	PlayerProfile.set_flip_control(mode)
	_show_control_options()

func _clear_menu_layout() -> void:
	for child in menu_layout.get_children():
		menu_layout.remove_child(child)
		child.queue_free()

func _set_paused(paused: bool) -> void:
	if not is_inside_tree():
		return
	manual_pause_requested = paused
	if paused:
		_show_pause_actions()
	_apply_pause_state()
	if paused and is_instance_valid(resume_button):
		resume_button.grab_focus()

func _apply_pause_state() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = manual_pause_requested or portrait_forced_pause or is_instance_valid(_inventory_screen)
	MusicController.set_stream_paused(get_tree().paused)
	if is_instance_valid(pause_overlay):
		pause_overlay.visible = manual_pause_requested and not is_instance_valid(_inventory_screen)
	if is_instance_valid(pause_button):
		pause_button.visible = not manual_pause_requested and not is_instance_valid(_inventory_screen)

func _open_inventory(mode: String) -> void:
	if is_instance_valid(_inventory_screen):
		return
	_inventory_return_to_pause = manual_pause_requested
	_inventory_screen = INVENTORY_SCREEN_SCENE.instantiate()
	_inventory_screen.view_mode = mode
	_inventory_screen.equipment_locked = true
	_inventory_screen.back_requested.connect(_on_inventory_back)
	add_child(_inventory_screen)
	_apply_pause_state()

func _on_inventory_back() -> void:
	_inventory_screen = null
	if _inventory_return_to_pause:
		manual_pause_requested = true
		_show_pause_actions()
	_apply_pause_state()
	if _inventory_return_to_pause and is_instance_valid(resume_button):
		resume_button.grab_focus()

func _close_inventory() -> void:
	if is_instance_valid(_inventory_screen):
		var screen := _inventory_screen
		_inventory_screen = null
		screen.queue_free()
	if _inventory_return_to_pause:
		manual_pause_requested = true
		_show_pause_actions()
	_apply_pause_state()

## Fades the in-run toolbar (pause, character, shop) while the runner is
## underneath it. The buttons stay clickable.
func set_toolbar_alpha(alpha: float) -> void:
	for child in get_children():
		if child is Button:
			(child as Button).modulate.a = alpha

func _quit_to_main_menu() -> void:
	manual_pause_requested = false
	get_tree().paused = false
	if Campaign.is_active():
		# Leaving a campaign stage goes back to its world map.
		AppNavigation.request_campaign_map()
	else:
		AppNavigation.request_game_hub()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	return style
