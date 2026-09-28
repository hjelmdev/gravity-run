extends SceneTree

const BuilderScript := preload("res://systems/course_manifest_builder.gd")
const RaceRulesScript := preload("res://systems/multiplayer_race_rules.gd")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const LocalPredictionScript := preload("res://systems/multiplayer_local_prediction.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const TerminalEventRules := preload("res://systems/multiplayer_terminal_event.gd")

func _initialize() -> void:
	assert(not HazardRules.spike_group_intersects_rect(1000.0, 460.0, 1, 32.0, 28.0, 32.0, false, Rect2(Vector2(986.0, 428.0), Vector2(2.0, 2.0))), "the triangular spike tip must not collide like its old bounding box")
	assert(HazardRules.spike_group_intersects_rect(1000.0, 460.0, 1, 32.0, 28.0, 32.0, false, Rect2(Vector2(999.0, 427.0), Vector2(2.0, 3.0))), "the actual triangular spike tip must collide in shared geometry")
	var side_spikes := HazardRules.step_spike_triangles(600.0, 460.0, 520.0, false)
	assert(HazardRules.triangle_intersects_rect(side_spikes[0], Rect2(Vector2(610.0, 465.0), Vector2(8.0, 10.0))), "side spikes on a floor step must collide with their visible triangles")
	var manifest: Resource = ManifestScript.new()
	manifest.set("generator_version", 4)
	manifest.set("course_identity", "sim-test")
	manifest.set("seed_value", 24680)
	manifest.set("course_length_px", 10000)
	manifest.set("start_x", 180.0)
	manifest.set("finish_x", 10180.0)
	manifest.set("initial_floor_y", 460.0)
	manifest.set("initial_ceiling_y", 80.0)
	manifest.set("manifest_hash", manifest.call("calculate_hash"))
	var simulation := SimulationScript.new()
	assert(RaceRulesScript.validate_players([{"user_id": "solo"}]).is_empty(), "a one-player host run should be valid")
	assert(not RaceRulesScript.validate_players([]).is_empty(), "an empty room must not start")
	var five_players: Array[Dictionary] = []
	for player_index in range(5):
		five_players.append({"user_id": "player_%d" % player_index})
	assert(RaceRulesScript.validate_players(five_players).is_empty(), "a five-player room should be valid")
	five_players.append({"user_id": "player_5"})
	assert(not RaceRulesScript.validate_players(five_players).is_empty(), "a sixth player must still be rejected")
	var solo_simulation := SimulationScript.new()
	assert(solo_simulation.configure(manifest, [{"user_id": "solo", "display_name": "Solo"}]).is_empty())
	solo_simulation.start()
	for _frame in range(1300):
		solo_simulation.advance_frame(1.0 / 60.0)
		if solo_simulation.match_finished:
			break
	assert(solo_simulation.match_finished, "a solo host race should run to completion")
	var client_prediction := SimulationScript.new()
	assert(client_prediction.configure(manifest, [{"user_id": "client_prediction", "display_name": "Client"}]).is_empty())
	client_prediction.start()
	assert(client_prediction.mark_disconnected("client_prediction"))
	client_prediction.advance_frame(1.0 / 60.0, false)
	assert(not client_prediction.match_finished, "a guest-side prediction must not authoritatively finish a multiplayer match")
	var configuration_error := simulation.configure(manifest, [
		{"user_id": "slow", "display_name": "Slow", "run_speed_percent": 10000},
		{"user_id": "fast", "display_name": "Fast", "run_speed_percent": 10100, "skin_id": 3},
	])
	assert(configuration_error.is_empty(), configuration_error)
	assert(int(simulation.get_player("fast").get("skin_id", -1)) == 3, "player skin selection should be included in authoritative simulation state")
	assert(is_equal_approx(float(simulation.get_player("slow").get("world_x", -1.0)), float(simulation.get_player("fast").get("world_x", -2.0))), "every runner must share the same simulation start position")
	simulation.start()
	assert(int(simulation.get_snapshot().get("tick", -1)) == 0, "the shared simulation must begin at tick zero")
	simulation.advance_frame(1.0 / 60.0)
	assert(int(simulation.get_snapshot().get("tick", -1)) == 1, "one fixed simulation step after the shared start must produce tick one")
	assert(simulation.submit_flip("slow", -1))
	assert(not simulation.submit_flip("slow", 1))
	var checkpoint_source := SimulationScript.new()
	assert(checkpoint_source.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	checkpoint_source.start()
	checkpoint_source.advance_to_tick(8)
	var checkpoint: Dictionary = checkpoint_source.get_snapshot()
	var replay_a := SimulationScript.new()
	var replay_b := SimulationScript.new()
	assert(replay_a.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	assert(replay_b.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	replay_a.start()
	replay_b.start()
	assert(replay_a.restore_checkpoint(checkpoint) and replay_b.restore_checkpoint(checkpoint), "a complete authority checkpoint should restore into separate prediction instances")
	var wire_checkpoint: Variant = JSON.parse_string(JSON.stringify(checkpoint))
	assert(wire_checkpoint is Dictionary, "a checkpoint must survive a real JSON encode/decode roundtrip")
	var json_prediction_simulation := SimulationScript.new()
	assert(json_prediction_simulation.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	json_prediction_simulation.start()
	var json_prediction := LocalPredictionScript.new()
	json_prediction.bind(json_prediction_simulation, "local")
	assert(json_prediction.remember_input(1, 10, -1, 1234))
	var json_reconciliation: Dictionary = json_prediction.reconcile(wire_checkpoint, 12)
	assert(bool(json_reconciliation.get("ok", false)), "local prediction must reconcile against a JSON-decoded checkpoint: %s" % json_reconciliation.get("reason", "unknown"))
	assert(int(json_reconciliation.get("replayed_to_tick", -1)) == 12)
	assert(int(json_prediction_simulation.get_player("local").get("gravity_direction", 1)) == -1, "unconfirmed local input must replay after JSON restore")
	wire_checkpoint["placements"] = [{"user_id": "host", "display_name": "Host", "finish_tick": 7, "status": "finished"}]
	var wire_restore := SimulationScript.new()
	assert(wire_restore.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	wire_restore.start()
	assert(wire_restore.restore_checkpoint(wire_checkpoint), "JSON-decoded checkpoint arrays must restore without typed-array runtime errors: %s" % wire_restore.last_restore_error)
	assert(int(wire_restore.get_snapshot().get("tick", -1)) == int(checkpoint.tick))
	assert(wire_restore.get_snapshot().get("placements", []).size() == 1)
	var atomic_before_wire_reject: Dictionary = wire_restore.get_snapshot()
	var invalid_wire_player: Dictionary = wire_checkpoint.duplicate(true)
	invalid_wire_player.players[0]["world_x"] = "not-a-number"
	assert(not wire_restore.restore_checkpoint(invalid_wire_player), "wire checkpoints must reject values with the wrong JSON scalar type")
	assert(wire_restore.last_restore_error.begins_with("player_fields_wrong_type:"), "wrong player scalar types should have a specific restore reason")
	assert(wire_restore.get_snapshot() == atomic_before_wire_reject, "wrong-type checkpoint rejection must preserve the entire visible simulation checkpoint")
	var invalid_wire_checkpoint: Dictionary = wire_checkpoint.duplicate(true)
	invalid_wire_checkpoint["placements"] = ["not a placement dictionary"]
	assert(not wire_restore.restore_checkpoint(invalid_wire_checkpoint), "malformed JSON placement elements must be rejected")
	assert(wire_restore.last_restore_error == "placement_not_dictionary:0")
	assert(wire_restore.get_snapshot() == atomic_before_wire_reject, "failed JSON checkpoint restore must leave all simulation state untouched")
	var barrel_wire_manifest := _make_manifest([{
		"event_id": "wire_barrels",
		"kind": "barrels",
		"x": 900.0,
		"y": 460.0,
		"count": 2,
		"spacing": 52.0,
		"motion_speed_multiplier": 1.2,
	}], 10000)
	var barrel_wire_source := SimulationScript.new()
	assert(barrel_wire_source.configure(barrel_wire_manifest, [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	barrel_wire_source.start()
	barrel_wire_source.advance_to_tick(8)
	var barrel_wire_checkpoint: Dictionary = JSON.parse_string(JSON.stringify(barrel_wire_source.get_snapshot()))
	var barrel_wire_target := SimulationScript.new()
	assert(barrel_wire_target.configure(barrel_wire_manifest, [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	barrel_wire_target.start()
	assert(barrel_wire_target.restore_checkpoint(barrel_wire_checkpoint), "JSON-decoded barrel arrays must restore as typed candidates: %s" % barrel_wire_target.last_restore_error)
	assert(barrel_wire_target.get_snapshot().get("world_hazards", {}).get("barrels", []).size() == 2)
	var wire_hazards: Dictionary = JSON.parse_string(JSON.stringify(barrel_wire_source.get_snapshot().get("world_hazards", {})))
	assert(barrel_wire_target.apply_authoritative_world_hazards(wire_hazards), "standalone hazard updates must normalize JSON arrays before committing")
	var hazards_before_reject: Dictionary = barrel_wire_target.get_snapshot().get("world_hazards", {})
	var malformed_hazards: Dictionary = wire_hazards.duplicate(true)
	malformed_hazards["destroyed_event_ids"] = ["not_in_manifest"]
	assert(not barrel_wire_target.apply_authoritative_world_hazards(malformed_hazards), "unknown destroyed hazard IDs must be rejected")
	assert(barrel_wire_target.get_snapshot().get("world_hazards", {}) == hazards_before_reject, "a rejected hazard update must not partially change the live world")
	var terminal_simulation := SimulationScript.new()
	assert(terminal_simulation.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	terminal_simulation.start()
	terminal_simulation.advance_to_tick(1, 1)
	var terminal_state_at_event := terminal_simulation.get_player("local")
	terminal_state_at_event.state = "dead"
	terminal_state_at_event.terminal_tick = 1
	terminal_state_at_event.terminal_reason = "out_of_bounds"
	assert(terminal_simulation.apply_authoritative_player_state("local", terminal_state_at_event))
	terminal_simulation.advance_to_tick(2, 1)
	var terminal_packet: Dictionary = TerminalEventRules.build_payload("room", "generation", "sim-test", terminal_simulation.get_player("local"), int(terminal_simulation.get("tick")))
	assert(TerminalEventRules.validation_error(terminal_packet).is_empty(), "a real death on tick 1 must remain valid when queued at host tick 2")
	assert(int(terminal_packet.event_tick) == 1 and int(terminal_packet.sent_host_tick) == 2, "reliable terminal messages must keep transition tick separate from send tick")
	terminal_packet["terminal_tick"] = 2
	assert(TerminalEventRules.validation_error(terminal_packet) == "invalid_terminal_tick", "terminal payload tick mismatches must be rejected explicitly")
	assert(bool(replay_a.queue_flip("local", 1, -1, 10).get("queued", false)))
	assert(bool(replay_b.queue_flip("local", 1, -1, 10).get("queued", false)))
	replay_a.advance_to_tick(20)
	replay_b.advance_to_tick(20)
	assert(replay_a.get_snapshot() == replay_b.get_snapshot(), "restoring the same tick and replaying the same queued input must be deterministic")
	var guest_live := SimulationScript.new()
	assert(guest_live.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	guest_live.start()
	var prediction := LocalPredictionScript.new()
	prediction.bind(guest_live, "local")
	guest_live.advance_to_tick(12)
	assert(guest_live.submit_flip("local", -1), "the guest should apply a locally predicted flip immediately")
	assert(prediction.remember_input(1, 13, -1, 1234))
	var reconciled := prediction.reconcile(checkpoint, 12)
	assert(bool(reconciled.get("ok", false)) and int(reconciled.get("replayed_to_tick", -1)) == 12, "an older host snapshot must restore and replay only to the bounded current prediction tick")
	assert(int(guest_live.get_player("local").get("gravity_direction", 0)) == 1, "a future-targeted flip must not be replayed before its target tick")
	guest_live.advance_to_tick(13)
	assert(int(guest_live.get_player("local").get("gravity_direction", 0)) == -1, "a pending local flip should execute exactly at its scheduled prediction tick")
	var accepted_authority := SimulationScript.new()
	assert(accepted_authority.configure(_make_manifest([], 10000), [{"user_id": "local"}, {"user_id": "host"}]).is_empty())
	accepted_authority.start()
	assert(accepted_authority.restore_checkpoint(checkpoint))
	assert(bool(accepted_authority.queue_flip("local", 1, -1, 9).get("queued", false)))
	accepted_authority.advance_to_tick(9)
	var accepted_snapshot: Dictionary = accepted_authority.get_snapshot()
	var accepted_reconciliation := prediction.reconcile(accepted_snapshot, 12)
	assert(bool(accepted_reconciliation.get("ok", false)) and accepted_reconciliation.get("confirmed_inputs", []).size() == 1, "the host checkpoint should confirm a processed input without replaying it twice")
	assert(prediction.pending_inputs().is_empty() and int(guest_live.get_player("local").get("gravity_direction", 0)) == -1, "an acknowledged flip should be retired after its effect is present in authority state")
	var remote_before_replay := float(guest_live.get_player("host").get("world_x", -1.0))
	var local_replay_start := int(guest_live.get("tick"))
	guest_live.advance_to_tick(local_replay_start + 8, 8, ["local"])
	assert(is_equal_approx(float(guest_live.get_player("host").get("world_x", -2.0)), remote_before_replay), "guest prediction ticks must not simulate remote player movement")
	assert(float(guest_live.get_player("local").get("world_x", 0.0)) > 180.0, "guest prediction must continue simulating its local runner")
	var input_queue_sim := SimulationScript.new()
	assert(input_queue_sim.configure(_make_manifest([], 10000), [{"user_id": "queued"}]).is_empty())
	input_queue_sim.start()
	var queued_input: Dictionary = input_queue_sim.queue_flip("queued", 1, -1, 4)
	assert(bool(queued_input.get("queued", false)) and int(queued_input.get("target_tick", -1)) == 4)
	input_queue_sim.advance_to_tick(3)
	assert(input_queue_sim.get_snapshot().get("processed_inputs", {}).get("queued", []).is_empty(), "queued input must not be acknowledged before its scheduled tick")
	input_queue_sim.advance_to_tick(4)
	var accepted_results: Array = input_queue_sim.get_snapshot().get("processed_inputs", {}).get("queued", [])
	assert(accepted_results.size() == 1 and bool(accepted_results[0].get("accepted", false)) and int(accepted_results[0].get("processed_tick", -1)) == 4, "host snapshots must identify an accepted input and exact processing tick")
	assert(bool(input_queue_sim.queue_flip("queued", 2, 1, 5).get("queued", false)))
	input_queue_sim.advance_to_tick(5)
	var outcomes: Array = input_queue_sim.get_snapshot().get("processed_inputs", {}).get("queued", [])
	assert(outcomes.size() == 2 and not bool(outcomes[1].get("accepted", true)), "a rejected input must also be reported as processed so a client can retire it")
	var before_invalid_restore: Dictionary = replay_a.get_snapshot()
	var invalid_checkpoint := checkpoint.duplicate(true)
	invalid_checkpoint["world_time"] = NAN
	assert(not replay_a.restore_checkpoint(invalid_checkpoint), "invalid checkpoint data must be rejected")
	assert(int(replay_a.get_snapshot().get("tick", -1)) == int(before_invalid_restore.get("tick", -2)), "failed checkpoint validation must not partially mutate live state")
	var stall_simulation := SimulationScript.new()
	assert(stall_simulation.configure(_make_manifest([], 10000), [{"user_id": "stall"}]).is_empty())
	stall_simulation.start()
	stall_simulation.advance_frame(0.5)
	assert(int(stall_simulation.get("tick")) == SimulationScript.MAX_CATCHUP_TICKS, "a long frame must obey the bounded per-frame simulation budget")
	assert(float(stall_simulation.get_snapshot().get("backlog_seconds", 0.0)) > 0.25, "unprocessed stall time must remain visible as backlog instead of being silently discarded")
	for _frame in range(3):
		stall_simulation.advance_frame(0.0)
	assert(int(stall_simulation.get("tick")) == 30 and is_zero_approx(float(stall_simulation.get_snapshot().get("backlog_seconds", 1.0))), "bounded follow-up frames should drain the retained simulation backlog")
	for frame_rate in [60, 30, 10]:
		var cadence_simulation := SimulationScript.new()
		assert(cadence_simulation.configure(_make_manifest([], 10000), [{"user_id": "cadence"}]).is_empty())
		cadence_simulation.start()
		var frame_delta := 1.0 / float(frame_rate)
		for _frame in range(frame_rate * 5):
			cadence_simulation.advance_frame(frame_delta)
		assert(int(cadence_simulation.get("tick")) >= 299 and int(cadence_simulation.get("tick")) <= 300, "a bounded catch-up budget should preserve five seconds of simulation time at %d FPS" % frame_rate)
	var last_events: Array[Dictionary] = []
	for frame in range(1300):
		last_events = simulation.advance_frame(1.0 / 60.0)
		if simulation.match_finished:
			break
	assert(simulation.match_finished, "race should finish when the leading runner reaches the finish line")
	var result: Variant = last_events.back().get("result", {}) if not last_events.is_empty() else {}
	assert(result is Dictionary and str(result.get("winner_user_id", "")) == "fast", "the faster runner should win under host simulation")
	assert(int(simulation.get_player("slow").get("finish_tick", 0)) > int(simulation.get_player("fast").get("finish_tick", 0)))

	var step_manifest: Resource = _make_manifest([{
		"event_id": "floor_drop",
		"kind": "step",
		"x": 600.0,
		"start_y": 460.0,
		"end_y": 520.0,
		"from_ceiling": false,
		"spiked": false,
	}], 10000)
	var step_simulation := SimulationScript.new()
	assert(step_simulation.configure(step_manifest, [
		{"user_id": "runner_a"},
		{"user_id": "runner_b"},
	]).is_empty())
	step_simulation.start()
	for _frame in range(52):
		step_simulation.advance_frame(1.0 / 60.0)
	var falling_runner := step_simulation.get_player("runner_a")
	assert(float(falling_runner.get("world_x", 0.0)) >= 600.0)
	assert(float(falling_runner.get("y", 0.0)) < 498.0, "a descending floor step must begin a fall, not teleport the runner down")
	assert(not bool(falling_runner.get("grounded", true)))

	var spike_manifest: Resource = _make_manifest([{
		"event_id": "floor_spikes",
		"kind": "spikes",
		"x": 650.0,
		"start_x": 650.0,
		"y": 460.0,
		"count": 1,
		"spacing": 32.0,
		"width": 28.0,
		"from_ceiling": false,
	}], 10000)
	var spike_simulation := SimulationScript.new()
	assert(spike_simulation.configure(spike_manifest, [
		{"user_id": "runner_a"},
		{"user_id": "runner_b"},
	]).is_empty())
	spike_simulation.start()
	for _frame in range(90):
		spike_simulation.advance_frame(1.0 / 60.0)
	assert(spike_simulation.get_player("runner_a").get("state", "") == "dead", "floor spikes must be authoritative and lethal")
	assert(spike_simulation.get_player("runner_a").get("terminal_reason", "") == "hazard_hit" and int(spike_simulation.get_player("runner_a").get("terminal_tick", -1)) > 0, "hazard deaths must expose their cause and exact simulation tick")
	assert(spike_simulation.match_finished and spike_simulation.match_finish_reason == "elimination", "the last hazard elimination should produce an explicit elimination finish reason")
	assert(not spike_simulation.get_terminal_transitions().is_empty() and spike_simulation.get_terminal_transitions()[0].get("hazard_type", "") == "spikes", "the terminal trace must identify the hazard that caused death")
	var spiked_step_manifest: Resource = _make_manifest([{
		"event_id": "spiked_floor_step",
		"kind": "step",
		"x": 600.0,
		"start_y": 460.0,
		"end_y": 520.0,
		"from_ceiling": false,
		"spiked": true,
	}], 10000)
	var spiked_step_simulation := SimulationScript.new()
	assert(spiked_step_simulation.configure(spiked_step_manifest, [{"user_id": "step_runner"}]).is_empty())
	spiked_step_simulation.start()
	for _frame in range(90):
		spiked_step_simulation.advance_frame(1.0 / 60.0)
	assert(spiked_step_simulation.get_player("step_runner").get("state", "") == "dead", "spikes attached to step walls must kill in multiplayer")
	var block_manifest: Resource = _make_manifest([{
		"event_id": "floor_block",
		"kind": "block",
		"x": 600.0,
		"y": 460.0,
		"width": 48.0,
		"height": 72.0,
		"from_ceiling": false,
	}], 10000)
	var block_simulation := SimulationScript.new()
	assert(block_simulation.configure(block_manifest, [{"user_id": "block_runner"}]).is_empty())
	block_simulation.start()
	for _frame in range(90):
		block_simulation.advance_frame(1.0 / 60.0)
	assert(block_simulation.get_player("block_runner").get("state", "") == "dead", "a block must kill the player on contact instead of stopping them safely in front")
	var disconnect_simulation := SimulationScript.new()
	assert(disconnect_simulation.configure(_make_manifest([], 10000), [
		{"user_id": "host"},
		{"user_id": "departed"},
	]).is_empty())
	disconnect_simulation.start()
	assert(disconnect_simulation.mark_disconnected("departed"), "the host should be able to mark a disconnected runner")
	assert(disconnect_simulation.get_player("departed").get("state", "") == "disconnected")
	assert(disconnect_simulation.get_player("departed").get("terminal_reason", "") == "confirmed_disconnect" and int(disconnect_simulation.get_player("departed").get("terminal_tick", -1)) == 0, "disconnects must carry an explicit reason and authoritative transition tick")
	assert(not disconnect_simulation.mark_disconnected("unknown"), "unknown peers must not create match state")
	var survivor_simulation := SimulationScript.new()
	assert(survivor_simulation.configure(_make_manifest([], 10000), [
		{"user_id": "host"},
		{"user_id": "guest_a"},
		{"user_id": "guest_b"},
	]).is_empty())
	survivor_simulation.start()
	for user_id in ["host", "guest_a"]:
		var terminal_player: Dictionary = survivor_simulation.get_player(user_id)
		terminal_player.state = "dead"
		terminal_player.terminal_reason = "hazard_hit"
		terminal_player.terminal_tick = 0
		assert(survivor_simulation.apply_authoritative_player_state(user_id, terminal_player))
	for _tick in range(180):
		survivor_simulation.advance_frame(1.0 / 60.0)
	assert(not survivor_simulation.match_finished and survivor_simulation.get_player("guest_b").get("state", "") == "running", "two terminal players must not end the host simulation while a third is still running")
	var prediction_simulation := SimulationScript.new()
	assert(prediction_simulation.configure(_make_manifest([], 10000), [
		{"user_id": "local"},
		{"user_id": "host"},
	]).is_empty())
	var authority_state := prediction_simulation.get_player("local")
	authority_state["world_x"] = 420.0
	authority_state["y"] = 300.0
	authority_state["state"] = "running"
	assert(prediction_simulation.apply_authoritative_player_state("local", authority_state))
	assert(is_equal_approx(float(prediction_simulation.get_player("local").get("world_x", 0.0)), 420.0), "prediction state should reconcile to host authority")
	authority_state["world_x"] = NAN
	assert(not prediction_simulation.apply_authoritative_player_state("local", authority_state), "invalid network positions must be rejected")
	var barrel_block_manifest: Resource = _make_manifest([
		{"event_id": "target_block", "kind": "block", "x": 1000.0, "y": 460.0, "width": 48.0, "height": 72.0, "from_ceiling": false},
		{"event_id": "test_barrel", "kind": "barrels", "x": 1000.0, "y": 460.0, "width": 54.0, "height": 54.0, "count": 1, "spacing": 70.0, "motion_speed_multiplier": 1.4, "spawn_lead_distance": 100.0},
	], 10000)
	var barrel_block_simulation := SimulationScript.new()
	assert(barrel_block_simulation.configure(barrel_block_manifest, [{"user_id": "barrel_runner"}]).is_empty())
	var local_hazards: Dictionary = barrel_block_simulation.get_snapshot().get("world_hazards", {})
	assert(barrel_block_simulation.authoritative_world_hazard_error({"barrels": [], "destroyed_event_ids": []}) == "barrel_count_mismatch:0/1", "hazard roster mismatch should be diagnosed without obscuring player snapshot processing")
	assert(not barrel_block_simulation.apply_authoritative_world_hazards({"barrels": [], "destroyed_event_ids": []}), "invalid hazard data must not overwrite the valid local hazard simulation")
	assert(barrel_block_simulation.get_snapshot().get("world_hazards", {}) == local_hazards, "rejecting hazard data must preserve the local hazard roster")
	barrel_block_simulation.start()
	for _frame in range(200):
		barrel_block_simulation.advance_frame(1.0 / 60.0)
	var barrel_block_world: Dictionary = barrel_block_simulation.get_snapshot().get("world_hazards", {})
	assert(barrel_block_world.get("destroyed_event_ids", []).has("target_block"), "a rolling barrel should destroy a breakable block in the shared course")
	assert(bool(barrel_block_world.get("barrels", [])[0].get("destroyed", false)), "a barrel should be consumed when it breaks a block")
	var barrel_spike_manifest: Resource = _make_manifest([
		{"event_id": "target_spikes", "kind": "spikes", "x": 1000.0, "start_x": 1000.0, "y": 460.0, "width": 28.0, "count": 1, "spacing": 32.0, "from_ceiling": false},
		{"event_id": "test_barrel", "kind": "barrels", "x": 1000.0, "y": 460.0, "width": 54.0, "height": 54.0, "count": 1, "spacing": 70.0, "motion_speed_multiplier": 1.4, "spawn_lead_distance": 100.0},
	], 10000)
	var barrel_spike_simulation := SimulationScript.new()
	assert(barrel_spike_simulation.configure(barrel_spike_manifest, [{"user_id": "spike_runner"}]).is_empty())
	barrel_spike_simulation.start()
	for _frame in range(120):
		barrel_spike_simulation.advance_frame(1.0 / 60.0)
	var barrel_spike_world: Dictionary = barrel_spike_simulation.get_snapshot().get("world_hazards", {})
	assert(bool(barrel_spike_world.get("barrels", [])[0].get("destroyed", false)), "spikes should destroy a rolling barrel")
	print("Multiplayer simulation tests passed.")
	quit()

func _make_manifest(events: Array[Dictionary], length_px: int) -> Resource:
	var manifest: Resource = ManifestScript.new()
	manifest.set("generator_version", 4)
	manifest.set("course_identity", "sim-test")
	manifest.set("seed_value", 24680)
	manifest.set("course_length_px", length_px)
	manifest.set("start_x", 180.0)
	manifest.set("finish_x", 180.0 + float(length_px))
	manifest.set("initial_floor_y", 460.0)
	manifest.set("initial_ceiling_y", 80.0)
	manifest.set("events", events)
	manifest.set("manifest_hash", manifest.call("calculate_hash"))
	return manifest
