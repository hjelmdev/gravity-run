extends Node
## Exercises the real main._start_run and _spawn_shared_coins SP adapter
## against immutable Gen20 MP plans.

const MainScene := preload("res://main.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Planner := preload("res://systems/shared_coin_planner.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const COURSE_LENGTH := 45000
const SEEDS: Array[int] = [100000006, 100000014, 100000019, 100000030]
const GEN19_TRACE_SEED := 1580534762

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder := Builder.new()
	for seed_value in SEEDS:
		var result: Dictionary = builder.build(seed_value, COURSE_LENGTH, 20)
		var manifest: Variant = result.get("manifest")
		_check(manifest != null, "Gen20 MP manifest builds for seed %d" % seed_value)
		if manifest == null:
			continue
		var game := MainScene.instantiate() as Node
		game.set_process(false)
		game.set_physics_process(false)
		get_tree().root.add_child(game)
		await get_tree().process_frame
		game.set_process(false)
		game.set_physics_process(false)
		var ruleset: Resource = builder.call("_make_multiplayer_ruleset", 20)
		ChallengeService.set("active", true)
		ChallengeService.set("seed_value", seed_value)
		ChallengeService.set("generation_version", 20)
		ChallengeService.set("ruleset", ruleset)
		game.set("demo_mode", false)
		game.call("_start_run")
		game.set_process(false)
		game.set_physics_process(false)
		_check(int(game.get("_active_seed")) == seed_value and int(game.get("_active_seed_version")) == 20, "real main run starts requested seed/version")
		game.call("_record_coin_trace", "disabled_probe", "diagnostics-off", Vector2.ZERO)
		_check((game.get("_coin_trace_events") as Array).is_empty(), "coin trace allocates no records when diagnostics are disabled")
		game.call("set_render_diagnostics_enabled", true)
		var node_coins: Array = game.get("coins")
		for coin in node_coins:
			if is_instance_valid(coin): coin.queue_free()
		game.set("coins", [])
		game.set("_pending_shared_coins", [])
		game.set("_spawned_shared_coin_ids", {})
		var distance := 0.0
		while distance <= float(COURSE_LENGTH) + 2000.0:
			game.set("course_distance", distance)
			game.call("_spawn_shared_coins")
			distance += 2000.0
		var actual: Array = []
		for coin in game.get("coins"):
			if not is_instance_valid(coin) or coin.is_queued_for_deletion():
				continue
			if float(coin.position.x) <= float(manifest.finish_x):
				actual.append([snappedf(float(coin.position.x), 0.01), snappedf(float(coin.position.y), 0.01)])
		for item in game.get("_pending_shared_coins"):
			if float(item.get("world_x", INF)) <= float(manifest.finish_x):
				actual.append([snappedf(float(item.get("world_x", 0.0)), 0.01), snappedf(float(item.get("world_y", 0.0)), 0.01)])
		actual.sort_custom(func(a: Array, b: Array) -> bool:
			if not is_equal_approx(float(a[0]), float(b[0])):
				return float(a[0]) < float(b[0])
			return float(a[1]) < float(b[1])
		)
		var expected: Array = []
		for coin in manifest.collectibles:
			expected.append([snappedf(float(coin.world_x), 0.01), snappedf(float(coin.world_y), 0.01)])
		_check(actual == expected, "real main streamed SP coin scene nodes and pending rows match MP plan seed=%d counts=%d/%d" % [seed_value, actual.size(), expected.size()])
		print("GEN20_MAIN_COIN_INTEGRATION seed=%d coins_sp=%d coins_mp=%d equal=%s" % [seed_value, actual.size(), expected.size(), str(actual == expected)])
		if seed_value == SEEDS[0]:
			var spawned: Array = game.get("coins")
			var trace_coin: Node2D = null
			for candidate in spawned:
				if is_instance_valid(candidate) and not bool(candidate.call("is_collected")):
					trace_coin = candidate
					break
			_check(trace_coin != null, "actual SP coin adapter spawned a node for diagnostic trace")
			if trace_coin != null:
				var center: Vector2 = trace_coin.global_position
				var sweep_start := Rect2(center + Vector2(-55.0, -10.0), Vector2(28.0, 20.0))
				var sweep_end := Rect2(sweep_start.position + Vector2(100.0, 0.0), sweep_start.size)
				var fraction := HazardRules.swept_rect_circle_fraction(sweep_start, sweep_end.position - sweep_start.position, center, 13.0)
				var before_coins := int(game.get("run_state").get("coins"))
				game.call("_record_coin_sweep_diagnostic", trace_coin, sweep_start, sweep_end, fraction, 2.0)
				trace_coin.call("collect")
				var after_coins := int(game.get("run_state").get("coins"))
				_check(fraction >= 0.0 and after_coins == before_coins + 1 and bool(trace_coin.call("is_collected")), "scene coin contact fixture runs the real collection burst and emits one award")
				var uncollected: Node2D = null
				for candidate in spawned:
					if is_instance_valid(candidate) and candidate != trace_coin and not bool(candidate.call("is_collected")):
						uncollected = candidate
						break
				if uncollected != null:
					uncollected.position.x = 0.0
					game.call("_record_uncollected_coin_expiry", 1000.0)
				var diagnostic_report: Dictionary = game.call("_build_render_diagnostics_report")
				var coin_trace: Dictionary = diagnostic_report.get("coin_trace", {})
				var events: Array = coin_trace.get("events", [])
				_check(bool(coin_trace.get("enabled", false)) and int(coin_trace.get("event_count", 0)) > 0, "smoothness export carries enabled bounded coin trace")
				_check(_has_trace_action(events, "spawned") and _has_trace_action(events, "swept_contact") and _has_trace_action(events, "collected"), "trace reports spawn, swept contact, and collection stages")
				if uncollected != null:
					_check(_has_trace_reason(events, "camera_passed_uncollected"), "trace reports explicit offscreen/uncollected reason")
				for index in range(520):
					game.call("_record_coin_trace", "cap_probe", "cap_%d" % index, Vector2(index, 0.0), {}, "cap:%d" % index)
				_check((game.get("_coin_trace_events") as Array).size() == 512 and int(game.get("_coin_trace_dropped")) > 0, "coin trace is capped and counts dropped records")
		elif seed_value == SEEDS[1]:
			game.call("set_render_diagnostics_enabled", false)
			game.call("set_render_diagnostics_enabled", true)
			var snapshot_report: Dictionary = game.call("_build_render_diagnostics_report")
			var snapshot_events: Array = snapshot_report.get("coin_trace", {}).get("events", [])
			_check(_has_trace_action(snapshot_events, "spawned_before_capture"), "mid-run trace snapshots already-spawned active coin nodes")
		game.queue_free()
		await get_tree().process_frame
	ChallengeService.set("active", false)
	await _test_gen19_coin_trace(builder)
	print("GEN20_MAIN_COIN_INTEGRATION_TEST failures=%d seeds=%d" % [failures, SEEDS.size()])
	get_tree().quit(1 if failures > 0 else 0)

func _test_gen19_coin_trace(builder: RefCounted) -> void:
	var game := MainScene.instantiate() as Node
	game.set_process(false)
	game.set_physics_process(false)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	ChallengeService.set("active", true)
	ChallengeService.set("seed_value", GEN19_TRACE_SEED)
	ChallengeService.set("generation_version", 19)
	ChallengeService.set("ruleset", builder.call("_make_multiplayer_ruleset", 19))
	game.set("demo_mode", false)
	game.call("_start_run")
	game.set_process(false)
	game.set_physics_process(false)
	game.call("set_render_diagnostics_enabled", true)
	for distance in range(0, 8001, 500):
		game.set("course_distance", float(distance))
		game.call("_spawn_shared_coins")
	var traced_coin: Node2D = null
	for coin in game.get("coins"):
		if is_instance_valid(coin) and not bool(coin.call("is_collected")):
			traced_coin = coin
			break
	_check(traced_coin != null, "public Gen19 seed spawns a coin through actual main adapter for trace check")
	if traced_coin != null:
		var center: Vector2 = traced_coin.global_position
		var start_rect := Rect2(center + Vector2(-55.0, -10.0), Vector2(28.0, 20.0))
		var end_rect := Rect2(start_rect.position + Vector2(100.0, 0.0), start_rect.size)
		var fraction := HazardRules.swept_rect_circle_fraction(start_rect, end_rect.position - start_rect.position, center, 13.0)
		var before := int(game.get("run_state").get("coins"))
		game.call("_record_coin_sweep_diagnostic", traced_coin, start_rect, end_rect, fraction, 2.0)
		traced_coin.call("collect")
		var after := int(game.get("run_state").get("coins"))
		var report: Dictionary = game.call("_build_render_diagnostics_report")
		var trace: Dictionary = report.get("coin_trace", {})
		var events: Array = trace.get("events", [])
		_check(int(report.get("session", {}).get("generator_version", -1)) == 19 and int(report.get("session", {}).get("seed", -1)) == GEN19_TRACE_SEED, "smoothness coin trace preserves real Gen19 seed/version")
		_check(fraction >= 0.0 and after == before + 1 and bool(traced_coin.call("is_collected")) and _has_trace_action(events, "collected"), "Gen19 actual coin collection burst records one award after swept-contact trace")
	game.queue_free()
	await get_tree().process_frame
	ChallengeService.set("active", false)
	print("GEN19_COIN_TRACE seed=%d failures_so_far=%d" % [GEN19_TRACE_SEED, failures])

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _has_trace_action(events: Array, action: String) -> bool:
	for event in events:
		if str(event.get("action", "")) == action:
			return true
	return false

func _has_trace_reason(events: Array, reason: String) -> bool:
	for event in events:
		if str(event.get("reason", "")) == reason:
			return true
	return false
