extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder := Builder.new()
	for seed_value in [1, 42, 100000014]:
		var summaries: Dictionary = {}
		for version in [8, 9]:
			var built: Dictionary = builder.build(seed_value, 45000, version)
			var manifest: Resource = built.get("manifest")
			if manifest == null:
				push_error("seed %d version %d failed: %s" % [seed_value, version, str(built.get("error", "unknown"))])
				quit(1)
				return
			var counts := {"spikes": 0, "barrels": 0, "rock": 0, "saw": 0}
			var relevant: Array[float] = []
			for event_value in manifest.get("events"):
				var event: Dictionary = event_value
				var kind := str(event.get("kind", ""))
				if counts.has(kind):
					counts[kind] = int(counts[kind]) + 1
					relevant.append(float(event.get("course_distance", event.get("x", 0.0))))
			relevant.sort()
			var max_gap := 0.0
			for index in range(1, relevant.size()):
				max_gap = maxf(max_gap, relevant[index] - relevant[index - 1])
			summaries[version] = {"counts": counts, "max_gap_px": max_gap, "total": relevant.size()}
		print("V9_DENSITY_SAMPLE seed=%d v8=%s v9=%s" % [seed_value, JSON.stringify(summaries[8]), JSON.stringify(summaries[9])])
	quit(0)
