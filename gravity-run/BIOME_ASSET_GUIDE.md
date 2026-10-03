# Biome graphics assets

The three presentation profiles live in `assets/biomes/definitions/`. A profile
is a `BiomeDefinition` resource; both singleplayer and multiplayer use the same
resource and render path. Biome selection follows course distance in fixed
4,800 px sections (classic, cave, haunted; a 14,400 px cycle). It does not
change course collision, hazard placement, or simulation timing.

## Replacing the surface atlas

1. Import a texture sheet whose tile cells have a consistent pixel size.
2. Create a Godot `TileSet` resource with a `TileSetAtlasSource` for that sheet.
   The atlas source ID is `atlas_source_id`; each tile is identified by its
   `Vector2i(x, y)` cell coordinate.
3. In the biome `.tres`, assign that TileSet, set `tile_world_size` to the
   intended world-space size, and fill `floor_surface_tiles` and
   `ceiling_surface_tiles` with valid atlas cells.
4. Optional `slope_up_tiles`, `slope_down_tiles`, and `ledge_edge_tiles` are
   chosen from the actual course surface. The renderer clips each tile to its
   supported interval, crops the matching atlas UV range at non-grid-aligned
   gaps, follows slope heights, and splits quads at steps. No tile is drawn
   across a gap. `flip_ceiling_tiles` controls the ceiling UV orientation.
5. Optional `decoration_tiles` are placed in the background layer only; they
   do not receive colliders. Optional `background_layers` are tiled behind the
   course, with matching `background_layer_tints` entries for palette variants.

If a TileSet/atlas cell is absent, the renderer leaves the existing vector
terrain fill and edge visible. Background vector motifs remain the fallback
when no replacement background textures are assigned. This makes an art swap
a resource edit rather than a gameplay or collision-code change.

`tools/biome_saw_showcase.tscn` is a local review fixture, not a player menu
entry. It renders all three profiles, uses the regular surface renderer, and
places off-grid gaps, a slope/step, a runner, coin, spike, rock warning, and
saw marks for landscape and portrait review.
