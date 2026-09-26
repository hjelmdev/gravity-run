extends Control

const TESTS := [
	{
		"title": "BIOME — generated terrain",
		"description": "En TileMap-testbana med golv, tak, förskjutna hål och spelarfiguren som storleksreferens.",
		"scene": "res://tools/biome_terrain_test.tscn",
		"color": Color("285b4b")
	},
	{
		"title": "GRASS — generated terrain",
		"description": "Bygg en terrängprofil från celler och låt Godot koppla ihop atlasrutorna.",
		"scene": "res://tools/generated_grass_terrain_test.tscn",
		"color": Color("245b4b")
	},
	{
		"title": "BIOMES — image viewer",
		"description": "Visar bildarken från gamla repot; genererar ingen bana.",
		"scene": "res://tools/biome_asset_preview.tscn",
		"color": Color("36506b")
	},
	{
		"title": "SLOPES — atlas viewer",
		"description": "Förstorad bildgranskning; testar inte terrängkoppling ännu.",
		"scene": "res://tools/terrain_atlas_inspector.tscn",
		"color": Color("624a27")
	},
	{
		"title": "GRAVITY RUN — sandbox",
		"description": "Starta den vanliga spelprototypen.",
		"scene": "res://main.tscn",
		"color": Color("57354b")
	}
]

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("101827")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title_row := HBoxContainer.new()
	layout.add_child(title_row)
	var title := Label.new()
	title.text = "GRAVITY RUN — TEST LAB"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("edf3ff"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var menu_button := Button.new()
	menu_button.text = "MAIN MENU"
	menu_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
	title_row.add_child(menu_button)

	var subtitle := Label.new()
	subtitle.text = "Utvecklingsprototyper och fristående tester. De påverkar inte en vanlig New Game-runda."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("b9c8dc"))
	layout.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2 if get_viewport_rect().size.x >= 760.0 else 1
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	layout.add_child(grid)
	get_viewport().size_changed.connect(func() -> void:
		grid.columns = 2 if get_viewport_rect().size.x >= 760.0 else 1
	)

	for test in TESTS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 150)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.focus_mode = Control.FOCUS_ALL
		card.add_theme_stylebox_override("panel", _button_style(test.color, 12))
		card.mouse_entered.connect(_set_card_hover.bind(card, test.color, true))
		card.mouse_exited.connect(_set_card_hover.bind(card, test.color, false))
		card.gui_input.connect(_on_card_input.bind(test.scene))
		grid.add_child(card)

		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		card.add_child(content)

		var heading := Label.new()
		heading.text = test.title
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", Color("f5f7fb"))
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(heading)

		var description := Label.new()
		description.text = test.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		description.add_theme_font_size_override("font_size", 13)
		description.add_theme_color_override("font_color", Color("d5dfef"))
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(description)

		var hint := Label.new()
		hint.text = "Öppna test"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color("ffe071"))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(hint)

func _button_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.border_color = color.lightened(0.24)
	style.set_border_width_all(1)
	return style

func _open_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _set_card_hover(card: PanelContainer, color: Color, hovered: bool) -> void:
	card.add_theme_stylebox_override("panel", _button_style(color.lightened(0.12) if hovered else color, 12))

func _on_card_input(event: InputEvent, scene_path: String) -> void:
	if event is InputEventScreenTouch and event.pressed:
		accept_event()
		_open_scene(scene_path)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		_open_scene(scene_path)
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]:
		accept_event()
		_open_scene(scene_path)
