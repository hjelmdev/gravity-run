extends Node2D

const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const VIEW_SIZE := Vector2(960.0, 540.0)
const CAPTURE_DIR := "E:/Utveckling/Gravity Run/.codex-user-right-edge-floatfix"
const USER_CAPTURE_COURSE_LEFTS := [
	5211.71783333335, 5230.75633333335, 5253.27933333335, 5272.16633333335,
	5290.34633333335, 5307.97083333335, 5327.26183333335, 5346.35083333335,
	5364.78333333336, 5382.91283333336, 5401.19383333336, 5419.77783333336,
	5439.57383333336, 5457.65283333336, 5477.90333333336, 5491.28583333336,
	5512.29383333336, 5529.61533333336, 5548.35083333336, 5567.89433333336,
	5585.01383333336, 5603.59783333336, 5623.79783333337, 5642.93733333337,
]
const CAPTURE_INDICES := [0, 1, 5, 8, 20, 21]

var failures := 0
var _camera: Camera2D
var _camera_left := 0.0

func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.enabled = true
	_camera.make_current()
	_test_capture_coordinate_replay()
	await _capture_gpu_frames()
	print("CAVE_USER_FLOAT_CLIP_REGRESSION_TEST failures=%d capture_count=%d output=%s" % [failures, CAPTURE_INDICES.size(), CAPTURE_DIR])
	get_tree().quit(1 if failures > 0 else 0)

func _draw() -> void:
	BiomeRenderer.draw_backdrop(self, _camera_left, VIEW_SIZE, _camera_left, 15)

func _test_capture_coordinate_replay() -> void:
	var reproduced_count := 0
	for course_left_variant in USER_CAPTURE_COURSE_LEFTS:
		var course_left := float(course_left_variant)
		var course_right := course_left + VIEW_SIZE.x
		var packed_left_x := float(PackedVector2Array([Vector2(course_left, VIEW_SIZE.y)])[0].x)
		var packed_right_x := float(PackedVector2Array([Vector2(course_right, VIEW_SIZE.y)])[0].x)
		var old_left_corner_would_enter := packed_left_x > course_left and packed_left_x < course_right
		var old_right_corner_would_enter := packed_right_x > course_left and packed_right_x < course_right
		if old_left_corner_would_enter or old_right_corner_would_enter:
			reproduced_count += 1
		_assert(old_left_corner_would_enter or old_right_corner_would_enter, "actual capture coordinate reproduces a float32 closing-corner false inclusion")
		for layer in range(3):
			var contour := BiomeRenderer.cave_clipped_ridge_vertices(course_left, course_left, 0.0, VIEW_SIZE.x, VIEW_SIZE.y, layer)
			_assert(contour.size() >= 2, "every cave ridge has clipped endpoints")
			var previous_x := -INF
			for point in contour:
				_assert(point.x > previous_x, "clipped upper ridge vertices remain strictly ordered")
				_assert(point.y >= 0.0 and point.y < VIEW_SIZE.y, "upper contour contains no bottom-fill closure vertex")
				previous_x = point.x
	_assert(reproduced_count == USER_CAPTURE_COURSE_LEFTS.size(), "all 24 supplied capture positions reproduce the prior float32 corner admission")

func _capture_gpu_frames() -> void:
	var absolute_dir := CAPTURE_DIR
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	_assert(error == OK or error == ERR_ALREADY_EXISTS, "GPU evidence output directory is available")
	for capture_index in CAPTURE_INDICES:
		var course_left := float(USER_CAPTURE_COURSE_LEFTS[capture_index])
		_camera_left = course_left
		_camera.global_position = Vector2(course_left + VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.5)
		queue_redraw()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		_assert(image != null and image.get_width() > 0 and image.get_height() > 0, "actual GPU viewport readback is non-empty")
		if image == null or image.is_empty():
			continue
		var path := "%s/after_%02d_%.3f.png" % [absolute_dir, capture_index, course_left]
		var save_error := image.save_png(path)
		_assert(save_error == OK, "actual GPU frame is saved: %s" % path)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
