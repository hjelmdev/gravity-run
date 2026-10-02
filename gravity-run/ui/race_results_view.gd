extends ScrollContainer
## Shared, authority-independent podium and result list. Receives committed rows.
const Medal := preload("res://ui/result_medal.gd")
const Frames := preload("res://assets/character/run_frames.tres")
const SkinPalette := preload("res://player/skin_palette.gd")

var rows: Array = []

func show_rows(placements: Array) -> void:
	rows = placements.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 100
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	var podium := HBoxContainer.new()
	podium.add_theme_constant_override("separation", 8)
	body.add_child(podium)
	# For ties all peers with the same medal share its step and label.
	for place in [2, 1, 3]:
		var group: Array = []
		for row in rows:
			if int(row.get("place", 0)) == place:
				group.append(row)
		if group.is_empty():
			continue
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.alignment = BoxContainer.ALIGNMENT_END
		podium.add_child(column)
		var portraits := HBoxContainer.new()
		portraits.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(portraits)
		for row in group:
			var portrait := TextureRect.new()
			portrait.texture = Frames.get_frame_texture("run", 0)
			portrait.material = SkinPalette.make_material(int(row.get("skin_id", 0)))
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.custom_minimum_size = Vector2(30, 48)
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portraits.add_child(portrait)
		var names := Label.new()
		var name_parts := PackedStringArray()
		for row in group:
			name_parts.append(str(row.get("display_name", tr("Player"))))
		names.text = " / ".join(name_parts)
		names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		names.add_theme_font_size_override("font_size", 14)
		column.add_child(names)
		var step := PanelContainer.new()
		step.custom_minimum_size.y = 76 if place == 1 else (54 if place == 2 else 36)
		var style := StyleBoxFlat.new()
		style.bg_color = [Color("b28b29"), Color("78869a"), Color("95633f")][place - 1]
		style.set_corner_radius_all(5)
		step.add_theme_stylebox_override("panel", style)
		column.add_child(step)
		var rank := Label.new()
		rank.text = "#%d" % place
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank.add_theme_font_size_override("font_size", 24)
		step.add_child(rank)
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		body.add_child(line)
		var place := int(row.get("place", 0))
		if place >= 1 and place <= 3:
			var medal := Medal.new()
			medal.place = place
			medal.custom_minimum_size = Vector2(38, 34)
			line.add_child(medal)
		var label := Label.new()
		label.text = "#%d  %s" % [place, str(row.get("display_name", tr("Player")))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(label)
		var details := Label.new()
		details.text = "%d m  ·  %s %d" % [int(float(row.get("distance", 0.0)) / 10.0), tr("Shared coins"), int(row.get("shared_coins", 0))]
		details.tooltip_text = readable_reason(str(row.get("reason", "")), str(row.get("state", "")))
		line.add_child(details)

func readable_reason(reason: String, state: String) -> String:
	if reason == "falling_rock_warning_missed_delivery":
		return tr("Connection lost")
	if state == "finished":
		return tr("Finished")
	if state == "disconnected":
		return tr("Connection lost")
	match reason:
		"spikes", "step_spikes": return tr("Spikes")
		"block": return tr("Block")
		"barrel_contact", "barrel": return tr("Barrel")
		"falling_rock": return tr("Falling rock")
		"out_of_bounds": return tr("Fell off the course")
	return tr("Eliminated")
