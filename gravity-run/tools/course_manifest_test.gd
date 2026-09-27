extends SceneTree

const BuilderScript := preload("res://systems/course_manifest_builder.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder: RefCounted = BuilderScript.new()
	var first_result: Dictionary = builder.build(918273645, 45000, 4)
	var second_result: Dictionary = builder.build(918273645, 45000, 4)
	var different_seed_result: Dictionary = builder.build(918273646, 45000, 4)
	_check(first_result.get("error", "") == "", "builder should construct a valid multiplayer manifest: %s" % first_result.get("error", ""))
	_check(second_result.get("error", "") == "", "same-seed rebuild should succeed")
	_check(different_seed_result.get("error", "") == "", "different-seed build should succeed")
	if first_result.get("manifest") is Resource and second_result.get("manifest") is Resource and different_seed_result.get("manifest") is Resource:
		var first: Resource = first_result.manifest
		var second: Resource = second_result.manifest
		var different: Resource = different_seed_result.manifest
		_check(str(first.get("manifest_hash")) == str(second.get("manifest_hash")), "same run definition should generate an identical canonical hash")
		_check(str(first.call("to_canonical_json")) == str(second.call("to_canonical_json")), "same run definition should generate byte-identical canonical JSON")
		_check(str(first.get("manifest_hash")) != str(different.get("manifest_hash")), "different seeds should change the manifest")
		var events: Array = first.get("events")
		_check(events.size() > 40, "the finite course should contain enough planned events")
		var has_slope := false
		var has_gap := false
		var has_barrels := false
		for event in events:
			has_slope = has_slope or str(event.get("kind", "")) == "slope"
			has_gap = has_gap or str(event.get("kind", "")) == "gap"
			has_barrels = has_barrels or str(event.get("kind", "")) == "barrels"
		_check(has_slope, "manifest should include resolved slopes when generated")
		_check(has_gap, "manifest should include track gaps when generated")
		_check(has_barrels, "multiplayer should include the shared generator's independent barrel encounters")
		_check(str(first.call("validate")).is_empty(), "fresh manifest should pass its own schema and hash validation")
		var tampered_events: Array = events.duplicate(true)
		tampered_events[0]["x"] = float(tampered_events[0]["x"]) + 1.0
		first.set("events", tampered_events)
		_check(not str(first.call("validate")).is_empty(), "tampering with canonical event geometry should fail hash validation")
	var invalid_result: Dictionary = builder.build(0, 45000, 4)
	_check(invalid_result.get("manifest") == null, "zero seed should be rejected")
	if failures == 0:
		print("Course manifest tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
