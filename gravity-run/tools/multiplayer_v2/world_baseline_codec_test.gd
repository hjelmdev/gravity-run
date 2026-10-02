extends SceneTree

const Ledger := preload("res://systems/multiplayer_v2/v2_world_event_ledger.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var original := Ledger.new()
	original.reset([
		{"entity_id": "coin_1_00000_0", "incarnation": 2, "kind": "coin", "health": 1},
		{"entity_id": "rock_a", "incarnation": 3, "kind": "rock", "health": 1},
		{"entity_id": "wall_a", "incarnation": 1, "kind": "block", "health": 2}
	])
	_check(original.apply_commit({"world_revision": 1, "entity_id": "coin_1_00000_0", "incarnation": 2, "action": "collect", "state_before": "active", "state_after": "collected", "winner_peer_id": 2, "award_value": 1}) == "applied", "source ledger records coin winner")
	_check(original.apply_commit({"world_revision": 2, "entity_id": "rock_a", "incarnation": 3, "action": "activate_rock", "state_before": "active", "state_after": "active", "rock_activation_tick": 48}) == "applied", "source ledger records rock activation")
	var snapshot: Dictionary = original.baseline()
	_check(int(snapshot.get("baseline_format_version", -1)) == Ledger.BASELINE_FORMAT_VERSION, "compact snapshot declares a versioned codec")
	var replica := Ledger.new()
	replica.reset([
		{"entity_id": "coin_1_00000_0", "incarnation": 2, "kind": "coin", "health": 1},
		{"entity_id": "rock_a", "incarnation": 3, "kind": "rock", "health": 1},
		{"entity_id": "wall_a", "incarnation": 1, "kind": "block", "health": 2}
	])
	_check(replica.restore_baseline(snapshot), "valid compact snapshot restores")
	_check(int(replica.entities["coin_1_00000_0"].winner_peer_id) == 2 and int(replica.entities["coin_1_00000_0"].award_value) == 1, "restore keeps awarded coin counter state even when commit history is empty")
	_check(int(replica.entities["rock_a"].rock_activation_tick) == 48 and replica.events.is_empty(), "restore keeps permanent rock activation while not depending on event history")
	var unchanged: Dictionary = replica.baseline()
	var wrong_version := snapshot.duplicate(true)
	wrong_version["baseline_format_version"] = 99
	_reject_without_mutation(replica, unchanged, wrong_version, "unknown codec version rejected atomically")
	var malformed_row_type := snapshot.duplicate(true)
	malformed_row_type.entities[0][4] = "1"
	_reject_without_mutation(replica, unchanged, malformed_row_type, "malformed row value type rejected atomically")
	var duplicate_id := snapshot.duplicate(true)
	duplicate_id.entities[1][0] = duplicate_id.entities[0][0]
	_reject_without_mutation(replica, unchanged, duplicate_id, "duplicate entity id rejected atomically")
	var missing_row := snapshot.duplicate(true)
	missing_row.entities.pop_back()
	_reject_without_mutation(replica, unchanged, missing_row, "missing entity rejected atomically")
	var unknown_id := snapshot.duplicate(true)
	unknown_id.entities[0][0] = "not_in_manifest"
	_reject_without_mutation(replica, unchanged, unknown_id, "unknown entity id rejected atomically")
	var bad_incarnation := snapshot.duplicate(true)
	bad_incarnation.entities[0][1] = 1
	_reject_without_mutation(replica, unchanged, bad_incarnation, "wrong incarnation rejected atomically")
	var bad_revision := snapshot.duplicate(true)
	bad_revision.entities[0][3] = int(snapshot.world_revision) + 1
	_reject_without_mutation(replica, unchanged, bad_revision, "future entity revision rejected atomically")
	var missing_format := snapshot.duplicate(true)
	missing_format.erase("baseline_format_version")
	_reject_without_mutation(replica, unchanged, missing_format, "unversioned snapshot rejected atomically")
	print("Compact baseline codec tests passed.")
	quit(1 if failures > 0 else 0)

func _reject_without_mutation(ledger: RefCounted, before: Dictionary, malformed: Dictionary, label: String) -> void:
	_check(not ledger.restore_baseline(malformed), label)
	_check(ledger.baseline() == before, "%s and leaves the previous ledger unchanged" % label)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
