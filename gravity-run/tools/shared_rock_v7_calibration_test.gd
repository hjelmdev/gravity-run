extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")

var failed := 0
var rock_total := 0
var spike_total := 0
var seeds_with_rocks := 0
var early_10k := 0
var early_20k := 0
var first_seed := -1
var first_distance := INF

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder: RefCounted = Builder.new()
	for seed in range(100000000, 100000200):
		var built: Dictionary = builder.build(seed, 45000, Generator.GENERATOR_VERSION)
		_check(str(built.get("error", "")).is_empty(), "v7 seed %d builds: %s" % [seed, built.get("error", "")])
		var manifest: Resource = built.get("manifest") as Resource
		if manifest == null:
			continue
		var seed_rocks := 0
		for event in manifest.get("events"):
			var kind := str(event.get("kind", ""))
			if kind == "rock":
				seed_rocks += 1
				rock_total += 1
				var distance := float(event.get("x", INF)) - float(manifest.get("start_x"))
				if distance < first_distance:
					first_seed = seed
					first_distance = distance
				if distance < 10000.0:
					early_10k += 1
				if distance < 20000.0:
					early_20k += 1
				_check(int(event.get("warning_ticks", 0)) == 90 and int(event.get("fall_ticks", 0)) == 42, "v7 rocks use the longer visible-warning and slower-fall schedule")
			elif kind == "spikes":
				spike_total += 1
		if seed_rocks > 0:
			seeds_with_rocks += 1
	var rock_mean := float(rock_total) / 200.0
	var spike_mean := float(spike_total) / 200.0
	print("V7 200-seed 45k distribution: rocks=%d (mean=%.3f, seeds=%d/200), spikes=%d (mean=%.3f), early<10k=%d, early<20k=%d; earliest_seed=%d distance=%.1f" % [rock_total, rock_mean, seeds_with_rocks, spike_total, spike_mean, early_10k, early_20k, first_seed, first_distance])
	_check(rock_mean < spike_mean, "accepted stones remain less common than spike groups")
	_check(rock_mean >= 3.5 and seeds_with_rocks >= 180, "v7 materially raises accepted-rock frequency without bypassing route checks")
	_check(first_seed > 0 and first_distance < 20000.0, "a reproducible early v7 rock exists within the first 20k")
	quit(1 if failed > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failed += 1
	push_error(message)
