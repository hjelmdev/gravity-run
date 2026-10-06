extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")
const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run()
	for failure in failures:
		push_error(failure)
	print("GHOST_HAZARD_SHARED_TEST failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	_check(GhostModel.phase_at(_event(2500.0, false), -1, 10) == GhostModel.DORMANT, "unactivated ghosts stay dormant")
	_check(GhostModel.phase_at(_event(2500.0, false), 20, 20) == GhostModel.WARNING, "activation starts the tick-based warning phase")
	_check(GhostModel.phase_at(_event(2500.0, false), 20, 140) == GhostModel.DANGEROUS, "warning changes to dangerous on the exact shared tick")
	_check(GhostModel.phase_at(_event(2500.0, false), 20, 640) == GhostModel.FADING, "danger ends on the exact shared tick")
	_check(GhostModel.phase_at(_event(2500.0, false), 20, 685) == GhostModel.EXPIRED, "fading ends permanently")
	_check(GhostModel.hitbox(_event(2500.0, false), 139, 20).size == Vector2.ZERO, "warning has no collision")
	_check(GhostModel.hitbox(_event(2500.0, false), 140, 20).size == Vector2(72.0, 96.0), "dangerous phase exposes the shared 72x96 contact rectangle")
	for speed in [250.0, 500.0, 750.0]:
		for from_ceiling in [false, true]:
			var escaped := _simulate_route(from_ceiling, speed, true)
			var unflipped := _simulate_route(from_ceiling, speed, false)
			_check(bool(escaped.get("safe", false)) and bool(escaped.get("activated", false)), "a real RunnerMotion lane change avoids the activated %s ghost at %.0f px/s" % ["ceiling" if from_ceiling else "floor", speed])
			_check(int(unflipped.get("contact_tick", -1)) > 0, "running straight into the activated %s ghost contacts it at %.0f px/s" % ["ceiling" if from_ceiling else "floor", speed])
	var ghost_count := 0
	var floor_count := 0
	var ceiling_count := 0
	for seed in range(1, 121):
		var built: Dictionary = Builder.new().build(seed, 45000, CourseGeneratorScript.GENERATOR_VERSION_11)
		var manifest: Variant = built.get("manifest")
		_check(manifest != null, "gen11 manifest seed %d builds: %s" % [seed, str(built.get("error", ""))])
		if manifest == null:
			continue
		var rebuilt: Dictionary = Builder.new().build(seed, 45000, CourseGeneratorScript.GENERATOR_VERSION_11)
		_check(str(manifest.manifest_hash) == str(rebuilt.manifest.manifest_hash), "ghost manifest is deterministic for seed %d" % seed)
		for event in manifest.events:
			if str(event.get("kind", "")) == "ghost":
				ghost_count += 1
				var biome: String = preload("res://biomes/biome_renderer.gd").biome_id_at(float(event.x) - float(manifest.start_x))
				_check(biome == "haunted", "seed %d ghost is restricted to the haunted biome" % seed)
				_check(int(event.get("blocked_lanes", 0)) in [1, 2], "seed %d ghost occupies exactly one lane" % seed)
				floor_count += 1 if int(event.blocked_lanes) == 1 else 0
				ceiling_count += 1 if int(event.blocked_lanes) == 2 else 0
		_check(not _has_ghost(seed, CourseGeneratorScript.GENERATOR_VERSION_10), "gen10 manifest seed %d preserves the no-ghost contract" % seed)
	_check(ghost_count > 0, "the bounded gen11 cohort includes haunted ghosts (%d)" % ghost_count)
	_check(floor_count > 0 and ceiling_count > 0, "both floor and ceiling ghost lanes occur in the bounded cohort")
	_check(floor_count + ceiling_count == ghost_count, "every generated ghost has one deterministic lane")
	_check(_shared_world_contact(), "the real shared world uses the activation commit and tick-based ghost contact")

func _has_ghost(seed: int, version: int) -> bool:
	var built: Dictionary = Builder.new().build(seed, 45000, version)
	if built.get("manifest") == null:
		return false
	for event in built.manifest.events:
		if str(event.get("kind", "")) == "ghost":
			return true
	return false

func _shared_world_contact() -> bool:
	for seed in range(1, 121):
		var built: Dictionary = Builder.new().build(seed, 45000, CourseGeneratorScript.GENERATOR_VERSION_11)
		var manifest: Variant = built.get("manifest")
		if manifest == null:
			continue
		for event in manifest.events:
			if str(event.get("kind", "")) != "ghost":
				continue
			var world := WorldSimulation.new()
			var configure_error := str(world.configure(manifest))
			if not configure_error.is_empty():
				print("GHOST_WORLD_CONFIG_ERROR seed=%d error=%s" % [seed, configure_error])
				return false
			var event_id := str(event.event_id)
			var commit := {"world_revision": 1, "commit_id": "ghost-test", "entity_id": event_id, "incarnation": 1, "action": "activate_ghost", "effective_tick": 10, "ghost_activation_tick": 10, "state_before": "active", "state_after": "active"}
			var commit_result := str(world.apply_world_commit(commit))
			if commit_result != "applied":
				print("GHOST_WORLD_COMMIT_ERROR seed=%d result=%s id=%s" % [seed, commit_result, event_id])
				return false
			for tick in range(1, 131):
				if not world.step_to(tick):
					print("GHOST_WORLD_TICK_ERROR seed=%d tick=%d current=%d" % [seed, tick, world.tick])
					return false
			var x := float(event.get("x", 0.0))
			var lane_y := float(event.get("floor_y", 460.0)) - Motion.SIZE.y * 0.5 if not bool(event.get("from_ceiling", false)) else float(event.get("ceiling_y", 80.0)) + Motion.SIZE.y * 0.5
			var player_state := {"world_x": x, "y": lane_y, "gravity_direction": -1 if bool(event.get("from_ceiling", false)) else 1}
			var danger := world.player_contact_at(player_state, 130)
			if str(danger.get("reason", "")) != "ghost":
				print("GHOST_WORLD_DANGER_MISSING seed=%d id=%s tick=%d event=%s contact=%s" % [seed, event_id, world.tick, JSON.stringify(event), JSON.stringify(danger)])
				return false
			var warning := world.player_contact_at(player_state, 129)
			if str(warning.get("reason", "")) == "ghost":
				print("GHOST_WORLD_WARNING_LETHAL seed=%d" % seed)
				return false
			return true
	return false

func _simulate_route(from_ceiling: bool, speed: float, flip: bool) -> Dictionary:
	var event := _event(2500.0, from_ceiling)
	var initial_lane := -1 if from_ceiling else 1
	var state := {"y": 102.0 if from_ceiling else 438.0, "gravity_direction": initial_lane, "vertical_speed": 0.0, "cooldown": 0.84, "grounded": true}
	var requested_flip := false
	var contact_tick := -1
	var lane_rect := GhostModel.hitbox(event, 0, 0)
	for tick in range(1, 700):
		if tick == 12:
			state.cooldown = 0.64 # 200 ms prior-hazard cooldown remains when warning begins.
		if tick == 60 and flip:
			requested_flip = Motion.try_flip(state, -initial_lane, 2.0)
		Motion.advance_vertical(state, 1.0 / 60.0, 460.0, 80.0, true, true)
		var player_x := speed * float(tick) / 60.0
		var player_rect := Rect2(Vector2(player_x, float(state.y)) - Motion.SIZE * 0.5, Motion.SIZE)
		var ghost_rect := GhostModel.hitbox(event, tick, 0)
		if ghost_rect.size != Vector2.ZERO and HazardRules.player_impact(player_rect, "block", ghost_rect) == HazardRules.PlayerImpact.LETHAL:
			contact_tick = tick
			break
	var safe_lane := float(state.y) < 124.0 if not from_ceiling else float(state.y) > 416.0
	return {"safe": requested_flip and contact_tick < 0 and safe_lane, "contact_tick": contact_tick, "activated": GhostModel.trigger_x(event) <= 0.0, "lane_hitbox": lane_rect.size}

func _event(x: float, from_ceiling: bool) -> Dictionary:
	return {"event_id": "ghost:test", "kind": "ghost", "x": x, "width": 72.0, "height": 96.0, "floor_y": 460.0, "ceiling_y": 80.0, "from_ceiling": from_ceiling, "blocked_lanes": 2 if from_ceiling else 1, "trigger_lead": 2500.0, "warning_ticks": 120, "danger_ticks": 500, "fade_ticks": 45}

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
