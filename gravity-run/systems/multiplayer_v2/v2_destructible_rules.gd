extends RefCounted
class_name MultiplayerV2DestructibleRules

enum ContactResult { IGNORE, BLOCK, LETHAL, DAMAGE_AND_CONTINUE, CONSUME_AND_LETHAL }

const POLICIES := {
	"barrel": {"destruction_policy": "consume_on_lethal_contact", "player_contact": ContactResult.CONSUME_AND_LETHAL, "initial_health": 1},
	"breakable_wall": {"destruction_policy": "damage", "player_contact": ContactResult.BLOCK, "initial_health": 1},
	"test_multihp": {"destruction_policy": "damage", "player_contact": ContactResult.BLOCK, "initial_health": 2},
	"spike": {"destruction_policy": "indestructible", "player_contact": ContactResult.LETHAL, "initial_health": 0},
}

static func policy_for(kind: String) -> Dictionary:
	var result: Variant = POLICIES.get(kind, {"destruction_policy": "indestructible", "player_contact": ContactResult.IGNORE, "initial_health": 0})
	return result.duplicate(true)

static func make_request(round_id: String, entity_id: String, incarnation: int, action: String, tick: int, input_sequence: int, world_revision: int, request_id: String) -> Dictionary:
	return {"round_id": round_id, "entity_id": entity_id, "incarnation": incarnation, "action": action, "simulation_tick": tick, "input_seq": input_sequence, "known_world_revision": world_revision, "request_id": request_id}

static func host_commit(ledger: MultiplayerV2WorldEventLedger, request: Dictionary, linked_player_transition: Dictionary = {}) -> Dictionary:
	var entity_id := str(request.get("entity_id", ""))
	var incarnation := int(request.get("incarnation", -1))
	if not ledger.is_active(entity_id, incarnation):
		return {"accepted": false, "reason": "already_consumed", "world_revision": ledger.revision}
	var entity: Dictionary = ledger.entities[entity_id]
	var policy := policy_for(str(entity.get("kind", "")))
	var action := str(request.get("action", "destroy"))
	if action == "damage" and str(policy.destruction_policy) != "damage":
		return {"accepted": false, "reason": "damage_not_allowed", "world_revision": ledger.revision}
	if action not in ["damage", "destroy", "lethal_contact"]:
		return {"accepted": false, "reason": "invalid_action", "world_revision": ledger.revision}
	var health_before := int(entity.get("shared_health", 1))
	var health_after := maxi(health_before - maxi(int(policy.get("damage_per_request", 1)), 1), 0) if action == "damage" else 0
	var next_state := "active" if health_after > 0 else "destroyed"
	var commit := {"world_revision": ledger.revision + 1, "commit_id": "world-%d" % (ledger.revision + 1), "request_id": str(request.get("request_id", "")), "entity_id": entity_id, "incarnation": incarnation, "action": action, "effective_tick": int(request.get("simulation_tick", 0)), "reason": "player_interaction", "state_before": "active", "state_after": next_state, "health_before": health_before, "health_after": health_after}
	if not linked_player_transition.is_empty():
		commit["linked_player_transition"] = linked_player_transition.duplicate(true)
	var result := ledger.apply_commit(commit)
	return {"accepted": result == "applied", "reason": result, "commit": commit, "world_revision": ledger.revision}
