extends SceneTree

const Protocol := preload("res://systems/multiplayer_v2/v2_protocol.gd")
const Clock := preload("res://systems/multiplayer_v2/v2_round_clock.gd")
const Track := preload("res://systems/multiplayer_v2/v2_remote_track.gd")
const Ledger := preload("res://systems/multiplayer_v2/v2_world_event_ledger.gd")
const Rules := preload("res://systems/multiplayer_v2/v2_destructible_rules.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Runner := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const Coordinator := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const V2Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const V2Transport := preload("res://systems/multiplayer_v2/v2_webrtc_transport.gd")

func _initialize() -> void:
	var numeric_roster := [
		{"user_id": "host-user", "player_slot": 1.0},
		{"user_id": "guest-user", "player_slot": 2.0}
	]
	var numeric_peer_map: Dictionary = V2Service._peer_map_for_roster(numeric_roster)
	_assert(numeric_peer_map == {"1": "host-user", "2": "guest-user"}, "peer map normalizes Supabase float slots to integer IDs")
	_assert(V2Service.room_snapshot_rejection_reason({"room_id": "room", "room_session_id": "session", "lobby_generation": 5, "phase": "PREPARING_COURSE"}, {"room_id": "room", "room_session_id": "session", "lobby_generation": 4, "phase": "OPEN"}, "refresh_room") == "older_generation", "stale room polling cannot roll back a newer generation")
	_assert(V2Service.room_snapshot_rejection_reason({"room_id": "room", "room_session_id": "session", "lobby_generation": 5, "phase": "PREPARING_COURSE"}, {"room_id": "room", "room_session_id": "session", "lobby_generation": 5, "phase": "OPEN"}, "refresh_room") == "phase_regression", "room polling cannot regress phase within one generation")
	_assert(V2Service.room_snapshot_rejection_reason({"room_id": "room", "room_session_id": "session", "lobby_generation": 5, "phase": "PREPARING_COURSE"}, {"room_id": "room", "room_session_id": "session", "lobby_generation": 6, "phase": "OPEN"}, "refresh_room").is_empty(), "a newer return-to-lobby generation can reopen the room")
	_assert(V2Service.room_snapshot_rejection_reason({"room_id": "room", "room_session_id": "session", "lobby_generation": 6, "state_revision": 20, "phase": "OPEN"}, {"room_id": "room", "room_session_id": "session", "lobby_generation": 6, "state_revision": 19, "phase": "OPEN"}, "refresh_room") == "older_state_revision", "same-generation responses cannot roll back a newer ready or return state")
	var lobby_snapshot := {"room_id": "room", "room_session_id": "session", "lobby_generation": 6, "phase": "OPEN"}
	_assert(V2Service.should_apply_return_to_lobby(lobby_snapshot, lobby_snapshot), "duplicate return-to-lobby packet is idempotently accepted at the same generation")
	_assert(not V2Service.should_apply_return_to_lobby(lobby_snapshot, {"room_id": "room", "room_session_id": "session", "lobby_generation": 5, "phase": "OPEN"}), "old return-to-lobby packet cannot regress a newer lobby")
	_assert(not V2Service.should_apply_return_to_lobby(lobby_snapshot, {"room_id": "room", "room_session_id": "other-session", "lobby_generation": 7, "phase": "OPEN"}), "return-to-lobby packet from another room session is rejected")
	var diagnostics = preload("res://systems/multiplayer_v2/v2_diagnostics.gd").new()
	var liveness_service = V2Service.new()
	liveness_service._last_heartbeat_usec[2] = 5_000_000
	liveness_service._disconnect_since_usec[2] = 4_900_000
	liveness_service.begin_round("liveness-round", 7)
	_assert(int(liveness_service._last_heartbeat_usec.get(2, -1)) == 5_000_000, "round transition preserves the peer session contact timestamp")
	_assert(int(liveness_service._disconnect_since_usec.get(2, -1)) == 4_900_000, "round transition preserves an in-progress transport outage")
	_assert(not V2Service.liveness_restart_due(5_050_000, 5_000_000, -1), "freshly acknowledged connected peer is not restarted after round start")
	_assert(not V2Service.liveness_restart_due(5_050_000, -1, -1), "missing heartbeat history cannot trigger an immediate reconnect")
	_assert(not V2Service.liveness_restart_due(7_900_000, 5_000_000, -1), "peer gets the full liveness deadline before reconnect")
	_assert(V2Service.liveness_restart_due(8_000_000, 5_000_000, -1), "genuinely silent peer can be restarted after liveness deadline")
	_assert(not V2Service.liveness_restart_due(8_500_000, 5_000_000, 8_000_000), "reconnect retry respects its full retry interval")
	_assert(V2Service.liveness_restart_due(10_000_000, 5_000_000, 8_000_000), "disconnected peer may retry after the explicit retry interval")
	_assert(V2Service.reconnect_world_revision_matches(7, 7), "reconnect session sync accepts an identical shared-world revision")
	_assert(not V2Service.reconnect_world_revision_matches(7, 6), "reconnect session sync rejects a stale shared-world revision")
	_assert(not V2Service.reconnect_world_revision_matches(-1, -1), "reconnect session sync rejects an unknown shared-world revision")
	liveness_service.free()
	var reconnect_transport = V2Transport.new()
	var reconnect_peer := WebRTCMultiplayerPeer.new()
	_assert(reconnect_peer.create_client(2) == OK and reconnect_peer.get_unique_id() == 2, "recreated WebRTC client preserves its assigned logical peer ID")
	reconnect_transport.owner_user_id = "host-user"
	reconnect_transport._connection_generations["host-user"] = 4
	reconnect_transport.rebind_client_peer(reconnect_peer)
	_assert(reconnect_transport.peer.get_unique_id() == 2, "transport rebind uses the recreated client peer")
	_assert(int(reconnect_transport._connection_generations.get("host-user", 0)) == 4, "client peer recreation preserves signaling generation monotonicity")
	reconnect_peer.close()
	reconnect_transport.free()
	var roster_transport = V2Transport.new()
	var roster_peer := WebRTCMultiplayerPeer.new()
	_assert(roster_peer.create_server([]) == OK, "roster replay fixture creates a WebRTC server peer")
	var requested_refresh := [false]
	var signal_events: Array[String] = []
	roster_transport.roster_refresh_requested.connect(func(_reason: String) -> void: requested_refresh[0] = true)
	roster_transport.signal_diagnostic.connect(func(event_name: String, _details: Dictionary) -> void: signal_events.append(event_name))
	roster_transport.configure({"room_id": "test-room", "owner_user_id": "host", "roster_revision": 2, "members": [{"user_id": "host", "player_slot": 1}]}, "host", roster_peer)
	var now_unix := int(Time.get_unix_time_from_system())
	var synthetic_sdp := "v=0\r\no=- 4611731400430051336 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\nc=IN IP4 0.0.0.0\r\na=ice-ufrag:synthetic\r\na=ice-pwd:syntheticpassword0123456789\r\na=ice-options:trickle\r\na=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\r\na=setup:actpass\r\na=mid:0\r\na=sctp-port:5000\r\n"
	var unknown_offer := {"network_mode": "v2", "room_id": "test-room", "connection_generation": 1, "attempt_id": "synthetic-attempt", "from_user_id": "guest", "to_user_id": "host", "type": "offer", "body": {"sdp_type": "offer", "sdp": synthetic_sdp}, "sent_at": now_unix, "expires_at": now_unix + 30}
	roster_transport.handle_signal(unknown_offer)
	_assert(requested_refresh[0] and roster_transport._unknown_member_signals.size() == 1, "unknown but room-scoped signaling is briefly queued while refreshing membership")
	roster_transport.update_room({"room_id": "test-room", "owner_user_id": "host", "roster_revision": 3, "members": [{"user_id": "host", "player_slot": 1}, {"user_id": "guest", "player_slot": 2}]})
	_assert(roster_transport._unknown_member_signals.is_empty() and "signal_replayed" in signal_events, "queued signaling is replayed only after the sender appears in the backend roster")
	roster_peer.close()
	roster_transport.free()
	var event_unix_before := int(Time.get_unix_time_from_system() * 1_000_000.0)
	diagnostics.record_event("utc-test")
	var event_unix := int(diagnostics.events.back().at_unix_usec)
	var event_unix_after := int(Time.get_unix_time_from_system() * 1_000_000.0)
	_assert(event_unix >= event_unix_before and event_unix <= event_unix_after, "diagnostic UTC uses wall-clock microseconds without monotonic-clock offset")

	var oversized_report := {"session": {"round_id": "export-test"}, "frames": [], "events": []}
	var large_frame_data := "x".repeat(256 * 1024)
	for _index in 40:
		oversized_report.frames.append({"sample": large_frame_data})
	var bounded_report: Dictionary = DiagnosticsExport.prepare_report(oversized_report)
	_assert(bool(bounded_report.get("export_truncated", false)), "oversized diagnostics explicitly record export truncation")
	_assert(JSON.stringify(bounded_report).to_utf8_buffer().size() <= DiagnosticsExport.MAX_EXPORT_BYTES, "diagnostics export stays within the browser download size limit")
	_assert(bounded_report.frames.size() < oversized_report.frames.size(), "diagnostics export trims the oldest frame samples first")

	var expected := {"room_id": "room", "room_session_id": "session", "lobby_generation": 4, "round_id": "round"}
	var envelope: Dictionary = Protocol.envelope("room", "session", 4, "round", "SAMPLE", 2, 1, {"world_x": 10.0})
	_assert(Protocol.validate_envelope(envelope, expected).is_empty(), "protocol accepts matching room/session/generation")
	envelope["lobby_generation"] = 3
	_assert(Protocol.validate_envelope(envelope, expected) == "lobby_generation_mismatch", "protocol rejects stale generation")

	var clock = Clock.new()
	for i in 3:
		clock.record_clock_exchange(1_000_000 + i * 100_000, 1_010_000 + i * 100_000, 1_010_100 + i * 100_000, 1_020_100 + i * 100_000)
	_assert(clock.is_synchronized(), "clock sync accepts three low-latency exchanges")
	_assert(clock.commit_start(2_000_000), "clock commits start once")
	_assert(not clock.commit_start(2_000_001), "clock rejects duplicate start")
	_assert(clock.advance(Clock.FIXED_DELTA * 3.0) == 3, "clock advances fixed simulation ticks")
	var host_coordinator = Coordinator.new()
	var started := [false]
	var prepare_scene_requested := [false]
	var sent_prepare: Dictionary = {}
	var prepare_targets: Array[int] = []
	host_coordinator.round_started.connect(func(_round_id: String, _descriptor: Dictionary) -> void: started[0] = true)
	host_coordinator.all_prepare_received.connect(func() -> void: prepare_scene_requested[0] = true)
	host_coordinator.control_requested.connect(func(peer_id: int, kind: String, payload: Dictionary) -> void:
		if kind == "PREPARE_ROUND":
			sent_prepare.merge(payload, true)
			prepare_targets.append(peer_id)
	)
	var round_descriptor := {"round_id": "barrier-round", "lobby_generation": 5, "manifest_hash": "hash", "seed": 4321, "players": [{"user_id": "host", "player_slot": 1}, {"user_id": "guest", "player_slot": 2}], "peer_map": {"1": "host", "2": "guest"}}
	var production_peers: Array[int] = V2Service._typed_peer_ids_from_packed(PackedInt32Array([2, 3]))
	_assert(production_peers.is_typed(), "production peer conversion preserves Array[int] at service boundary")
	_assert(host_coordinator.prepare_as_host(round_descriptor, production_peers, 3_000_000), "service-converted peer array starts host round prepare")
	_assert(prepare_targets == [2, 3], "service-converted peer array sends prepare to the exact connected peer IDs")
	_assert(sent_prepare.get("players", []).size() == 2 and sent_prepare.get("peer_map", {}).get("2", "") == "guest", "prepare RPC carries the host-frozen roster and peer map")
	_assert(not prepare_scene_requested[0], "host waits for every guest to receive the frozen descriptor before changing scenes")
	host_coordinator.acknowledge_prepare_received(2, "barrier-round")
	_assert(not prepare_scene_requested[0], "one prepare receipt cannot move the host scene")
	host_coordinator.acknowledge_prepare_received(3, "barrier-round")
	_assert(prepare_scene_requested[0], "host moves to the match only after every guest confirms prepare receipt")
	host_coordinator.mark_local_prepared(3_000_001)
	_assert(host_coordinator.state == Coordinator.State.PREPARING, "start barrier waits for remote prepared acknowledgements")
	host_coordinator.acknowledge_prepared(2, "barrier-round", 3_000_002)
	host_coordinator.acknowledge_prepared(3, "barrier-round", 3_000_003)
	_assert(host_coordinator.state == Coordinator.State.COMMITTING, "host commits start only after all prepared acknowledgements")
	host_coordinator.acknowledge_start(2, "barrier-round", 3_000_004)
	host_coordinator.acknowledge_start(3, "barrier-round", 3_000_005)
	host_coordinator.process(host_coordinator.host_start_usec + 1)
	_assert(started[0], "round starts after host time anchor and start acknowledgements")

	var solo_coordinator = Coordinator.new()
	var solo_prepare_sends := [0]
	solo_coordinator.control_requested.connect(func(_peer_id: int, kind: String, _payload: Dictionary) -> void:
		if kind == "PREPARE_ROUND": solo_prepare_sends[0] += 1
	)
	var solo_peers: Array[int] = V2Service._typed_peer_ids_from_packed(PackedInt32Array())
	_assert(solo_peers.is_typed() and solo_peers.is_empty(), "production peer conversion supports typed empty solo roster")
	_assert(solo_coordinator.prepare_as_host({"round_id": "solo-round"}, solo_peers, 4_000_000), "solo host can prepare through production peer conversion")
	_assert(solo_prepare_sends[0] == 0 and solo_coordinator.state == Coordinator.State.PREPARING, "solo prepare sends no guest RPC while its scene loads")
	solo_coordinator.mark_local_prepared(4_000_001)
	_assert(solo_coordinator.state == Coordinator.State.COMMITTING, "solo host advances to commit after the local scene is prepared")

	var guest_cancel_coordinator = Coordinator.new()
	var guest_cancel_packets: Array[String] = []
	guest_cancel_coordinator.control_requested.connect(func(_peer_id: int, kind: String, _payload: Dictionary) -> void: guest_cancel_packets.append(kind))
	_assert(guest_cancel_coordinator.receive_prepare_as_guest({"round_id": "abort-round", "attempt_id": "abort-attempt", "lobby_generation": 9}), "guest accepts descriptor before preparing-failure test")
	guest_cancel_coordinator.cancel("scene_missing", "match_scene_ready")
	_assert(guest_cancel_packets == ["PREPARE_FAILED"], "guest reports prepare failure using PREPARE_FAILED")
	guest_cancel_packets.clear()
	guest_cancel_coordinator.state = Coordinator.State.PREPARING
	guest_cancel_coordinator.cancel("host_cancelled", "host_cancelled", false)
	_assert(guest_cancel_packets.is_empty(), "guest does not echo host cancellation back to the host")

	var retry_coordinator = Coordinator.new()
	var prepare_sends := [0]
	var prepare_failures: Array[String] = []
	retry_coordinator.control_requested.connect(func(_peer_id: int, kind: String, _payload: Dictionary) -> void:
		if kind == "PREPARE_ROUND":
			prepare_sends[0] += 1
	)
	retry_coordinator.round_failed.connect(func(reason: String) -> void: prepare_failures.append(reason))
	_assert(retry_coordinator.prepare_as_host({"round_id": "retry-round", "lobby_generation": 8}, [2], 10_000_000), "host starts retryable prepare")
	retry_coordinator.mark_local_prepared(10_000_001)
	retry_coordinator.process(10_000_000 + Coordinator.PREPARE_RETRY_USEC)
	_assert(prepare_sends[0] == 2, "host retries prepare for an unprepared guest")
	retry_coordinator.process(10_000_000 + Coordinator.PREPARE_TIMEOUT_USEC)
	_assert(prepare_failures == ["prepare_timeout"], "host cancels and reports a stalled prepare")
	_assert(retry_coordinator.state == Coordinator.State.CANCELLED, "timed out prepare releases coordinator state")
	retry_coordinator.reset_for_lobby()
	_assert(retry_coordinator.state == Coordinator.State.IDLE and retry_coordinator.round_id.is_empty(), "returning to lobby clears stale round state")

	var guest_coordinator = Coordinator.new()
	_assert(guest_coordinator.receive_prepare_as_guest({"round_id": "old-round", "lobby_generation": 3}), "guest accepts first prepare")
	guest_coordinator.state = Coordinator.State.CANCELLED
	_assert(guest_coordinator.receive_prepare_as_guest({"round_id": "new-round", "lobby_generation": 4}), "guest accepts a newer lobby generation after an aborted round")
	_assert(guest_coordinator.round_id == "new-round", "guest coordinator replaces the stale round")

	var track = Track.new()
	_assert(track.add_sample(_sample(2, 2, 200.0)), "remote track accepts later sample")
	_assert(track.add_sample(_sample(1, 1, 100.0)), "remote track inserts reordered sample")
	_assert(not track.add_sample(_sample(1, 1, 100.0)), "remote track rejects duplicate sequence")
	_assert(track.samples.size() == 2, "remote history survives new samples")
	var shared_track = Track.new()
	shared_track.add_sample(_sample(1, 1, 100.0))
	shared_track.add_sample(_sample(2, 2, 200.0))
	shared_track.set_shared_presentation_tick(1.5)
	shared_track.advance(0.25)
	_assert(is_equal_approx(float(shared_track.sample_at_render_time().world_x), 150.0), "all tracks use an explicitly shared presentation time instead of first-packet arrival phase")
	var frozen := Track.new()
	frozen.add_sample(_sample(1, 1, 100.0, "blocked", 0.0))
	frozen.render_tick = 10.0
	_assert(is_equal_approx(float(frozen.sample_at_render_time().world_x), 100.0), "blocked remote player is not extrapolated")

	var ledger = Ledger.new()
	ledger.reset([{"entity_id": "shared", "incarnation": 1, "kind": "barrel", "health": 1}])
	var request: Dictionary = Rules.make_request("round", "shared", 1, "lethal_contact", 10, 2, 0, "claim-a")
	var committed: Dictionary = Rules.host_commit(ledger, request, {"owner_peer_id": 2, "state": "dead"})
	_assert(bool(committed.accepted), "first shared entity claim commits")
	_assert(not bool(Rules.host_commit(ledger, request).accepted), "competing or duplicate shared claim is rejected")
	var replica = Ledger.new()
	replica.reset([{"entity_id": "shared", "incarnation": 1, "kind": "barrel", "health": 1}])
	_assert(replica.apply_commit(committed.commit) == "applied", "world commit applies on replica")
	_assert(replica.apply_commit(committed.commit) == "duplicate", "world commit is idempotent")
	var multihp_host = Ledger.new()
	multihp_host.reset([{"entity_id": "wall", "incarnation": 1, "kind": "test_multihp", "health": 2}])
	var hit_one := Rules.host_commit(multihp_host, {"entity_id": "wall", "incarnation": 1, "action": "damage", "request_id": "hit-1"})
	_assert(bool(hit_one.accepted) and multihp_host.is_active("wall") and int(multihp_host.entities.wall.shared_health) == 1, "multi-HP entity remains active after first damage commit")
	var hit_two := Rules.host_commit(multihp_host, {"entity_id": "wall", "incarnation": 1, "action": "damage", "request_id": "hit-2"})
	_assert(bool(hit_two.accepted) and not multihp_host.is_active("wall"), "multi-HP entity is destroyed after final damage commit")
	var reconnect_replica = Ledger.new()
	reconnect_replica.reset([{"entity_id": "wall", "incarnation": 1, "kind": "test_multihp", "health": 2}])
	_assert(reconnect_replica.restore_baseline(multihp_host.baseline()), "world baseline restores destroyed entity state for reconnect")
	_assert(not reconnect_replica.is_active("wall"), "restored baseline does not respawn destroyed entity")

	var built: Dictionary = Builder.new().build(73421, 45000, CourseGenerator.GENERATOR_VERSION)
	_assert(built.get("manifest") != null, "deterministic course manifest builds")
	if built.get("manifest") != null:
		var first = World.new()
		var second = World.new()
		_assert(first.configure(built.manifest).is_empty(), "first world configures")
		_assert(second.configure(built.manifest).is_empty(), "second world configures")
		for tick in range(1, 121):
			first.step_to(tick)
			second.step_to(tick)
		_assert(first.state_hash() == second.state_hash(), "world hashes match at same tick/revision")

	var owner = Runner.new()
	owner.configure("round", 2, 100.0, 460.0, {"run_speed_percent": 10200, "flip_cooldown_percent": 9500})
	_assert(is_equal_approx(owner.run_speed_multiplier, 1.02), "V2 freezes the same resolved run speed multiplier as other game modes")
	_assert(is_equal_approx(owner.flip_cooldown_multiplier, 0.95), "V2 freezes the same resolved flip cooldown as other game modes")
	var before_x := float(owner.player_state.world_x)
	owner.step(0, 460.0, 80.0)
	var local_after := float(owner.player_state.world_x)
	_assert(local_after > before_x, "owner runner advances locally")
	_assert(is_equal_approx(float(owner.player_state.world_x), local_after), "remote presentation cannot mutate owner runner state")
	var faster = Runner.new()
	var slower = Runner.new()
	faster.configure("speed-round", 1, 100.0, 460.0, {"run_speed_percent": 10100})
	slower.configure("speed-round", 2, 100.0, 460.0, {"run_speed_percent": 10000})
	for _tick in 45:
		faster.step(0, 460.0, 80.0)
		slower.step(0, 460.0, 80.0)
	var measured_speed_gap := float(faster.player_state.world_x) - float(slower.player_state.world_x)
	_assert(is_equal_approx(measured_speed_gap, 3.75), "101 percent versus 100 percent keeps its expected 45-tick distance lead")

	if _failures == 0:
		print("Multiplayer V2 contract tests passed.")
		quit(0)
	else:
		push_error("Multiplayer V2 contract tests failed: %d" % _failures)
		quit(1)

var _failures := 0
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

func _sample(tick: int, sequence: int, x: float, state: String = "running", vx: float = 100.0) -> Dictionary:
	return {"simulation_tick": tick, "sample_seq": sequence, "world_x": x, "y": 10.0, "velocity_x": vx, "velocity_y": 0.0, "locomotion_state": state}
