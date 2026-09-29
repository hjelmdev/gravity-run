extends Node
## Real native/browser WebRTC transport, using production RPC endpoint and remote sampler.
## No backend/authentication. This verifies transport delivery, not lobby lifecycle.
const Endpoint := preload("res://systems/multiplayer_v2/v2_rpc_endpoint.gd")
const Track := preload("res://systems/multiplayer_v2/v2_remote_track.gd")
const Validation := preload("res://systems/multiplayer_v2/v2_validation.gd")
var peers: Dictionary = {}
var endpoints: Dictionary = {}
var apis: Dictionary = {}
var connections: Array[WebRTCPeerConnection] = []
var counts: Dictionary = {}
var tracks: Dictionary = {}
var sequences: Dictionary = {}
var elapsed := 0.0
var send_elapsed := 0.0
var active_elapsed := 0.0
var sequence := 0
var errors := 0
var test_root: Node

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	test_root = Node.new()
	add_child(test_root)
	for id in [1, 2, 3]:
		var node := Node.new()
		node.name = "Client%d" % id
		test_root.add_child(node)
		var api := SceneMultiplayer.new()
		get_tree().set_multiplayer(api, node.get_path())
		apis[id] = api
		var peer := WebRTCMultiplayerPeer.new()
		var error := peer.create_server([]) if id == 1 else peer.create_client(id)
		_require(error == OK)
		peers[id] = peer
		api.multiplayer_peer = peer
		var endpoint := Endpoint.new()
		endpoint.name = "Endpoint"
		node.add_child(endpoint)
		endpoints[id] = endpoint
		endpoint.player_sample_received.connect(_received.bind(id))
		tracks[id] = {}
		counts[id] = {}
		sequences[id] = {}
	for guest in [2, 3]:
		var host_connection := WebRTCPeerConnection.new()
		var guest_connection := WebRTCPeerConnection.new()
		_require(host_connection.initialize({"iceServers": []}) == OK)
		_require(guest_connection.initialize({"iceServers": []}) == OK)
		connections.append(host_connection)
		connections.append(guest_connection)
		host_connection.session_description_created.connect(_description.bind(host_connection, guest_connection))
		guest_connection.session_description_created.connect(_description.bind(guest_connection, host_connection))
		host_connection.ice_candidate_created.connect(_ice.bind(guest_connection))
		guest_connection.ice_candidate_created.connect(_ice.bind(host_connection))
		_require(peers[1].add_peer(host_connection, guest) == OK)
		_require(peers[guest].add_peer(guest_connection, 1) == OK)
		_require(host_connection.create_offer() == OK)

func _description(type: String, sdp: String, local: WebRTCPeerConnection, remote: WebRTCPeerConnection) -> void:
	_require(local.set_local_description(type, sdp) == OK)
	_require(remote.set_remote_description(type, sdp) == OK)

func _ice(media: String, index: int, candidate: String, remote: WebRTCPeerConnection) -> void:
	remote.add_ice_candidate(media, index, candidate)

func _process(delta: float) -> void:
	elapsed += delta
	if endpoints.size() != 3:
		return
	var connected: bool = apis[1].get_peers().size() == 2 and apis[2].get_peers().size() >= 1 and apis[3].get_peers().size() >= 1
	if connected:
		active_elapsed += delta
		send_elapsed += delta
		if send_elapsed >= 1.0 / 30.0:
			send_elapsed = fmod(send_elapsed, 1.0 / 30.0)
			sequence += 1
			for owner in [1, 2, 3]:
				var sample := {"round_id": "rpc-test", "owner_peer_id": owner, "sample_seq": sequence, "simulation_tick": sequence * 2, "world_x": 180.0 + sequence * 500.0 / 30.0, "y": 438.0 - owner * sin(active_elapsed) * 30.0, "velocity_x": 500.0, "velocity_y": 0.0, "gravity_direction": 1, "locomotion_state": "running", "last_input_seq": 0}
				if owner == 1:
					_received(1, sample, 1)
				else:
					errors += int(endpoints[owner].send_sample_to_peer(1, sample) != OK)
		for viewer in tracks:
			for track in tracks[viewer].values():
				track.advance(delta)
	if active_elapsed > 5.5 or elapsed > 20.0:
		var passed: bool = connected and errors == 0
		for viewer in [1, 2, 3]:
			for owner in [1, 2, 3]:
				if viewer == owner:
					continue
				passed = passed and int(counts[viewer].get(owner, 0)) > 100
				if tracks[viewer].has(owner):
					passed = passed and float(tracks[viewer][owner].sample_at_render_time().get("world_x", 0.0)) > 1000.0
				else:
					passed = false
		var connection_states: Array = []
		for connection in connections:
			connection_states.append(connection.get_connection_state())
		var result := {"passed": passed, "counts": counts, "send_errors": errors, "active_seconds": active_elapsed, "connection_states": connection_states, "peers": [apis[1].get_peers(), apis[2].get_peers(), apis[3].get_peers()]}
		print("UNIFIED_RPC_TEST " + JSON.stringify(result))
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.unifiedRpcResult = " + JSON.stringify(result), true)
		for connection in connections:
			connection.close()
		for peer in peers.values():
			peer.close()
		get_tree().quit(0 if passed else 1)
	return

func _received(sender: int, sample: Dictionary, viewer: int) -> void:
	var owner := int(sample.get("owner_peer_id", -1))
	if viewer == 1:
		_require(sender == owner)
	else:
		_require(sender == 1 and owner != viewer)
	var previous_seq := int(sequences[viewer].get(owner, 0))
	_require(Validation.validate_sample(sample, "rpc-test", owner, previous_seq, previous_seq * 2).is_empty())
	sequences[viewer][owner] = int(sample.sample_seq)
	if owner != viewer:
		counts[viewer][owner] = int(counts[viewer].get(owner, 0)) + 1
		if not tracks[viewer].has(owner):
			tracks[viewer][owner] = Track.new()
		_require(tracks[viewer][owner].add_sample(sample))
	if viewer == 1:
		for target in [2, 3]:
			if target != owner:
				errors += int(endpoints[1].send_sample_to_peer(target, sample) != OK)

func _require(condition: bool) -> void:
	if not condition:
		errors += 1
		push_error("WebRTC fixture contract failed")
