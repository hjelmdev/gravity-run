class_name BiomeDefinition
extends Resource

## Data-only recipe for selecting atlas tiles while a level chunk is generated.
## Atlas coordinates are TileSetAtlasSource cell coordinates (64 px per cell for
## tilesheet_complete_atlas.tres), not pixel coordinates.

@export var biome_id: StringName
@export var display_name: String
@export var tile_set: TileSet
@export var atlas_source_id: int = 0
@export var tile_world_size: Vector2i = Vector2i(64, 64)
## World px the surface tiles reach above the surface line (grass blade tips).
@export var tile_rise: int = 0
## Pixel art: tiles and the fill texture are drawn with nearest filtering.
@export var pixel_art := false
## Optional texture repeated under the surface (world-anchored) instead of the
## flat terrain_fill_color, scaled by fill_texture_scale world px per texel.
@export var terrain_fill_texture: Texture2D
@export var fill_texture_scale: float = 2.0
## The thin coloured line along the surface; off when the tiles draw their own.
@export var draw_edge_line := true
## The pixel style (shared pixel art for ground, hazards and backdrop) and its
## colours. Null: the biome draws itself the classic way.
@export var pixel_palette: PixelPalette
@export var flip_ceiling_tiles := true
@export var palette_row: int = 0
@export var floor_surface_tiles: Array[Vector2i] = []
@export var ceiling_surface_tiles: Array[Vector2i] = []
@export var slope_up_tiles: Array[Vector2i] = []
@export var slope_down_tiles: Array[Vector2i] = []
@export var ledge_edge_tiles: Array[Vector2i] = []
@export var decoration_tiles: Array[Vector2i] = []
## Optional full-viewport background layers. When present, these replace the
## renderer's vector fallback motifs and can be swapped without code changes.
@export var background_layers: Array[Texture2D] = []
@export var background_layer_tints: Array[Color] = []
## Background layer scale/placement and scroll speed. Each item stays anchored to
## course distance even when a biome only occupies a narrow viewport fragment.
@export var background_layer_height_ratios := PackedFloat32Array()
@export var background_layer_y_ratios := PackedFloat32Array()
@export var background_layer_parallax := PackedFloat32Array()
@export var background_color: Color = Color("101827")
@export var accent_color: Color = Color("42d6c5")
@export var surface_tint: Color = Color.WHITE
@export var surface_overlay_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var terrain_fill_color: Color = Color("202d40")
@export var terrain_edge_color: Color = Color("42d6c5")
@export var layer_colors: Array[Color] = [Color("26364b"), Color("1d2d42"), Color("19263a")]
