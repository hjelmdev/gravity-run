extends Node2D
class_name TrackGap
## A generated opening in one boundary of the running track.

var width := 160.0
var from_ceiling := false

func configure(new_width: float, attach_to_ceiling: bool) -> void:
	width = new_width
	from_ceiling = attach_to_ceiling

func contains_track_x(world_x: float, ceiling: bool) -> bool:
	return ceiling == from_ceiling and absf(world_x - global_position.x) <= width * 0.5

func advance_motion(_delta: float, movement: float, _player_position: Vector2, _floor_y_at: Callable, _surface_angle_at: Callable, _surface_supported_at: Callable = Callable()) -> void:
	position.x -= movement
