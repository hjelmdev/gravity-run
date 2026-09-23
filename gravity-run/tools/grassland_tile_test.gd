extends Node2D

const GRASSLAND_TILE_SET := preload("res://assets/biomes/grassland_prototype.tres")

func _ready() -> void:
	var title := Label.new()
	title.position = Vector2(24.0, 24.0)
	title.text = "GRASSLAND TILE TEST — 64×64 legacy tile"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	var note := Label.new()
	note.position = Vector2(24.0, 60.0)
	note.text = "Repeated TileMapLayer cells; current gameplay and main scene are unchanged."
	add_child(note)

	var ground := TileMapLayer.new()
	ground.tile_set = GRASSLAND_TILE_SET
	ground.position = Vector2(0.0, 260.0)
	for x in range(15):
		for y in range(4):
			ground.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	add_child(ground)
