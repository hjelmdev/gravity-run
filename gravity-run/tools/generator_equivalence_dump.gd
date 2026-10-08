extends SceneTree
## Usage: godot --headless --path . -s res://tools/generator_equivalence_dump.gd -- [course_px]
## Run on two checkouts and diff the EQ lines.
## Dumps hashes of generator plans, runtime resolutions and manifests so that a
## performance refactor can be proven output-identical. Not part of the game.
const Gen := preload("res://systems/course_generator.gd")
const Ruleset := preload("res://systems/course_generation_ruleset.gd")
const RunDef := preload("res://systems/course_run_definition.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")

func _h(v: Variant) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(JSON.stringify(v).to_utf8_buffer())
	return c.finish().hex_encode().substr(0, 16)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var length := float(args[0]) if args.size() > 0 else 40000.0
	var versions := [5, 8, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]
	var seeds := [1, 7, 42, 100000014, 100000042, 100000918, 123456789, 987654]
	for version in versions:
		for seed_value in seeds:
			var gen = Gen.new()
			var def := RunDef.new()
			def.set("scenario_id", &"endless"); def.set("seed_value", seed_value); def.set("generator_version", version); def.set("ruleset", Ruleset.new())
			if not gen.configure_run_definition(def):
				print("EQ v=%d s=%d CONFIGURE_FAILED" % [version, seed_value]); continue
			var b = Builder.new()
			var d := 0.0
			var resolve_hashes: Array[String] = []
			var step := 0
			while d < length:
				d += 337.0
				gen.ensure_horizon(d + 2360.0, 500.0, 540.0, 1000.0)
				gen.pop_events_until(d + 1000.0)
				step += 1
				if step % 9 == 0:
					gen.ensure_horizon(d + 7000.0, 500.0, 540.0, 1000.0)
					resolve_hashes.append(_h(b.resolve_runtime_events(gen.get_planned_events(), ceili(d + 6800.0), version, 13.0 * float(version))))
			var events: Array = gen.get_planned_events()
			var stats: Dictionary = gen.get_generation_stats()
			var built: Dictionary = Builder.new().build(seed_value, 30000, version)
			var mh := "none"
			if built.get("manifest") != null:
				mh = str(built.manifest.manifest_hash) + ":" + _h(built.manifest.events)
			print("EQ v=%d s=%d n=%d events=%s stats=%s resolves=%s manifest=%s" % [version, seed_value, events.size(), _h(events), _h(stats), _h(resolve_hashes), mh])
	quit(0)
