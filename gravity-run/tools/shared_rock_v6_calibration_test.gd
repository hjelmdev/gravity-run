extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")

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
		var built: Dictionary = builder.build(seed, 45000, 6)
		_check(str(built.get("error", "")).is_empty(), "v6 seed %d builds: %s" % [seed, built.get("error", "")])
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
				_check(float(event.get("trigger_lead", 0.0)) >= 1100.0 and int(event.get("warning_ticks", 0)) >= 36 and int(event.get("fall_ticks", 0)) >= 20, "rock timing keeps the reviewed safety margins")
			elif kind == "spikes":
				spike_total += 1
		if seed_rocks > 0:
			seeds_with_rocks += 1
	var rock_mean := float(rock_total) / 200.0
	var spike_mean := float(spike_total) / 200.0
	print("V6 200-seed 45k distribution: rocks=%d (mean=%.3f, seeds=%d/200), spikes=%d (mean=%.3f), early<10k=%d, early<20k=%d; earliest_seed=%d distance=%.1f" % [rock_total, rock_mean, seeds_with_rocks, spike_total, spike_mean, early_10k, early_20k, first_seed, first_distance])
	_check(rock_mean <= spike_mean * 0.5, "spike groups remain at least twice as common as accepted rocks")
	_check(rock_mean >= 2.0 and rock_mean <= 4.0 and seeds_with_rocks >= 170, "v6 reaches the calibration target without bypassing route safety")
	_check(first_seed > 0 and first_distance < 20000.0, "a reproducible early rock exists within the first 20k")
	quit(1 if failed > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failed += 1
	push_error(message)
