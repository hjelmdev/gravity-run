extends Control

const GAME_SCENE := preload("res://main.tscn")
const TEST_LAB_SCENE := "res://tools/test_hub.tscn"
const COURSE_GENERATOR_SCRIPT := preload("res://systems/course_generator.gd")
const COURSE_RULESET_SCRIPT := preload("res://systems/course_generation_ruleset.gd")

var menu_panel: PanelContainer
var _leaderboard_rows: VBoxContainer
var _leaderboard_status: Label
var _leaderboard_title: Label
var _leaderboard_subtitle: Label
var _account_status: Label
var _account_progress_label: Label
var _account_email: LineEdit
var _account_password: LineEdit
var _account_nickname: LineEdit
var _nickname_save_button: Button
var _account_scroll: ScrollContainer
var _menu_view := "main"
var _return_to_main_after_profile_load := false
var _email_auth_mode := "sign_in"
var _leaderboard_mode := "best_run"
var _challenge_code_edit: LineEdit
var _challenge_status: Label
var _challenge_join_button: Button
var _challenge_preview_ready := false
var _challenge_score_rows: VBoxContainer
var _challenge_score_status: Label
var _challenge_creator_label: Label
var _challenge_difficulty_label: Label
var _challenge_hazards_label: Label
var _challenge_title_label: Label
var _saved_challenge_status: Label
var _saved_challenge_rows: VBoxContainer
var _achievement_group_cards: Array[Control] = []
var _achievement_group_overlay_id := ""
var _create_challenge_difficulty: OptionButton
var _create_challenge_name: LineEdit
var _create_challenge_title: LineEdit
var _create_challenge_profiles: Array[CheckBox] = []
var _create_challenge_status: Label
var _create_challenge_button: Button

func _ready() -> void:
	Leaderboard.top_runs_received.connect(_on_top_runs_received)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	AuthService.auth_action_finished.connect(_on_auth_action_finished)
	PlayerAccountProfile.profile_changed.connect(_on_account_profile_changed)
	PlayerAccountProfile.action_finished.connect(_on_account_profile_action_finished)
	AccountProgress.progress_changed.connect(_on_account_progress_changed)
	AccountProgress.total_distance_leaderboard_received.connect(_on_total_distance_leaderboard_received)
	AccountProgress.monthly_distance_leaderboard_received.connect(_on_monthly_distance_leaderboard_received)
	AchievementService.state_changed.connect(_on_achievement_state_changed)
	ChallengeService.challenge_definition_received.connect(_on_challenge_definition_received)
	ChallengeService.leaderboard_received.connect(_on_challenge_leaderboard_received)
	ChallengeService.challenge_created.connect(_on_menu_challenge_created)
	ChallengeService.challenge_library_received.connect(_on_challenge_library_received)
	var demo_background: Node = GAME_SCENE.instantiate()
	demo_background.name = "AutoplayBackground"
	demo_background.set("demo_mode", true)
	add_child(demo_background)
	_build_menu()
	var launch_challenge_code := ChallengeService.read_challenge_code_from_web_url()
	if not launch_challenge_code.is_empty():
		_show_challenge_menu(launch_challenge_code)
		if not ChallengeService.load_challenge_code(launch_challenge_code):
			_challenge_status.text = tr(ChallengeService.last_error)
			_challenge_status.visible = true
		elif launch_challenge_code.to_upper().begins_with("GC-"):
			_challenge_status.text = tr("Loading challenge...")
			_challenge_status.visible = true
		else:
			_challenge_preview_ready = true
			_challenge_join_button.text = tr("Start challenge")
			ChallengeService.fetch_current_scores()

func _build_menu() -> void:
	var tint := ColorRect.new()
	tint.color = Color(0.035, 0.055, 0.09, 0.34)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	_show_main_menu()

func _show_main_menu() -> void:
	_menu_view = "main"
	_clear_menu_panel()
	var viewport_size := get_viewport_rect().size
	var panel_height := minf(500.0, maxf(viewport_size.y - 32.0, 360.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(320.0, panel_height)
	menu_panel.anchor_left = 1.0
	menu_panel.anchor_right = 1.0
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -344.0
	menu_panel.offset_right = -24.0
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	var main_panel_style := _panel_style()
	main_panel_style.content_margin_left = 16.0
	main_panel_style.content_margin_right = 16.0
	main_panel_style.content_margin_top = 16.0
	main_panel_style.content_margin_bottom = 16.0
	menu_panel.add_theme_stylebox_override("panel", main_panel_style)
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	menu_panel.add_child(layout)

	var title := Label.new()
	title.text = tr("GRAVITY RUN")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)

	var tagline := Label.new()
	tagline.text = "RUN  ·  FLIP  ·  SURVIVE"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 11)
	tagline.add_theme_color_override("font_color", Color("42d6c5"))
	layout.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 2.0
	layout.add_child(spacer)

	var new_game_button := _make_button(tr("New Game"))
	new_game_button.custom_minimum_size.y = 36.0
	new_game_button.pressed.connect(_start_new_game)
	layout.add_child(new_game_button)

	var challenge_button := _make_button(tr("Challenges"))
	challenge_button.custom_minimum_size.y = 36.0
	challenge_button.pressed.connect(_show_challenge_options)
	layout.add_child(challenge_button)

	var leaderboard_button := _make_button(tr("Leaderboard"))
	leaderboard_button.custom_minimum_size.y = 36.0
	leaderboard_button.pressed.connect(_show_leaderboard_menu)
	layout.add_child(leaderboard_button)

	if AuthService.is_authenticated:
		var achievements_button := _make_button(tr("Achievements"))
		achievements_button.custom_minimum_size.y = 36.0
		achievements_button.pressed.connect(_show_achievements_menu)
		layout.add_child(achievements_button)

	var test_lab_button := _make_button(tr("Test Lab"))
	test_lab_button.custom_minimum_size.y = 36.0
	test_lab_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TEST_LAB_SCENE))
	layout.add_child(test_lab_button)

	var account_label := tr("Account")
	if AuthService.is_authenticated:
		account_label = tr("Account · %s") % PlayerAccountProfile.nickname if PlayerAccountProfile.has_profile else tr("Account · Signed in")
	var account_button := _make_button(account_label)
	account_button.custom_minimum_size.y = 36.0
	account_button.pressed.connect(_show_account_menu)
	layout.add_child(account_button)

	var options_button := _make_button(tr("Options"))
	options_button.custom_minimum_size.y = 36.0
	options_button.pressed.connect(_show_options_menu)
	layout.add_child(options_button)

	var quit_button := _make_button(tr("Quit Game"))
	quit_button.custom_minimum_size.y = 36.0
	quit_button.pressed.connect(_quit_game)
	layout.add_child(quit_button)

	new_game_button.grab_focus()

func _show_achievements_menu() -> void:
	if not AuthService.is_authenticated:
		return
	_menu_view = "achievements"
	_clear_menu_panel()
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(1400.0, maxf(viewport_size.x - 32.0, 320.0))
	var panel_height := minf(520.0, maxf(viewport_size.y - 24.0, 320.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	var achievements_panel_style := _panel_style()
	achievements_panel_style.content_margin_left = 14.0
	achievements_panel_style.content_margin_right = 14.0
	achievements_panel_style.content_margin_top = 12.0
	achievements_panel_style.content_margin_bottom = 12.0
	menu_panel.add_theme_stylebox_override("panel", achievements_panel_style)
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	menu_panel.add_child(layout)
	var title := Label.new()
	title.text = tr("ACHIEVEMENTS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	var summary := Label.new()
	summary.text = tr("Achievements are tied to your account.")
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.columns = clampi(floori((panel_width - 64.0) / 270.0), 1, 5)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var grid_width := panel_width - 56.0
	grid.custom_minimum_size.x = grid_width
	var card_width := minf(280.0, (grid_width - 16.0 - float(grid.columns - 1) * 6.0) / float(grid.columns))
	scroll.add_child(grid)
	var unlocked_count := 0
	var visible_count := 0
	var grouped_definitions: Dictionary = {}
	var group_order: Array[String] = []
	for definition in AchievementService.get_definitions():
		var achievement_id := str(definition.id)
		if not grouped_definitions.has(achievement_id):
			grouped_definitions[achievement_id] = []
			group_order.append(achievement_id)
		grouped_definitions[achievement_id].append(definition)
	for achievement_id in group_order:
		var group_definitions: Array = grouped_definitions[achievement_id]
		group_definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("tier", 0)) < int(b.get("tier", 0))
		)
		var available_definitions: Array = []
		var group_unlocked := 0
		for definition in group_definitions:
			var tier := int(definition.get("tier", 1))
			var is_unlocked := AchievementService.is_unlocked(achievement_id, tier)
			if str(definition.get("visibility", "visible")) == "secret" and not is_unlocked:
				continue
			available_definitions.append(definition)
			visible_count += 1
			if is_unlocked:
				group_unlocked += 1
				unlocked_count += 1
		if available_definitions.is_empty():
			continue
		var current_definition: Dictionary = available_definitions.back()
		for definition in available_definitions:
			if not AchievementService.is_unlocked(achievement_id, int(definition.get("tier", 1))):
				current_definition = definition
				break
		var displayable_definitions: Array = []
		for definition in available_definitions:
			var tier := int(definition.get("tier", 1))
			var is_unlocked := AchievementService.is_unlocked(achievement_id, tier)
			if is_unlocked or tier <= 1 or AchievementService.is_unlocked(achievement_id, tier - 1):
				displayable_definitions.append(definition)
		var deck := Control.new()
		var back_card_count := maxi(displayable_definitions.size() - 1, 0)
		deck.custom_minimum_size = Vector2(card_width, 62.0)
		grid.add_child(deck)
		for stack_index in range(back_card_count):
			var back_card := PanelContainer.new()
			var back_y := 10.0 * float(stack_index) / float(back_card_count)
			back_card.position = Vector2(0.0, back_y)
			back_card.size = Vector2(card_width, 52.0)
			back_card.add_theme_stylebox_override("panel", _achievement_menu_stack_back_style())
			deck.add_child(back_card)
		var group_card := PanelContainer.new()
		var front_offset := 10.0
		group_card.position = Vector2(0.0, front_offset)
		group_card.size = Vector2(card_width, 52.0)
		group_card.custom_minimum_size = group_card.size
		group_card.add_theme_stylebox_override("panel", _achievement_menu_card_style(group_unlocked > 0))
		deck.add_child(group_card)
		var group_content := VBoxContainer.new()
		group_content.add_theme_constant_override("separation", 2)
		group_card.add_child(group_content)
		var group_button := Button.new()
		var base_title := _achievement_group_title(tr(str(group_definitions[0].get("title", achievement_id))))
		group_button.text = "▸ " + base_title + "  %d/%d" % [group_unlocked, group_definitions.size()]
		group_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		group_button.flat = true
		group_button.custom_minimum_size.y = 20.0
		group_button.add_theme_font_size_override("font_size", 10)
		group_button.add_theme_color_override("font_color", Color("edf3ff"))
		group_button.pressed.connect(_show_achievement_group_overlay.bind(achievement_id, displayable_definitions, group_card))
		group_content.add_child(group_button)
		var next_unlocked := AchievementService.is_unlocked(achievement_id, int(current_definition.get("tier", 1)))
		var summary_row := HBoxContainer.new()
		summary_row.add_theme_constant_override("separation", 4)
		group_content.add_child(summary_row)
		var summary_badge := Label.new()
		summary_badge.text = "★" if next_unlocked else "◇"
		summary_badge.custom_minimum_size = Vector2(12, 12)
		summary_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary_badge.add_theme_font_size_override("font_size", 9)
		summary_badge.add_theme_color_override("font_color", Color("f5d45e") if next_unlocked else Color("718098"))
		summary_row.add_child(summary_badge)
		var summary_column := VBoxContainer.new()
		summary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_column.add_theme_constant_override("separation", 0)
		summary_row.add_child(summary_column)
		var description := Label.new()
		description.text = tr(str(current_definition.get("description", "")))
		description.add_theme_font_size_override("font_size", 8)
		description.add_theme_color_override("font_color", Color("b8c7dc"))
		summary_column.add_child(description)
		if not next_unlocked:
			var progress: Dictionary = AchievementService.get_progress(current_definition)
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 3
			bar.show_percentage = false
			bar.max_value = int(progress.target)
			bar.value = int(progress.current)
			summary_column.add_child(bar)
	var count_label := Label.new()
	count_label.text = tr("Unlocked %d of %d") % [unlocked_count, visible_count]
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color("42d6c5"))
	layout.add_child(count_label)
	var back := _make_button(tr("Back"))
	back.custom_minimum_size.y = 36
	back.pressed.connect(_show_main_menu)
	layout.add_child(back)

func _on_achievement_state_changed() -> void:
	if _menu_view == "achievements":
		_show_achievements_menu()

func _show_achievement_group_overlay(achievement_id: String, definitions: Array, source_card: Control) -> void:
	if not _achievement_group_cards.is_empty() and _achievement_group_overlay_id == achievement_id:
		_close_achievement_group_overlay()
		return
	_close_achievement_group_overlay()
	_achievement_group_overlay_id = achievement_id
	var overlay_width := minf(source_card.size.x, 420.0)
	var card_height := 48.0
	var card_step := 40.0
	var stack_height := card_height + float(definitions.size() - 1) * card_step
	var panel_rect := menu_panel.get_global_rect()
	var root_rect := get_global_rect()
	var source_rect := source_card.get_global_rect()
	var stack_x := source_rect.position.x - root_rect.position.x
	var stack_y := source_rect.position.y - root_rect.position.y - 10.0
	stack_x = clampf(stack_x, panel_rect.position.x - root_rect.position.x + 12.0, panel_rect.end.x - root_rect.position.x - overlay_width - 12.0)
	stack_y = clampf(stack_y, panel_rect.position.y - root_rect.position.y + 48.0, panel_rect.end.y - root_rect.position.y - stack_height - 54.0)
	for index in range(definitions.size()):
		var definition: Dictionary = definitions[index]
		var tier := int(definition.get("tier", 1))
		var is_unlocked := AchievementService.is_unlocked(achievement_id, tier)
		var card := PanelContainer.new()
		card.position = Vector2(stack_x, stack_y + float(index) * card_step)
		card.size = Vector2(overlay_width, card_height)
		card.custom_minimum_size = card.size
		card.z_index = 100 + index
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_stylebox_override("panel", _achievement_menu_card_style(is_unlocked))
		add_child(card)
		_achievement_group_cards.append(card)
		if index == 0:
			card.gui_input.connect(_on_achievement_expanded_card_input)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		card.add_child(content)
		var heading_row := HBoxContainer.new()
		content.add_child(heading_row)
		var badge := Label.new()
		badge.text = "★" if is_unlocked else "◇"
		badge.custom_minimum_size = Vector2(12.0, 12.0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", Color("f5d45e") if is_unlocked else Color("718098"))
		heading_row.add_child(badge)
		var title := Label.new()
		title.text = tr(str(definition.get("title", achievement_id)))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 9)
		title.add_theme_color_override("font_color", Color("edf3ff") if is_unlocked else Color("b8c7dc"))
		heading_row.add_child(title)
		if index == 0:
			var close_button := Button.new()
			close_button.text = "×"
			close_button.flat = true
			close_button.custom_minimum_size = Vector2(16.0, 16.0)
			close_button.add_theme_font_size_override("font_size", 11)
			close_button.pressed.connect(_close_achievement_group_overlay)
			heading_row.add_child(close_button)
		var description := Label.new()
		description.text = tr(str(definition.get("description", "")))
		description.add_theme_font_size_override("font_size", 8)
		description.add_theme_color_override("font_color", Color("b8c7dc"))
		content.add_child(description)
		if not is_unlocked:
			var progress: Dictionary = AchievementService.get_progress(definition)
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 3
			bar.show_percentage = false
			bar.max_value = int(progress.target)
			bar.value = int(progress.current)
			content.add_child(bar)

func _close_achievement_group_overlay() -> void:
	for card in _achievement_group_cards:
		if is_instance_valid(card):
			card.queue_free()
	_achievement_group_cards.clear()
	_achievement_group_overlay_id = ""

func _on_achievement_expanded_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_achievement_group_overlay()

func _achievement_group_title(title: String) -> String:
	for suffix in [" III", " II", " I", " 3", " 2", " 1"]:
		if title.ends_with(suffix):
			return title.trim_suffix(suffix)
	return title

func _achievement_menu_card_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101827")
	style.border_color = Color("42d6c5", 0.65) if is_unlocked else Color("53647d", 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _achievement_menu_stack_back_style() -> StyleBoxFlat:
	var style := _achievement_menu_card_style(false)
	style.bg_color = Color("101827")
	style.border_color = Color("287f7c", 0.85)
	return style

func _show_challenge_menu(launch_code: String = "") -> void:
	_menu_view = "challenge"
	_clear_menu_panel()
	_challenge_code_edit = null
	_challenge_status = null
	_challenge_join_button = null
	_challenge_preview_ready = false
	_challenge_score_rows = null
	_challenge_score_status = null
	_challenge_creator_label = null
	_challenge_difficulty_label = null
	_challenge_hazards_label = null
	_challenge_title_label = null
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(520.0, maxf(viewport_size.x - 32.0, 280.0))
	var panel_height := minf(520.0, maxf(viewport_size.y - 32.0, 300.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_panel.add_child(content_scroll)
	content_scroll.add_child(layout)
	_challenge_title_label = Label.new()
	_challenge_title_label.text = tr("JOIN CHALLENGE")
	_challenge_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_title_label.add_theme_font_size_override("font_size", 28)
	_challenge_title_label.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(_challenge_title_label)
	var description := Label.new()
	description.text = tr("Play a friend's course and compare your distance.")
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(description)
	_challenge_code_edit = LineEdit.new()
	_challenge_code_edit.placeholder_text = tr("Challenge code, e.g. GR2-1234567890")
	_challenge_code_edit.max_length = 24
	_challenge_code_edit.text = launch_code
	_challenge_code_edit.custom_minimum_size.y = 44.0
	layout.add_child(_challenge_code_edit)
	_challenge_join_button = _make_button(tr("Join challenge"))
	_challenge_join_button.pressed.connect(_join_seed_challenge)
	layout.add_child(_challenge_join_button)
	_challenge_status = Label.new()
	_challenge_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_status.add_theme_color_override("font_color", Color("ffbd5c"))
	_challenge_status.visible = false
	layout.add_child(_challenge_status)
	_challenge_creator_label = Label.new()
	_challenge_creator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_creator_label.add_theme_font_size_override("font_size", 14)
	_challenge_creator_label.add_theme_color_override("font_color", Color("b8c7dc"))
	_challenge_creator_label.visible = false
	layout.add_child(_challenge_creator_label)
	_challenge_difficulty_label = Label.new()
	_challenge_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_difficulty_label.add_theme_font_size_override("font_size", 16)
	_challenge_difficulty_label.add_theme_color_override("font_color", Color("f5d45e"))
	_challenge_difficulty_label.visible = false
	layout.add_child(_challenge_difficulty_label)
	_challenge_hazards_label = Label.new()
	_challenge_hazards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_hazards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_hazards_label.add_theme_font_size_override("font_size", 14)
	_challenge_hazards_label.add_theme_color_override("font_color", Color("b8c7dc"))
	_challenge_hazards_label.visible = false
	layout.add_child(_challenge_hazards_label)
	var scores_title := Label.new()
	scores_title.text = tr("CHALLENGE RECORDS")
	scores_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores_title.add_theme_color_override("font_color", Color("42d6c5"))
	layout.add_child(scores_title)
	_challenge_score_rows = VBoxContainer.new()
	_challenge_score_rows.add_theme_constant_override("separation", 2)
	layout.add_child(_challenge_score_rows)
	_challenge_score_status = Label.new()
	_challenge_score_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_score_status.add_theme_color_override("font_color", Color("b8c7dc"))
	_challenge_score_status.visible = false
	layout.add_child(_challenge_score_status)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	layout.add_child(back_button)
	if launch_code.is_empty():
		_challenge_code_edit.grab_focus()

func _show_challenge_options() -> void:
	_menu_view = "challenge_options"
	_clear_menu_panel()
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(360.0, 360.0)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -180.0
	menu_panel.offset_right = 180.0
	menu_panel.offset_top = -180.0
	menu_panel.offset_bottom = 180.0
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	menu_panel.add_child(layout)
	var title := Label.new()
	title.text = tr("CHALLENGES")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	var join_button := _make_button(tr("Join challenge"))
	join_button.pressed.connect(_show_challenge_menu)
	layout.add_child(join_button)
	var create_button := _make_button(tr("Create challenge"))
	create_button.pressed.connect(_show_create_challenge_menu)
	layout.add_child(create_button)
	var saved_button := _make_button(tr("My challenges"))
	saved_button.pressed.connect(_show_saved_challenges_menu)
	layout.add_child(saved_button)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	layout.add_child(back_button)

func _join_seed_challenge() -> void:
	if not is_instance_valid(_challenge_code_edit) or not is_instance_valid(_challenge_status):
		return
	if _challenge_preview_ready:
		ChallengeService.clear_challenge_code_from_web_url(ChallengeService.get_challenge_code())
		get_tree().change_scene_to_packed(GAME_SCENE)
		return
	var code := _challenge_code_edit.text.strip_edges().to_upper()
	if not ChallengeService.load_challenge_code(code):
		_challenge_status.text = tr(ChallengeService.last_error)
		return
	if code.begins_with("GC-"):
		_challenge_status.text = tr("Loading challenge...")
		_challenge_status.visible = true
		_challenge_join_button.disabled = true
	else:
		get_tree().change_scene_to_packed(GAME_SCENE)

func _on_challenge_definition_received(success: bool, definition: Dictionary, error_message: String) -> void:
	if _menu_view != "challenge" or not is_instance_valid(_challenge_status):
		return
	if not success:
		_challenge_status.text = tr(error_message)
		_challenge_status.visible = true
		if is_instance_valid(_challenge_join_button):
			_challenge_join_button.disabled = false
		return
	_challenge_preview_ready = true
	if is_instance_valid(_challenge_join_button):
		_challenge_join_button.disabled = false
		_challenge_join_button.text = tr("Start challenge")
	var ruleset: Variant = definition.get("ruleset", {})
	var challenge_name := str(definition.get("challenge_name", ""))
	if not challenge_name.is_empty() and is_instance_valid(_challenge_title_label):
		_challenge_title_label.text = challenge_name
	var included: Variant = ruleset.get("included_profile_ids", []) if ruleset is Dictionary else []
	var hazard_names := PackedStringArray()
	if bool(ruleset.get("include_all_profiles", true)):
		hazard_names.append(tr("All current hazards"))
	else:
		for profile_id in included:
			hazard_names.append(_friendly_hazard_name(str(profile_id)))
	_challenge_status.text = ""
	_challenge_status.visible = false
	_challenge_creator_label.text = tr("Created by %s") % str(definition.get("creator_name", ""))
	_challenge_creator_label.visible = true
	_challenge_difficulty_label.text = tr("Difficulty: %s") % _challenge_difficulty_name(ruleset)
	_challenge_difficulty_label.visible = true
	_challenge_hazards_label.text = tr("Hazards") + "  ·  " + ", ".join(hazard_names)
	_challenge_hazards_label.visible = true
	_challenge_score_status.text = tr("Loading challenge records...")
	_challenge_score_status.visible = true
	ChallengeService.fetch_current_scores()

func _challenge_difficulty_name(ruleset: Dictionary) -> String:
	var density := float(ruleset.get("event_density", 1.0))
	var size := float(ruleset.get("hazard_size", 1.0))
	var alternation := float(ruleset.get("lane_alternation", 0.0))
	var margin := float(ruleset.get("reaction_margin", 1.0))
	if is_equal_approx(density, 0.85) and is_equal_approx(size, 0.9) and is_equal_approx(alternation, 0.15) and is_equal_approx(margin, 1.25):
		return tr("Easy")
	if is_equal_approx(density, 1.0) and is_equal_approx(size, 1.0) and is_equal_approx(alternation, 0.25) and is_equal_approx(margin, 1.0):
		return tr("Normal")
	if is_equal_approx(density, 1.35) and is_equal_approx(size, 1.15) and is_equal_approx(alternation, 0.6) and is_equal_approx(margin, 0.7):
		return tr("Hard")
	return tr("Custom")

func _on_challenge_leaderboard_received(version: int, seed: int, rows: Array, error_message: String) -> void:
	if _menu_view != "challenge" or not is_instance_valid(_challenge_score_rows):
		return
	for child in _challenge_score_rows.get_children():
		child.queue_free()
	if not error_message.is_empty():
		_challenge_score_status.text = tr("Challenge records unavailable.")
		_challenge_score_status.visible = true
		return
	if rows.is_empty():
		_challenge_score_status.text = tr("No results yet — set the first record!")
		_challenge_score_status.visible = true
		return
	_challenge_score_status.text = ""
	_challenge_score_status.visible = false
	for index in range(mini(rows.size(), 5)):
		var row: Variant = rows[index]
		if not row is Dictionary:
			continue
		var record := Label.new()
		record.text = "%d. %s  ·  %d m" % [index + 1, str(row.get("player_name", "")), int(row.get("best_distance_m", 0))]
		record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		record.add_theme_font_size_override("font_size", 14)
		record.add_theme_color_override("font_color", Color("edf3ff"))
		_challenge_score_rows.add_child(record)

func _show_saved_challenges_menu() -> void:
	_menu_view = "saved_challenges"
	_clear_menu_panel()
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(520.0, maxf(viewport_size.x - 32.0, 280.0))
	var panel_height := minf(520.0, maxf(viewport_size.y - 32.0, 300.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	menu_panel.add_child(layout)
	var title := Label.new()
	title.text = tr("MY CHALLENGES")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	_saved_challenge_status = Label.new()
	_saved_challenge_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved_challenge_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saved_challenge_status.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_saved_challenge_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_saved_challenge_rows = VBoxContainer.new()
	_saved_challenge_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_saved_challenge_rows)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_challenge_options)
	layout.add_child(back_button)
	_saved_challenge_status.text = tr("Loading your challenges...") if AuthService.is_authenticated else tr("Challenges are saved on this device.")
	ChallengeService.fetch_challenge_library()

func _on_challenge_library_received(entries: Array, error_message: String) -> void:
	if _menu_view != "saved_challenges" or not is_instance_valid(_saved_challenge_rows):
		return
	for child in _saved_challenge_rows.get_children():
		child.queue_free()
	if entries.is_empty():
		_saved_challenge_status.text = tr("No saved challenges yet.") if error_message.is_empty() else tr("Could not sync your challenge list. Showing challenges saved on this device.")
		return
	_saved_challenge_status.text = tr("Challenge list could not sync; showing this device's saved challenges.") if not error_message.is_empty() else ""
	for entry in entries:
		if not entry is Dictionary:
			continue
		var challenge_code := str(entry.get("challenge_code", ""))
		var challenge_name := str(entry.get("challenge_name", challenge_code))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_saved_challenge_rows.add_child(row)
		var open_button := _make_button("%s\n%s · %s" % [challenge_name, tr("By %s") % str(entry.get("creator_name", "")), challenge_code])
		open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_button.custom_minimum_size.y = 64.0
		open_button.add_theme_font_size_override("font_size", 15)
		open_button.pressed.connect(_open_saved_challenge.bind(challenge_code))
		row.add_child(open_button)
		var remove_button := Button.new()
		remove_button.text = "×"
		remove_button.tooltip_text = tr("Remove from my list")
		remove_button.custom_minimum_size = Vector2(48.0, 48.0)
		remove_button.pressed.connect(_remove_saved_challenge.bind(challenge_code))
		row.add_child(remove_button)

func _open_saved_challenge(challenge_code: String) -> void:
	_show_challenge_menu(challenge_code)
	if not ChallengeService.load_challenge_code(challenge_code):
		_challenge_status.text = tr(ChallengeService.last_error)
		_challenge_status.visible = true
		return
	if challenge_code.begins_with("GC-"):
		_challenge_status.text = tr("Loading challenge...")
		_challenge_status.visible = true
		_challenge_join_button.disabled = true
	else:
		_challenge_preview_ready = true
		_challenge_join_button.text = tr("Start challenge")
		ChallengeService.fetch_current_scores()

func _remove_saved_challenge(challenge_code: String) -> void:
	ChallengeService.remove_challenge_from_library(challenge_code)
	_on_challenge_library_received(PlayerProfile.get_saved_seed_challenges(), "")

func _show_create_challenge_menu() -> void:
	_menu_view = "create_challenge"
	_clear_menu_panel()
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(560.0, maxf(viewport_size.x - 32.0, 300.0))
	var panel_height := minf(700.0, maxf(viewport_size.y - 24.0, 360.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_panel.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)
	var title := Label.new()
	title.text = tr("CREATE CHALLENGE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(title)
	var description := Label.new()
	description.text = tr("Choose a difficulty and the hazards for a fixed, shareable course.")
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(description)
	var challenge_title_label := Label.new()
	challenge_title_label.text = tr("Challenge name")
	layout.add_child(challenge_title_label)
	_create_challenge_title = LineEdit.new()
	_create_challenge_title.max_length = 40
	_create_challenge_title.placeholder_text = tr("Give your challenge a name")
	layout.add_child(_create_challenge_title)
	var difficulty_label := Label.new()
	difficulty_label.text = tr("Difficulty")
	layout.add_child(difficulty_label)
	_create_challenge_difficulty = OptionButton.new()
	for difficulty_name in [tr("Easy"), tr("Normal"), tr("Hard")]:
		_create_challenge_difficulty.add_item(difficulty_name)
	_create_challenge_difficulty.select(1)
	layout.add_child(_create_challenge_difficulty)
	var hazards_label := Label.new()
	hazards_label.text = tr("Included hazards")
	layout.add_child(hazards_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	layout.add_child(grid)
	_create_challenge_profiles.clear()
	var catalog_generator := COURSE_GENERATOR_SCRIPT.new() as CourseGenerator
	for profile in catalog_generator.get_profile_catalog(CourseGenerator.GENERATOR_VERSION):
		var checkbox := CheckBox.new()
		checkbox.text = _friendly_hazard_name(String(profile.profile_id))
		checkbox.button_pressed = true
		checkbox.set_meta("profile_id", String(profile.profile_id))
		_create_challenge_profiles.append(checkbox)
		grid.add_child(checkbox)
	var name_label := Label.new()
	name_label.text = tr("Challenge creator nickname")
	layout.add_child(name_label)
	_create_challenge_name = LineEdit.new()
	_create_challenge_name.max_length = 16
	_create_challenge_name.placeholder_text = tr("Nickname")
	_create_challenge_name.text = PlayerAccountProfile.nickname if PlayerAccountProfile.has_profile else PlayerProfile.leaderboard_name
	_create_challenge_name.editable = not PlayerAccountProfile.has_profile
	layout.add_child(_create_challenge_name)
	_create_challenge_status = Label.new()
	_create_challenge_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_create_challenge_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_create_challenge_status.add_theme_color_override("font_color", Color("ffbd5c"))
	layout.add_child(_create_challenge_status)
	_create_challenge_button = _make_button(tr("Create and start"))
	_create_challenge_button.pressed.connect(_create_selected_challenge)
	layout.add_child(_create_challenge_button)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	layout.add_child(back_button)

func _create_selected_challenge() -> void:
	if not is_instance_valid(_create_challenge_name) or not is_instance_valid(_create_challenge_title) or not is_instance_valid(_create_challenge_button):
		return
	var creator_name := _create_challenge_name.text.strip_edges()
	var challenge_title := _create_challenge_title.text.strip_edges()
	if not _is_valid_challenge_nickname(creator_name):
		_create_challenge_status.text = tr("Use a nickname with 3–16 letters, numbers or underscores.")
		_create_challenge_name.grab_focus()
		return
	if challenge_title.length() < 1 or challenge_title.length() > 40:
		_create_challenge_status.text = tr("Choose a challenge name with 1–40 characters.")
		_create_challenge_title.grab_focus()
		return
	var selected_ids := PackedStringArray()
	for checkbox in _create_challenge_profiles:
		if checkbox.button_pressed:
			selected_ids.append(str(checkbox.get_meta("profile_id")))
	if selected_ids.is_empty():
		_create_challenge_status.text = tr("Select at least one hazard.")
		return
	var ruleset := COURSE_RULESET_SCRIPT.new() as Resource
	ruleset.set("ruleset_id", &"community_challenge")
	ruleset.set("revision", 1)
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", selected_ids)
	match _create_challenge_difficulty.selected:
		0:
			ruleset.set("event_density", 0.85)
			ruleset.set("hazard_size", 0.9)
			ruleset.set("lane_alternation", 0.15)
			ruleset.set("reaction_margin", 1.25)
		1:
			ruleset.set("event_density", 1.0)
			ruleset.set("hazard_size", 1.0)
			ruleset.set("lane_alternation", 0.25)
			ruleset.set("reaction_margin", 1.0)
		2:
			ruleset.set("event_density", 1.35)
			ruleset.set("hazard_size", 1.15)
			ruleset.set("lane_alternation", 0.6)
			ruleset.set("reaction_margin", 0.7)
	if is_instance_valid(_create_challenge_button):
		_create_challenge_button.disabled = true
	_create_challenge_status.text = tr("Creating challenge...")
	ChallengeService.clear_challenge()
	ChallengeService.begin_run()
	ChallengeService.ruleset = ruleset
	ChallengeService.create_challenge_for_current_run(creator_name, ruleset, challenge_title)
	PlayerProfile.set_leaderboard_name(creator_name)

func _on_menu_challenge_created(success: bool, _challenge_code: String, error_message: String) -> void:
	if _menu_view != "create_challenge":
		return
	if not success:
		_create_challenge_status.text = tr(error_message)
		if is_instance_valid(_create_challenge_button):
			_create_challenge_button.disabled = false
		return
	get_tree().change_scene_to_packed(GAME_SCENE)

func _is_valid_challenge_nickname(nickname: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_]{3,16}$")
	return pattern.search(nickname) != null

func _friendly_hazard_name(profile_id: String) -> String:
	var key := "Hazard: %s" % profile_id
	var translated := tr(key)
	return profile_id.capitalize().replace("_", " ") if translated == key else translated

func _show_account_menu() -> void:
	_menu_view = "account"
	_clear_menu_panel()
	_account_email = null
	_account_password = null
	_account_nickname = null
	_nickname_save_button = null
	var panel_layout := _create_account_panel(390.0)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel_layout.add_child(layout)
	_add_account_title(layout, tr("ACCOUNT"))
	_account_status = Label.new()
	_account_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account_status.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_account_status)
	if AuthService.is_authenticated:
		_account_status.text = tr("Signed in as %s.") % AuthService.email
		_account_progress_label = Label.new()
		_account_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_account_progress_label.add_theme_color_override("font_color", Color("42d6c5"))
		layout.add_child(_account_progress_label)
		_on_account_progress_changed(AccountProgress.wallet_coins, AccountProgress.total_distance_m, AccountProgress.best_distance_m)
		var nickname_label := Label.new()
		nickname_label.text = tr("Public nickname (3–16 characters)")
		nickname_label.add_theme_color_override("font_color", Color("b8c7dc"))
		layout.add_child(nickname_label)
		_account_nickname = LineEdit.new()
		_account_nickname.placeholder_text = tr("Nickname")
		_account_nickname.max_length = 16
		_account_nickname.text = PlayerAccountProfile.nickname
		layout.add_child(_account_nickname)
		_nickname_save_button = _make_button(tr("Save nickname"))
		_nickname_save_button.pressed.connect(_save_nickname)
		layout.add_child(_nickname_save_button)
		var sign_out_button := _make_button(tr("Sign Out"))
		sign_out_button.pressed.connect(AuthService.sign_out)
		panel_layout.add_child(sign_out_button)
	else:
		_account_status.text = ""
		var google_button := _make_button(tr("Continue with Google"))
		google_button.pressed.connect(_start_google_sign_in)
		layout.add_child(google_button)
		var email_button := _make_button(tr("Continue with email"))
		email_button.pressed.connect(_show_email_auth_menu)
		layout.add_child(email_button)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	panel_layout.add_child(back_button)
	if is_instance_valid(_account_nickname):
		_account_nickname.grab_focus()

func _show_email_auth_menu() -> void:
	_menu_view = "email_auth"
	_clear_menu_panel()
	var panel_layout := _create_account_panel(450.0)
	_add_account_title(panel_layout, tr("Email account"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	panel_layout.add_child(mode_row)
	var sign_in_mode := _make_button(_mode_button_text("sign_in", tr("Sign In")))
	sign_in_mode.pressed.connect(_set_email_auth_mode.bind("sign_in"))
	mode_row.add_child(sign_in_mode)
	var sign_up_mode := _make_button(_mode_button_text("sign_up", tr("Create Account")))
	sign_up_mode.pressed.connect(_set_email_auth_mode.bind("sign_up"))
	mode_row.add_child(sign_up_mode)
	_account_scroll = ScrollContainer.new()
	_account_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_account_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_account_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_layout.add_child(_account_scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 10)
	_account_scroll.add_child(form)
	_account_email = LineEdit.new()
	_account_email.placeholder_text = tr("Email address")
	_account_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_account_email.max_length = 254
	_account_email.focus_entered.connect(_keep_account_input_visible)
	form.add_child(_account_email)
	_account_password = LineEdit.new()
	_account_password.placeholder_text = tr("Password (at least 8 characters)")
	_account_password.secret = true
	_account_password.max_length = 128
	_account_password.focus_entered.connect(_keep_account_input_visible)
	form.add_child(_account_password)
	_account_status = Label.new()
	_account_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account_status.add_theme_color_override("font_color", Color("b8c7dc"))
	form.add_child(_account_status)
	var submit_button := _make_button(tr("Sign In") if _email_auth_mode == "sign_in" else tr("Create Account"))
	submit_button.pressed.connect(_submit_account_action.bind(_email_auth_mode))
	form.add_child(submit_button)
	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_account_menu)
	panel_layout.add_child(back_button)
	_account_email.grab_focus()

func _create_account_panel(max_height: float) -> VBoxContainer:
	_account_scroll = null
	var view_size := get_viewport_rect().size
	var panel_width := minf(440.0, maxf(view_size.x - 32.0, 280.0))
	var panel_height := minf(max_height, maxf(view_size.y - 32.0, 300.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)
	var panel_layout := VBoxContainer.new()
	panel_layout.add_theme_constant_override("separation", 10)
	menu_panel.add_child(panel_layout)
	return panel_layout

func _add_account_title(parent: Container, title_text: String) -> Label:
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	parent.add_child(title)
	return title

func _mode_button_text(mode: String, label: String) -> String:
	return ("›  " if _email_auth_mode == mode else "") + label

func _set_email_auth_mode(mode: String) -> void:
	if _email_auth_mode == mode:
		return
	var email_value := _account_email.text if is_instance_valid(_account_email) else ""
	_email_auth_mode = mode
	_show_email_auth_menu()
	_account_email.text = email_value

func _submit_account_action(action: String) -> void:
	var account_email := _account_email.text.strip_edges()
	var password := _account_password.text
	if account_email.is_empty() or not account_email.contains("@"):
		_account_status.text = tr("Enter a valid email address.")
		return
	if password.length() < 8:
		_account_status.text = tr("Choose a stronger password (at least 8 characters).")
		return
	_account_status.text = tr("Working...")
	_account_password.clear()
	if action == "sign_in":
		_return_to_main_after_profile_load = true
		AuthService.sign_in(account_email, password)
	else:
		AuthService.create_account(account_email, password)

func _start_google_sign_in() -> void:
	_return_to_main_after_profile_load = true
	AuthService.sign_in_with_google()

func _keep_account_input_visible() -> void:
	call_deferred("_scroll_to_focused_account_input")

func _scroll_to_focused_account_input() -> void:
	if not is_instance_valid(_account_scroll):
		return
	if is_instance_valid(_account_email) and _account_email.has_focus():
		_account_scroll.ensure_control_visible(_account_email)
	elif is_instance_valid(_account_password) and _account_password.has_focus():
		_account_scroll.ensure_control_visible(_account_password)

func _on_auth_state_changed(_authenticated: bool, _email: String) -> void:
	if _menu_view in ["account", "email_auth"]:
		_show_account_menu()
	elif _menu_view == "main":
		_show_main_menu()

func _on_auth_action_finished(action: String, success: bool, message: String) -> void:
	if action in ["sign_in", "google_sign_in"] and not success:
		_return_to_main_after_profile_load = false
	if _menu_view not in ["account", "email_auth"] or not is_instance_valid(_account_status):
		return
	if action == "sign_out":
		_account_status.text = tr("Signed out.") if success else tr("Signed out on this device.")
	else:
		_account_status.text = message if not message.is_empty() else (tr("Signed in successfully.") if success else tr("Sign-in failed. Please try again."))

func _save_nickname() -> void:
	if not is_instance_valid(_account_nickname):
		return
	if is_instance_valid(_account_status):
		_account_status.text = tr("Saving nickname...")
	if is_instance_valid(_nickname_save_button):
		_nickname_save_button.disabled = true
	PlayerAccountProfile.save_nickname(_account_nickname.text)

func _on_account_profile_changed(_nickname: String, _has_profile: bool) -> void:
	if _menu_view == "account" and AuthService.is_authenticated:
		_show_account_menu()

func _on_account_progress_changed(wallet_coins: int, total_distance_m: int, _best_distance_m: int) -> void:
	if is_instance_valid(_account_progress_label):
		_account_progress_label.text = tr("Wallet: %d coins · Total distance: %d m") % [wallet_coins, total_distance_m]

func _on_account_profile_action_finished(action: String, success: bool, message: String) -> void:
	if _menu_view not in ["account", "email_auth"] or not is_instance_valid(_account_status):
		return
	if action == "load_profile" and _return_to_main_after_profile_load:
		_return_to_main_after_profile_load = false
		if success and PlayerAccountProfile.has_profile:
			_show_main_menu()
		elif not success:
			_account_status.text = message
		return
	if action == "save_nickname":
		_account_status.text = message
		if is_instance_valid(_nickname_save_button):
			_nickname_save_button.disabled = false

func _show_leaderboard_menu() -> void:
	_menu_view = "leaderboard"
	_clear_menu_panel()
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(520.0, maxf(viewport_size.x - 32.0, 280.0))
	var panel_height := minf(500.0, maxf(viewport_size.y - 32.0, 300.0))
	menu_panel = PanelContainer.new()
	menu_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -panel_width * 0.5
	menu_panel.offset_right = panel_width * 0.5
	menu_panel.offset_top = -panel_height * 0.5
	menu_panel.offset_bottom = panel_height * 0.5
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	menu_panel.add_child(layout)

	_leaderboard_mode = "best_run"
	_leaderboard_title = Label.new()
	_leaderboard_title.text = tr("LEADERBOARD — TOP 20")
	_leaderboard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_title.add_theme_font_size_override("font_size", 30)
	_leaderboard_title.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(_leaderboard_title)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	layout.add_child(mode_row)
	var best_button := _make_button(tr("Single runs"))
	best_button.pressed.connect(_select_leaderboard_mode.bind("best_run"))
	mode_row.add_child(best_button)
	var total_button := _make_button(tr("Total distance"))
	total_button.pressed.connect(_select_leaderboard_mode.bind("total_distance"))
	mode_row.add_child(total_button)
	var monthly_button := _make_button(tr("This month"))
	monthly_button.pressed.connect(_select_leaderboard_mode.bind("monthly_distance"))
	mode_row.add_child(monthly_button)

	_leaderboard_subtitle = Label.new()
	_leaderboard_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_subtitle.add_theme_font_size_override("font_size", 14)
	_leaderboard_subtitle.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_leaderboard_subtitle)

	_leaderboard_status = Label.new()
	_leaderboard_status.text = tr("Loading leaderboard...")
	_leaderboard_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leaderboard_status.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_leaderboard_status)

	var scroll := ScrollContainer.new()
	# Keep the heading and Back button visible; only the leaderboard rows should scroll.
	scroll.custom_minimum_size = Vector2(0.0, minf(330.0, maxf(panel_height - 280.0, 100.0)))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_leaderboard_rows = VBoxContainer.new()
	_leaderboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_leaderboard_rows)

	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	layout.add_child(back_button)
	back_button.grab_focus()
	_select_leaderboard_mode("best_run")

func _select_leaderboard_mode(mode: String) -> void:
	_leaderboard_mode = mode
	if not is_instance_valid(_leaderboard_title) or not is_instance_valid(_leaderboard_subtitle) or not is_instance_valid(_leaderboard_status):
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	_leaderboard_status.text = tr("Loading leaderboard...")
	if mode == "total_distance":
		_leaderboard_title.text = tr("TOTAL DISTANCE — TOP 20")
		_leaderboard_subtitle.text = tr("One entry per account, ranked by lifetime distance.")
		AccountProgress.fetch_total_distance_leaderboard()
	elif mode == "monthly_distance":
		_leaderboard_title.text = tr("THIS MONTH — TOP 20")
		_leaderboard_subtitle.text = tr("One entry per account, ranked by distance this calendar month.")
		AccountProgress.fetch_monthly_distance_leaderboard()
	else:
		_leaderboard_title.text = tr("LEADERBOARD — TOP 20")
		_leaderboard_subtitle.text = tr("Runs are ranked by distance. Coins are shown separately.")
		Leaderboard.fetch_top_runs()

func _on_top_runs_received(runs: Array, error_message: String) -> void:
	if _leaderboard_mode != "best_run" or not is_instance_valid(_leaderboard_rows) or not is_instance_valid(_leaderboard_status):
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	if not error_message.is_empty():
		_leaderboard_status.text = error_message
		return
	if runs.is_empty():
		_leaderboard_status.text = tr("The leaderboard is empty for now.")
		return
	_leaderboard_status.text = ""
	for index in range(runs.size()):
		var run: Dictionary = runs[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_leaderboard_rows.add_child(row)

		var rank := Label.new()
		rank.text = "%02d." % (index + 1)
		rank.custom_minimum_size.x = 42.0
		row.add_child(rank)

		var player_name := Label.new()
		player_name.text = str(run.get("player_name", "???"))
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.clip_text = true
		row.add_child(player_name)

		var distance := Label.new()
		distance.text = tr("%d m") % int(run.get("distance_m", 0))
		distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		distance.custom_minimum_size.x = 78.0
		row.add_child(distance)

		var coins := Label.new()
		coins.text = tr("%d coins") % int(run.get("coins", 0))
		coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		coins.custom_minimum_size.x = 86.0
		row.add_child(coins)

func _on_total_distance_leaderboard_received(rows: Array, error_message: String) -> void:
	if _leaderboard_mode != "total_distance" or not is_instance_valid(_leaderboard_rows) or not is_instance_valid(_leaderboard_status):
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	if not error_message.is_empty():
		_leaderboard_status.text = error_message
		return
	if rows.is_empty():
		_leaderboard_status.text = tr("No account runs yet.")
		return
	_leaderboard_status.text = ""
	for index in range(rows.size()):
		var entry: Dictionary = rows[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_leaderboard_rows.add_child(row)
		var rank := Label.new()
		rank.text = "%02d." % (index + 1)
		rank.custom_minimum_size.x = 42.0
		row.add_child(rank)
		var player_name := Label.new()
		player_name.text = str(entry.get("player_name", "???"))
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.clip_text = true
		row.add_child(player_name)
		_add_leaderboard_distance(row, int(entry.get("total_distance_m", 0)))

func _on_monthly_distance_leaderboard_received(rows: Array, error_message: String) -> void:
	if _leaderboard_mode != "monthly_distance" or not is_instance_valid(_leaderboard_rows) or not is_instance_valid(_leaderboard_status):
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	if not error_message.is_empty():
		_leaderboard_status.text = error_message
		return
	if rows.is_empty():
		_leaderboard_status.text = tr("No account runs this month yet.")
		return
	_leaderboard_status.text = ""
	for index in range(rows.size()):
		var entry: Dictionary = rows[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_leaderboard_rows.add_child(row)
		var rank := Label.new()
		rank.text = "%02d." % (index + 1)
		rank.custom_minimum_size.x = 42.0
		row.add_child(rank)
		var player_name := Label.new()
		player_name.text = str(entry.get("player_name", "???"))
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.clip_text = true
		row.add_child(player_name)
		_add_leaderboard_distance(row, int(entry.get("monthly_distance_m", 0)))

func _add_leaderboard_distance(row: HBoxContainer, distance_m: int) -> void:
	var distance := Label.new()
	distance.text = tr("%d m") % distance_m
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance.custom_minimum_size.x = 100.0
	row.add_child(distance)

func _show_options_menu() -> void:
	_menu_view = "options"
	_clear_menu_panel()
	menu_panel = PanelContainer.new()
	# Leave enough room for the heading, device-specific choices, and Back.
	# The previous 330 px minimum let the VBox overflow on some web canvas scales.
	menu_panel.custom_minimum_size = Vector2(380.0, 410.0)
	menu_panel.anchor_left = 1.0
	menu_panel.anchor_right = 1.0
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -404.0
	menu_panel.offset_right = -24.0
	menu_panel.offset_top = -205.0
	menu_panel.offset_bottom = 205.0
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	menu_panel.add_child(layout)
	var title := Label.new()
	title.text = tr("OPTIONS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	layout.add_child(title)
	var is_touch_device := DisplayServer.is_touchscreen_available()
	var hint := Label.new()
	hint.text = tr("Mobile gravity control") if is_touch_device else tr("Desktop gravity control")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(hint)
	# Build this typed array explicitly. A conditional expression returning an
	# untyped Array can fail its Array[Dictionary] assignment in exported builds;
	# that would leave the Options panel showing only its heading and hint.
	var control_options: Array[Dictionary] = []
	if is_touch_device:
		control_options.append({"mode": "swipe", "label": tr("Swipe up / down")})
		control_options.append({"mode": "tap", "label": tr("Tap screen to flip")})
	else:
		control_options.append({"mode": "keyboard", "label": tr("Swap with W / S")})
		control_options.append({"mode": "mouse", "label": tr("Swap with mouse click")})
	var first_control_button: Button
	for option in control_options:
		var mode := str(option["mode"])
		var control_button := _make_button(_control_label(mode, str(option["label"])))
		control_button.pressed.connect(_select_control.bind(mode))
		layout.add_child(control_button)
		if first_control_button == null:
			first_control_button = control_button
	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 8)
	language_row.alignment = BoxContainer.ALIGNMENT_CENTER
	language_row.add_child(_make_language_button("‹", -1))
	var language_label := Label.new()
	language_label.text = "Svenska" if PlayerProfile.language == "sv" else "English"
	language_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	language_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	language_label.custom_minimum_size.x = 130.0
	language_row.add_child(language_label)
	language_row.add_child(_make_language_button("›", 1))
	layout.add_child(language_row)

	var back_button := _make_button(tr("Back"))
	back_button.pressed.connect(_show_main_menu)
	layout.add_child(back_button)
	if is_instance_valid(first_control_button):
		first_control_button.grab_focus()

func _make_language_button(symbol: String, direction: int) -> Button:
	var button := _make_button(symbol)
	button.custom_minimum_size = Vector2(54.0, 48.0)
	button.pressed.connect(_cycle_language.bind(direction))
	return button

func _cycle_language(direction: int) -> void:
	var next_language := "en" if PlayerProfile.language == "sv" else "sv"
	PlayerProfile.set_language(next_language)
	_show_options_menu()

func _control_label(mode: String, label: String) -> String:
	return ("[x]  " if PlayerProfile.flip_control == mode else "") + label

func _select_control(mode: String) -> void:
	PlayerProfile.set_flip_control(mode)
	_show_options_menu()

func _clear_menu_panel() -> void:
	if is_instance_valid(menu_panel):
		menu_panel.queue_free()
	_close_achievement_group_overlay()
	_achievement_group_overlay_id = ""

func _start_new_game() -> void:
	ChallengeService.clear_challenge()
	get_tree().change_scene_to_packed(GAME_SCENE)

func _quit_game() -> void:
	if OS.has_feature("web"):
		var dialog := AcceptDialog.new()
		dialog.title = tr("Thanks for playing!")
		dialog.dialog_text = tr("You can close this browser tab.")
		dialog.ok_button_text = tr("Back to game")
		dialog.confirmed.connect(dialog.queue_free)
		dialog.close_requested.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered(Vector2i(380, 160))
		return
	get_tree().quit()

func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 20)
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.105, 0.17, 0.82)
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	return style
