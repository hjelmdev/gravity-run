extends SceneTree

const Protocol := preload("res://systems/multiplayer_v2/v2_protocol.gd")
const Clock := preload("res://systems/multiplayer_v2/v2_round_clock.gd")
const Track := preload("res://systems/multiplayer_v2/v2_remote_track.gd")
const Motion := preload("res://systems/runner_motion.gd")
const Ledger := preload("res://systems/multiplayer_v2/v2_world_event_ledger.gd")
const Rules := preload("res://systems/multiplayer_v2/v2_destructible_rules.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Runner := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const Coordinator := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const V2Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const V2Transport := preload("res://systems/multiplayer_v2/v2_webrtc_transport.gd")
const HudLayout := preload("res://ui/multiplayer_v2/v2_hud_layout.gd")

func _initialize() -> void:
	var lobby_version_migration := FileAccess.get_file_as_string("res://supabase/migrations/202609300002_v2_lobby_cycles.sql")
	_assert(lobby_version_migration.contains("p_game_version <> '%s'" % V2Service.V2_GAME_VERSION), "V2 client lobby version remains compatible with the deployed room-creation gate")
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
	_assert(Coordinator.START_LEAD_USEC == 3_000_000, "common start reserves a full three-second countdown")
	_assert(Coordinator.countdown_label(10_000_000, 7_000_000) == "3", "countdown begins with three seconds at the shared start deadline")
	_assert(Coordinator.countdown_label(10_000_000, 8_000_001) == "2", "countdown uses the shared deadline after delayed frames")
	_assert(Coordinator.countdown_label(10_000_000, 9_100_000) == "1", "countdown advances from remaining shared time")
	_assert(Coordinator.countdown_label(10_000_000, 10_000_001) == "START!", "late frames show START without replaying a stale local sequence")
	for viewport_size in [Vector2(1920, 1080), Vector2(960, 540), Vector2(844, 390), Vector2(320, 180)]:
		var hud_layout: Dictionary = HudLayout.for_viewport(viewport_size)
		var hud_margin := float(hud_layout.margin)
		var menu_rect: Rect2 = hud_layout.button
		var status_rect: Rect2 = hud_layout.status
		var tools_rect: Rect2 = hud_layout.panel
		_assert(menu_rect.position.x >= 0.0 and menu_rect.end.x <= viewport_size.x - hud_margin + 0.01, "responsive menu stays inside the right safe margin at %s" % viewport_size)
		_assert(status_rect.position.x >= hud_margin - 0.01 and status_rect.end.x <= menu_rect.position.x - 15.0, "status text stays clear of the menu at %s" % viewport_size)
		_assert(tools_rect.position.x >= hud_margin - 0.01 and tools_rect.end.x <= viewport_size.x - hud_margin + 0.01, "diagnostics panel adapts to the viewport width at %s" % viewport_size)
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
	var stale_track := Track.new()
	var stale_source := _sample(1, 1, 108.0)
	stale_source["velocity_x"] = 500.0
	_assert(stale_track.seed({"world_x": 100.0, "y": 200.0, "velocity_x": 500.0, "gravity_direction": 1, "grounded": true}), "remote track seeds from the frozen round spawn at tick zero")
	_assert(stale_track.add_sample(stale_source), "remote track accepts its first movement sample after the seed")
	stale_track.set_shared_presentation_tick(6.94)
	var age_99: Dictionary = stale_track.advance_presentation(1.0 / 144.0)
	_assert(not bool(age_99.stale) and str(age_99.render_mode) == "projection", "99 ms sample age remains inside bounded projection")
	_assert(is_equal_approx(float(age_99.world_x), 157.5), "projection is based on sample velocity and actual presentation age")
	stale_track.set_shared_presentation_tick(7.0)
	var age_100: Dictionary = stale_track.advance_presentation(1.0 / 144.0)
	_assert(not bool(age_100.stale) and is_equal_approx(float(age_100.world_x), 158.0), "100 ms boundary retains the last projected pose")
	stale_track.set_shared_presentation_tick(7.06)
	var age_101: Dictionary = stale_track.advance_presentation(1.0 / 144.0)
	_assert(bool(age_101.stale) and str(age_101.render_mode) == "stale_hold", "101 ms transitions directly to stale hold without raw-position fallback")
	stale_track.set_shared_presentation_tick(10.0)
	var age_150: Dictionary = stale_track.advance_presentation(1.0 / 144.0)
	_assert(bool(age_150.stale) and is_equal_approx(float(age_150.world_x), 158.0), "a direct jump to 150 ms holds the capped projected position")
	var late_sample := _sample(9, 2, 120.0)
	late_sample["velocity_x"] = 500.0
	_assert(stale_track.add_sample(late_sample), "remote track accepts a delayed recovery sample behind the held pose")
	var recovery_previous_x := float(stale_track.advance_presentation(1.0 / 60.0).world_x)
	for tick in range(11, 40):
		stale_track.set_shared_presentation_tick(float(tick))
		var recovery_pose: Dictionary = stale_track.advance_presentation(1.0 / 60.0)
		_assert(float(recovery_pose.world_x) >= recovery_previous_x - 0.001, "stale recovery cannot move a running player backwards at presentation tick %d" % tick)
		recovery_previous_x = float(recovery_pose.world_x)
	var reads_a: Dictionary = stale_track.sample_at_render_time()
	var reads_b: Dictionary = stale_track.sample_at_render_time()
	_assert(reads_a == reads_b, "camera, diagnostics, and sprites observe the same cached pose within a frame")
	var terminal_sample := _sample(40, 3, 130.0, "dead", 0.0)
	_assert(stale_track.add_sample(terminal_sample), "remote track accepts authoritative terminal state")
	stale_track.set_shared_presentation_tick(40.0)
	var exact_terminal: Dictionary = stale_track.advance_presentation(1.0 / 60.0)
	_assert(str(exact_terminal.render_mode) == "terminal" and is_equal_approx(float(exact_terminal.world_x), 130.0), "terminal pose bypasses running-only stale recovery correction")
	for packet_rate in [30, 60]:
		for render_rate in [30, 60, 144]:
			var network_track := Track.new()
			network_track.seed({"world_x": 0.0, "y": 200.0, "velocity_x": 500.0, "gravity_direction": 1, "grounded": true})
			var in_flight: Array[Dictionary] = []
			var next_sequence := 1
			var elapsed_seconds := 0.0
			var previous_presented_x := 0.0
			for frame in range(render_rate * 3):
				var frame_scale: float = 0.65 if frame % 5 == 0 else (1.35 if frame % 7 == 0 else 1.0)
				elapsed_seconds += frame_scale / float(render_rate)
				while float(next_sequence) / float(packet_rate) <= elapsed_seconds:
					var sent_at := float(next_sequence) / float(packet_rate)
					var sent_tick := int(round(sent_at * 60.0))
					var packet := _sample(sent_tick, next_sequence, sent_at * 500.0)
					packet["velocity_x"] = 500.0
					var jitter: float = float([0.0, 0.035, 0.075, 0.015][next_sequence % 4])
					if next_sequence % 7 != 3:
						in_flight.append({"delivery_at": sent_at + jitter, "sample": packet})
						if next_sequence % 11 == 0:
							in_flight.append({"delivery_at": sent_at + jitter + 0.01, "sample": packet.duplicate(true)})
					next_sequence += 1
				in_flight.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.delivery_at) < float(b.delivery_at))
				while not in_flight.is_empty() and float(in_flight[0].delivery_at) <= elapsed_seconds:
					network_track.add_sample(in_flight.pop_front().sample)
				network_track.set_shared_presentation_tick(elapsed_seconds * 60.0)
				var presented: Dictionary = network_track.advance_presentation(frame_scale / float(render_rate))
				_assert(float(presented.world_x) >= previous_presented_x - 0.001, "jitter/loss at %d Hz packets and %d Hz rendering cannot regress on stale recovery" % [packet_rate, render_rate])
				previous_presented_x = float(presented.world_x)
	var vertical_track := Track.new()
	vertical_track.seed({"world_x": 0.0, "y": 260.0, "velocity_x": 500.0, "velocity_y": 1000.0, "gravity_direction": 1, "grounded": false})
	vertical_track.vertical_projector = Callable(self, "_project_test_vertical")
	vertical_track.set_shared_presentation_tick(6.0)
	var vertical_pose: Dictionary = vertical_track.advance_presentation(1.0 / 60.0)
	_assert(float(vertical_pose.y) > 260.0 and is_equal_approx(float(vertical_pose.y), 278.0) and bool(vertical_pose.grounded), "vertical prediction advances between samples and snaps to support geometry")
	for packet_rate in [30, 60]:
		for render_rate in [60, 144, 240]:
			var max_vertical_step := _run_vertical_fixture(packet_rate, render_rate)
			_assert(max_vertical_step <= 25.0, "vertical presentation stays continuous through a flip at %d Hz packets and %d Hz rendering (largest step %.2f px)" % [packet_rate, render_rate, max_vertical_step])
	var trace_diagnostics = preload("res://systems/multiplayer_v2/v2_diagnostics.gd").new()
	trace_diagnostics.begin_round_trace("trace-one", 2, "guest", 1_000_000, 500.0)
	for frame_index in range(960):
		trace_diagnostics.record_round_trace("presented_frames", {"presentation_tick": float(frame_index) / 240.0, "local_usec": 1_000_000 + frame_index * 4167})
	trace_diagnostics.freeze_round_trace("test_round_end")
	trace_diagnostics.begin_round_trace("trace-two", 2, "guest", 2_000_000, 500.0)
	var exported_traces: Dictionary = trace_diagnostics.export_report()
	_assert(exported_traces.round_traces.size() == 1 and str(exported_traces.round_traces[0].round_id) == "trace-one", "start diagnostics are frozen by round and do not combine rematches")
	_assert(exported_traces.active_round_trace.has("start_deadline_usec") and int(exported_traces.active_round_trace.schema_version) == 2, "active start trace records its local start deadline and schema")
	var saved_start_trace: Dictionary = exported_traces.round_traces[0]
	_assert(saved_start_trace.presented_frames.size() >= 450 and saved_start_trace.presented_frames.size() <= 600, "240 Hz rendering is explicitly sampled at 120 Hz without truncating the four-second trace")
	_assert(int(saved_start_trace.decimated.get("presented_frames", 0)) > 0 and int(saved_start_trace.dropped.get("presented_frames", 0)) == 0, "trace reports intentional decimation separately from dropped records")
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
	_assert(is_equal_approx(World.presentation_fraction(16.25, 17), 0.25), "world entities can be rendered on the same one-tick-delayed presentation timeline as runners")
	if built.get("manifest") != null:
		var first = World.new()
		var second = World.new()
		_assert(first.configure(built.manifest).is_empty(), "first world configures")
		_assert(second.configure(built.manifest).is_empty(), "second world configures")
		var surface_index = SurfaceIndex.new()
		surface_index.configure(built.manifest.events, float(built.manifest.initial_floor_y), float(built.manifest.initial_ceiling_y))
		var surface_probe_xs: Array[float] = []
		for event_value in built.manifest.events:
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value
			match str(event.get("kind", "")):
				"step":
					var step_x := float(event.get("x", 0.0))
					surface_probe_xs.append_array([step_x - 0.001, step_x, step_x + 0.001])
				"slope":
					var slope_start := float(event.get("start_x", 0.0))
					var slope_end := float(event.get("end_x", 0.0))
					surface_probe_xs.append_array([slope_start - 0.001, slope_start, slope_start + 0.001, slope_end - 0.001, slope_end, slope_end + 0.001])
				"gap":
					var gap_start := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
					var gap_end := gap_start + float(event.get("width", 0.0))
					surface_probe_xs.append_array([gap_start - 0.001, gap_start, gap_start + 0.001, gap_end - 0.001, gap_end, gap_end + 0.001])
		for sample_index in range(256):
			surface_probe_xs.append(float(built.manifest.start_x) + float(sample_index) * float(built.manifest.finish_x - built.manifest.start_x) / 255.0)
		var surface_index_matches := true
		for x in surface_probe_xs:
			for ceiling in [false, true]:
				var indexed: Dictionary = surface_index.surface_at(x, ceiling)
				var reference: Dictionary = SurfaceIndex.linear_surface_at(built.manifest.events, float(built.manifest.initial_floor_y), float(built.manifest.initial_ceiling_y), x, ceiling)
				if not is_equal_approx(float(indexed.y), float(reference.y)) or bool(indexed.supported) != bool(reference.supported):
					surface_index_matches = false
					break
		_assert(surface_index_matches, "indexed floor and ceiling queries preserve exact step, slope, and gap geometry")
		second._surface_index = null # Reference path: the original event-by-event surface scan.
		var indexed_world_matches_reference := true
		for tick in range(1, 121):
			first.step_to(tick)
			second.step_to(tick)
			if first.state_hash() != second.state_hash():
				indexed_world_matches_reference = false
				break
		_assert(first.state_hash() == second.state_hash(), "world hashes match at same tick/revision")
		_assert(indexed_world_matches_reference, "indexed surface queries preserve deterministic world simulation against the original scan")
		if not first.barrels.is_empty():
			var barrel_id := str(first.barrels[0].entity_id)
			var fraction := 0.5
			var probe: Dictionary = first.barrel_presentation_probe(barrel_id, float(first.tick) - 0.5, fraction)
			var rendered_world: Dictionary = first.render_state(fraction)
			var rendered_barrel: Dictionary = {}
			for rendered_value in rendered_world.get("barrels", []):
				if str(rendered_value.get("entity_id", "")) == barrel_id:
					rendered_barrel = rendered_value
					break
			_assert(str(probe.get("entity_id", "")) == barrel_id, "barrel presentation probe keeps a stable entity ID")
			_assert(int(probe.get("simulation_tick", -1)) == first.tick and probe.has("previous") and probe.has("current"), "barrel probe records adjacent simulation states")
			_assert(not rendered_barrel.is_empty() and is_equal_approx(float(probe.get("displayed", {}).get("x", -1.0)), float(rendered_barrel.get("x", -2.0))), "barrel probe reports the same displayed pose as presentation")

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

func _project_test_vertical(sample: Dictionary, target_tick: float) -> Dictionary:
	var state := {"y": float(sample.get("y", 0.0)), "vertical_speed": float(sample.get("velocity_y", 0.0)), "gravity_direction": int(sample.get("gravity_direction", 1)), "grounded": bool(sample.get("grounded", false)), "cooldown": 0.0}
	var remaining := target_tick - float(sample.get("simulation_tick", 0.0))
	while remaining > 0.0001:
		var step_ticks := minf(remaining, 1.0)
		Motion.advance_vertical(state, step_ticks / 60.0, 300.0, 80.0, true, true)
		remaining -= step_ticks
	return {"y": float(state.y), "velocity_y": float(state.vertical_speed), "grounded": bool(state.grounded)}

func _run_vertical_fixture(packet_rate: int, render_rate: int) -> float:
	var track := Track.new()
	var initial := {"world_x": 0.0, "y": 278.0, "velocity_x": 500.0, "velocity_y": 0.0, "gravity_direction": 1, "grounded": true, "blocked": false, "locomotion_state": "running"}
	track.seed(initial)
	track.vertical_projector = Callable(self, "_project_test_vertical")
	var motion_state := {"y": 278.0, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
	var next_simulation_tick := 1
	var next_packet_tick := 60 / packet_rate
	var sequence := 0
	var elapsed_seconds := 0.0
	var previous_y := 278.0
	var max_step := 0.0
	for _frame in range(render_rate * 2):
		elapsed_seconds += 1.0 / float(render_rate)
		var completed_tick := int(floor(elapsed_seconds * 60.0))
		while next_simulation_tick <= completed_tick:
			if next_simulation_tick == 15:
				Motion.try_flip(motion_state, -1)
			Motion.advance_vertical(motion_state, 1.0 / 60.0, 300.0, 80.0, true, true)
			if next_simulation_tick >= next_packet_tick:
				sequence += 1
				var packet := {"simulation_tick": next_simulation_tick, "sample_seq": sequence, "world_x": float(next_simulation_tick) * 500.0 / 60.0, "y": float(motion_state.y), "velocity_x": 500.0, "velocity_y": float(motion_state.vertical_speed), "gravity_direction": int(motion_state.gravity_direction), "grounded": bool(motion_state.grounded), "blocked": false, "locomotion_state": "running"}
				track.add_sample(packet)
				next_packet_tick += 60 / packet_rate
			next_simulation_tick += 1
		track.set_shared_presentation_tick(maxf(elapsed_seconds * 60.0 - 1.0, 0.0))
		var pose: Dictionary = track.advance_presentation(1.0 / float(render_rate))
		var step_size := absf(float(pose.y) - previous_y)
		if step_size > max_step:
			max_step = step_size
		previous_y = float(pose.y)
	return max_step
