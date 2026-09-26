class_name BiomeDefinition
extends Resource

## Data-only recipe for selecting atlas tiles while a level chunk is generated.
## Atlas coordinates are TileSetAtlasSource cell coordinates (64 px per cell for
## tilesheet_complete_atlas.tres), not pixel coordinates.

@export var biome_id: StringName
@export var display_name: String
@export var tile_set: TileSet
@export var atlas_source_id: int = 0
@export var palette_row: int = 0
@export var floor_surface_tiles: Array[Vector2i] = []
@export var ceiling_surface_tiles: Array[Vector2i] = []
@export var slope_up_tiles: Array[Vector2i] = []
@export var slope_down_tiles: Array[Vector2i] = []
@export var ledge_edge_tiles: Array[Vector2i] = []
@export var decoration_tiles: Array[Vector2i] = []
@export var background_color: Color = Color("101827")
