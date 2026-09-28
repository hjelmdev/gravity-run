extends RefCounted
class_name MultiplayerLocalPrediction

const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const MAX_REPLAY_TICKS := 24

var simulation: RefCounted
var local_user_id := ""
var _pending_inputs: Array[Dictionary] = []

func bind(target_simulation: RefCounted, user_id: String) -> void:
	simulation = target_simulation
	local_user_id = user_id
	_pending_inputs.clear()

func remember_input(sequence: int, target_tick: int, gravity_direction: int, sent_at_msec: int) -> bool:
	if sequence <= 0 or target_tick < 0 or gravity_direction not in [-1, 1]:
		return false
	for input in _pending_inputs:
		if int(input.get("sequence", 0)) == sequence:
			return false
	_pending_inputs.append({
		"sequence": sequence,
		"target_tick": target_tick,
		"gravity_direction": gravity_direction,
		"sent_at_msec": sent_at_msec,
	})
	return true

func pending_inputs() -> Array[Dictionary]:
	return _pending_inputs.duplicate(true)

func reject_input(sequence: int) -> bool:
	var remaining: Array[Dictionary] = []
	var found := false
	for input in _pending_inputs:
		if int(input.get("sequence", 0)) == sequence:
			found = true
		else:
			remaining.append(input)
	_pending_inputs = remaining
	return found

func clear() -> void:
	_pending_inputs.clear()

func reconcile(checkpoint: Variant, requested_target_tick: int) -> Dictionary:
	if simulation == null or not checkpoint is Dictionary:
		return {"ok": false, "reason": "missing_simulation_or_checkpoint"}
	var checkpoint_tick := int(checkpoint.get("tick", -1))
	if checkpoint_tick < 0:
		return {"ok": false, "reason": "invalid_checkpoint_tick"}
	var target_tick := maxi(requested_target_tick, checkpoint_tick)
	var replay_end := mini(target_tick, checkpoint_tick + MAX_REPLAY_TICKS)
	var old_tick := int(simulation.get("tick"))
	var old_player: Dictionary = simulation.get_player(local_user_id)
	if not simulation.restore_checkpoint(checkpoint):
		return {"ok": false, "reason": "checkpoint_validation_failed"}

	var confirmed := {}
	var results_by_player: Variant = checkpoint.get("processed_inputs", {})
	var local_results: Variant = results_by_player.get(local_user_id, []) if results_by_player is Dictionary else []
	if local_results is Array:
		for result in local_results:
			if result is Dictionary and int(result.get("processed_tick", -1)) <= checkpoint_tick:
				confirmed[int(result.get("sequence", 0))] = result
	var remaining: Array[Dictionary] = []
	var confirmed_results: Array[Dictionary] = []
	for input in _pending_inputs:
		var sequence := int(input.get("sequence", 0))
		if confirmed.has(sequence):
			var result: Dictionary = (confirmed[sequence] as Dictionary).duplicate(true)
			result["sent_at_msec"] = int(input.get("sent_at_msec", 0))
			confirmed_results.append(result)
		else:
			remaining.append(input)
	_pending_inputs = remaining

	var replay_errors: Array[Dictionary] = []
	for input in _pending_inputs:
		var target := int(input.get("target_tick", checkpoint_tick + 1))
		if target <= checkpoint_tick:
			target = checkpoint_tick + 1
		var queued: Dictionary = simulation.queue_flip(
			local_user_id,
			int(input.get("sequence", 0)),
			int(input.get("gravity_direction", 0)),
			target
		)
		if not bool(queued.get("queued", false)):
			replay_errors.append({"sequence": int(input.get("sequence", 0)), "reason": str(queued.get("reason", "queue_failed"))})
	if replay_end > checkpoint_tick:
		simulation.advance_to_tick(replay_end, MAX_REPLAY_TICKS)
	var new_player: Dictionary = simulation.get_player(local_user_id)
	return {
		"ok": true,
		"checkpoint_tick": checkpoint_tick,
		"old_tick": old_tick,
		"target_tick": target_tick,
		"replayed_to_tick": int(simulation.get("tick")),
		"replay_was_bounded": replay_end < target_tick,
		"old_player": old_player,
		"new_player": new_player,
		"confirmed_inputs": confirmed_results,
		"replay_errors": replay_errors,
	}
