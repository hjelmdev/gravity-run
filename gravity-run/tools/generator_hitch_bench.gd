extends SceneTree
## Simulates the singleplayer physics loop's generator calls (ensure_horizon +
## get_planned_events) at 60 Hz and reports per-tick cost and an event hash.
## Usage: godot --headless --path . -s res://tools/generator_hitch_bench.gd -- [seconds] [version] [seed] [gen|both]
const Gen := preload("res://systems/course_generator.gd")
const Ruleset := preload("res://systems/course_generation_ruleset.gd")
const RunDef := preload("res://systems/course_run_definition.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 180.0
	var version := int(args[1]) if args.size() > 1 else Gen.GENERATOR_VERSION
	var seed_value := int(args[2]) if args.size() > 2 else 100000042
	var gen = Gen.new()
	var def := RunDef.new()
	def.set("scenario_id", &"endless")
	def.set("seed_value", seed_value)
	def.set("generator_version", version)
	def.set("ruleset", Ruleset.new())
	if not gen.configure_run_definition(def):
		print("CONFIGURE_FAILED"); quit(2); return
	var distance := 0.0
	var speed := 500.0
	var ticks := int(seconds * 60.0)
	var worst := 0
	var worst_tick := 0
	var total := 0
	var over_8ms := 0
	var over_16ms := 0
	var buckets := {}
	var builder = Builder.new()
	var planned_until := -INF
	var resolve_worst := 0
	var resolve_buckets := {}
	var mode := args[3] if args.size() > 3 else "both"
	for tick in ticks:
		distance += speed / 60.0
		var t0 := Time.get_ticks_usec()
		gen.ensure_horizon(distance + 960.0 + 1400.0, speed, 540.0, 1000.0)
		var planned_count := 0
		for e in gen.get_planned_events():
			if str(e.get("kind", "")) == "rock":
				planned_count += 1
		gen.pop_events_until(distance + 1000.0)
		var dt := Time.get_ticks_usec() - t0
		if mode != "gen" and 180.0 + distance + 2360.0 >= planned_until + 250.0:
			var r0 := Time.get_ticks_usec()
			gen.ensure_horizon(180.0 + distance + 2360.0 + 4700.0, speed, 540.0, 1000.0)
			var resolved: Array[Dictionary] = builder.resolve_runtime_events(gen.get_planned_events(), ceili(distance + 2360.0 + 4500.0), version, 0.0)
			planned_until = 180.0 + distance + 2360.0
			var rdt := Time.get_ticks_usec() - r0
			resolve_worst = maxi(resolve_worst, rdt)
			resolve_buckets[tick / 3600] = maxi(int(resolve_buckets.get(tick / 3600, 0)), rdt)
			dt += rdt
		total += dt
		if dt > worst:
			worst = dt; worst_tick = tick
		if dt > 8000: over_8ms += 1
		if dt > 16000: over_16ms += 1
		var minute := tick / 3600
		buckets[minute] = maxi(int(buckets.get(minute, 0)), dt)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var events: Array = gen.get_planned_events()
	var kept: Array = []
	for e in events:
		if float(e.get("course_distance", 0.0)) <= distance:
			kept.append(e)
	ctx.update(JSON.stringify(kept).to_utf8_buffer())
	print("BENCH version=%d seed=%d seconds=%.0f events=%d hash=%s" % [version, seed_value, seconds, kept.size(), ctx.finish().hex_encode().substr(0, 16)])
	print("BENCH total_ms=%.1f avg_us=%.1f worst_ms=%.2f at_s=%.1f ticks_over_8ms=%d over_16ms=%d" % [total / 1000.0, float(total) / ticks, worst / 1000.0, worst_tick / 60.0, over_8ms, over_16ms])
	var line := "BENCH worst_ms_per_minute:"
	for m in buckets.keys():
		line += " %d:%.1f" % [m, buckets[m] / 1000.0]
	print(line)
	line = "BENCH resolve_worst_ms_per_minute:"
	for m in resolve_buckets.keys():
		line += " %d:%.1f" % [m, resolve_buckets[m] / 1000.0]
	print(line)
	quit(0)
