extends SceneTree

const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const Coordinator := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")

class TestService extends Service:
	var sent: Array[Dictionary] = []
	var links := PackedInt32Array()
	var restarts := 0
	func connected_peer_ids() -> PackedInt32Array:
		return links
	func send_control(peer_id: int, kind: String, payload: Dictionary) -> void:
		var packet := _session_envelope()
		packet.merge(payload, true)
		sent.append({"target": peer_id, "kind": kind, "payload": packet})
	func _restart_peer_link(_peer_id: int) -> void:
		restarts += 1
	func _ensure_manifest() -> void:
		pass
	func _set_backend_phase(phase: String) -> void:
		room_state["phase"] = phase

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _make_service(host: bool) -> TestService:
	var service := TestService.new()
	service.identity_user_id = "host" if host else "guest"
	service.room_state = {"room_id": "test-room", "room_session_id": "test-session", "owner_user_id": "host", "phase": "OPEN", "lobby_generation": 4, "members": [{"user_id": "host", "player_slot": 1, "display_name": "Ada"}, {"user_id": "guest", "player_slot": 2, "display_name": "Bo"}]}
	service.session = {"role": "host" if host else "guest", "local_peer_id": 1 if host else 2}
	service._active = true
	service.links = PackedInt32Array([2] if host else [1])
	return service

func _deliver(from: TestService, to: TestService, sender: int) -> void:
	var messages := from.sent.duplicate(true)
	from.sent.clear()
	for message in messages:
		to._on_control_rpc(sender, str(message.kind), message.payload)

func _run() -> void:
	var host := _make_service(true)
	var guest := _make_service(false)
	host._on_peer_connected(3)
	guest._on_peer_connected(3)
	_check(not host._reconnect_sync_pending.has(3), "host does not validate an unrostered logical peer")
	_check(not guest._reconnect_sync_pending.has(3), "guest does not start a direct handshake for another guest's logical slot")
	var topology: Dictionary = guest.current_diagnostic_state()
	_check(topology.direct_transport_peers == [1] and topology.logical_roster_peers == [1, 2], "diagnostics distinguish a guest's direct host link from its full logical roster")
	# First connection has no prior outage: it must nevertheless validate.
	host._on_peer_connected(2)
	guest._on_peer_connected(1)
	_check(guest._reconnect_sync_pending.has(1), "first guest connection starts session sync")
	guest._send_reconnect_sync_request()
	_deliver(guest, host, 2)
	_deliver(host, guest, 1)
	_deliver(guest, host, 2)
	_deliver(host, guest, 1)
	_check(host._session_confirmed_peers.has(2) and guest._session_confirmed_peers.has(1), "first connection completes without manual restart")
	_check(not guest._reconnect_sync_pending.has(1), "completion clears pending flag")
	# A stale completion cannot validate a replacement link.
	var old_request := str(guest._sync_request_ids[1])
	guest._disconnect_since_usec[1] = Time.get_ticks_usec() - 20_000_000
	guest._on_peer_connected(1)
	_check(Time.get_ticks_usec() - int(guest._reconnect_sync_since_usec[1]) < 1_000_000, "handshake gets a fresh deadline despite a 20 second outage")
	guest._handle_guest_control("RECONNECT_SYNC_COMPLETE", {"round_id": "", "world_revision": 0, "sync_request_id": old_request})
	_check(guest._reconnect_sync_pending.has(1), "old request completion rejected")
	guest.sent.clear()
	guest._process_reconnect_sync(1.1)
	_check(guest.sent.size() == 1 and guest.sent[0].kind == "RECONNECT_SYNC", "missing ack retries on connected transport")
	guest._reconnect_sync_since_usec[1] = Time.get_ticks_usec() - Service.DISCONNECT_GRACE_USEC - 1
	guest._check_disconnect_grace()
	_check(guest.restarts == 1, "exhausted handshake can recover connected link with correct peer id")
	guest.links = PackedInt32Array()
	guest._reconnect_sync_pending.clear()
	guest._last_heartbeat_usec.clear()
	guest._last_reconnect_attempt_usec.clear()
	guest._disconnect_since_usec[1] = Time.get_ticks_usec() - Service.DISCONNECT_GRACE_USEC - 1
	guest._check_disconnect_grace()
	_check(guest.restarts == 2, "initial transport can recover even with no heartbeat history")
	# Results use frozen round participants, not a subsequently shortened lobby.
	host._round_id = "round-a"
	host._round_coordinator.round_descriptor = {"players": host.room_state.members.duplicate(true)}
	host.room_state.members = [host.room_state.members[0]]
	host.terminal_status = {1: {"owner_peer_id": 1, "state": "dead", "simulation_tick": 10, "world_x": 100.0}, 2: {"owner_peer_id": 2, "state": "dead", "simulation_tick": 20, "world_x": 200.0}}
	host._maybe_finish_round()
	_check(host._committed_result.placements.size() == 2 and int(host._committed_result.placements[0].owner_peer_id) == 2, "result retains departed frozen participant and ranks by distance")
	_check(host._round_coordinator.state == Coordinator.State.FINISHED, "result terminates coordinator")
	# The sequence counter is not a pose. Disconnects must freeze the last state.
	host.terminal_status.clear()
	host._last_sample_by_peer[2] = 42
	host._last_sample_state_by_peer[2] = {"world_x": 345.0, "y": 80.0, "gravity_direction": -1}
	host._commit_terminal(2, {"state": "disconnected", "reason": "connection_grace_expired"})
	_check(float(host.terminal_status[2].world_x) == 345.0 and float(host.terminal_status[2].y) == 80.0 and int(host.terminal_status[2].gravity_direction) == -1, "disconnect freezes last sampled pose and gravity, not sequence counter")
	guest._round_id = "round-a"
	guest._round_coordinator.round_descriptor = host._round_coordinator.round_descriptor.duplicate(true)
	_check(guest._accept_result_commit(host._committed_result), "guest accepts authoritative frozen result")
	_check(guest._accept_result_commit(host._committed_result), "duplicate result is acknowledged idempotently")
	var malformed := host._committed_result.duplicate(true)
	malformed.placements[1] = malformed.placements[0].duplicate(true)
	_check(not guest._accept_result_commit(malformed), "duplicate participant rejected")
	guest._complete_lobby_return()
	_check(not guest._accept_result_commit(host._committed_result), "old result cannot reopen lobby")
	_check(guest.world_simulation == null and guest.terminal_status.is_empty(), "lobby return clears round state")
	host.free()
	guest.free()
	if failures == 0:
		print("V2 session lifecycle tests passed.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
