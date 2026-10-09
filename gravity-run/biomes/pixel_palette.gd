extends Resource
class_name PixelPalette
## Everything that makes one biome's pixel art its own: colours plus a few
## switches. The shared pixel-art code reads it everywhere:
##   tools/pixel_tiles/generate_biome_tiles.gd  the ground (surface caps, fill)
##   hazards/pixel_hazard_art.gd                blocks, spikes, saws, rocks, barrels
##   BiomeRenderer._draw_pixel_backdrop          sky, sun, clouds, hills, trees
## A biome turns the pixel style on by setting BiomeDefinition.pixel_palette.
## The defaults are the meadow's, so a new biome only overrides what differs.
## See docs/PIXEL_BIOMES.md.

@export_group("Ground")
## Outline of the ground art (surface caps).
@export var ground_outline := Color8(23, 52, 33)
## The surface growth (grass on the meadow): highlight, base, mid, dark.
@export var surface_hi := Color8(170, 226, 92)
@export var surface := Color8(108, 190, 72)
@export var surface_mid := Color8(70, 152, 60)
@export var surface_dark := Color8(44, 108, 50)
## The fill under the surface (dirt on the meadow).
@export var fill := Color8(122, 82, 54)
@export var fill_shade := Color8(104, 69, 46)
@export var fill_dark := Color8(76, 49, 35)
@export var fill_light := Color8(146, 102, 68)
## Pebbles in the fill.
@export var pebble := Color8(150, 142, 132)
@export var pebble_light := Color8(190, 184, 172)
@export var pebble_dark := Color8(104, 98, 92)
@export var pebble_count := 7
## Blade tips sticking up above the surface line.
@export var blade_tips := true
## Flowers per surface variant (8 variants) and their colours.
@export var flower_counts := PackedInt32Array([0, 1, 0, 2, 1, 0, 1, 2])
@export var flower_colors: Array[Color] = [Color8(250, 246, 236), Color8(255, 214, 74), Color8(244, 128, 168), Color8(150, 196, 255)]
@export var flower_center := Color8(255, 176, 40)
@export var stem := Color8(52, 124, 54)
## Clover marks in two of the variants.
@export var clover := true
## Changes every random choice of the ground art (another biome's tufts and
## pebbles should not sit in the same places as the meadow's).
@export var seed_offset := 0

@export_group("Hazards")
@export var hazard_outline := Color8(23, 40, 33)
## Stone of pillars and falling rocks.
@export var stone := Color8(150, 146, 136)
@export var stone_light := Color8(196, 192, 178)
@export var stone_dark := Color8(104, 100, 96)
@export var mortar := Color8(84, 80, 78)
## What grows on stone (moss on the meadow): base and dark.
@export var growth := Color8(96, 164, 70)
@export var growth_dark := Color8(58, 120, 56)
@export var steel := Color8(176, 186, 198)
@export var steel_light := Color8(232, 238, 244)
@export var steel_dark := Color8(108, 116, 132)
@export var wood := Color8(198, 124, 64)
@export var wood_dark := Color8(70, 44, 30)
@export var iron := Color8(78, 84, 98)
@export var rubber := Color8(64, 183, 174)
@export var rubber_dull := Color8(57, 124, 120)
@export var rubber_dark := Color8(20, 63, 87)
@export var axle := Color8(255, 178, 83)
## Shape of blocks: "pillar" (rough stone) or "grave" (a headstone).
@export_enum("pillar", "grave") var block_style := "pillar"
## Shape of spikes: "steel", "cross" (a stone cross-spear), "ice" (an ice
## shard) or "cactus" (a spiny cactus).
@export_enum("steel", "cross", "ice", "cactus") var spike_style := "steel"
## Rolling barrels: "wood" barrels, "snowball"s or "tumbleweed"s.
@export_enum("wood", "snowball", "tumbleweed") var barrel_style := "wood"
## Ice (icicles).
@export var ice := Color8(185, 232, 245)
@export var ice_light := Color8(234, 255, 255)
@export var ice_dark := Color8(139, 199, 223)

@export_group("Backdrop")
## Draw the shared pixel backdrop (off: the biome draws its own).
@export var backdrop := true
@export var sky_bands: Array[Color] = [Color(0.42, 0.68, 0.92), Color(0.47, 0.72, 0.93), Color(0.53, 0.77, 0.94), Color(0.6, 0.82, 0.95)]
@export var sun := true
@export var sun_halo := Color(1.0, 0.95, 0.7, 0.3)
@export var sun_disc := Color(1.0, 0.86, 0.45)
@export var sun_core := Color(1.0, 0.95, 0.66)
@export var clouds := true
@export var cloud := Color(1.0, 1.0, 1.0, 0.92)
@export var cloud_shade := Color(0.82, 0.9, 0.97, 0.92)
## Hill ranges from far to near: [colour, crest colour] each.
@export var ridge := Color(0.66, 0.82, 0.82)
@export var ridge_crest := Color(0.74, 0.88, 0.86)
@export var hills_far := Color(0.55, 0.77, 0.6)
@export var hills_far_crest := Color(0.64, 0.84, 0.64)
@export var hills_near := Color(0.4, 0.66, 0.42)
@export var hills_near_crest := Color(0.5, 0.75, 0.46)
## Round trees on the near hills.
@export var trees := true
## "round" leafy trees, "dead" bare trees, snowy "pine"s or "cactus"es.
@export_enum("round", "dead", "pine", "cactus") var tree_style := "round"
## Snow on the backdrop (pine tiers and hill crests), and the hills drawn as
## "puffy" cloud banks instead of rolling "hills".
@export var snow := Color(0.95, 0.98, 1.0)
@export_enum("hills", "puffy") var hill_style := "hills"
## Small grassy islands floating in the sky (grass in the tree canopy colours,
## rock in the trunk colour).
@export var islands := false
@export var tree_trunk := Color(0.36, 0.25, 0.18)
@export var tree_rim := Color(0.2, 0.42, 0.26)
@export var tree_canopy := Color(0.3, 0.56, 0.32)
@export var tree_light := Color(0.42, 0.68, 0.38)

## A key that tells palettes apart in caches.
func cache_key() -> String:
	return resource_path if not resource_path.is_empty() else str(get_instance_id())
