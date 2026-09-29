extends RefCounted
class_name MultiplayerV2Protocol

const NETWORK_MODE := "v2"
const PROTOCOL_VERSION := 1
const MAX_SAMPLE_HISTORY := 64

static func envelope(room_id: String, room_session_id: String, lobby_generation: int, round_id: String, kind: String, sender_peer_id: int, sequence: int, body: Dictionary) -> Dictionary:
	return {"network_mode": NETWORK_MODE, "protocol_version": PROTOCOL_VERSION, "room_id": room_id, "room_session_id": room_session_id, "lobby_generation": lobby_generation, "round_id": round_id, "kind": kind, "sender_peer_id": sender_peer_id, "sequence": sequence, "body": body.duplicate(true)}

static func validate_envelope(message: Dictionary, expected: Dictionary) -> String:
	if str(message.get("network_mode", "")) != NETWORK_MODE:
		return "wrong_network_mode"
	if int(message.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return "protocol_version_mismatch"
	for field in ["room_id", "room_session_id", "round_id"]:
		if str(message.get(field, "")) != str(expected.get(field, "")):
			return "%s_mismatch" % field
	if int(message.get("lobby_generation", -1)) != int(expected.get("lobby_generation", -2)):
		return "lobby_generation_mismatch"
	if int(message.get("sequence", -1)) < 0 or not message.get("body", null) is Dictionary:
		return "malformed_envelope"
	return ""
