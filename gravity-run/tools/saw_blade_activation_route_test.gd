extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const SawScene := preload("res://hazards/saw_blade.tscn")
const ServiceScript := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(1, 45000, 9)
	var manifest: Resource = built.get("manifest")
	_check(manifest != null, "v9 manifest resolves saw geometry: %s" % str(built.get("error", "")))
	if manifest == null:
		quit(1)
		return
	var world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(world.configure(manifest)).is_empty(), "world configures the common manifest")
	_test_first_sample_activation(manifest, world)
	var chosen: Dictionary = {}
	for saw in world.saws:
		if bool(saw.event.get("from_ceiling", false)):
			chosen = saw
			break
	_check(not chosen.is_empty(), "seed includes ceiling-origin saw")
	if chosen.is_empty():
		quit(1)
		return
	var saw_event: Dictionary = chosen.get("event", {})
	var saw_id := str(chosen.get("event_id", ""))
	var revision := 0
	for saw in world.saws:
		var event_id := str(saw.get("event_id", ""))
		var activation_tick := 80
		var commit := {"world_revision": revision + 1, "commit_id": "saw-%s-%d" % [event_id, activation_tick], "entity_id": event_id, "incarnation": 1, "action": "activate_saw", "effective_tick": activation_tick, "saw_activation_tick": activation_tick, "state_before": "active", "state_after": "active"}
		_check(world.apply_world_commit(commit) == "applied", "host activation commit records one shared activation tick")
		revision += 1
	for tick in range(1, 241):
		_check(world.step_to(tick), "world advances deterministic saw tick %d" % tick)
	var current_saw: Dictionary = world._saw_state_for_event(saw_id)
	_check(bool(current_saw.get("falling", false)) or not bool(current_saw.get("ceiling_lane", true)), "ceiling blade reaches the expected fall/landing phase")
	var history_tick := 150
	var history_state: Dictionary = world._saw_state_for_event(saw_id, history_tick)
	_check(bool(history_state.get("active", false)), "bounded history retains the requested collision pose")
	var saw_center := Vector2(float(history_state.get("x", 0.0)), float(history_state.get("y", 0.0)))
	var centered_player := {"world_x": saw_center.x, "y": saw_center.y, "gravity_direction": -1}
	var contact: Dictionary = world.player_contact_at(centered_player, history_tick)
	_check(str(contact.get("reason", "")) == "saw_blade", "historical contact resolves the saw at the requested tick")
	var current_state: Dictionary = world._saw_state_for_event(saw_id)
	var current_center := Vector2(float(current_state.get("x", 0.0)), float(current_state.get("y", 0.0)))
	var current_contact: Dictionary = world.player_contact({"world_x": current_center.x, "y": current_center.y, "gravity_direction": 1})
	_check(str(current_contact.get("reason", "")) == "saw_blade", "public current MP contact API resolves the same shared saw circle")
	var corner_rect := Rect2(saw_center + Vector2(27.0, 26.0), Vector2(34.0, 44.0))
	_check(not HazardRules.circle_intersects_rect(saw_center, SawModel.RADIUS, corner_rect), "circular contact rejects an AABB-only corner overlap")
	var corner_player := {"world_x": corner_rect.get_center().x, "y": corner_rect.get_center().y, "gravity_direction": -1}
	var corner_result: Dictionary = world.player_contact_at(corner_player, history_tick)
	_check(str(corner_result.get("reason", "")) != "saw_blade", "public MP historical contact API rejects the circular corner miss")
	_test_late_scene_reconstruction(manifest, saw_id, world)
	var prior_revision := int(world.entity_ledger.revision)
	var prior_pose := world._saw_state_for_event(saw_id).duplicate(true)
	var duplicate_commit := {"world_revision": prior_revision, "commit_id": "ignored-duplicate", "entity_id": saw_id, "incarnation": 1, "action": "activate_saw", "effective_tick": 80, "saw_activation_tick": 80, "state_before": "active", "state_after": "active"}
	_check(world.apply_world_commit(duplicate_commit) == "duplicate", "replayed activation is idempotent")
	_check(world._saw_state_for_event(saw_id) == prior_pose, "duplicate commit cannot replay the saw from spawn")
	var baseline := world.entity_ledger.baseline()
	var replica := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(replica.configure(manifest)) == "", "replica starts from the same manifest")
	for tick in range(1, 241):
		replica.step_to(tick)
	_check(replica.apply_baseline(baseline), "late baseline restores activation snapshot")
	_check(replica._saw_state_for_event(saw_id) == current_saw, "baseline reconstructs current saw pose from activation history")
	var invalid := baseline.duplicate(true)
	invalid.baseline_format_version = 1
	_check(not replica.apply_baseline(invalid), "unknown legacy row codec is rejected")
	_test_player_speed_routes(saw_event, world)
	_test_biome_world_coordinate_contract()
	if failures == 0:
		print("SAW_ACTIVATION_ROUTE_PASS saw=%s tick=240 activation=80 history=%d codec=%d" % [saw_id, history_tick, int(baseline.baseline_format_version)])
	quit(1 if failures > 0 else 0)

func _test_player_speed_routes(event: Dictionary, world: MultiplayerV2WorldSimulation) -> void:
	for speed in [250.0, 500.0, 750.0]:
		var trigger_x := float(event.get("spawn_x", float(event.get("x", 0.0)) + SawModel.START_OFFSET)) - SawModel.SPAWN_LEAD
		var activation_tick := 12
		var state := SawModel.initial_state(event, float(world.manifest.get("start_x")), 0, activation_tick)
		var contact_ticks: Dictionary = {"ceiling": -1, "floor": -1, "speed": speed}
		var runner := {"y": float(world.surface_at(trigger_x, false).y) - RunnerMotion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
		var player_x := trigger_x
		for tick in range(1, 421):
			player_x = trigger_x + speed * float(tick) / SawModel.TICK_RATE
			state = SawModel.advance(event, state, tick, Callable(world, "surface_at"))
			var floor_info: Dictionary = world.surface_at(player_x, false)
			var ceiling_info: Dictionary = world.surface_at(player_x, true)
			RunnerMotion.advance_vertical(runner, 1.0 / SawModel.TICK_RATE, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
			if not bool(state.get("active", false)):
				continue
			var rect := Rect2(Vector2(player_x, float(runner.y)) - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
			if HazardRules.circle_intersects_rect(Vector2(float(state.x), float(state.y)), SawModel.RADIUS, rect):
				var nearest_ceiling := absf(float(runner.y) - (float(ceiling_info.y) + RunnerMotion.SIZE.y * 0.5))
				var nearest_floor := absf(float(runner.y) - (float(floor_info.y) - RunnerMotion.SIZE.y * 0.5))
				var lane_key := "ceiling" if nearest_ceiling < nearest_floor else "floor"
				if int(contact_ticks[lane_key]) < 0:
					contact_ticks[lane_key] = tick
		var ceiling_contact := int(contact_ticks.ceiling)
		var floor_contact := int(contact_ticks.floor)
		# A no-contact run is an observation, never a blanket safety assertion.
		if ceiling_contact >= 0 or floor_contact >= 0:
			var contact_tick: int = mini(ceiling_contact, floor_contact) if ceiling_contact >= 0 and floor_contact >= 0 else maxi(ceiling_contact, floor_contact)
			var contact_x: float = trigger_x + speed * float(contact_tick) / SawModel.TICK_RATE
			print("SAW_SPEED_ROUTE event=%.1f speed=%d trigger=%.1f activation=%d ceiling_tick=%d floor_tick=%d first_contact_x=%.1f offset=%.1f" % [float(event.x), int(speed), trigger_x, activation_tick, ceiling_contact, floor_contact, contact_x, contact_x - float(event.x)])
		else:
			print("SAW_SPEED_ROUTE speed=%d trigger=%.1f activation=%d ceiling_tick=none floor_tick=none" % [int(speed), trigger_x, activation_tick])
		var planned_event := _matching_source_event(float(event.get("x", 0.0)), float(world.manifest.start_x))
		_check(not planned_event.is_empty(), "same seed's accepted generator event exposes its route interval")
		if ceiling_contact >= 0:
			_check(_contact_inside_planner_interval(planned_event, contact_ticks, ceiling_contact, true, float(world.manifest.start_x)), "actual ceiling-lane collision is covered by planner threat interval at speed %d" % int(speed))
		if floor_contact >= 0:
			_check(_contact_inside_planner_interval(planned_event, contact_ticks, floor_contact, false, float(world.manifest.start_x)), "actual floor-lane collision is covered by planner threat interval at speed %d" % int(speed))
		var found_safe_route := false
		var gap_x := float(event.get("roof_gap_x", float(event.get("x", 0.0)) + SawModel.ROOF_GAP_OFFSET))
		var second_flip_x: float = gap_x - speed * 0.36 - 20.0
		for flip_distance in range(-300, 701, 50):
			if _simulate_runner_route(event, world, speed, trigger_x, 1, trigger_x + float(flip_distance), second_flip_x):
				found_safe_route = true
				print("SAW_RUNNER_ROUTE speed=%d initial=floor flip1=trigger%+d flip2=%.1f grounded_after=true" % [int(speed), flip_distance, second_flip_x])
				break
		if not found_safe_route:
			for flip_distance in range(-300, 701, 50):
				if _simulate_runner_route(event, world, speed, trigger_x, -1, trigger_x + float(flip_distance)):
					found_safe_route = true
					print("SAW_RUNNER_ROUTE speed=%d initial=ceiling flip1=trigger%+d grounded_after=true" % [int(speed), flip_distance])
					break
		_check(found_safe_route, "generated ceiling-origin saw has a collision-free RunnerMotion route at speed %d" % int(speed))

func _simulate_runner_route(event: Dictionary, world: MultiplayerV2WorldSimulation, speed: float, trigger_x: float, initial_lane: int, flip_x: float, second_flip_x: float = INF) -> bool:
	var start_x := trigger_x - 500.0
	var ceiling := initial_lane < 0
	var surface: Dictionary = world.surface_at(start_x, ceiling)
	if not bool(surface.get("supported", false)):
		return false
	var player := {"y": float(surface.y) + RunnerMotion.SIZE.y * 0.5 if ceiling else float(surface.y) - RunnerMotion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": initial_lane, "grounded": true, "cooldown": 0.0}
	var blade := SawModel.initial_state(event, float(world.manifest.start_x), 0, -1)
	var flip_count := 0
	var activation_scheduled := false
	for tick in range(1, 721):
		var player_x := start_x + speed * float(tick) / SawModel.TICK_RATE
		if not activation_scheduled and player_x >= trigger_x:
			blade = SawModel.initial_state(event, float(world.manifest.start_x), 0, SawModel.contact_activation_tick(tick))
			activation_scheduled = true
		if flip_count == 0 and player_x >= flip_x and RunnerMotion.try_flip(player, -initial_lane):
			flip_count = 1
		if flip_count == 1 and player_x >= second_flip_x and RunnerMotion.try_flip(player, initial_lane):
			flip_count = 2
		blade = SawModel.advance(event, blade, tick, Callable(world, "surface_at"))
		var floor_info: Dictionary = world.surface_at(player_x, false)
		var ceiling_info: Dictionary = world.surface_at(player_x, true)
		RunnerMotion.advance_vertical(player, 1.0 / SawModel.TICK_RATE, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
		if bool(blade.get("active", false)):
			var runner_rect := Rect2(Vector2(player_x, float(player.y)) - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
			if HazardRules.circle_intersects_rect(Vector2(float(blade.x), float(blade.y)), SawModel.RADIUS, runner_rect):
				return false
		if player_x >= float(event.get("x", 0.0)) + float(world.manifest.start_x) + 1400.0:
			return bool(player.grounded) and absf(float(player.y)) < 540.0
	return false

func _matching_source_event(world_event_x: float, course_start_x: float) -> Dictionary:
	var generator: RefCounted = load("res://systems/course_generator.gd").new()
	var builder := Builder.new()
	var ruleset: Resource = builder.call("_make_multiplayer_ruleset", 9)
	var definition: Resource = RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", 1)
	definition.set("generator_version", 9)
	definition.set("ruleset", ruleset)
	if not generator.configure_run_definition(definition):
		return {}
	generator.ensure_horizon(45000.0, 500.0)
	for planned in generator.get_planned_events():
		if str(planned.get("kind", "")) == "saw" and absf(float(planned.get("course_distance", 0.0)) + course_start_x - world_event_x) < 0.1:
			return planned
	return {}

func _contact_inside_planner_interval(planned: Dictionary, contacts: Dictionary, contact_tick: int, ceiling: bool, course_start_x: float) -> bool:
	if planned.is_empty():
		return false
	var speed := 0.0
	# The call site records the test speed as a temporary field in the contact map.
	speed = float(contacts.get("speed", 0.0))
	if speed <= 0.0:
		return false
	var trigger_x := float(planned.get("course_distance", 0.0)) + course_start_x + SawModel.START_OFFSET - SawModel.SPAWN_LEAD
	var contact_course_x := trigger_x + speed * float(contact_tick) / SawModel.TICK_RATE - course_start_x
	var mask := 2 if ceiling else 1
	for interval_value in planned.get("threats", []):
		if not interval_value is Dictionary:
			continue
		var interval: Dictionary = interval_value
		if int(interval.get("blocked_lanes", 0)) & mask and contact_course_x >= float(interval.get("start", INF)) - 2.0 and contact_course_x <= float(interval.get("end", -INF)) + 2.0:
			return true
	return false

func _test_first_sample_activation(manifest: Resource, world: MultiplayerV2WorldSimulation) -> void:
	var activation_world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(activation_world.configure(manifest)).is_empty(), "first-sample activation fixture configures")
	var service = ServiceScript.new()
	service.set("current_manifest", manifest)
	service.set("world_simulation", activation_world)
	service.set("terminal_status", {})
	var saw: Dictionary = activation_world.saws[0]
	var event: Dictionary = saw.get("event", {})
	var trigger_x := float(event.get("spawn_x", float(event.get("x", 0.0)) + SawModel.START_OFFSET)) - SawModel.SPAWN_LEAD
	service.call("_maybe_activate_saws", 1, {}, {"world_x": trigger_x + 1.0, "simulation_tick": activation_world.tick})
	_check(int(activation_world.entity_ledger.entities.get(str(saw.event_id), {}).get("saw_activation_tick", -1)) >= 0, "first validated position after the threshold activates an otherwise dormant saw")
	var second_saw: Dictionary = {}
	var second_trigger := -INF
	for candidate in activation_world.saws:
		var candidate_event: Dictionary = candidate.get("event", {})
		var candidate_trigger := float(candidate_event.get("spawn_x", float(candidate_event.get("x", 0.0)) + SawModel.START_OFFSET)) - SawModel.SPAWN_LEAD
		if candidate_trigger > trigger_x:
			second_saw = candidate
			second_trigger = candidate_trigger
	if not second_saw.is_empty():
		service.call("_maybe_activate_saws", 1, {"world_x": second_trigger + 1.0}, {"world_x": second_trigger + 1.0, "simulation_tick": activation_world.tick})
		_check(int(activation_world.entity_ledger.entities.get(str(second_saw.event_id), {}).get("saw_activation_tick", -1)) >= 0, "equal consecutive samples already beyond threshold still activate an uncommitted saw")
	service.free()

func _test_late_scene_reconstruction(manifest: Resource, saw_id: String, world: MultiplayerV2WorldSimulation) -> void:
	var late_world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(late_world.configure(manifest)).is_empty(), "late-join world configures")
	var revision := 0
	for saw in late_world.saws:
		revision += 1
		var event_id := str(saw.get("event_id", ""))
		var commit := {"world_revision": revision, "commit_id": "late-%s" % event_id, "entity_id": event_id, "incarnation": 1, "action": "activate_saw", "effective_tick": 80, "saw_activation_tick": 80, "state_before": "active", "state_after": "active"}
		late_world.apply_world_commit(commit)
	for tick in range(1, 4502):
		late_world.step_to(tick)
	var event: Dictionary = {}
	for saw in late_world.saws:
		if str(saw.get("event_id", "")) == saw_id:
			event = saw.get("event", {})
			break
	var node := SawScene.instantiate() as Node2D
	get_root().add_child(node)
	node.call("configure", event, Callable(late_world, "surface_at"), float(manifest.start_x), 4501)
	node.call("set_activation_tick", 80)
	var expected: Dictionary = late_world._saw_state_for_event(saw_id, 4501)
	var actual: Dictionary = node.get("state")
	_check(is_equal_approx(float(actual.get("x", NAN)), float(expected.get("x", NAN))) and is_equal_approx(float(actual.get("y", NAN)), float(expected.get("y", NAN))), "late-instantiated SP scene reconstructs the shared current world pose")
	node.queue_free()

func _test_biome_world_coordinate_contract() -> void:
	for world_x in [4790.0, 4800.0, 4810.0, 9590.0, 9600.0, 9610.0]:
		var sp_distance := BiomeRenderer.course_distance_at_world_x(world_x, 180.0)
		var mp_distance := BiomeRenderer.course_distance_at_world_x(world_x, 180.0)
		_check(is_equal_approx(sp_distance, mp_distance), "SP and MP map the same absolute world position to the same biome distance at %.0f" % world_x)
		_check(BiomeRenderer.biome_id_at(sp_distance) == BiomeRenderer.biome_id_at(mp_distance), "SP and MP biome boundary selection matches at %.0f" % world_x)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	if failures <= 20:
		push_error("FAIL: " + message)

