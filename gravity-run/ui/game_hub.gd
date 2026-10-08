extends Control

const ActionIconScript := preload("res://ui/action_icon.gd")
const SkinPalette := preload("res://player/skin_palette.gd")
const RunnerFrames := preload("res://assets/character/run_frames.tres")

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
var _seed_edit: LineEdit
var _seed_label: Label
var _seed_mobile_button: Button
var _mobile_text_entry := false
var _skin_preview: TextureRect
var _skin_preview_frame := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_text_entry = MobileTextEntry.is_mobile_web
	MobileTextEntry.entry_submitted.connect(_on_mobile_text_submitted)
	visibility_changed.connect(_on_visibility_changed)
	_build()

func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var panel_width := minf(560.0, get_viewport_rect().size.x - 24.0)
	var panel_height := minf(468.0, get_viewport_rect().size.y - 24.0)
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
	layout.add_theme_constant_override("separation", 6)
	scroll.add_child(layout)
	var title := Label.new()
	title.text = tr("GAME HUB")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color("b8c7dc"))
	_status_label.visible = false
	layout.add_child(_status_label)
	_seed_label = Label.new()
	_seed_label.text = ""
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_font_size_override("font_size", 12)
	_seed_label.add_theme_color_override("font_color", Color("b8c7dc"))
	_seed_label.visible = false
	layout.add_child(_seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("Seed (optional; blank = random)")
	_seed_edit.tooltip_text = tr("Enter a number or a GR-version-seed challenge code.")
	_seed_edit.max_length = 32
	_seed_edit.clear_button_enabled = true
	_seed_edit.text_changed.connect(_on_seed_input_changed)
	layout.add_child(_seed_edit)
	if _mobile_text_entry:
		_seed_edit.visible = false
		_seed_mobile_button = _make_button(tr("Enter course seed"), 44.0)
		_seed_mobile_button.pressed.connect(_open_mobile_seed_entry)
		layout.add_child(_seed_mobile_button)
	_balance_label = Label.new()
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_balance_label.add_theme_color_override("font_color", Color("f5d45e"))
	layout.add_child(_balance_label)
	_start_button = _make_button(tr("Start challenge") if ChallengeService.active else tr("Start run"), 44.0)
	_start_button.pressed.connect(_start_run)
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
	equipment_row.add_child(_make_skin_picker())
	equipment_row.add_child(_make_icon_action("inventory", tr("Character and inventory"), tr("Character / Inventory"), character_requested.emit))
	equipment_row.add_child(_make_icon_action("shop", tr("Shop"), tr("Shop"), shop_requested.emit))
	var main_menu_button := _make_button(tr("Main menu"), 30.0)
	main_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_menu_button.pressed.connect(main_menu_requested.emit)
	layout.add_child(main_menu_button)
	_update_account_summary()
	AuthService.auth_state_changed.connect(_on_account_changed)
	AccountProgress.progress_changed.connect(_on_progress_changed)
	PlayerAccountProfile.profile_changed.connect(_on_profile_changed)

## Runner colour picker. The choice is stored locally (PlayerProfile) and used
## for singleplayer runs and as the default skin in multiplayer lobbies.
func _make_skin_picker() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var previous := Button.new()
	previous.text = "<"
	previous.custom_minimum_size = Vector2(30.0, 48.0)
	previous.tooltip_text = tr("Previous skin")
	previous.accessibility_name = previous.tooltip_text
	previous.pressed.connect(_cycle_skin.bind(-1))
	row.add_child(previous)
	_skin_preview = TextureRect.new()
	_skin_preview.custom_minimum_size = Vector2(48.0, 48.0)
	_skin_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skin_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skin_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skin_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skin_preview.texture = RunnerFrames.get_frame_texture("run", 0)
	row.add_child(_skin_preview)
	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(30.0, 48.0)
	next.tooltip_text = tr("Next skin")
	next.accessibility_name = next.tooltip_text
	next.pressed.connect(_cycle_skin.bind(1))
	row.add_child(next)
	var label := Label.new()
	label.text = tr("Skin")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	column.add_child(label)
	_apply_skin_preview()
	return column

func _cycle_skin(direction: int) -> void:
	PlayerProfile.set_preferred_skin_id(PlayerProfile.preferred_skin_id + direction)
	_apply_skin_preview()

func _apply_skin_preview() -> void:
	if not is_instance_valid(_skin_preview):
		return
	var skin_id := int(PlayerProfile.preferred_skin_id)
	_skin_preview.material = null if skin_id == 0 else SkinPalette.make_material(skin_id)

func _process(delta: float) -> void:
	# Let the preview runner jog in place so the picker reads as a character.
	if not is_instance_valid(_skin_preview) or not is_visible_in_tree():
		return
	var frame_count := RunnerFrames.get_frame_count("run")
	if frame_count <= 0:
		return
	var previous_frame := int(_skin_preview_frame)
	_skin_preview_frame = fmod(_skin_preview_frame + delta * RunnerFrames.get_animation_speed("run"), float(frame_count))
	if int(_skin_preview_frame) != previous_frame:
		_skin_preview.texture = RunnerFrames.get_frame_texture("run", int(_skin_preview_frame))

func _make_icon_action(icon_name: String, accessible_name: String, caption: String, callback: Callable) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var button := Button.new()
	button.custom_minimum_size = Vector2(62.0, 48.0)
	button.tooltip_text = accessible_name
	button.accessibility_name = accessible_name
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
	# Keep routine account state out of the launch form. This label is reserved
	# for actionable validation/status messages set by the relevant interaction.
	_status_label.visible = not _status_label.text.is_empty()
	_balance_label.text = tr("Coins: %d") % AccountProgress.wallet_coins if AuthService.is_authenticated else tr("Coins: —")
	if is_instance_valid(_start_button):
		_start_button.text = tr("Start challenge") if ChallengeService.active else tr("Start run")
	if is_instance_valid(_seed_label):
		_seed_label.visible = false
	if is_instance_valid(_seed_edit):
		_seed_edit.visible = not ChallengeService.active and not _mobile_text_entry
		_seed_edit.editable = not ChallengeService.active
	if is_instance_valid(_seed_mobile_button):
		_seed_mobile_button.visible = not ChallengeService.active
		_seed_mobile_button.disabled = ChallengeService.active
		_seed_mobile_button.text = _seed_edit.text if is_instance_valid(_seed_edit) and not _seed_edit.text.is_empty() else tr("Enter course seed")

func _on_visibility_changed() -> void:
	_update_account_summary()

func _start_run() -> void:
	var seed_input := _seed_edit.text.strip_edges() if is_instance_valid(_seed_edit) and not ChallengeService.active else ""
	if not seed_input.is_empty() and not bool(ChallengeService.call("start_singleplayer_seed_input", seed_input)):
		_status_label.text = tr(str(ChallengeService.get("last_error")))
		_status_label.visible = true
		return
	_status_label.text = ""
	_status_label.visible = false
	start_run_requested.emit()

func _on_seed_input_changed(_new_text: String) -> void:
	if is_instance_valid(_seed_mobile_button):
		_seed_mobile_button.text = _seed_edit.text if not _seed_edit.text.is_empty() else tr("Enter course seed")
	if is_instance_valid(_status_label):
		_status_label.text = ""
		_status_label.visible = false

func _open_mobile_seed_entry() -> void:
	if not _mobile_text_entry or ChallengeService.active:
		return
	MobileTextEntry.open("singleplayer_seed", _seed_edit.text, tr("Course seed"), "text", 32, "text", "off", "characters")

func _on_mobile_text_submitted(field: String, value: String) -> void:
	if field != "singleplayer_seed" or not is_instance_valid(_seed_edit):
		return
	_seed_edit.text = value.substr(0, 32)
	_on_seed_input_changed(_seed_edit.text)

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
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style
