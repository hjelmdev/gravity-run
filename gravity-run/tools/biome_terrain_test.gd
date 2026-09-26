extends Control

const BIOMES: Array[BiomeDefinition] = [
	preload("res://assets/biomes/definitions/red_brown.tres"),
	preload("res://assets/biomes/definitions/yellow_green.tres"),
	preload("res://assets/biomes/definitions/blue_gray.tres"),
	preload("res://assets/biomes/definitions/green_green.tres"),
]
const PLAYER_SCENE := preload("res://player/player.tscn")

var selected_biome_index := 0
var floor_layer: TileMapLayer
var ceiling_layer: TileMapLayer
var title_label: Label
var description_label: Label
var buttons: Array[Button] = []

func _ready() -> void:
	_build_ui()
	_show_biome(0)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101827")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var top_row := HBoxContainer.new()
	layout.add_child(top_row)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("edf3ff"))
	top_row.add_child(title_label)
	var back_button := Button.new()
	back_button.text = "← TEST HUB"
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://tools/test_hub.tscn"))
	top_row.add_child(back_button)

	description_label = Label.new()
	description_label.add_theme_font_size_override("font_size", 14)
	description_label.add_theme_color_override("font_color", Color("b9c8dc"))
	layout.add_child(description_label)

	var selector := HBoxContainer.new()
	selector.add_theme_constant_override("separation", 10)
	layout.add_child(selector)
	for index in range(BIOMES.size()):
		var biome := BIOMES[index]
		var button := Button.new()
		button.text = biome.display_name
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(150, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_biome.bind(index))
		selector.add_child(button)
		buttons.append(button)

	var preview := PanelContainer.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_theme_stylebox_override("panel", _panel_style(Color("18243a")))
	layout.add_child(preview)
	var canvas := Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(canvas)
	ceiling_layer = TileMapLayer.new()
	ceiling_layer.name = "GeneratedCeiling"
	ceiling_layer.tile_set = BIOMES[0].tile_set
	ceiling_layer.position = Vector2(20, 8)
	canvas.add_child(ceiling_layer)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "GeneratedFloor"
	floor_layer.tile_set = BIOMES[0].tile_set
	floor_layer.position = Vector2(20, 220)
	canvas.add_child(floor_layer)
	var player := PLAYER_SCENE.instantiate()
	player.name = "ScaleReferencePlayer"
	player.position = Vector2(170, 198)
	canvas.add_child(player)

	var note := Label.new()
	note.text = "Visuell testlayout • 64 px atlasrutor • luckorna är tomma TileMap-celler • figuren visar ungefärlig skala"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("9eafc7"))
	layout.add_child(note)

func _show_biome(index: int) -> void:
	selected_biome_index = index
	var biome := BIOMES[index]
	title_label.text = "TILEMAP-BANA — %s" % biome.display_name.to_upper()
	description_label.text = "Biome: %s. Golv- och takluckorna är förskjutna; jämför 64 px-rutorna med spelarfiguren." % biome.display_name
	floor_layer.clear()
	ceiling_layer.clear()
	floor_layer.tile_set = biome.tile_set
	ceiling_layer.tile_set = biome.tile_set
	# Fixed visual layout: platforms, a two-cell opening in each surface,
	# with the gaps offset so an opposite surface is always available.
	_place_platform(floor_layer, biome, 0, 4, 1, false)
	_place_platform(floor_layer, biome, 7, 11, 4, false)
	_place_platform(ceiling_layer, biome, 0, 2, 1, true)
	_place_platform(ceiling_layer, biome, 5, 11, 2, true)
	for button_index in range(buttons.size()):
		buttons[button_index].button_pressed = button_index == index

func _place_platform(layer: TileMapLayer, biome: BiomeDefinition, start_column: int, end_column: int, first_atlas_x: int, flip_vertical: bool) -> void:
	for column in range(start_column, end_column + 1):
		var atlas_x := first_atlas_x + column - start_column
		var atlas_coords := Vector2i(atlas_x, biome.palette_row)
		var alternative := TileSetAtlasSource.TRANSFORM_FLIP_V if flip_vertical else 0
		layer.set_cell(Vector2i(column, 0), biome.atlas_source_id, atlas_coords, alternative)

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
