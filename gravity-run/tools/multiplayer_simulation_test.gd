extends SceneTree

const BuilderScript := preload("res://systems/course_manifest_builder.gd")
const RaceRulesScript := preload("res://systems/multiplayer_race_rules.gd")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

func _initialize() -> void:
	assert(not HazardRules.spike_group_intersects_rect(1000.0, 460.0, 1, 32.0, 28.0, 32.0, false, Rect2(Vector2(986.0, 428.0), Vector2(2.0, 2.0))), "the triangular spike tip must not collide like its old bounding box")
	assert(HazardRules.spike_group_intersects_rect(1000.0, 460.0, 1, 32.0, 28.0, 32.0, false, Rect2(Vector2(999.0, 427.0), Vector2(2.0, 3.0))), "the actual triangular spike tip must collide in shared geometry")
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
	var solo_simulation := SimulationScript.new()
	assert(solo_simulation.configure(manifest, [{"user_id": "solo", "display_name": "Solo"}]).is_empty())
	solo_simulation.start()
	for _frame in range(1300):
		solo_simulation.advance_frame(1.0 / 60.0)
		if solo_simulation.match_finished:
			break
	assert(solo_simulation.match_finished, "a solo host race should run to completion")
	var configuration_error := simulation.configure(manifest, [
		{"user_id": "slow", "display_name": "Slow", "run_speed_percent": 10000},
		{"user_id": "fast", "display_name": "Fast", "run_speed_percent": 10100, "skin_id": 3},
	])
	assert(configuration_error.is_empty(), configuration_error)
	assert(int(simulation.get_player("fast").get("skin_id", -1)) == 3, "player skin selection should be included in authoritative simulation state")
	simulation.start()
	assert(simulation.submit_flip("slow", -1))
	assert(not simulation.submit_flip("slow", 1))
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
	assert(not disconnect_simulation.mark_disconnected("unknown"), "unknown peers must not create match state")
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
