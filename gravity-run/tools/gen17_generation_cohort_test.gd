extends SceneTree
## Bounded comparison of accepted, post-validation manifest encounters and coins.

const Builder := preload("res://systems/course_manifest_builder.gd")
const GEN16 := 16
const GEN17 := 17
const FIRST_SEED := 100000001
const SEED_COUNT := 40
const COURSE_LENGTH := 45000
const HAZARDS := ["spikes", "block", "barrels", "rock", "ghost", "saw", "lava_crack", "volcano"]

func _initialize() -> void:
	var builder := Builder.new()
	var totals := {16: {"events": 0, "coins": 0, "new": 0, "chaser": 0, "icicle": 0, "pool": 0, "max_gap": 0.0}, 17: {"events": 0, "coins": 0, "new": 0, "chaser": 0, "icicle": 0, "pool": 0, "max_gap": 0.0}}
	var build_failures := 0
	for offset in range(SEED_COUNT):
		var seed_value := FIRST_SEED + offset
		for generator_version in [GEN16, GEN17]:
			var result: Dictionary = builder.build(seed_value, COURSE_LENGTH, generator_version)
			var manifest: Variant = result.get("manifest")
			if manifest == null:
				build_failures += 1
				continue
			var positions: Array[float] = []
			var counts: Dictionary = totals[generator_version]
			counts["coins"] = int(counts["coins"]) + manifest.collectibles.size()
			for event in manifest.events:
				var kind := str(event.get("kind", ""))
				if kind not in HAZARDS:
					continue
				counts["events"] = int(counts["events"]) + 1
				positions.append(float(event.get("x", 0.0)))
				if generator_version == GEN17 and kind == "ghost" and int(event.get("ghost_variant", 0)) == 1:
					counts["new"] = int(counts["new"]) + 1
					counts["chaser"] = int(counts["chaser"]) + 1
				elif generator_version == GEN17 and kind == "rock" and int(event.get("rock_variant", 0)) == 1:
					counts["new"] = int(counts["new"]) + 1
					counts["icicle"] = int(counts["icicle"]) + 1
				elif generator_version == GEN17 and kind == "lava_crack" and int(event.get("lava_variant", 0)) == 1:
					counts["new"] = int(counts["new"]) + 1
					counts["pool"] = int(counts["pool"]) + 1
			positions.sort()
			var prior_x := float(manifest.get("start_x"))
			for x in positions:
				counts["max_gap"] = maxf(float(counts["max_gap"]), x - prior_x)
				prior_x = x
			counts["max_gap"] = maxf(float(counts["max_gap"]), float(manifest.get("course_length_px")) + float(manifest.get("start_x")) - prior_x)
	var span := float(SEED_COUNT * COURSE_LENGTH) / 1000.0
	for generator_version in [GEN16, GEN17]:
		print("GEN17_COHORT version=%d seeds=%d accepted_hazards=%d per_1000px=%.3f coins=%d coins_per_1000px=%.3f variants=%d(chaser=%d,icicle=%d,pool=%d) max_center_gap=%.1fpx build_failures=%d" % [generator_version, SEED_COUNT, int(totals[generator_version].events), float(totals[generator_version].events) / span, int(totals[generator_version].coins), float(totals[generator_version].coins) / span, int(totals[generator_version].new), int(totals[generator_version].chaser), int(totals[generator_version].icicle), int(totals[generator_version].pool), float(totals[generator_version].max_gap), build_failures])
	quit(0 if build_failures == 0 else 1)
