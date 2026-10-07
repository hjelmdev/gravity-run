extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Motion := preload("res://systems/runner_motion.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const RockModel := preload("res://systems/falling_rock_model.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")
const CASES := [
	{"seed": 100000030, "from_ceiling": true},
	{"seed": 100000019, "from_ceiling": false},
]
const SPEEDS := [250.0, 500.0, 750.0]

var failures := 0

func _initialize() -> void:
	_test_close_pursuit_filter()
	for test_case in CASES:
		var seed_value := int(test_case.seed)
		var expected_origin := bool(test_case.from_ceiling)
		var built: Dictionary = Builder.new().build(seed_value, 45000, 20)
		var manifest: Variant = built.get("manifest")
		_check(manifest != null, "Gen19 generated manifest builds seed=%d" % seed_value)
		if manifest == null:
			continue
		var target: Dictionary = {}
		for event in manifest.events:
			if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3 and bool(event.get("from_ceiling", false)) == expected_origin:
				target = event
				break
		_check(not target.is_empty(), "seed=%d has a generated %s-origin one-shot pursuit" % [seed_value, "ceiling" if expected_origin else "floor"])
		if target.is_empty():
			continue
		var safe_speed_count := 0
		var target_lanes: Dictionary = {}
		for speed in SPEEDS:
			var floor_strategy := _simulate(manifest, target, seed_value, float(speed), false)
			var ceiling_strategy := _simulate(manifest, target, seed_value, float(speed), true)
			var safe := floor_strategy or ceiling_strategy
			_check(safe, "seed=%d origin=%s has a full-manifest RunnerMotion escape route with 12-tick reaction and all hazards at speed=%.0f" % [seed_value, "ceiling" if expected_origin else "floor", speed])
			if safe:
				safe_speed_count += 1
				if floor_strategy:
					target_lanes["floor_start"] = 1
				if ceiling_strategy:
					target_lanes["ceiling_start"] = 2
		_check(safe_speed_count == SPEEDS.size(), "all representative speeds are tested for seed=%d" % seed_value)
		print("GEN19_FULL_MANIFEST_PURSUIT_ROUTE seed=%d target=%s origin=%s speeds=%s safe_speeds=%d safe_target_lanes=%s" % [seed_value, str(target.get("event_id", "")), "ceiling" if expected_origin else "floor", str(SPEEDS), safe_speed_count, str(target_lanes)])
	quit(1 if failures > 0 else 0)

func _test_close_pursuit_filter() -> void:
	var builder := Builder.new()
	var events: Array[Dictionary] = [
		{"event_id": "close-a", "kind": "ghost", "ghost_variant": 3, "x": 5000.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": false, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
		{"event_id": "close-b", "kind": "ghost", "ghost_variant": 3, "x": 5180.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": true, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
		{"event_id": "separated-c", "kind": "ghost", "ghost_variant": 3, "x": 9000.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": false, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
	]
	var filtered: Array[Dictionary] = builder.call("filter_unsafe_gen19_pursuits", events)
	_check(filtered.size() == 2 and str(filtered[0].event_id) == "close-a" and str(filtered[1].event_id) == "separated-c", "Gen19 drops only the pursuit whose trigger overlaps an active chase")
	_check(is_equal_approx(float(filtered[1].x) - float(filtered[0].x), Builder.GEN19_PURSUIT_MIN_TRIGGER_GAP), "Gen19 keeps pursuit trigger spacing at the documented boundary")
	var support_events: Array[Dictionary] = [
		{"event_id": "accepted-before-gap", "kind": "ghost", "ghost_variant": 3, "x": 2500.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": false, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
		{"event_id": "support-gap", "kind": "gap", "x": 5500.0, "width": 200.0, "from_ceiling": false},
		{"event_id": "rejected-support", "kind": "ghost", "ghost_variant": 3, "x": 7000.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": true, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
		{"event_id": "accepted-after-gap", "kind": "ghost", "ghost_variant": 3, "x": 10500.0, "trigger_lead": 2500.0, "warning_ticks": 90, "danger_ticks": 200, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "from_ceiling": false, "floor_y": 460.0, "ceiling_y": 80.0, "width": 72.0, "height": 96.0},
	]
	var filtered_support: Array[Dictionary] = builder.call("filter_unsafe_gen19_pursuits", support_events)
	var support_index := preload("res://systems/course_surface_index.gd").new()
	support_index.configure(support_events, 460.0, 80.0)
	print("GEN19_PURSUIT_SUPPORT_PROBE supported=%s near_floor=%s near_ceil=%s interval=%s" % [str(support_index.call("interval_is_supported", -436.0, 4826.0, false)), str(builder.call("_gen18_surface_stays_near", support_index, -436.0, 4826.0, false, 460.0)), str(builder.call("_gen18_surface_stays_near", support_index, -436.0, 4826.0, true, 80.0)), str(support_index.call("surface_at", 4826.0, false))])
	var surviving_support_pursuits: Array[String] = []
	var filtered_support_ids: Array[String] = []
	for event in filtered_support:
		filtered_support_ids.append(str(event.get("event_id", "")))
		if int(event.get("ghost_variant", 0)) == 3:
			surviving_support_pursuits.append(str(event.get("event_id", "")))
	print("GEN19_PURSUIT_SUPPORT_FILTER all=%s accepted=%s" % [str(filtered_support_ids), str(surviving_support_pursuits)])
	_check(surviving_support_pursuits == ["accepted-before-gap", "accepted-after-gap"], "a rejected unsupported pursuit does not shift spacing and suppress the next supported candidate")

func _simulate(manifest: Resource, target: Dictionary, seed_value: int, speed: float, start_ceiling: bool) -> bool:
	var world := World.new()
	var config_error := str(world.configure(manifest))
	if not config_error.is_empty():
		print("GEN19_ROUTE_SETUP_FAIL speed=%.0f error=%s" % [speed, config_error])
		return false
	var start_x := float(manifest.get("start_x"))
	var end_x := float(target.get("x", 0.0)) + 1800.0
	print("GEN19_ROUTE_SETUP seed=%d speed=%.0f target=%s x=%.1f trigger=%.1f start_lane=%s initial=%d" % [seed_value, speed, str(target.get("event_id", "")), float(target.get("x", 0.0)), GhostModel.trigger_x(target), "ceiling" if start_ceiling else "floor", start_x])
	var max_tick := ceili((end_x - start_x) / speed * 60.0)
	var runner := {"y": float(manifest.get("initial_floor_y")) - Motion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
	if start_ceiling:
		Motion.try_flip(runner, -1)
	var previous := {"world_x": start_x, "y": float(runner.y), "gravity_direction": 1}
	var target_activation := -1
	var target_lane := 0
	var flipped := false
	var pursuit_snapshots: Dictionary = {}
	var pursuit_reacted: Dictionary = {}
	var target_passed := false
	for tick in range(1, max_tick + 1):
		var player_x := start_x + speed * float(tick) / 60.0
		if not world.step_to(tick):
			print("GEN19_ROUTE_STEP_FAIL speed=%.0f tick=%d" % [speed, tick])
			return false
		for event in manifest.get("events"):
			var kind := str(event.get("kind", ""))
			if kind not in ["ghost", "rock", "saw"]:
				continue
			var entity_id := str(event.get("event_id", ""))
			var entity: Dictionary = world.entity_ledger.entities.get(entity_id, {})
			if entity.is_empty():
				continue
			if kind == "ghost":
				if int(entity.get("ghost_activation_tick", -1)) >= 0 or player_x < GhostModel.trigger_x(event):
					continue
				if int(event.get("ghost_variant", 0)) in [2, 3] and not bool(runner.grounded):
					continue
				var lane := 1 if int(runner.gravity_direction) > 0 else 2
				var commit := {"world_revision": world.entity_ledger.revision + 1, "commit_id": "g19-%s-%d" % [entity_id, tick], "entity_id": entity_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": tick, "ghost_activation_tick": tick, "trigger_peer_id": 1, "trigger_tick": tick, "state_before": "active", "state_after": "active"}
				if int(event.get("ghost_variant", 0)) in [2, 3]:
					commit.merge({"ghost_activation_lane": lane, "ghost_activation_world_x": player_x, "ghost_activation_speed": speed, "ghost_target_peer_id": 1}, true)
				var result := str(world.apply_world_commit(commit))
				if result != "applied":
					print("GEN19_ROUTE_GHOST_ACTIVATION_FAIL speed=%.0f event=%s result=%s" % [speed, entity_id, result])
					return false
				if entity_id == str(target.get("event_id", "")):
					target_activation = tick
					target_lane = lane
					print("GEN19_ROUTE_TARGET_ACTIVATED speed=%.0f tick=%d px=%.1f lane=%d ghost_variant=%d" % [speed, tick, player_x, lane, int(event.get("ghost_variant", 0))])
				if int(event.get("ghost_variant", 0)) in [2, 3]:
					pursuit_snapshots[entity_id] = {"activation_tick": tick, "lane": lane, "world_x": player_x}
					print("GEN19_ROUTE_PURSUIT_SNAPSHOT speed=%.0f event=%s variant=%d tick=%d lane=%d x=%.1f" % [speed, entity_id, int(event.get("ghost_variant", 0)), tick, lane, player_x])
			elif kind == "rock":
				if int(entity.get("rock_activation_tick", -1)) >= 0 or player_x < float(event.get("x", 0.0)) - float(event.get("trigger_lead", RockModel.TRIGGER_LEAD)):
					continue
				var commit := {"world_revision": world.entity_ledger.revision + 1, "commit_id": "r19-%s-%d" % [entity_id, tick], "entity_id": entity_id, "incarnation": 1, "action": "activate_rock", "effective_tick": tick + int(event.get("delivery_ticks", RockModel.DELIVERY_TICKS)), "rock_activation_tick": tick + int(event.get("delivery_ticks", RockModel.DELIVERY_TICKS)), "state_before": "active", "state_after": "active"}
				world.apply_world_commit(commit)
			else:
				if int(entity.get("saw_activation_tick", -1)) >= 0:
					continue
				var trigger_x := float(event.get("spawn_x", float(event.get("x", 0.0)) + SawModel.START_OFFSET)) - SawModel.SPAWN_LEAD
				if player_x < trigger_x:
					continue
				var commit := {"world_revision": world.entity_ledger.revision + 1, "commit_id": "s19-%s-%d" % [entity_id, tick], "entity_id": entity_id, "incarnation": 1, "action": "activate_saw", "effective_tick": tick + SawModel.ACTIVATION_DELAY_TICKS, "saw_activation_tick": tick + SawModel.ACTIVATION_DELAY_TICKS, "state_before": "active", "state_after": "active"}
				world.apply_world_commit(commit)
		for pursuit_id in pursuit_snapshots:
			if pursuit_reacted.has(pursuit_id):
				continue
			var snapshot: Dictionary = pursuit_snapshots[pursuit_id]
			if tick < int(snapshot.activation_tick) + 12:
				continue
			var escape_direction := -1 if int(snapshot.lane) == 1 else 1
			if int(runner.gravity_direction) == escape_direction:
				pursuit_reacted[pursuit_id] = true
			elif bool(runner.grounded):
				var reacted := Motion.try_flip(runner, escape_direction)
				if pursuit_id == str(target.get("event_id", "")) and tick <= int(snapshot.activation_tick) + 30:
					print("GEN19_ROUTE_REACTION speed=%.0f tick=%d target_tick=%d current=%d escape=%d grounded=%s cooldown=%.3f y=%.1f result=%s" % [speed, tick, int(snapshot.activation_tick), int(runner.gravity_direction), escape_direction, str(bool(runner.grounded)), float(runner.get("cooldown", 0.0)), float(runner.y), str(reacted)])
				if reacted:
					pursuit_reacted[pursuit_id] = true
					if pursuit_id == str(target.get("event_id", "")):
						flipped = true
		var floor_info: Dictionary = world.surface_at(player_x, false)
		var ceiling_info: Dictionary = world.surface_at(player_x, true)
		Motion.advance_vertical(runner, 1.0 / 60.0, float(floor_info.get("y", 460.0)), float(ceiling_info.get("y", 80.0)), bool(floor_info.get("supported", true)), bool(ceiling_info.get("supported", true)))
		var proposed := {"world_x": player_x, "y": float(runner.y), "gravity_direction": int(runner.gravity_direction), "grounded": bool(runner.grounded), "vertical_speed": float(runner.vertical_speed)}
		var contact := world.first_static_terminal_contact(previous, proposed)
		if str(contact.get("kind", "")) == "terminal":
			var terminal_id := str(contact.get("event_id", ""))
			var terminal_entity: Dictionary = world.entity_ledger.entities.get(terminal_id, {})
			var terminal_event: Dictionary = {}
			for candidate in manifest.get("events"):
				if str(candidate.get("event_id", "")) == terminal_id:
					terminal_event = candidate
					break
			var terminal_activation := int(terminal_entity.get("ghost_activation_tick", -1))
			var terminal_pose := GhostModel.center_for_activation(terminal_event, terminal_activation, tick, world.call("_ghost_activation_state", terminal_entity)) if str(terminal_event.get("kind", "")) == "ghost" else Vector2.ZERO
			print("GEN19_ROUTE_TERMINAL speed=%.0f tick=%d x=%.2f y=%.2f reason=%s event=%s lane=%d target_activation=%d ghostpose=%s ghostlane=%d ghostactivation=%d targetlane=%d" % [speed, tick, player_x, float(runner.y), str(contact.get("reason", "")), terminal_id, int(runner.gravity_direction), target_activation, str(terminal_pose), int(terminal_entity.get("ghost_activation_lane", 0)), terminal_activation, target_lane])
			return false
		var endpoint := world.player_contact(proposed)
		if str(endpoint.get("kind", "")) == "terminal":
			print("GEN19_ROUTE_ENDPOINT_TERMINAL speed=%.0f tick=%d x=%.2f reason=%s event=%s lane=%d target_activation=%d" % [speed, tick, player_x, str(endpoint.get("reason", "")), str(endpoint.get("event_id", "")), int(runner.gravity_direction), target_activation])
			return false
		var target_state: Dictionary = world.entity_ledger.entities.get(str(target.get("event_id", "")), {})
		if int(target_state.get("ghost_activation_tick", -1)) >= 0:
			var ghost_center := GhostModel.center_for_activation(target, target_activation, tick, {"lane": int(target_state.get("ghost_activation_lane", 1)), "world_x": float(target_state.get("ghost_activation_world_x", player_x)), "speed": speed, "target_peer_id": 1})
			if ghost_center.x > player_x + float(target.get("width", 72.0)) * 0.5 + Motion.SIZE.x * 0.5:
				target_passed = true
		previous = proposed
	var passed := target_passed and target_activation >= 0 and flipped and bool(runner.grounded)
	print("GEN19_ROUTE_RESULT speed=%.0f start_lane=%s activation=%d target_lane=%d flip=%s passed=%s grounded=%s final_x=%.1f final_lane=%d" % [speed, "ceiling" if start_ceiling else "floor", target_activation, target_lane, str(flipped), str(target_passed), str(bool(runner.grounded)), end_x, int(runner.gravity_direction)])
	return passed

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("GEN19_FULL_MANIFEST_PURSUIT_ROUTE: " + message)
