extends Control

const ATLAS := preload("res://assets/biomes/legacy_candidates/tilesheet_complete.png")
const TILE_SIZE := 64
const ZOOM_REGION := Rect2i(0, 0, 640, 512)

func _ready() -> void:
	var back_button := Button.new()
	back_button.text = "← TEST HUB"
	back_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back_button.offset_left = -154.0
	back_button.offset_top = 8.0
	back_button.offset_right = -12.0
	back_button.offset_bottom = 44.0
	back_button.z_index = 10
	back_button.pressed.connect(_back_to_hub)
	add_child(back_button)
	queue_redraw()

func _back_to_hub() -> void:
	get_tree().change_scene_to_file("res://tools/test_hub.tscn")

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("101827"))
	draw_string(ThemeDB.fallback_font, Vector2(20, 30), "TERRAIN ATLAS — slope- och biomegranskning", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("edf3ff"))
	draw_string(ThemeDB.fallback_font, Vector2(20, 52), "Rutnätet visar 64 px atlasrutor. Zoomvyn till vänster fokuserar terrängdelarna.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b9c8dc"))

	var zoom_scale := minf((viewport_size.x * 0.55) / ZOOM_REGION.size.x, (viewport_size.y - 120.0) / ZOOM_REGION.size.y)
	var zoom_origin := Vector2(20, 85)
	var zoom_size := Vector2(ZOOM_REGION.size) * zoom_scale
	draw_texture_rect_region(ATLAS, Rect2(zoom_origin, zoom_size), ZOOM_REGION, Color.WHITE, false, true)
	_draw_grid(zoom_origin, zoom_scale, ZOOM_REGION.size)
	draw_rect(Rect2(zoom_origin, zoom_size), Color("d5e2f0"), false, 1.0)

	var overview_scale := minf((viewport_size.x * 0.39) / ATLAS.get_width(), (viewport_size.y * 0.38) / ATLAS.get_height())
	var overview_origin := Vector2(viewport_size.x * 0.59, 85)
	var overview_size := Vector2(ATLAS.get_size()) * overview_scale
	draw_texture_rect(ATLAS, Rect2(overview_origin, overview_size), false, Color.WHITE)
	_draw_grid(overview_origin, overview_scale, ATLAS.get_size())
	draw_rect(Rect2(overview_origin, overview_size), Color("d5e2f0"), false, 1.0)
	var selected := Rect2(overview_origin, Vector2(ZOOM_REGION.size) * overview_scale)
	draw_rect(selected, Color("ffe071"), false, 2.0)

	var note_y := overview_origin.y + overview_size.y + 28
	draw_string(ThemeDB.fallback_font, Vector2(overview_origin.x, note_y), "Översikt — gul ruta = zoom till vänster", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffe071"))
	draw_string(ThemeDB.fallback_font, Vector2(overview_origin.x, note_y + 24), "Titta särskilt på sammanhängande gröna/bruna", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b9c8dc"))
	draw_string(ThemeDB.fallback_font, Vector2(overview_origin.x, note_y + 42), "lutningar och skarvar mellan atlasrutor.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b9c8dc"))

func _draw_grid(origin: Vector2, scale: float, region_size: Vector2i) -> void:
	var cols := int(region_size.x / TILE_SIZE)
	var rows := int(region_size.y / TILE_SIZE)
	for col in range(cols + 1):
		var x := origin.x + col * TILE_SIZE * scale
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + region_size.y * scale), Color(0.95, 0.95, 1.0, 0.38), 1.0)
		if col < cols and scale > 0.45:
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, origin.y + 13), str(col), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	for row in range(rows + 1):
		var y := origin.y + row * TILE_SIZE * scale
		draw_line(Vector2(origin.x, y), Vector2(origin.x + region_size.x * scale, y), Color(0.95, 0.95, 1.0, 0.38), 1.0)
		if row < rows and scale > 0.45:
			draw_string(ThemeDB.fallback_font, Vector2(origin.x + 3, y + 25), str(row), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
