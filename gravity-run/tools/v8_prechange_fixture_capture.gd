extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")

func _initialize() -> void:
	var builder := Builder.new()
	for seed_value in [1, 42, 918273645, 100000014]:
		var result: Dictionary = builder.build(seed_value, 45000, 8)
		var manifest: Resource = result.get("manifest")
		print("V8_PRECHANGE seed=%d error=%s hash=%s" % [seed_value, str(result.get("error", "")), str(manifest.get("manifest_hash")) if manifest != null else "missing"])
	quit(0)
