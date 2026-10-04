extends Node
## Local visual evidence from the canonical Gen12 manifest and shared scene.

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const PlayerScene := preload("res://player/player.tscn")
const HudScene := preload("res://ui/hud.tscn")
const OUTPUT_DIR := "E:/Utveckling/Gravity Run/.codex-overnight-review"
const DESIGN_WIDTH := 960.0
const DESIGN_HEIGHT := 540.0

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var biome_manifest: Resource = Builder.new().build(100000014, 100000, Generator.GENERATOR_VERSION_12).get("manifest")
	var barrel_manifest: Resource = Builder.new().build(100000003, 100000, Generator.GENERATOR_VERSION_12).get("manifest")
	if biome_manifest == null or barrel_manifest == null:
		_failures("Could not build the fixed Gen12 capture manifests.")
		return
	var representative: Array[Dictionary] = []
	for target_distance in [2200.0, 6500.0, 11200.0]:
		var best: Dictionary = {}
		var best_delta := INF
		for event in biome_manifest.events:
			var distance := float(event.get("x", 0.0)) - float(biome_manifest.start_x)
			var delta := absf(distance - target_distance)
			if delta < best_delta and str(event.get("kind", "")) in ["block", "spikes", "rock", "saw", "ghost", "barrels"]:
				best = event
				best_delta = delta
		representative.append(best)
	for index in representative.size():
		await _capture_case("biome_%s" % ["classic", "cave", "haunted"][index], biome_manifest, float(representative[index].get("x", 0.0)))
	var risk_coin: Dictionary = {}
	var risk_manifest: Resource = null
	var risk_seed := 0
	for seed_value in [100000014, 100000042, 100000123, 100000777, 100000888, 100001111, 100002222, 100004321]:
		var candidate: Resource = Builder.new().build(seed_value, 100000, Generator.GENERATOR_VERSION_12).get("manifest")
		if candidate == null:
			continue
		for coin in candidate.collectibles:
			if str(coin.get("formation", "")) == "risk":
				risk_coin = coin
				risk_manifest = candidate
				risk_seed = seed_value
				break
		if not risk_coin.is_empty():
			break
	if risk_coin.is_empty():
		_failures("The bounded Gen12 seed cohort no longer has a risk-coin row.")
	else:
		await _capture_case("risk_coins_seed%d" % risk_seed, risk_manifest, float(risk_coin.get("world_x", 0.0)))
	var spiked_event: Dictionary = {}
	for event in barrel_manifest.events:
		if str(event.get("kind", "")) == "barrels" and bool(event.get("spiked", false)):
			spiked_event = event
			break
	if spiked_event.is_empty():
		_failures("Seed 100000003 no longer has a generated spiked-barrel variant.")
	else:
		await _capture_case("spiked_barrel_seed100000003", barrel_manifest, float(spiked_event.get("x", 0.0)))
	if failures.is_empty():
		print("BIOME_RISK_SPIKED_CAPTURE PASS files=10 risk_seed=%d spiked_barrel_seed=100000003" % risk_seed)
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)

func _capture_case(case_name: String, manifest: Resource, focus_x: float) -> void:
	for viewport_size in [Vector2i(1280, 720), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_tree().root.add_child(viewport)
		var presentation := Presentation.new()
		viewport.add_child(presentation)
		var load_error := str(presentation.load_manifest(manifest))
		if not load_error.is_empty():
			_failures("%s manifest presentation failed: %s" % [case_name, load_error])
			viewport.queue_free()
			return
		var camera_scale := minf(float(viewport_size.x) / DESIGN_WIDTH, float(viewport_size.y) / DESIGN_HEIGHT)
		camera_scale = maxf(camera_scale, 0.01)
		var logical_view_size := Vector2(viewport_size) / camera_scale
		var camera_left := maxf(focus_x - logical_view_size.x * 0.55, 0.0)
		presentation.call("set_camera_left", camera_left)
		var camera := Camera2D.new()
		camera.zoom = Vector2.ONE * camera_scale
		camera.position = Vector2(camera_left + logical_view_size.x * 0.5, logical_view_size.y * 0.5)
		viewport.add_child(camera)
		camera.make_current()
		var runner := PlayerScene.instantiate() as Node2D
		var runner_x := camera_left + logical_view_size.x * 0.18
		runner.position = Vector2(runner_x, float(presentation.call("_surface_y_at", runner_x, false)) - 22.0)
		runner.set("world_x", runner.position.x)
		viewport.add_child(runner)
		var hud_layer := CanvasLayer.new()
		viewport.add_child(hud_layer)
		var hud := HudScene.instantiate() as Node2D
		hud_layer.add_child(hud)
		hud.call("set_seed", Generator.GENERATOR_VERSION_12, int(manifest.seed_value))
		hud.call("update_stats", maxf(focus_x - float(manifest.start_x), 0.0), 0)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			_failures("%s produced an empty GPU capture for %s" % [case_name, str(viewport_size)])
		else:
			var suffix := "landscape" if viewport_size.x > viewport_size.y else "portrait"
			var path := "%s/%s_%s.png" % [OUTPUT_DIR, case_name, suffix]
			var save_error := image.save_png(path)
			if save_error != OK:
				_failures("Could not save %s: %s" % [path, error_string(save_error)])
			else:
				print("GEN12_CAPTURE %s %s" % [suffix, path])
		viewport.queue_free()
		await get_tree().process_frame

func _failures(message: String) -> void:
	failures.append(message)
