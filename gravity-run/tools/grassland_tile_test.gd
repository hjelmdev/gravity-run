extends Node2D

const GRASSLAND_TILE_SET := preload("res://assets/biomes/grassland_prototype.tres")

func _ready() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var back_button := Button.new()
	back_button.text = "← TEST HUB"
	back_button.position = Vector2(790.0, 14.0)
	back_button.size = Vector2(150.0, 38.0)
	back_button.pressed.connect(_back_to_hub)
	ui.add_child(back_button)

	var title := Label.new()
	title.position = Vector2(24.0, 24.0)
	title.text = "GRASSLAND — one 64×64 tile repeated across a flat floor"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	var note := Label.new()
	note.position = Vector2(24.0, 60.0)
	note.text = "This is only a single-tile repeat test; autotile terrain mapping is not configured yet."
	add_child(note)

	var ground := TileMapLayer.new()
	ground.tile_set = GRASSLAND_TILE_SET
	ground.position = Vector2(0.0, 380.0)
	for x in range(15):
		ground.set_cell(Vector2i(x, 0), 0, Vector2i.ZERO)
	add_child(ground)

func _back_to_hub() -> void:
	get_tree().change_scene_to_file("res://tools/test_hub.tscn")
