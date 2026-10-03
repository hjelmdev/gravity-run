extends RefCounted
class_name BiomeRenderer
## Shared, distance-addressed biome presentation. Biomes only affect drawing.

const CLASSIC: BiomeDefinition = preload("res://assets/biomes/definitions/classic.tres")
const CAVE: BiomeDefinition = preload("res://assets/biomes/definitions/cave.tres")
const HAUNTED: BiomeDefinition = preload("res://assets/biomes/definitions/haunted.tres")
const THEME_LENGTH := 4800.0
const CYCLE_LENGTH := THEME_LENGTH * 3.0
const TILE_WORLD_SIZE := 64.0
const LOGICAL_BACKGROUND_HEIGHT := 540.0

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
		var layout_size := Vector2(segment_size.x, minf(view_size.y, LOGICAL_BACKGROUND_HEIGHT))
		var fragment_offset := cursor - view_left
		canvas.draw_rect(Rect2(Vector2(cursor, 0.0), segment_size), biome.background_color)
		var has_layers := _draw_background_layers(canvas, biome, cursor, layout_size, distance, view_left, course_distance)
		if not has_layers:
			match biome.biome_id:
				&"cave": _draw_cave_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, biome)
				&"haunted": pass
				_: _draw_classic_backdrop(canvas, cursor, layout_size, course_distance * 0.12 + fragment_offset, biome)
		if biome.biome_id == &"haunted":
			_draw_haunted_backdrop(canvas, cursor, layout_size, distance, view_left, Vector2(view_size.x, layout_size.y), course_distance, biome)
		_draw_atlas_decorations(canvas, biome, cursor, layout_size, distance)
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

static func _draw_background_layers(canvas: CanvasItem, biome: BiomeDefinition, left: float, size: Vector2, distance: float, view_left: float, camera_course_distance: float) -> bool:
	var drew := false
	for index in range(biome.background_layers.size()):
		var texture := biome.background_layers[index]
		if texture == null:
			continue
		var tint := biome.background_layer_tints[index] if index < biome.background_layer_tints.size() else Color.WHITE
		var height_ratio := biome.background_layer_height_ratios[index] if index < biome.background_layer_height_ratios.size() else 1.0
		var y_ratio := biome.background_layer_y_ratios[index] if index < biome.background_layer_y_ratios.size() else 0.0
		var parallax := biome.background_layer_parallax[index] if index < biome.background_layer_parallax.size() else 0.06 + float(index) * 0.025
		if height_ratio <= 0.0 or parallax <= 0.0:
			continue
		var source_size := texture.get_size()
		var tile_height := size.y * height_ratio
		var tile_width := maxf(tile_height * source_size.x / maxf(source_size.y, 1.0), 1.0)
		# Course origin controls slow parallax motion; fragment offset remains 1:1
		# so splitting a viewport at a theme boundary cannot resize the artwork.
		var parallax_left := camera_course_distance * parallax + (left - view_left)
		var parallax_right := parallax_left + size.x
		var first_tile := floori(parallax_left / tile_width)
		var last_tile := ceili(parallax_right / tile_width)
		var destination_y := size.y * y_ratio
		for tile_index in range(first_tile, last_tile):
			var tile_left := float(tile_index) * tile_width
			var clip_left := maxf(tile_left, parallax_left)
			var clip_right := minf(tile_left + tile_width, parallax_right)
			if clip_right <= clip_left:
				continue
			var u0 := (clip_left - tile_left) / tile_width
			var u1 := (clip_right - tile_left) / tile_width
			var source_rect := Rect2(u0 * source_size.x, 0.0, (u1 - u0) * source_size.x, source_size.y)
			var dest_left := view_left + (clip_left - camera_course_distance * parallax)
			var dest_width := clip_right - clip_left
			var dest := Rect2(dest_left, destination_y, dest_width, tile_height)
			canvas.draw_texture_rect_region(texture, dest, source_rect, tint)
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
	var first_index := floori(distance / 224.0)
	var last_index := ceili((distance + size.x) / 224.0)
	for index in range(first_index, last_index):
		var world_x := float(index) * 224.0
		var x := left + world_x - distance
		var tile := biome.decoration_tiles[posmod(index, biome.decoration_tiles.size())]
		if not source.has_tile(tile):
			continue
		var atlas_region := Rect2(Vector2(tile) * region, region)
		var destination := Rect2(x, size.y * 0.24 + float(posmod(index, 3)) * 18.0, 30.0, 30.0)
		if destination.position.x < left or destination.end.x > left + size.x:
			continue
		canvas.draw_texture_rect_region(source.texture, destination, atlas_region, biome.surface_tint)

static func _draw_classic_backdrop(canvas: CanvasItem, left: float, size: Vector2, parallax_left: float, biome: BiomeDefinition) -> void:
	for point in _landmarks_in_course(parallax_left, parallax_left + size.x, 82.0, 13):
		var screen_x := left + float(point.x) - parallax_left
		var radius := 0.8 + point.y * 0.9
		if screen_x - radius < left or screen_x + radius > left + size.x:
			continue
		var y := size.y * (0.10 + point.y * 0.54)
		var color := biome.accent_color
		color.a = 0.38 + point.y * 0.30
		canvas.draw_circle(Vector2(screen_x, y), radius, color)

static func _draw_cave_backdrop(canvas: CanvasItem, left: float, size: Vector2, camera_course_distance: float, fragment_offset: float, biome: BiomeDefinition) -> void:
	for layer in range(3):
		var amplitude := size.y * (0.13 + 0.055 * float(layer))
		var base_y := size.y * (0.32 + 0.18 * float(layer))
		var points := PackedVector2Array()
		var spacing := 48.0
		var parallax := 0.16 + 0.07 * float(layer)
		var layer_parallax_left := camera_course_distance * parallax + fragment_offset
		var first_sample := floori(layer_parallax_left / spacing)
		var last_sample := ceili((layer_parallax_left + size.x) / spacing)
		for i in range(first_sample, last_sample + 1):
			var course_x := float(i) * spacing
			var x := left + course_x - layer_parallax_left
			var phase := course_x * 0.003
			var ridge_y := clampf(base_y + sin(phase) * amplitude + cos(phase * 0.37) * amplitude * 0.4, size.y * 0.04, size.y * 0.94)
			points.append(Vector2(x, ridge_y))
		if points.is_empty():
			continue
		points.append(Vector2(left + size.x, size.y))
		points.append(Vector2(left, size.y))
		var color := biome.layer_colors[layer % biome.layer_colors.size()]
		var clipped := PackedVector2Array([Vector2(left, _cave_ridge_y(layer_parallax_left, size.y, layer)), Vector2(left + size.x, _cave_ridge_y(layer_parallax_left + size.x, size.y, layer))])
		for point_index in range(points.size()):
			var point := points[point_index]
			if point.x > left and point.x < left + size.x:
				clipped.insert(clipped.size() - 1, point)
		clipped.append(Vector2(left + size.x, size.y))
		clipped.append(Vector2(left, size.y))
		canvas.draw_colored_polygon(clipped, color)
	var crystal_parallax_left := camera_course_distance * 0.11 + fragment_offset
	for point in _landmarks_in_course(crystal_parallax_left, crystal_parallax_left + size.x, 193.0, 51):
		var x := left + float(point.x) - crystal_parallax_left
		if x - 6.0 < left or x + 6.0 > left + size.x:
			continue
		var y := size.y * (0.28 + point.y * 0.18)
		var crystal := biome.accent_color.lerp(biome.background_color, 0.48)
		crystal.a = 0.68
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 6.0), Vector2(x + 5.0, y), Vector2(x, y + 8.0), Vector2(x - 5.0, y)]), crystal)
		canvas.draw_line(Vector2(x, y + 8.0), Vector2(x, y + 12.0), crystal, 1.2, true)

static func _cave_ridge_y(parallax_x: float, viewport_height: float, layer: int) -> float:
	var amplitude := viewport_height * (0.13 + 0.055 * float(layer))
	var base_y := viewport_height * (0.32 + 0.18 * float(layer))
	var phase := parallax_x * 0.003
	return clampf(base_y + sin(phase) * amplitude + cos(phase * 0.37) * amplitude * 0.4, viewport_height * 0.04, viewport_height * 0.94)

static func _draw_haunted_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, view_left: float, full_view_size: Vector2, camera_course_distance: float, biome: BiomeDefinition) -> void:
	# Moon and silhouettes are tied to the biome's course interval, not the
	# width of the fragment left after clipping at a theme boundary.
	var haunted_start := floori(distance / CYCLE_LENGTH) * CYCLE_LENGTH + THEME_LENGTH * 2.0
	var moon_parallax := 0.055
	var moon_anchor := haunted_start * moon_parallax + full_view_size.x * 0.74
	var moon_x_screen := view_left + moon_anchor - camera_course_distance * moon_parallax
	var moon_radius := minf(full_view_size.x, full_view_size.y) * 0.055
	if moon_x_screen - moon_radius >= left and moon_x_screen + moon_radius <= left + size.x:
		var moon_center := Vector2(moon_x_screen, full_view_size.y * 0.50)
		var halo := Color(0.66, 0.61, 0.91, 0.075)
		canvas.draw_circle(moon_center, moon_radius * 1.6, halo)
		canvas.draw_circle(moon_center, moon_radius, Color(0.84, 0.81, 0.93, 0.90))
		canvas.draw_circle(moon_center + Vector2(moon_radius * 0.30, -moon_radius * 0.13), moon_radius * 0.88, biome.background_color)
	var silhouette_parallax_left := camera_course_distance * 0.22 + (left - view_left)
	for point in _landmarks_in_course(silhouette_parallax_left, silhouette_parallax_left + size.x, 247.0, 87):
		var center_x := view_left + float(point.x) - camera_course_distance * 0.22
		var width := 30.0 + point.y * 25.0
		var height := full_view_size.y * (0.09 + point.y * 0.09)
		var base_y := full_view_size.y * (0.62 + point.y * 0.055)
		if center_x - width * 0.5 < left or center_x + width * 0.5 > left + size.x:
			continue
		var tint := biome.layer_colors[1]
		tint.a = 0.78
		var x := center_x - width * 0.5
		canvas.draw_rect(Rect2(x + width * 0.18, base_y - height * 0.68, width * 0.64, height * 0.68), tint)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, base_y - height * 0.68), Vector2(center_x, base_y - height), Vector2(x + width, base_y - height * 0.68)]), tint)
		# Bare branch-like spires stay faint and well behind the play surface.
		var branch := Color(0.24, 0.20, 0.34, 0.66)
		canvas.draw_line(Vector2(center_x, base_y - height * 0.18), Vector2(center_x - width * 0.30, base_y - height * 0.48), branch, 2.0, true)
		canvas.draw_line(Vector2(center_x, base_y - height * 0.28), Vector2(center_x + width * 0.31, base_y - height * 0.61), branch, 2.0, true)
		canvas.draw_line(Vector2(center_x - width * 0.19, base_y - height * 0.39), Vector2(center_x - width * 0.35, base_y - height * 0.53), branch, 1.2, true)
		canvas.draw_line(Vector2(center_x + width * 0.20, base_y - height * 0.51), Vector2(center_x + width * 0.36, base_y - height * 0.66), branch, 1.2, true)
	# Restrained ground-hugging fog across the playable corridor.
	for fog_index in range(2):
		var y := full_view_size.y * (0.68 + fog_index * 0.045)
		var fog := Color(0.62, 0.59, 0.77, 0.045)
		canvas.draw_rect(Rect2(left, y, size.x, full_view_size.y * 0.055), fog)

static func _landmarks_in_course(course_start: float, course_end: float, period: float, salt: int) -> Array[Vector2]:
	## Deterministic course-space point lattice; segmentation or viewport width
	## cannot alter a point's position, count, or vertical placement.
	var result: Array[Vector2] = []
	if period <= 0.0 or course_end <= course_start:
		return result
	var first := floori(course_start / period) - 1
	var last := ceili(course_end / period) + 1
	for cell in range(first, last + 1):
		var point := _landmark_for_cell(cell, period, salt)
		if point.x >= course_start and point.x < course_end:
			result.append(point)
	return result

static func _landmark_for_cell(cell: int, period: float, salt: int) -> Vector2:
	var raw := posmod(cell * 1103515245 + salt * 12345 + 1013904223, 2147483647)
	var next_raw := posmod(raw * 48271 + 1, 2147483647)
	var jitter := float(raw) / 2147483647.0
	var vertical := float(next_raw) / 2147483647.0
	return Vector2((float(cell) + 0.18 + jitter * 0.64) * period, vertical)
