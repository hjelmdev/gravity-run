extends RefCounted
class_name MultiplayerV2WorldEventLedger

var revision := 0
var entities: Dictionary = {}
var events: Array[Dictionary] = []

func reset(round_entities: Array[Dictionary] = []) -> void:
	revision = 0
	entities.clear()
	events.clear()
	for entity in round_entities:
		var entity_id := str(entity.get("entity_id", ""))
		if not entity_id.is_empty():
			entities[entity_id] = {"incarnation": int(entity.get("incarnation", 1)), "kind": str(entity.get("kind", "")), "state": "active", "state_revision": 0, "shared_health": int(entity.get("health", 1))}

func apply_commit(commit: Dictionary) -> String:
	var entity_id := str(commit.get("entity_id", ""))
	var next_revision := int(commit.get("world_revision", 0))
	if entity_id.is_empty() or next_revision <= 0:
		return "malformed_commit"
	if next_revision <= revision:
		return "duplicate"
	if next_revision != revision + 1:
		return "revision_gap"
	if not entities.has(entity_id):
		return "unknown_entity"
	var entity: Dictionary = entities[entity_id]
	if int(entity.get("incarnation", -1)) != int(commit.get("incarnation", -2)):
		return "incarnation_mismatch"
	if str(entity.get("state", "")) != str(commit.get("state_before", "active")):
		return "state_mismatch"
	entity.state = str(commit.get("state_after", "destroyed"))
	entity.state_revision = next_revision
	if commit.has("health_after"):
		entity.shared_health = int(commit.health_after)
	entities[entity_id] = entity
	revision = next_revision
	events.append(commit.duplicate(true))
	return "applied"

func is_active(entity_id: String, incarnation: int = 1) -> bool:
	if not entities.has(entity_id):
		return false
	var entity: Dictionary = entities[entity_id]
	return int(entity.incarnation) == incarnation and str(entity.state) == "active"

func baseline() -> Dictionary:
	return {"world_revision": revision, "entities": entities.duplicate(true)}

func restore_baseline(value: Dictionary) -> bool:
	var next_revision := int(value.get("world_revision", -1))
	var next_entities: Variant = value.get("entities", null)
	if next_revision < 0 or not next_entities is Dictionary:
		return false
	for entity_id in next_entities:
		if not entities.has(str(entity_id)):
			return false
		var old: Dictionary = entities[str(entity_id)]
		var incoming: Variant = next_entities[entity_id]
		if not incoming is Dictionary or int(incoming.get("incarnation", -1)) != int(old.get("incarnation", -2)):
			return false
	for entity_id in entities.keys():
		if not next_entities.has(entity_id):
			return false
	entities = next_entities.duplicate(true)
	revision = next_revision
	events.clear()
	return true
