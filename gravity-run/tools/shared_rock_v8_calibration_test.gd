extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")

var failures := 0
var rock_total := 0
var spike_total := 0
var seeds_with_rocks := 0
var first_seed := -1
var first_distance := INF

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder: RefCounted = Builder.new()
	for seed in range(100000000, 100000200):
		var built: Dictionary = builder.build(seed, 45000, Generator.GENERATOR_VERSION)
		_check(str(built.get("error", "")).is_empty(), "v8 seed %d builds: %s" % [seed, built.get("error", "")])
		var manifest: Resource = built.get("manifest") as Resource
		if manifest == null:
			continue
		var seed_rocks := 0
		for event in manifest.get("events"):
			match str(event.get("kind", "")):
				"rock":
					seed_rocks += 1
					rock_total += 1
					var distance := float(event.get("x", INF)) - float(manifest.get("start_x"))
					if distance < first_distance:
						first_seed = seed
						first_distance = distance
					_check(int(event.get("warning_ticks", 0)) == 104 and int(event.get("fall_ticks", 0)) == 42 and is_equal_approx(float(event.get("trigger_lead", 0.0)), 1600.0), "v8 uses the versioned visible-drop geometry")
				"spikes":
					spike_total += 1
		if seed_rocks > 0:
			seeds_with_rocks += 1
	var rock_mean := float(rock_total) / 200.0
	var spike_mean := float(spike_total) / 200.0
	print("V8 200-seed 45k distribution: rocks=%d (mean=%.3f, seeds=%d/200), spikes=%d (mean=%.3f); earliest_seed=%d distance=%.1f" % [rock_total, rock_mean, seeds_with_rocks, spike_total, spike_mean, first_seed, first_distance])
	_check(rock_mean < spike_mean, "accepted rocks remain less common than spike groups")
	_check(rock_mean >= 3.5 and seeds_with_rocks >= 180, "v8 keeps the calibrated rock frequency while preserving route checks")
	_check(first_seed >= 100000000 and first_distance < 20000.0, "a reproducible early v8 rock uses a valid challenge seed")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
