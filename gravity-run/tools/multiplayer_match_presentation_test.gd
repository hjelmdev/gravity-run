extends Node

const MatchScript := preload("res://ui/multiplayer_match.gd")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const LocalPredictionScript := preload("res://systems/multiplayer_local_prediction.gd")
const TerminalEventRules := preload("res://systems/multiplayer_terminal_event.gd")
const PlayerScene := preload("res://player/player.tscn")

func _ready() -> void:
	var player := PlayerScene.instantiate()
	player.call("set_input_enabled", false)
	add_child(player)
	player.call("set_input_enabled", false)
	assert(not player.get_node("AnimatedSprite2D").is_playing(), "a newly added multiplayer runner should safely stop its run animation")
	player.call("set_running", true)
	assert(player.get_node("AnimatedSprite2D").is_playing(), "the shared player scene should resume its animation")
	player.call("set_skin_id", 2)
	assert((player.get_node("AnimatedSprite2D") as AnimatedSprite2D).material is ShaderMaterial, "the shared player scene should support synchronized palette skins")
	player.queue_free()
	var manifest: Resource = ManifestScript.new()
	var events: Array[Dictionary] = [
		{"event_id": "block_a", "kind": "block", "x": 120.0, "y": 460.0, "width": 48.0, "height": 72.0, "from_ceiling": false},
		{"kind": "gap", "x": 200.0, "width": 100.0, "from_ceiling": false},
		{"kind": "gap", "x": 250.0, "width": 100.0, "from_ceiling": false},
		{"event_id": "barrels_a", "kind": "barrels", "x": 350.0, "y": 460.0, "width": 124.0, "height": 54.0, "count": 2, "spacing": 70.0, "motion_speed_multiplier": 1.4, "spawn_lead_distance": 820.0},
		{"event_id": "spikes_a", "kind": "spikes", "x": 500.0, "start_x": 470.0, "y": 460.0, "count": 2, "spacing": 32.0, "from_ceiling": false},
		{"event_id": "step_a", "kind": "step", "x": 650.0, "start_y": 460.0, "end_y": 400.0, "spiked": false, "from_ceiling": false},
		{"event_id": "slope_a", "kind": "slope", "x": 900.0, "start_x": 680.0, "end_x": 1120.0, "start_y": 400.0, "end_y": 460.0, "from_ceiling": false},
	]
	manifest.set("events", events)
	manifest.set("initial_floor_y", 460.0)
	manifest.set("initial_ceiling_y", 80.0)
	manifest.set("start_x", 180.0)
	assert(MatchScript.interpolated_player_state("running", "dead", 0.0) == "dead", "an authoritative death should display immediately even while position is interpolated")
	assert(MatchScript.interpolated_player_state("dead", "running", 1.0) == "dead", "an older/out-of-order running state must not resurrect a dead remote runner")
	assert(MatchScript.interpolated_player_state("running", "running", 0.25) == "running", "running state should remain unchanged during position interpolation")
	assert(MatchScript.effective_player_state("running", "dead") == "dead", "authoritative terminal status must override a stale rendered running state")
	assert(MatchScript.effective_player_state("dead", "running", true) == "running", "only local predicted terminal status may be masked by an authoritative running state")
	assert(MatchScript.effective_player_state("dead", "", true) == "running", "a predicted local death must wait for an authoritative status before becoming final")
	assert(MatchScript.effective_player_state("dead", "running") == "running", "remote presentation must use the latest authoritative running status")
	var spectator_roster: Array = [
		{"user_id": "dead_local", "state": "dead", "world_x": 900.0},
		{"user_id": "leader", "state": "running", "world_x": 600.0},
		{"user_id": "trailer", "state": "running", "world_x": 300.0},
	]
	assert(MatchScript.choose_spectator_target(spectator_roster) == "leader", "spectator should choose the furthest living player rather than the dead local player")
	spectator_roster[1]["world_x"] = 100.0
	assert(MatchScript.choose_spectator_target(spectator_roster, "leader") == "leader", "spectator target should remain stable while that runner is alive")
	spectator_roster[1]["state"] = "dead"
	assert(MatchScript.choose_spectator_target(spectator_roster, "leader") == "trailer", "spectator target should change when its current runner is terminal")
	var spectator_view: Node2D = MatchScript.new()
	spectator_view.set("_local_user_id", "dead_local")
	spectator_view.set("_snapshot", {"players": spectator_roster})
	spectator_view.set("_authoritative_snapshot", {"finished": false, "players": spectator_roster})
	spectator_view.set("_visual_slot_by_user", {"trailer": 0.0})
	spectator_view.call("_refresh_camera_state")
	assert(is_equal_approx(float(spectator_view.call("_camera_left")), 120.0), "a dead runner ahead of survivors must not pin the spectator camera at its own location")
	spectator_view.free()
	assert(MatchScript.estimate_prediction_target_tick(100, 0.05, 100.0, 0.0, 24) == 108, "prediction should estimate current host time from packet age and half-RTT instead of freezing at the received tick")
	assert(MatchScript.estimate_prediction_target_tick(100, 10.0, 0.0, 0.0, 24) == 124, "prediction recovery must remain bounded to the replay limit")
	assert(MatchScript.estimate_prediction_target_from_anchor(1, 2.55, 2.55, 19.0, 0.0, 24) == 3, "a newly received snapshot must have zero local age, even after a long lobby countdown")
	assert(MatchScript.estimate_prediction_target_from_anchor(1, 2.55, 2.55, 19.0, 0.0, 24) == MatchScript.estimate_prediction_target_from_anchor(1, 2.55, 2.55, 19.0, 0.0, 24), "the prediction target must not fall between receive handling and the next frame at the same clock")
	assert(MatchScript.estimate_prediction_target_from_anchor(61, 5.0, 5.0, 19.0, 0.0, 24) == 63, "a current normal snapshot should only account for half-RTT, not the previous packet age")
	assert(MatchScript.estimate_prediction_target_from_anchor(61, 5.0, 5.0 + 1.0 / 60.0, 19.0, 0.0, 24) >= MatchScript.estimate_prediction_target_from_anchor(61, 5.0, 5.0, 19.0, 0.0, 24), "an accepted timing anchor must be monotonic as network time advances")
	assert(MatchScript.estimate_prediction_target_tick(100, 0.2, 0.0, 0.1, 24) == 108, "backlog represents elapsed but unsimulated host time and must be subtracted exactly once")
	assert(MatchScript.estimate_prediction_target_tick(100, 0.0, 0.0, 0.0, 24, 1.0 / 60.0) >= MatchScript.estimate_prediction_target_tick(100, 0.0, 0.0, 0.0, 24, 0.0), "normal host accumulator phase must never move the prediction target backwards")
	assert(MatchScript.percentile_int([1, 2, 3, 4], 0.95) == 4, "network timing diagnostics should calculate a useful upper percentile")
	var gravity_before: Dictionary = {"user_id": "remote", "world_x": 100.0, "y": 80.0, "vertical_speed": 60.0, "state": "running", "gravity_direction": -1, "grounded": false}
	var gravity_after: Dictionary = {"user_id": "remote", "world_x": 200.0, "y": 140.0, "vertical_speed": -60.0, "state": "running", "gravity_direction": 1, "grounded": true}
	var mid_flip: Dictionary = MatchScript.interpolate_player_sample(gravity_before, gravity_after, 0.5)
	assert(is_equal_approx(float(mid_flip.world_x), 150.0) and int(mid_flip.gravity_direction) == -1 and not bool(mid_flip.grounded), "motion should interpolate while discrete gravity/contact state waits for the authoritative endpoint")
	var end_flip: Dictionary = MatchScript.interpolate_player_sample(gravity_before, gravity_after, 1.0)
	assert(int(end_flip.gravity_direction) == 1 and bool(end_flip.grounded), "discrete movement state should switch at the authoritative sample")
	var terminal_flip: Dictionary = MatchScript.interpolate_player_sample(gravity_before, {"user_id": "remote", "world_x": 200.0, "y": 140.0, "state": "dead", "gravity_direction": 1}, 0.1)
	assert(str(terminal_flip.state) == "dead", "terminal state should be immediate even while position is interpolated")
	assert(not MatchScript.may_show_results(false, {"finished": false}), "a guest must not show local predicted results before the host finishes")
	assert(MatchScript.may_show_results(false, {"finished": true}), "a guest should show results once the host's authoritative snapshot is finished")
	assert(not MatchScript.may_show_results(true, {"finished": false}), "the host must not show results before its simulation finishes")
	assert(MatchScript.may_show_results(true, {}, true), "the host simulation is authoritative for its own results")
	var valid_finished := {"tick": 12, "finished": true, "finish_revision": 1, "finish_tick": 12, "finish_reason": "elimination", "players": [
		{"user_id": "host", "state": "dead", "terminal_reason": "hazard_hit", "terminal_tick": 5},
		{"user_id": "guest_a", "state": "dead", "terminal_reason": "out_of_bounds", "terminal_tick": 12},
		{"user_id": "guest_b", "state": "dead", "terminal_reason": "hazard_hit", "terminal_tick": 9},
	]}
	assert(MatchScript.match_state_error(valid_finished, ["host", "guest_a", "guest_b"]).is_empty(), "a complete and reasoned terminal roster should pass finish validation")
	var contradictory_finish: Dictionary = valid_finished.duplicate(true)
	contradictory_finish.players[2].state = "running"
	assert(MatchScript.match_state_error(contradictory_finish, ["host", "guest_a", "guest_b"]) == "finished_snapshot_has_running_player", "a finish decision must never accept a still-running player")
	assert(not MatchScript.match_state_error(valid_finished, ["host", "guest_a"]).is_empty(), "finish validation must require the locked complete roster")
	var malformed_terminal: Dictionary = valid_finished.duplicate(true)
	malformed_terminal.players[0].terminal_reason = ""
	assert(not MatchScript.match_state_error(malformed_terminal, ["host", "guest_a", "guest_b"]).is_empty(), "terminal states must include an explicit cause")
	var rollback_snapshot: Dictionary = {"tick": 13, "finished": false, "players": valid_finished.players}
	assert(MatchScript.match_state_error(rollback_snapshot, ["host", "guest_a", "guest_b"], 1) == "finished_state_rolled_back", "a guest must not accept a running snapshot after an accepted finish")
	var service_identity := MultiplayerService.identity_user_id
	var service_room: Dictionary = MultiplayerService.room_state.duplicate(true)
	MultiplayerService.identity_user_id = "host"
	MultiplayerService.room_state = {"room_id": "presentation-test", "owner_user_id": "host"}
	var camera_manifest: Resource = ManifestScript.new()
	camera_manifest.set("generator_version", 4)
	camera_manifest.set("course_identity", "presentation-test")
	camera_manifest.set("seed_value", 24680)
	camera_manifest.set("course_length_px", 10000)
	camera_manifest.set("finish_x", 10180.0)
	camera_manifest.set("manifest_hash", camera_manifest.call("calculate_hash"))
	var host_simulation := SimulationScript.new()
	assert(host_simulation.configure(camera_manifest, [
		{"user_id": "host", "display_name": "Host"},
		{"user_id": "guest_a", "display_name": "Guest A"},
		{"user_id": "guest_b", "display_name": "Guest B"},
	]).is_empty())
	var host_dead: Dictionary = host_simulation.get_player("host")
	host_dead.state = "dead"
	var guest_a_dead: Dictionary = host_simulation.get_player("guest_a")
	guest_a_dead.state = "dead"
	var guest_b_running: Dictionary = host_simulation.get_player("guest_b")
	guest_b_running.world_x = 1400.0
	assert(host_simulation.apply_authoritative_player_state("host", host_dead))
	assert(host_simulation.apply_authoritative_player_state("guest_a", guest_a_dead))
	assert(host_simulation.apply_authoritative_player_state("guest_b", guest_b_running))
	var host_camera_view: Node2D = MatchScript.new()
	host_camera_view.set("_local_user_id", "host")
	host_camera_view.set("_owner_user_id", "host")
	host_camera_view.set("_simulation", host_simulation)
	host_camera_view.set("_snapshot", host_simulation.get_snapshot())
	host_camera_view.set("_authoritative_snapshot", {})
	host_camera_view.set("_visual_slot_by_user", {"guest_b": 0.0})
	host_camera_view.call("_refresh_camera_state")
	assert(str(host_camera_view.call("_player_state", "host").get("state", "")) == "dead", "the host's own simulated death must be authoritative without a received snapshot")
	assert(host_camera_view.get("_camera_mode") == "SPECTATING" and host_camera_view.get("_spectator_target_user_id") == "guest_b", "a dead host should spectate the living guest")
	assert(is_equal_approx(float(host_camera_view.call("_camera_left")), 1220.0), "the host spectator camera should use the living guest's position")
	host_camera_view.free()
	var rejected_finish_view: Node2D = MatchScript.new()
	rejected_finish_view.set("_manifest", camera_manifest)
	rejected_finish_view.set("_start_generation", "test-generation")
	var expected_roster: Array[String] = ["host", "guest_a", "guest_b"]
	rejected_finish_view.set("_match_roster_ids", expected_roster)
	rejected_finish_view.set("_last_authoritative_tick", 11)
	var rejected_finish := valid_finished.duplicate(true)
	rejected_finish["tick"] = 12
	rejected_finish["course_identity"] = "presentation-test"
	rejected_finish["match_generation"] = "test-generation"
	rejected_finish.players[2].state = "running"
	assert(not rejected_finish_view.call("_accept_authoritative_snapshot", rejected_finish), "the guest snapshot path must reject finished=true with a running player")
	assert(int(rejected_finish_view.get("_last_authoritative_tick")) == 11 and str(rejected_finish_view.get("_last_snapshot_rejection")) == "finished_snapshot_has_running_player", "rejected finish data must not mutate the guest's accepted state: %s at tick %d" % [str(rejected_finish_view.get("_last_snapshot_rejection")), int(rejected_finish_view.get("_last_authoritative_tick"))])
	rejected_finish_view.free()
	# Exercise the real guest snapshot receive/reconcile path for both the first
	# packet after a long countdown and an ordinary 30 Hz packet.
	MultiplayerService.identity_user_id = "guest"
	MultiplayerService.room_state = {"room_id": "presentation-test", "owner_user_id": "host"}
	var guest_simulation := SimulationScript.new()
	assert(guest_simulation.configure(camera_manifest, [
		{"user_id": "host", "display_name": "Host"},
		{"user_id": "guest", "display_name": "Guest"},
	]).is_empty())
	guest_simulation.start()
	guest_simulation.advance_to_tick(2, 12, ["guest"])
	var guest_tick_two: Dictionary = guest_simulation.get_player("guest")
	guest_simulation.advance_to_tick(3, 12, ["guest"])
	var guest_tick_three: Dictionary = guest_simulation.get_player("guest")
	var prediction: RefCounted = LocalPredictionScript.new()
	prediction.bind(guest_simulation, "guest")
	var clock_view: Node2D = MatchScript.new()
	clock_view.set("_manifest", camera_manifest)
	clock_view.set("_simulation", guest_simulation)
	clock_view.set("_local_prediction", prediction)
	clock_view.set("_local_user_id", "guest")
	clock_view.set("_owner_user_id", "host")
	var clock_roster: Array[String] = ["guest", "host"]
	clock_view.set("_match_roster_ids", clock_roster)
	clock_view.set("_start_generation", "clock-test")
	clock_view.set("_planned_local_start_msec", 1)
	clock_view.set("_network_clock", 2.55)
	clock_view.set("_estimated_peer_rtt_msec", 19.0)
	clock_view.set("_last_authoritative_tick", -1)
	var first_render_history: Array[Dictionary] = [
		{"tick": 2, "position": Vector2(float(guest_tick_two.world_x), float(guest_tick_two.y))},
		{"tick": 3, "position": Vector2(float(guest_tick_three.world_x), float(guest_tick_three.y))},
	]
	clock_view.set("_local_render_history", first_render_history)
	clock_view.set("_local_render_clock_tick", 2.5)
	var host_simulation_for_clock := SimulationScript.new()
	assert(host_simulation_for_clock.configure(camera_manifest, [
		{"user_id": "host", "display_name": "Host"},
		{"user_id": "guest", "display_name": "Guest"},
	]).is_empty())
	host_simulation_for_clock.start()
	host_simulation_for_clock.advance_to_tick(1, 12)
	var first_clock_snapshot: Dictionary = JSON.parse_string(JSON.stringify(host_simulation_for_clock.get_snapshot()))
	first_clock_snapshot["match_generation"] = "clock-test"
	assert(bool(clock_view.call("_accept_authoritative_snapshot", first_clock_snapshot)), "first post-countdown snapshot should reconcile through the complete receive path: %s players=%d roster=%d" % [str(clock_view.get("_last_snapshot_rejection")), first_clock_snapshot.get("players", []).size(), (clock_view.get("_match_roster_ids") as Array).size()])
	assert(int(guest_simulation.get("tick")) == 3 and int(clock_view.call("_prediction_target_tick")) == 3, "the first snapshot must not use countdown time as packet age or cause a replay jump")
	assert((clock_view.get("_visual_correction") as Vector2).length() < 0.01, "a countdown-length wait followed by an ordinary first snapshot must not create a false camera correction")
	assert(is_equal_approx(float(clock_view.get("_last_snapshot_received_network_clock")), 2.55), "the accepted snapshot tick and receive-time anchor must be committed together")
	host_simulation_for_clock.advance_to_tick(61, 60)
	while int(guest_simulation.get("tick")) < 63:
		guest_simulation.advance_to_tick(int(guest_simulation.get("tick")) + 1, 1, ["guest"])
		clock_view.call("_record_local_render_sample")
	clock_view.set("_local_render_clock_tick", 62.5)
	clock_view.set("_network_clock", 2.55 + 1.0 / 30.0)
	var ordinary_clock_snapshot: Dictionary = JSON.parse_string(JSON.stringify(host_simulation_for_clock.get_snapshot()))
	ordinary_clock_snapshot["match_generation"] = "clock-test"
	assert(bool(clock_view.call("_accept_authoritative_snapshot", ordinary_clock_snapshot)), "ordinary snapshot should reconcile through the complete receive path")
	assert(int(guest_simulation.get("tick")) == 63 and int(clock_view.call("_prediction_target_tick")) == 63, "normal receive must not replay to tick 65 and then immediately target 63")
	assert((clock_view.get("_visual_correction") as Vector2).length() < 0.01, "constant-speed replay at the same simulation phase must not be turned into correction")
	var before_bad_snapshot: Dictionary = guest_simulation.get_snapshot()
	var before_bad_anchor := float(clock_view.get("_last_snapshot_received_network_clock"))
	var before_bad_buffer_size := (clock_view.get("_snapshot_buffer") as Array).size()
	var malformed_clock_snapshot: Dictionary = ordinary_clock_snapshot.duplicate(true)
	malformed_clock_snapshot["tick"] = 62
	assert(not clock_view.call("_accept_authoritative_snapshot", malformed_clock_snapshot), "a JSON checkpoint with mismatched world time must be rejected")
	assert(guest_simulation.get_snapshot() == before_bad_snapshot, "rejected network state must not move the guest or mutate its world")
	assert(int(clock_view.get("_last_authoritative_tick")) == 61 and is_equal_approx(float(clock_view.get("_last_snapshot_received_network_clock")), before_bad_anchor) and (clock_view.get("_snapshot_buffer") as Array).size() == before_bad_buffer_size, "rejection must preserve accepted tick, timing anchor, and render history")
	clock_view.free()
	# Reproduce the three-player case: host and guest A are already terminal,
	# guest B is still alive, and guest A learns its death over the reliable path.
	MultiplayerService.identity_user_id = "guest_a"
	MultiplayerService.room_state = {"room_id": "presentation-test", "owner_user_id": "host"}
	var spectator_simulation := SimulationScript.new()
	assert(spectator_simulation.configure(camera_manifest, [
		{"user_id": "host", "display_name": "Host"},
		{"user_id": "guest_a", "display_name": "Guest A"},
		{"user_id": "guest_b", "display_name": "Guest B"},
	]).is_empty())
	spectator_simulation.start()
	spectator_simulation.advance_to_tick(1, 1)
	for dead_id in ["host", "guest_a"]:
		var dead_player: Dictionary = spectator_simulation.get_player(dead_id)
		dead_player.state = "dead"
		dead_player.terminal_tick = 1
		dead_player.terminal_reason = "hazard_hit"
		assert(spectator_simulation.apply_authoritative_player_state(dead_id, dead_player))
	var survivor_state: Dictionary = spectator_simulation.get_player("guest_b")
	survivor_state.world_x = 1400.0
	assert(spectator_simulation.apply_authoritative_player_state("guest_b", survivor_state))
	spectator_simulation.advance_to_tick(2, 1)
	var guest_spectator_view: Node2D = MatchScript.new()
	guest_spectator_view.set("_manifest", camera_manifest)
	guest_spectator_view.set("_simulation", spectator_simulation)
	guest_spectator_view.set("_local_user_id", "guest_a")
	guest_spectator_view.set("_owner_user_id", "host")
	guest_spectator_view.set("_start_generation", "spectator-test")
	var spectator_roster_ids: Array[String] = ["host", "guest_a", "guest_b"]
	guest_spectator_view.set("_match_roster_ids", spectator_roster_ids)
	guest_spectator_view.set("_snapshot", spectator_simulation.get_snapshot())
	guest_spectator_view.set("_authoritative_snapshot", spectator_simulation.get_snapshot())
	guest_spectator_view.set("_last_authoritative_tick", 1)
	guest_spectator_view.set("_visual_slot_by_user", {"guest_b": 0.0})
	var guest_a_prediction: RefCounted = LocalPredictionScript.new()
	guest_a_prediction.bind(spectator_simulation, "guest_a")
	guest_spectator_view.set("_local_prediction", guest_a_prediction)
	var guest_a_terminal: Dictionary = spectator_simulation.get_player("guest_a")
	var guest_a_terminal_packet: Dictionary = TerminalEventRules.build_payload("presentation-test", "spectator-test", "presentation-test", guest_a_terminal, 2)
	guest_spectator_view.call("_accept_reliable_player_terminal", guest_a_terminal_packet)
	guest_spectator_view.call("_refresh_camera_state")
	assert(guest_spectator_view.get("_camera_mode") == "SPECTATING" and guest_spectator_view.get("_spectator_target_user_id") == "guest_b", "a dead guest must spectate the surviving guest after receiving its reliable terminal event")
	assert(float(guest_spectator_view.call("_camera_left")) > 1200.0, "the dead guest camera must follow the still-running third player, not remain near the dead local runner")
	guest_spectator_view.call("_accept_reliable_player_terminal", guest_a_terminal_packet)
	guest_spectator_view.call("_refresh_camera_state")
	assert((guest_spectator_view.get("_terminal_overlays") as Dictionary).size() == 1 and guest_spectator_view.get("_spectator_target_user_id") == "guest_b", "a duplicate terminal retry must be idempotent and keep spectator camera ownership")
	guest_spectator_view.free()
	MultiplayerService.identity_user_id = service_identity
	MultiplayerService.room_state = service_room
	assert(is_equal_approx(MatchScript.estimate_shared_start_msec(1000, 5.0, [400, 600]), 6250.0), "host start should compensate for measured peer delivery latency")
	assert(is_equal_approx(MatchScript.estimate_guest_clock_offset_ms(5200, 5000, 5400), 0.0), "clock-offset estimation should use the probe round-trip midpoint")
	assert(is_equal_approx(MatchScript.estimate_guest_clock_offset_ms(15200, 10000, 10400), 5000.0), "clock-offset estimation should translate a guest clock into host time")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 0.0, 5.0, -1.0), 95.0), "snapshot rendering should start behind the newest host tick")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 1.0, 5.0, 95.0), 103.0), "snapshot extrapolation must be capped to three ticks")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 0.0, 5.0, 96.0), 96.0), "the render timeline must never move backwards")
	assert(MatchScript.correction_after_authority(Vector2(102.0, 202.0), Vector2(100.0, 200.0)).is_equal_approx(Vector2(2.0, 2.0)), "small local prediction errors should fade smoothly")
	assert(MatchScript.correction_after_authority(Vector2(300.0, 200.0), Vector2(100.0, 200.0)).is_equal_approx(Vector2(200.0, 0.0)), "large ordinary prediction errors should be smoothed, not abruptly erased")
	assert(MatchScript.correction_after_authority(Vector2(100.0, 350.0), Vector2(100.0, 200.0)).is_equal_approx(Vector2(0.0, 150.0)), "large vertical errors must not erase an unrelated horizontal render anchor")
	assert(MatchScript.correction_after_authority(Vector2(102.0, 202.0), Vector2(100.0, 200.0), "running", "dead") == Vector2.ZERO, "terminal state transitions must not be visually delayed")
	assert(MatchScript.fade_render_correction(Vector2(50.0, 30.0), 0.1, 420.0).length() < Vector2(50.0, 30.0).length(), "a replay continuity error should fade smoothly in both axes")
	var x_fade_without_y: float = MatchScript.fade_render_correction(Vector2(12.0, 0.0), 1.0 / 60.0, 420.0).x
	var x_fade_with_y: float = MatchScript.fade_render_correction(Vector2(12.0, 80.0), 1.0 / 60.0, 420.0).x
	assert(is_equal_approx(x_fade_without_y, x_fade_with_y), "vertical correction must not slow horizontal/camera correction")
	var render_samples: Array[Dictionary] = [
		{"tick": 0, "position": Vector2.ZERO},
		{"tick": 1, "position": Vector2(500.0, 0.0)},
	]
	for fps in [60, 120, 240]:
		var previous_x := -1.0
		for frame in range(fps + 1):
			var at_tick := float(frame) * 60.0 / float(fps)
			var render_position: Vector2 = MatchScript.interpolate_local_render_position(render_samples, at_tick)
			assert(render_position.x >= previous_x, "local interpolation must remain monotonic at %d Hz render: frame=%d x=%f previous=%f" % [fps, frame, render_position.x, previous_x])
			previous_x = render_position.x
		assert(is_equal_approx(previous_x, 500.0), "local interpolation must reach the simulation sample at %d Hz render" % fps)
	var old_render_path: Array[Dictionary] = [
		{"tick": 62, "position": Vector2(700.0, 300.0)},
		{"tick": 63, "position": Vector2(705.0, 300.0)},
	]
	var corrected_render_path: Array[Dictionary] = [
		{"tick": 61, "position": Vector2(695.0, 300.0)},
		{"tick": 62, "position": Vector2(700.0, 300.0)},
		{"tick": 63, "position": Vector2(705.0, 300.0)},
	]
	assert(is_zero_approx(MatchScript.interpolate_local_render_position(old_render_path, 62.5).distance_to(MatchScript.interpolate_local_render_position(corrected_render_path, 62.5))), "snapshot reconcile must compare actual old and replayed motion at the same fractional render phase")
	var blocked_path_before := MatchScript.interpolate_local_render_position([{"tick": 62, "position": Vector2(380.0, 250.0)}, {"tick": 63, "position": Vector2(380.0, 240.0)}], 62.5)
	var blocked_path_after := MatchScript.interpolate_local_render_position([{"tick": 61, "position": Vector2(380.0, 270.0)}, {"tick": 62, "position": Vector2(380.0, 250.0)}, {"tick": 63, "position": Vector2(380.0, 240.0)}], 62.5)
	assert(is_zero_approx(blocked_path_before.distance_to(blocked_path_after)), "a correct blocked X and vertical motion must not get a fabricated constant-speed correction")
	var ranking := [
		{"user_id": "alpha", "state": "running", "world_x": 780.0},
		{"user_id": "beta", "state": "running", "world_x": 780.0},
	]
	assert(MatchScript.calculate_player_place(ranking, "alpha") == 1 and MatchScript.calculate_player_place(ranking, "beta") == 2, "exact running ties should use the same deterministic user ID tiebreak on every peer")
	ranking[0]["state"] = "dead"
	assert(MatchScript.calculate_player_place(ranking, "alpha") == 2, "an eliminated player should rank behind a still-running opponent")
	assert(MatchScript.calculate_player_place(ranking, "beta") == 1, "the remaining runner should lead while another player is eliminated")
	var match_view: Node2D = MatchScript.new()
	match_view.set("_manifest", manifest)
	match_view.set("_snapshot", {"tick": 100, "players": [{"user_id": "runner", "state": "running", "world_x": 500.0}]})
	match_view.set("_authoritative_snapshot", {"tick": 100, "world_time": 100.0 / 60.0, "players": [{"user_id": "runner", "state": "running", "world_x": 500.0}], "world_hazards": {}})
	match_view.set("_last_authoritative_tick", 100)
	match_view.call("_store_terminal_overlay", "runner", {"user_id": "runner", "state": "dead", "world_x": 510.0}, 104)
	assert(int(match_view.get("_authoritative_snapshot").get("tick", -1)) == 100, "a reliable terminal event must not relabel an older full checkpoint with a newer tick")
	assert(int(match_view.get("_last_authoritative_tick")) == 100, "terminal events must not advance the full-snapshot tick watermark")
	assert(str(match_view.call("_authoritative_player_state", "runner").get("state", "")) == "dead", "the terminal overlay must immediately provide authoritative player state")
	var still_older_checkpoint: Dictionary = match_view.get("_authoritative_snapshot")
	match_view.call("_apply_terminal_overlays", still_older_checkpoint)
	assert(str(still_older_checkpoint.players[0].state) == "dead", "terminal overlays must survive later stale running checkpoints in presentation")
	assert(not match_view.call("_store_terminal_overlay", "runner", {"user_id": "runner", "state": "dead", "world_x": 505.0}, 103), "an older terminal event must not replace a newer one")
	var draw_order_view: Node2D = MatchScript.new()
	var draw_order_root := Node2D.new()
	draw_order_view.add_child(draw_order_root)
	draw_order_view.set("_course_root", draw_order_root)
	var course_root := Node2D.new()
	var remote_runner := Node2D.new()
	var local_runner := Node2D.new()
	draw_order_root.add_child(local_runner)
	draw_order_root.add_child(remote_runner)
	draw_order_view.set("_local_user_id", "local")
	draw_order_view.set("_player_views", {"local": local_runner, "remote": remote_runner})
	draw_order_view.set("_visual_slot_by_user", {"local": -14.0, "remote": 14.0, "third": 0.0})
	draw_order_view.call("_bring_local_runner_to_front")
	assert(draw_order_root.get_child(draw_order_root.get_child_count() - 1) == local_runner, "each client should draw its own runner in front regardless of shared player order")
	var overlap_states: Array = [
		{"user_id": "local", "world_x": 400.0, "y": 200.0},
		{"user_id": "remote", "world_x": 400.0, "y": 200.0},
		{"user_id": "third", "world_x": 400.0, "y": 270.0},
	]
	var local_visual: Vector2 = draw_order_view.call("_visual_player_position", overlap_states[0], overlap_states)
	var remote_visual: Vector2 = draw_order_view.call("_visual_player_position", overlap_states[1], overlap_states)
	assert(is_equal_approx(absf(local_visual.x - remote_visual.x), 28.0), "overlapping runners should use stable roster offsets")
	var crossed_states: Array = [
		{"user_id": "local", "world_x": 411.0, "y": 200.0},
		{"user_id": "remote", "world_x": 389.0, "y": 200.0},
		{"user_id": "third", "world_x": 400.0, "y": 270.0},
	]
	var local_offset_before_crossing := local_visual.x - float(overlap_states[0].world_x)
	var local_after_crossing: Vector2 = draw_order_view.call("_visual_player_position", crossed_states[0], crossed_states)
	assert(is_equal_approx(local_after_crossing.x - float(crossed_states[0].world_x), local_offset_before_crossing), "a runner crossing another or changing vertical lane must not change its stable visual slot")
	assert(is_equal_approx(MatchScript.stable_visual_offset("local", ["third", "remote", "local"]), MatchScript.stable_visual_offset("local", ["local", "third", "remote"])), "visual slots must not depend on player array order")
	draw_order_view.free()
	match_view.add_child(course_root)
	match_view.set("_course_root", course_root)
	match_view.call("_build_course_view")
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 640.0, false)), 460.0))
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 650.1, false)), 400.0))
	assert(is_equal_approx(float(match_view.call("_manifest_surface_y_at", 900.0, false)), 430.0))
	assert(match_view.get("_terrain_events").size() == 2, "multiplayer surface rendering should cache both steps and slopes")
	var course_nodes: Dictionary = match_view.get("_course_nodes")
	assert(course_nodes["block_a"].get_script().resource_path == "res://hazards/block.gd")
	assert(course_nodes["barrels_a_0"].get_script().resource_path == "res://hazards/barrel.gd")
	course_nodes["barrels_a_0"].call("apply_replicated_motion", Vector2(333.0, 460.0), 1.25, 0.0, true)
	assert(is_equal_approx(float(course_nodes["barrels_a_0"].get("roll_angle")), 1.25), "networked barrel visuals must update their own draw state")
	assert(bool(course_nodes["barrels_a_0"].visible), "spawned networked barrels should be visible")
	assert(course_nodes["spikes_a_0"].get_script().resource_path == "res://hazards/spikes.gd")
	assert(course_nodes["step_a"].get_script().resource_path == "res://terrain/ledge.gd")
	assert(course_nodes["slope_a"].get_script().resource_path == "res://terrain/slope.gd")
	assert(course_root.get_child_count() == 9, "manifest events should instantiate the same block, barrel, spike and terrain scenes as singleplayer")
	(course_nodes["barrels_a_0"] as Node).free()
	match_view.set("_snapshot", {"world_hazards": {"barrels": [{"entity_id": "barrels_a_0_0"}], "destroyed_event_ids": []}})
	match_view.call("_sync_course_view")
	assert(MatchScript.distance_m(180.0, 180.0) == 0)
	assert(MatchScript.distance_m(12005.0, 180.0) == 1182)
	match_view.call("_build_hud")
	match_view.set("_snapshot", {"finished": true, "players": [
		{"user_id": "winner", "display_name": "Winner", "state": "finished", "finish_tick": 20, "world_x": 1200.0},
		{"user_id": "second", "display_name": "Second", "state": "dead", "finish_tick": -1, "world_x": 900.0},
	]})
	match_view.set("_authoritative_snapshot", {"finished": true, "finish_reason": "finish_line", "players": match_view.get("_snapshot").players})
	match_view.set("_accepted_finish_revision", 1)
	match_view.call("_show_results")
	assert((match_view.get("_results_list") as VBoxContainer).get_child_count() == 2, "the results board should include finishers and eliminated players")
	assert((match_view.get("_results_panel") as PanelContainer).visible, "the standings should have a visible results panel")
	match_view.free()
	var tie_view: Node2D = MatchScript.new()
	tie_view.set("_manifest", manifest)
	tie_view.call("_build_hud")
	tie_view.set("_snapshot", {"finished": true, "players": [
		{"user_id": "alpha", "display_name": "Alpha", "state": "dead", "world_x": 900.0},
		{"user_id": "beta", "display_name": "Beta", "state": "dead", "world_x": 900.0},
	]})
	tie_view.set("_authoritative_snapshot", {"finished": true, "finish_reason": "elimination", "players": tie_view.get("_snapshot").players})
	tie_view.set("_accepted_finish_revision", 1)
	tie_view.call("_show_results")
	assert((tie_view.get("_result_label") as Label).text.begins_with(tr("No winner")), "an exact distance tie after elimination must not arbitrarily name a winner")
	var tie_rows: VBoxContainer = tie_view.get("_results_list")
	assert((tie_rows.get_child(0).get_child(1) as Label).text == "#1" and (tie_rows.get_child(1).get_child(1) as Label).text == "#1", "players eliminated at the same distance should share a place")
	assert(not (tie_view.get("_status_label") as Label).visible, "the in-game status text should not remain behind the results modal")
	tie_view.set("_return_requester_name", "Guest")
	tie_view.call("_update_return_request_notice")
	assert((tie_view.get("_return_request_notice") as Label).visible and (tie_view.get("_return_request_notice") as Label).text.contains("Guest"), "a guest return request should be readable inside the results panel")
	tie_view.free()
	print("Multiplayer match presentation tests passed.")
	get_tree().quit()
