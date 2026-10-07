extends Node
## Bounded actual-main adapter cost comparison at 60Hz-equivalent distance steps.

const MainScene := preload("res://main.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const SPEED := 500.0
const SEED := 100000014

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var summaries: Dictionary = {}
	for distance in [10000.0, 45000.0]:
		summaries[distance] = {}
		for version in [19, 20]:
			var summary := await _measure_version(int(version), float(distance))
			summaries[distance][version] = summary
			print("GEN20_COIN_REPLAN_COST gen=%d seed=%d distance=%.1f refreshes=%d spawned=%d elapsed_ms=%.3f max_refresh_ms=%.3f" % [version, SEED, float(summary.distance), int(summary.refreshes), int(summary.spawned), float(summary.elapsed_usec) / 1000.0, float(summary.max_refresh_usec) / 1000.0])
		var legacy: Dictionary = summaries[distance][19]
		var current: Dictionary = summaries[distance][20]
		_check(int(current.refreshes) < int(legacy.refreshes), "Gen20 batching reduces full-prefix resolve refresh count at %.0fpx" % distance)
		_check(float(current.elapsed_usec) < float(legacy.elapsed_usec), "Gen20 total adapter work remains below Gen19 at %.0fpx" % distance)
		_check(int(current.spawned) > 0 and int(legacy.spawned) > 0, "both versions exercised actual main coin scene spawning at %.0fpx" % distance)
	var legacy_45k: Dictionary = summaries[45000.0][19]
	var current_45k: Dictionary = summaries[45000.0][20]
	_check(int(current_45k.refreshes) <= 200 and int(current_45k.refreshes) >= 150 and int(legacy_45k.refreshes) >= 400, "45km refresh counts match the 250px vs 100px thresholds")
	print("GEN20_COIN_REPLAN_COST_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _measure_version(version: int, course_length: float) -> Dictionary:
	var game := MainScene.instantiate() as Node
	game.set_process(false)
	game.set_physics_process(false)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var builder := Builder.new()
	ChallengeService.set("active", true)
	ChallengeService.set("seed_value", SEED)
	ChallengeService.set("generation_version", version)
	ChallengeService.set("ruleset", builder.call("_make_multiplayer_ruleset", version))
	game.set("demo_mode", false)
	game.call("_start_run")
	game.set_process(false)
	game.set_physics_process(false)
	var previous_planned_until := float(game.get("_shared_coin_planned_until"))
	var refreshes := 0
	var max_refresh_usec := 0
	var started_usec := Time.get_ticks_usec()
	var frame_count := int(round(course_length / SPEED * 60.0))
	for frame in range(frame_count + 1):
		var distance := minf(float(frame) * SPEED / 60.0, course_length)
		game.set("course_distance", distance)
		var before_until := float(game.get("_shared_coin_planned_until"))
		var call_started := Time.get_ticks_usec()
		game.call("_spawn_shared_coins")
		var call_elapsed := Time.get_ticks_usec() - call_started
		var after_until := float(game.get("_shared_coin_planned_until"))
		if after_until > before_until + 0.001:
			refreshes += 1
			max_refresh_usec = maxi(max_refresh_usec, call_elapsed)
			previous_planned_until = after_until
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	var spawned := 0
	for coin in game.get("coins"):
		if is_instance_valid(coin):
			spawned += 1
	game.queue_free()
	await get_tree().process_frame
	ChallengeService.set("active", false)
	return {"version": version, "distance": course_length, "refreshes": refreshes, "spawned": spawned, "elapsed_usec": elapsed_usec, "max_refresh_usec": max_refresh_usec, "last_planned_until": previous_planned_until}

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error(label)
