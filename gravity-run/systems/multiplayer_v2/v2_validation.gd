extends RefCounted
class_name MultiplayerV2Validation

const MAX_SAMPLE_TICK_JUMP := 600

static func validate_sample(sample: Dictionary, expected_round_id: String, expected_peer_id: int, previous_sequence: int, previous_tick: int) -> String:
	if str(sample.get("round_id", "")) != expected_round_id:
		return "round_mismatch"
	if int(sample.get("owner_peer_id", -1)) != expected_peer_id:
		return "owner_mismatch"
	if int(sample.get("sample_seq", -1)) <= previous_sequence:
		return "stale_sequence"
	if sample.size() > 24:
		return "sample_too_large"
	var tick := int(sample.get("simulation_tick", -1))
	if tick < previous_tick or tick - previous_tick > MAX_SAMPLE_TICK_JUMP:
		return "invalid_tick_delta"
	for field in ["world_x", "y", "velocity_x", "velocity_y"]:
		var value := float(sample.get(field, NAN))
		if not is_finite(value) or absf(value) > 1_000_000.0:
			return "invalid_%s" % field
	if int(sample.get("gravity_direction", 0)) not in [-1, 1]:
		return "invalid_gravity"
	if str(sample.get("locomotion_state", "")) not in ["running", "blocked", "pending_barrel", "dead", "finished"]:
		return "invalid_locomotion_state"
	return ""

static func validate_terminal(message: Dictionary, round_id: String, owner_peer_id: int) -> String:
	if str(message.get("round_id", "")) != round_id:
		return "round_mismatch"
	if int(message.get("owner_peer_id", -1)) != owner_peer_id:
		return "owner_mismatch"
	if str(message.get("state", "")) not in ["dead", "finished", "disconnected"]:
		return "invalid_terminal_state"
	if int(message.get("simulation_tick", -1)) < 0:
		return "invalid_terminal_tick"
	return ""
