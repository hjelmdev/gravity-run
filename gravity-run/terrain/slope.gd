extends Node2D

const SLOPE_WIDTH := 440.0
const TRACK_FLOOR_Y := 484.0
const TRACK_CEILING_Y := 56.0

var start_y := TRACK_FLOOR_Y
var end_y := TRACK_FLOOR_Y
var from_ceiling := false

func configure(start_surface_y: float, end_surface_y: float, attach_to_ceiling: bool) -> void:
	start_y = start_surface_y
	end_y = end_surface_y
	from_ceiling = attach_to_ceiling
	position.y = start_y
	queue_redraw()

func get_start_x() -> float:
	return global_position.x

func get_end_x() -> float:
	return global_position.x + SLOPE_WIDTH

func get_end_y() -> float:
	return end_y

func is_ceiling_slope() -> bool:
	return from_ceiling

func get_surface_y_at(x: float) -> float:
	var progress := clampf((x - global_position.x) / SLOPE_WIDTH, 0.0, 1.0)
	return lerpf(start_y, end_y, progress)

func get_surface_angle_at(x: float) -> float:
	if x < get_start_x() or x > get_end_x():
		return 0.0
	return atan2(end_y - start_y, SLOPE_WIDTH)

func scale_track_height(scale: float) -> void:
	start_y = 56.0 + (start_y - 56.0) * scale
	end_y = 56.0 + (end_y - 56.0) * scale
	position.y = start_y
	queue_redraw()

