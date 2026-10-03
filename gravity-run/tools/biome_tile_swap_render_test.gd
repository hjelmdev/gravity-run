extends SceneTree

const Definition := preload("res://biomes/biome_definition.gd")
const Probe := preload("res://tools/biome_atlas_render_probe.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	source_image.fill(Color("e72aa8"))
	var texture := ImageTexture.create_from_image(source_image)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(64, 64)
	atlas.create_tile(Vector2i.ZERO)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(64, 64)
	tile_set.add_source(atlas, 0)
	var biome := Definition.new() as BiomeDefinition
	biome.biome_id = &"replacement_render_test"
	biome.tile_set = tile_set
	biome.floor_surface_tiles = [Vector2i.ZERO]
	biome.tile_world_size = Vector2i(64, 64)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe := Probe.new()
	probe.biome = biome
	viewport.add_child(probe)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var failures: Array[String] = []
	if image == null or image.is_empty():
		failures.append("GPU renderer did not return atlas test pixels")
	else:
		var atlas_pixel := image.get_pixel(92, 96)
		var outside_left := image.get_pixel(50, 96)
		var outside_right := image.get_pixel(140, 96)
		if atlas_pixel.r < 0.75 or atlas_pixel.b < 0.35 or atlas_pixel.a < 0.9:
			failures.append("assigned replacement texture did not render on the supported floor: %s" % str(atlas_pixel))
		if outside_left.a > 0.05 or outside_right.a > 0.05:
			failures.append("textured quad escaped its non-grid supported interval: left=%s right=%s" % [str(outside_left), str(outside_right)])
	if failures.is_empty():
		print("BIOME_ATLAS_GPU_SWAP_PASS texture pixels replace fallback and remain clipped to [63,129]")
	else:
		for failure in failures:
			push_error(failure)
	viewport.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
