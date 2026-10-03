extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder := Builder.new()
	for seed_value in [1, 42, 100000014]:
		var result: Dictionary = builder.build(seed_value, 45000, Generator.GENERATOR_VERSION_9)
		var manifest: Resource = result.get("manifest")
		print("V9 seed=%d error=%s hash=%s" % [seed_value, str(result.get("error", "")), str(manifest.get("manifest_hash")) if manifest != null else "missing"])
		if manifest == null:
			var generator := Generator.new()
			generator.configure_ruleset(builder._make_multiplayer_ruleset(Generator.GENERATOR_VERSION_9), Generator.GENERATOR_VERSION_9)
			generator.reset(seed_value)
			generator.ensure_horizon(45000.0, 500.0)
			var resolved: Array[Dictionary] = builder._resolve_events(generator.get_planned_events(), 45000)
			for event in resolved:
				if str(event.get("kind", "")) == "saw":
					print("BAD_SAW ", JSON.stringify(event))
		if manifest != null:
			var saw_count := 0
			for event in manifest.get("events"):
				if str(event.get("kind", "")) == "saw":
					saw_count += 1
			print("events=%d saws=%d bytes=%d" % [manifest.get("events").size(), saw_count, manifest.to_canonical_json().to_utf8_buffer().size()])
	quit(0)
