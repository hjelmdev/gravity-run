extends RefCounted
class_name BiomeKeys
## Biome keys (equipment step 4): one key per campaign world, won by beating
## that world's boss and active only on that world's stages, so replaying a
## world for its stars gets a little easier. Keys are campaign rewards kept in
## the local campaign progress (beating the boss is the proof), not inventory
## items, because effect items are off on campaign stages.
##
##   ice_picks    (cave)     one hit from a falling rock or icicle per stage is
##                           shrugged off
##   lantern      (haunted)  fog and darkness clear further ahead of the runner
##   heat_shield  (volcano)  one hit from lava (crack, pool, volcano or ember
##                           bomb) per stage is shrugged off

const KEYS := {
	&"cave": {"key_id": "ice_picks", "title": "Ice picks", "description": "One hit from a falling rock or icicle per stage is shrugged off"},
	&"haunted": {"key_id": "lantern", "title": "Lantern", "description": "Fog and darkness clear further ahead of you"},
	&"volcano": {"key_id": "heat_shield", "title": "Heat shield", "description": "One hit from lava per stage is shrugged off"},
}
## How much further the lantern lets the runner see into fog and darkness.
const LANTERN_CLEAR_SCALE := 1.6

## The key of a world, or "" when the world has none.
static func key_id_for_world(world_id: StringName) -> String:
	return str((KEYS.get(world_id, {}) as Dictionary).get("key_id", ""))

static func title_of(world_id: StringName) -> String:
	return str((KEYS.get(world_id, {}) as Dictionary).get("title", ""))

static func description_of(world_id: StringName) -> String:
	return str((KEYS.get(world_id, {}) as Dictionary).get("description", ""))

## True once the world's boss is beaten.
static func is_owned(world: CampaignWorld) -> bool:
	if world == null or key_id_for_world(world.world_id).is_empty():
		return false
	var boss := world.get_boss()
	return boss != null and Campaign.is_completed(boss)

## The key that works on a stage, or "" (none, or not won yet). Boss stages
## are fought without it.
static func active_key_for(level: CampaignLevel) -> String:
	if level == null or level.is_boss():
		return ""
	var world := CampaignCatalog.world_of(level)
	return key_id_for_world(world.world_id) if world != null and is_owned(world) else ""

## Whether a hazard node belongs to the family a key guards against.
static func guards_against(key_id: String, hazard: Node) -> bool:
	match key_id:
		"ice_picks":
			return hazard.is_in_group("falling_rocks")
		"heat_shield":
			return hazard.is_in_group("lava_hazards") or hazard.is_in_group("ember_bombs")
	return false
