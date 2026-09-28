extends RefCounted
class_name MultiplayerTerminalEvent

static func build_payload(room_id: String, match_generation: String, course_identity: String, player: Dictionary, sent_host_tick: int) -> Dictionary:
	var event_tick := int(player.get("terminal_tick", -1))
	return {
		"kind": "player_terminal",
		"room_id": room_id,
		"match_generation": match_generation,
		"course_identity": course_identity,
		"event_tick": event_tick,
		"sent_host_tick": sent_host_tick,
		"terminal_reason": str(player.get("terminal_reason", "")),
		"terminal_tick": event_tick,
		"player": player.duplicate(true),
	}

static func validation_error(payload: Variant) -> String:
	if not payload is Dictionary:
		return "terminal_payload_not_dictionary"
	var player: Variant = payload.get("player", {})
	if not player is Dictionary or str(player.get("state", "")) not in ["dead", "finished", "disconnected"]:
		return "invalid_terminal_player"
	var event_tick := int(payload.get("event_tick", payload.get("terminal_tick", -1)))
	var sent_host_tick := int(payload.get("sent_host_tick", payload.get("tick", event_tick)))
	var terminal_tick := int(payload.get("terminal_tick", event_tick))
	var player_tick := int(player.get("terminal_tick", -1))
	var terminal_reason := str(payload.get("terminal_reason", player.get("terminal_reason", "")))
	if event_tick < 0 or sent_host_tick < event_tick or terminal_tick != event_tick or player_tick != event_tick:
		return "invalid_terminal_tick"
	if terminal_reason not in ["hazard_hit", "out_of_bounds", "finish_line", "confirmed_disconnect", "explicit_leave"] or str(player.get("terminal_reason", terminal_reason)) != terminal_reason:
		return "terminal_reason_mismatch_or_invalid"
	return ""
