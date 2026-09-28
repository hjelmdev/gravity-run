extends Node

const MatchScript := preload("res://ui/multiplayer_match.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const SimulationScript := preload("res://systems/multiplayer_simulation.gd")
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
	assert(MatchScript.may_show_results(true, {"finished": false}), "the host remains authoritative for its own results")
	assert(is_equal_approx(MatchScript.estimate_shared_start_msec(1000, 5.0, [400, 600]), 6250.0), "host start should compensate for measured peer delivery latency")
	assert(is_equal_approx(MatchScript.estimate_guest_clock_offset_ms(5200, 5000, 5400), 0.0), "clock-offset estimation should use the probe round-trip midpoint")
	assert(is_equal_approx(MatchScript.estimate_guest_clock_offset_ms(15200, 10000, 10400), 5000.0), "clock-offset estimation should translate a guest clock into host time")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 0.0, 5.0, -1.0), 95.0), "snapshot rendering should start behind the newest host tick")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 1.0, 5.0, 95.0), 103.0), "snapshot extrapolation must be capped to three ticks")
	assert(is_equal_approx(MatchScript.render_target_tick(100.0, 0.0, 5.0, 96.0), 96.0), "the render timeline must never move backwards")
	assert(MatchScript.correction_after_authority(Vector2(102.0, 202.0), Vector2(100.0, 200.0)).is_equal_approx(Vector2(2.0, 2.0)), "small local prediction errors should fade smoothly")
	assert(MatchScript.correction_after_authority(Vector2(300.0, 200.0), Vector2(100.0, 200.0)) == Vector2.ZERO, "large prediction errors should snap to authority")
	assert(MatchScript.correction_after_authority(Vector2(102.0, 202.0), Vector2(100.0, 200.0), "running", "dead") == Vector2.ZERO, "terminal state transitions must not be visually delayed")
	var faded_correction: Vector2 = MatchScript.fade_render_correction(Vector2(50.0, 30.0), 0.1, 420.0)
	assert(faded_correction.length() < Vector2(50.0, 30.0).length() and faded_correction.length() > 0.0, "replayed local prediction should smoothly fade its render-continuity correction")
	var rollback_manifest: Resource = ManifestScript.new()
	rollback_manifest.set("generator_version", 4)
	rollback_manifest.set("course_identity", "presentation-rollback-test")
	rollback_manifest.set("seed_value", 24680)
	rollback_manifest.set("course_length_px", 10000)
	rollback_manifest.set("start_x", 180.0)
	rollback_manifest.set("finish_x", 10180.0)
	rollback_manifest.set("initial_floor_y", 460.0)
	rollback_manifest.set("initial_ceiling_y", 80.0)
	rollback_manifest.set("manifest_hash", rollback_manifest.call("calculate_hash"))
	var authoritative_simulation := SimulationScript.new()
	assert(authoritative_simulation.configure(rollback_manifest, [{"user_id": "local"}, {"user_id": "remote"}]).is_empty())
	authoritative_simulation.start()
	for _tick in range(10):
		authoritative_simulation.advance_frame(1.0 / 60.0, false)
	var authority_snapshot: Dictionary = authoritative_simulation.get_snapshot()
	var client_simulation := SimulationScript.new()
	assert(client_simulation.configure(rollback_manifest, [{"user_id": "local"}, {"user_id": "remote"}]).is_empty())
	client_simulation.start()
	for _tick in range(11):
		client_simulation.advance_frame(1.0 / 60.0, false)
	assert(client_simulation.submit_flip("local", -1))
	for _tick in range(4):
		client_simulation.advance_frame(1.0 / 60.0, false)
	var expected_client_state: Dictionary = client_simulation.get_player("local")
	for authoritative_player in authority_snapshot.players:
		assert(client_simulation.apply_authoritative_player_state(str(authoritative_player.user_id), authoritative_player))
	assert(client_simulation.apply_authoritative_world_hazards(authority_snapshot.world_hazards))
	assert(client_simulation.restore_authoritative_frame(int(authority_snapshot.tick), authority_snapshot.placements, false))
	var replay_view: Node2D = MatchScript.new()
	replay_view.set("_simulation", client_simulation)
	replay_view.set("_local_user_id", "local")
	replay_view.set("_authoritative_snapshot", authority_snapshot)
	var pending_replay_inputs: Array[Dictionary] = [{"sequence": 1, "client_tick": 11, "gravity_direction": -1}]
	replay_view.set("_pending_local_inputs", pending_replay_inputs)
	replay_view.call("_replay_local_prediction", 10, 15)
	var replayed_client_state: Dictionary = client_simulation.get_player("local")
	assert(int(client_simulation.get_snapshot().tick) == 15, "client rollback should replay to the previous predicted tick")
	assert(is_equal_approx(float(replayed_client_state.world_x), float(expected_client_state.world_x)) and is_equal_approx(float(replayed_client_state.y), float(expected_client_state.y)) and int(replayed_client_state.gravity_direction) == int(expected_client_state.gravity_direction), "client rollback should replay unacknowledged flips to preserve the local trajectory")
	replay_view.free()
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
	match_view.set("_authoritative_snapshot", {"finished": true})
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
	tie_view.set("_authoritative_snapshot", {"finished": true})
	tie_view.call("_show_results")
	assert((tie_view.get("_result_label") as Label).text == tr("No winner"), "an exact distance tie after elimination must not arbitrarily name a winner")
	var tie_rows: VBoxContainer = tie_view.get("_results_list")
	assert((tie_rows.get_child(0).get_child(1) as Label).text == "#1" and (tie_rows.get_child(1).get_child(1) as Label).text == "#1", "players eliminated at the same distance should share a place")
	assert(not (tie_view.get("_status_label") as Label).visible, "the in-game status text should not remain behind the results modal")
	tie_view.set("_return_requester_name", "Guest")
	tie_view.call("_update_return_request_notice")
	assert((tie_view.get("_return_request_notice") as Label).visible and (tie_view.get("_return_request_notice") as Label).text.contains("Guest"), "a guest return request should be readable inside the results panel")
	tie_view.free()
	print("Multiplayer match presentation tests passed.")
	get_tree().quit()
