extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const Ruleset := preload("res://systems/course_generation_ruleset.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Planner := preload("res://systems/shared_coin_planner.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	for seed_value in [100000014, 100000042, 100001918]:
		var length := 45000
		var built: Dictionary = Builder.new().build(seed_value, length, 8)
		if built.get("manifest") == null:
			failures.append("MP manifest failed seed %d" % seed_value)
			continue
		var manifest: Resource = built.manifest
		var definition = RunDefinition.new()
		var ruleset: Resource = Ruleset.new()
		ruleset.set("revision", 5)
		ruleset.set("event_density", 1.5)
		definition.set("scenario_id", &"endless")
		definition.set("seed_value", seed_value)
		definition.set("generator_version", 8)
		definition.set("ruleset", ruleset)
		var generator = Generator.new()
		if not generator.configure_run_definition(definition):
			failures.append("SP generator config failed seed %d" % seed_value)
			continue
		generator.ensure_horizon(float(length), 500.0, Generator.REFERENCE_TRACK_HEIGHT, Generator.EVENT_SPAWN_LEAD_DISTANCE)
		var source_events: Array[Dictionary] = generator.get_planned_events()
		var resolved: Array[Dictionary] = Builder.new().call("_resolve_events", source_events, length)
		var stream = Planner.new()
		stream.reset(seed_value, Builder.PLAYER_START_X, int(ruleset.get("coin_revision")), float(ruleset.get("coin_density")))
		var streamed: Array[Dictionary] = []
		var cursor := 0.0
		while cursor < float(length) + Builder.PLAYER_START_X:
			cursor = minf(cursor + 5173.0, float(length) + Builder.PLAYER_START_X)
			streamed.append_array(stream.extend(cursor, resolved, Builder.FLOOR_START_Y, Builder.CEILING_START_Y, 0))
		var mp_coins: Array = manifest.collectibles
		if JSON.stringify(streamed) != JSON.stringify(mp_coins):
			failures.append("SP stream/MP manifest coin mismatch seed %d (%d/%d)" % [seed_value, streamed.size(), mp_coins.size()])
		var rock_params: Dictionary = {}
		var sp_hazards := 0
		var mp_hazards := 0
		for event in resolved:
			if str(event.get("kind", "")) in ["block", "spikes", "barrel", "rock", "step", "gap"]: sp_hazards += 1
		for event in manifest.events:
			if str(event.get("kind", "")) in ["block", "spikes", "barrel", "rock", "step", "gap"]: mp_hazards += 1
			if str(event.get("kind", "")) == "rock": rock_params = event
		var presentation: Node2D = Presentation.new()
		presentation.load_manifest(manifest)
		var presented_coins := 0
		for entity_id in presentation.event_nodes:
			if str(entity_id).begins_with("coin_"): presented_coins += 1
		if presented_coins != mp_coins.size(): failures.append("MP presentation node count mismatch seed %d (%d/%d)" % [seed_value, presented_coins, mp_coins.size()])
		print("coin_parity seed=%d length=%d SP-generated=%d SP-streamed=%d MP-manifest=%d MP-presented=%d SP-hazards=%d MP-hazards=%d largest_coin_gap=%.1f rock_warning=%d(%.2fs) rock_fall=%d(%.2fs)" % [seed_value, length, streamed.size(), streamed.size(), mp_coins.size(), presented_coins, sp_hazards, mp_hazards, _largest_coin_gap(streamed), int(rock_params.get("warning_ticks", 0)), float(rock_params.get("warning_ticks", 0)) / 60.0, int(rock_params.get("fall_ticks", 0)), float(rock_params.get("fall_ticks", 0)) / 60.0])
		presentation.free()
	if failures.is_empty():
		print("shared_coin_mode_parity_test: PASS")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _largest_coin_gap(coins: Array) -> float:
	var previous := float(Builder.PLAYER_START_X)
	var largest := 0.0
	for coin in coins:
		largest = maxf(largest, float(coin.world_x) - previous)
		previous = float(coin.world_x)
	return maxf(largest, float(Builder.PLAYER_START_X + 45000) - previous)
