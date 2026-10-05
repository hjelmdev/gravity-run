extends CanvasLayer

const COPY_ICON_SCRIPT := preload("res://ui/copy_icon.gd")
const GameIconScript := preload("res://ui/game_icon.gd")

var _diagnostic_save_button: Button
var _distance_m := 0
var _coins := 0
var _name_edit: LineEdit
var _mobile_name_button: Button
var _name_label: Label
var _privacy_note: Label
var _score_label: Label
var _account_save_label: Label
var _status_label: Label
var _submit_button: Button
var _scroll: ScrollContainer
var _panel: PanelContainer
var _challenge_code_label: Label
var _challenge_code_title: Label
var _challenge_link_title: Label
var _challenge_code_edit: LineEdit
var _challenge_code_row: HBoxContainer
var _challenge_short_code_edit: LineEdit
var _challenge_short_code_row: HBoxContainer
var _share_challenge_button: Button
var _challenge_share_status: Label
var _achievement_section: VBoxContainer
var _achievement_title: Label
var _achievement_description: Label
var _achievement_counter: Label
var _achievement_category_icon: Control
var _achievement_previous: Button
var _achievement_next: Button
var _run_achievements: Array[Dictionary] = []
var _achievement_index := 0
var _shown_run_id := ""

func _ready() -> void:
	MobileTextEntry.entry_submitted.connect(_on_mobile_text_submitted)
	_build_ui()
	Leaderboard.submission_finished.connect(_on_submission_finished)
	ChallengeService.score_submission_finished.connect(_on_seed_score_submission_finished)
	ChallengeService.challenge_created.connect(_on_challenge_created)
	PlayerAccountProfile.profile_changed.connect(_on_account_profile_changed)
	AccountProgress.run_saved.connect(_on_account_run_saved)
	AccountProgress.run_loot_resolved.connect(_on_run_loot_resolved)
	AchievementService.run_unlocks_changed.connect(_on_run_achievements_changed)

func show_result(raw_distance: float, coins: int, challenge_code: String = "", is_challenge_run: bool = false, run_id: String = "") -> void:
	_diagnostic_save_button.visible = bool(get_parent().get("render_diagnostics_enabled"))
	_shown_run_id = run_id
	_distance_m = int(raw_distance / 10.0)
	_coins = coins
	_score_label.text = tr("Distance: %d m     Coins: %02d") % [_distance_m, _coins]
	_challenge_code_label.visible = is_challenge_run
	_challenge_code_title.visible = is_challenge_run
	_challenge_link_title.visible = is_challenge_run
	_challenge_code_row.visible = is_challenge_run
	_challenge_short_code_row.visible = is_challenge_run
	_share_challenge_button.visible = not is_challenge_run
	_share_challenge_button.text = tr("Save score to this seed") if is_challenge_run else tr("Share this run as a challenge")
	_challenge_code_edit.text = ChallengeService.get_challenge_link(challenge_code)
	_challenge_short_code_edit.text = challenge_code if not challenge_code.is_empty() else ChallengeService.get_challenge_code()
	_challenge_share_status.text = ""
	_share_challenge_button.disabled = false
	_name_edit.text = _preferred_leaderboard_name()
	_update_name_identity_ui()
	if is_challenge_run:
		_privacy_note.text = tr("Your nickname and result on this seed will be public.")
	_account_save_label.text = tr("Saving run to your account...") if AuthService.is_authenticated else tr("Sign in to save coins and total distance.")
	_run_achievements = AchievementService.get_recent_run_unlocks()
	_achievement_index = 0
	_update_achievement_carousel()
	_status_label.text = tr("Enter a name to submit your run to the leaderboard.")
	_submit_button.disabled = false
	visible = true
	_name_edit.release_focus()
	if is_challenge_run:
		var challenge_player_name := _preferred_leaderboard_name().strip_edges()
		if _is_public_nickname(challenge_player_name):
			PlayerProfile.set_leaderboard_name(challenge_player_name)
			_challenge_share_status.text = tr("Saving your public seed result...")
			ChallengeService.submit_current_run(challenge_player_name, _distance_m)
		else:
			_share_challenge_button.visible = true
			_challenge_share_status.text = tr("Enter a nickname to save your result to this seed.")

func _build_ui() -> void:
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.02, 0.04, 0.08, 0.78)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	_scroll = ScrollContainer.new()
	_scroll.name = "ResponsiveScroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	var root := MarginContainer.new()
	root.name = "Overlay"
	root.add_theme_constant_override("margin_left", 20)
	root.add_theme_constant_override("margin_top", 20)
	root.add_theme_constant_override("margin_right", 20)
	root.add_theme_constant_override("margin_bottom", 20)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll.add_child(root)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)
	_fit_panel_width()

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_panel.add_child(layout)

	var title := Label.new()
	title.text = tr("RUN OVER")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("ff647c"))
	layout.add_child(title)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 21)
	_score_label.add_theme_color_override("font_color", Color("edf3ff"))
	layout.add_child(_score_label)

	_challenge_code_label = Label.new()
	_challenge_code_label.text = tr("Share the code or link so a friend can open the challenge.")
	_challenge_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_code_label.add_theme_color_override("font_color", Color("42d6c5"))
	_challenge_code_label.visible = false
	layout.add_child(_challenge_code_label)
	_share_challenge_button = _make_button(tr("Share this run as a challenge"))
	_share_challenge_button.pressed.connect(_share_run_challenge)
	layout.add_child(_share_challenge_button)
	_challenge_code_title = Label.new()
	_challenge_code_title.text = tr("Challenge code")
	_challenge_code_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_code_title.visible = false
	layout.add_child(_challenge_code_title)
	_challenge_short_code_row = HBoxContainer.new()
	_challenge_short_code_row.add_theme_constant_override("separation", 8)
	_challenge_short_code_row.visible = false
	layout.add_child(_challenge_short_code_row)
	_challenge_short_code_edit = LineEdit.new()
	_challenge_short_code_edit.editable = false
	_challenge_short_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_short_code_edit.custom_minimum_size.y = 42.0
	_challenge_short_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_short_code_row.add_child(_challenge_short_code_edit)
	_challenge_short_code_row.add_child(_make_copy_icon_button(tr("Copy challenge code"), _copy_challenge_code))
	_challenge_link_title = Label.new()
	_challenge_link_title.text = tr("Challenge link")
	_challenge_link_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_link_title.visible = false
	layout.add_child(_challenge_link_title)
	_challenge_code_row = HBoxContainer.new()
	_challenge_code_row.add_theme_constant_override("separation", 8)
	_challenge_code_row.visible = false
	layout.add_child(_challenge_code_row)
	_challenge_code_edit = LineEdit.new()
	_challenge_code_edit.editable = false
	_challenge_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_code_edit.custom_minimum_size.y = 42.0
	_challenge_code_edit.add_theme_font_size_override("font_size", 12)
	_challenge_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_code_row.add_child(_challenge_code_edit)
	_challenge_code_row.add_child(_make_copy_icon_button(tr("Copy challenge link"), _copy_challenge_link))
	_challenge_share_status = Label.new()
	_challenge_share_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_share_status.add_theme_color_override("font_color", Color("42d6c5"))
	layout.add_child(_challenge_share_status)

	_account_save_label = Label.new()
	_account_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_account_save_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account_save_label.add_theme_color_override("font_color", Color("42d6c5"))
	layout.add_child(_account_save_label)

	_achievement_section = VBoxContainer.new()
	_achievement_section.add_theme_constant_override("separation", 5)
	_achievement_section.visible = false
	layout.add_child(_achievement_section)
	var achievement_heading := Label.new()
	achievement_heading.text = tr("UNLOCKED THIS RUN")
	achievement_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	achievement_heading.add_theme_color_override("font_color", Color("42d6c5"))
	_achievement_section.add_child(achievement_heading)
	var achievement_row := HBoxContainer.new()
	achievement_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_achievement_section.add_child(achievement_row)
	_achievement_previous = _make_button("‹")
	_achievement_previous.custom_minimum_size = Vector2(44, 42)
	_achievement_previous.pressed.connect(func() -> void: _change_achievement(-1))
	achievement_row.add_child(_achievement_previous)
	var achievement_card := PanelContainer.new()
	achievement_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievement_card.add_theme_stylebox_override("panel", _achievement_card_style())
	achievement_row.add_child(achievement_card)
	var achievement_card_row := HBoxContainer.new()
	achievement_card_row.add_theme_constant_override("separation", 10)
	achievement_card.add_child(achievement_card_row)
	var badge: Control = GameIconScript.new()
	badge.icon_family = "achievement_status"
	badge.unlocked = true
	badge.custom_minimum_size = Vector2(42, 42)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_card_row.add_child(badge)
	_achievement_category_icon = GameIconScript.new()
	_achievement_category_icon.icon_family = "achievement_category"
	_achievement_category_icon.custom_minimum_size = Vector2(26, 26)
	_achievement_category_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_card_row.add_child(_achievement_category_icon)
	var achievement_text := VBoxContainer.new()
	achievement_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievement_card_row.add_child(achievement_text)
	_achievement_title = Label.new()
	_achievement_title.add_theme_color_override("font_color", Color("edf3ff"))
	achievement_text.add_child(_achievement_title)
	_achievement_description = Label.new()
	_achievement_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_achievement_description.add_theme_font_size_override("font_size", 12)
	_achievement_description.add_theme_color_override("font_color", Color("b8c7dc"))
	achievement_text.add_child(_achievement_description)
	_achievement_next = _make_button("›")
	_achievement_next.custom_minimum_size = Vector2(44, 42)
	_achievement_next.pressed.connect(func() -> void: _change_achievement(1))
	achievement_row.add_child(_achievement_next)
	_achievement_counter = Label.new()
	_achievement_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_achievement_counter.add_theme_font_size_override("font_size", 11)
	_achievement_counter.add_theme_color_override("font_color", Color("b8c7dc"))
	_achievement_section.add_child(_achievement_counter)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_name_label)

	_privacy_note = Label.new()
	_privacy_note.add_theme_font_size_override("font_size", 13)
	_privacy_note.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_privacy_note)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Your name")
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size.y = 44.0
	_name_edit.text = _preferred_leaderboard_name()
	_name_edit.focus_entered.connect(_ensure_name_visible)
	layout.add_child(_name_edit)
	if MobileTextEntry.is_mobile_web:
		_name_edit.visible = false
		_mobile_name_button = _make_button(tr("Your name"))
		_mobile_name_button.pressed.connect(func() -> void:
			MobileTextEntry.open("run_end_nickname", _name_edit.text, tr("Your name"), "text", 16)
		)
		layout.add_child(_mobile_name_button)
	_update_name_identity_ui()

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.custom_minimum_size.y = 42.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_status_label)

	_diagnostic_save_button = _make_button(tr("Save diagnostics"))
	_diagnostic_save_button.visible = false
	_diagnostic_save_button.pressed.connect(func() -> void: _status_label.text = str(get_parent().call("save_render_diagnostics")))
	layout.add_child(_diagnostic_save_button)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	layout.add_child(buttons)

	_submit_button = _make_button(tr("Submit score"))
	_submit_button.pressed.connect(_submit_score)
	buttons.add_child(_submit_button)

	var retry_button := _make_button(tr("Replay this course"))
	retry_button.pressed.connect(func() -> void: get_parent().call("retry_run"))
	buttons.add_child(retry_button)

	var random_button := _make_button(tr("New random course"))
	random_button.pressed.connect(func() -> void: get_parent().call("new_random_run"))
	buttons.add_child(random_button)

	var menu_button := _make_button(tr("Game Hub"))
	menu_button.pressed.connect(func() -> void: get_parent().call("return_to_main_menu"))
	buttons.add_child(menu_button)

func _ensure_name_visible() -> void:
	call_deferred("_keep_focused_name_visible")

func _keep_focused_name_visible() -> void:
	if is_instance_valid(_scroll) and is_instance_valid(_name_edit) and _name_edit.has_focus():
		_scroll.ensure_control_visible(_name_edit)

func _on_viewport_size_changed() -> void:
	_fit_panel_width()
	_keep_focused_name_visible()

func _fit_panel_width() -> void:
	if not is_instance_valid(_panel):
		return
	var available_width := maxf(get_viewport().get_visible_rect().size.x - 40.0, 280.0)
	_panel.custom_minimum_size.x = minf(560.0, available_width)

func _submit_score() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		_status_label.text = tr("Enter a name first.")
		_name_edit.grab_focus()
		return
	PlayerProfile.set_leaderboard_name(player_name)
	_submit_button.disabled = true
	_status_label.text = tr("Submitting score...")
	Leaderboard.submit_run(player_name, _distance_m, _coins)

func _on_mobile_text_submitted(field: String, value: String) -> void:
	if field == "run_end_nickname" and is_instance_valid(_name_edit):
		_name_edit.text = value.substr(0, 16)

func _share_run_challenge() -> void:
	var player_name := _preferred_leaderboard_name() if PlayerAccountProfile.has_profile else _name_edit.text.strip_edges()
	if not _is_public_nickname(player_name):
		_challenge_share_status.text = tr("Use a nickname with 3–16 letters, numbers or underscores.")
		if not PlayerAccountProfile.has_profile:
			_name_edit.grab_focus()
		return
	PlayerProfile.set_leaderboard_name(player_name)
	_challenge_code_label.visible = true
	_challenge_code_title.visible = true
	_challenge_link_title.visible = true
	_challenge_short_code_row.visible = true
	_challenge_code_row.visible = true
	_share_challenge_button.disabled = true
	_challenge_share_status.text = tr("Preparing a shareable challenge...")
	ChallengeService.create_challenge_for_current_run(player_name)

func _on_challenge_created(success: bool, challenge_code: String, _error_message: String) -> void:
	if not visible or not _share_challenge_button.disabled:
		return
	if success:
		_challenge_short_code_edit.text = challenge_code
		_challenge_code_edit.text = ChallengeService.get_challenge_link(challenge_code)
	else:
		# Until the additive RPC migration is applied, preserve the existing
		# plain-seed sharing path rather than blocking players from sharing.
		_challenge_short_code_edit.text = ChallengeService.get_challenge_code()
		_challenge_code_edit.text = ChallengeService.get_challenge_link()
	_copy_challenge_link()
	_challenge_share_status.text = tr("Saving your public seed result...")
	ChallengeService.submit_current_run(_preferred_leaderboard_name(), _distance_m)

func _is_public_nickname(player_name: String) -> bool:
	var nickname_pattern := RegEx.new()
	nickname_pattern.compile("^[A-Za-z0-9_]{3,16}$")
	return nickname_pattern.search(player_name) != null

func _on_seed_score_submission_finished(success: bool, error_message: String) -> void:
	if not visible:
		return
	_share_challenge_button.disabled = success
	if success:
		_challenge_share_status.text = tr("Seed result saved.")
	elif error_message == "nickname_reserved":
		_share_challenge_button.visible = true
		_challenge_share_status.text = tr("That nickname belongs to a registered player. Sign in to use it.")
	elif error_message.begins_with("network_error") or error_message.begins_with("http_error"):
		_share_challenge_button.visible = true
		_challenge_share_status.text = tr("Could not save the seed result. Check your connection and try again.")
	else:
		_share_challenge_button.visible = true
		_challenge_share_status.text = tr(error_message)

func _copy_challenge_link() -> void:
	var challenge_link := _challenge_code_edit.text.strip_edges()
	if challenge_link.is_empty():
		return
	DisplayServer.clipboard_set(challenge_link)
	_challenge_share_status.text = tr("Challenge link copied. Share it with a friend!")

func _copy_challenge_code() -> void:
	var challenge_code := _challenge_short_code_edit.text.strip_edges()
	if challenge_code.is_empty():
		return
	DisplayServer.clipboard_set(challenge_code)
	_challenge_share_status.text = tr("Challenge code copied. Share it with a friend!")

func _make_copy_icon_button(tooltip: String, callback: Callable) -> Button:
	var copy_button := Button.new()
	copy_button.custom_minimum_size = Vector2(52.0, 42.0)
	copy_button.tooltip_text = tooltip
	copy_button.accessibility_description = tooltip
	copy_button.pressed.connect(callback)
	var copy_icon := Control.new()
	copy_icon.set_script(COPY_ICON_SCRIPT)
	copy_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_icon.anchor_left = 0.5
	copy_icon.anchor_right = 0.5
	copy_icon.anchor_top = 0.5
	copy_icon.anchor_bottom = 0.5
	copy_icon.offset_left = -12.0
	copy_icon.offset_right = 12.0
	copy_icon.offset_top = -12.0
	copy_icon.offset_bottom = 12.0
	copy_button.add_child(copy_icon)
	return copy_button

func _on_submission_finished(success: bool, error_message: String) -> void:
	if not visible:
		return
	_submit_button.disabled = success
	_status_label.text = tr("Score submitted!") if success else error_message

func _on_account_run_saved(success: bool, message: String) -> void:
	if not visible or not is_instance_valid(_account_save_label):
		return
	_account_save_label.text = message
	_account_save_label.add_theme_color_override("font_color", Color("42d6c5") if success else Color("ffbd5c"))

func _on_run_loot_resolved(run_id: String, claims: Array) -> void:
	if run_id != _shown_run_id or claims.is_empty() or not is_instance_valid(_account_save_label):
		return
	var results: Array[String] = []
	for claim in claims:
		if not claim is Dictionary:
			continue
		var item_id := str(claim.get("item_id", ""))
		if str(claim.get("claim_status", "")) == "awarded":
			results.append(tr("Loot found: %s") % item_id.replace("_", " ").capitalize())
		elif str(claim.get("claim_status", "")) == "already_owned":
			results.append(tr("Loot found, but already owned: %s") % item_id.replace("_", " ").capitalize())
		else:
			results.append(tr("No item found this time."))
	_account_save_label.text += "\n" + "\n".join(results)

func _on_run_achievements_changed(entries: Array) -> void:
	if not visible:
		return
	_run_achievements.clear()
	for entry in entries:
		if entry is Dictionary:
			_run_achievements.append(entry)
	_achievement_index = 0
	_update_achievement_carousel()

func _change_achievement(direction: int) -> void:
	if _run_achievements.is_empty():
		return
	_achievement_index = posmod(_achievement_index + direction, _run_achievements.size())
	_update_achievement_carousel()

func _update_achievement_carousel() -> void:
	if not is_instance_valid(_achievement_section):
		return
	_achievement_section.visible = AuthService.is_authenticated and not _run_achievements.is_empty()
	if not _achievement_section.visible:
		return
	var entry: Dictionary = _run_achievements[_achievement_index]
	_achievement_title.text = tr(str(entry.get("title", "Achievement")))
	_achievement_description.text = tr(str(entry.get("description", "")))
	_achievement_category_icon.icon_key = _achievement_category_key(str(entry.get("id", "")), str(entry.get("metric", "")))
	_achievement_counter.text = "%d / %d" % [_achievement_index + 1, _run_achievements.size()]
	_achievement_previous.disabled = _run_achievements.size() < 2
	_achievement_next.disabled = _run_achievements.size() < 2

func _achievement_category_key(achievement_id: String, metric: String) -> String:
	if achievement_id == "coins_earned" or metric == "total_coins_earned":
		return "coins_earned"
	if achievement_id == "gravity_flips" or metric == "total_gravity_flips":
		return "gravity_flips"
	if achievement_id == "hazards_discovered" or metric in ["distinct_hazards_seen", "hazard_encounters"]:
		return "hazards_discovered"
	if achievement_id == "distance_run" or metric == "best_run_distance_m":
		return "distance_run"
	if achievement_id == "distance_total" or metric == "total_distance_m":
		return "distance_total"
	return "unknown"

func _achievement_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101827", 0.62)
	style.border_color = Color("f5d45e", 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _on_account_profile_changed(_nickname: String, _has_profile: bool) -> void:
	if not is_instance_valid(_name_edit):
		return
	_name_edit.text = _preferred_leaderboard_name()
	_update_name_identity_ui()

func _update_name_identity_ui() -> void:
	if is_instance_valid(_name_edit):
		_name_edit.editable = not PlayerAccountProfile.has_profile
	if is_instance_valid(_mobile_name_button):
		_mobile_name_button.visible = not PlayerAccountProfile.has_profile
	if is_instance_valid(_name_label):
		_name_label.text = tr("Account nickname") if PlayerAccountProfile.has_profile else tr("Leaderboard name (up to 16 characters)")
	if is_instance_valid(_privacy_note):
		_privacy_note.text = tr("Your account nickname will be used for this score.") if PlayerAccountProfile.has_profile else tr("Your name and score will be public.")

func _preferred_leaderboard_name() -> String:
	if PlayerAccountProfile.has_profile:
		return PlayerAccountProfile.nickname
	return PlayerProfile.leaderboard_name

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	return style
