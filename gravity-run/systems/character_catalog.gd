extends RefCounted
class_name CharacterCatalog
## Every playable character, in picker order. The first entry is the default.

const DEFINITIONS: Array[CharacterDefinition] = [
	preload("res://characters/runner.tres"),
	preload("res://characters/nova.tres"),
	preload("res://characters/nova_mini.tres"),
	preload("res://characters/fox.tres"),
	preload("res://characters/frog.tres"),
	preload("res://characters/penguin.tres"),
	preload("res://characters/panda.tres"),
	preload("res://characters/axolotl.tres"),
	preload("res://characters/robot.tres"),
	preload("res://characters/cat.tres"),
]

static func default_definition() -> CharacterDefinition:
	return DEFINITIONS[0]

static func get_definition(character_id: StringName) -> CharacterDefinition:
	for definition in DEFINITIONS:
		if definition.id == character_id:
			return definition
	return DEFINITIONS[0]

static func has_character(character_id: StringName) -> bool:
	for definition in DEFINITIONS:
		if definition.id == character_id:
			return true
	return false

static func index_of(character_id: StringName) -> int:
	for index in DEFINITIONS.size():
		if DEFINITIONS[index].id == character_id:
			return index
	return 0

## Characters the player may pick. Unlocking via coins/achievements plugs in here.
static func is_unlocked(definition: CharacterDefinition) -> bool:
	if definition == null or not definition.unlocked_by_default:
		return false
	if definition.campaign_unlock_world != StringName():
		var world := CampaignCatalog.get_world(definition.campaign_unlock_world)
		var boss := world.get_boss() if world != null else null
		return boss != null and Campaign.is_completed(boss)
	return true

## Characters that beating this world's boss unlocks.
static func unlocked_by_world(world_id: StringName) -> Array[CharacterDefinition]:
	var result: Array[CharacterDefinition] = []
	for definition in DEFINITIONS:
		if definition.campaign_unlock_world == world_id:
			result.append(definition)
	return result
