extends SceneTree

const ServiceScript := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")

class ControlledCoinProvider extends Node:
	signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
	signal request_timing(action: String, context: String, queue_usec: int, http_usec: int)
	var probe: Variant
	var role := ""
	var room_id := ""
	var generation := 0
	var delay := 0.0
	func call_rpc(action: String, _rpc: String, payload: Dictionary, token: String, context: String = "") -> void:
		probe.events.append({"role": role, "action": action, "stage": "requested", "runtime_round_id": str(payload.get("p_runtime_round_id", ""))})
		if token.is_empty():
			request_finished.emit(action, false, null, "test missing token", context)
			return
		_complete_after(action, context, payload)
	func _complete_after(action: String, context: String, payload: Dictionary) -> void:
		await get_tree().create_timer(delay if action == "coin_link_resolve" else 0.05).timeout
		var data: Dictionary = {}
		if role == "host" and action == "coin_round_register" and not probe.host_registration_response_lost:
			probe.host_registration_response_lost = true
			probe.events.append({"role": role, "action": action, "stage": "server_committed_response_lost", "runtime_round_id": str(payload.get("p_runtime_round_id", ""))})
			request_finished.emit(action, false, {"http_status": 0, "http_result": HTTPRequest.RESULT_TIMEOUT}, "simulated response loss after idempotent backend commit", context)
			return
		match action:
			"coin_link_request":
				data = {"bound": false, "challenge_id": "00000000-0000-0000-0000-000000000123", "nonce": "a".repeat(64), "expires_in_seconds": 300}
			"coin_link_resolve":
				data = {"bound": true, "room_id": room_id, "lobby_generation": generation}
			"coin_round_register":
				data = {"coin_round_id": "00000000-0000-0000-0000-000000000999", "duplicate": false}
		probe.events.append({"role": role, "action": action, "stage": "completed"})
		request_finished.emit(action, true, data, "", context)

class ControlledLobbyProvider extends Node:
	signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
	signal request_timing(action: String, context: String, queue_usec: int, request_usec: int)
	var owner_service: Node
	func start_prepare(_room_id: String, _token: String, context: String) -> void:
		var room: Dictionary = owner_service.room_state.duplicate(true)
		room["phase"] = "PREPARING_COURSE"
		room["lobby_generation"] = int(room.lobby_generation) + 1
		room["state_revision"] = int(room.state_revision) + 1
		_complete.call_deferred("prepare_round", {"room": room}, context)
	func refresh_room(_room_id: String, _loadout_hash: String, _token: String, context: String) -> void:
		_complete.call_deferred("refresh_room", {"room": owner_service.room_state.duplicate(true)}, context)
	func set_phase(_room_id: String, phase: String, _token: String, context: String) -> void:
		var room: Dictionary = owner_service.room_state.duplicate(true)
		room["phase"] = phase
		room["state_revision"] = int(room.get("state_revision", 0)) + 1
		_complete.call_deferred("set_phase", {"room": room}, context)
	func _complete(action: String, data: Dictionary, context: String) -> void:
		await get_tree().create_timer(0.03).timeout
		request_finished.emit(action, true, data, "", context)

var failures := 0
var elapsed := 0.0
var events: Array[Dictionary] = []
var services: Dictionary = {}
var peers: Array[WebRTCPeerConnection] = []
var connections_started := false
var round_started_ids: Dictionary = {}
var slow_guest_resolved := false
var host_registration_response_lost := false
var start_errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var auth := root.get_node("AuthService")
	auth.is_authenticated = false
	var built: Dictionary = Builder.new().build(43, 45000, 6)
	_check(str(built.get("error", "")).is_empty(), "v6 manifest builds for a full prepare test")
	var manifest: Resource = built.manifest
	var room_id := "00000000-0000-0000-0000-000000000043"
	var base_room := {"room_id": room_id, "room_session_id": "prepare-test-session", "owner_user_id": "test-network-1", "phase": "OPEN", "lobby_generation": 1, "state_revision": 1, "lobby_cycle": 1, "content_revision": 0, "game_version": ServiceScript.V2_GAME_VERSION, "generator_version": 6, "seed": 43, "course_length_px": 45000, "manifest_hash": str(manifest.get("manifest_hash")), "signaling_topic": "local-prepare-test", "members": []}
	var roster: Array = []
	for peer_id in [1, 2, 3]:
		roster.append({"user_id": "test-network-%d" % peer_id, "display_name": "Runner %d" % peer_id, "player_slot": peer_id, "is_ready": true, "ready_cycle": 1, "ready_content_revision": 0, "returned_for_cycle": 1, "is_connected": true, "loaded_manifest_hash": str(manifest.get("manifest_hash")), "loadout_hash": "", "ready_loadout_hash": ""})
	for peer_id in [1, 2, 3]:
		var service: Node = ServiceScript.new()
		service.name = "PrepareClient%d" % peer_id
		root.add_child(service)
		await process_frame
		service.room_state = base_room.duplicate(true)
		service.room_state["members"] = roster.duplicate(true)
		service.identity_user_id = "test-network-%d" % peer_id
		service.identity_is_anonymous = true
		service.current_manifest = manifest
		var local_hash := str(service.local_loadout_hash())
		for member in service.room_state.members:
			member.loadout_hash = local_hash
			member.ready_loadout_hash = local_hash
		var identity: Node = service._identity_adapter
		identity.user_id = service.identity_user_id
		identity.access_token = "network-token-%d" % peer_id
		identity.expires_at = int(Time.get_unix_time_from_system()) + 3600
		var old_lobby: Node = service._lobby_provider
		old_lobby.queue_free()
		var fake_lobby := ControlledLobbyProvider.new()
		fake_lobby.owner_service = service
		fake_lobby.name = "ControlledLobbyProvider"
		service.add_child(fake_lobby)
		fake_lobby.request_finished.connect(service._on_lobby_request_finished)
		fake_lobby.request_timing.connect(service._on_lobby_request_timing)
		service._lobby_provider = fake_lobby
		var old_coin: Node = service._coin_award_provider
		old_coin.queue_free()
		var fake_coin := ControlledCoinProvider.new()
		fake_coin.name = "ControlledCoinProvider"
		fake_coin.probe = self
		fake_coin.role = "host" if peer_id == 1 else "guest%d" % peer_id
		fake_coin.room_id = room_id
		fake_coin.generation = 2
		fake_coin.delay = 1.2 if peer_id == 2 else 0.15
		service.add_child(fake_coin)
		fake_coin.request_finished.connect(service._on_coin_award_request_finished)
		fake_coin.request_timing.connect(service._on_coin_award_request_timing)
		service._coin_award_provider = fake_coin
		service.round_prepare_requested.connect(_on_prepare_requested.bind(peer_id))
		service.round_started.connect(_on_started.bind(peer_id))
		services[peer_id] = service
	var host: Node = services[1]
	var host_room: Dictionary = host.room_state
	_check(host.open_host(host_room, 4) == OK, "host WebRTC session starts using the actual multiplayer service")
	for peer_id in [2, 3]:
		var guest: Node = services[peer_id]
		_check(guest.configure_client_peer(peer_id) == OK, "guest WebRTC peer is configured")
		guest.activate_client_session(guest.room_state)
		var host_connection := WebRTCPeerConnection.new()
		var guest_connection := WebRTCPeerConnection.new()
		peers.append(host_connection)
		peers.append(guest_connection)
		host_connection.session_description_created.connect(_description.bind(host_connection, guest_connection))
		guest_connection.session_description_created.connect(_description.bind(guest_connection, host_connection))
		host_connection.ice_candidate_created.connect(_ice.bind(guest_connection))
		guest_connection.ice_candidate_created.connect(_ice.bind(host_connection))
		_check(host_connection.initialize({"iceServers": []}) == OK and guest_connection.initialize({"iceServers": []}) == OK, "local WebRTC negotiation initializes")
		_check(host.attach_guest_peer(peer_id, host_connection) == OK and guest.webrtc_peer.add_peer(guest_connection, 1) == OK, "local WebRTC peers are attached")
		_check(host_connection.create_offer() == OK, "host starts real data-channel negotiation")
	var auth_again := root.get_node("AuthService")
	auth_again.is_authenticated = true
	auth_again.user_id = "prepare-test-account"
	auth_again.set("_access_token", "signed-account-token")
	auth_again.set("_expires_at", 0)
	connections_started = true
	call_deferred("_start_when_connected")

func _start_when_connected() -> void:
	var host: Node = services.get(1)
	var start_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < start_deadline:
		await process_frame
		if host.connected_peer_ids().has(2) and host.connected_peer_ids().has(3) and host._session_confirmed_peers.has(2) and host._session_confirmed_peers.has(3):
			break
	_check(host.connected_peer_ids().has(2) and host.connected_peer_ids().has(3), "two remote peers connect over actual WebRTC before starting")
	_check(host._session_confirmed_peers.has(2) and host._session_confirmed_peers.has(3), "normal session confirmation completes before start")
	if failures > 0:
		quit(1)
		return
	host.request_start()

func _process(delta: float) -> bool:
	if not connections_started:
		return false
	elapsed += delta
	var host: Node = services.get(1)
	var register_index := -1
	var slow_resolve_index := -1
	for index in range(events.size()):
		if events[index].role == "guest2" and events[index].action == "coin_link_resolve" and events[index].stage == "completed":
			slow_resolve_index = index
		if events[index].action == "coin_round_register" and events[index].stage == "requested":
			register_index = index
	if slow_resolve_index >= 0:
		slow_guest_resolved = true
	if register_index >= 0:
		_check(slow_resolve_index >= 0 and slow_resolve_index < register_index, "host registers the frozen catalog only after the delayed guest account resolve finishes")
	var register_requests: Array[Dictionary] = []
	for event in events:
		if event.role == "host" and event.action == "coin_round_register" and event.stage == "requested":
			register_requests.append(event)
	if register_requests.size() >= 2:
		_check(str(register_requests[0].get("runtime_round_id", "")) == str(register_requests[1].get("runtime_round_id", "")), "an ambiguous registration retry reuses the same idempotent runtime round key")
	if round_started_ids.size() == 3:
		_check(host._round_coordinator.state == ServiceScript.RoundCoordinatorScript.State.RUNNING, "host completes prepare, registration, COMMIT_START, ACK, and countdown")
		_check(events.any(func(event: Dictionary) -> bool: return event.role == "guest2" and event.action == "coin_link_resolve" and event.stage == "completed"), "slow guest account binding completed")
		_check(host_registration_response_lost and register_requests.size() == 2, "an idempotent retry succeeds after the first backend commit response is lost")
		host.start_failure_changed.connect(_on_start_failure)
		host.room_state["phase"] = "OPEN"
		host._on_coin_award_request_finished("coin_round_register", true, {"duplicate": true}, "", str(host._round_id))
		_check(host._round_coordinator.state == ServiceScript.RoundCoordinatorScript.State.CANCELLED and start_errors.any(func(error: String) -> bool: return error.contains("required coin_round_id")), "HTTP success without coin_round_id is rejected as a concrete contract failure (state=%s, errors=%s)" % [str(host._round_coordinator.state), str(start_errors)])
		print("Prepare start integration passed: 3 real WebRTC service clients, signed account links, delayed guest bind, frozen catalog registration, synchronized countdown.")
		for service in services.values():
			service._active = false
			service.webrtc_peer.close()
		quit(0 if failures == 0 else 1)
		return true
	if elapsed > 35.0:
		_check(false, "actual service/coordinator prepare flow reaches RUNNING within 35 seconds")
		print("prepare timeout phase=%s coordinator=%s guest2=%s events=%s" % [host.room_state.get("phase"), host._round_coordinator.state, services[2]._round_coordinator.state, str(events)])
		quit(1)
		return true
	return false

func _on_prepare_requested(descriptor: Dictionary, peer_id: int) -> void:
	var service: Node = services.get(peer_id)
	var world := World.new()
	world.configure(service.current_manifest)
	service.configure_world_simulation(world)
	service.mark_local_prepared()

func _on_started(_round_id: String, _descriptor: Dictionary, peer_id: int) -> void:
	round_started_ids[peer_id] = true

func _on_start_failure(message: String) -> void:
	start_errors.append(message)

func _description(kind: String, sdp: String, local: WebRTCPeerConnection, remote: WebRTCPeerConnection) -> void:
	_check(local.set_local_description(kind, sdp) == OK and remote.set_remote_description(kind, sdp) == OK, "WebRTC SDP exchange")

func _ice(media: String, index: int, candidate: String, remote: WebRTCPeerConnection) -> void:
	remote.add_ice_candidate(media, index, candidate)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
