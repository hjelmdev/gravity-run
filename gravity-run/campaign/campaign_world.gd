extends Resource
class_name CampaignWorld
## A campaign world: one biome, its stages in order (the boss last) and the
## map that shows them. Worlds without stages are shown as "coming soon".

@export var world_id: StringName = &"meadow"
@export var number := 1
@export var title := ""
@export var biome_id: StringName = &"classic"
@export var levels: Array[CampaignLevel] = []
## Painted 320x180 map background (drawn x3 with nearest filtering).
@export var map_texture: Texture2D
## Node centres in map pixels, one per stage, in stage order.
@export var map_nodes := PackedVector2Array()
## Accent colour for cards and the world title.
@export var accent := Color("42d6c5")

func is_playable() -> bool:
	return not levels.is_empty()

func get_level(level_id: StringName) -> CampaignLevel:
	for level in levels:
		if level.level_id == level_id:
			return level
	return null

func get_boss() -> CampaignLevel:
	for level in levels:
		if level.is_boss():
			return level
	return null

func total_stars() -> int:
	var total := 0
	for level in levels:
		total += level.stars.size()
	return total
