extends SceneTree
const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")

class LocalService extends Service:
	func _ready() -> void:
		_create_network_branch()
	func _process(delta: float) -> void:
		if not _active:
			return
		_process_reconnect_sync(delta)
		_process_result_delivery(delta)
		_process_terminal_delivery(delta)
		_check_disconnect_grace()
		_heartbeat_elapsed += delta
		if _heartbeat_elapsed >= 1.0:
			_heartbeat_elapsed = 0
			for peer_id in connected_peer_ids():
				send_control(peer_id, "HEARTBEAT", {})
	func _set_backend_phase(phase: String) -> void:
		room_state["phase"] = phase
	func _ensure_manifest() -> void:
		pass

var clients: Dictionary = {}
var connections: Array[WebRTCPeerConnection] = []
var elapsed := 0.0
var confirmed_at := -1.0
var round_number := 0
var waiting_results := false
var waiting_lobby := false
var finished_rounds := 0
var manifest: Resource
var roster: Array = []

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	manifest = Builder.new().build(1260459445, 45000, 4).manifest
	for id in [1, 2, 3]:
		roster.append({"user_id": "user-%d" % id, "display_name": "Player %d" % id, "player_slot": id, "is_ready": true, "is_connected": true, "skin_id": id - 1, "loaded_manifest_hash": str(manifest.manifest_hash)})
	for id in [1, 2, 3]:
		var service := LocalService.new()
		service.name = "Client%d" % id
		root.add_child(service)
		service.room_state = {"room_id": "local-room", "room_session_id": "local-session", "owner_user_id": "user-1", "phase": "OPEN", "lobby_generation": 1, "manifest_hash": str(manifest.manifest_hash), "members": roster.duplicate(true)}
		service.identity_user_id = "user-%d" % id
		service.current_manifest = manifest
		var peer := WebRTCMultiplayerPeer.new()
		_require((peer.create_server([]) if id == 1 else peer.create_client(id)) == OK, "peer creation")
		service.webrtc_peer = peer
		service.network_api.multiplayer_peer = peer
		service.session = {"local_peer_id": id, "role": "host" if id == 1 else "guest"}
		service._active = true
		clients[id] = service
	for id in [2, 3]:
		var host := WebRTCPeerConnection.new()
		var guest := WebRTCPeerConnection.new()
		_require(host.initialize({"iceServers": []}) == OK and guest.initialize({"iceServers": []}) == OK, "ICE initialization")
		connections.append(host)
		connections.append(guest)
		host.session_description_created.connect(_description.bind(host, guest))
		guest.session_description_created.connect(_description.bind(guest, host))
		host.ice_candidate_created.connect(_ice.bind(guest))
		guest.ice_candidate_created.connect(_ice.bind(host))
		_require(clients[1].webrtc_peer.add_peer(host, id) == OK and clients[id].webrtc_peer.add_peer(guest, 1) == OK, "peer registration")
		_require(host.create_offer() == OK, "offer")

func _description(type: String, sdp: String, local: WebRTCPeerConnection, remote: WebRTCPeerConnection) -> void:
	_require(local.set_local_description(type, sdp) == OK and remote.set_remote_description(type, sdp) == OK, "description")

func _ice(media: String, index: int, candidate: String, remote: WebRTCPeerConnection) -> void:
	remote.add_ice_candidate(media, index, candidate)

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 40.0:
		_require(false, "lifecycle exceeded deadline")
		return false
	if clients.size() != 3:
		return false
	var host: LocalService = clients[1]
	var all_confirmed: bool = host._session_confirmed_peers.has(2) and host._session_confirmed_peers.has(3) and clients[2]._session_confirmed_peers.has(1) and clients[3]._session_confirmed_peers.has(1)
	if not all_confirmed:
		return false
	if confirmed_at < 0:
		confirmed_at = elapsed
		print("Three real WebRTC sessions confirmed automatically.")
	# Hold in the lobby long enough to expose the previous liveness timeout.
	if elapsed - confirmed_at < 20.0:
		return false
	if waiting_results:
		for service in clients.values():
			if not service._result_committed:
				return false
		for service in clients.values():
			_require(int(service._committed_result.placements[0].owner_peer_id) == 2, "authoritative result ranks farthest runner first")
		if not bool(host._result_acks.get(2, false)) or not bool(host._result_acks.get(3, false)):
			return false
		finished_rounds += 1
		host.room_state.lobby_generation += 1
		host.room_state.phase = "OPEN"
		host._complete_lobby_return()
		for peer_id in host.connected_peer_ids():
			host.send_control(peer_id, "RETURN_TO_LOBBY", {"room": host.room_state.duplicate(true)})
		waiting_results = false
		waiting_lobby = true
		return false
	if waiting_lobby:
		for service in clients.values():
			if not service._round_id.is_empty() or service.room_state.phase != "OPEN":
				return false
		waiting_lobby = false
		if finished_rounds == 3:
			print("Real WebRTC session tests passed: initial sync, 20s lobby, three result/ACK/lobby RPC cycles, preserved peer IDs.")
			for service in clients.values():
				service._active = false
				service.webrtc_peer.close()
			quit()
			return false
	round_number += 1
	for service in clients.values():
		service.begin_round("local-round-%d" % round_number, int(service.room_state.lobby_generation))
		service._round_coordinator.round_descriptor = {"players": roster.duplicate(true)}
		service._round_coordinator.state = service.RoundCoordinatorScript.State.RUNNING
		service.room_state.phase = "RUNNING"
	clients[1].submit_local_terminal("dead", "spikes", 198, 1846.5, 438.0)
	clients[3].submit_local_terminal("dead", "step_spikes", 312, 2780.0, 126.25, -1)
	clients[2].submit_local_terminal("dead", "spikes", 1591, 13438.333, 478.0)
	waiting_results = true
	return false

func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
