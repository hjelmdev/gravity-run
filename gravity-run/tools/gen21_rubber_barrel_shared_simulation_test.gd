extends SceneTree
## Generated Gen21 rubber encounter through the canonical shared world model.

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const Generator := preload("res://systems/course_generator.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const RockModel := preload("res://systems/falling_rock_model.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")

var failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var manifest: Resource
	var rubber_event: Dictionary = {}
	var selected_seed := -1
	for seed_value in range(100000001, 100000081):
		var result: Dictionary = Builder.new().build(seed_value, 45000, Generator.GENERATOR_VERSION_21)
		var candidate: Variant = result.get("manifest")
		if candidate == null:
			continue
		for event in candidate.events:
			if str(event.get("kind", "")) == "barrels" and int(event.get("barrel_variant", 0)) == 1:
				manifest = candidate
				rubber_event = event
				selected_seed = seed_value
				break
		if manifest != null:
			break
	_check(manifest != null, "bounded seed search finds a generated Gen21 rubber encounter")
	if manifest == null:
		_finish()
		return
	if selected_seed == 100000007:
		for event in manifest.events:
			if float(event.get("x", -INF)) >= 2100.0 and float(event.get("x", INF)) <= 3400.0 and str(event.get("kind", "")) in ["block", "ghost", "rock", "saw", "spikes", "gap"]:
				print("GEN21_ROUTE_EVENT id=%s kind=%s x=%.1f ceiling=%s variant=%d" % [str(event.get("event_id", "")), str(event.get("kind", "")), float(event.get("x", 0.0)), str(bool(event.get("from_ceiling", false))), int(event.get("ghost_variant", 0))])
	_check(str(manifest.call("validate")).is_empty(), "generated rubber target passes strict manifest validation")
	_check(int(rubber_event.get("count", 0)) == 1 and not bool(rubber_event.get("spiked", false)), "rubber encounter is one unspiked barrel")
	var target_x := float(rubber_event.get("rubber_target_x", NAN))
	var target_found := false
	var target_event: Dictionary = {}
	for event in manifest.events:
		if str(event.get("kind", "")) == "block" and absf(float(event.get("x", INF)) - target_x) <= 0.1:
			target_found = true
			target_event = event
			break
	_check(target_found and is_finite(target_x), "rubber metadata identifies its actual source block")
	if target_found:
		_verify_spent_barrel_persistence(manifest, rubber_event, target_event)
		_verify_non_target_block_contacts(manifest, rubber_event, target_event)
		_verify_mixed_barrel_late_join_baseline(manifest, rubber_event)
	var route_results: Array[Dictionary] = []
	for speed in [250.0, 500.0, 750.0]:
		var route_result := _simulate_visible_runner_route_with_schedule(manifest, rubber_event, float(speed), -1, -1)
		if speed >= 750.0 and target_x <= 12000.0 and not bool(route_result.get("passed", false)):
			route_result = _search_safe_runner_schedule(manifest, rubber_event, float(speed), route_result)
		route_results.append(route_result)
		if speed <= 500.0:
			_check(bool(route_result.get("passed", false)), "real RunnerMotion safely passes the complete activated target corridor at %.0f px/s after a 12-tick reaction" % speed)
			_check(bool(route_result.get("safe_opposite_at_bounce", false)), "opposite supported lane is clear at the actual bounce tick at %.0f px/s" % speed)
		if bool(route_result.get("barrel_encounter_visible", false)) and int(route_result.get("bounce_tick", -1)) >= 0:
			_check(int(route_result.get("bounce_reaction_ticks", -1)) >= 0, "visible barrel leaves a reaction margin before bounce at %.0f px/s" % speed)
		print("GEN21_RUBBER_ROUTE speed=%.0f threat_visible=%d barrel_visible=%d encounter=%d bounce=%d bounce_margin_ticks=%d bounce_margin_seconds=%.3f encounter_margin_ticks=%d closest_gap=%.1f terminal=%s opposite_safe=%s searched=%s schedules=%d passed=%s" % [speed, int(route_result.get("visible_tick", -1)), int(route_result.get("barrel_visible_tick", -1)), int(route_result.get("encounter_tick", -1)), int(route_result.get("bounce_tick", -1)), int(route_result.get("bounce_reaction_ticks", -1)), float(route_result.get("bounce_reaction_ticks", -1)) / 60.0, int(route_result.get("reaction_margin_ticks", -1)), float(route_result.get("closest_gap", INF)), str(route_result.get("terminal_event", "")), str(bool(route_result.get("safe_opposite_at_bounce", false))), str(bool(route_result.get("schedule_searched", false))), int(route_result.get("schedules_tested", 0)), str(bool(route_result.get("passed", false)))])
	if selected_seed == 100000007:
		var legacy_result: Dictionary = Builder.new().build(selected_seed, 45000, 20)
		var legacy_manifest: Variant = legacy_result.get("manifest")
		var legacy_target: Dictionary = {}
		if legacy_manifest != null:
			for event in legacy_manifest.events:
				if str(event.get("kind", "")) == "block" and absf(float(event.get("x", INF)) - target_x) <= 0.1:
					legacy_target = {"event_id": str(event.get("event_id", "")), "rubber_target_x": target_x}
					break
		if legacy_manifest != null and not legacy_target.is_empty():
			var legacy_route := _simulate_visible_runner_route_with_schedule(legacy_manifest, legacy_target, 750.0, -1, -1)
			print("GEN20_MATCHED_ROUTE seed=%d target_x=%.1f speed=750 terminal=%s passed=%s" % [selected_seed, target_x, str(legacy_route.get("terminal_event", "")), str(bool(legacy_route.get("passed", false)))])
			_check(str(route_results[2].get("terminal_event", "")).begins_with("falling_rock:") and str(legacy_route.get("terminal_event", "")).begins_with("falling_rock:"), "750px/s rock-corridor route limitation is also present in matched Gen20 baseline")
		else:
			_check(false, "Gen20 comparison manifest contains the matched base block for the rubber route")
		_find_safe_all_speed_rubber_seed(100000008, 100000040)

	var host := World.new()
	var guest := World.new()
	_check(str(host.configure(manifest)).is_empty() and str(guest.configure(manifest)).is_empty(), "host and guest configure the same canonical generated manifest")
	var barrel: Dictionary = {}
	for state in host.barrels:
		if str(state.get("event_id", "")) == str(rubber_event.get("event_id", "")):
			barrel = state
			break
	_check(not barrel.is_empty() and bool(barrel.get("rubber", false)), "shared world instantiates the explicit rubber variant")
	if barrel.is_empty():
		_finish()
		return
	var spawn_x := float(rubber_event.x) + float(rubber_event.get("spawn_lead_distance", 820.0)) * (float(rubber_event.get("motion_speed_multiplier", 1.0)) - 1.0)
	var player_at_spawn := float(rubber_event.x) - float(rubber_event.get("spawn_lead_distance", 820.0))
	_check(is_equal_approx(float(barrel.x), spawn_x) and is_equal_approx(float(manifest.start_x) + float(barrel.spawn_time) * Motion.BASE_RUN_SPEED, player_at_spawn), "canonical barrel pose and spawn tick agree with the authored lead")
	var last_tick := mini(6000, ceili(float(barrel.spawn_time) * 60.0) + 360)
	var bounce_tick := -1
	for next_tick in range(1, last_tick + 1):
		host.step_to(next_tick)
		guest.step_to(next_tick)
		var host_barrel := _barrel_for_event(host, str(rubber_event.event_id))
		var guest_barrel := _barrel_for_event(guest, str(rubber_event.event_id))
		_check(is_equal_approx(float(host_barrel.get("x", NAN)), float(guest_barrel.get("x", NAN))) and int(host_barrel.get("bounce_count", -1)) == int(guest_barrel.get("bounce_count", -2)), "host and guest rubber simulation remains tick-identical")
		if int(host_barrel.get("bounce_count", 0)) > 0:
			bounce_tick = next_tick
			barrel = host_barrel
			break
	_check(bounce_tick > 0, "generated rubber barrel reaches a block or solid step and bounces within bounded simulation")
	if bounce_tick > 0:
		_check(int(barrel.get("travel_direction", 1)) == -1 and not bool(barrel.get("destroyed", true)), "first target impact reverses the barrel without consuming it")
		var target_id := ""
		for event in manifest.events:
			if str(event.get("kind", "")) == "block" and absf(float(event.get("x", INF)) - target_x) <= 0.1:
				target_id = str(event.get("event_id", ""))
				break
		_check(not target_id.is_empty() and host.entity_ledger.is_active(target_id), "the designated block remains active after rubber contact")
		var expected_contact_x := target_x + float(target_event.get("width", 48.0)) * 0.5 + HazardRules.barrel_radius(float(barrel.width), float(barrel.height)) + 1.0
		_check(absf(float(barrel.x) - expected_contact_x) <= 0.5, "the first generated rubber bounce is against its designated block")
		var radius := HazardRules.barrel_radius(float(barrel.width), float(barrel.height))
		var screen_distance := absf(float(barrel.x) - (float(manifest.start_x) + Motion.BASE_RUN_SPEED * float(bounce_tick) / 60.0))
		_check(screen_distance < 960.0, "the bounced barrel remains within one gameplay viewport of the runner")
		var baseline := host.baseline()
		_check(int(baseline.get("baseline_format_version", -1)) == 5, "Gen21 bounce state uses its versioned baseline format")
		_check(guest.apply_baseline(baseline), "a guest can restore the authoritative post-bounce baseline")
		var restored := _barrel_for_event(guest, str(rubber_event.event_id))
		_check(int(restored.get("bounce_count", 0)) == 1 and int(restored.get("travel_direction", 0)) == -1 and is_equal_approx(float(restored.get("x", NAN)), float(barrel.x)), "baseline restores the exact active bounce pose")
		var ceiling := float(host.surface_at(float(barrel.x), true).get("y", 80.0))
		var safe_contact := host.player_contact_at({"world_x": float(barrel.x), "y": ceiling + Motion.SIZE.y * 0.5, "gravity_direction": -1, "grounded": true}, bounce_tick)
		_check(str(safe_contact.get("kind", "")) != "terminal", "the opposite supported lane remains a safe route at the bounce phase")
	print("GEN21_RUBBER_BARREL_SHARED_SIMULATION seed=%d source=%s target_x=%.1f bounce_x=%.1f spawn_tick=%d bounce_tick=%d viewport_gap=%.1f failures=%d" % [selected_seed, str(rubber_event.get("event_id", "")), target_x, float(barrel.get("x", NAN)), ceili(float(barrel.spawn_time) * 60.0), bounce_tick, absf(float(barrel.get("x", 0.0)) - (float(manifest.start_x) + Motion.BASE_RUN_SPEED * float(bounce_tick) / 60.0)), failures])
	_finish()

func _barrel_for_event(world: RefCounted, event_id: String) -> Dictionary:
	for value in world.get("barrels"):
		if str(value.get("event_id", "")) == event_id:
			return value
	return {}

func _verify_non_target_block_contacts(course_manifest: Resource, rubber_event: Dictionary, target_event: Dictionary) -> void:
	var target_x := float(rubber_event.get("rubber_target_x", NAN))
	var event_id := str(rubber_event.get("event_id", ""))
	var floor_y := float(course_manifest.get("initial_floor_y"))
	for offset in [-400.0, 400.0]:
		var world := World.new()
		var test_manifest: Resource = Builder.new().build(int(course_manifest.get("seed_value")), 45000, Generator.GENERATOR_VERSION_21).get("manifest")
		_check(str(world.configure(test_manifest)).is_empty(), "MP extra-block contact world configures")
		var extra_x := target_x + float(offset)
		var extra_id := "test_extra_block_%.0f" % extra_x
		var extra_block := {"event_id": extra_id, "kind": "block", "x": extra_x, "y": floor_y, "width": 48.0, "height": 72.0, "from_ceiling": false}
		var test_events: Array[Dictionary] = [target_event.duplicate(true), extra_block]
		world.manifest.events = test_events
		world.entity_ledger.entities[extra_id] = {"incarnation": 1, "kind": "block", "state": "active", "state_revision": 0, "shared_health": 1}
		var barrel := _barrel_for_event(world, event_id)
		var radius := HazardRules.barrel_radius(float(barrel.get("width", 0.0)), float(barrel.get("height", 0.0)))
		barrel["spawned"] = true
		barrel["x"] = extra_x + 24.0 + radius - 1.0
		barrel["y"] = floor_y
		barrel["travel_direction"] = 1
		barrel["bounce_count"] = 0
		barrel["retired"] = false
		world.call("_resolve_barrel_interactions", barrel)
		_check(int(barrel.get("bounce_count", 0)) == 1 and int(barrel.get("travel_direction", 0)) == -1, "MP rubber barrel bounces from non-target block at offset %.0f" % offset)
		_check(is_equal_approx(float(barrel.get("x", NAN)), extra_x + 24.0 + radius + 1.0), "MP non-target block supplies the actual bounce face at offset %.0f" % offset)
		_check(world.entity_ledger.is_active(extra_id) and world.entity_ledger.is_active(str(target_event.get("event_id", ""))), "MP rubber contact preserves both non-target and designated blocks")
	var world := World.new()
	var overlap_manifest: Resource = Builder.new().build(int(course_manifest.get("seed_value")), 45000, Generator.GENERATOR_VERSION_21).get("manifest")
	_check(str(world.configure(overlap_manifest)).is_empty(), "MP overlapping step/block priority world configures")
	var overlap_x := target_x + 800.0
	var block_id := "test_overlap_block"
	var step_id := "test_overlap_step"
	var block_event := {"event_id": block_id, "kind": "block", "x": overlap_x, "y": floor_y, "width": 48.0, "height": 72.0, "from_ceiling": false}
	var step_event := {"event_id": step_id, "kind": "step", "x": overlap_x, "start_y": floor_y - 84.0, "end_y": floor_y, "from_ceiling": false}
	var overlap_events: Array[Dictionary] = [step_event, block_event]
	world.manifest.events = overlap_events
	world.entity_ledger.entities[block_id] = {"incarnation": 1, "kind": "block", "state": "active", "state_revision": 0, "shared_health": 1}
	world.entity_ledger.entities[step_id] = {"incarnation": 1, "kind": "step", "state": "active", "state_revision": 0, "shared_health": 1}
	var overlap_barrel := _barrel_for_event(world, event_id)
	var overlap_radius := HazardRules.barrel_radius(float(overlap_barrel.get("width", 0.0)), float(overlap_barrel.get("height", 0.0)))
	overlap_barrel["spawned"] = true
	overlap_barrel["x"] = overlap_x + 33.0
	overlap_barrel["y"] = floor_y
	overlap_barrel["travel_direction"] = 1
	overlap_barrel["bounce_count"] = 0
	overlap_barrel["retired"] = false
	world.call("_resolve_barrel_interactions", overlap_barrel)
	_check(int(overlap_barrel.get("bounce_count", 0)) == 1 and is_equal_approx(float(overlap_barrel.get("x", NAN)), overlap_x + 24.0 + overlap_radius + 1.0), "MP simultaneous step/block contact deterministically prioritizes the block face")
	_check(world.entity_ledger.is_active(block_id) and world.entity_ledger.is_active(step_id), "MP rubber block-priority bounce preserves both overlapping solids")

func _verify_spent_barrel_persistence(course_manifest: Resource, rubber_event: Dictionary, target_event: Dictionary) -> void:
	var spent_world := World.new()
	var guest_world := World.new()
	_check(str(spent_world.configure(course_manifest)).is_empty() and str(guest_world.configure(course_manifest)).is_empty(), "spent-state persistence worlds configure the same manifest")
	var event_id := str(rubber_event.get("event_id", ""))
	var state := _barrel_for_event(spent_world, event_id)
	if state.is_empty():
		_check(false, "spent-state fixture finds its canonical rubber barrel")
		return
	var block_width := float(target_event.get("width", 48.0))
	var block_height := float(target_event.get("height", 72.0))
	var edge_y := float(target_event.get("y", course_manifest.initial_floor_y))
	var block_rect := Rect2(Vector2(float(target_event.x) - block_width * 0.5, edge_y - block_height), Vector2(block_width, block_height))
	var radius := HazardRules.barrel_radius(float(state.width), float(state.height))
	state["spawned"] = true
	state["bounce_count"] = HazardRules.RUBBER_BARREL_MAX_BOUNCES
	state["travel_direction"] = 1
	state["x"] = block_rect.end.x + radius - 0.5
	state["y"] = edge_y
	spent_world.call("_resolve_barrel_interactions", state)
	var parked_x := block_rect.end.x + radius + 1.0
	_check(bool(state.get("retired", false)) and not bool(state.get("destroyed", false)) and is_equal_approx(float(state.x), parked_x), "bounce-limit contact parks the barrel visibly at the block face instead of destroying it")
	_check(spent_world.entity_ledger.is_active(str(target_event.event_id)), "the contacted block remains active when the rubber barrel parks")
	_check(not HazardRules.circle_intersects_rect(HazardRules.barrel_center(Vector2(float(state.x), float(state.y)), float(state.width), float(state.height)), radius, block_rect), "parked rubber barrel is not hidden inside its block")
	var player_y := edge_y - Motion.SIZE.y * 0.5
	var contact := spent_world.player_contact({"world_x": parked_x, "y": player_y, "gravity_direction": 1, "grounded": true})
	_check(str(contact.get("kind", "")) == "shared_interaction" and str(contact.get("reason", "")) == "barrel_contact", "parked barrel stays lethal to the player")
	var baseline := spent_world.baseline()
	_check(guest_world.apply_baseline(baseline), "Gen21 baseline restores the spent barrel state")
	var restored := _barrel_for_event(guest_world, event_id)
	_check(bool(restored.get("retired", false)) and is_equal_approx(float(restored.get("x", NAN)), parked_x) and guest_world.entity_ledger.is_active(str(target_event.event_id)), "restored spent barrel remains parked and both entities remain active")
	spent_world.step_to(1)
	guest_world.step_to(1)
	state = _barrel_for_event(spent_world, event_id)
	_check(is_equal_approx(float(state.get("x", NAN)), parked_x) and int(state.get("bounce_count", -1)) == HazardRules.RUBBER_BARREL_MAX_BOUNCES, "parked barrel cannot enter an endless obstacle-bounce loop")
	var barrel_scene := load("res://hazards/barrel.tscn") as PackedScene
	var barrel_node := barrel_scene.instantiate() as Node2D
	barrel_node.call("configure", Vector2(float(state.width), float(state.height)), false)
	barrel_node.call("set_rubber_variant", true, float(rubber_event.get("rubber_target_x", -1.0)))
	barrel_node.position = Vector2(float(state.x), float(state.y))
	barrel_node.call("apply_shared_barrel_state", state)
	var player_rect := Rect2(Vector2(parked_x - Motion.SIZE.x * 0.5, player_y - Motion.SIZE.y * 0.5), Motion.SIZE)
	_check(barrel_node.visible and bool(barrel_node.call("intersects_rect", player_rect)), "SP/MP barrel presentation keeps the spent hazard visible and aligned with its collision")
	barrel_node.free()

func _verify_mixed_barrel_late_join_baseline(course_manifest: Resource, rubber_event: Dictionary) -> void:
	var host := World.new()
	var late_guest := World.new()
	_check(str(host.configure(course_manifest)).is_empty() and str(late_guest.configure(course_manifest)).is_empty(), "mixed ordinary/rubber late-join worlds configure the same manifest")
	var rubber_id := str(rubber_event.get("event_id", "")) + "_0"
	var ordinary_id := ""
	var ordinary_state: Dictionary = {}
	var rubber_state: Dictionary = {}
	var configured_barrel_x: Dictionary = {}
	for state in host.barrels:
		configured_barrel_x[str(state.get("entity_id", ""))] = float(state.get("x", 0.0))
	var host_tick := -1
	for next_tick in range(1, 6001):
		if not host.step_to(next_tick):
			break
		rubber_state = _barrel_for_event(host, str(rubber_event.get("event_id", "")))
		for state in host.barrels:
			if not bool(state.get("rubber", false)) and not bool(state.get("spiked", false)) and bool(state.get("spawned", false)) and not bool(state.get("destroyed", false)) and absf(float(state.get("x", 0.0)) - float(configured_barrel_x.get(str(state.get("entity_id", "")), state.get("x", 0.0)))) >= 1.0:
				# The state has advanced in the actual shared simulation. Keep the
				# first such ordinary barrel concurrent with the live rubber encounter.
				if bool(rubber_state.get("spawned", false)) and int(rubber_state.get("bounce_count", 0)) > 0 and not bool(rubber_state.get("destroyed", false)):
					ordinary_id = str(state.get("entity_id", ""))
					ordinary_state = state
					host_tick = next_tick
					break
		if host_tick >= 0:
			break
	_check(host_tick > 0 and not ordinary_id.is_empty() and not rubber_state.is_empty(), "actual shared simulation reaches a moving ordinary barrel concurrently with a bounced rubber barrel")
	if host_tick < 0:
		return
	var initial_ordinary_x := float(configured_barrel_x.get(ordinary_id, NAN))
	var ordinary_moved := absf(float(ordinary_state.get("x", initial_ordinary_x)) - initial_ordinary_x) >= 1.0
	_check(bool(ordinary_state.get("spawned", false)) and ordinary_moved, "ordinary barrel is spawned and moving at the authoritative host tick")
	var active_saw_id := ""
	for saw in host.saws:
		var candidate_saw_id := str(saw.get("event_id", ""))
		var activation_tick := maxi(host_tick - 20, 0)
		var commit := {"world_revision": host.entity_ledger.revision + 1, "commit_id": "late-baseline-saw-%s" % candidate_saw_id, "entity_id": candidate_saw_id, "incarnation": 1, "action": "activate_saw", "effective_tick": activation_tick, "saw_activation_tick": activation_tick, "state_before": "active", "state_after": "active"}
		if host.apply_world_commit(commit) != "applied":
			continue
		var candidate_state: Dictionary = host._saw_state_for_event(candidate_saw_id, host_tick)
		if not bool(candidate_state.get("active", false)):
			continue
		var candidate_center := Vector2(float(candidate_state.get("x", 0.0)), float(candidate_state.get("y", 0.0)))
		var candidate_contact: Dictionary = host.player_contact_at({"world_x": candidate_center.x, "y": candidate_center.y, "gravity_direction": 1, "grounded": false}, host_tick)
		if str(candidate_contact.get("reason", "")) == "saw_blade":
			active_saw_id = candidate_saw_id
			break
	_check(not active_saw_id.is_empty(), "host tick has an activated saw pose usable for a late-join historical contact check")
	var late_baseline: Dictionary = host.baseline()
	var barrel_rows: Array = late_baseline.get("barrels", [])
	var row_by_id: Dictionary = {}
	for row_value in barrel_rows:
		if row_value is Dictionary:
			var row: Dictionary = row_value
			row_by_id[str(row.get("id", ""))] = row
	_check(int(late_baseline.get("baseline_format_version", -1)) == 5 and barrel_rows.size() == host.barrels.size() and row_by_id.size() == barrel_rows.size() and row_by_id.has(rubber_id) and row_by_id.has(ordinary_id), "mixed late-join baseline5 carries every dynamic barrel pose exactly once")
	_check(late_guest.apply_baseline(late_baseline), "late guest accepts the mixed ordinary/rubber baseline5")
	if not active_saw_id.is_empty():
		_check(late_guest.tick == host_tick and late_guest._saw_history.has(host_tick) and late_guest._barrel_history.has(host_tick), "baseline5 reconstructs saw and barrel history at the same host tick")
		var restored_saw: Dictionary = late_guest._saw_state_for_event(active_saw_id, host_tick)
		var restored_center := Vector2(float(restored_saw.get("x", 0.0)), float(restored_saw.get("y", 0.0)))
		var restored_contact: Dictionary = late_guest.player_contact_at({"world_x": restored_center.x, "y": restored_center.y, "gravity_direction": 1, "grounded": false}, host_tick)
		_check(str(restored_contact.get("reason", "")) == "saw_blade", "late-join historical player_contact_at resolves the active saw at the baseline tick")
	var restored_rubber := _barrel_for_entity(late_guest, rubber_id)
	var restored_ordinary := _barrel_for_entity(late_guest, ordinary_id)
	for source_state in host.barrels:
		var restored_state := _barrel_for_entity(late_guest, str(source_state.get("entity_id", "")))
		for key in ["x", "y", "fall_velocity", "spawned", "falling", "roll_angle", "rotation", "travel_direction", "bounce_count", "bounce_ticks", "retired", "destroyed"]:
			_check(is_equal_approx(float(restored_state.get(key, 0.0)), float(source_state.get(key, 0.0))) if key in ["x", "y", "fall_velocity", "roll_angle", "rotation"] else restored_state.get(key) == source_state.get(key), "late baseline restores %s for barrel %s" % [key, str(source_state.get("entity_id", ""))])
	_check(int(restored_rubber.get("bounce_count", -1)) > 0 and is_equal_approx(float(restored_rubber.get("x", NAN)), float(rubber_state.get("x", 0.0))), "late join restores the active rubber barrel's authoritative bounce state")
	_check(bool(restored_ordinary.get("spawned", false)) and not bool(restored_ordinary.get("rubber", true)) and late_guest.entity_ledger.is_active(ordinary_id), "already-moving ordinary barrel remains present and active beside restored rubber state")
	_check(host.step_to(host_tick + 1) and late_guest.step_to(host_tick + 1), "host and late guest continue from the same restored simulation tick")
	for source_state in host.barrels:
		var restored_state := _barrel_for_entity(late_guest, str(source_state.get("entity_id", "")))
		_check(is_equal_approx(float(restored_state.get("x", NAN)), float(source_state.get("x", NAN))) and is_equal_approx(float(restored_state.get("y", NAN)), float(source_state.get("y", NAN))) and bool(restored_state.get("spawned", false)) == bool(source_state.get("spawned", false)), "mixed barrel poses remain tick-identical after late-join resume")
	var invalid_duplicate: Dictionary = late_baseline.duplicate(true)
	invalid_duplicate.barrels[1].id = str(invalid_duplicate.barrels[0].id)
	_check(not late_guest.apply_baseline(invalid_duplicate), "baseline rejects duplicate barrel IDs")
	var invalid_missing: Dictionary = late_baseline.duplicate(true)
	invalid_missing.barrels.pop_back()
	_check(not late_guest.apply_baseline(invalid_missing), "baseline rejects a missing dynamic barrel row")
	var invalid_unknown: Dictionary = late_baseline.duplicate(true)
	invalid_unknown.barrels[0].id = "unknown_barrel"
	_check(not late_guest.apply_baseline(invalid_unknown), "baseline rejects an unknown barrel ID")
	var invalid_variant: Dictionary = late_baseline.duplicate(true)
	invalid_variant.barrels[0].variant = 999
	_check(not late_guest.apply_baseline(invalid_variant), "baseline rejects a barrel variant mismatch")
	var invalid_type: Dictionary = late_baseline.duplicate(true)
	invalid_type.barrels[0].x = "not-a-number"
	_check(not late_guest.apply_baseline(invalid_type), "baseline rejects malformed dynamic pose types")
	_check(_barrel_for_entity(late_guest, ordinary_id).get("spawned", false) == true and is_equal_approx(float(_barrel_for_entity(late_guest, ordinary_id).get("x", NAN)), float(ordinary_state.get("x", NAN))), "rejected malformed baselines leave the restored ordinary barrel intact")
	print("GEN21_MIXED_BARREL_LATE_BASELINE seed=%d tick=%d ordinary=%s ordinary_x=%.2f rubber=%s rubber_x=%.2f bounce=%d saw=%s saw_history=%s" % [int(course_manifest.get("seed_value")), host_tick, ordinary_id, float(_barrel_for_entity(late_guest, ordinary_id).get("x", NAN)), rubber_id, float(_barrel_for_entity(late_guest, rubber_id).get("x", NAN)), int(_barrel_for_entity(late_guest, rubber_id).get("bounce_count", -1)), active_saw_id, str(late_guest._saw_history.has(host_tick))])
	_verify_legacy_world_baseline_formats(int(course_manifest.get("seed_value")))

func _barrel_for_entity(world: RefCounted, entity_id: String) -> Dictionary:
	for barrel in world.get("barrels"):
		if str(barrel.get("entity_id", "")) == entity_id:
			return barrel
	return {}

func _verify_legacy_world_baseline_formats(seed_value: int) -> void:
	var built: Dictionary = Builder.new().build(seed_value, 45000, 20)
	var old_manifest: Variant = built.get("manifest")
	_check(old_manifest != null, "Gen20 manifest remains available for legacy baseline compatibility")
	if old_manifest == null:
		return
	var source := World.new()
	_check(str(source.configure(old_manifest)).is_empty(), "Gen20 world configures for legacy baseline compatibility")
	var canonical: Dictionary = source.baseline()
	_check(int(canonical.get("baseline_format_version", -1)) == 4 and not canonical.has("barrels"), "Gen20 keeps its original baseline4 schema")
	for legacy_version in [2, 3, 4]:
		var snapshot: Dictionary = canonical.duplicate(true)
		snapshot["baseline_format_version"] = int(legacy_version)
		if legacy_version < 4:
			var legacy_rows: Array = []
			var row_size := 9 if legacy_version == 2 else 10
			for row_value in snapshot.get("entities", []):
				if row_value is Array:
					legacy_rows.append((row_value as Array).slice(0, row_size))
			snapshot["entities"] = legacy_rows
		var replica := World.new()
		_check(str(replica.configure(old_manifest)).is_empty() and replica.apply_baseline(snapshot), "world simulation continues to accept legacy baseline format %d" % legacy_version)

func _find_safe_all_speed_rubber_seed(first_seed: int, last_seed_exclusive: int) -> void:
	var builder := Builder.new()
	var rubber_candidates := 0
	var matched_500_seed := -1
	for seed_value in range(first_seed, last_seed_exclusive):
		var built: Dictionary = builder.build(seed_value, 45000, Generator.GENERATOR_VERSION_21)
		var candidate_manifest: Variant = built.get("manifest")
		if candidate_manifest == null:
			continue
		var candidate_rubber: Dictionary = {}
		for event in candidate_manifest.events:
			if str(event.get("kind", "")) == "barrels" and int(event.get("barrel_variant", 0)) == 1:
				candidate_rubber = event
				break
		if candidate_rubber.is_empty():
			continue
		rubber_candidates += 1
		var routes: Array[Dictionary] = []
		var safe_at_all_speeds := true
		for speed in [250.0, 500.0, 750.0]:
			var route := _simulate_visible_runner_route_with_schedule(candidate_manifest, candidate_rubber, float(speed), -1, -1)
			if seed_value == first_seed + 1 and not bool(route.get("passed", false)):
				route = _search_safe_runner_schedule(candidate_manifest, candidate_rubber, float(speed), route)
			routes.append(route)
			safe_at_all_speeds = safe_at_all_speeds and bool(route.get("passed", false))
		print("GEN21_ROUTE_CANDIDATE seed=%d rubber=%s safe250=%s terminal250=%s searched250=%s schedules250=%d safe500=%s terminal500=%s searched500=%s schedules500=%d safe750=%s terminal750=%s searched750=%s schedules750=%d" % [seed_value, str(candidate_rubber.get("event_id", "")), str(bool(routes[0].get("passed", false))), str(routes[0].get("terminal_event", "")), str(bool(routes[0].get("schedule_searched", false))), int(routes[0].get("schedules_tested", 0)), str(bool(routes[1].get("passed", false))), str(routes[1].get("terminal_event", "")), str(bool(routes[1].get("schedule_searched", false))), int(routes[1].get("schedules_tested", 0)), str(bool(routes[2].get("passed", false))), str(routes[2].get("terminal_event", "")), str(bool(routes[2].get("schedule_searched", false))), int(routes[2].get("schedules_tested", 0))])
		if seed_value == first_seed + 1:
			_compare_candidate_to_gen20(builder, seed_value, float(candidate_rubber.get("rubber_target_x", NAN)))
			_check(safe_at_all_speeds, "bounded independent RunnerMotion schedules find a legal route through this rubber encounter at 250/500/750 px/s")
			_check(bool(routes[1].get("barrel_encounter_visible", false)) and int(routes[1].get("bounce_tick", -1)) >= 0, "the 500 px/s safe route visibly reaches the generated rubber contact")
		if matched_500_seed < 0 and bool(routes[1].get("passed", false)):
			matched_500_seed = seed_value
		if safe_at_all_speeds:
			print("GEN21_ALL_SPEED_RUBBER_SEED seed=%d rubber=%s routes=%s" % [seed_value, str(candidate_rubber.get("event_id", "")), str(routes)])
			return
	print("GEN21_ALL_SPEED_RUBBER_SEED not_found_range=%d..%d rubber_candidates=%d first_safe_500_seed=%d" % [first_seed, last_seed_exclusive - 1, rubber_candidates, matched_500_seed])

func _compare_candidate_to_gen20(builder: RefCounted, seed_value: int, target_x: float) -> void:
	var legacy_build: Dictionary = builder.build(seed_value, 45000, 20)
	var legacy_manifest: Variant = legacy_build.get("manifest")
	if legacy_manifest == null:
		print("GEN21_MATCHED_GEN20 seed=%d manifest=null target_x=%.1f" % [seed_value, target_x])
		return
	var nearest_block: Dictionary = {}
	var nearest_gap := INF
	for event in legacy_manifest.events:
		if str(event.get("kind", "")) != "block":
			continue
		var gap := absf(float(event.get("x", INF)) - target_x)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest_block = event
	if nearest_block.is_empty():
		print("GEN21_MATCHED_GEN20 seed=%d block=none target_x=%.1f" % [seed_value, target_x])
		return
	var matched_target := {"event_id": str(nearest_block.get("event_id", "")), "rubber_target_x": float(nearest_block.get("x", NAN))}
	var routes: Array[Dictionary] = []
	for speed in [250.0, 500.0, 750.0]:
		var route := _simulate_visible_runner_route_with_schedule(legacy_manifest, matched_target, speed, -1, -1)
		if not bool(route.get("passed", false)):
			route = _search_safe_runner_schedule(legacy_manifest, matched_target, speed, route)
		routes.append(route)
	print("GEN21_MATCHED_GEN20 seed=%d gen20_block=%s block_x=%.1f target_delta=%.1f safe250=%s terminal250=%s schedules250=%d safe500=%s terminal500=%s schedules500=%d safe750=%s terminal750=%s schedules750=%d" % [seed_value, str(nearest_block.get("event_id", "")), float(nearest_block.get("x", NAN)), nearest_gap, str(bool(routes[0].get("passed", false))), str(routes[0].get("terminal_event", "")), int(routes[0].get("schedules_tested", 0)), str(bool(routes[1].get("passed", false))), str(routes[1].get("terminal_event", "")), int(routes[1].get("schedules_tested", 0)), str(bool(routes[2].get("passed", false))), str(routes[2].get("terminal_event", "")), int(routes[2].get("schedules_tested", 0))])

func _search_safe_runner_schedule(course_manifest: Resource, target: Dictionary, speed: float, baseline: Dictionary) -> Dictionary:
	# Search a bounded set of real first flips, first without a return flip, then
	# a later return only after the target block is cleared and cooldown expires.
	var schedules_tested := 0
	var start_x := float(course_manifest.start_x)
	var target_x := float(target.get("rubber_target_x", NAN))
	var visible_tick := ceili(maxf(target_x - 780.0 - start_x, 0.0) * 60.0 / speed)
	var crossing_tick := ceili((target_x + 72.0 - start_x) * 60.0 / speed)
	for first_tick in range(visible_tick + 12, maxi(visible_tick + 12, crossing_tick - 7), 12):
		var stay_ceiling := _simulate_visible_runner_route_with_schedule(course_manifest, target, speed, first_tick, -1)
		schedules_tested += 1
		if bool(stay_ceiling.get("passed", false)):
			stay_ceiling["searched_schedule"] = true
			stay_ceiling["schedules_tested"] = schedules_tested
			return stay_ceiling
		for second_tick in range(maxi(crossing_tick, first_tick + ceili(Motion.FLIP_COOLDOWN_SECONDS * 60.0)), crossing_tick + 25, 12):
			var return_route := _simulate_visible_runner_route_with_schedule(course_manifest, target, speed, first_tick, second_tick)
			schedules_tested += 1
			if bool(return_route.get("passed", false)):
				return_route["searched_schedule"] = true
				return_route["schedules_tested"] = schedules_tested
				return return_route
			if schedules_tested >= 30:
				baseline["schedule_searched"] = true
				baseline["schedules_tested"] = schedules_tested
				return baseline
	baseline["schedule_searched"] = true
	baseline["schedules_tested"] = schedules_tested
	return baseline

func _simulate_visible_runner_route_with_schedule(course_manifest: Resource, target: Dictionary, speed: float, scheduled_first_flip: int, scheduled_second_flip: int) -> Dictionary:
	var simulation := World.new()
	if not str(simulation.configure(course_manifest)).is_empty():
		return {"passed": false}
	var start_x := float(course_manifest.start_x)
	var target_id := str(target.get("event_id", ""))
	var event_target_x := float(target.get("rubber_target_x", NAN))
	# Start a local encounter corridor at its real course time, not at tick zero.
	# Every event in the full manifest is still present and prior triggerable hazards
	# are activated while the corridor advances to the warning approach. This checks
	# a reachable supported state entering the encounter, not whole-run survivability.
	var route_start_x := maxf(start_x, event_target_x - 780.0)
	var route_start_tick := ceili((route_start_x - start_x) * 60.0 / speed)
	var player := {"y": float(course_manifest.initial_floor_y) - Motion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
	for pre_tick in range(1, route_start_tick + 1):
		if not simulation.step_to(pre_tick):
			return {"passed": false}
		var pre_x := start_x + speed * float(pre_tick) / 60.0
		var pre_floor := simulation.surface_at(pre_x, false)
		player["y"] = float(pre_floor.get("y", course_manifest.initial_floor_y)) - Motion.SIZE.y * 0.5
		_activate_due_shared_hazards(simulation, course_manifest, player, pre_x, pre_tick, speed)
	var start_floor := simulation.surface_at(route_start_x, false)
	if not bool(start_floor.get("supported", false)):
		return {"passed": false, "terminal_event": "unsupported_corridor_start"}
	player["y"] = float(start_floor.get("y", course_manifest.initial_floor_y)) - Motion.SIZE.y * 0.5
	var previous := {"world_x": route_start_x, "y": float(player.y), "gravity_direction": 1, "grounded": true, "vertical_speed": 0.0}
	var visible_tick := -1
	var barrel_visible_tick := -1
	var encounter_tick := -1
	var bounce_tick := -1
	var closest_gap := INF
	var safe_opposite := false
	var flipped := false
	var returned_to_floor := false
	var actual_first_flip_tick := -1
	var terminal_event := ""
	var max_tick := mini(12000, maxi(route_start_tick + 1, ceili((event_target_x + 1100.0 - start_x) * 60.0 / speed)))
	for sim_tick in range(route_start_tick + 1, max_tick + 1):
		if not simulation.step_to(sim_tick):
			return {"passed": false}
		var player_x := start_x + speed * float(sim_tick) / 60.0
		var camera_left := maxf(player_x - 180.0, 0.0)
		var block_screen_x := event_target_x - camera_left
		if visible_tick < 0 and block_screen_x >= -64.0 and block_screen_x <= 960.0:
			visible_tick = sim_tick
		_activate_due_shared_hazards(simulation, course_manifest, player, player_x, sim_tick, speed)
		var barrel := _barrel_for_event(simulation, target_id)
		if bool(barrel.get("spawned", false)) and not bool(barrel.get("destroyed", false)):
			var screen_x := float(barrel.get("x", INF)) - camera_left
			if barrel_visible_tick < 0 and screen_x >= -36.0 and screen_x <= 960.0:
				barrel_visible_tick = sim_tick
			var gap := absf(float(barrel.get("x", INF)) - player_x)
			if gap < closest_gap:
				closest_gap = gap
				encounter_tick = sim_tick
			if int(barrel.get("bounce_count", 0)) > 0 and bounce_tick < 0:
				bounce_tick = sim_tick
				var bounce_x := float(barrel.get("x", player_x))
				var ceiling := simulation.surface_at(bounce_x, true)
				var opposite_state := {"world_x": bounce_x, "y": float(ceiling.y) + Motion.SIZE.y * 0.5, "gravity_direction": -1, "grounded": bool(ceiling.supported), "vertical_speed": 0.0}
				var opposite_static := simulation.first_static_terminal_contact(opposite_state, opposite_state)
				var opposite_dynamic := simulation.player_contact_at(opposite_state, sim_tick)
				safe_opposite = bool(ceiling.supported) and str(opposite_static.get("kind", "")) != "terminal" and str(opposite_dynamic.get("kind", "")) not in ["terminal", "shared_interaction"]
		if visible_tick >= 0 and actual_first_flip_tick < 0:
			actual_first_flip_tick = visible_tick + 12 if scheduled_first_flip < 0 else scheduled_first_flip
		if visible_tick >= 0 and not flipped and sim_tick >= actual_first_flip_tick and bool(player.grounded):
			flipped = Motion.try_flip(player, -1)
		if flipped and not returned_to_floor and scheduled_second_flip >= 0 and sim_tick >= scheduled_second_flip and player_x >= event_target_x + 72.0 and float(player.get("cooldown", 0.0)) <= 0.0 and bool(player.grounded):
			returned_to_floor = Motion.try_flip(player, 1)
		var floor_info := simulation.surface_at(player_x, false)
		var ceiling_info := simulation.surface_at(player_x, true)
		Motion.advance_vertical(player, 1.0 / 60.0, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
		var proposed := {"world_x": player_x, "y": float(player.y), "gravity_direction": int(player.gravity_direction), "grounded": bool(player.grounded), "vertical_speed": float(player.vertical_speed)}
		var static_contact := simulation.first_static_terminal_contact(previous, proposed)
		var dynamic_contact := simulation.player_contact_at(proposed, sim_tick)
		if str(static_contact.get("kind", "")) == "terminal":
			terminal_event = "%s:%s" % [str(static_contact.get("reason", "static")), str(static_contact.get("event_id", "static"))]
			break
		if str(dynamic_contact.get("kind", "")) in ["terminal", "shared_interaction"]:
			terminal_event = "%s:%s" % [str(dynamic_contact.get("reason", "dynamic")), str(dynamic_contact.get("event_id", dynamic_contact.get("kind", "dynamic")))]
			break
		previous = proposed
		if player_x > event_target_x + 1100.0:
			break
	var margin_ticks := encounter_tick - barrel_visible_tick - 12 if barrel_visible_tick >= 0 and encounter_tick >= 0 else -1
	var bounce_margin_ticks := bounce_tick - barrel_visible_tick - 12 if barrel_visible_tick >= 0 and bounce_tick >= 0 else -1
	var passed := terminal_event.is_empty() and visible_tick >= 0 and flipped and bool(player.grounded)
	return {"passed": passed, "visible_tick": visible_tick, "first_flip_tick": actual_first_flip_tick, "second_flip_tick": scheduled_second_flip, "barrel_visible_tick": barrel_visible_tick, "barrel_encounter_visible": barrel_visible_tick >= 0 and encounter_tick >= 0, "encounter_tick": encounter_tick, "bounce_tick": bounce_tick, "reaction_margin_ticks": margin_ticks, "bounce_reaction_ticks": bounce_margin_ticks, "closest_gap": closest_gap, "safe_opposite_at_bounce": safe_opposite, "returned_to_floor": returned_to_floor, "terminal_event": terminal_event, "final_x": start_x + speed * float(simulation.tick) / 60.0, "final_lane": int(player.gravity_direction)}

func _activate_due_shared_hazards(simulation: RefCounted, course_manifest: Resource, runner: Dictionary, player_x: float, tick_value: int, speed: float) -> void:
	for event in course_manifest.events:
		var kind := str(event.get("kind", ""))
		var event_id := str(event.get("event_id", ""))
		var entity: Dictionary = simulation.entity_ledger.entities.get(event_id, {})
		if entity.is_empty():
			continue
		if kind == "ghost" and int(entity.get("ghost_activation_tick", -1)) < 0 and player_x >= GhostModel.trigger_x(event):
			if int(event.get("ghost_variant", 0)) in [2, 3] and not bool(runner.get("grounded", false)):
				continue
			var activation: Dictionary = {"world_revision": simulation.entity_ledger.revision + 1, "commit_id": "g21-%s-%d" % [event_id, tick_value], "entity_id": event_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": tick_value, "ghost_activation_tick": tick_value, "trigger_peer_id": 1, "trigger_tick": tick_value, "state_before": "active", "state_after": "active"}
			if int(event.get("ghost_variant", 0)) in [2, 3]:
				activation.merge({"ghost_activation_lane": 1 if int(runner.get("gravity_direction", 1)) > 0 else 2, "ghost_activation_world_x": player_x, "ghost_activation_speed": speed, "ghost_target_peer_id": 1}, true)
			simulation.apply_world_commit(activation)
		elif kind == "rock" and int(entity.get("rock_activation_tick", -1)) < 0 and player_x >= float(event.get("x", 0.0)) - float(event.get("trigger_lead", RockModel.TRIGGER_LEAD)):
			var activation_tick := tick_value + int(event.get("delivery_ticks", RockModel.DELIVERY_TICKS))
			simulation.apply_world_commit({"world_revision": simulation.entity_ledger.revision + 1, "commit_id": "r21-%s-%d" % [event_id, tick_value], "entity_id": event_id, "incarnation": 1, "action": "activate_rock", "effective_tick": activation_tick, "rock_activation_tick": activation_tick, "state_before": "active", "state_after": "active"})
		elif kind == "saw" and int(entity.get("saw_activation_tick", -1)) < 0:
			var trigger_x := float(event.get("spawn_x", float(event.get("x", 0.0)) + SawModel.START_OFFSET)) - SawModel.SPAWN_LEAD
			if player_x >= trigger_x:
				var activation_tick := tick_value + SawModel.ACTIVATION_DELAY_TICKS
				simulation.apply_world_commit({"world_revision": simulation.entity_ledger.revision + 1, "commit_id": "s21-%s-%d" % [event_id, tick_value], "entity_id": event_id, "incarnation": 1, "action": "activate_saw", "effective_tick": activation_tick, "saw_activation_tick": activation_tick, "state_before": "active", "state_after": "active"})

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _finish() -> void:
	print("GEN21_RUBBER_BARREL_SHARED_SIMULATION_TEST failures=%d" % failures)
	quit(1 if failures > 0 else 0)
