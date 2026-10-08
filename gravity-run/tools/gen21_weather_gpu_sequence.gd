extends Node2D
## Bounded post-draw samples from the production BiomeRenderer while its camera
## traverses a biome seam. This is a renderer/GPU fixture, not a live match.

const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const Generator := preload("res://systems/course_generator.gd")
const OUT_DIR := "res://.codex-gen21-gameplay-captures/weather"

var camera_course := 0.0
var presentation_seconds := 0.0
var viewport_size := Vector2(960.0, 540.0)
var failures := 0

func _ready() -> void:
	call_deferred("_capture")

func _draw() -> void:
	var camera_x := float(BiomeRenderer.course_distance_at_world_x(camera_course + 180.0, 180.0))
	var seed_offset := BiomeRenderer.start_biome_offset_for_seed(100000007, Generator.GENERATOR_VERSION_21)
	draw_set_transform(Vector2(-camera_course, 0.0))
	BiomeRenderer.draw_backdrop(self, camera_course, viewport_size, camera_x + seed_offset, Generator.GENERATOR_VERSION_21, presentation_seconds)
	draw_set_transform(Vector2.ZERO)

func _capture() -> void:
	var root := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(root)
	# Draw every rendered frame along the haunted->lava boundary at 500px/s;
	# persist one frame every 12 ticks to keep the artifact set bounded.
	for frame_index in range(145):
		camera_course = 4200.0 + 500.0 * float(frame_index) / 60.0
		presentation_seconds = float(frame_index) / 60.0
		queue_redraw()
		await RenderingServer.frame_post_draw
		if frame_index % 12 != 0:
			continue
		var image := get_viewport().get_texture().get_image()
		var index := frame_index / 12
		var path := root.path_join("weather-landscape-%02d-x%05d.png" % [index, int(camera_course)])
		_check(image.save_png(path) == OK, "landscape postdraw sample saves")
		print("GEN21_WEATHER_GPU view=landscape frame=%d sample=%d camera=%.1f time=%.3f biome=%s image=%s size=%s" % [frame_index, index, camera_course, presentation_seconds, BiomeRenderer.biome_id_for_seed(100000007, camera_course, Generator.GENERATOR_VERSION_21), path, str(image.get_size())])
	# Repeat an actual rendered-frame traversal through the same seam in portrait width.
	viewport_size = Vector2(540.0, 960.0)
	get_viewport().size = Vector2i(540, 960)
	for frame_index in range(73):
		camera_course = 4500.0 + 500.0 * float(frame_index) / 60.0
		presentation_seconds = float(frame_index) / 60.0
		queue_redraw()
		await RenderingServer.frame_post_draw
		if frame_index % 12 != 0:
			continue
		var image := get_viewport().get_texture().get_image()
		var index := frame_index / 12
		var path := root.path_join("weather-portrait-%02d-x%05d.png" % [index, int(camera_course)])
		_check(image.save_png(path) == OK, "portrait postdraw sample saves")
		print("GEN21_WEATHER_GPU view=portrait frame=%d sample=%d camera=%.1f time=%.3f biome=%s image=%s size=%s" % [frame_index, index, camera_course, presentation_seconds, BiomeRenderer.biome_id_for_seed(100000007, camera_course, Generator.GENERATOR_VERSION_21), path, str(image.get_size())])
	print("GEN21_WEATHER_GPU_SEQUENCE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)
