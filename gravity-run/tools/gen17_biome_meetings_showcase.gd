extends Node2D
## GPU-only review fixture that draws the production hazard scenes in representative phases.

const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const RockScene := preload("res://hazards/falling_rock.tscn")
const LavaScene := preload("res://hazards/lava_hazard.tscn")

var _floor_y := 460.0
var _ceiling_y := 82.0
var _viewport_size := Vector2.ZERO
var _portrait := false
var _ghosts: Array[Node2D] = []
var _rocks: Array[Node2D] = []
var _pools: Array[Node2D] = []
var _ghost_labels: Array[Control] = []
var _rock_labels: Array[Control] = []
var _pool_labels: Array[Control] = []

func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_portrait = _viewport_size.y > _viewport_size.x
	var bands: Array[Dictionary] = []
	if _portrait:
		for index in range(3):
			var top := _viewport_size.y * float(index) / 3.0
			var bottom := _viewport_size.y * float(index + 1) / 3.0
			bands.append({"top": top, "bottom": bottom, "ceiling": top + 40.0, "floor": bottom - 42.0})
	else:
		bands.append({"top": 0.0, "bottom": _viewport_size.y, "ceiling": 82.0, "floor": minf(_viewport_size.y - 70.0, 460.0)})
	var first: Dictionary = bands[0]
	var second: Dictionary = bands[1] if _portrait else first
	var third: Dictionary = bands[2] if _portrait else first
	var x_left := _viewport_size.x * (0.28 if _portrait else 1.0 / 6.0)
	var x_middle := _viewport_size.x * 0.5
	var x_right := _viewport_size.x * (0.72 if _portrait else 5.0 / 6.0)
	_add_ghost(x_left, 16, 0, "CHASER / WARNING", float(first.floor), float(first.ceiling), float(first.top))
	_add_ghost(x_right, 55, 2, "CHASER / DANGER", float(first.floor), float(first.ceiling), float(first.top))
	_add_icicle(x_left, 18, "ICICLE / WARNING", float(second.floor), float(second.ceiling), float(second.top))
	_add_icicle(x_middle, 63, "ICICLE / FALLING", float(second.floor), float(second.ceiling), float(second.top))
	_add_icicle(x_right, 92, "ICICLE / LODGED", float(second.floor), float(second.ceiling), float(second.top))
	_add_pool(_viewport_size.x * 0.17, 0, "POOL / LOW", float(third.floor), float(third.ceiling), float(third.top))
	_add_pool(_viewport_size.x * 0.5, 45, "POOL / GROWING", float(third.floor), float(third.ceiling), float(third.top))
	_add_pool(_viewport_size.x * 0.83, 90, "POOL / HIGH", float(third.floor), float(third.ceiling), float(third.top))
	queue_redraw()
	await RenderingServer.frame_post_draw
	var out_dir := ProjectSettings.globalize_path("res://.codex-gen17-review")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var all_labels := _ghost_labels + _rock_labels + _pool_labels
	var capture_specs := [
		{"name": "chaser", "nodes": _ghosts, "labels": _ghost_labels},
		{"name": "icicles", "nodes": _rocks, "labels": _rock_labels},
		{"name": "tidal-pool", "nodes": _pools, "labels": _pool_labels},
	]
	var failed := false
	for spec in capture_specs:
		for node in _ghosts + _rocks + _pools:
			node.visible = spec.nodes.has(node)
		for label in all_labels:
			label.visible = spec.labels.has(label)
		queue_redraw()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("gen17-biome-%s-%s.png" % [str(spec.name), "portrait" if _viewport_size.y > _viewport_size.x else "landscape"])
		var error := image.save_png(path)
		print("GEN17_GPU_CAPTURE path=%s size=%s error=%d" % [path, str(image.get_size()), error])
		failed = failed or error != OK
	_pools[1].call("apply_simulation_tick", 135.0, 180.0)
	_pool_labels[1].text = "POOL / RETRACTING"
	for node in _ghosts + _rocks + _pools:
		node.visible = node == _pools[1]
	for label in all_labels:
		label.visible = label == _pool_labels[1]
	queue_redraw()
	await RenderingServer.frame_post_draw
	var retracting_path := out_dir.path_join("gen17-biome-tidal-pool-retracting-%s.png" % ("portrait" if _viewport_size.y > _viewport_size.x else "landscape"))
	var retracting_image := get_viewport().get_texture().get_image()
	var retracting_error := retracting_image.save_png(retracting_path)
	print("GEN17_GPU_CAPTURE path=%s size=%s error=%d" % [retracting_path, str(retracting_image.get_size()), retracting_error])
	failed = failed or retracting_error != OK
	get_tree().quit(2 if failed else 0)

func _add_ghost(x: float, tick: int, skin: int, label: String, floor_y: float, ceiling_y: float, band_top: float) -> void:
	var event := {"event_id": "showcase_chaser_%d" % tick, "kind": "ghost", "ghost_variant": 1, "x": x + 220.0, "width": 72.0, "height": 96.0, "floor_y": floor_y, "ceiling_y": ceiling_y, "trigger_lead": 0.0, "warning_ticks": 54, "danger_ticks": 210, "fade_ticks": 30, "chase_speed": 760.0, "chase_start_lag": 220.0, "skin_variant": skin, "blocked_lanes": 1}
	var ghost := GhostScene.instantiate() as Node2D
	add_child(ghost)
	ghost.call("configure", event)
	ghost.call("set_activation_tick", 0)
	ghost.call("set_simulation_tick", tick)
	_ghosts.append(ghost)
	_ghost_labels.append(_add_label(Vector2(x - 140.0, band_top + 24.0), label))

func _add_icicle(x: float, tick: int, label: String, floor_y: float, ceiling_y: float, band_top: float) -> void:
	var event := {"event_id": "showcase_icicle_%d" % tick, "kind": "rock", "rock_variant": 1, "x": x, "width": 64.0, "height": 116.0, "floor_y": floor_y, "ceiling_y": ceiling_y, "from_ceiling": true, "trigger_lead": 1250.0, "warning_ticks": 48, "fall_ticks": 30, "lodged_ticks": 240, "burial_depth": 18.0, "floor_supported": true}
	var rock := RockScene.instantiate() as Node2D
	add_child(rock)
	rock.call("configure", event)
	rock.call("set_activation_tick", 0)
	rock.call("set_simulation_tick", tick)
	_rocks.append(rock)
	_rock_labels.append(_add_label(Vector2(x - 140.0, band_top + 22.0), label))

func _add_pool(x: float, tick: int, label: String, floor_y: float, ceiling_y: float, band_top: float) -> void:
	var event := {"event_id": "showcase_pool_%d" % tick, "kind": "lava_crack", "lava_variant": 1, "x": x, "y": floor_y, "width": 180.0, "pool_min_depth": 6.0, "pool_max_depth": 30.0, "pool_min_width": 68.0, "pool_max_width": 180.0, "pool_period_ticks": 180, "pool_phase_ticks": 0, "from_ceiling": false}
	var lava := LavaScene.instantiate() as Node2D
	add_child(lava)
	lava.call("configure", event, 180.0)
	lava.call("apply_simulation_tick", float(tick), 180.0)
	_pools.append(lava)
	_pool_labels.append(_add_label(Vector2(x - 120.0, band_top + 20.0), label))

func _add_label(at: Vector2, text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = Vector2(280.0, 28.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("f5f4f0"))
	add_child(label)
	return label

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color("111822"), true)
	var band_count := 3 if _portrait else 1
	for index in range(band_count):
		var top := _viewport_size.y * float(index) / float(band_count)
		var bottom := _viewport_size.y * float(index + 1) / float(band_count)
		var ceiling := top + (40.0 if _portrait else 82.0)
		var floor := bottom - (42.0 if _portrait else maxf(_viewport_size.y - 460.0, 70.0))
		draw_rect(Rect2(0.0, top, _viewport_size.x, ceiling - top), Color("202c3b"), true)
		draw_rect(Rect2(0.0, floor, _viewport_size.x, bottom - floor), Color("28313a"), true)
		draw_line(Vector2(0.0, ceiling), Vector2(_viewport_size.x, ceiling), Color("9aa7b4"), 3.0)
		draw_line(Vector2(0.0, floor), Vector2(_viewport_size.x, floor), Color("9aa7b4"), 3.0)
		if index > 0:
			draw_line(Vector2(0.0, top), Vector2(_viewport_size.x, top), Color("ffffff", 0.18), 1.0)
	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, Vector2(18.0, 25.0), "GEN17 SHARED HAZARD SCENES · TICK-SAMPLED REVIEW FIXTURE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("ccd6df"))
