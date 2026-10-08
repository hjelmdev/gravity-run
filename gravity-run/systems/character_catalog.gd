extends RefCounted
class_name CharacterCatalog
## Every playable character, in picker order. The first entry is the default.

const DEFINITIONS: Array[CharacterDefinition] = [
	preload("res://characters/runner.tres"),
	preload("res://characters/nova.tres"),
	preload("res://characters/nova_mini.tres"),
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
	return definition != null and definition.unlocked_by_default
