extends Node2D

const ATLAS_TEXTURE := preload("res://assets/biomes/legacy_candidates/autotiles.png")
const TILE_SIZE := 16
const FLOOR_CELL_COUNT := 54
const FLOOR_BOTTOM := 25

# Godot 3's autotile bitmask values copied from the old LevelBase TileSet.
# In Godot 4 these become Terrain Peering Bits on the same atlas cells.
const LEGACY_MASKS := [
	144, 146, 18, 16,
	176, 178, 50, 48,
	184, 186, 58, 56,
	152, 154, 26, 24,
	443, 434, 182, 250,
	440, 510, 447, 62,
	248, 507, 255, 59,
	190, 218, 155, 442,
	432, 438, 446, 54,
	506, 254, 511, 63,
	504, -1, 443, 191,
	216, 251, 219, 27
]

const PEERING_BITS := [
	{"bit": 1, "neighbor": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER},
	{"bit": 2, "neighbor": TileSet.CELL_NEIGHBOR_TOP_SIDE},
	{"bit": 4, "neighbor": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER},
	{"bit": 8, "neighbor": TileSet.CELL_NEIGHBOR_LEFT_SIDE},
	{"bit": 32, "neighbor": TileSet.CELL_NEIGHBOR_RIGHT_SIDE},
	{"bit": 64, "neighbor": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER},
	{"bit": 128, "neighbor": TileSet.CELL_NEIGHBOR_BOTTOM_SIDE},
	{"bit": 256, "neighbor": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER}
]

func _ready() -> void:
	_add_background_and_labels()
	_add_back_button()
	var tile_set := _build_legacy_grass_terrain_set()
	var tile_map := TileMapLayer.new()
	tile_map.name = "GeneratedGrassTileMap"
	tile_map.position = Vector2(24.0, 78.0)
	tile_map.tile_set = tile_set
	add_child(tile_map)

	var cells: Array[Vector2i] = []
	var profile: Array[int] = []
	for x in range(FLOOR_CELL_COUNT):
		var surface_y := _surface_cell_y(x)
		profile.append(surface_y)
		for y in range(surface_y, FLOOR_BOTTOM):
			cells.append(Vector2i(x, y))
	tile_map.set_cells_terrain_connect(cells, 0, 0)
	var selected_tiles: Dictionary = {}
	for cell in tile_map.get_used_cells():
		selected_tiles[tile_map.get_cell_atlas_coords(cell)] = true
	print("Generated terrain cells: ", tile_map.get_used_cells().size(), "; atlas variants selected: ", selected_tiles.keys().size(), " ", selected_tiles.keys())
	_add_generated_collision(profile)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960.0, 540.0)), Color("101827"))

func _build_legacy_grass_terrain_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(0)
	tile_set.set_terrain_name(0, 0, "Grassland")
	tile_set.set_terrain_color(0, 0, Color("55c96a"))

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ATLAS_TEXTURE
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, 0)
	for x in range(12):
		for y in range(4):
			var coords := Vector2i(x, y)
			var index := x * 4 + y
			var mask: int = LEGACY_MASKS[index]
			if mask < 0:
				continue
			atlas.create_tile(coords)
			var tile_data := atlas.get_tile_data(coords, 0)
			tile_data.terrain_set = 0
			tile_data.terrain = 0
			for bit_info in PEERING_BITS:
				var terrain_id := 0 if mask & int(bit_info.bit) else -1
				tile_data.set_terrain_peering_bit(int(bit_info.neighbor), terrain_id)
	return tile_set

func _surface_cell_y(x: int) -> int:
	if x < 10 or x >= 44:
		return 14
	if x < 22:
		return 14 - int((x - 10) / 2)
	if x < 32:
		return 8
	return 8 + int((x - 32) / 2)

func _add_generated_collision(profile: Array[int]) -> void:
	var polygon := PackedVector2Array()
	for x in range(profile.size()):
		polygon.append(Vector2(x * TILE_SIZE, profile[x] * TILE_SIZE))
	polygon.append(Vector2(profile.size() * TILE_SIZE, FLOOR_BOTTOM * TILE_SIZE))
	polygon.append(Vector2(0.0, FLOOR_BOTTOM * TILE_SIZE))
	var body := StaticBody2D.new()
	body.position = Vector2(24.0, 78.0)
	body.name = "GeneratedGroundCollision"
	var collision := CollisionPolygon2D.new()
	collision.polygon = polygon
	body.add_child(collision)
	add_child(body)

func _add_background_and_labels() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.position = Vector2(24.0, 14.0)
	title.text = "AUTOGENERERAD GRÄSTERRÄNG — GODOT TERRAIN CONNECT"
	title.add_theme_font_size_override("font_size", 18)
	layer.add_child(title)
	var explanation := Label.new()
	explanation.position = Vector2(24.0, 42.0)
	explanation.text = "Koden bygger plan mark → uppförsbacke → platå → nedförsbacke → plan mark. Godot väljer kanttiles."
	explanation.add_theme_font_size_override("font_size", 12)
	layer.add_child(explanation)
	var footer := Label.new()
	footer.position = Vector2(24.0, 500.0)
	footer.text = "Gamla tile-regler återanvänds; ingen gammal scen importerad. Kollisionsprofilen byggs från samma terrängform."
	footer.add_theme_font_size_override("font_size", 11)
	layer.add_child(footer)

func _add_back_button() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var button := Button.new()
	button.text = "← TEST HUB"
	button.position = Vector2(790.0, 12.0)
	button.size = Vector2(150.0, 36.0)
	button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://tools/test_hub.tscn"))
	layer.add_child(button)
