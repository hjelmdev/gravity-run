extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const LavaScene := preload("res://hazards/lava_hazard.tscn")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--gen15-filter-only"):
		_test_gen15_unsafe_volcano_filtering()
		print("LAVA_GEN15_FILTER_ONLY failures=%d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	if OS.get_cmdline_user_args().has("--gen15-cohort-only"):
		_test_gen15_volcano_cohort()
		print("LAVA_GEN15_COHORT_ONLY failures=%d" % failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	var built: Dictionary = Builder.new().build(100000014, 45000, 14)
	_check(built.get("manifest") != null, "representative Gen14 course builds")
	if built.get("manifest") == null:
		get_tree().quit(1)
		return
	var manifest: Resource = built.manifest
	var crack: Dictionary = {}
	var volcano: Dictionary = {}
	for event in manifest.get("events"):
		if crack.is_empty() and str(event.get("kind", "")) == "lava_crack":
			crack = event
		if volcano.is_empty() and str(event.get("kind", "")) == "volcano":
			volcano = event
	_check(not crack.is_empty() and not volcano.is_empty(), "test seed contains both lava hazard types")
	if crack.is_empty() or volcano.is_empty():
		get_tree().quit(1)
		return
	var presentation := Presentation.new() as Node
	get_tree().root.add_child(presentation)
	_check(str(presentation.call("load_manifest", manifest)).is_empty(), "real shared presentation loads generated lava events")
	var full_world := WorldSimulation.new()
	_check(str(full_world.configure(manifest)).is_empty(), "shared multiplayer world accepts generated lava manifest")
	var first_render: Dictionary = full_world.render_state(0.5)
	_check((first_render.get("lava", []) as Array).size() == full_world.lava_events.size(), "world render state carries every immutable lava event")
	presentation.call("set_world_state", first_render)
	var presented_volcano: Node = presentation.get("event_nodes").get(str(volcano.event_id))
	_check(is_instance_valid(presented_volcano) and presented_volcano is LavaHazard, "MP presentation creates the common lava hazard scene")
	if is_instance_valid(presented_volcano):
		var render_tick := float(presented_volcano.get("simulation_tick"))
		_check(is_equal_approx(render_tick, float(first_render.get("tick", -1.0))), "MP scene receives the same interpolated shared simulation tick")
		var rendered_projectiles: Array[Dictionary] = LavaModel.projectiles_at(volcano, float(manifest.get("start_x")), render_tick)
		var node_event: Dictionary = presented_volcano.get("event")
		var node_projectiles: Array[Dictionary] = LavaModel.projectiles_at(node_event, float(presented_volcano.get("course_start_x")), render_tick)
		_check(rendered_projectiles == node_projectiles, "presentation and world render the same deterministic projectile positions")
	_test_direct_contact(manifest, crack, "lava_crack")
	_test_direct_contact(manifest, volcano, "lava_projectile")
	_test_volcano_body_contact(manifest, volcano)
	_test_safe_route(manifest, volcano, true)
	_test_safe_route(manifest, crack, not bool(crack.get("from_ceiling", false)))
	_test_generated_manifest_route(manifest, volcano, true)
	_test_generated_manifest_route(manifest, crack, not bool(crack.get("from_ceiling", false)))
	_test_gen15_fan_contract()
	_test_gen15_unsafe_volcano_filtering()
	_test_gen15_volcano_cohort()
	_test_gen14_trajectory_freeze()
	print("LAVA_SHARED_WORLD_TEST failures=%d volcano=%s crack=%s" % [failures, str(volcano.get("event_id", "")), str(crack.get("event_id", ""))])
	presentation.queue_free()
	get_tree().quit(1 if failures > 0 else 0)

func _test_gen15_fan_contract() -> void:
	var result: Dictionary = Builder.new().build(100000034, 45000, 15)
	_check(result.get("manifest") != null, "Gen15 volcano route seed builds")
	if result.get("manifest") == null:
		return
	var manifest: Resource = result.manifest
	_check(int(manifest.get("generator_version")) == 15 and int(manifest.get("manifest_version")) == 8, "Gen15 uses generator15/manifest8")
	var gen15_volcano: Dictionary = {}
	for event in manifest.get("events"):
		if gen15_volcano.is_empty() and str(event.get("kind", "")) == "volcano":
			gen15_volcano = event
	_check(not gen15_volcano.is_empty(), "representative Gen15 route seed contains a volcano")
	if gen15_volcano.is_empty():
		return
	_check(int(gen15_volcano.get("projectile_fan_revision", 0)) == 1, "Gen15 volcano opts into an explicit fan revision")
	var start_tick := LavaModel.eruption_start_tick(gen15_volcano, float(manifest.get("start_x")))
	var fan: Array[Dictionary] = LavaModel.projectiles_at(gen15_volcano, float(manifest.get("start_x")), float(start_tick + 20))
	_check(fan.size() == 6, "one Gen15 burst has six projectiles: three arcs in each direction")
	var ids: Dictionary = {}
	var left_count := 0
	var right_count := 0
	for projectile in fan:
		ids[str(projectile.get("projectile_id", ""))] = true
		if int(projectile.get("direction", 0)) < 0:
			left_count += 1
		else:
			right_count += 1
	_check(ids.size() == 6 and left_count == 3 and right_count == 3, "fan projectile identities are unique and symmetrically spread")
	_check(LavaModel.projectiles_at(gen15_volcano, float(manifest.get("start_x")), float(start_tick + 61)).is_empty(), "all fan arcs are bounded by their serialized lifetimes")
	var intervals: Array[Dictionary] = LavaModel.projectile_positions_for_interval(gen15_volcano, float(manifest.get("start_x")), start_tick + 19, start_tick + 21)
	_check(intervals.size() == 6, "the shared swept model returns every active fan arc")
	var envelope: Rect2 = LavaModel.volcano_collision_envelope(gen15_volcano)
	var envelope_contains_samples := true
	for tick_offset in range(0, 61, 3):
		for projectile in LavaModel.projectiles_at(gen15_volcano, float(manifest.get("start_x")), float(start_tick + tick_offset)):
			var center: Vector2 = Vector2(float(projectile.x), float(projectile.y))
			var radius := float(projectile.radius)
			if center.x - radius < envelope.position.x or center.x + radius > envelope.end.x or center.y - radius < envelope.position.y or center.y + radius > envelope.end.y:
				envelope_contains_samples = false
	_check(envelope_contains_samples, "coin/collision envelope covers all sampled fan projectile positions")
	_check(CoinPlanner._position_blocked(float(gen15_volcano.x), envelope.position.y + 20.0, manifest.get("events")), "coin planner excludes the top of the complete Gen15 fan envelope")
	var safe_top := float(gen15_volcano.get("ceiling_y", 80.0)) + RunnerMotion.SIZE.y + 25.0
	_check(not CoinPlanner._position_blocked(float(gen15_volcano.x), safe_top, manifest.get("events")), "the fan exclusion still leaves the ceiling coin route available")
	var isolated_fan_manifest: Resource = _isolated_manifest(manifest, gen15_volcano)
	var fan_world := WorldSimulation.new()
	_check(str(fan_world.configure(isolated_fan_manifest)).is_empty(), "Gen15 fan event validates in the real shared MP world model")
	var representative: Dictionary = fan.front() if not fan.is_empty() else {}
	if not representative.is_empty():
		var center: Vector2 = Vector2(float(representative.x), float(representative.y))
		var runner := {"world_x": center.x, "y": center.y, "gravity_direction": 1}
		fan_world.tick = start_tick + 20
		_check(str(fan_world.player_contact(runner).get("reason", "")) == "lava_projectile", "Gen15 projectile collision reaches the authoritative shared ledger contact path")
	_check(_simulate_gen15_invalid_manifest(manifest, gen15_volcano), "validator rejects malformed or ceiling-unsafe Gen15 fan payloads")
	_check(_simulate_gen15_unsupported_ceiling(manifest, gen15_volcano), "manifest validator rejects a ceiling gap placed inside the fan's full x envelope")
	_test_direct_contact(manifest, gen15_volcano, "lava_projectile")
	_test_generated_manifest_route(manifest, gen15_volcano, true)
	var crack_result: Dictionary = Builder.new().build(100000014, 45000, 15)
	var gen15_crack: Dictionary = {}
	if crack_result.get("manifest") != null:
		for event in crack_result.manifest.get("events"):
			if str(event.get("kind", "")) == "lava_crack":
				gen15_crack = event
				break
	_check(not gen15_crack.is_empty(), "separate Gen15 seed supplies a crack for width/collision testing")
	if not gen15_crack.is_empty():
		_check(float(gen15_crack.get("width", 0.0)) >= 150.0 and float(gen15_crack.get("width", 0.0)) <= 180.0, "Gen15 crack has its versioned widened collision footprint")
		_check(int(gen15_crack.get("lava_crack_revision", 0)) == 1 and float(gen15_crack.get("visual_depth", 0.0)) >= 24.0, "Gen15 crack has versioned branch depth decoration")
		_test_direct_contact(crack_result.manifest, gen15_crack, "lava_crack")
		_test_generated_manifest_route(crack_result.manifest, gen15_crack, not bool(gen15_crack.get("from_ceiling", false)))

func _test_gen15_volcano_cohort() -> void:
	var seeds: Array[int] = [100000020, 100000034, 100000043]
	var total_coins := 0
	var total_risk_rows := 0
	var total_volcanoes := 0
	var total_cracks := 0
	for seed_value in seeds:
		var built: Dictionary = Builder.new().build(seed_value, 45000, 15)
		_check(built.get("manifest") != null, "Gen15 route cohort seed %d builds" % seed_value)
		if built.get("manifest") == null:
			continue
		var manifest: Resource = built.manifest
		total_coins += manifest.collectibles.size()
		for coin in manifest.collectibles:
			if str(coin.get("formation", "")) == "risk":
				total_risk_rows += 1
		var volcanoes: Array[Dictionary] = []
		for event in manifest.events:
			if str(event.get("kind", "")) == "lava_crack":
				total_cracks += 1
			if str(event.get("kind", "")) == "volcano":
				volcanoes.append(event)
		total_volcanoes += volcanoes.size()
		_check(not volcanoes.is_empty(), "cohort seed %d has generated Gen15 volcanoes to verify" % seed_value)
		for volcano in volcanoes:
			_check(_gen15_fan_has_supported_ceiling(manifest, volcano), "seed %d volcano %s keeps the full fan corridor over supported ceiling terrain" % [seed_value, str(volcano.get("event_id", ""))])
			_test_generated_manifest_route(manifest, volcano, true)
		print("GEN15_COHORT_SEED seed=%d coins=%d risk_rows=%d cracks=%d volcanoes=%d" % [seed_value, manifest.collectibles.size(), _count_risk_rows(manifest), _count_events(manifest, "lava_crack"), volcanoes.size()])
	_check(total_volcanoes >= 4, "targeted cohort exercises multiple generated volcanoes rather than one fixture")
	print("GEN15_ROUTE_COHORT seeds=%s coins=%d risk_rows=%d cracks=%d volcanoes=%d route_speeds=250,500,750" % [str(seeds), total_coins, total_risk_rows, total_cracks, total_volcanoes])

func _test_gen15_unsafe_volcano_filtering() -> void:
	var source_manifest: Resource
	var volcano: Dictionary = {}
	for seed_value in [100000034, 100000043, 100000020]:
		var built: Dictionary = Builder.new().build(int(seed_value), 45000, 15)
		if built.get("manifest") == null:
			continue
		var candidate: Resource = built.manifest
		for event in candidate.get("events"):
			if str(event.get("kind", "")) == "volcano":
				source_manifest = candidate
				volcano = event
				break
		if not volcano.is_empty():
			break
	_check(not volcano.is_empty(), "unsafe-volcano filtering fixture has a normal generated Gen15 event")
	if volcano.is_empty():
		return
	var events: Array[Dictionary] = source_manifest.get("events").duplicate(true)
	var original_volcano_count := _count_events(source_manifest, "volcano")
	var envelope: Rect2 = LavaModel.volcano_collision_envelope(volcano)
	# Put a one-pixel ceiling gap between the old validator's 8px support samples.
	var gap_x := envelope.position.x + 4.0
	events.append({"event_id": "fixture_one_pixel_roof_gap", "kind": "gap", "x": gap_x, "width": 1.0, "from_ceiling": true, "blocked_lanes": CourseGenerator.CEILING_LANE})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("x", 0.0)) < float(b.get("x", 0.0)))
	var surface_index := preload("res://systems/course_surface_index.gd").new()
	surface_index.configure(events, float(source_manifest.get("initial_floor_y")), float(source_manifest.get("initial_ceiling_y")))
	_check(not LavaModel.gen15_ceiling_route_is_supported(volcano, surface_index, float(source_manifest.get("start_x"))), "analytic full-envelope support check catches a 1px gap between former 8px samples")
	var eruption_tick := LavaModel.eruption_start_tick(volcano, float(source_manifest.get("start_x")))
	var apex_projectiles: Array[Dictionary] = LavaModel.projectiles_at(volcano, float(source_manifest.get("start_x")), float(eruption_tick + 32))
	var apex_projectile: Dictionary = {}
	for projectile in apex_projectiles:
		if int(projectile.get("arc_index", -1)) == 2 and int(projectile.get("direction", 0)) > 0:
			apex_projectile = projectile
			break
	_check(not apex_projectile.is_empty(), "step-margin fixture locates the outer high arc")
	var step_index_x := -1.0
	if not apex_projectile.is_empty():
		var step_events: Array[Dictionary] = source_manifest.get("events").duplicate(true)
		var target_step_x := float(apex_projectile.get("x", 0.0))
		step_index_x = envelope.position.x + floorf((target_step_x - envelope.position.x - 4.0) / 8.0) * 8.0 + 4.0
		var prior_step_index := preload("res://systems/course_surface_index.gd").new()
		prior_step_index.configure(step_events, float(source_manifest.get("initial_floor_y")), float(source_manifest.get("initial_ceiling_y")))
		var start_step_y := float(prior_step_index.surface_at(step_index_x - 0.01, true).get("y", 80.0))
		step_events.append({"event_id": "fixture_one_pixel_step", "kind": "step", "x": step_index_x, "start_y": start_step_y, "end_y": 220.0, "from_ceiling": true, "spiked": false})
		var step_surface_index := preload("res://systems/course_surface_index.gd").new()
		step_surface_index.configure(step_events, float(source_manifest.get("initial_floor_y")), float(source_manifest.get("initial_ceiling_y")))
		_check(not LavaModel.gen15_ceiling_route_is_supported(volcano, step_surface_index, float(source_manifest.get("start_x"))), "exact fan trajectory/boundary test catches a narrow unsafe roof step between old 8px samples")
		var high_arc := LavaModel.gen15_fan_arcs()[2]
		var apex_age := float(high_arc.get("vertical_speed", 0.0)) / float(high_arc.get("gravity", 1.0))
		var source_y := float(volcano.get("floor_y", 460.0)) - float(volcano.get("height", 76.0)) * 0.78
		var arc_origin_x := float(volcano.get("x", 0.0)) + float(volcano.get("width", 116.0)) * 0.12
		var arc_vx := float(high_arc.get("horizontal_speed", 0.0))
		var arc_radius := float(high_arc.get("radius", 0.0))
		var apex_x := arc_origin_x + arc_vx * apex_age
		var plateau_half_width := 60.0
		var expanded_span := arc_radius + RunnerMotion.SIZE.x * 0.5
		var plateau_y := envelope.position.y - RunnerMotion.SIZE.y - 24.0 + 1.0
		var required_top := plateau_y + RunnerMotion.SIZE.y + 24.0
		var entry_age := (apex_x - plateau_half_width - expanded_span - arc_origin_x) / arc_vx
		var exit_age := (apex_x + plateau_half_width + expanded_span - arc_origin_x) / arc_vx
		var entry_top := source_y - float(high_arc.get("vertical_speed", 0.0)) * entry_age + 0.5 * float(high_arc.get("gravity", 1.0)) * entry_age * entry_age - arc_radius
		var exit_top := source_y - float(high_arc.get("vertical_speed", 0.0)) * exit_age + 0.5 * float(high_arc.get("gravity", 1.0)) * exit_age * exit_age - arc_radius
		_check(entry_top >= required_top and exit_top >= required_top and envelope.position.y < required_top, "low-roof plateau fixture is safe at both swept boundaries but unsafe at the ballistic interior apex")
		var plateau_events: Array[Dictionary] = source_manifest.get("events").duplicate(true)
		var plateau_start := apex_x - plateau_half_width
		var plateau_end := apex_x + plateau_half_width
		var plateau_base_y := float(prior_step_index.surface_at(plateau_start - 0.01, true).get("y", 80.0))
		plateau_events.append({"event_id": "fixture_apex_plateau_enter", "kind": "step", "x": plateau_start, "start_y": plateau_base_y, "end_y": plateau_y, "from_ceiling": true, "spiked": false})
		plateau_events.append({"event_id": "fixture_apex_plateau_exit", "kind": "step", "x": plateau_end, "start_y": plateau_y, "end_y": plateau_base_y, "from_ceiling": true, "spiked": false})
		var plateau_surface_index := preload("res://systems/course_surface_index.gd").new()
		plateau_surface_index.configure(plateau_events, float(source_manifest.get("initial_floor_y")), float(source_manifest.get("initial_ceiling_y")))
		_check(not LavaModel.gen15_ceiling_route_is_supported(volcano, plateau_surface_index, float(source_manifest.get("start_x"))), "continuous apex envelope rejects a plateau whose edge-only ballistic samples are safe")
	var malformed_manifest: Resource = source_manifest.duplicate(true)
	malformed_manifest.set("events", events)
	malformed_manifest.set("manifest_hash", malformed_manifest.call("calculate_hash"))
	_check(not str(malformed_manifest.call("validate")).is_empty(), "manifest validator remains a defense against the unsafe side gap")
	var builder := Builder.new()
	var filtered: Array[Dictionary] = builder.filter_unsafe_gen15_volcanoes(events, float(source_manifest.get("start_x")))
	var volcano_count := 0
	var gap_preserved := false
	for event in filtered:
		if str(event.get("kind", "")) == "volcano":
			volcano_count += 1
		if str(event.get("event_id", "")) == "fixture_one_pixel_roof_gap":
			gap_preserved = true
	_check(volcano_count == original_volcano_count - 1 and gap_preserved, "Gen15 builder filtering drops only the unsafe volcano while retaining terrain and other volcanoes")
	var replanned_coins: Array[Dictionary] = CoinPlanner.plan(int(source_manifest.get("seed_value")), float(source_manifest.get("start_x")), float(source_manifest.get("finish_x")), filtered, float(source_manifest.get("initial_floor_y")), float(source_manifest.get("initial_ceiling_y")), 2, 1.55)
	_check(not replanned_coins.is_empty(), "coin catalog can be planned against the filtered event set instead of failing the whole build")
	for coin in replanned_coins:
		_check(str(coin.get("risk_event_id", "")) != str(volcano.get("event_id", "")), "filtered coin catalog does not retain a risk-row reference to the dropped volcano")
	print("GEN15_UNSAFE_FILTER seed=%d event=%s gap_x=%.2f gap_width=1.0 narrow_step_x=%.2f volcanoes=%d->%d replanned_coins=%d" % [int(source_manifest.get("seed_value")), str(volcano.get("event_id", "")), gap_x, step_index_x if not apex_projectile.is_empty() else -1.0, original_volcano_count, volcano_count, replanned_coins.size()])

func _gen15_fan_has_supported_ceiling(manifest: Resource, volcano: Dictionary) -> bool:
	var world := WorldSimulation.new()
	if not str(world.configure(manifest)).is_empty():
		return false
	return LavaModel.gen15_ceiling_route_is_supported(volcano, world._surface_index, float(manifest.get("start_x")))

func _simulate_gen15_unsupported_ceiling(source: Resource, volcano: Dictionary) -> bool:
	var malformed: Resource = source.duplicate(true)
	var events: Array[Dictionary] = malformed.get("events").duplicate(true)
	var envelope: Rect2 = LavaModel.volcano_collision_envelope(volcano)
	var gap_x := float(volcano.get("x", 0.0)) + 24.0
	if gap_x < envelope.position.x or gap_x > envelope.end.x:
		gap_x = envelope.get_center().x
	events.append({"event_id": "review_fixture_ceiling_gap", "kind": "gap", "x": gap_x, "width": 80.0, "from_ceiling": true, "blocked_lanes": 2})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("x", 0.0)) < float(b.get("x", 0.0)))
	malformed.set("events", events)
	malformed.set("manifest_hash", malformed.call("calculate_hash"))
	return not str(malformed.call("validate")).is_empty()

func _count_risk_rows(manifest: Resource) -> int:
	var count := 0
	for coin in manifest.collectibles:
		if str(coin.get("formation", "")) == "risk":
			count += 1
	return count

func _count_events(manifest: Resource, kind: String) -> int:
	var count := 0
	for event in manifest.events:
		if str(event.get("kind", "")) == kind:
			count += 1
	return count

func _test_gen14_trajectory_freeze() -> void:
	var result: Dictionary = Builder.new().build(100000918, 45000, 14)
	_check(result.get("manifest") != null, "frozen Gen14 trajectory seed builds")
	if result.get("manifest") == null:
		return
	var manifest: Resource = result.manifest
	var volcano: Dictionary = {}
	for event in manifest.get("events"):
		if str(event.get("kind", "")) == "volcano":
			volcano = event
			break
	_check(not volcano.is_empty(), "frozen Gen14 seed retains its volcano")
	if volcano.is_empty():
		return
	_check(not volcano.has("projectile_fan_revision") and not volcano.has("projectile_arcs"), "Gen14 event payload stays on the original paired trajectory schema")
	var activation := LavaModel.eruption_start_tick(volcano, float(manifest.get("start_x")))
	var at_24: Array[Dictionary] = LavaModel.projectiles_at(volcano, float(manifest.get("start_x")), float(activation + 24))
	_check(activation == 2065 and at_24.size() == 2, "Gen14 frozen activation/two-projectile trajectory remains unchanged")
	if at_24.size() == 2:
		at_24.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("direction", 0)) < int(b.get("direction", 0)))
		_check(is_equal_approx(float(at_24[0].get("x", 0.0)), 19049.6593551168) and is_equal_approx(float(at_24[0].get("y", 0.0)), 336.72), "Gen14 left projectile remains at its frozen age-24 pose")
		_check(is_equal_approx(float(at_24[1].get("x", 0.0)), 19343.0779000387) and is_equal_approx(float(at_24[1].get("y", 0.0)), 336.72), "Gen14 right projectile remains at its frozen age-24 pose")

func _simulate_gen15_invalid_manifest(source: Resource, event: Dictionary) -> bool:
	var malformed: Resource = source.duplicate(true)
	var events: Array[Dictionary] = malformed.get("events")
	for index in range(events.size()):
		if str(events[index].get("event_id", "")) == str(event.get("event_id", "")):
			var bad_event := events[index].duplicate(true)
			var arcs: Array = bad_event.get("projectile_arcs", []).duplicate(true)
			if arcs.is_empty():
				return false
			(arcs[2] as Dictionary)["vertical_speed"] = 620.0
			(arcs[2] as Dictionary)["gravity"] = 900.0
			bad_event["projectile_arcs"] = arcs
			events[index] = bad_event
			break
	malformed.set("events", events)
	malformed.set("manifest_hash", malformed.call("calculate_hash"))
	return not str(malformed.call("validate")).is_empty()

func _test_direct_contact(source_manifest: Resource, event: Dictionary, expected_reason: String) -> void:
	var isolated := _isolated_manifest(source_manifest, event)
	var world := WorldSimulation.new()
	_check(str(world.configure(isolated)).is_empty(), "isolated shared lava event validates as MP world")
	var hazard := LavaScene.instantiate() as Node2D
	hazard.call("configure", event, float(source_manifest.get("start_x")))
	var center: Vector2
	var contact_tick := 0
	if str(event.get("kind", "")) == "lava_crack":
		var bounds: Rect2 = LavaModel.crack_rect(event)
		center = bounds.get_center()
	else:
		contact_tick = LavaModel.eruption_start_tick(event, float(source_manifest.get("start_x"))) + 20
		var projectiles: Array[Dictionary] = LavaModel.projectiles_at(event, float(source_manifest.get("start_x")), float(contact_tick))
		center = Vector2(float(projectiles[0].get("x", 0.0)), float(projectiles[0].get("y", 0.0)))
	world.tick = contact_tick
	hazard.call("apply_simulation_tick", float(contact_tick), float(source_manifest.get("start_x")))
	var player_rect := Rect2(center - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
	var player_state := {"world_x": center.x, "y": center.y, "gravity_direction": 1}
	var mp_contact: Dictionary = world.player_contact(player_state)
	_check(str(mp_contact.get("reason", "")) == expected_reason, "shared MP world detects exact %s contact" % expected_reason)
	_check(bool(hazard.call("is_lethal_at", player_rect, contact_tick, float(source_manifest.get("start_x")))), "SP shared scene detects the same exact %s contact" % expected_reason)
	var swept: Dictionary = world.first_static_terminal_contact(player_state, player_state)
	_check(str(swept.get("reason", "")) == expected_reason, "shared MP swept terminal path catches exact %s overlap" % expected_reason)
	if expected_reason == "lava_projectile":
		var before_tick := LavaModel.eruption_start_tick(event, float(source_manifest.get("start_x"))) - 1
		var early_projectile: Array[Dictionary] = LavaModel.projectiles_at(event, float(source_manifest.get("start_x")), float(before_tick))
		_check(early_projectile.is_empty(), "no projectile can cause contact before deterministic activation")
	hazard.free()

func _test_volcano_body_contact(source_manifest: Resource, event: Dictionary) -> void:
	var isolated := _isolated_manifest(source_manifest, event)
	var world := WorldSimulation.new()
	_check(str(world.configure(isolated)).is_empty(), "volcano body contact manifest validates")
	var hazard := LavaScene.instantiate() as Node2D
	hazard.call("configure", event, float(source_manifest.get("start_x")))
	var body_center := Vector2(float(event.x), float(event.floor_y) - float(event.height) * 0.83)
	var body_rect := Rect2(body_center - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
	var state := {"world_x": body_center.x, "y": body_center.y, "gravity_direction": 1}
	var contact: Dictionary = world.player_contact(state)
	_check(not contact.is_empty(), "the visually solid volcano body has an authoritative lethal contact")
	_check(bool(hazard.call("is_lethal_at", body_rect, 0, float(source_manifest.get("start_x")))), "SP uses the same visible volcano-body polygon as lethal geometry")
	hazard.free()

func _test_safe_route(source_manifest: Resource, event: Dictionary, safe_on_ceiling: bool) -> void:
	for speed in [250.0, 500.0, 750.0]:
		var isolated := _isolated_manifest(source_manifest, event)
		var world := WorldSimulation.new()
		if not str(world.configure(isolated)).is_empty():
			_check(false, "isolated route manifest validates")
			continue
		var start_x := float(isolated.get("start_x"))
		var event_distance := float(event.get("x", 0.0)) - start_x
		var route_start_distance := maxf(0.0, event_distance - 1500.0)
		var start_tick := floori(route_start_distance / speed * 60.0)
		world.tick = start_tick
		world.elapsed = float(start_tick) / 60.0
		var lane_direction := -1 if safe_on_ceiling else 1
		var initial_surface: Dictionary = world.surface_at(start_x + route_start_distance, false)
		var state := {"world_x": start_x + route_start_distance, "y": float(initial_surface.y) - RunnerMotion.SIZE.y * 0.5, "gravity_direction": 1, "vertical_speed": 0.0, "grounded": true, "cooldown": 0.0}
		var flipped := false
		var collision_seen := false
		var supported_through_zone := true
		var grounded_in_safe_lane := false
		for _frame in range(2000):
			var previous: Dictionary = state.duplicate(true)
			var distance := float(state.world_x) - start_x
			if not flipped and distance >= event_distance - 1100.0 and int(state.gravity_direction) != lane_direction:
				flipped = RunnerMotion.try_flip(state, lane_direction, 2.0)
			var floor_surface: Dictionary = world.surface_at(float(state.world_x), false)
			var ceiling_surface: Dictionary = world.surface_at(float(state.world_x), true)
			RunnerMotion.advance_vertical(state, 1.0 / 60.0, float(floor_surface.y), float(ceiling_surface.y), bool(floor_surface.supported), bool(ceiling_surface.supported))
			state.world_x = float(state.world_x) + speed / 60.0
			world.step_to(world.tick + 1)
			var proposed: Dictionary = state.duplicate(true)
			var lethal: Dictionary = world.first_static_terminal_contact(previous, proposed)
			if not lethal.is_empty():
				collision_seen = true
				break
			var current_distance := float(state.world_x) - start_x
			if current_distance >= event_distance - 500.0 and current_distance <= event_distance + 500.0:
				var chosen_surface: Dictionary = world.surface_at(float(state.world_x), safe_on_ceiling)
				if not bool(chosen_surface.get("supported", false)):
					supported_through_zone = false
				if current_distance >= event_distance - 100.0 and int(state.gravity_direction) == lane_direction and bool(state.grounded):
					grounded_in_safe_lane = true
			if current_distance > event_distance + 500.0:
				break
		_check(flipped or not safe_on_ceiling, "speed %.0f route performs its required early flip" % speed)
		_check(not collision_seen, "RunnerMotion speed %.0f passes the %s event without contact" % [speed, str(event.get("kind", ""))])
		_check(supported_through_zone, "safe lane stays supported around %s at speed %.0f" % [str(event.get("kind", "")), speed])
		if safe_on_ceiling:
			_check(grounded_in_safe_lane, "RunnerMotion speed %.0f reaches the supported ceiling before the hazard window" % speed)

func _test_generated_manifest_route(manifest: Resource, event: Dictionary, safe_on_ceiling: bool) -> void:
	# Keep every generated terrain/hazard in the world. This checks that the selected
	# lava route remains traversable in its real course context, not only in an isolated event fixture.
	for speed in [250.0, 500.0, 750.0]:
		# Start at run tick zero and let the manifest route advance at this speed;
		# volcano phase is observed, never injected at a teleported position.
		var phase_offsets: Array[int] = [0]
		var saw_active_projectile := false
		for phase_offset in phase_offsets:
			var result := _simulate_full_manifest_route(manifest, event, speed, safe_on_ceiling, phase_offset)
			var contact_phase := int(result.get("terminal_tick", -1)) - int(result.get("eruption_tick", -1)) if int(result.get("terminal_tick", -1)) >= 0 else int(result.get("passage_phase", -1))
			var context := "event=%s seed=%d x=%.0f speed=%.0f phase_offset=%d eruption_tick=%d passage_tick=%d passage_phase=%d contact_phase=%d hit=%s hit_event=%s tick=%d xhit=%.1f pose=%s support=%s" % [str(event.get("event_id", "")), int(manifest.seed_value), float(event.get("x", 0.0)), speed, phase_offset, int(result.get("eruption_tick", -1)), int(result.get("passage_tick", -1)), int(result.get("passage_phase", -1)), contact_phase, str(result.get("contact_reason", "")), str(result.get("terminal_event_id", "")), int(result.get("terminal_tick", -1)), float(result.get("terminal_x", -1.0)), str(result.get("terminal_pose", {})), str(result.get("terminal_support", result.get("passage_support", {})))]
			if int(manifest.get("generator_version")) >= 15 and str(event.get("kind", "")) == "volcano":
				print("GEN15_ROUTE seed=%d event=%s event_x=%.1f speed=%.0f first_contact=%s passage_x=%.1f passage_tick=%d eruption_tick=%d phase=%d support=%s projectiles_seen=%s" % [int(manifest.seed_value), str(event.get("event_id", "")), float(event.get("x", 0.0)), speed, str(result.get("contact_reason", "none")) if not bool(result.get("escaped", false)) else "none", float(result.get("passage_x", -1.0)), int(result.get("passage_tick", -1)), int(result.get("eruption_tick", -1)), int(result.get("passage_phase", -1)), str(result.get("passage_support", result.get("terminal_support", {}))), str(result.get("projectile_seen", false))])
			_check(bool(result.get("entered_safe_lane", false)) or not safe_on_ceiling, "full-manifest route reaches the selected ceiling lane: " + context)
			_check(bool(result.get("escaped", false)) and bool(result.get("reached_past_event", false)), "full manifest route survives: " + context)
			_check(bool(result.get("supported", false)), "full route reaches actual safe support: " + context)
			saw_active_projectile = saw_active_projectile or bool(result.get("projectile_seen", false))
		if str(event.get("kind", "")) == "volcano" and speed <= 500.0:
			_check(saw_active_projectile, "natural round timeline reaches an active generated eruption at this speed")

func _simulate_full_manifest_route(manifest: Resource, event: Dictionary, speed: float, safe_on_ceiling: bool, phase_offset: int) -> Dictionary:
	var world := WorldSimulation.new()
	if not str(world.configure(manifest)).is_empty():
		return {"escaped": false}
	var start_x := float(manifest.get("start_x"))
	var event_x := float(event.get("x", 0.0))
	var eruption_tick := LavaModel.eruption_start_tick(event, start_x) if str(event.get("kind", "")) == "volcano" else 0
	world.tick = 0
	world.elapsed = 0.0
	var start_x_player := start_x + 220.0
	var safe_lane := -1 if safe_on_ceiling else 1
	var initial_surface: Dictionary = world.surface_at(start_x_player, false)
	if not bool(initial_surface.get("supported", false)):
		return {"escaped": false, "contact_reason": "unsupported_approach_lane", "terminal_x": start_x_player, "terminal_tick": world.tick, "terminal_support": {"approach": initial_surface}}
	var state := {"world_x": start_x_player, "y": float(initial_surface.y) - RunnerMotion.SIZE.y * 0.5, "gravity_direction": 1, "vertical_speed": 0.0, "grounded": true, "cooldown": 0.0}
	var switch_plan := _manifest_lane_switches(manifest, speed)
	var switch_index := 0
	var entered_safe_lane := not safe_on_ceiling
	var escaped := true
	var supported := false
	var reached_past_event := false
	var projectile_seen := false
	var terminal_reason := ""
	var terminal_event_id := ""
	var terminal_tick := -1
	var terminal_x := -1.0
	var terminal_support: Dictionary = {}
	var terminal_pose: Dictionary = {}
	var passage_tick := -1
	var passage_phase := -1
	var passage_x := -1.0
	var passage_support: Dictionary = {}
	var max_frames := mini(20000, ceili((event_x + 320.0 - start_x_player) / speed * 60.0) + 60)
	for _frame in range(max_frames):
		var previous: Dictionary = state.duplicate(true)
		while switch_index < switch_plan.size() and float(state.world_x) >= float(switch_plan[switch_index].get("request_x", 0.0)):
			var requested_lane_mask := int(switch_plan[switch_index].get("lane", 1))
			var requested_direction := -1 if requested_lane_mask == 2 else 1
			if int(state.gravity_direction) == requested_direction:
				switch_index += 1
				continue
			if RunnerMotion.try_flip(state, requested_direction):
				switch_index += 1
				if requested_direction == safe_lane:
					entered_safe_lane = true
			else:
				break
		var floor_surface: Dictionary = world.surface_at(float(state.world_x), false)
		var ceiling_surface: Dictionary = world.surface_at(float(state.world_x), true)
		RunnerMotion.advance_vertical(state, 1.0 / 60.0, float(floor_surface.y), float(ceiling_surface.y), bool(floor_surface.supported), bool(ceiling_surface.supported))
		state.world_x = float(state.world_x) + speed / 60.0
		world.step_to(world.tick + 1)
		var lethal: Dictionary = world.first_static_terminal_contact(previous, state)
		if not lethal.is_empty():
			escaped = false
			terminal_reason = str(lethal.get("reason", "unknown"))
			terminal_event_id = str(lethal.get("event_id", ""))
			terminal_tick = world.tick
			terminal_x = float(state.get("world_x", -1.0))
			terminal_support = {"floor": world.surface_at(terminal_x, false), "ceiling": world.surface_at(terminal_x, true)}
			terminal_pose = {"y": float(state.get("y", 0.0)), "gravity": int(state.get("gravity_direction", 0)), "grounded": bool(state.get("grounded", false)), "cooldown": float(state.get("cooldown", 0.0)), "pending_switch": switch_plan[switch_index] if switch_index < switch_plan.size() else {}}
			break
		if str(event.get("kind", "")) == "volcano" and float(state.world_x) >= event_x - 160.0 and float(state.world_x) <= event_x + 280.0:
			projectile_seen = projectile_seen or not LavaModel.projectiles_at(event, start_x, float(world.tick)).is_empty()
		if float(state.world_x) >= event_x - 160.0 and float(state.world_x) <= event_x + 280.0:
			var safe_surface: Dictionary = world.surface_at(float(state.world_x), safe_on_ceiling)
			if passage_tick < 0:
				passage_tick = world.tick
				passage_phase = world.tick - eruption_tick
				passage_x = float(state.world_x)
				passage_support = {"floor": world.surface_at(float(state.world_x), false), "ceiling": world.surface_at(float(state.world_x), true)}
			if bool(safe_surface.get("supported", false)) and int(state.gravity_direction) == safe_lane and bool(state.grounded):
				supported = true
		if float(state.world_x) > event_x + 280.0:
			reached_past_event = true
			break
	return {"entered_safe_lane": entered_safe_lane, "escaped": escaped, "supported": supported, "reached_past_event": reached_past_event, "projectile_seen": projectile_seen, "contact_reason": terminal_reason, "terminal_event_id": terminal_event_id, "terminal_tick": terminal_tick, "terminal_x": terminal_x, "terminal_support": terminal_support, "terminal_pose": terminal_pose if not escaped else {}, "passage_x": passage_x, "passage_tick": passage_tick, "passage_phase": passage_phase, "passage_support": passage_support, "approach_x": start_x_player, "eruption_tick": eruption_tick}

func _manifest_lane_switches(manifest: Resource, speed: float) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var configured_generator := CourseGenerator.new()
	var profiles: Array = configured_generator.get_profile_catalog(int(manifest.generator_version))
	for profile in profiles:
		profile.spawn_lead_distance = CourseGenerator.EVENT_SPAWN_LEAD_DISTANCE
	for event in manifest.events:
		var profile: Variant = null
		for candidate in profiles:
			if str(candidate.event_kind) == str(event.get("kind", "")):
				profile = candidate
				break
		if profile == null:
			continue
		var forecast_event: Dictionary = event.duplicate(true)
		forecast_event["course_distance"] = float(event.get("x", 0.0))
		forecast_event["spiked_step"] = bool(event.get("spiked", false))
		var kind := str(event.get("kind", ""))
		var from_ceiling := bool(event.get("from_ceiling", false))
		forecast_event["blocked_lanes"] = int(event.get("blocked_lanes", 2 if from_ceiling else 1))
		forecast_event["motion_speed_multiplier"] = float(event.get("motion_speed_multiplier", 1.0))
		if not forecast_event.has("width"):
			match kind:
				"spikes": forecast_event["width"] = float(maxi(int(event.get("count", 1)) - 1, 0) * int(round(float(event.get("spacing", 32.0)))) + 28)
				"step": forecast_event["width"] = 240.0 if bool(event.get("spiked", false)) else 36.0
				"slope": forecast_event["width"] = maxf(float(event.get("end_x", 0.0)) - float(event.get("start_x", 0.0)), 36.0)
				_: forecast_event["width"] = 90.0
		var event_threats: Array[Dictionary] = profile.build_threat_intervals(forecast_event)
		for threat_value in event_threats:
			if not threat_value is Dictionary:
				continue
			var threat: Dictionary = threat_value
			var begin := float(threat.get("start", 0.0))
			var finish := float(threat.get("end", begin))
			var mask := int(threat.get("blocked_lanes", 0)) & 3
			if finish <= begin or mask == 0:
				continue
			edges.append({"x": begin, "floor_delta": 1 if mask & 1 else 0, "ceiling_delta": 1 if mask & 2 else 0, "clearance": float(threat.get("switch_clearance", 0.0))})
			edges.append({"x": finish, "floor_delta": -1 if mask & 1 else 0, "ceiling_delta": -1 if mask & 2 else 0, "clearance": 0.0})
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
	var clearance := float(CourseGenerator.new().get_switch_clearance_distance(speed, float(manifest.world_height)))
	var result: Array[Dictionary] = []
	var floor_count := 0
	var ceiling_count := 0
	var current_lane := 1
	var index := 0
	while index < edges.size() - 1:
		var x := float(edges[index].x)
		var local_clearance := clearance
		while index < edges.size() and is_equal_approx(float(edges[index].x), x):
			floor_count += int(edges[index].floor_delta)
			ceiling_count += int(edges[index].ceiling_delta)
			local_clearance = maxf(local_clearance, float(edges[index].clearance))
			index += 1
		if index >= edges.size():
			break
		var blocked := (1 if floor_count > 0 else 0) | (2 if ceiling_count > 0 else 0)
		if blocked == 0 or blocked == 3:
			continue
		var required_lane := 2 if blocked & 1 else 1
		if required_lane != current_lane:
			result.append({"request_x": x - local_clearance, "lane": required_lane})
			current_lane = required_lane
	return result

func _isolated_manifest(source: Resource, event: Dictionary) -> Resource:
	var manifest := ManifestScript.new() as Resource
	for key in ["protocol_version", "generator_version", "match_rules_version", "course_identity", "seed_value", "course_length_px", "world_width", "world_height", "start_x", "finish_x", "initial_floor_y", "initial_ceiling_y", "ruleset_fingerprint"]:
		manifest.set(key, source.get(key))
	manifest.set("manifest_version", source.get("manifest_version"))
	var events: Array[Dictionary] = [event.duplicate(true)]
	manifest.set("events", events)
	manifest.set("collectibles", [])
	manifest.set("manifest_hash", manifest.call("calculate_hash"))
	_check(str(manifest.call("validate")).is_empty(), "isolated event manifest remains valid")
	return manifest

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
