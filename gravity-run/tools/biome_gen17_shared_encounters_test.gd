extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const CourseRunDefinition := preload("res://systems/course_run_definition.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const RockModel := preload("res://systems/falling_rock_model.gd")
const LavaModel := preload("res://systems/lava_hazard_model.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

const CASES := [
	{"seed": 100000019, "variant_kind": "ghost", "variant_key": "ghost_variant", "variant": 1},
	{"seed": 100000002, "variant_kind": "rock", "variant_key": "rock_variant", "variant": 1},
	{"seed": 100000057, "variant_kind": "lava_crack", "variant_key": "lava_variant", "variant": 1},
]

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for fixture in CASES:
		_test_generated_case(fixture)
	_test_model_phase_contracts()
	_test_gen16_stationary_ghost_collision_boundaries()
	for failure in failures:
		push_error(failure)
	print("BIOME_GEN17_SHARED_ENCOUNTERS_TEST failures=%d" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)

func _test_generated_case(fixture: Dictionary) -> void:
	var seed_value := int(fixture.seed)
	var built: Dictionary = Builder.new().build(seed_value, 45000, Generator.GENERATOR_VERSION_17)
	var manifest: Resource = built.get("manifest")
	_check(manifest != null, "Gen17 seed %d builds: %s" % [seed_value, str(built.get("error", ""))])
	if manifest == null:
		return
	_check(str(manifest.call("validate")).is_empty(), "Gen17 seed %d passes full manifest validation" % seed_value)
	_check(int(manifest.get("generator_version")) == 17 and int(manifest.get("manifest_version")) == 10, "Gen17 seed %d uses the new shared manifest contract" % seed_value)
	var target: Dictionary = {}
	for event in manifest.get("events"):
		if str(event.get("kind", "")) == str(fixture.variant_kind) and int(event.get(str(fixture.variant_key), 0)) == int(fixture.variant):
			target = event
			break
	_check(not target.is_empty(), "Gen17 seed %d contains its short target variant" % seed_value)
	if target.is_empty():
		return
	print("GEN17_ENCOUNTER seed=%d kind=%s course_x=%.1f id=%s" % [seed_value, str(target.kind), float(target.get("x", 0.0)) - float(manifest.get("start_x")), str(target.get("event_id", ""))])
	var world := World.new()
	_check(str(world.configure(manifest)).is_empty(), "shared V2 world configures Gen17 seed %d" % seed_value)
	var presentation := Presentation.new()
	add_child(presentation)
	_check(str(presentation.call("load_manifest", manifest)).is_empty(), "shared race presentation loads Gen17 seed %d" % seed_value)
	var event_id := str(target.get("event_id", ""))
	var activation_tick := 10
	var action := "activate_ghost" if str(target.kind) == "ghost" else "activate_rock" if str(target.kind) == "rock" else ""
	if not action.is_empty():
		var field := "ghost_activation_tick" if action == "activate_ghost" else "rock_activation_tick"
		var commit := {"world_revision": 1, "commit_id": "gen17-test-%s" % event_id, "entity_id": event_id, "incarnation": 1, "action": action, "effective_tick": activation_tick, field: activation_tick, "state_before": "active", "state_after": "active"}
		_check(world.apply_world_commit(commit) == "applied", "shared ledger accepts the correct existing activation path for %s" % str(target.kind))
		_check(world.apply_world_commit(commit) == "duplicate", "activation replay is idempotent for %s" % str(target.kind))
	var phase_tick := activation_tick + 54 + 30
	if str(target.kind) == "rock":
		phase_tick = activation_tick + int(target.get("warning_ticks", 48)) + int(target.get("fall_ticks", 30)) + 1
	elif str(target.kind) == "lava_crack":
		phase_tick = 91
	for next_tick in range(1, phase_tick + 1):
		_check(world.step_to(next_tick), "shared world advances target event tick %d" % next_tick)
	var render_state: Dictionary = world.render_state(0.5)
	presentation.call("set_world_state", render_state)
	var event_nodes: Dictionary = presentation.get("event_nodes")
	var node: Variant = event_nodes.get(event_id)
	_check(is_instance_valid(node), "shared presentation instantiates target %s scene" % str(target.kind))
	if is_instance_valid(node):
		if str(target.kind) == "ghost":
			var activation := int(world.entity_ledger.entities.get(event_id, {}).get("ghost_activation_tick", -1))
			var expected := GhostModel.center_at(target, activation, float(world.tick))
			_check(node is Node2D and (node as Node2D).global_position.distance_to(expected) < 0.01, "MP ghost scene follows authoritative Gen17 chase pose")
			_check(str(node.get("phase")) == GhostModel.phase_at(target, activation, world.tick), "MP ghost scene follows authoritative warning/danger phase")
			var sp_ghost: Node = load("res://hazards/ghost_hazard.tscn").instantiate()
			add_child(sp_ghost)
			sp_ghost.call("configure", target)
			sp_ghost.call("set_activation_tick", activation)
			sp_ghost.call("set_simulation_tick", world.tick)
			_check(sp_ghost.call("get_hitbox_rect") == node.call("get_hitbox_rect"), "SP and MP reuse identical chaser hitbox at the same shared tick")
			sp_ghost.queue_free()
			_test_chaser_motion(target, activation)
		elif str(target.kind) == "rock":
			var activation := int(world.entity_ledger.entities.get(event_id, {}).get("rock_activation_tick", -1))
			var expected_rect: Rect2 = RockModel.hitbox_at(target, activation, float(world.tick))
			_check(node.call("get_hitbox_rect") == expected_rect, "MP icicle scene collision equals the common tick model")
			_check(str(node.call("get_phase")) == RockModel.phase_at(target, activation, world.tick), "MP icicle scene presents its model phase")
			var sp_rock: Node = load("res://hazards/falling_rock.tscn").instantiate()
			add_child(sp_rock)
			sp_rock.call("configure", target)
			sp_rock.call("set_activation_tick", activation)
			sp_rock.call("set_simulation_tick", world.tick)
			_check(sp_rock.call("get_hitbox_rect") == node.call("get_hitbox_rect"), "SP and MP reuse the same icicle hitbox")
			sp_rock.queue_free()
			_test_icicle_lifecycle(target, activation)
		else:
			var tick_value := float(node.get("simulation_tick"))
			_check(node.call("get_hitbox_rect") == LavaModel.crack_rect(target, tick_value), "MP tidal-pool scene collision equals its visible tick geometry")
			var sp_lava: Node = load("res://hazards/lava_hazard.tscn").instantiate()
			add_child(sp_lava)
			sp_lava.call("configure", target, float(manifest.get("start_x")))
			sp_lava.call("apply_simulation_tick", tick_value, float(manifest.get("start_x")))
			_check(sp_lava.call("get_hitbox_rect") == node.call("get_hitbox_rect"), "SP and MP reuse the same tidal-pool phase geometry")
			sp_lava.queue_free()
			_test_pool_phase(target)
	for speed in [250.0, 500.0, 750.0]:
		_check(_simulate_full_manifest_route(manifest, target, speed, 12), "full-manifest RunnerMotion route with 200ms reaction after ghost warning safely passes %s at %d px/s" % [str(target.kind), int(speed)])
	if str(target.kind) == "lava_crack":
		for phase_offset in [45, 90, 135]:
			_check(_simulate_full_manifest_route(manifest, target, 500.0, 0, phase_offset), "full-manifest lava passage remains available at pool phase offset %d ticks" % int(phase_offset))
	var baseline: Dictionary = world.entity_ledger.baseline()
	var replica := World.new()
	_check(str(replica.configure(manifest)).is_empty(), "late replica loads identical Gen17 manifest")
	_check(replica.apply_baseline(baseline), "existing compact world baseline restores Gen17 activation")
	_check(replica.entity_ledger.baseline() == baseline, "Gen17 shared event activation survives baseline replay exactly")
	presentation.queue_free()
	await get_tree().process_frame

func _test_model_phase_contracts() -> void:
	var chaser := {"event_id": "contract_chaser", "kind": "ghost", "x": 2000.0, "width": 72.0, "height": 96.0, "floor_y": 460.0, "ceiling_y": 80.0, "trigger_lead": 1700.0, "warning_ticks": 54, "danger_ticks": 210, "fade_ticks": 30, "ghost_variant": 1, "chase_speed": 760.0, "chase_start_lag": 220.0}
	var start_tick := 100
	var runner_x := float(chaser.x) - float(chaser.trigger_lead)
	var hit_at_500 := false
	for tick in range(start_tick + 1, start_tick + 54 + 210 + 1):
		var previous := Vector2(runner_x, float(chaser.floor_y) - RunnerMotion.SIZE.y * 0.5)
		runner_x += 500.0 / 60.0
		var current := Vector2(runner_x, previous.y)
		if GhostModel.swept_contact_fraction(chaser, start_tick, tick - 1, tick, previous, current, RunnerMotion.SIZE) >= 0.0:
			hit_at_500 = true
			break
	_check(hit_at_500, "chaser reaches a floor runner in its bounded dangerous corridor at 500 px/s")
	_check(GhostModel.phase_at(chaser, start_tick, start_tick + 54 + 210 + 30) == GhostModel.EXPIRED, "chaser danger and fade end at its deterministic lifetime")
	var icicle := {"event_id": "contract_icicle", "kind": "rock", "x": 500.0, "width": 64.0, "height": 116.0, "floor_y": 460.0, "ceiling_y": 80.0, "from_ceiling": true, "rock_variant": 1, "warning_ticks": 48, "fall_ticks": 30, "lodged_ticks": 240, "burial_depth": 18.0, "floor_supported": true}
	_check(RockModel.phase_at(icicle, 10, 57) == "warning" and RockModel.phase_at(icicle, 10, 58) == "falling", "icicle warning-to-fall boundary is tick exact")
	_check(RockModel.phase_at(icicle, 10, 88) == "lodged" and RockModel.phase_at(icicle, 10, 328) == "expired", "supported icicle lodges temporarily then expires")
	var floor_gap := icicle.duplicate(true)
	floor_gap.floor_supported = false
	_check(RockModel.phase_at(floor_gap, 10, 117) == "falling" and RockModel.phase_at(floor_gap, 10, 118) == "expired", "icicle that falls through a floor gap expires instead of landing later")
	_check(RockModel.hitbox_at(floor_gap, 10, 118).size == Vector2.ZERO, "expired gap icicle has no residual collision")
	var pool := {"event_id": "contract_pool", "kind": "lava_crack", "x": 500.0, "y": 460.0, "width": 160.0, "hot_depth": 18.0, "from_ceiling": false, "lava_variant": 1, "pool_min_depth": 6.0, "pool_max_depth": 30.0, "pool_period_ticks": 180, "pool_phase_ticks": 0}
	var shallow := LavaModel.tidal_pool_rect(pool, 0.0)
	var deep := LavaModel.tidal_pool_rect(pool, 90.0)
	_check(shallow.size.y < deep.size.y and shallow.size.x < deep.size.x, "tidal pool grows and shrinks by shared deterministic phase")
	var low_contact := LavaModel.swept_crack_contact_fraction(pool, 0, 0, Vector2(500.0, 420.0), Vector2(500.0, 420.0))
	var high_contact := LavaModel.swept_crack_contact_fraction(pool, 90, 90, Vector2(500.0, 420.0), Vector2(500.0, 420.0))
	_check(low_contact < 0.0 and high_contact >= 0.0, "the pool's lethal contact envelope follows visible depth, without decorative glow extending it")
	_test_icicle_expiration_sweep()

func _test_gen16_stationary_ghost_collision_boundaries() -> void:
	var built: Dictionary = Builder.new().build(100000014, 45000, 16)
	var manifest: Resource = built.get("manifest")
	if manifest == null:
		_check(false, "build a frozen Gen16 manifest for stationary-ghost boundary regression")
		return
	var legacy_ghost: Dictionary = {}
	for event in manifest.get("events"):
		if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 0:
			legacy_ghost = event.duplicate(true)
			break
	_check(not legacy_ghost.is_empty(), "frozen Gen16 seed contains the stationary ghost variant")
	if legacy_ghost.is_empty():
		return
	manifest.set("events", [legacy_ghost])
	manifest.set("collectibles", [])
	manifest.set("manifest_hash", str(manifest.call("calculate_hash")))
	var world := World.new()
	_check(str(world.configure(manifest)).is_empty(), "isolated Gen16 stationary ghost world configures")
	if world.manifest == null:
		return
	var activation_tick := 100
	var event_id := str(legacy_ghost.get("event_id", ""))
	var commit := {"world_revision": 1, "commit_id": "gen16-legacy-ghost-activation", "entity_id": event_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": activation_tick, "ghost_activation_tick": activation_tick, "state_before": "active", "state_after": "active"}
	_check(world.apply_world_commit(commit) == "applied", "Gen16 stationary ghost is activated by the existing ledger path")
	var warning_ticks := int(legacy_ghost.get("warning_ticks", 120))
	var danger_ticks := int(legacy_ghost.get("danger_ticks", 500))
	var danger_entry_tick := activation_tick + warning_ticks
	var danger_rect := GhostModel.hitbox(legacy_ghost, danger_entry_tick, activation_tick)
	var start_center := Vector2(danger_rect.position.x - RunnerMotion.SIZE.x * 0.5 - 10.0, danger_rect.get_center().y)
	var end_center := Vector2(danger_rect.position.x - RunnerMotion.SIZE.x * 0.5 + 1.0, danger_rect.get_center().y)
	var previous := {"world_x": start_center.x, "y": start_center.y}
	var proposed := {"world_x": end_center.x, "y": end_center.y}
	world.tick = danger_entry_tick
	var transition_result: Dictionary = world.first_static_terminal_contact(previous, proposed)
	var expected_entry := _gen16_head_ghost_fraction(legacy_ghost, activation_tick, danger_entry_tick, start_center, end_center)
	_check(is_equal_approx(float(transition_result.get("fraction", -1.0)), expected_entry) and is_equal_approx(expected_entry, 1.0), "Gen16 warning-to-danger contact preserves the pre-Gen17 endpoint-only boundary")
	var expired_tick := danger_entry_tick + danger_ticks
	world.tick = expired_tick
	var expired_result: Dictionary = world.first_static_terminal_contact({"world_x": danger_rect.get_center().x, "y": danger_rect.get_center().y}, {"world_x": danger_rect.get_center().x, "y": danger_rect.get_center().y})
	_check(expired_result.is_empty(), "Gen16 danger-to-expired boundary remains nonlethal on the expired tick")
	var active_tick := danger_entry_tick + 2
	var active_rect := GhostModel.hitbox(legacy_ghost, active_tick, activation_tick)
	var crossing_start := Vector2(active_rect.position.x - RunnerMotion.SIZE.x * 0.5 - 30.0, active_rect.get_center().y)
	var crossing_end := Vector2(active_rect.end.x + RunnerMotion.SIZE.x * 0.5 + 30.0, active_rect.get_center().y)
	world.tick = active_tick
	var crossing_result: Dictionary = world.first_static_terminal_contact({"world_x": crossing_start.x, "y": crossing_start.y}, {"world_x": crossing_end.x, "y": crossing_end.y})
	var expected_crossing := _gen16_head_ghost_fraction(legacy_ghost, activation_tick, active_tick, crossing_start, crossing_end)
	_check(expected_crossing >= 0.0 and is_equal_approx(float(crossing_result.get("fraction", -1.0)), expected_crossing), "Gen16 stationary ghost keeps its original within-danger swept contact timing")

func _gen16_head_ghost_fraction(event: Dictionary, activation_tick: int, tick: int, start_center: Vector2, end_center: Vector2) -> float:
	if activation_tick < 0 or GhostModel.phase_at(event, activation_tick, tick) != GhostModel.DANGEROUS:
		return -1.0
	var ghost_rect := GhostModel.hitbox(event, tick, activation_tick)
	if GhostModel.phase_at(event, activation_tick, maxi(tick - 1, 0)) == GhostModel.DANGEROUS:
		var polygon := PackedVector2Array([ghost_rect.position, Vector2(ghost_rect.end.x, ghost_rect.position.y), ghost_rect.end, Vector2(ghost_rect.position.x, ghost_rect.end.y)])
		return HazardRules.swept_rect_polygon_fraction(Rect2(start_center - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE), end_center - start_center, polygon)
	var endpoint := Rect2(end_center - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
	return 1.0 if HazardRules.player_impact(endpoint, "block", ghost_rect) == HazardRules.PlayerImpact.LETHAL else -1.0

func _test_icicle_expiration_sweep() -> void:
	var supported := {"event_id": "expiry_supported", "kind": "rock", "rock_variant": 1, "x": 500.0, "width": 52.0, "height": 112.0, "floor_y": 460.0, "ceiling_y": 80.0, "from_ceiling": true, "warning_ticks": 48, "fall_ticks": 30, "lodged_ticks": 240, "burial_depth": 18.0, "floor_supported": true}
	var activation := 10
	var expiry := activation + int(supported.warning_ticks) + int(supported.fall_ticks) + int(supported.lodged_ticks)
	var remote_start := Vector2(9000.0, 270.0)
	var remote_end := Vector2(9000.0, 270.0)
	_check(RockModel.swept_contact_fraction(supported, activation, expiry - 1, expiry, remote_start, remote_end, RunnerMotion.SIZE) < 0.0, "supported icicle expiration never sweeps its hitbox back toward the world origin")
	var gap := supported.duplicate(true)
	gap.event_id = "expiry_gap"
	gap.floor_supported = false
	var gap_expiry := activation + int(gap.warning_ticks) + int(gap.fall_ticks) * 2
	_check(RockModel.swept_contact_fraction(gap, activation, gap_expiry - 1, gap_expiry, remote_start, remote_end, RunnerMotion.SIZE) < 0.0, "gap-falling icicle expiry never creates a remote swept collision")
	var impact_tick := activation + int(supported.warning_ticks) + int(supported.fall_ticks)
	var impact_center := RockModel.center_at(supported, activation, float(impact_tick))
	var overlapping_player := Vector2(impact_center.x, impact_center.y - RunnerMotion.SIZE.y * 0.5)
	_check(RockModel.swept_contact_fraction(supported, activation, impact_tick - 1, impact_tick, overlapping_player, overlapping_player, RunnerMotion.SIZE) >= 0.0, "icicle remains lethal through its real landing transition")

func _test_gen17_runtime_filter_parity() -> void:
	var seed_value := 100000019
	var generator_version := 17
	var built: Dictionary = Builder.new().build(seed_value, 45000, generator_version)
	var manifest: Resource = built.get("manifest")
	if manifest == null:
		_check(false, "build Gen17 manifest for SP/MP safety-filter parity")
		return
	var builder := Builder.new()
	var ruleset: Resource = builder.call("_make_multiplayer_ruleset", generator_version)
	var definition: Resource = CourseRunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", generator_version)
	definition.set("ruleset", ruleset)
	var generator: Variant = Generator.new()
	_check(bool(generator.call("configure_run_definition", definition)), "configure same deterministic source generator used by the manifest builder")
	generator.call("ensure_horizon", 45000.0, 500.0)
	var biome_offset: float = BiomeRenderer.start_biome_offset_for_seed(seed_value, generator_version)
	var source_events: Array[Dictionary] = generator.call("get_planned_events")
	var runtime_events: Array[Dictionary] = builder.call("resolve_runtime_events", source_events, 45000, generator_version, biome_offset)
	_check(_event_ids(runtime_events) == _event_ids(manifest.get("events")), "SP runtime resolver applies the same Gen17 unsafe-event filter as MP manifest generation")
	var raw_resolved: Array[Dictionary] = builder.call("_resolve_events", source_events, 45000, generator_version, biome_offset)
	var rejected_variant := false
	for event in raw_resolved:
		if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 1 and not _event_ids(runtime_events).has(str(event.get("event_id", ""))):
			rejected_variant = true
			break
	_check(rejected_variant or _event_ids(runtime_events) == _event_ids(raw_resolved), "runtime filtering either rejects an unsafe chaser or retains every already-safe event")
	var expected_coins: Array[Dictionary] = manifest.get("collectibles")
	var actual_coins: Array[Dictionary] = CoinPlanner.plan(seed_value, float(manifest.get("start_x")), float(manifest.get("finish_x")), runtime_events, 460.0, 80.0, int(ruleset.get("coin_revision")), float(ruleset.get("coin_density")))
	_check(actual_coins == expected_coins, "SP coin planning receives the same post-safety-filter event catalog as the MP manifest")
	var ghost_distance := -1.0
	for distance in range(4500, 18000, 250):
		if str(BiomeRenderer.biome_id_for_generator(float(distance) + biome_offset, generator_version)) == "haunted":
			ghost_distance = float(distance)
			break
	if ghost_distance >= 0.0:
		var synthetic: Array[Dictionary] = [
			{"id": "haunted_chaser", "kind": "ghost", "course_distance": ghost_distance, "width": 72.0, "height": 72.0, "from_ceiling": false, "ghost_variant": 1, "trigger_lead": 1700.0, "warning_ticks": 54, "danger_ticks": 210, "chase_speed": 760.0, "chase_start_lag": 220.0},
			{"id": "ceiling_gap", "kind": "gap", "course_distance": ghost_distance + 350.0, "width": 120.0, "from_ceiling": true},
		]
		var unsafe_raw: Array[Dictionary] = builder.call("_resolve_events", synthetic, int(ghost_distance + 2000.0), generator_version, biome_offset)
		var unsafe_filtered: Array[Dictionary] = builder.call("resolve_runtime_events", synthetic, int(ghost_distance + 2000.0), generator_version, biome_offset)
		var raw_has_chaser := false
		var kept_chaser := false
		for event in unsafe_raw:
			if int(event.get("ghost_variant", 0)) == 1:
				raw_has_chaser = true
		for event in unsafe_filtered:
			if int(event.get("ghost_variant", 0)) == 1:
				kept_chaser = true
		_check(raw_has_chaser and not kept_chaser, "synthetic roof-gap chaser rejected by the same runtime safety filter")

func _event_ids(events: Array) -> Array[String]:
	var ids: Array[String] = []
	for event in events:
		if event is Dictionary:
			ids.append(str(event.get("event_id", "")))
	return ids

func _test_chaser_motion(event: Dictionary, activation_tick: int) -> void:
	for speed in [250.0, 500.0, 750.0]:
		var floor_y := float(event.get("floor_y", 460.0))
		var ceiling_y := float(event.get("ceiling_y", 80.0))
		var state := {"y": floor_y - RunnerMotion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
		var flipped := RunnerMotion.try_flip(state, -1)
		var ceiling_safe := false
		for _tick in range(1, 60):
			RunnerMotion.advance_vertical(state, 1.0 / 60.0, floor_y, ceiling_y)
			if bool(state.grounded) and int(state.gravity_direction) == -1:
				ceiling_safe = true
				break
		_check(flipped and ceiling_safe, "opposite supported lane is reachable for the chaser at %d px/s without teleporting" % int(speed))
		var start_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 1700.0)) - 100.0
		var finish_x: float = start_x + speed * float(int(event.get("warning_ticks", 54)) + int(event.get("danger_ticks", 210))) / 60.0
		var swept := GhostModel.swept_contact_fraction(event, activation_tick, activation_tick, activation_tick + int(event.get("warning_ticks", 54)) + int(event.get("danger_ticks", 210)), Vector2(start_x, floor_y - RunnerMotion.SIZE.y * 0.5), Vector2(finish_x, floor_y - RunnerMotion.SIZE.y * 0.5), RunnerMotion.SIZE)
		if speed < 700.0:
			_check(swept >= 0.0, "shared swept chase contact is detected at runner speed %d" % int(speed))
		else:
			_check(swept < 0.0, "fast runner can outrun the short chase, leaving the opposite-lane option available")

func _test_icicle_lifecycle(event: Dictionary, activation_tick: int) -> void:
	var landing_tick := activation_tick + int(event.get("warning_ticks", 48)) + int(event.get("fall_ticks", 30))
	var impact_rect: Rect2 = RockModel.hitbox_at(event, activation_tick, float(landing_tick))
	_check(not impact_rect.size.is_zero_approx() and is_equal_approx(impact_rect.end.y, float(event.get("floor_y", 460.0))), "landed icicle's visible/contact portion ends exactly at floor surface")
	var gap_event := event.duplicate(true)
	gap_event.floor_supported = false
	var after_fall := activation_tick + int(event.get("warning_ticks", 48)) + int(event.get("fall_ticks", 30)) * 2 + 1
	_check(RockModel.phase_at(gap_event, activation_tick, after_fall) == "expired" and RockModel.hitbox_at(gap_event, activation_tick, after_fall).size == Vector2.ZERO, "icicle falling through an authored gap cannot reappear")

func _test_pool_phase(event: Dictionary) -> void:
	var period := float(event.get("pool_period_ticks", 180))
	var phase_ticks := int(event.get("pool_phase_ticks", 0))
	var cycle_start := float(posmod(-phase_ticks, maxi(int(period), 1)))
	var phases := [cycle_start, cycle_start + period * 0.25, cycle_start + period * 0.5, cycle_start + period * 0.75]
	var dimensions: Array[Vector2] = []
	for tick in phases:
		var rect: Rect2 = LavaModel.crack_rect(event, tick)
		dimensions.append(rect.size)
		_check(rect == LavaModel.tidal_pool_rect(event, tick), "pool render and canonical contact geometry match at tick %.0f" % tick)
	_check(dimensions[0].x < dimensions[2].x and dimensions[0].y < dimensions[2].y and is_equal_approx(dimensions[1].x, dimensions[3].x), "generated pool cycles through expand and contract phases")

func _simulate_full_manifest_route(manifest: Resource, target: Dictionary, speed: float, ghost_reaction_ticks: int = 0, pool_phase_offset: int = 0) -> bool:
	var route_manifest: Resource = manifest
	if pool_phase_offset != 0:
		route_manifest = manifest.duplicate(true)
		var adjusted_events: Array[Dictionary] = []
		for event in route_manifest.get("events"):
			var adjusted: Dictionary = event.duplicate(true)
			if str(adjusted.get("kind", "")) == "lava_crack" and int(adjusted.get("lava_variant", 0)) == 1:
				adjusted["pool_phase_ticks"] = int(adjusted.get("pool_phase_ticks", 0)) + pool_phase_offset
			adjusted_events.append(adjusted)
		route_manifest.set("events", adjusted_events)
		route_manifest.set("manifest_version", int(manifest.get("manifest_version")))
		route_manifest.set("manifest_hash", str(route_manifest.call("calculate_hash")))
	var world := World.new()
	var configure_error := str(world.configure(route_manifest))
	if not configure_error.is_empty():
		print("GEN17_ROUTE_CONFIG_FAIL seed=%d speed=%d error=%s" % [int(manifest.get("seed_value")), int(speed), configure_error])
		return false
	var start_x := float(manifest.get("start_x"))
	var target_x := float(target.get("x", 0.0))
	var player := {"y": float(manifest.get("initial_floor_y")) - RunnerMotion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0}
	var previous := {"world_x": start_x, "y": float(player.y), "gravity_direction": 1}
	var flipped_to_ceiling := false
	var flipped_back := false
	var hold_opposite_lane := str(target.get("kind", "")) == "ghost"
	var target_activation_tick := -1
	var route_end_x := target_x + (2600.0 if hold_opposite_lane else 1100.0)
	var max_tick := ceili((route_end_x - start_x) / speed * 60.0)
	for tick in range(1, max_tick + 1):
		var player_x: float = start_x + speed * float(tick) / 60.0
		if not world.step_to(tick):
			print("GEN17_ROUTE_STEP_FAIL seed=%d speed=%d tick=%d world_tick=%d" % [int(manifest.get("seed_value")), int(speed), tick, int(world.tick)])
			return false
		for event in manifest.get("events"):
			var kind := str(event.get("kind", ""))
			if kind not in ["ghost", "rock"]:
				continue
			var event_id := str(event.get("event_id", ""))
			var state: Dictionary = world.entity_ledger.entities.get(event_id, {})
			var activation_key := "ghost_activation_tick" if kind == "ghost" else "rock_activation_tick"
			if state.is_empty() or int(state.get(activation_key, -1)) >= 0:
				continue
			var trigger := GhostModel.trigger_x(event) if kind == "ghost" else float(event.get("x", 0.0)) - float(event.get("trigger_lead", 1100.0))
			if player_x < trigger:
				continue
			var revision := int(world.entity_ledger.revision) + 1
			var action := "activate_ghost" if kind == "ghost" else "activate_rock"
			var commit := {"world_revision": revision, "commit_id": "route-%s-%d" % [event_id, tick], "entity_id": event_id, "incarnation": 1, "action": action, "effective_tick": tick, activation_key: tick, "trigger_peer_id": 1, "trigger_tick": tick, "state_before": "active", "state_after": "active"}
			var commit_result := world.apply_world_commit(commit)
			if commit_result != "applied":
				print("GEN17_ROUTE_ACTIVATION_FAIL seed=%d speed=%d event=%s result=%s revision=%d commitrev=%d" % [int(manifest.get("seed_value")), int(speed), event_id, commit_result, int(world.entity_ledger.revision), revision])
				return false
			if event_id == str(target.get("event_id", "")):
				target_activation_tick = tick
		# Use an actual early floor-to-ceiling flip, before any target activation;
		# for chasers, wait until its warning is underway and allow a 200ms
		# reaction margin before issuing the flip. This remains real RunnerMotion.
		var flip_tick := 1
		if hold_opposite_lane:
			if target_activation_tick < 0:
				flip_tick = maxi(max_tick + 1, 1)
			else:
				flip_tick = target_activation_tick + int(target.get("warning_ticks", 54)) + ghost_reaction_ticks
		if not flipped_to_ceiling and tick >= flip_tick and player_x >= start_x + 1.0:
			flipped_to_ceiling = RunnerMotion.try_flip(player, -1)
		if flipped_to_ceiling and not hold_opposite_lane and not flipped_back and player_x >= target_x + 300.0:
			flipped_back = RunnerMotion.try_flip(player, 1)
		var floor_info: Dictionary = world.surface_at(player_x, false)
		var ceiling_info: Dictionary = world.surface_at(player_x, true)
		RunnerMotion.advance_vertical(player, 1.0 / 60.0, float(floor_info.get("y", 460.0)), float(ceiling_info.get("y", 80.0)), bool(floor_info.get("supported", true)), bool(ceiling_info.get("supported", true)))
		var proposed := {"world_x": player_x, "y": float(player.y), "gravity_direction": int(player.gravity_direction)}
		var contact := world.first_static_terminal_contact(previous, proposed)
		if str(contact.get("kind", "")) == "terminal":
			print("GEN17_ROUTE_BLOCK kind=%s seed=%d target=%s speed=%d tick=%d x=%.1f lane=%d reason=%s event=%s" % [str(manifest.get("generator_version")), int(manifest.get("seed_value")), str(target.get("kind", "")), int(speed), tick, player_x, int(player.gravity_direction), str(contact.get("reason", "")), str(contact.get("event_id", ""))])
			return false
		var endpoint_contact: Dictionary = world.player_contact(proposed)
		if str(endpoint_contact.get("kind", "")) == "terminal":
			print("GEN17_ROUTE_BLOCK kind=%s seed=%d target=%s speed=%d tick=%d x=%.1f lane=%d reason=%s event=%s" % [str(manifest.get("generator_version")), int(manifest.get("seed_value")), str(target.get("kind", "")), int(speed), tick, player_x, int(player.gravity_direction), str(endpoint_contact.get("reason", "")), str(endpoint_contact.get("event_id", ""))])
			return false
		if absf(float(player.y)) > 650.0:
			print("GEN17_ROUTE_EXIT seed=%d target=%s speed=%d tick=%d x=%.1f y=%.1f" % [int(manifest.get("seed_value")), str(target.get("kind", "")), int(speed), tick, player_x, float(player.y)])
			return false
		previous = proposed
	var safe_finish := flipped_to_ceiling and (hold_opposite_lane or flipped_back) and bool(player.grounded)
	if not safe_finish:
		print("GEN17_ROUTE_INCOMPLETE seed=%d target=%s speed=%d x=%.1f lane=%d grounded=%s switched=%s/%s y=%.1f" % [int(manifest.get("seed_value")), str(target.get("kind", "")), int(speed), float(previous.world_x), int(player.gravity_direction), str(player.grounded), str(flipped_to_ceiling), str(flipped_back), float(player.y)])
	return safe_finish

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
