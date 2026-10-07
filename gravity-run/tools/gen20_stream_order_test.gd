extends SceneTree
## Confirms Gen20's later ordinary barrels do not make SP's incremental event
## stream out of order or differ from the same generator's full planned prefix.

const Generator := preload("res://systems/course_generator.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000006, 100000014, 100000019, 100000022]
const LENGTH := 45000

func _initialize() -> void:
	var failures := 0
	for seed_value in SEEDS:
		var definition := RunDefinition.new() as Resource
		definition.set("scenario_id", &"multiplayer_race")
		definition.set("seed_value", seed_value)
		definition.set("generator_version", 20)
		definition.set("ruleset", Builder.new().call("_make_multiplayer_ruleset", 20))
		var full := Generator.new() as CourseGenerator
		if not full.configure_run_definition(definition):
			push_error("GEN20_STREAM configure failed seed=%d" % seed_value)
			failures += 1
			continue
		full.ensure_horizon(float(LENGTH), 500.0)
		var expected: Array = []
		var previous := -INF
		for event in full.get_planned_events():
			var distance := float(event.get("course_distance", -1.0))
			if distance < previous:
				push_error("GEN20_STREAM full order violation seed=%d at=%.1f after=%.1f" % [seed_value, previous, distance])
				failures += 1
				break
			previous = distance
			if distance <= LENGTH:
				expected.append(_fingerprint(event))
		var streamed := Generator.new() as CourseGenerator
		if not streamed.configure_run_definition(definition):
			push_error("GEN20_STREAM second configure failed seed=%d" % seed_value)
			failures += 1
			continue
		var actual: Array = []
		for boundary in range(1000, LENGTH + 1000, 1000):
			streamed.ensure_horizon(float(boundary + Generator.EVENT_SPAWN_LEAD_DISTANCE), 500.0)
			for event in streamed.pop_events_until(float(boundary)):
				actual.append(_fingerprint(event))
		var actual_ordered := true
		for index in range(1, actual.size()):
			if float(actual[index].distance) < float(actual[index - 1].distance):
				actual_ordered = false
		if actual != expected or not actual_ordered:
			push_error("GEN20_STREAM prefix mismatch seed=%d expected=%d actual=%d ordered=%s" % [seed_value, expected.size(), actual.size(), str(actual_ordered)])
			failures += 1
		print("GEN20_STREAM seed=%d events=%d barrels=%d order=true prefix_equal=%s" % [seed_value, actual.size(), _count_kind(full.get_planned_events(), "barrels"), str(actual == expected)])
	print("GEN20_STREAM_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _fingerprint(event: Dictionary) -> Dictionary:
	return {"distance": snappedf(float(event.get("course_distance", 0.0)), 0.001), "kind": str(event.get("kind", "")), "id": str(event.get("id", "")), "profile": str(event.get("profile_id", "")), "width": snappedf(float(event.get("width", 0.0)), 0.001), "spiked": bool(event.get("spiked", false))}

func _count_kind(events: Array, kind: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("kind", "")) == kind:
			count += 1
	return count
