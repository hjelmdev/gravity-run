extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldScript := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const ServiceScript := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const MatchScript := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")
const LocalRunner := preload("res://systems/multiplayer_v2/v2_local_runner.gd")

var _early_packets: Array[Dictionary] = []
var _final_commits: Array[Dictionary] = []
var _cancellation_packets: Array[Dictionary] = []
var _reward_signals := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var built: Dictionary = Builder.new().build(42, 10000, 8)
	if built.get("manifest") == null:
		_finish(["could not build the canonical coin manifest"])
		return
	var manifest: Resource = built.manifest
	var fixture := _isolated_contact(manifest, {})
	var coin: Dictionary = fixture.get("coin", {})
	if coin.is_empty():
		_finish(["could not create a real swept coin-contact fixture"])
		return
	var entity_id := str(coin.entity_id)
	var round_id := "coin-contact-broadcast-test"
	var start: Dictionary = fixture.start
	var finish: Dictionary = fixture.finish
	var host_world = WorldScript.new()
	var guest_world = WorldScript.new()
	if not str(host_world.configure(manifest)).is_empty() or not str(guest_world.configure(manifest)).is_empty():
		_finish(["failed to configure canonical host/guest worlds"])
		return
	var host_course = PresentationScript.new()
	var guest_course = PresentationScript.new()
	host_course.load_manifest(manifest)
	guest_course.load_manifest(manifest)
	add_child(host_course)
	add_child(guest_course)
	var host_coin: Node2D = host_course.event_nodes[entity_id]
	var guest_coin: Node2D = guest_course.event_nodes[entity_id]
	host_coin.collected.connect(_on_reward_signal)
	guest_coin.collected.connect(_on_reward_signal)
	var host_match = MatchScript.new()
	host_match.set("_round_id", round_id)
	host_match.set("_world", host_world)
	host_match.set("_course_presentation", host_course)
	host_match.set("_pending_coin_claims", {})
	var runner := LocalRunner.new()
	runner.configure(round_id, 1, float(manifest.start_x), float(manifest.initial_floor_y))
	runner.simulation_tick = 11
	host_match.set("_runner", runner)
	var guest_match = MatchScript.new()
	guest_match.set("_round_id", round_id)
	guest_match.set("_world", guest_world)
	guest_match.set("_course_presentation", guest_course)
	guest_match.set("_pending_coin_claims", {})
	var host_service = MultiplayerV2Service
	var host_was_processing := host_service.is_processing()
	host_service.set_process(false)
	host_service.call("configure_world_simulation", host_world)
	host_service.set("_active", true)
	host_service.set("_round_id", round_id)
	host_service.set("session", {"round_id": round_id, "local_peer_id": 1, "role": "host"})
	host_service.set("identity_user_id", "coin-contact-host")
	var room := {"room_id": "coin-contact-room", "room_session_id": "coin-contact-session", "lobby_generation": 3, "phase": "RUNNING", "owner_user_id": "coin-contact-host", "members": [{"user_id": "coin-contact-host", "player_slot": 1}, {"user_id": "coin-contact-guest", "player_slot": 2}, {"user_id": "coin-contact-invalid", "player_slot": 3}]}
	host_service.set("room_state", room.duplicate(true))
	host_service.set("current_manifest", manifest)
	host_service.set("_coin_contact_presentations", {})
	host_service.set("_interaction_results", {})
	host_service.set("_pending_interactions", [])
	host_service.set("_last_input_sequence_by_peer", {1: 0, 2: 0, 3: 0})
	host_service.set("terminal_status", {})
	host_world.tick = 11
	var history := [
		{"round_id": round_id, "owner_peer_id": 2, "simulation_tick": 10, "history_tick": 10.0, "world_x": float(start.world_x), "y": float(start.y)},
		{"round_id": round_id, "owner_peer_id": 2, "simulation_tick": 11, "history_tick": 11.0, "world_x": float(finish.world_x), "y": float(finish.y)}
	]
	host_service.set("_validated_motion_history", {2: history, 1: history.map(func(row: Dictionary) -> Dictionary: var copy := row.duplicate(true); copy["owner_peer_id"] = 1; return copy)})
	host_service.coin_contact_presented.connect(host_match._on_verified_coin_contact)
	host_service.coin_contact_presented.connect(_capture_early_packet)
	host_service.coin_contact_presentation_cancelled.connect(host_match._on_coin_contact_cancelled)
	host_service.coin_contact_presentation_cancelled.connect(_capture_cancellation_packet)
	host_service.world_event_committed.connect(_capture_final_commit)
	var guest_service = ServiceScript.new()
	add_child(guest_service)
	guest_service.set_process(false)
	guest_service.set("_active", true)
	guest_service.set("_round_id", round_id)
	guest_service.set("session", {"round_id": round_id, "local_peer_id": 2, "role": "guest"})
	guest_service.set("room_state", room.duplicate(true))
	guest_service.set("world_simulation", guest_world)
	guest_service.coin_contact_presented.connect(guest_match._on_verified_coin_contact)
	guest_service.coin_contact_presentation_cancelled.connect(guest_match._on_coin_contact_cancelled)
	var remote_request_id := "guest-verified-request"
	guest_course.call("predict_coin_collection", entity_id, int(coin.get("incarnation", 1)), round_id, remote_request_id)
	guest_match.set("_pending_coin_claims", {entity_id: {"request_id": remote_request_id, "round_id": round_id, "incarnation": int(coin.get("incarnation", 1)), "contact_usec": Time.get_ticks_usec(), "predicted": true}})
	var guest_request := {"round_id": round_id, "owner_peer_id": 2, "request_id": remote_request_id, "entity_id": entity_id, "incarnation": int(coin.get("incarnation", 1)), "action": "collect", "simulation_tick": 11, "input_seq": 0, "known_world_revision": 0}
	host_service.call("_process_world_interaction", 2, guest_request)
	if _early_packets.size() != 1:
		failures.append("first host-verified guest contact did not emit exactly one presentation event")
	if not bool(host_coin.get("is_being_collected")) or not bool(guest_coin.get("is_being_collected")):
		failures.append("host/guest did not show the same coin burst before claim arbitration")
	if not host_world.entity_ledger.is_active(entity_id, int(coin.get("incarnation", 1))) or not guest_world.entity_ledger.is_active(entity_id, int(coin.get("incarnation", 1))):
		failures.append("early contact presentation changed a canonical coin ledger before award commit")
	if _reward_signals != 0:
		failures.append("effects-only early contact emitted a reward signal")
	if _early_packets.size() == 1:
		var packet: Dictionary = _early_packets[0].duplicate(true)
		packet.merge({"network_mode": "v2", "protocol_version": 1, "room_id": str(room.room_id), "room_session_id": str(room.room_session_id), "lobby_generation": int(room.lobby_generation)}, true)
		guest_service.call("_on_control_rpc", 1, "COIN_CONTACT_PRESENTATION", packet)
		if not bool(guest_coin.get("is_being_collected")):
			failures.append("guest control receive path did not present the host-verified contact")
		var elapsed_before_duplicate := float(guest_coin.get("burst_elapsed"))
		guest_service.call("_on_control_rpc", 1, "COIN_CONTACT_PRESENTATION", packet)
		if not is_equal_approx(float(guest_coin.get("burst_elapsed")), elapsed_before_duplicate):
			failures.append("duplicate early control packet restarted the existing coin burst")
	# A second valid player competes while the presentation is already underway.
	host_match.call("_submit_coin_claims", start, finish, 2.0)
	if _early_packets.size() != 1:
		failures.append("competing valid contact caused a second burst broadcast")
	var queued_before_decision: Array = host_service.get("_pending_interactions")
	if queued_before_decision.size() != 2 or not host_world.entity_ledger.is_active(entity_id, int(coin.get("incarnation", 1))):
		failures.append("host finalized the coin before the 120 ms arbitration window")
	for pending_value in queued_before_decision:
		pending_value["received_usec"] = Time.get_ticks_usec() - 130_000
	host_service.call("_drain_interaction_claims")
	var host_coin_state: Dictionary = host_world.entity_ledger.entities.get(entity_id, {})
	var expected_winner := 1 if str(host_service.call("_coin_tie_rank", entity_id, 1)) < str(host_service.call("_coin_tie_rank", entity_id, 2)) else 2
	if str(host_coin_state.get("state", "")) != "collected" or int(host_coin_state.get("winner_peer_id", -1)) != expected_winner or int(host_coin_state.get("award_value", 0)) != 1:
		failures.append("final arbitration did not award exactly one deterministic winner: %s" % str(host_coin_state))
	if _reward_signals != 0:
		failures.append("coin presentation generated a single-player collected reward")
	if not _early_packets.is_empty() and not _final_commits.is_empty():
		var committed: Dictionary = _final_commits[0].duplicate(true)
		var packet := committed.duplicate(true)
		packet.merge({"network_mode": "v2", "protocol_version": 1, "room_id": str(room.room_id), "room_session_id": str(room.room_session_id), "lobby_generation": int(room.lobby_generation)}, true)
		guest_service.call("_on_control_rpc", 1, "WORLD_COMMIT", packet)
		var burst_before_duplicate := float(guest_coin.get("burst_elapsed"))
		guest_match.call("_on_world_commit", committed)
		if str(guest_world.entity_ledger.entities[entity_id].get("state", "")) != "collected":
			failures.append("guest canonical ledger did not apply the final authoritative commit")
		if not bool(guest_coin.get("is_being_collected")) or not is_equal_approx(float(guest_coin.get("burst_elapsed")), burst_before_duplicate):
			failures.append("final commit duplicated or interrupted the already-running contact effect")
		guest_course.call("set_world_state", {"entities": guest_world.entity_ledger.entities})
		if not bool(guest_coin.get("is_being_collected")):
			failures.append("collected baseline resync replaced/replayed the in-progress shared coin effect")
	# Invalid motion may still be queued for the normal arbiter response, but cannot trigger any broadcast.
	var invalid_fixture := _isolated_contact(manifest, {entity_id: true})
	var invalid_coin: Dictionary = invalid_fixture.get("coin", {})
	if not invalid_coin.is_empty():
		var invalid_request := {"round_id": round_id, "owner_peer_id": 3, "request_id": "unverified-request", "entity_id": str(invalid_coin.entity_id), "incarnation": int(invalid_coin.get("incarnation", 1)), "action": "collect", "simulation_tick": 11, "input_seq": 0, "known_world_revision": 0}
		host_service.call("_process_world_interaction", 3, invalid_request)
		if _early_packets.size() != 1:
			failures.append("unverified motion produced a coin contact broadcast")
	# A request that passed host motion verification but becomes invalid at the terminal boundary
	# must cancel its effects on both clients and leave the still-active canonical coin usable.
	var void_fixture := _isolated_contact(manifest, {entity_id: true, str(invalid_coin.get("entity_id", "")): true})
	var void_coin: Dictionary = void_fixture.get("coin", {})
	if not void_coin.is_empty():
		var void_id := str(void_coin.entity_id)
		var void_start: Dictionary = void_fixture.start
		var void_finish: Dictionary = void_fixture.finish
		var void_request_id := "verified-then-void-request"
		guest_match.set("_pending_coin_claims", {void_id: {"request_id": void_request_id, "round_id": round_id, "incarnation": int(void_coin.get("incarnation", 1)), "contact_usec": Time.get_ticks_usec(), "predicted": true}})
		guest_course.call("predict_coin_collection", void_id, int(void_coin.get("incarnation", 1)), round_id, void_request_id)
		host_service.set("_validated_motion_history", {2: [
			{"round_id": round_id, "owner_peer_id": 2, "simulation_tick": 10, "history_tick": 10.0, "world_x": float(void_start.world_x), "y": float(void_start.y)},
			{"round_id": round_id, "owner_peer_id": 2, "simulation_tick": 11, "history_tick": 11.0, "world_x": float(void_finish.world_x), "y": float(void_finish.y)}
		]})
		var void_request := {"round_id": round_id, "owner_peer_id": 2, "request_id": void_request_id, "entity_id": void_id, "incarnation": int(void_coin.get("incarnation", 1)), "action": "collect", "simulation_tick": 11, "input_seq": 0, "known_world_revision": host_world.entity_ledger.revision}
		host_service.call("_process_world_interaction", 2, void_request)
		if _early_packets.size() != 2 or not bool(host_course.event_nodes[void_id].get("is_being_collected")):
			failures.append("second verified contact did not start an early voidable effect")
		var void_packet: Dictionary = _early_packets[1].duplicate(true)
		void_packet.merge({"network_mode": "v2", "protocol_version": 1, "room_id": str(room.room_id), "room_session_id": str(room.room_session_id), "lobby_generation": int(room.lobby_generation)}, true)
		guest_service.call("_on_control_rpc", 1, "COIN_CONTACT_PRESENTATION", void_packet)
		host_service.set("terminal_status", {2: {"terminal_contact_tick": float(void_packet.get("contact_tick", -1.0))}})
		var pending_void: Array = host_service.get("_pending_interactions")
		for pending_value in pending_void:
			pending_value["received_usec"] = Time.get_ticks_usec() - 130_000
		host_service.call("_drain_interaction_claims")
		if _cancellation_packets.size() != 1:
			failures.append("voided host contact did not emit one scoped presentation cancellation")
		if not bool(host_world.entity_ledger.is_active(void_id, int(void_coin.get("incarnation", 1)))) or not bool(host_course.event_nodes[void_id].visible) or bool(host_course.event_nodes[void_id].get("is_being_collected")):
			failures.append("host did not restore a still-active coin after contact cancellation")
		if _cancellation_packets.size() == 1:
			var cancellation: Dictionary = _cancellation_packets[0].duplicate(true)
			cancellation.merge({"network_mode": "v2", "protocol_version": 1, "room_id": str(room.room_id), "room_session_id": str(room.room_session_id), "lobby_generation": int(room.lobby_generation)}, true)
			guest_service.call("_on_control_rpc", 1, "COIN_CONTACT_PRESENTATION_CANCEL", cancellation)
			if not bool(guest_world.entity_ledger.is_active(void_id, int(void_coin.get("incarnation", 1)))) or not bool(guest_course.event_nodes[void_id].visible) or bool(guest_course.event_nodes[void_id].get("is_being_collected")):
				failures.append("guest did not restore a still-active coin after host void cancellation")
		if _reward_signals != 0:
			failures.append("voided coin effect emitted an award signal")
		host_service.set("terminal_status", {})
	guest_service.set("_round_id", "next-round")
	guest_service.set("session", {"round_id": "next-round", "local_peer_id": 2, "role": "guest"})
	var stale: Dictionary = _early_packets[0].duplicate(true) if not _early_packets.is_empty() else {}
	stale.merge({"network_mode": "v2", "protocol_version": 1, "room_id": str(room.room_id), "room_session_id": str(room.room_session_id), "lobby_generation": int(room.lobby_generation)}, true)
	guest_service.call("_on_control_rpc", 1, "COIN_CONTACT_PRESENTATION", stale)
	if _reward_signals != 0:
		failures.append("stale/duplicate presentation emitted a real reward signal")
	host_service.coin_contact_presented.disconnect(host_match._on_verified_coin_contact)
	host_service.coin_contact_presented.disconnect(_capture_early_packet)
	host_service.coin_contact_presentation_cancelled.disconnect(host_match._on_coin_contact_cancelled)
	host_service.coin_contact_presentation_cancelled.disconnect(_capture_cancellation_packet)
	host_service.world_event_committed.disconnect(_capture_final_commit)
	guest_service.coin_contact_presented.disconnect(guest_match._on_verified_coin_contact)
	guest_service.coin_contact_presentation_cancelled.disconnect(guest_match._on_coin_contact_cancelled)
	host_service.call("configure_world_simulation", null)
	host_service.set("session", {})
	host_service.set("room_state", {})
	host_service.set("current_manifest", null)
	host_service.set("_active", false)
	host_service.set("_round_id", "")
	host_service.set("_pending_interactions", [])
	host_service.set("_interaction_results", {})
	host_service.set("_coin_contact_presentations", {})
	host_service.set_process(host_was_processing)
	host_match.free()
	guest_match.free()
	host_course.queue_free()
	guest_course.queue_free()
	guest_service.queue_free()
	await get_tree().process_frame
	_finish(failures)

func _capture_early_packet(presentation: Dictionary) -> void:
	_early_packets.append(presentation.duplicate(true))

func _capture_final_commit(commit: Dictionary) -> void:
	if str(commit.get("action", "")) == "collect":
		_final_commits.append(commit.duplicate(true))

func _capture_cancellation_packet(presentation: Dictionary) -> void:
	_cancellation_packets.append(presentation.duplicate(true))

func _on_reward_signal(_value: int) -> void:
	_reward_signals += 1

func _isolated_contact(manifest: Resource, excluded: Dictionary) -> Dictionary:
	for candidate in manifest.collectibles:
		var entity_id := str(candidate.get("entity_id", ""))
		if excluded.has(entity_id):
			continue
		var start := {"world_x": float(candidate.get("world_x", 0.0)) - 4.0, "y": float(candidate.get("world_y", 0.0))}
		var finish := {"world_x": float(candidate.get("world_x", 0.0)) + 4.0, "y": float(candidate.get("world_y", 0.0))}
		var probe = WorldScript.new()
		probe.configure(manifest)
		if probe.coin_contacts_swept(start, finish).size() == 1 and str(probe.coin_contacts_swept(start, finish)[0].get("entity_id", "")) == entity_id:
			return {"coin": candidate, "start": start, "finish": finish}
	return {}

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("coin_contact_broadcast_integration_test: PASS (host-verified early effects on canonical host/guest worlds, deterministic delayed award, dedup, void cancellation/restore, stale and invalid claims)")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
