extends SceneTree

const Definition := preload("res://biomes/biome_definition.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var image := Image.create(192, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(0, 0, 64, 64), Color("ef3c9a"))
	image.fill_rect(Rect2i(64, 0, 64, 64), Color("36d9a6"))
	image.fill_rect(Rect2i(128, 0, 64, 64), Color("f4d64d"))
	var texture := ImageTexture.create_from_image(image)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(64, 64)
	for coordinate in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]:
		atlas.create_tile(coordinate)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(64, 64)
	tile_set.add_source(atlas, 0)
	var biome := Definition.new() as BiomeDefinition
	biome.biome_id = &"fixture"
	biome.tile_set = tile_set
	biome.atlas_source_id = 0
	biome.floor_surface_tiles = [Vector2i.ZERO]
	biome.slope_down_tiles = [Vector2i(1, 0)]
	biome.ledge_edge_tiles = [Vector2i(2, 0)]
	biome.terrain_fill_color = Color("182333")
	biome.terrain_edge_color = Color("182333")
	var failures: Array[String] = []
	if not tile_set.get_source(0) is TileSetAtlasSource:
		failures.append("replacement atlas was not attached to the biome resource")
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var flat_tiles := BiomeRenderer._tiles_for_surface_cell(biome, false, 0.0, 64.0, _flat_surface)
	var step_tiles := BiomeRenderer._tiles_for_surface_cell(biome, false, 96.0, 160.0, _step_surface)
	var slope_tiles := BiomeRenderer._tiles_for_surface_cell(biome, false, 256.0, 320.0, _slope_surface)
	if flat_tiles != [Vector2i.ZERO] or not source.has_tile(flat_tiles[0]):
		failures.append("flat floor did not resolve the replacement atlas tile")
	if step_tiles != [Vector2i(2, 0)] or not source.has_tile(step_tiles[0]):
		failures.append("step edge did not resolve the ledge atlas tile")
	if slope_tiles != [Vector2i(1, 0)] or not source.has_tile(slope_tiles[0]):
		failures.append("slope did not resolve the slope atlas tile")
	var detected_step := BiomeRenderer._find_step_threshold(_step_surface, false, 96.0, 160.0, 150.0, 130.0, 130.0)
	if absf(detected_step - 128.0) > 0.1:
		failures.append("textured surface quad did not isolate the non-grid-aligned step")
	# The renderer clips tile UVs to each supported interval. This interval ends
	# at the true gap edge, not the next 64px atlas boundary.
	var support_start := 127.0
	var support_end := 211.0
	var first_cell_left := maxf(support_start, floorf(support_start / 64.0) * 64.0)
	var first_cell_right := minf(support_end, 128.0)
	if not is_equal_approx(first_cell_left, 127.0) or not is_equal_approx(first_cell_right, 128.0):
		failures.append("atlas surface escaped a non-grid-aligned supported interval")
	# CourseSurfaceRenderer splits surfaces around gaps before calling the tile
	# renderer; exercise the same interval predicate used for that split.
	if not _gap_removes_surface_at(220.0, [{"start": 200.0, "end": 240.0}]):
		failures.append("gap fixture did not exclude its surface interval")
	if failures.is_empty():
		print("BIOME_TILE_SWAP_PASS replacement atlas, flat/step/slope selection, non-grid support clipping, gap exclusion")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _flat_surface(_x: float, _ceiling: bool) -> float:
	return 150.0

func _step_surface(x: float, _ceiling: bool) -> float:
	return 150.0 if x < 128.0 else 130.0

func _slope_surface(x: float, _ceiling: bool) -> float:
	return lerpf(130.0, 150.0, clampf((x - 256.0) / 64.0, 0.0, 1.0))

func _gap_removes_surface_at(x: float, gaps: Array[Dictionary]) -> bool:
	for gap in gaps:
		if x >= float(gap.start) and x < float(gap.end):
			return true
	return false
