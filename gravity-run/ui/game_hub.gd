extends Control

signal start_run_requested
signal challenges_requested
signal leaderboard_requested
signal achievements_requested
signal character_requested
signal shop_requested
signal multiplayer_requested
signal main_menu_requested

var _status_label: Label
var _balance_label: Label
var _start_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var panel_width := minf(560.0, get_viewport_rect().size.x - 32.0)
	var panel_height := minf(500.0, get_viewport_rect().size.y - 28.0)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	scroll.add_child(layout)
	var title := Label.new()
	title.text = tr("GAME HUB")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_status_label)
	_balance_label = Label.new()
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_balance_label.add_theme_color_override("font_color", Color("f5d45e"))
	layout.add_child(_balance_label)
	_start_button = _make_button(tr("Start challenge") if ChallengeService.active else tr("Start run"), 44.0)
	_start_button.pressed.connect(start_run_requested.emit)
	layout.add_child(_start_button)
	var challenge_button := _make_button(tr("Challenges"), 38.0)
	challenge_button.pressed.connect(challenges_requested.emit)
	layout.add_child(challenge_button)
	var progression_row := HBoxContainer.new()
	progression_row.add_theme_constant_override("separation", 8)
	layout.add_child(progression_row)
	var leaderboard_button := _make_button(tr("Leaderboard"), 36.0)
	leaderboard_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leaderboard_button.pressed.connect(leaderboard_requested.emit)
	progression_row.add_child(leaderboard_button)
	var achievements_button := _make_button(tr("Achievements"), 36.0)
	achievements_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievements_button.pressed.connect(achievements_requested.emit)
	progression_row.add_child(achievements_button)
	var multiplayer_button := _make_button(tr("Multiplayer"), 38.0)
	multiplayer_button.pressed.connect(multiplayer_requested.emit)
	layout.add_child(multiplayer_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	var equipment_row := HBoxContainer.new()
	equipment_row.alignment = BoxContainer.ALIGNMENT_CENTER
	equipment_row.add_theme_constant_override("separation", 16)
	layout.add_child(equipment_row)
	equipment_row.add_child(_make_icon_action("◈", tr("Character and inventory"), tr("Character / Inventory"), character_requested.emit))
	equipment_row.add_child(_make_icon_action("▤", tr("Shop"), tr("Shop"), shop_requested.emit))
	var main_menu_button := _make_button(tr("Main menu"), 32.0)
	main_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_menu_button.pressed.connect(main_menu_requested.emit)
	layout.add_child(main_menu_button)
	_update_account_summary()
	AuthService.auth_state_changed.connect(_on_account_changed)
	AccountProgress.progress_changed.connect(_on_progress_changed)
	PlayerAccountProfile.profile_changed.connect(_on_profile_changed)

func _make_icon_action(glyph: String, accessible_name: String, caption: String, callback: Callable) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var button := Button.new()
	button.custom_minimum_size = Vector2(76.0, 64.0)
	button.tooltip_text = accessible_name
	button.accessibility_name = accessible_name
	button.add_theme_font_size_override("font_size", 26)
	button.text = glyph
	button.pressed.connect(callback)
	column.add_child(button)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	column.add_child(label)
	return column

func _make_button(text_value: String, height: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, height)
	button.add_theme_font_size_override("font_size", 14)
	return button

func _update_account_summary() -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = tr("Signed in · inventory is synced") if AuthService.is_authenticated else tr("Guest · sign in to save inventory")
	_balance_label.text = tr("Coins: %d") % AccountProgress.wallet_coins if AuthService.is_authenticated else tr("Coins: —")
	if is_instance_valid(_start_button):
		_start_button.text = tr("Start challenge") if ChallengeService.active else tr("Start run")

func _on_account_changed(_authenticated: bool, _email: String) -> void:
	_update_account_summary()

func _on_progress_changed(_coins: int, _distance: int, _best: int) -> void:
	_update_account_summary()

func _on_profile_changed(_nickname: String, _has_profile: bool) -> void:
	_update_account_summary()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 15.0
	style.content_margin_bottom = 15.0
	return style
