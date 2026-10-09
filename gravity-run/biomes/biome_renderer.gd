extends RefCounted
class_name BiomeRenderer
## Shared, distance-addressed biome presentation. Biomes only affect drawing.

const CLASSIC: BiomeDefinition = preload("res://assets/biomes/definitions/classic.tres")
const CAVE: BiomeDefinition = preload("res://assets/biomes/definitions/cave.tres")
const HAUNTED: BiomeDefinition = preload("res://assets/biomes/definitions/haunted.tres")
const LAVA: BiomeDefinition = preload("res://assets/biomes/definitions/lava.tres")
## Campaign-only presentation biome (world 1). Never part of the rotation;
## generation treats it as classic.
const MEADOW: BiomeDefinition = preload("res://assets/biomes/definitions/meadow.tres")
## Campaign-only presentation biome (world 2). Same tiles and generation as
## `cave`, plus a livelier backdrop. Never part of the rotation.
const CAVE_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/cave_campaign.tres")
## Campaign-only presentation biome (world 3). Same tiles and generation as
## `haunted`, plus a livelier backdrop. Never part of the rotation.
const HAUNTED_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/haunted_campaign.tres")
## Campaign-only presentation biome (world 4). Same generation as `lava`, plus
## a dedicated backdrop. Never part of the rotation.
const VOLCANO_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/volcano_campaign.tres")
## Campaign-only presentation biome (world 5). Generation is the cave mix.
const FROST_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/frost_campaign.tres")
## Campaign-only presentation biome (world 6). Generation is the classic mix.
const CLOUDS_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/clouds_campaign.tres")
## Campaign-only presentation biome (world 7). Generation is the classic mix.
const DESERT_CAMPAIGN: BiomeDefinition = preload("res://assets/biomes/definitions/desert_campaign.tres")
const GENERATOR_VERSION_14 := 14
const GENERATOR_VERSION_16 := 16
const GENERATOR_VERSION_21 := 21
const THEME_LENGTH := 4800.0
const CYCLE_LENGTH := THEME_LENGTH * 3.0
const GEN14_CYCLE_LENGTH := THEME_LENGTH * 4.0
const TILE_WORLD_SIZE := 64.0
const LOGICAL_BACKGROUND_HEIGHT := 540.0

## Presentation/runtime-filter lock for campaign stages. Set by the singleplayer
## scene from its ruleset at run start and cleared by every non-campaign entry
## point, so endless runs and multiplayer always see the normal rotation.
static var _locked_definition: BiomeDefinition = null

static func set_locked_biome(biome_id: StringName) -> void:
	match biome_id:
		&"classic": _locked_definition = CLASSIC
		&"cave": _locked_definition = CAVE
		&"haunted": _locked_definition = HAUNTED
		&"lava": _locked_definition = LAVA
		&"meadow": _locked_definition = MEADOW
		&"cave_campaign": _locked_definition = CAVE_CAMPAIGN
		&"haunted_campaign": _locked_definition = HAUNTED_CAMPAIGN
		&"volcano_campaign": _locked_definition = VOLCANO_CAMPAIGN
		&"frost_campaign": _locked_definition = FROST_CAMPAIGN
		&"clouds_campaign": _locked_definition = CLOUDS_CAMPAIGN
		&"desert_campaign": _locked_definition = DESERT_CAMPAIGN
		_: _locked_definition = null

static func locked_biome_id() -> StringName:
	return _locked_definition.biome_id if _locked_definition != null else &""

static func locked_definition() -> BiomeDefinition:
	return _locked_definition

## The pixel palette of the locked (campaign) biome, or null when it is not a
## pixel-style biome. Hazards and terrain use it to pick their pixel art.
static func locked_pixel_palette() -> PixelPalette:
	return _locked_definition.pixel_palette if _locked_definition != null else null

static func definition_for_id(biome_id: StringName) -> BiomeDefinition:
	match biome_id:
		&"meadow": return MEADOW
		&"cave_campaign": return CAVE_CAMPAIGN
		&"haunted_campaign": return HAUNTED_CAMPAIGN
		&"volcano_campaign": return VOLCANO_CAMPAIGN
		&"frost_campaign": return FROST_CAMPAIGN
		&"clouds_campaign": return CLOUDS_CAMPAIGN
		&"desert_campaign": return DESERT_CAMPAIGN
		&"cave": return CAVE
		&"haunted": return HAUNTED
		&"lava": return LAVA
		_: return CLASSIC

static func definition_at(distance: float) -> BiomeDefinition:
	return definition_for_generator(distance, GENERATOR_VERSION_14 - 1)

## Endless runs, seeds and multiplayer draw the rotation with the campaign's
## pixel looks (the meadow for classic, and so on). Presentation only: the
## encounter rules still see the generation biome (biome_id_for_generator).
static var pixel_rotation := true

static func _look(definition: BiomeDefinition) -> BiomeDefinition:
	if not pixel_rotation:
		return definition
	match definition.biome_id:
		&"cave": return CAVE_CAMPAIGN
		&"haunted": return HAUNTED_CAMPAIGN
		&"lava": return VOLCANO_CAMPAIGN
		_: return MEADOW

static func definition_for_generator(distance: float, generator_version: int) -> BiomeDefinition:
	if _locked_definition != null:
		return _locked_definition
	var cycle_length := GEN14_CYCLE_LENGTH if generator_version >= GENERATOR_VERSION_14 else CYCLE_LENGTH
	var slot := int(floor(fposmod(maxf(distance, 0.0), cycle_length) / THEME_LENGTH))
	match slot:
		1: return _look(CAVE)
		2: return _look(HAUNTED)
		3: return _look(LAVA if generator_version >= GENERATOR_VERSION_14 else CLASSIC)
		_: return _look(CLASSIC)

## Where hazards of the current run sit on the course: world x of course
## distance 0, the seed's biome start offset and the generator version. Set
## by the singleplayer scene and the race presentation at run start, so a
## hazard can find the pixel look of the biome it stands in.
static var _frame_start_x := 180.0
static var _frame_offset := 0.0
static var _frame_version := GENERATOR_VERSION_14 - 1

static func set_world_frame(course_start_x: float, biome_start_offset: float, generator_version: int) -> void:
	_frame_start_x = course_start_x
	_frame_offset = biome_start_offset
	_frame_version = generator_version

## The biome look at a world x of the current run (the locked one in the
## campaign).
static func definition_at_world_x(world_x: float) -> BiomeDefinition:
	return definition_for_generator(maxf(world_x - _frame_start_x, 0.0) + _frame_offset, _frame_version)

## The pixel palette at a world x of the current run, or null when that biome
## is not drawn in pixel art.
static func pixel_palette_at_world_x(world_x: float) -> PixelPalette:
	return definition_at_world_x(world_x).pixel_palette

static func start_biome_slot_for_seed(seed_value: int, generator_version: int) -> int:
	if generator_version < GENERATOR_VERSION_16 or seed_value <= 0:
		return 0
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(str(seed_value).to_utf8_buffer())
	var digest := context.finish()
	return int(digest[0] & 3)

static func start_biome_offset_for_seed(seed_value: int, generator_version: int) -> float:
	return float(start_biome_slot_for_seed(seed_value, generator_version)) * THEME_LENGTH

static func biome_id_for_seed(seed_value: int, distance: float, generator_version: int) -> String:
	return biome_id_for_generator(distance + start_biome_offset_for_seed(seed_value, generator_version), generator_version)

static func biome_id_at(distance: float) -> String:
	return biome_id_for_generator(distance, GENERATOR_VERSION_14 - 1)

## Campaign presentation biomes and the generation biome their stages use.
## Encounter rules (ghosts only in "haunted", lava only in "lava") must see
## the generation biome, not the look, or a locked campaign stage loses them.
const GENERATION_BIOME := {
	&"meadow": "classic", &"cave_campaign": "cave", &"haunted_campaign": "haunted",
	&"volcano_campaign": "lava", &"frost_campaign": "cave", &"clouds_campaign": "classic",
	&"desert_campaign": "classic",
}

## The generation biome at a distance (never a campaign presentation biome).
static func biome_id_for_generator(distance: float, generator_version: int) -> String:
	var biome_id := definition_for_generator(distance, generator_version).biome_id
	return str(GENERATION_BIOME.get(biome_id, String(biome_id)))

static func cycle_length_for_generator(generator_version: int) -> float:
	return GEN14_CYCLE_LENGTH if generator_version >= GENERATOR_VERSION_14 else CYCLE_LENGTH

static func course_distance_at_world_x(world_x: float, course_start_x: float) -> float:
	## SP and manifest-backed MP share this world-to-course coordinate contract.
	return maxf(world_x - course_start_x, 0.0)

static func draw_backdrop(canvas: CanvasItem, view_left: float, view_size: Vector2, course_distance: float, generator_version: int = GENERATOR_VERSION_14 - 1, presentation_time_seconds: float = 0.0) -> void:
	var cursor := view_left
	var right := view_left + view_size.x
	var cycle_length := cycle_length_for_generator(generator_version)
	while cursor < right:
		var distance := maxf(course_distance + cursor - view_left, 0.0)
		var biome := definition_for_generator(distance, generator_version)
		var cycle_start: float = floor(distance / cycle_length) * cycle_length
		var next_theme_distance: float = cycle_start + (floor(fposmod(distance, cycle_length) / THEME_LENGTH) + 1.0) * THEME_LENGTH
		var segment_end := minf(right, cursor + maxf(next_theme_distance - distance, 1.0))
		if _locked_definition != null:
			# One biome for the whole view: no theme seams to split at.
			segment_end = right
		var segment_size := Vector2(segment_end - cursor, view_size.y)
		var layout_size := Vector2(segment_size.x, minf(view_size.y, LOGICAL_BACKGROUND_HEIGHT))
		var fragment_offset := cursor - view_left
		canvas.draw_rect(Rect2(Vector2(cursor, 0.0), segment_size), biome.background_color)
		var has_layers := _draw_background_layers(canvas, biome, cursor, layout_size, distance, view_left, course_distance)
		if not has_layers and biome.pixel_palette != null and biome.pixel_palette.backdrop:
			_draw_pixel_backdrop(canvas, cursor, layout_size, view_left, course_distance, presentation_time_seconds, biome.pixel_palette)
		elif not has_layers:
			match biome.biome_id:
				&"cave": _draw_cave_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, biome)
				&"cave_campaign":
					_draw_cave_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, biome, false)
					_draw_cave_campaign_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, presentation_time_seconds)
				&"haunted": pass
				&"volcano_campaign": pass
				&"lava": _draw_lava_backdrop(canvas, cursor, layout_size, distance, view_left, course_distance, biome)
				_: _draw_classic_backdrop(canvas, cursor, layout_size, course_distance * 0.12 + fragment_offset, biome)
		var pixel_backdrop := biome.pixel_palette != null and biome.pixel_palette.backdrop
		if pixel_backdrop:
			pass
		elif biome.biome_id == &"volcano_campaign":
			_draw_volcano_campaign_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, presentation_time_seconds)
		elif biome.biome_id == &"haunted_campaign":
			_draw_haunted_campaign_backdrop(canvas, cursor, layout_size, course_distance, fragment_offset, presentation_time_seconds)
		elif biome.biome_id == &"haunted":
			_draw_haunted_backdrop(canvas, cursor, layout_size, distance, view_left, Vector2(view_size.x, layout_size.y), course_distance, biome, cycle_length)
		_draw_atlas_decorations(canvas, biome, cursor, layout_size, distance)
		if generator_version >= GENERATOR_VERSION_21:
			_draw_weather_layer(canvas, biome, cursor, layout_size, distance, course_distance + fragment_offset, presentation_time_seconds)
		cursor = segment_end

static func _draw_weather_layer(canvas: CanvasItem, biome: BiomeDefinition, left: float, size: Vector2, distance: float, view_course_left: float, presentation_time_seconds: float) -> void:
	## Small deterministic primitives only: no per-frame nodes, textures, or RNG.
	## Lava ember polygons are tiny CPU-side arrays bounded by visible cells.
	## Cell identity uses course position; every motif stays inside its biome fragment.
	if size.x <= 8.0 or size.y <= 32.0 or biome.biome_id == &"cave_campaign" or biome.biome_id == &"haunted_campaign" or biome.biome_id == &"volcano_campaign" or biome.biome_id == &"frost_campaign" or biome.biome_id == &"clouds_campaign" or biome.biome_id == &"desert_campaign":
		return
	var kind := str(biome.biome_id)
	var period := 138.0
	var speed := 14.0
	var salt := 3101
	match kind:
		"cave":
			period = 96.0
			speed = 8.0
			salt = 3119
		"haunted":
			period = 156.0
			speed = 18.0
			salt = 3137
		"meadow":
			period = 120.0
			speed = 16.0
			salt = 3181
		"lava":
			period = 94.0
			speed = 11.0
			salt = 3163
	var drift := maxf(presentation_time_seconds, 0.0) * speed
	var first_cell := floori((view_course_left - drift - period) / period)
	var last_cell := ceili((view_course_left + size.x - drift + period) / period)
	for cell in range(first_cell, last_cell + 1):
		var motif := _landmark_for_cell(cell, period, salt)
		var course_x := motif.x + drift
		var x := weather_canvas_x(left, course_x, view_course_left)
		# draw_backdrop renders adjacent biomes as sibling fragments without a
		# canvas scissor. Keep every primitive wholly inside this fragment; merely
		# clamping its center still lets antialiasing/line width bleed across a seam.
		var extent := weather_primitive_extent(kind)
		if not weather_primitive_fits_fragment(left, size.x, x, extent):
			continue
		var edge_fade := clampf(minf(x - left, left + size.x - x) / 42.0, 0.0, 1.0)
		if edge_fade <= 0.0:
			continue
		var y := size.y * (0.17 + motif.y * 0.56)
		if kind == "haunted":
			# Keep the fog in the shared play corridor instead of losing most
			# motifs behind the usual solid ceiling/floor silhouettes.
			y = size.y * (0.44 + motif.y * 0.18)
		match kind:
			"cave":
				var frost := Color(0.72, 0.95, 1.0, 0.43 * edge_fade)
				var frost_edge := Color(0.87, 0.98, 1.0, 0.28 * edge_fade)
				# A compact six-arm ice crystal (about 12 px across), rather than
				# isolated pinpricks. It stays well below coin/hazard scale.
				canvas.draw_line(Vector2(x - 6.0, y), Vector2(x + 6.0, y), frost, 1.8, true)
				canvas.draw_line(Vector2(x - 3.0, y - 5.2), Vector2(x + 3.0, y + 5.2), frost, 1.8, true)
				canvas.draw_line(Vector2(x - 3.0, y + 5.2), Vector2(x + 3.0, y - 5.2), frost, 1.8, true)
				canvas.draw_line(Vector2(x - 6.0, y), Vector2(x - 3.8, y - 1.8), frost_edge, 1.2, true)
				canvas.draw_line(Vector2(x - 6.0, y), Vector2(x - 3.8, y + 1.8), frost_edge, 1.2, true)
				canvas.draw_line(Vector2(x + 6.0, y), Vector2(x + 3.8, y - 1.8), frost_edge, 1.2, true)
				canvas.draw_line(Vector2(x + 6.0, y), Vector2(x + 3.8, y + 1.8), frost_edge, 1.2, true)
				canvas.draw_circle(Vector2(x, y), 1.1, Color(0.91, 0.99, 1.0, 0.62 * edge_fade))
			"haunted":
				var fog := Color(0.73, 0.80, 0.98, 0.065 * edge_fade)
				# A diffuse wisp built from overlapping soft lobes rather than a
				# hard-edged bar that might read as a platform or collision object.
				canvas.draw_circle(Vector2(x - 20.0, y + 3.0), 9.0, fog)
				canvas.draw_circle(Vector2(x - 12.0, y + 1.5), 9.0, fog)
				canvas.draw_circle(Vector2(x - 4.0, y), 9.0, fog)
				canvas.draw_circle(Vector2(x + 4.0, y - 1.5), 9.0, fog)
				canvas.draw_circle(Vector2(x + 12.0, y - 3.0), 9.0, fog)
				canvas.draw_circle(Vector2(x + 20.0, y - 4.5), 9.0, fog)
				canvas.draw_line(Vector2(x - 19.0, y + 3.0), Vector2(x + 19.0, y - 4.0), Color(0.82, 0.87, 1.0, 0.035 * edge_fade), 2.0, true)
			"lava":
				var ember := Color(1.0, 0.40, 0.12, 0.68 * edge_fade)
				var ember_core := Color(1.0, 0.76, 0.36, 0.58 * edge_fade)
				# Small tilted ember with a visible head and short tail, 10–12 px
				# overall. This reads as drifting ash, not a collectible or projectile.
				var ember_shape := PackedVector2Array([
					Vector2(x + 6.0, y - 4.5), Vector2(x + 2.0, y - 1.5),
					Vector2(x + 1.0, y + 4.5), Vector2(x - 4.0, y + 6.0),
					Vector2(x - 2.0, y), Vector2(x - 0.5, y - 5.5)
				])
				canvas.draw_colored_polygon(ember_shape, ember)
				canvas.draw_line(Vector2(x - 3.5, y + 5.0), Vector2(x - 6.0, y + 8.0), Color(1.0, 0.54, 0.19, 0.42 * edge_fade), 2.0, true)
				canvas.draw_circle(Vector2(x + 1.0, y - 1.0), 1.6, ember_core)
			"meadow":
				# Drifting petals and pollen, a few px, well below pickup scale.
				var petal := Color(1.0, 0.93, 0.98, 0.55 * edge_fade) if int(motif.x) % 3 != 0 else Color(1.0, 0.86, 0.42, 0.6 * edge_fade)
				var sway := sin(presentation_time_seconds * 1.7 + motif.x * 0.05) * 2.0
				canvas.draw_rect(Rect2(Vector2(x - 2.0 + sway, y - 1.0), Vector2(4.0, 2.0)), petal)
				canvas.draw_rect(Rect2(Vector2(x - 1.0 + sway, y - 2.0), Vector2(2.0, 4.0)), petal)
			"_":
				var sparkle := Color(0.91, 0.96, 1.0, 0.24 * edge_fade)
				canvas.draw_circle(Vector2(x, y), 1.5, sparkle)

static func weather_canvas_x(fragment_left: float, motif_course_x: float, fragment_course_left: float) -> float:
	## Spatial phase is anchored to course position. A biome fragment changes both
	## left values by the same amount, so splitting the viewport cannot move weather.
	return fragment_left + motif_course_x - fragment_course_left

static func weather_primitive_extent(biome_kind: String) -> float:
	match biome_kind:
		"cave": return 7.0
		"lava": return 9.0
		"haunted": return 35.0
		"meadow": return 5.0
		_: return 2.0

static func weather_primitive_fits_fragment(fragment_left: float, fragment_width: float, center_x: float, extent: float) -> bool:
	## Draw calls have no global canvas scissor, so require the full antialiased
	## primitive bounds to fit instead of allowing a neighboring biome bleed.
	return fragment_width > 0.0 and center_x - extent >= fragment_left and center_x + extent <= fragment_left + fragment_width

static func draw_surface_tiles(canvas: CanvasItem, biome: BiomeDefinition, ceiling: bool, start_x: float, end_x: float, canvas_origin_x: float, surface_y_at: Callable, tint := Color.WHITE, biome_distance_offset := 0.0, generator_version: int = GENERATOR_VERSION_14 - 1) -> bool:
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
		var selected_biome := biome if biome != null else definition_for_generator((tile_left + tile_right) * 0.5 - biome_distance_offset, generator_version)
		if selected_biome == null or selected_biome.tile_set == null:
			continue
		var source := selected_biome.tile_set.get_source(selected_biome.atlas_source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		# Classify the whole world cell, not the visible part of it. Clipping at
		# the view edge or a segment boundary otherwise changed the tile (flat,
		# slope, ledge) while it scrolled, so slopes popped at the screen edges.
		var cell_right := x + float(world_tile_size.x)
		var candidates := _tiles_for_surface_cell(selected_biome, ceiling, x, cell_right, surface_y_at)
		if candidates.is_empty():
			continue
		var texture_tile_size := source.texture_region_size
		var atlas := candidates[posmod(cell, candidates.size())]
		if not source.has_tile(atlas):
			continue
		var tile_tint := tint if tint != Color.WHITE else selected_biome.surface_tint
		var u0 := clampf((tile_left - x) / float(world_tile_size.x), 0.0, 1.0)
		var u1 := clampf((tile_right - x) / float(world_tile_size.x), 0.0, 1.0)
		var source_rect := Rect2(Vector2(atlas * texture_tile_size), Vector2(texture_tile_size))
		var tile_texture: Texture2D = pixel_texture(source.texture, false) if selected_biome.pixel_art else source.texture
		var rise := selected_biome.tile_rise
		var step_threshold := _find_step_threshold(surface_y_at, ceiling, x, cell_right, float(surface_y_at.call(x, ceiling)), float(surface_y_at.call((x + cell_right) * 0.5, ceiling)), float(surface_y_at.call(cell_right, ceiling)))
		if step_threshold > tile_left and step_threshold < tile_right:
			var step_fraction := (step_threshold - x) / float(world_tile_size.x)
			var left_surface := Callable(func(position_x: float, _ceiling: bool) -> float: return float(surface_y_at.call(minf(position_x, step_threshold - 0.01), ceiling)))
			var right_surface := Callable(func(position_x: float, _ceiling: bool) -> float: return float(surface_y_at.call(maxf(position_x, step_threshold + 0.01), ceiling)))
			_draw_surface_tile_quad(canvas, tile_texture, source_rect, tile_left, step_threshold, x, world_tile_size.y, canvas_origin_x, left_surface, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, u0, step_fraction, rise)
			_draw_surface_tile_quad(canvas, tile_texture, source_rect, step_threshold, tile_right, x, world_tile_size.y, canvas_origin_x, right_surface, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, step_fraction, u1, rise)
		else:
			_draw_surface_tile_quad(canvas, tile_texture, source_rect, tile_left, tile_right, x, world_tile_size.y, canvas_origin_x, surface_y_at, ceiling, tile_tint, selected_biome.surface_overlay_color, selected_biome.flip_ceiling_tiles, u0, u1, rise)
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

static func _draw_surface_tile_quad(canvas: CanvasItem, texture: Texture2D, source_rect: Rect2, left: float, right: float, tile_origin_x: float, tile_height: int, canvas_origin_x: float, surface_y_at: Callable, ceiling: bool, tint: Color, overlay: Color, flip_ceiling: bool, u0: float, u1: float, rise: int = 0) -> void:
	if right <= left:
		return
	# The tile reaches `rise` px past the surface (grass tips above the floor,
	# below the ceiling).
	var lift := float(rise) if ceiling else -float(rise)
	var y0 := float(surface_y_at.call(left, ceiling)) + lift
	var y1 := float(surface_y_at.call(right, ceiling)) + lift
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

## The shared pixel backdrop of pixel-style biomes, in the runners' style
## (shapes snap to a 4 px grid), coloured by the biome's PixelPalette: a banded
## sky with dithered seams, a block sun, clouds with a shaded underside, a pale
## far ridge, two parallax ranges of stepped hills with a lit crest, and round
## pixel trees on the near hills. Each part can be switched off in the palette.
## Every shape is a function of course position, so fragments at theme
## boundaries join without seams.
const PIXEL_PX := 4.0

static func _draw_pixel_backdrop(canvas: CanvasItem, left: float, size: Vector2, view_left: float, camera_course_distance: float, time_seconds: float, palette: PixelPalette) -> void:
	var right := left + size.x
	var px := PIXEL_PX
	# Sky bands, each seam dithered with a checker row.
	var band_h := roundf(size.y * 0.12 / px) * px
	for index in range(palette.sky_bands.size()):
		var y := float(index) * band_h
		var h := band_h if index < palette.sky_bands.size() - 1 else size.y * 0.5
		canvas.draw_rect(Rect2(Vector2(left, y), Vector2(size.x, h)), palette.sky_bands[index])
		if index > 0:
			var x := floorf(left / (px * 2.0)) * px * 2.0
			while x < right:
				var cell := Rect2(Vector2(x, y), Vector2(px, px)).intersection(Rect2(left, 0.0, size.x, size.y))
				if cell.size.x > 0.0:
					canvas.draw_rect(cell, palette.sky_bands[index - 1])
				x += px * 2.0
	# The sun keeps its place on screen: blocks, with a soft block halo.
	var sun := Vector2(view_left + 760.0, size.y * 0.27)
	if palette.sun and sun.x - 40.0 >= left and sun.x + 40.0 <= right:
		_pixel_disc(canvas, sun, 34.0, px, palette.sun_halo)
		_pixel_disc(canvas, sun, 22.0, px, palette.sun_disc)
		_pixel_disc(canvas, sun + Vector2(-4.0, -4.0), 14.0, px, palette.sun_core)
	# Clouds: stacked block rows with a shaded underside, slow parallax plus wind.
	var cloud_parallax := camera_course_distance * 0.06 + time_seconds * 6.0
	var period := 420.0
	var first := floori((cloud_parallax + (left - view_left) - 120.0) / period)
	var last := ceili((cloud_parallax + (right - view_left) + 120.0) / period)
	var view := Rect2(left, 0.0, size.x, size.y)
	for cell in range(first, last + 1 if palette.clouds else first):
		var landmark := _landmark_for_cell(cell, period, 4211)
		var cx := roundf((view_left + landmark.x - cloud_parallax) / px) * px
		var cy := roundf(size.y * (0.20 + landmark.y * 0.16) / px) * px
		var w := roundf((60.0 + landmark.y * 50.0) / px) * px
		if cx + w < left or cx - w > right:
			continue
		var parts := [
			[Rect2(cx - w * 0.5, cy - 8.0, w, 12.0), palette.cloud],
			[Rect2(cx - w * 0.5 + px, cy + 4.0, w - px * 2.0, 4.0), palette.cloud_shade],
			[Rect2(cx - w * 0.3, cy - 20.0, roundf(w * 0.45 / px) * px, 12.0), palette.cloud],
			[Rect2(cx - w * 0.05, cy - 28.0, roundf(w * 0.3 / px) * px, 8.0), palette.cloud],
		]
		for part in parts:
			var clipped: Rect2 = (part[0] as Rect2).intersection(view)
			if clipped.size.x > 0.0:
				canvas.draw_rect(clipped, part[1])
	# Far ridge, then two hill ranges; trees stand on the near range.
	if palette.islands:
		_draw_pixel_islands(canvas, left, size, view_left, camera_course_distance * 0.08 + time_seconds * 3.0, palette)
	var puffy := palette.hill_style == "puffy"
	_draw_pixel_hills(canvas, left, size, view_left, camera_course_distance * 0.05, size.y * 0.46, 40.0, 0.006, palette.ridge, palette.ridge_crest, puffy)
	_draw_pixel_hills(canvas, left, size, view_left, camera_course_distance * 0.10, size.y * 0.54, 34.0, 0.011, palette.hills_far, palette.hills_far_crest, puffy)
	var near_offset := camera_course_distance * 0.22
	var near_base := size.y * 0.66
	if palette.trees:
		_draw_pixel_trees(canvas, left, size, view_left, near_offset, near_base, 28.0, 0.017, palette)
	_draw_pixel_hills(canvas, left, size, view_left, near_offset, near_base, 28.0, 0.017, palette.hills_near, palette.hills_near_crest, puffy)

static func _pixel_hill_y(u: float, base_y: float, amplitude: float, frequency: float) -> float:
	return base_y - amplitude * (0.6 * sin(u * frequency) + 0.4 * sin(u * frequency * 2.3 + 1.7))

## A hill range as stepped columns (4 px wide, heights snapped to 4 px) with a
## lighter crest row.
## "puffy" adds round bumps on top, so the range reads as a cloud bank.
static func _draw_pixel_hills(canvas: CanvasItem, left: float, size: Vector2, view_left: float, parallax_offset: float, base_y: float, amplitude: float, frequency: float, color: Color, crest := Color.TRANSPARENT, puffy := false) -> void:
	var px := PIXEL_PX
	# Columns as rects (cheap to batch; no polygon triangulation per frame).
	var x := floorf(left / px) * px
	var right := left + size.x
	while x < right:
		var u := parallax_offset + (x - view_left)
		var hill_y := _pixel_hill_y(u, base_y, amplitude, frequency)
		if puffy:
			hill_y -= 14.0 * sqrt(absf(sin(u * 0.04)))
		var y := roundf(hill_y / px) * px
		var x0 := maxf(x, left)
		var w := minf(x + px, right) - x0
		if w > 0.0:
			canvas.draw_rect(Rect2(Vector2(x0, y), Vector2(w, size.y - y)), color)
			if crest.a > 0.0:
				canvas.draw_rect(Rect2(Vector2(x0, y), Vector2(w, px)), crest)
		x += px

## Round pixel trees on the near hills: a trunk and a canopy of 4 px blocks
## with a dark rim and a lit top-left, rooted on the hill line behind them.
static func _draw_pixel_trees(canvas: CanvasItem, left: float, size: Vector2, view_left: float, parallax_offset: float, base_y: float, amplitude: float, frequency: float, palette: PixelPalette) -> void:
	var px := PIXEL_PX
	var period := 260.0
	var first := floori((parallax_offset + (left - view_left) - 60.0) / period)
	var last := ceili((parallax_offset + (left + size.x - view_left) + 60.0) / period)
	for cell in range(first, last + 1):
		var landmark := _landmark_for_cell(cell, period, 9157)
		if landmark.y < 0.35:
			continue
		var u := landmark.x
		var x := roundf((view_left + u - parallax_offset) / px) * px
		if x + 24.0 < left or x - 24.0 > left + size.x:
			continue
		var ground := roundf(_pixel_hill_y(u, base_y, amplitude, frequency) / px) * px + px * 2.0
		var radius := 12.0 + roundf(landmark.y * 3.0) * px
		var crown := Vector2(x, ground - 16.0 - radius)
		if palette.tree_style == "dead":
			_draw_pixel_dead_tree(canvas, Vector2(x, ground), radius, px, palette, Rect2(left, 0.0, size.x, size.y), cell)
			continue
		if palette.tree_style == "pine":
			_draw_pixel_pine(canvas, Vector2(x, ground), radius, px, palette, Rect2(left, 0.0, size.x, size.y))
			continue
		if palette.tree_style == "cactus":
			_draw_pixel_cactus(canvas, Vector2(x, ground), radius, px, palette, Rect2(left, 0.0, size.x, size.y), cell)
			continue
		var view := Rect2(left, 0.0, size.x, size.y)
		var trunk := Rect2(Vector2(x - px * 0.5, crown.y), Vector2(px, ground - crown.y)).intersection(view)
		if trunk.size.x > 0.0:
			canvas.draw_rect(trunk, palette.tree_trunk)
		_pixel_disc(canvas, crown, radius + px, px, palette.tree_rim, view)
		_pixel_disc(canvas, crown, radius, px, palette.tree_canopy, view)
		_pixel_disc(canvas, crown + Vector2(-px, -px), radius * 0.55, px, palette.tree_light, view)

## A filled circle drawn as px-sized blocks, optionally clipped to `clip`.
static func _pixel_disc(canvas: CanvasItem, center: Vector2, radius: float, px: float, color: Color, clip := Rect2()) -> void:
	var snapped := (center / px).round() * px
	var cells := int(ceil(radius / px))
	for gy in range(-cells, cells + 1):
		var row_y := float(gy) * px
		var half := sqrt(maxf(radius * radius - row_y * row_y, 0.0))
		var span := roundf(half / px) * px
		if span <= 0.0:
			continue
		var rect := Rect2(snapped + Vector2(-span, row_y - px * 0.5), Vector2(span * 2.0, px))
		if clip.size != Vector2.ZERO:
			rect = rect.intersection(clip)
			if rect.size.x <= 0.0:
				continue
		canvas.draw_rect(rect, color)

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

static func _draw_cave_backdrop(canvas: CanvasItem, left: float, size: Vector2, camera_course_distance: float, fragment_offset: float, biome: BiomeDefinition, with_crystals := true) -> void:
	for layer in range(3):
		var clipped := cave_clipped_ridge_vertices(left, camera_course_distance, fragment_offset, size.x, size.y, layer)
		if clipped.size() < 2:
			continue
		var color := biome.layer_colors[layer % biome.layer_colors.size()]
		for point_index in range(clipped.size() - 1):
			var segment := PackedVector2Array([
				clipped[point_index],
				clipped[point_index + 1],
				Vector2(clipped[point_index + 1].x, size.y),
				Vector2(clipped[point_index].x, size.y),
			])
			canvas.draw_colored_polygon(segment, color)
	if not with_crystals:
		return
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

const CAVE_CRYSTAL_BLUE := Color("8fb4ff")
const CAVE_CRYSTAL_PURPLE := Color("b57cff")

## Campaign cave lift, drawn over the ridge layers: two parallax ranges of
## stalactite silhouettes, water drops falling from the near range, and glowing
## crystals low in the background. Everything is a function of course position
## (and time for the drops), so theme fragments join without seams. Colours stay
## dark and low-contrast so hazards in the play corridor read first.
static func _draw_cave_campaign_backdrop(canvas: CanvasItem, left: float, size: Vector2, camera_course_distance: float, fragment_offset: float, time_seconds: float) -> void:
	var right := left + size.x
	# Far then near stalactites.
	for layer in range(2):
		var parallax := 0.12 if layer == 0 else 0.26
		var period := 120.0 if layer == 0 else 150.0
		var parallax_left := camera_course_distance * parallax + fragment_offset
		var color := Color(0.05, 0.09, 0.15, 1.0) if layer == 0 else Color(0.035, 0.065, 0.11, 1.0)
		for point in _landmarks_in_course(parallax_left - 40.0, parallax_left + size.x + 40.0, period, 71 + layer * 13):
			var x := left + point.x - parallax_left
			var length := size.y * (0.10 + point.y * (0.12 + 0.08 * float(layer)))
			var half := 11.0 + point.y * 12.0 + 6.0 * float(layer)
			if x - half < left or x + half > right:
				continue
			var top := 34.0
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(x - half, top), Vector2(x + half, top), Vector2(x + half * 0.25, top + length * 0.7), Vector2(x, top + length), Vector2(x - half * 0.3, top + length * 0.7)]), color)
			if layer == 1:
				canvas.draw_line(Vector2(x - half * 0.55, top), Vector2(x, top + length * 0.92), Color(0.12, 0.2, 0.3, 0.55), 1.2, true)
			if layer == 1 and point.y > 0.35:
				# A water drop forms on the tip and falls (1.7-2.6 s cycle).
				var cycle := 1.7 + point.y * 0.9
				var phase := fposmod(time_seconds + point.x * 0.013, cycle) / cycle
				var tip := Vector2(x, top + length)
				var drop_color := Color(0.55, 0.78, 1.0, 0.75)
				if phase < 0.55:
					canvas.draw_circle(tip + Vector2(0.0, 1.0 + phase * 3.0), 0.8 + phase * 2.0, drop_color)
				else:
					var fall := (phase - 0.55) / 0.45
					var drop_y := tip.y + 3.0 + fall * fall * size.y * 0.45
					if drop_y < size.y - 70.0:
						canvas.draw_line(Vector2(x, drop_y - 6.0 * fall), Vector2(x, drop_y), Color(0.55, 0.78, 1.0, 0.35), 1.5)
						canvas.draw_circle(Vector2(x, drop_y), 2.2, drop_color)
	# Glowing crystals.
	var crystal_left := camera_course_distance * 0.2 + fragment_offset
	for point in _landmarks_in_course(crystal_left - 30.0, crystal_left + size.x + 30.0, 210.0, 97):
		var x := left + point.x - crystal_left
		if x - 26.0 < left or x + 26.0 > right:
			continue
		var purple := int(point.y * 100.0) % 3 == 0
		var base := CAVE_CRYSTAL_PURPLE if purple else CAVE_CRYSTAL_BLUE
		var y := size.y * (0.30 + point.y * 0.28)
		var pulse := 0.8 + 0.2 * sin(time_seconds * 2.0 + point.x * 0.05)
		var halo := base
		halo.a = 0.11 * pulse
		canvas.draw_circle(Vector2(x, y), 22.0, halo)
		halo.a = 0.16 * pulse
		canvas.draw_circle(Vector2(x, y), 12.0, halo)
		var body := base.lerp(Color(0.04, 0.07, 0.14), 0.1)
		body.a = 0.95
		var shine := base.lerp(Color.WHITE, 0.5)
		shine.a = 0.75 * pulse
		for shard in [[-5.0, 7.0, 4.0], [0.0, 12.0, 5.0], [5.0, 8.0, 4.0]]:
			var sx: float = x + shard[0] * 1.5
			var sh: float = shard[1] * 1.5
			var sw: float = shard[2] * 1.6
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(sx, y - sh), Vector2(sx + sw * 0.5, y), Vector2(sx, y + sh * 0.4), Vector2(sx - sw * 0.5, y)]), body)
			canvas.draw_line(Vector2(sx, y - sh), Vector2(sx, y + sh * 0.2), shine, 1.0)

const HAUNTED_GHOST_GREEN := Color("8dffc0")

## Campaign haunted lift, drawn over the ruin/fog layers: a big moon, two
## parallax rows of dead-tree silhouettes, low fog bands that drift and a few
## floating will-o'-wisps. Everything is a function of course position (and time
## for drift and bobbing), so theme fragments join without seams. The palette is
## purple and dark blue, with green ghost lights kept small and dim so the
## ghosts and spikes in the play corridor read first.
static func _draw_haunted_campaign_backdrop(canvas: CanvasItem, left: float, size: Vector2, camera_course_distance: float, fragment_offset: float, time_seconds: float) -> void:
	var right := left + size.x
	# Big moon: a slow parallax lattice so one is nearly always in view.
	var moon_left := camera_course_distance * 0.04 + fragment_offset
	var moon_period := 1500.0
	for point in _landmarks_in_course(moon_left - 200.0, moon_left + size.x + 200.0, moon_period, 211):
		var radius := size.y * 0.15
		var moon_x := left + point.x - moon_left
		var moon_y := size.y * (0.32 + point.y * 0.06)
		if moon_x - radius * 2.4 < left or moon_x + radius * 2.4 > right:
			continue
		var moon_center := Vector2(moon_x, moon_y)
		for ring in range(4):
			canvas.draw_circle(moon_center, radius * (2.2 - ring * 0.35), Color(0.55, 0.5, 0.95, 0.035 + 0.012 * ring))
		canvas.draw_circle(moon_center, radius, Color(0.6, 0.58, 0.8, 0.88))
		# Craters and a shaded limb.
		for crater in [[-0.35, -0.2, 0.2], [0.25, 0.1, 0.27], [-0.1, 0.5, 0.16], [0.45, -0.45, 0.12]]:
			canvas.draw_circle(moon_center + Vector2(crater[0], crater[1]) * radius, crater[2] * radius, Color(0.5, 0.47, 0.72, 0.7))
		# Soft shading on the lower right limb, kept inside the disc.
		canvas.draw_circle(moon_center + Vector2(radius * 0.62, radius * 0.22), radius * 0.34, Color(0.5, 0.46, 0.76, 0.3))
		canvas.draw_circle(moon_center + Vector2(radius * 0.4, radius * 0.5), radius * 0.4, Color(0.5, 0.46, 0.76, 0.22))
	# Far then near dead trees, rooted at the ground and fading into the fog.
	for layer in range(2):
		var parallax := 0.14 if layer == 0 else 0.3
		var period := 130.0 if layer == 0 else 190.0
		var parallax_left := camera_course_distance * parallax + fragment_offset
		var color := Color(0.075, 0.06, 0.17, 1.0) if layer == 0 else Color(0.045, 0.035, 0.11, 1.0)
		for point in _landmarks_in_course(parallax_left - 60.0, parallax_left + size.x + 60.0, period, 131 + layer * 17):
			var x := left + point.x - parallax_left
			var scale := (0.75 + point.y * 0.5) * (1.0 if layer == 1 else 0.8)
			var height := size.y * 0.42 * scale
			if x - height * 0.5 < left or x + height * 0.5 > right:
				continue
			var base_y := size.y * (0.80 if layer == 0 else 0.86)
			_draw_dead_tree(canvas, Vector2(x, base_y), height, point.y, color)
	# Low fog bands drifting right to left at their own speeds.
	for band in range(3):
		var speed := 9.0 + 7.0 * band
		var fog_left := camera_course_distance * (0.1 + 0.07 * band) + fragment_offset + time_seconds * speed
		var y := size.y * (0.74 + band * 0.05)
		for point in _landmarks_in_course(fog_left - 120.0, fog_left + size.x + 120.0, 170.0 + band * 40.0, 331 + band * 7):
			var x := left + point.x - fog_left
			var half := 70.0 + point.y * 50.0
			if x - half < left or x + half > right:
				continue
			var fog := Color(0.5, 0.44, 0.82, 0.05 + 0.012 * band)
			# One flat ellipse per band patch (a single alpha, so no blobby overlaps).
			var outline := PackedVector2Array()
			for step in range(16):
				var angle := TAU * float(step) / 16.0
				outline.append(Vector2(x + cos(angle) * half, y + sin(angle) * (11.0 + 3.0 * sin(time_seconds * 0.4 + point.x))))
			canvas.draw_colored_polygon(outline, fog)
	# Will-o'-wisps: small, dim, greenish, bobbing above the play corridor.
	var wisp_left := camera_course_distance * 0.2 + fragment_offset
	for point in _landmarks_in_course(wisp_left - 40.0, wisp_left + size.x + 40.0, 260.0, 457):
		var bob := time_seconds * 0.9 + point.x * 0.03
		var x := left + point.x - wisp_left + sin(bob) * 14.0
		var y := size.y * (0.38 + point.y * 0.2) + cos(bob * 1.3) * 9.0
		if x - 18.0 < left or x + 18.0 > right:
			continue
		var flicker := 0.75 + 0.25 * sin(time_seconds * 5.0 + point.x)
		var glow := HAUNTED_GHOST_GREEN
		glow.a = 0.09 * flicker
		canvas.draw_circle(Vector2(x, y), 15.0, glow)
		glow.a = 0.18 * flicker
		canvas.draw_circle(Vector2(x, y), 8.0, glow)
		var core := HAUNTED_GHOST_GREEN.lerp(Color.WHITE, 0.55)
		core.a = 0.8 * flicker
		canvas.draw_circle(Vector2(x, y), 2.4, core)
		# A short fading tail trailing behind.
		for tail in range(1, 4):
			var tail_color := HAUNTED_GHOST_GREEN
			tail_color.a = 0.14 * flicker / float(tail)
			canvas.draw_circle(Vector2(x + tail * 5.0, y + tail * 1.5), 2.0 - 0.4 * tail, tail_color)

## A gnarled bare tree: tapered trunk plus a few forked branches.
static func _draw_dead_tree(canvas: CanvasItem, base: Vector2, height: float, seed_value: float, color: Color) -> void:
	var trunk := height * 0.06
	var lean := (seed_value - 0.5) * height * 0.12
	var top := base + Vector2(lean, -height * 0.62)
	canvas.draw_colored_polygon(PackedVector2Array([base + Vector2(-trunk * 1.5, 0.0), base + Vector2(trunk * 1.5, 0.0), top + Vector2(trunk * 0.4, 0.0), top + Vector2(-trunk * 0.4, 0.0)]), color)
	var flip := -1.0 if seed_value > 0.5 else 1.0
	for branch in [[0.0, -1.0, 0.34, -0.5, 3.0], [0.0, 1.0, 0.30, -0.42, 3.0], [-0.4, flip, 0.26, -0.3, 2.4], [-0.18, -flip, 0.22, -0.34, 2.4]]:
		var origin := top + (base - top) * (-float(branch[0]))
		var reach := height * float(branch[2])
		var tip := origin + Vector2(float(branch[1]) * reach, float(branch[3]) * reach)
		canvas.draw_line(origin, tip, color, float(branch[4]), true)
		var mid := origin.lerp(tip, 0.6)
		canvas.draw_line(mid, mid + Vector2(float(branch[1]) * reach * 0.35, -reach * 0.38), color, 1.6, true)
		canvas.draw_line(mid, mid + Vector2(float(branch[1]) * reach * 0.4, reach * 0.02), color, 1.4, true)
	canvas.draw_line(top, top + Vector2(0.0, -height * 0.12), color, 2.0, true)

## Campaign volcano backdrop (world 4): a dark red sky, a huge smoking volcano
## in the distance, two parallax rows of black basalt columns, a heat glow from
## below and a few drifting embers. A function of course position (and time for
## smoke, glow and embers), so theme fragments join without seams. Kept dark and
## low-contrast so the lava, spikes and rocks in the play corridor read first.
static func _draw_volcano_campaign_backdrop(canvas: CanvasItem, left: float, size: Vector2, camera_course_distance: float, fragment_offset: float, time_seconds: float) -> void:
	var right := left + size.x
	# Sky: dark red at the top, hotter towards the horizon.
	var bands := 8
	for band in range(bands):
		var t := float(band) / float(bands - 1)
		var sky := Color(0.1, 0.02, 0.035).lerp(Color(0.46, 0.115, 0.045), t * t)
		canvas.draw_rect(Rect2(left, size.y * float(band) / float(bands), size.x, size.y / float(bands) + 1.0), sky)
	# The big volcano: a slow parallax lattice so one is nearly always in view.
	var volcano_left := camera_course_distance * 0.05 + fragment_offset
	var volcano_period := 760.0
	for point in _landmarks_in_course(volcano_left - 420.0, volcano_left + size.x + 420.0, volcano_period, 523):
		var half_base := size.y * 0.62
		var cx := left + point.x - volcano_left
		var base_y := size.y * 0.9
		var peak_y := size.y * (0.3 + point.y * 0.06)
		var half_top := half_base * 0.17
		if cx + half_base < left or cx - half_base > right:
			continue
		var body := Color(0.115, 0.032, 0.045, 1.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(clampf(cx - half_base, left, right), base_y), Vector2(clampf(cx - half_base * 0.5, left, right), peak_y + (base_y - peak_y) * 0.42),
			Vector2(clampf(cx - half_top, left, right), peak_y), Vector2(clampf(cx + half_top, left, right), peak_y),
			Vector2(clampf(cx + half_base * 0.5, left, right), peak_y + (base_y - peak_y) * 0.42), Vector2(clampf(cx + half_base, left, right), base_y)]), body)
		if cx - half_top < left or cx + half_top > right:
			continue
		# Glowing crater rim and two lava streaks running down the flanks.
		var pulse := 0.8 + 0.2 * sin(time_seconds * 1.7 + point.x)
		canvas.draw_rect(Rect2(cx - half_top, peak_y - 2.0, half_top * 2.0, 4.0), Color(1.0, 0.5, 0.12, 0.85 * pulse))
		canvas.draw_circle(Vector2(cx, peak_y - 4.0), half_top * 1.1, Color(1.0, 0.4, 0.08, 0.1 * pulse))
		canvas.draw_line(Vector2(cx - half_top * 0.5, peak_y + 3.0), Vector2(cx - half_base * 0.36, peak_y + (base_y - peak_y) * 0.62), Color(1.0, 0.36, 0.07, 0.5 * pulse), 2.0, true)
		canvas.draw_line(Vector2(cx + half_top * 0.6, peak_y + 3.0), Vector2(cx + half_base * 0.28, peak_y + (base_y - peak_y) * 0.5), Color(1.0, 0.36, 0.07, 0.4 * pulse), 1.6, true)
		# Smoke column: soft puffs rise, widen and fade while drifting sideways.
		for puff in range(6):
			var age := fposmod(time_seconds * 0.07 + float(puff) / 6.0 + point.y, 1.0)
			var smoke := Color(0.26, 0.1, 0.1, 0.34 * (1.0 - age) * minf(age * 6.0, 1.0))
			canvas.draw_circle(Vector2(cx + age * half_base * 0.55 + sin(age * 5.0 + float(puff)) * 8.0, peak_y - 6.0 - age * size.y * 0.3), half_top * (0.55 + age * 1.5), smoke)
	# Far then near basalt column clusters, rooted at the ground.
	for layer in range(2):
		var parallax := 0.14 if layer == 0 else 0.3
		var period := 150.0 if layer == 0 else 210.0
		var parallax_left := camera_course_distance * parallax + fragment_offset
		var color := Color(0.075, 0.024, 0.04, 1.0) if layer == 0 else Color(0.04, 0.015, 0.028, 1.0)
		var base_y := size.y * (0.84 if layer == 0 else 0.92)
		for point in _landmarks_in_course(parallax_left - 80.0, parallax_left + size.x + 80.0, period, 641 + layer * 19):
			var x := left + point.x - parallax_left
			var count := 3 + int(point.y * 3.0)
			var column_w := 15.0 if layer == 0 else 22.0
			if x - column_w * count < left or x + column_w * count > right:
				continue
			for i in range(count):
				var offset := (float(i) - float(count - 1) * 0.5) * column_w
				var height := size.y * (0.16 + 0.2 * fposmod(point.y * 7.3 + float(i) * 0.37, 1.0)) * (1.0 if layer == 1 else 0.8)
				var cx := x + offset
				var tilt := (fposmod(point.y * 3.1 + float(i) * 0.53, 1.0) - 0.5) * column_w * 0.9
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(cx - column_w * 0.5, base_y), Vector2(cx - column_w * 0.5, base_y - height),
					Vector2(cx + column_w * 0.5, base_y - height + tilt), Vector2(cx + column_w * 0.5, base_y)]), color)
				if layer == 1:
					# Lit edge from the glow below.
					canvas.draw_line(Vector2(cx + column_w * 0.5, base_y), Vector2(cx + column_w * 0.5, base_y - height + tilt), Color(0.9, 0.3, 0.07, 0.3), 1.0)
	# Glow from below: stacked translucent bands that breathe slowly.
	var glow := 0.85 + 0.15 * sin(time_seconds * 1.1)
	for band in range(5):
		var h := size.y * (0.1 + 0.05 * band)
		canvas.draw_rect(Rect2(left, size.y - h, size.x, h), Color(1.0, 0.33, 0.06, 0.06 * glow))
	# Embers rising and drifting.
	var ember_left := camera_course_distance * 0.2 + fragment_offset
	for point in _landmarks_in_course(ember_left - 40.0, ember_left + size.x + 40.0, 150.0, 797):
		var age := fposmod(time_seconds * (0.1 + point.y * 0.06) + point.x * 0.013, 1.0)
		var x := left + point.x - ember_left + sin(age * 9.0 + point.x) * 12.0
		var y := size.y * (0.95 - age * 0.8)
		if x - 6.0 < left or x + 6.0 > right:
			continue
		var fade := (1.0 - age) * minf(age * 8.0, 1.0)
		canvas.draw_circle(Vector2(x, y), 4.5, Color(1.0, 0.35, 0.06, 0.12 * fade))
		canvas.draw_circle(Vector2(x, y), 1.6, Color(1.0, 0.7, 0.3, 0.9 * fade))

static func cave_clipped_ridge_vertices(left: float, camera_course_distance: float, fragment_offset: float, fragment_width: float, logical_height: float, layer: int) -> PackedVector2Array:
	## Return only the upper ridge contour. Fill quads add their own bottom corners
	## after clipping; mixing those corners into this float32 array can make them
	## round just inside a high-precision clip edge and self-intersect the contour.
	if fragment_width <= 0.0 or logical_height <= 0.0 or layer < 0 or layer >= 3:
		return PackedVector2Array()
	var samples := cave_ridge_diagnostic_samples(camera_course_distance, fragment_offset, fragment_width, logical_height)
	var phase_left := float(samples[layer].get("phase_left", 0.0))
	var spacing := 48.0
	var first_sample := floori(phase_left / spacing)
	var last_sample := ceili((phase_left + fragment_width) / spacing)
	var candidates := PackedVector2Array()
	var amplitude := logical_height * (0.13 + 0.055 * float(layer))
	var base_y := logical_height * (0.32 + 0.18 * float(layer))
	for i in range(first_sample, last_sample + 1):
		var course_x := float(i) * spacing
		var x := left + course_x - phase_left
		var phase := course_x * 0.003
		var ridge_y := clampf(base_y + sin(phase) * amplitude + cos(phase * 0.37) * amplitude * 0.4, logical_height * 0.04, logical_height * 0.94)
		candidates.append(Vector2(x, ridge_y))
	var clipped := PackedVector2Array([
		Vector2(left, _cave_ridge_y(phase_left, logical_height, layer)),
		Vector2(left + fragment_width, _cave_ridge_y(phase_left + fragment_width, logical_height, layer)),
	])
	for point in candidates:
		if point.x > left and point.x < left + fragment_width:
			clipped.insert(clipped.size() - 1, point)
	return clipped

static func _cave_ridge_y(parallax_x: float, viewport_height: float, layer: int) -> float:
	var amplitude := viewport_height * (0.13 + 0.055 * float(layer))
	var base_y := viewport_height * (0.32 + 0.18 * float(layer))
	var phase := parallax_x * 0.003
	return clampf(base_y + sin(phase) * amplitude + cos(phase * 0.37) * amplitude * 0.4, viewport_height * 0.04, viewport_height * 0.94)

static func cave_ridge_diagnostic_samples(camera_course_distance: float, fragment_offset: float, fragment_width: float, logical_height: float) -> Array[Dictionary]:
	## Shared by the renderer and opt-in diagnostics so clipped fragments report
	## the exact parallax phases and ridge endpoints used for drawing.
	var samples: Array[Dictionary] = []
	for layer in range(3):
		var parallax := 0.16 + 0.07 * float(layer)
		var phase_left := camera_course_distance * parallax + fragment_offset
		var phase_right := phase_left + fragment_width
		samples.append({
			"layer": layer,
			"parallax": parallax,
			"phase_left": phase_left,
			"phase_right": phase_right,
			"left_y": _cave_ridge_y(phase_left, logical_height, layer),
			"right_y": _cave_ridge_y(phase_right, logical_height, layer),
		})
	return samples

static func _draw_haunted_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, view_left: float, full_view_size: Vector2, camera_course_distance: float, biome: BiomeDefinition, cycle_length: float = CYCLE_LENGTH) -> void:
	# Moon and silhouettes are tied to the biome's course interval, not the
	# width of the fragment left after clipping at a theme boundary.
	var haunted_start := floori(distance / cycle_length) * cycle_length + THEME_LENGTH * 2.0
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

static func _draw_lava_backdrop(canvas: CanvasItem, left: float, size: Vector2, distance: float, view_left: float, camera_course_distance: float, biome: BiomeDefinition) -> void:
	# Fixed course-space motifs keep the lava backdrop stable across fragments,
	# viewport sizes, and SP/MP cameras. All bright marks stay above the track.
	var parallax := 0.14
	var parallax_left := camera_course_distance * parallax + (left - view_left)
	var first := floori(parallax_left / 210.0) - 1
	var last := ceili((parallax_left + size.x) / 210.0) + 1
	for cell in range(first, last + 1):
		var motif := _landmark_for_cell(cell, 210.0, 503)
		var x := view_left + motif.x - camera_course_distance * parallax
		if x < left - 50.0 or x > left + size.x + 50.0:
			continue
		var height := size.y * (0.18 + motif.y * 0.20)
		var base_y := size.y * (0.72 + motif.y * 0.09)
		var width := 46.0 + motif.y * 34.0
		var silhouette := biome.layer_colors[posmod(cell, maxi(biome.layer_colors.size(), 1))]
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x - width * 0.5, base_y), Vector2(x - width * 0.28, base_y - height * 0.62), Vector2(x - width * 0.12, base_y - height * 0.43), Vector2(x + width * 0.06, base_y - height), Vector2(x + width * 0.24, base_y - height * 0.49), Vector2(x + width * 0.43, base_y)]), silhouette)
	# Sparse dim lava veins are decorative background only; the lethal cracks
	# are separate manifest hazards rendered on the support surface.
	var vein_left := camera_course_distance * 0.20 + (left - view_left)
	for point in _landmarks_in_course(vein_left, vein_left + size.x, 310.0, 521):
		var x := view_left + float(point.x) - camera_course_distance * 0.20
		if x < left or x > left + size.x:
			continue
		var y := size.y * (0.55 + point.y * 0.15)
		var glow := biome.accent_color
		glow.a = 0.24
		canvas.draw_line(Vector2(x - 13.0, y), Vector2(x, y + 5.0), glow, 2.0, true)
		canvas.draw_line(Vector2(x, y + 5.0), Vector2(x + 12.0, y - 2.0), glow, 2.0, true)

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

static var _pixel_textures: Dictionary = {}

## The texture wrapped for pixel art: nearest filtering (no blur when scaled up)
## and, for fills, repeat. Cached per texture.
static func pixel_texture(texture: Texture2D, repeat: bool) -> Texture2D:
	if texture == null:
		return null
	var key := "%d|%s" % [texture.get_instance_id(), str(repeat)]
	if not _pixel_textures.has(key):
		var wrapped := CanvasTexture.new()
		wrapped.diffuse_texture = texture
		wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wrapped.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if repeat else CanvasItem.TEXTURE_REPEAT_DISABLED
		_pixel_textures[key] = wrapped
	return _pixel_textures[key]

## A bare dead tree of px blocks: a dark trunk that leans a little and a few
## crooked branches ending in twigs, rooted at `ground`.
static func _draw_pixel_dead_tree(canvas: CanvasItem, ground: Vector2, size: float, px: float, palette: PixelPalette, clip: Rect2, seed_cell: int) -> void:
	var height := roundf((size * 2.6) / px) * px
	var lean := 1.0 if posmod(seed_cell, 2) == 0 else -1.0
	var blocks: Array[Rect2] = []
	var x := ground.x
	var y := ground.y
	var steps := int(height / px)
	for step in range(steps):
		if step % 4 == 3:
			x += px * lean * 0.5
		var width := px * (2.0 if step < steps / 2 else 1.0)
		blocks.append(Rect2(Vector2(roundf(x / px) * px - width * 0.5, y - float(step + 1) * px), Vector2(width, px)))
	# Branches from the upper half, alternating sides, each rising as it goes.
	var top := ground.y - height
	for b in range(3):
		var side := 1.0 if (b + posmod(seed_cell, 3)) % 2 == 0 else -1.0
		var start := Vector2(roundf((x - px * lean * 0.5 * float(2 - b)) / px) * px, top + float(b + 1) * height * 0.18)
		for s in range(3 + b):
			blocks.append(Rect2(start + Vector2(side * px * float(s + 1), -px * float(s / 2)), Vector2(px, px)))
	for block in blocks:
		var rim := block.grow(px * 0.5).intersection(clip)
		if rim.size.x > 0.0:
			canvas.draw_rect(rim, palette.tree_rim)
	for block in blocks:
		var body := block.intersection(clip)
		if body.size.x > 0.0:
			canvas.draw_rect(body, palette.tree_trunk)

## A snowy pine of px blocks: a short trunk under three stacked tiers, each a
## stepped triangle with a dark rim, a lit left side and snow along its top.
static func _draw_pixel_pine(canvas: CanvasItem, ground: Vector2, size: float, px: float, palette: PixelPalette, clip: Rect2) -> void:
	size *= 1.5
	var x := roundf(ground.x / px) * px
	var trunk := Rect2(Vector2(x - px * 0.5, ground.y - px * 2.0), Vector2(px, px * 2.0)).intersection(clip)
	if trunk.size.x > 0.0:
		canvas.draw_rect(trunk, palette.tree_trunk)
	var tier_h := roundf(size * 0.9 / px) * px
	var bottom := ground.y - px * 2.0
	for tier in range(3):
		var half_base := roundf((size * (1.0 - 0.24 * float(tier))) / px) * px
		var tier_bottom := bottom - float(tier) * tier_h * 0.62
		var rows := int(tier_h / px)
		for row in range(rows):
			var t := float(row + 1) / float(rows)
			var half := maxf(roundf(half_base * t / px) * px, px * 0.5)
			var y := tier_bottom - tier_h + float(row) * px
			var rim := Rect2(Vector2(x - half - px * 0.5, y), Vector2(half * 2.0 + px, px)).intersection(clip)
			if rim.size.x > 0.0:
				canvas.draw_rect(rim, palette.tree_rim)
			var body := Rect2(Vector2(x - half + px * 0.5, y), Vector2(maxf(half * 2.0 - px, px), px)).intersection(clip)
			if body.size.x > 0.0:
				canvas.draw_rect(body, palette.tree_canopy)
			var lit := Rect2(Vector2(x - half + px * 0.5, y), Vector2(maxf(half * 0.6, px), px)).intersection(clip)
			if lit.size.x > 0.0 and row > 0:
				canvas.draw_rect(lit, palette.tree_light)
			# Snow sits on the top rows and on the tips of each tier.
			if row < 2 or row == rows - 1:
				var snow_w := half * 2.0 - px if row < 2 else px * 2.0
				var snow_x := x - half + px * 0.5 if row < 2 else x - half - px * 0.5
				var snow := Rect2(Vector2(snow_x, y), Vector2(maxf(snow_w, px), px)).intersection(clip)
				if snow.size.x > 0.0:
					canvas.draw_rect(snow, palette.snow)

## A saguaro cactus of px blocks: a column with a round top and one or two
## arms that bend upwards, a dark rim and a lit rib.
static func _draw_pixel_cactus(canvas: CanvasItem, ground: Vector2, size: float, px: float, palette: PixelPalette, clip: Rect2, seed_cell: int) -> void:
	var x := roundf(ground.x / px) * px
	var height := roundf(size * 2.4 / px) * px
	var blocks: Array[Rect2] = [Rect2(Vector2(x - px, ground.y - height), Vector2(px * 2.0, height))]
	var arms := 1 + posmod(seed_cell, 2)
	for arm in range(arms):
		var side := -1.0 if arm == 0 else 1.0
		var arm_y := ground.y - height * (0.45 + 0.15 * float(arm))
		var reach := px * 3.0
		blocks.append(Rect2(Vector2(x + (side * px - px * 0.5 if side > 0.0 else -px - reach + px * 0.5), arm_y), Vector2(reach, px)))
		var up_x := x + side * (px + reach) - (px if side > 0.0 else 0.0)
		blocks.append(Rect2(Vector2(up_x - px * 0.5, arm_y - height * 0.3), Vector2(px * 1.5, height * 0.3 + px)))
	for block in blocks:
		var rim := block.grow(px * 0.5).intersection(clip)
		if rim.size.x > 0.0:
			canvas.draw_rect(rim, palette.tree_rim)
	for block in blocks:
		var body := block.intersection(clip)
		if body.size.x > 0.0:
			canvas.draw_rect(body, palette.tree_canopy)
	var rib := Rect2(Vector2(x - px * 0.5, ground.y - height + px), Vector2(px * 0.5, height - px * 2.0)).intersection(clip)
	if rib.size.x > 0.0:
		canvas.draw_rect(rib, palette.tree_light)

## Grassy islands floating in the sky: a grass cap with a lit edge on a rock
## underside that narrows in steps to a point, a dark rim, now and then a
## small round tree. Slow parallax, between the clouds and the hills.
static func _draw_pixel_islands(canvas: CanvasItem, left: float, size: Vector2, view_left: float, parallax_offset: float, palette: PixelPalette) -> void:
	var px := PIXEL_PX
	var period := 520.0
	var view := Rect2(left, 0.0, size.x, size.y)
	var first := floori((parallax_offset + (left - view_left) - 140.0) / period)
	var last := ceili((parallax_offset + (left + size.x - view_left) + 140.0) / period)
	for cell in range(first, last + 1):
		var landmark := _landmark_for_cell(cell, period, 6113)
		var cx := roundf((view_left + landmark.x - parallax_offset) / px) * px
		var top := roundf(size.y * (0.3 + landmark.y * 0.14) / px) * px
		var half := roundf((28.0 + landmark.y * 30.0) / px) * px
		if cx + half + px < left or cx - half - px > left + size.x:
			continue
		var blocks: Array[Array] = []
		# Rock underside: rows narrowing to a point.
		var rows := int(half / px * 0.8) + 2
		for row in range(rows):
			var row_half := roundf(half * (1.0 - float(row) / float(rows)) / px) * px
			if row_half < px:
				row_half = px * 0.5
			var shade := palette.tree_trunk if row % 3 != 2 else palette.tree_trunk.darkened(0.2)
			blocks.append([Rect2(cx - row_half, top + px * 2.0 + float(row) * px, row_half * 2.0, px), shade])
		blocks.append([Rect2(cx - half, top, half * 2.0, px * 2.0), palette.tree_canopy])
		blocks.append([Rect2(cx - half, top, half * 2.0, px), palette.tree_light])
		for entry in blocks:
			var rim := (entry[0] as Rect2).grow(px * 0.5).intersection(view)
			if rim.size.x > 0.0:
				canvas.draw_rect(rim, palette.tree_rim)
		for entry in blocks:
			var body := (entry[0] as Rect2).intersection(view)
			if body.size.x > 0.0:
				canvas.draw_rect(body, entry[1])
		if landmark.y > 0.45:
			var tree := Vector2(cx - half * 0.4, top - px * 3.0)
			var trunk := Rect2(Vector2(tree.x - px * 0.5, tree.y), Vector2(px, px * 3.0)).intersection(view)
			if trunk.size.x > 0.0:
				canvas.draw_rect(trunk, palette.tree_trunk)
			_pixel_disc(canvas, tree, 10.0, px, palette.tree_rim, view)
			_pixel_disc(canvas, tree, 7.0, px, palette.tree_canopy, view)
			_pixel_disc(canvas, tree + Vector2(-px, -px), 4.0, px, palette.tree_light, view)
