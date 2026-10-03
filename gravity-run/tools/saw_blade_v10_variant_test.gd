extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

const V9_HASHES := {
	1: "5c76fbf68f80629be2b792af5cc91dcd5ac488b5530b55fdd7020711d894bca4",
	42: "0fdd1b7279eb42dd0106de133085d7be2f30fb743d53a125767e31830c9ade0b",
	918273645: "00b6b2a081f48b66865c88ff4e247a7a9ae6eba0624ea92ba1b391e8544e0cf6",
	100000014: "c168e2c8a7d100bf11f929d4915ceef43419476d98946849730242c613808b37",
}
const VARIANTS := ["floor_embedded", "ceiling_embedded", "ceiling_gap_drop"]

var failures := 0
var builder := Builder.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_frozen_v9()
	var counts := {"floor_embedded": 0, "ceiling_embedded": 0, "ceiling_gap_drop": 0}
	var samples: Dictionary = {}
	var saw_events := 0
	for seed in range(1, 121):
		var built: Dictionary = builder.build(seed, 45000, Generator.GENERATOR_VERSION)
		var manifest: Resource = built.get("manifest")
		_check(manifest != null, "v10 manifest builds for seed %d: %s" % [seed, str(built.get("error", ""))])
		if manifest == null:
			continue
		for event in manifest.get("events"):
			if str(event.get("kind", "")) != "saw":
				continue
			saw_events += 1
			var variant := str(event.get("saw_variant", ""))
			_check(variant in VARIANTS, "v10 saw event names a supported variant")
			if not counts.has(variant):
				continue
			counts[variant] = int(counts[variant]) + 1
			_check(is_equal_approx(float(event.get("saw_radius", 0.0)), 34.0), "v10 saw radius is explicit and 34px")
			var has_roof_gap: bool = (event as Dictionary).has("roof_gap_x")
			_check(has_roof_gap == (variant == "ceiling_gap_drop"), "only the rare ceiling-drop variant creates a roof gap")
			if variant == "ceiling_gap_drop":
				_check(is_equal_approx(float(event.get("roof_gap_x", 0.0)), float(event.get("x", 0.0)) + SawModel.V10_DROP_ROOF_GAP_OFFSET), "v10 drop gap is moved earlier without changing legacy roof gaps")
				_check(is_equal_approx(float(event.get("roof_gap_width", 0.0)), SawModel.V10_DROP_ROOF_GAP_WIDTH), "v10 drop gap uses the bounded authored width")
			if not samples.has(variant):
				samples[variant] = {"seed": seed, "event": event.duplicate(true), "manifest": manifest}
	_check(saw_events >= 35, "120 representative seeds generate enough saws for variant coverage (%d)" % saw_events)
	_check(int(counts["floor_embedded"]) > int(counts["ceiling_embedded"]), "floor saws remain the most common variant")
	_check(int(counts["ceiling_gap_drop"]) > 0 and int(counts["ceiling_gap_drop"]) < int(counts["ceiling_embedded"]), "ceiling-gap drops occur but remain rarer than ceiling rollers")
	print("SAW_V10_DISTRIBUTION seeds=120 saws=%d floor=%d ceiling=%d drop=%d" % [saw_events, counts.floor_embedded, counts.ceiling_embedded, counts.ceiling_gap_drop])
	for variant in VARIANTS:
		if samples.has(variant):
			_test_variant_model_and_contacts(variant, samples[variant])
	if failures == 0:
		print("SAW_V10_VARIANTS_PASS")
	quit(1 if failures > 0 else 0)

func _test_frozen_v9() -> void:
	for seed in V9_HASHES:
		var built: Dictionary = builder.build(seed, 45000, Generator.GENERATOR_VERSION_9)
		var manifest: Resource = built.get("manifest")
		_check(manifest != null and str(manifest.get("manifest_hash")) == str(V9_HASHES[seed]), "v9 seed %d retains byte-exact frozen manifest hash" % seed)

func _test_variant_model_and_contacts(variant: String, sample: Dictionary) -> void:
	var manifest: Resource = sample.manifest
	var event: Dictionary = sample.event
	var radius := SawModel.radius_for_event(event)
	_check(is_equal_approx(radius, 34.0), "%s model consumes the versioned 34px radius" % variant)
	var built_generator := Generator.new() as CourseGenerator
	var run_rules: Resource = builder.call("_make_multiplayer_ruleset", Generator.GENERATOR_VERSION)
	_check(built_generator.configure_ruleset(run_rules, Generator.GENERATOR_VERSION), "gen10 matching source planner configures")
	built_generator.reset(int(manifest.get("seed_value")))
	built_generator.ensure_horizon(float(manifest.get("course_length_px")), 500.0)
	var source_event: Dictionary = {}
	for planned in built_generator.get_planned_events():
		if str(planned.get("kind", "")) == "saw" and absf(float(planned.get("course_distance", 0.0)) + float(manifest.get("start_x")) - float(event.get("x", 0.0))) < 0.1:
			source_event = planned
			break
	_check(not source_event.is_empty(), "%s resolved manifest event matches the seeded planner event" % variant)
	var world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(world.configure(manifest)).is_empty(), "%s course configures shared MP world" % variant)
	var event_id := str(event.get("event_id", ""))
	var trigger_x := float(event.get("spawn_x", 0.0)) - SawModel.SPAWN_LEAD
	var activation_tick := SawModel.contact_activation_tick(0)
	var saw_state := SawModel.initial_state(event, float(manifest.get("start_x")), 0, activation_tick)
	var model_surface := Callable(world, "surface_at")
	var lane_contacts := {"floor": {}, "ceiling": {}}
	for initial_ceiling in [false, true]:
		for speed in [250.0, 500.0, 750.0]:
			var state := SawModel.initial_state(event, float(manifest.get("start_x")), 0, activation_tick)
			var floor_start: Dictionary = world.surface_at(trigger_x, false)
			var ceiling_start: Dictionary = world.surface_at(trigger_x, true)
			var lane_y := float(ceiling_start.y) + RunnerMotion.SIZE.y * 0.5 if initial_ceiling else float(floor_start.y) - RunnerMotion.SIZE.y * 0.5
			var runner := {"y": lane_y, "vertical_speed": 0.0, "gravity_direction": -1 if initial_ceiling else 1, "grounded": true, "cooldown": 0.0}
			var contact_tick := -1
			var contact_offset := INF
			for tick in range(1, 1201):
				var player_x: float = trigger_x + float(speed) * float(tick) / SawModel.TICK_RATE
				state = SawModel.advance(event, state, tick, model_surface)
				var floor_info: Dictionary = world.surface_at(player_x, false)
				var ceiling_info: Dictionary = world.surface_at(player_x, true)
				RunnerMotion.advance_vertical(runner, 1.0 / SawModel.TICK_RATE, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
				if not bool(state.get("active", false)) or bool(state.get("removed", false)):
					continue
				var runner_rect := Rect2(Vector2(player_x, float(runner.y)) - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
				if HazardRules.circle_intersects_rect(Vector2(float(state.x), float(state.y)), radius, runner_rect):
					contact_tick = tick
					# Planner intervals are stored in course coordinates, not relative
					# offsets from this event's world x.
					contact_offset = player_x - float(manifest.get("start_x"))
					break
			var lane_name := "ceiling" if initial_ceiling else "floor"
			lane_contacts[lane_name][str(int(speed))] = {"tick": contact_tick, "offset": contact_offset}
			if contact_tick >= 0:
				_check(_planner_covers(source_event, initial_ceiling, contact_offset), "%s actual %dpx/s %s contact at %.1fpx is covered by its planner window" % [variant, int(speed), lane_name, contact_offset])
			var expected_contact_lane := "floor" if variant in ["floor_embedded", "ceiling_gap_drop"] else "ceiling"
			if variant != "ceiling_gap_drop":
				_check((contact_tick >= 0) == (lane_name == expected_contact_lane), "%s RunnerMotion route at %dpx/s has the expected safe escape lane" % [variant, int(speed)])
			print("SAW_V10_CONTACT variant=%s lane=%s speed=%d tick=%d course_x=%.1f event_x=%.1f event_offset=%.1f" % [variant, lane_name, int(speed), contact_tick, contact_offset, float(source_event.get("course_distance", 0.0)), contact_offset - float(source_event.get("course_distance", 0.0))])
	if variant == "ceiling_gap_drop":
		for speed in [250.0, 500.0, 750.0]:
			_check(_simulate_drop_to_floor_route(event, world, speed), "ceiling-gap drop has a grounded, collision-free floor route at %dpx/s after flipping before the roof gap" % int(speed))
	# Shared world state and shared SP scene use the same event, model, support query and tick.
	var world_saw: Dictionary = {}
	for candidate in world.saws:
		if str(candidate.get("event_id", "")) == event_id:
			world_saw = candidate
			break
	_check(not world_saw.is_empty(), "%s event is present in the MP world's shared saw collection" % variant)
	var activation_commit := {"world_revision": int(world.entity_ledger.revision) + 1, "commit_id": "v10-%s" % event_id, "entity_id": event_id, "incarnation": 1, "action": "activate_saw", "effective_tick": activation_tick, "saw_activation_tick": activation_tick, "state_before": "active", "state_after": "active"}
	_check(world.apply_world_commit(activation_commit) == "applied", "%s MP world accepts one authoritative activation" % variant)
	var scene := preload("res://hazards/saw_blade.tscn").instantiate() as Node2D
	get_root().add_child(scene)
	scene.call("configure", event, model_surface, float(manifest.get("start_x")), 0)
	scene.call("set_activation_tick", activation_tick)
	for tick in range(1, 241):
		world.step_to(tick)
		scene.call("set_simulation_tick", tick)
		var replicated_state: Dictionary = scene.get("state")
		var shared_state: Dictionary = world._saw_state_for_event(event_id)
		_check(replicated_state == shared_state, "%s shared SP scene and MP model match at tick %d" % [variant, tick])
	var final_state: Dictionary = scene.get("state")
	_check(is_equal_approx(float(final_state.get("radius", 0.0)), 34.0), "%s scene hitbox keeps radius 34 after tick replay" % variant)
	scene.queue_free()

func _planner_covers(source_event: Dictionary, ceiling_lane: bool, contact_offset: float) -> bool:
	var lane_bit := 2 if ceiling_lane else 1
	for interval in source_event.get("threats", []):
		if int(interval.get("blocked_lanes", 0)) & lane_bit and contact_offset >= float(interval.get("start", INF)) - 2.0 and contact_offset <= float(interval.get("end", -INF)) + 2.0:
			return true
	return false

func _simulate_drop_to_floor_route(event: Dictionary, world: MultiplayerV2WorldSimulation, speed: float) -> bool:
	var trigger_x := float(event.get("spawn_x", 0.0)) - SawModel.SPAWN_LEAD
	var gap_start := float(event.get("roof_gap_x", 0.0))
	var gap_end := gap_start + float(event.get("roof_gap_width", 0.0))
	var floor_info: Dictionary = world.surface_at(trigger_x, false)
	var ceiling_info: Dictionary = world.surface_at(trigger_x, true)
	# Carry a full prior-flip cooldown into the approach, as a realistic preceding
	# encounter can leave the runner unable to switch immediately.
	var runner := {"y": float(ceiling_info.y) + RunnerMotion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": -1, "grounded": true, "cooldown": 0.84}
	var state := SawModel.initial_state(event, float(world.manifest.get("start_x")), 0, SawModel.contact_activation_tick(0))
	var flip_requested := false
	for tick in range(1, 1201):
		var player_x: float = trigger_x + speed * float(tick) / SawModel.TICK_RATE
		if not flip_requested and player_x >= gap_start - 250.0:
			flip_requested = RunnerMotion.try_flip(runner, 1)
		state = SawModel.advance(event, state, tick, Callable(world, "surface_at"))
		floor_info = world.surface_at(player_x, false)
		ceiling_info = world.surface_at(player_x, true)
		RunnerMotion.advance_vertical(runner, 1.0 / SawModel.TICK_RATE, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported))
		var runner_y := float(runner.y)
		if runner_y < 0.0 or runner_y > float(world.manifest.get("world_height")):
			return false
		if bool(state.get("active", false)) and not bool(state.get("removed", false)):
			var rect := Rect2(Vector2(player_x, runner_y) - RunnerMotion.SIZE * 0.5, RunnerMotion.SIZE)
			if HazardRules.circle_intersects_rect(Vector2(float(state.x), float(state.y)), SawModel.radius_for_state(state), rect):
				return false
		if player_x > gap_end + 120.0:
			return flip_requested and bool(runner.grounded) and int(runner.gravity_direction) == 1
	return false

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	if failures < 50:
		push_error("FAIL: " + message)
