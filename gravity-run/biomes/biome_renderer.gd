extends RefCounted
class_name BiomeRenderer
## Shared, distance-addressed biome presentation. Biomes only affect drawing.

const CLASSIC: BiomeDefinition = preload("res://assets/biomes/definitions/classic.tres")
const CAVE: BiomeDefinition = preload("res://assets/biomes/definitions/cave.tres")
const HAUNTED: BiomeDefinition = preload("res://assets/biomes/definitions/haunted.tres")
const THEME_LENGTH := 4800.0
const CYCLE_LENGTH := THEME_LENGTH * 3.0
const TILE_WORLD_SIZE := 64.0

static func definition_at(distance: float) -> BiomeDefinition:
	var slot := int(floor(fposmod(maxf(distance, 0.0), CYCLE_LENGTH) / THEME_LENGTH))
	match slot:
		1: return CAVE
		2: return HAUNTED
		_: return CLASSIC

static func biome_id_at(distance: float) -> String:
	return String(definition_at(distance).biome_id)

static func course_distance_at_world_x(world_x: float, course_start_x: float) -> float:
	## SP and manifest-backed MP share this world-to-course coordinate contract.
	return maxf(world_x - course_start_x, 0.0)

static func draw_backdrop(canvas: CanvasItem, view_left: float, view_size: Vector2, course_distance: float) -> void:
	var cursor := view_left
	var right := view_left + view_size.x
	while cursor < right:
		var distance := maxf(course_distance + cursor - view_left, 0.0)
		var biome := definition_at(distance)
		var next_theme_distance: float = (floor(distance / THEME_LENGTH) + 1.0) * THEME_LENGTH
		var segment_end := minf(right, cursor + maxf(next_theme_distance - distance, 1.0))
		var segment_size := Vector2(segment_end - cursor, view_size.y)
		canvas.draw_rect(Rect2(Vector2(cursor, 0.0), segment_size), biome.background_color)
		if not _draw_background_layers(canvas, biome, cursor, segment_size, distance):
			match biome.biome_id:
				&"cave": _draw_cave_backdrop(canvas, cursor, segment_size, distance, biome)
				&"haunted": _draw_haunted_backdrop(canvas, cursor, segment_size, distance, biome)
				_: _draw_classic_backdrop(canvas, cursor, segment_size, distance, biome)
		_draw_atlas_decorations(canvas, biome, cursor, segment_size, distance)
		cursor = segment_end

static func draw_surface_tiles(canvas: CanvasItem, biome: BiomeDefinition, ceiling: bool, start_x: float, end_x: float, canvas_origin_x: float, surface_y_at: Callable, tint := Color.WHITE, biome_distance_offset := 0.0) -> bool:
	if end_x <= start_x:
		return false
	var drew_any := false
	var world_tile_size := biome.tile_world_size if biome != null else Vector2i(int(TILE_WORLD_SIZE), int(TILE_WORLD_SIZE))
	if world_tile_size.x <= 0 or world_tile_size.y <= 0:
		return false
	var first_cell := floori((start_x - biome_distance_offset) / float(world_tile_size.x))
	var last_cell := ceili((end_x - biome_distance_offset) / float(world_tile_size.x))
	for cell in range(first_cell, last_cell):
		var x := float(cell * world_tile_size.x) + biome_distance_offset
		var tile_left := maxf(x, start_x)
		var tile_right := minf(x + float(world_tile_size.x), end_x)
		if tile_right <= tile_left:
			continue
		var selected_biome := biome if biome != null else definition_at((tile_left + tile_right) * 0.5 - biome_distance_offset)
		if selected_biome == null or selected_biome.tile_set == null:
			continue
		var source := selected_biome.tile_set.get_source(selected_biome.atlas_source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var candidates := _tiles_for_surface_cell(selected_biome, ceiling, tile_left, tile_right, surface_y_at)
		if candidates.is_empty():
			continue
		var texture_tile_size := source.texture_region_size
		var atlas := candidates[posmod(cell, candidates.size())]
		if not source.has_tile(atlas):
			continue
		var tile_tint := tint if tint != Color.WHITE else selected_biome.surface_tint
		var u0 := clampf((tile_left - x) / float(world_tile_size.x), 0.0, 1.0)
		var u1 := clampf((tile_right - x) / float(world_tile_size.x), 0.0, 1.0)
		var y_left := float(surface_y_at.call(tile_left, ceiling))
		var y_right := float(surface_y_at.call(tile_right, ceiling))
		var y_mid := float(surface_y_at.call((tile_left + tile_right) * 0.5, ceiling))
		var source_rect := Rect2(Vector2(atlas * texture_tile_size), Vector2(texture_tile_size))
		var step_threshold := _find_step_threshold(surface_y_at, ceiling, tile_left, tile_right, y_left, y_mid, y_right)
		if step_threshold > tile_left and step_threshold < tile_right:
			var step_fraction := (step_threshold - x) / float(world_tile_size.x)
			var left_surface := Callable(func(position_x: float, _ceiling: bool) -> float: return float(surface_y_at.call(minf(position_x, step_threshold - 0.01), ceiling)))
			var right_surface := Callable(func(position_x: float, _ceiling: bool) -> float: return float(surface_y_at.call(maxf(position_x, step_threshold + 0.01), ceiling)))
			_draw_surface_tile_quad(canvas, source.texture, source_rect, tile_left, step_threshold, x, world_tile_size.y, canvas_origin_x, left_surface, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, u0, step_fraction)
			_draw_surface_tile_quad(canvas, source.texture, source_rect, step_threshold, tile_right, x, world_tile_size.y, canvas_origin_x, right_surface, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, step_fraction, u1)
		else:
			_draw_surface_tile_quad(canvas, source.texture, source_rect, tile_left, tile_right, x, world_tile_size.y, canvas_origin_x, surface_y_at, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, u0, u1)
		drew_any = true
	return drew_any

static func _tiles_for_surface_cell(biome: BiomeDefinition, ceiling: bool, x_left: float, x_right: float, surface_y_at: Callable) -> Array[Vector2i]:
	var regular := biome.ceiling_surface_tiles if ceiling and not biome.ceiling_surface_tiles.is_empty() else (biome.floor_surface_tiles if not biome.floor_surface_tiles.is_empty() else biome.ceiling_surface_tiles)
	var left_y := float(surface_y_at.call(x_left + 0.5, ceiling))
	var right_y := float(surface_y_at.call(x_right - 0.5, ceiling))
	var mid_y := float(surface_y_at.call((x_left + x_right) * 0.5, ceiling))
	if absf(right_y - left_y) >= 4.0 and absf(mid_y - (left_y + right_y) * 0.5) >= 3.0 and not biome.ledge_edge_tiles.is_empty():
		return biome.ledge_edge_tiles
	if absf(right_y - left_y) > 4.0:
		var slope_tiles := biome.slope_down_tiles if right_y > left_y else biome.slope_up_tiles
		if not slope_tiles.is_empty():
			return slope_tiles
	var before_y := float(surface_y_at.call(x_left - 0.5, ceiling))
	var after_y := float(surface_y_at.call(x_right + 0.5, ceiling))
	if absf(before_y - left_y) > 4.0 or absf(after_y - right_y) > 4.0:
		if not biome.ledge_edge_tiles.is_empty():
			return biome.ledge_edge_tiles
	return regular

static func _find_step_threshold(surface_y_at: Callable, ceiling: bool, left: float, right: float, y_left: float, y_mid: float, y_right: float) -> float:
	if right - left < 8.0 or absf(y_right - y_left) < 4.0:
		return -1.0
	if absf(y_mid - (y_left + y_right) * 0.5) < 3.0:
		return -1.0
	var low := left
	var high := right
	var left_level := y_left
	for _i in range(12):
		var middle := (low + high) * 0.5
		var middle_level := float(surface_y_at.call(middle, ceiling))
		if is_equal_approx(middle_level, left_level):
			low = middle
		else:
			high = middle
	return (low + high) * 0.5

static func _draw_surface_tile_quad(canvas: CanvasItem, texture: Texture2D, source_rect: Rect2, left: float, right: float, tile_origin_x: float, tile_height: int, canvas_origin_x: float, surface_y_at: Callable, ceiling: bool, tint: Color, overlay: Color, flip_ceiling: bool, u0: float, u1: float) -> void:
	if right <= left:
		return
	var y0 := float(surface_y_at.call(left, ceiling))
	var y1 := float(surface_y_at.call(right, ceiling))
	var top0 := y0 - float(tile_height) if ceiling else y0
	var top1 := y1 - float(tile_height) if ceiling else y1
	var bottom0 := y0 if ceiling else y0 + float(tile_height)
	var bottom1 := y1 if ceiling else y1 + float(tile_height)
	var points := PackedVector2Array([
		Vector2(left - canvas_origin_x, top0), Vector2(right - canvas_origin_x, top1),
		Vector2(right - canvas_origin_x, bottom1), Vector2(left - canvas_origin_x, bottom0)
	])
	var source_u0 := source_rect.position.x + u0 * source_rect.size.x
	var source_u1 := source_rect.position.x + u1 * source_rect.size.x
	var v_top := source_rect.position.y
	var v_bottom := source_rect.position.y + source_rect.size.y
	if ceiling and flip_ceiling:
		var swap := v_top
		v_top = v_bottom
		v_bottom = swap
	var texture_size := Vector2(texture.get_size())
	var uvs := PackedVector2Array([
		Vector2(source_u0, v_top) / texture_size, Vector2(source_u1, v_top) / texture_size,
		Vector2(source_u1, v_bottom) / texture_size, Vector2(source_u0, v_bottom) / texture_size
	])
	canvas.draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), uvs, texture)
	if overlay.a > 0.0:
		canvas.draw_colored_polygon(points, overlay)

static func _draw_background_layers(canvas: CanvasItem, biome: BiomeDefinition, left: float, size: Vector2, distance: float) -> bool:
	var drew := false
	for index in range(biome.background_layers.size()):
		var texture := biome.background_layers[index]
		if texture == null:
			continue
		var tint := biome.background_layer_tints[index] if index < biome.background_layer_tints.size() else Color.WHITE
		var texture_width := maxf(texture.get_size().x, 1.0)
		var parallax_offset := fposmod(distance * (0.04 + float(index) * 0.025), texture_width)
		var layer_rect := Rect2(left - parallax_offset, 0.0, size.x + parallax_offset, size.y)
		canvas.draw_texture_rect(texture, layer_rect, true, tint)
		drew = true
	return drew

static func _draw_atlas_decorations(canvas: CanvasItem, biome: BiomeDefinition, left: float, size: Vector2, distance: float) -> void:
	if biome == null or biome.decoration_tiles.is_empty() or biome.tile_set == null:
		return
	var source := biome.tile_set.get_source(biome.atlas_source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return
	var region := Vector2(source.texture_region_size)
	if region.x <= 0.0 or region.y <= 0.0:
		return
	var first_index := floori((distance + left) / 224.0)
	var last_index := ceili((distance + left + size.x) / 224.0)
	for index in range(first_index, last_index):
		var world_x := float(index) * 224.0
		var x := left + world_x - distance
		var tile := biome.decoration_tiles[posmod(index, biome.decoration_tiles.size())]
		if not source.has_tile(tile):
			continue
		var atlas_region := Rect2(Vector2(tile) * region, region)
		var destination := Rect2(x, size.y * 0.24 + float(posmod(index, 3)) * 18.0, 30.0, 30.0)
		canvas.draw_texture_rect_region(source.texture, destination, atlas_region, biome.surface_tint)

static func _draw_classic_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, biome: BiomeDefinition) -> void:
	for i in range(16):
		var x := left + fposmod(float(i * 97) + distance * 0.12, size.x)
		canvas.draw_circle(Vector2(x, 48.0 + float((i * 43) % maxi(int(size.y - 80.0), 1))), 1.4, biome.accent_color)

static func _draw_cave_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, biome: BiomeDefinition) -> void:
	if size.x < 48.0:
		canvas.draw_rect(Rect2(Vector2(left, 0.0), size), biome.background_color)
		return
	for layer in range(3):
		var amplitude := size.y * (0.13 + 0.055 * float(layer))
		var base_y := size.y * (0.32 + 0.18 * float(layer))
		var points := PackedVector2Array()
		for i in range(13):
			var x := left + float(i) * size.x / 12.0
			var phase := (x + distance * (0.06 + 0.04 * float(layer))) * (0.003 + float(layer) * 0.0008)
			var ridge_y := clampf(base_y + sin(phase) * amplitude + cos(phase * 0.37) * amplitude * 0.4, size.y * 0.04, size.y * 0.94)
			points.append(Vector2(x, ridge_y))
		points.append(Vector2(left + size.x, size.y))
		points.append(Vector2(left, size.y))
		var color := biome.layer_colors[layer % biome.layer_colors.size()]
		canvas.draw_colored_polygon(points, color)
	for i in range(4):
		var x := left + fposmod(float(i * 241) + distance * 0.045, size.x)
		var y := size.y * (0.31 + float((i * 13) % 24) / 100.0)
		var crystal := biome.accent_color.lerp(biome.background_color, 0.48)
		crystal.a = 0.68
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 6.0), Vector2(x + 5.0, y), Vector2(x, y + 8.0), Vector2(x - 5.0, y)]), crystal)
		canvas.draw_line(Vector2(x, y + 8.0), Vector2(x, y + 12.0), crystal, 1.2, true)

static func _draw_haunted_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, biome: BiomeDefinition) -> void:
	var moon_center := Vector2(left + size.x * 0.77, size.y * 0.2)
	canvas.draw_circle(moon_center, minf(size.x, size.y) * 0.075, biome.accent_color)
	canvas.draw_circle(moon_center + Vector2(9.0, -5.0), minf(size.x, size.y) * 0.069, biome.background_color)
	for i in range(6):
		var x := left + fposmod(float(i * 197) + distance * 0.035, size.x)
		# Keep the skyline in the playable corridor's background. It must be
		# visible above the floor in both the SP and MP camera layouts; placing
		# its base near the viewport bottom lets the course occlude it entirely.
		var base_y := size.y * (0.54 + float(i % 3) * 0.025)
		var width := 24.0 + float(i % 3) * 10.0
		var height := size.y * (0.14 + float((i + 1) % 3) * 0.035)
		var tint := biome.layer_colors[i % biome.layer_colors.size()]
		canvas.draw_rect(Rect2(x, base_y - height, width, height), tint)
		canvas.draw_rect(Rect2(x - 4.0, base_y - height - 6.0, width + 8.0, 7.0), tint)
