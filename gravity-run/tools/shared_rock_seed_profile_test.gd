extends SceneTree

const BuilderScript := preload("res://systems/course_manifest_builder.gd")

var failures := 0
var total_rocks := 0
var seeds_with_rocks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder: RefCounted = BuilderScript.new()
	for seed in range(1, 129):
		var result: Dictionary = builder.build(seed, 45000, 5)
		_check(str(result.get("error", "")).is_empty(), "v5 finite seed %d builds: %s" % [seed, result.get("error", "")])
		var manifest: Variant = result.get("manifest", null)
		if not manifest is Resource:
			continue
		var found := 0
		for event in manifest.get("events"):
			if str(event.get("kind", "")) == "rock":
				found += 1
				_check(float(event.get("trigger_lead", 0.0)) >= 1100.0, "rock event retains early trigger lead")
				_check(int(event.get("warning_ticks", 0)) >= 36 and int(event.get("fall_ticks", 0)) >= 20, "rock event carries warning and fall windows")
		total_rocks += found
		if found > 0:
			seeds_with_rocks += 1
	_check(total_rocks > 0, "v5 finite seeds produce accepted falling rocks")
	print("Rock seed profile: %d accepted rocks across %d/128 seeds at 45,000px." % [total_rocks, seeds_with_rocks])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
