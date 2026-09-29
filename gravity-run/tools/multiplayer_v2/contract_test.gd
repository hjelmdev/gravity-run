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

func _initialize() -> void:
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
	host_coordinator.round_started.connect(func(_round_id: String, _descriptor: Dictionary) -> void: started[0] = true)
	host_coordinator.all_prepare_received.connect(func() -> void: prepare_scene_requested[0] = true)
	host_coordinator.control_requested.connect(func(_peer_id: int, kind: String, payload: Dictionary) -> void:
		if kind == "PREPARE_ROUND": sent_prepare.merge(payload, true)
	)
	var round_descriptor := {"round_id": "barrier-round", "lobby_generation": 5, "manifest_hash": "hash", "seed": 4321, "players": [{"user_id": "host", "player_slot": 1}, {"user_id": "guest", "player_slot": 2}], "peer_map": {"1": "host", "2": "guest"}}
	_assert(host_coordinator.prepare_as_host(round_descriptor, [2, 3], 3_000_000), "host starts round prepare")
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
