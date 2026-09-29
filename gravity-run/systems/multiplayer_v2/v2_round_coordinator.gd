extends RefCounted
class_name MultiplayerV2RoundCoordinator

signal control_requested(peer_id: int, kind: String, payload: Dictionary)
signal round_started(round_id: String, descriptor: Dictionary)
signal round_failed(reason: String)

const START_LEAD_USEC := 2_500_000
const ACK_MARGIN_USEC := 500_000

enum State { IDLE, PREPARING, COMMITTING, RUNNING, CANCELLED }

var state := State.IDLE
var round_id := ""
var lobby_generation := 0
var manifest_hash := ""
var host_start_usec := -1
var start_ack_deadline_usec := -1
var is_host := false
var peer_ids: Array[int] = []
var prepared_peers: Dictionary = {}
var start_acks: Dictionary = {}
var clock := MultiplayerV2RoundClock.new()
var round_descriptor: Dictionary = {}

func prepare_as_host(descriptor: Dictionary, peers: Array[int], now_usec: int) -> bool:
	if state not in [State.IDLE, State.CANCELLED, State.RUNNING]:
		return false
	_reset_round(descriptor, peers, true)
	state = State.PREPARING
	prepared_peers[1] = false
	for peer_id in peer_ids:
		control_requested.emit(peer_id, "PREPARE_ROUND", _control_payload())
	_try_commit(now_usec)
	return true

func receive_prepare_as_guest(descriptor: Dictionary) -> bool:
	if state not in [State.IDLE, State.CANCELLED, State.RUNNING]:
		return false
	_reset_round(descriptor, [], false)
	state = State.PREPARING
	return true

func mark_local_prepared(now_usec: int) -> void:
	if state != State.PREPARING:
		return
	if is_host:
		prepared_peers[1] = true
		_try_commit(now_usec)
	else:
		control_requested.emit(1, "PREPARED", _control_payload())

func acknowledge_prepared(peer_id: int, received_round_id: String, now_usec: int) -> bool:
	if not is_host or state != State.PREPARING or received_round_id != round_id or peer_id not in peer_ids:
		return false
	prepared_peers[peer_id] = true
	_try_commit(now_usec)
	return true

func receive_commit_as_guest(descriptor: Dictionary) -> bool:
	if is_host or state != State.PREPARING or str(descriptor.get("round_id", "")) != round_id:
		return false
	host_start_usec = int(descriptor.get("start_at_host_usec", -1))
	if host_start_usec <= 0 or not clock.is_synchronized():
		return false
	state = State.COMMITTING
	start_acks[1] = true
	control_requested.emit(1, "START_ACK", _control_payload())
	return true

func acknowledge_start(peer_id: int, received_round_id: String, now_usec: int) -> bool:
	if not is_host or state != State.COMMITTING or received_round_id != round_id or peer_id not in peer_ids:
		return false
	start_acks[peer_id] = true
	return true

func process(now_usec: int) -> void:
	if is_host and state == State.PREPARING:
		_try_commit(now_usec)
	elif state == State.COMMITTING:
		if is_host and not _all_peers(start_acks) and now_usec >= start_ack_deadline_usec:
			cancel("start_ack_timeout")
			return
		if is_host and _all_peers(start_acks) and now_usec >= host_start_usec:
			_start()
		elif not is_host and now_usec >= clock.host_time_to_local_usec(host_start_usec):
			_start()

func cancel(reason: String) -> void:
	state = State.CANCELLED
	control_requested.emit(0 if is_host else 1, "CANCEL_START", {"round_id": round_id, "reason": reason})
	round_failed.emit(reason)

func _reset_round(descriptor: Dictionary, peers: Array[int], host: bool) -> void:
	state = State.IDLE
	round_descriptor = descriptor.duplicate(true)
	round_id = str(descriptor.get("round_id", ""))
	lobby_generation = int(descriptor.get("lobby_generation", 0))
	manifest_hash = str(descriptor.get("manifest_hash", ""))
	peer_ids = peers.duplicate()
	is_host = host
	prepared_peers.clear()
	start_acks.clear()
	clock.reset_round()
	host_start_usec = -1
	start_ack_deadline_usec = -1

func _try_commit(now_usec: int) -> void:
	if not is_host or state != State.PREPARING or not _all_peers(prepared_peers):
		return
	host_start_usec = now_usec + START_LEAD_USEC
	start_ack_deadline_usec = host_start_usec - ACK_MARGIN_USEC
	state = State.COMMITTING
	start_acks[1] = true
	for peer_id in peer_ids:
		control_requested.emit(peer_id, "COMMIT_START", _control_payload())

func _all_peers(values: Dictionary) -> bool:
	if not bool(values.get(1, is_host)):
		return false
	for peer_id in peer_ids:
		if not bool(values.get(peer_id, false)):
			return false
	return true

func _control_payload() -> Dictionary:
	return {"round_id": round_id, "lobby_generation": lobby_generation, "manifest_hash": manifest_hash, "start_at_host_usec": host_start_usec}

func _start() -> void:
	state = State.RUNNING
	clock.commit_start(clock.host_time_to_local_usec(host_start_usec))
	round_started.emit(round_id, round_descriptor.duplicate(true))
