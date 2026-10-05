extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const LavaScene := preload("res://hazards/lava_hazard.tscn")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
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
	print("LAVA_SHARED_WORLD_TEST failures=%d volcano=%s crack=%s" % [failures, str(volcano.get("event_id", "")), str(crack.get("event_id", ""))])
	presentation.queue_free()
	get_tree().quit(1 if failures > 0 else 0)

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
		var phase_offsets: Array[int] = [0]
		if str(event.get("kind", "")) == "volcano":
			var period := maxi(int(event.get("eruption_period_ticks", 156)), 1)
			var lifetime := maxi(int(event.get("projectile_lifetime_ticks", 58)), 1)
			phase_offsets = [0, 1, maxi(lifetime / 2, 1), maxi(lifetime - 1, 1), lifetime, period / 2, period - 1]
			phase_offsets.sort()
			for index in range(phase_offsets.size() - 1, 0, -1):
				if phase_offsets[index] == phase_offsets[index - 1]:
					phase_offsets.remove_at(index)
		var saw_active_projectile := false
		for phase_offset in phase_offsets:
			var result := _simulate_full_manifest_route(manifest, event, speed, safe_on_ceiling, phase_offset)
			_check(bool(result.get("flipped", false)) or not safe_on_ceiling, "full route at %.0f px/s makes required lane change in eruption phase %d" % [speed, phase_offset])
			_check(bool(result.get("escaped", false)) and bool(result.get("reached_past_event", false)), "full manifest route at %.0f px/s survives eruption phase %d" % [speed, phase_offset])
			_check(bool(result.get("supported", false)), "full route at %.0f px/s reaches actual safe support in eruption phase %d" % [speed, phase_offset])
			saw_active_projectile = saw_active_projectile or bool(result.get("projectile_seen", false))
		if str(event.get("kind", "")) == "volcano":
			_check(saw_active_projectile, "the generated full-manifest route is exercised while at least one actual eruption is active")

func _simulate_full_manifest_route(manifest: Resource, event: Dictionary, speed: float, safe_on_ceiling: bool, phase_offset: int) -> Dictionary:
	var world := WorldSimulation.new()
	if not str(world.configure(manifest)).is_empty():
		return {"escaped": false}
	var start_x := float(manifest.get("start_x"))
	var event_x := float(event.get("x", 0.0))
	var start_x_player := maxf(start_x + 220.0, event_x - 1450.0)
	var travel_ticks_to_event := roundi((event_x - start_x_player) / speed * 60.0)
	var eruption_tick := LavaModel.eruption_start_tick(event, start_x) if str(event.get("kind", "")) == "volcano" else 0
	var initial_tick := maxi(0, eruption_tick - travel_ticks_to_event + phase_offset)
	world.tick = initial_tick
	world.elapsed = float(initial_tick) / 60.0
	var initial_floor: Dictionary = world.surface_at(start_x_player, false)
	var state := {"world_x": start_x_player, "y": float(initial_floor.y) - RunnerMotion.SIZE.y * 0.5, "gravity_direction": 1, "vertical_speed": 0.0, "grounded": true, "cooldown": 0.0}
	var safe_lane := -1 if safe_on_ceiling else 1
	var flipped := false
	var escaped := true
	var supported := false
	var reached_past_event := false
	var projectile_seen := false
	for _frame in range(720):
		var previous: Dictionary = state.duplicate(true)
		if not flipped and int(state.gravity_direction) != safe_lane and float(state.world_x) >= event_x - 1050.0:
			flipped = RunnerMotion.try_flip(state, safe_lane, 2.0)
		var floor_surface: Dictionary = world.surface_at(float(state.world_x), false)
		var ceiling_surface: Dictionary = world.surface_at(float(state.world_x), true)
		RunnerMotion.advance_vertical(state, 1.0 / 60.0, float(floor_surface.y), float(ceiling_surface.y), bool(floor_surface.supported), bool(ceiling_surface.supported))
		state.world_x = float(state.world_x) + speed / 60.0
		world.step_to(world.tick + 1)
		var lethal: Dictionary = world.first_static_terminal_contact(previous, state)
		if not lethal.is_empty():
			escaped = false
			break
		if str(event.get("kind", "")) == "volcano" and float(state.world_x) >= event_x - 160.0 and float(state.world_x) <= event_x + 280.0:
			projectile_seen = projectile_seen or not LavaModel.projectiles_at(event, start_x, float(world.tick)).is_empty()
		if float(state.world_x) >= event_x - 160.0 and float(state.world_x) <= event_x + 280.0:
			var safe_surface: Dictionary = world.surface_at(float(state.world_x), safe_on_ceiling)
			if bool(safe_surface.get("supported", false)) and int(state.gravity_direction) == safe_lane and bool(state.grounded):
				supported = true
		if float(state.world_x) > event_x + 280.0:
			reached_past_event = true
			break
	return {"flipped": flipped, "escaped": escaped, "supported": supported, "reached_past_event": reached_past_event, "projectile_seen": projectile_seen}

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
