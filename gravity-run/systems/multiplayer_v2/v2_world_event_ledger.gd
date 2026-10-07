extends RefCounted
class_name MultiplayerV2WorldEventLedger

const BASELINE_FORMAT_VERSION := 4

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
			entities[entity_id] = {"incarnation": int(entity.get("incarnation", 1)), "kind": str(entity.get("kind", "")), "ghost_variant": int(entity.get("ghost_variant", 0)), "state": "active", "state_revision": 0, "shared_health": int(entity.get("health", 1)), "winner_peer_id": 0, "award_value": 0, "rock_activation_tick": -1, "saw_activation_tick": -1, "ghost_activation_tick": -1, "ghost_activation_lane": 0, "ghost_activation_world_x": -1.0, "ghost_activation_speed": 0.0, "ghost_target_peer_id": 0}

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
	var next_state := str(commit.get("state_after", "destroyed"))
	var kind := str(entity.get("kind", ""))
	var action := str(commit.get("action", "destroy"))
	if kind == "coin":
		if action != "collect" or str(entity.state) != "active" or next_state != "collected":
			return "invalid_coin_transition"
		var winner := int(commit.get("winner_peer_id", 0))
		var value := int(commit.get("award_value", 0))
		if winner <= 0 or value != 1:
			return "invalid_coin_award"
		entity.winner_peer_id = winner
		entity.award_value = value
	elif kind == "rock":
		if action != "activate_rock" or str(entity.state) != "active" or next_state != "active":
			return "invalid_rock_transition"
		var activation_tick := int(commit.get("rock_activation_tick", -1))
		if activation_tick < 0:
			return "invalid_rock_activation"
		var existing_tick := int(entity.get("rock_activation_tick", -1))
		if existing_tick >= 0:
			return "rock_already_activated"
		entity.rock_activation_tick = activation_tick
	elif kind == "saw":
		if action != "activate_saw" or str(entity.state) != "active" or next_state != "active":
			return "invalid_saw_transition"
		var activation_tick := int(commit.get("saw_activation_tick", -1))
		var existing_tick := int(entity.get("saw_activation_tick", -1))
		if activation_tick < 0:
			return "invalid_saw_activation"
		if existing_tick >= 0:
			return "saw_already_activated"
		entity.saw_activation_tick = activation_tick
	elif kind == "ghost":
		if action != "activate_ghost" or str(entity.state) != "active" or next_state != "active":
			return "invalid_ghost_transition"
		var activation_tick := int(commit.get("ghost_activation_tick", -1))
		if activation_tick < 0:
			return "invalid_ghost_activation"
		if int(entity.get("ghost_activation_tick", -1)) >= 0:
			return "ghost_already_activated"
		if int(entity.get("ghost_variant", 0)) in [2, 3]:
			var lane: Variant = commit.get("ghost_activation_lane", null)
			var world_x: Variant = commit.get("ghost_activation_world_x", null)
			var speed: Variant = commit.get("ghost_activation_speed", null)
			var target_peer: Variant = commit.get("ghost_target_peer_id", null)
			if not lane is int or int(lane) not in [1, 2] or not (world_x is int or world_x is float) or not is_finite(float(world_x)) or float(world_x) < 0.0 or not (speed is int or speed is float) or not is_finite(float(speed)) or float(speed) < 200.0 or float(speed) > 800.0 or not target_peer is int or int(target_peer) <= 0:
				return "invalid_ghost_snapshot"
			entity.ghost_activation_lane = int(lane)
			entity.ghost_activation_world_x = float(world_x)
			entity.ghost_activation_speed = float(speed)
			entity.ghost_target_peer_id = int(target_peer)
		entity.ghost_activation_tick = activation_tick
	elif action not in ["destroy", "damage", "lethal_contact"] or next_state not in ["active", "destroyed"]:
		return "invalid_world_transition"
	entity.state = next_state
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
	var compact_entities: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()
	for entity_id_variant in entity_ids:
		var entity_id := str(entity_id_variant)
		var state: Dictionary = entities[entity_id]
		compact_entities.append([entity_id, int(state.get("incarnation", 1)), str(state.get("state", "")), int(state.get("state_revision", 0)), int(state.get("shared_health", 1)), int(state.get("winner_peer_id", 0)), int(state.get("award_value", 0)), int(state.get("rock_activation_tick", -1)), int(state.get("saw_activation_tick", -1)), int(state.get("ghost_activation_tick", -1)), int(state.get("ghost_activation_lane", 0)), float(state.get("ghost_activation_world_x", -1.0)), float(state.get("ghost_activation_speed", 0.0)), int(state.get("ghost_target_peer_id", 0))])
	return {"baseline_format_version": BASELINE_FORMAT_VERSION, "world_revision": revision, "entities": compact_entities}

func restore_baseline(value: Dictionary) -> bool:
	var baseline_version := int(value.get("baseline_format_version", -1))
	if baseline_version not in [2, 3, BASELINE_FORMAT_VERSION]:
		return false
	var next_revision := int(value.get("world_revision", -1))
	var incoming_entities: Variant = value.get("entities", null)
	if next_revision < 0 or not incoming_entities is Array or incoming_entities.size() != entities.size():
		return false
	var next_entities: Dictionary = {}
	for row_variant in incoming_entities:
		if not row_variant is Array or row_variant.size() != (9 if baseline_version == 2 else (10 if baseline_version == 3 else 14)):
			return false
		var row: Array = row_variant
		if typeof(row[0]) != TYPE_STRING or typeof(row[1]) != TYPE_INT or typeof(row[2]) != TYPE_STRING:
			return false
		for field_index in range(3, row.size()):
			if baseline_version == 4 and field_index in [11, 12]:
				if typeof(row[field_index]) != TYPE_FLOAT and typeof(row[field_index]) != TYPE_INT:
					return false
			elif typeof(row[field_index]) != TYPE_INT:
				return false
		var entity_id := str(row[0])
		if entity_id.is_empty() or next_entities.has(entity_id) or not entities.has(entity_id):
			return false
		var local_entity: Dictionary = entities[entity_id]
		if int(row[1]) != int(local_entity.get("incarnation", 1)) or int(row[3]) < 0 or int(row[3]) > next_revision:
			return false
		var ghost_activation_tick := int(row[9]) if baseline_version >= 3 else -1
		var ghost_activation_lane := int(row[10]) if baseline_version >= 4 else 0
		var ghost_activation_world_x := float(row[11]) if baseline_version >= 4 else -1.0
		var ghost_activation_speed := float(row[12]) if baseline_version >= 4 else 0.0
		var ghost_target_peer_id := int(row[13]) if baseline_version >= 4 else 0
		next_entities[entity_id] = {"incarnation": int(row[1]), "kind": str(local_entity.get("kind", "")), "ghost_variant": int(local_entity.get("ghost_variant", 0)), "state": str(row[2]), "state_revision": int(row[3]), "shared_health": int(row[4]), "winner_peer_id": int(row[5]), "award_value": int(row[6]), "rock_activation_tick": int(row[7]), "saw_activation_tick": int(row[8]), "ghost_activation_tick": ghost_activation_tick, "ghost_activation_lane": ghost_activation_lane, "ghost_activation_world_x": ghost_activation_world_x, "ghost_activation_speed": ghost_activation_speed, "ghost_target_peer_id": ghost_target_peer_id}
	if next_entities.size() != entities.size():
		return false
	for entity_id in next_entities:
		if not entities.has(str(entity_id)):
			return false
		var old: Dictionary = entities[str(entity_id)]
		var incoming: Variant = next_entities[entity_id]
		if not incoming is Dictionary or int(incoming.get("incarnation", -1)) != int(old.get("incarnation", -2)) or str(incoming.get("kind", "")) != str(old.get("kind", "")):
			return false
		var state := str(incoming.get("state", ""))
		if state not in ["active", "destroyed", "collected"]:
			return false
		if str(old.get("kind", "")) == "coin":
			var winner := int(incoming.get("winner_peer_id", 0))
			var coin_award_value := int(incoming.get("award_value", 0))
			if (state == "active" and (winner != 0 or coin_award_value != 0)) or (state == "collected" and (winner <= 0 or coin_award_value != 1)) or state == "destroyed":
				return false
		elif str(old.get("kind", "")) == "rock":
			var activation_tick := int(incoming.get("rock_activation_tick", -1))
			var old_activation_tick := int(old.get("rock_activation_tick", -1))
			if state != "active" or int(incoming.get("winner_peer_id", 0)) != 0 or int(incoming.get("award_value", 0)) != 0 or activation_tick < -1 or (old_activation_tick >= 0 and activation_tick != old_activation_tick):
				return false
		elif str(old.get("kind", "")) == "saw":
			var activation_tick := int(incoming.get("saw_activation_tick", -1))
			var old_activation_tick := int(old.get("saw_activation_tick", -1))
			if state != "active" or int(incoming.get("winner_peer_id", 0)) != 0 or int(incoming.get("award_value", 0)) != 0 or activation_tick < -1 or (old_activation_tick >= 0 and activation_tick != old_activation_tick):
				return false
		elif str(old.get("kind", "")) == "ghost":
			var activation_tick := int(incoming.get("ghost_activation_tick", -1))
			var old_activation_tick := int(old.get("ghost_activation_tick", -1))
			var variant := int(old.get("ghost_variant", 0))
			var lane := int(incoming.get("ghost_activation_lane", 0))
			var world_x := float(incoming.get("ghost_activation_world_x", -1.0))
			var speed := float(incoming.get("ghost_activation_speed", 0.0))
			var target_peer := int(incoming.get("ghost_target_peer_id", 0))
			var empty_snapshot := lane == 0 and world_x == -1.0 and speed == 0.0 and target_peer == 0
			var valid_snapshot := lane in [1, 2] and is_finite(world_x) and world_x >= 0.0 and is_finite(speed) and speed >= 200.0 and speed <= 800.0 and target_peer > 0
			var snapshot_valid := (variant in [2, 3] and ((activation_tick < 0 and empty_snapshot) or (activation_tick >= 0 and valid_snapshot))) or (variant not in [2, 3] and empty_snapshot)
			if state != "active" or int(incoming.get("winner_peer_id", 0)) != 0 or int(incoming.get("award_value", 0)) != 0 or activation_tick < -1 or (old_activation_tick >= 0 and activation_tick != old_activation_tick) or not snapshot_valid:
				return false
			if old_activation_tick >= 0 and (lane != int(old.get("ghost_activation_lane", 0)) or not is_equal_approx(world_x, float(old.get("ghost_activation_world_x", -1.0))) or not is_equal_approx(speed, float(old.get("ghost_activation_speed", 0.0))) or target_peer != int(old.get("ghost_target_peer_id", 0))):
				return false
		elif state == "collected" or int(incoming.get("winner_peer_id", 0)) != 0 or int(incoming.get("award_value", 0)) != 0:
			return false
	for entity_id in entities.keys():
		if not next_entities.has(entity_id):
			return false
	entities = next_entities.duplicate(true)
	revision = next_revision
	events.clear()
	return true
