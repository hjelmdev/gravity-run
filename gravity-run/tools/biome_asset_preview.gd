extends Control

const ASSETS := [
	["Tile.png — single grass/dirt tile", "res://assets/biomes/legacy_candidates/Tile.png"],
	["autotiles.png — terrain atlas", "res://assets/biomes/legacy_candidates/autotiles.png"],
	["tileset2x2.png — large terrain pieces", "res://assets/biomes/legacy_candidates/tileset2x2.png"],
	["tilesheet_complete.png — full platformer sheet", "res://assets/biomes/legacy_candidates/tilesheet_complete.png"]
]

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("101827")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margins.add_theme_constant_override(margin_name, 14)
	add_child(margins)

	var layout := VBoxContainer.new()
	margins.add_child(layout)

	var title := Label.new()
	title.text = "GRAVITY RUN — LEGACY TILE CANDIDATES"
	title.add_theme_font_size_override("font_size", 20)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Raw PNGs reimported in Godot 4; no legacy scenes or TileSet resources used."
	subtitle.add_theme_font_size_override("font_size", 12)
	layout.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(grid)

	for asset in ASSETS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0.0, 205.0)
		grid.add_child(panel)

		var content := VBoxContainer.new()
		panel.add_child(content)

		var label := Label.new()
		label.text = asset[0]
		content.add_child(label)

		var preview := TextureRect.new()
		preview.texture = load(asset[1]) as Texture2D
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(0.0, 160.0)
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(preview)
