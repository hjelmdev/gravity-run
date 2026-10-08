extends CanvasLayer
## Result screen for a campaign stage: a quick retry after a fall, or the
## stars, score and unlocks after the finish line.

signal retry_requested
signal next_requested
signal map_requested

const StarIconScript := preload("res://campaign/star_icon.gd")

var _root: Control
var _title: Label
var _subtitle: Label
var _stars_row: HBoxContainer
var _score_label: Label
var _detail_label: Label
var _unlock_label: Label
var _primary: Button
var _replay: Button
var _map: Button
var _primary_action := "retry"
var _star_icons: Array[Control] = []

func _ready() -> void:
	_build()
	visible = false

func hide_panel() -> void:
	visible = false

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.02, 0.04, 0.08, 0.72)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	_title = _label("", 30, Color("f5d45e"))
	layout.add_child(_title)
	_subtitle = _label("", 15, Color("b8c7dc"))
	layout.add_child(_subtitle)
	_stars_row = HBoxContainer.new()
	_stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stars_row.add_theme_constant_override("separation", 14)
	layout.add_child(_stars_row)
	_score_label = _label("", 22, Color("edf3ff"))
	layout.add_child(_score_label)
	_detail_label = _label("", 13, Color("b8c7dc"))
	layout.add_child(_detail_label)
	_unlock_label = _label("", 15, Color("42d6c5"))
	layout.add_child(_unlock_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	layout.add_child(buttons)
	_primary = _button("", buttons)
	_primary.pressed.connect(_on_primary)
	_replay = _button(tr("Replay"), buttons)
	_replay.pressed.connect(retry_requested.emit)
	_map = _button(tr("Map"), buttons)
	_map.pressed.connect(map_requested.emit)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, parent: Container) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 46.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	parent.add_child(button)
	return button

func _on_primary() -> void:
	if _primary_action == "next":
		next_requested.emit()
	elif _primary_action == "map":
		map_requested.emit()
	else:
		retry_requested.emit()

func show_result(level: CampaignLevel, result: Dictionary) -> void:
	for icon in _star_icons:
		icon.queue_free()
	_star_icons.clear()
	var failed := bool(result.get("failed", false))
	var star_total := level.stars.size() if level != null else 0
	if failed:
		_title.text = tr("RULLAREN WINS THIS ROUND") if level != null and level.is_boss() else tr("OUCH!")
		_title.add_theme_color_override("font_color", Color("ff647c"))
		_subtitle.text = "%s  %s" % [str(level.level_id), tr(level.title)] if level != null else ""
		_stars_row.visible = false
		var progress := float(result.get("progress", 0.0))
		_score_label.text = tr("You made it %d%% of the way") % roundi(progress * 100.0) if level != null and not level.is_boss() else tr("Hit the glowing plates to damage it")
		_score_label.add_theme_font_size_override("font_size", 17)
		_detail_label.text = tr("No checkpoints: the stage starts over from the beginning.")
		_unlock_label.text = ""
		_primary.text = tr("Try again")
		_primary_action = "retry"
		_replay.visible = false
	else:
		_title.text = tr("RULLAREN IS BEATEN!") if level.is_boss() else tr("STAGE CLEAR!")
		_title.add_theme_color_override("font_color", Color("f5d45e"))
		_subtitle.text = "%s  %s" % [str(level.level_id), tr(level.title)]
		_stars_row.visible = star_total > 0
		var collected := int(result.get("star_count", 0))
		for index in range(star_total):
			var icon := StarIconScript.new() as Control
			icon.custom_minimum_size = Vector2(54.0, 54.0)
			icon.set("filled", index < collected)
			icon.set("pop_delay", 0.25 + float(index) * 0.22)
			_stars_row.add_child(icon)
			_star_icons.append(icon)
		_score_label.add_theme_font_size_override("font_size", 22)
		var score_text := tr("Score: %d") % int(result.get("score", 0))
		if bool(result.get("new_best", false)) and not bool(result.get("first_completion", false)):
			score_text += "  ·  " + tr("New best!")
		_score_label.text = score_text
		_detail_label.text = tr("Coins %d  ·  Stars %d/%d  ·  Best %d") % [int(result.get("coins", 0)), int(result.get("total_stars", collected)), star_total, int(result.get("best_score", 0))] if star_total > 0 else tr("Coins %d  ·  Best %d") % [int(result.get("coins", 0)), int(result.get("best_score", 0))]
		var unlock_lines: Array[String] = []
		var world_unlocked: CampaignWorld = result.get("world_unlocked")
		if world_unlocked != null:
			unlock_lines.append(tr("New world unlocked: %s") % tr(world_unlocked.title))
		var next: CampaignLevel = result.get("next_level")
		if bool(result.get("next_unlocked_now", false)) and next != null:
			unlock_lines.append(tr("Unlocked: %s %s") % [str(next.level_id), tr(next.title)])
		if int(result.get("new_stars", 0)) > 0 and not bool(result.get("first_completion", false)):
			unlock_lines.append(tr("+%d new gravity stars") % int(result.get("new_stars", 0)))
		_unlock_label.text = "\n".join(unlock_lines)
		var has_next := next != null and Campaign.is_level_unlocked(next)
		_primary.text = tr("Next stage") if has_next else tr("Map")
		_primary_action = "next" if has_next else "map"
		_replay.visible = true
		_map.visible = has_next
	if failed:
		_map.visible = true
	visible = true
	_primary.grab_focus()
