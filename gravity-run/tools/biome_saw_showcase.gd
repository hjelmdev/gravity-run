extends Node2D
## Local-only visual review fixture. It is not connected to the product menu.

const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const SurfaceRenderer := preload("res://systems/course_surface_renderer.gd")
const WarningIcon := preload("res://systems/rock_warning_icon.gd")

const THEME_DISTANCE := {&"classic": 0.0, &"cave": 4800.0, &"haunted": 9600.0}

func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 2.0 or viewport_size.y < 2.0:
		return
	var panel_height := viewport_size.y / 3.0
	var world_width := viewport_size.x
	var panel_ids: Array[StringName] = [&"classic", &"cave", &"haunted"]
	for panel_index in range(panel_ids.size()):
		var theme_id := panel_ids[panel_index]
		var top := float(panel_index) * panel_height
		var distance := float(THEME_DISTANCE[theme_id])
		var biome := BiomeRendererScript.definition_at(distance)
		draw_set_transform(Vector2(0.0, top))
		BiomeRendererScript.draw_backdrop(self, 0.0, Vector2(world_width, panel_height), distance)
		var floor_gap_start := world_width * 0.47 + 13.0
		var ceiling_gap_start := world_width * 0.79 + 9.0
		var gaps: Array[Dictionary] = [
			{"start": floor_gap_start, "end": floor_gap_start + 66.0, "ceiling": false},
			{"start": ceiling_gap_start, "end": ceiling_gap_start + 52.0, "ceiling": true},
		]
		SurfaceRenderer.draw_track(self, 0.0, Vector2(world_width, panel_height), gaps, [], [], _surface_y.bind(panel_height), 0.0, biome, distance)
		_draw_gameplay_symbols(world_width, panel_height, biome.accent_color, floor_gap_start, ceiling_gap_start)
		draw_rect(Rect2(0.0, 0.0, world_width, 36.0), Color(0.025, 0.035, 0.055, 0.76))
		var surface_art := "ATLAS" if biome.tile_set != null else "VECTOR SURFACE"
		draw_string(ThemeDB.fallback_font, Vector2(14.0, 25.0), "%s BIOME | V9 %s" % [String(theme_id).to_upper(), surface_art], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color.WHITE)
		if panel_index > 0:
			draw_line(Vector2(0.0, 0.0), Vector2(world_width, 0.0), Color(0.76, 0.83, 0.9, 0.6), 2.0)
	draw_set_transform(Vector2.ZERO)

func _surface_y(x: float, ceiling: bool, panel_height: float) -> float:
	var floor_y := panel_height * 0.79
	if x > panel_height * 0.56:
		floor_y -= minf((x - panel_height * 0.56) * 0.055, 14.0)
	if x > panel_height * 0.92:
		floor_y -= 10.0
	var ceiling_y := panel_height * 0.20
	if ceiling:
		return ceiling_y
	return floor_y

func _draw_gameplay_symbols(width: float, height: float, accent: Color, floor_gap_start: float, ceiling_gap_start: float) -> void:
	var floor_y := _surface_y(width * 0.18, false, height)
	var runner := Rect2(width * 0.16, floor_y - 43.0, 28.0, 42.0)
	draw_rect(runner, Color("e8edf3"), true)
	draw_circle(runner.position + Vector2(20.0, 8.0), 2.2, Color("18202b"))
	var coin_x := width * 0.32
	var coin_y := _surface_y(coin_x, false, height) - 34.0
	draw_circle(Vector2(coin_x, coin_y), 12.0, Color("ffd466"))
	draw_circle(Vector2(coin_x, coin_y), 7.0, Color("fff0a8"))
	var spike_x := width * 0.54
	var spike_y := _surface_y(spike_x, false, height)
	draw_colored_polygon(PackedVector2Array([Vector2(spike_x - 17.0, spike_y), Vector2(spike_x, spike_y - 28.0), Vector2(spike_x + 17.0, spike_y)]), Color("c9d0d8"))
	var saw_center := Vector2(width * 0.73, _surface_y(width * 0.73, false, height) - 24.0)
	draw_circle(saw_center, 21.0, Color("aeb8bf"))
	draw_circle(saw_center, 14.0, Color("38414a"))
	for tooth in range(8):
		var outer := saw_center + Vector2.from_angle(TAU * float(tooth) / 8.0) * 23.0
		var left := saw_center + Vector2.from_angle(TAU * float(tooth) / 8.0 - 0.16) * 12.0
		var right := saw_center + Vector2.from_angle(TAU * float(tooth) / 8.0 + 0.16) * 12.0
		draw_colored_polygon(PackedVector2Array([left, outer, right]), Color("e6ebef"))
	var rock_warning_center := Vector2(floor_gap_start - 36.0, _surface_y(floor_gap_start - 36.0, false, height) - 52.0)
	WarningIcon.draw(self, rock_warning_center, 38.0)
	# The holes are deliberately off the tile grid; this marker makes their exact
	# edge apparent in screenshots without placing decoration into the gap.
	draw_line(Vector2(floor_gap_start, _surface_y(floor_gap_start, false, height)), Vector2(floor_gap_start, height), accent, 2.0)
	draw_line(Vector2(ceiling_gap_start, _surface_y(ceiling_gap_start, true, height)), Vector2(ceiling_gap_start, 0.0), accent, 2.0)
