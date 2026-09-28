extends Node

const TransportScript := preload("res://systems/webrtc_match_transport.gd")

func _ready() -> void:
	var transport: Node = TransportScript.new()
	transport.set("_room_id", "room-test")
	transport.set("_is_owner", true)
	transport.set("_owner_user_id", "host")
	transport.set("_attempt_by_peer", {"guest": "old-attempt"})
	transport.call("handle_signal", {
		"room_id": "room-test",
		"from_user_id": "guest",
		"attempt_id": "new-attempt",
		"type": "restart",
		"body": {"previous_attempt_id": "old-attempt", "next_attempt_id": "new-attempt"},
	})
	assert(transport.get("_attempt_by_peer").get("guest", "") == "new-attempt", "a room-authenticated restart handshake should replace the guest's old generation")
	transport.call("handle_signal", {
		"room_id": "room-test",
		"from_user_id": "guest",
		"attempt_id": "old-attempt",
		"type": "offer",
		"body": {"sdp_type": "offer", "sdp": "stale"},
	})
	assert(transport.get("_attempt_by_peer").get("guest", "") == "new-attempt" and not transport.get("_entries").has("guest"), "late SDP from a retired attempt must not replace the new generation")
	transport.set("_is_owner", false)
	transport.set("_started", true)
	transport.set("_room_id", "room-test")
	transport.set("_retry_count_by_peer", {"host": TransportScript.MAX_CONNECTION_RETRIES})
	transport.call("_fail_peer", "host", "test exhausted retry budget")
	assert(not bool(transport.get("_started")) and (transport.get("_entries") as Dictionary).is_empty(), "exhausted retries must leave the same-room reconnect action available")
	print("Multiplayer transport generation/retry tests passed.")
	transport.free()
	get_tree().quit()
