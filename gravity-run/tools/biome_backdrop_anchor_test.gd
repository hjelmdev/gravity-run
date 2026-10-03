extends SceneTree

const Renderer := preload("res://biomes/biome_renderer.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	for boundary: float in [4800.0, 14400.0]:
		for viewport_width: float in [1280.0, 540.0]:
			var start: float = boundary - 10.0
			var finish: float = boundary + 10.0
			for factor: float in [0.055, 0.12, 0.22]:
				var camera_origin: float = start
				var parallax_start: float = camera_origin * factor
				var parallax_end: float = parallax_start + (finish - start)
				var whole := Renderer._landmarks_in_course(parallax_start, parallax_end, 82.0, 13)
				var split_at: float = parallax_start + (boundary - start)
				var split := Renderer._landmarks_in_course(parallax_start, split_at, 82.0, 13)
				split.append_array(Renderer._landmarks_in_course(split_at, parallax_end, 82.0, 13))
				if not _same_points(whole, split):
					push_error("landmark lattice changed when split at theme boundary=%.0f width=%.0f factor=%.3f" % [boundary, viewport_width, factor])
					failures += 1
				var expanded := Renderer._landmarks_in_course(parallax_start - viewport_width, parallax_end + viewport_width, 82.0, 13)
				if whole.size() > expanded.size():
					push_error("landmark set was not bounded by its extended viewport interval")
					failures += 1
	var haunted := load("res://assets/biomes/definitions/haunted.tres") as BiomeDefinition
	if haunted == null or haunted.background_layers.size() < 2:
		push_error("haunted biome must provide replaceable ruin and fog texture layers")
		failures += 1
	else:
		for i in range(haunted.background_layers.size()):
			var height_ratio := haunted.background_layer_height_ratios[i] if i < haunted.background_layer_height_ratios.size() else 0.0
			var parallax := haunted.background_layer_parallax[i] if i < haunted.background_layer_parallax.size() else 0.0
			if haunted.background_layers[i] == null or height_ratio <= 0.0 or parallax <= 0.0:
				push_error("haunted texture layer %d has invalid texture/scale/parallax" % i)
				failures += 1
	if failures == 0:
		print("BIOME_BACKDROP_ANCHOR_TEST PASS boundaries=4800,14400 viewports=1280,540 parallax=0.055,0.12,0.22 split-invariant haunted-layers=2")
		quit(0)
	else:
		push_error("BIOME_BACKDROP_ANCHOR_TEST failures=%d" % failures)
		quit(1)

func _same_points(left: Array[Vector2], right: Array[Vector2]) -> bool:
	if left.size() != right.size():
		return false
	for i in range(left.size()):
		if not is_equal_approx(left[i].x, right[i].x) or not is_equal_approx(left[i].y, right[i].y):
			return false
	return true
