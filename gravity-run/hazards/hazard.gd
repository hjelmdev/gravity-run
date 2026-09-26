extends Node2D

signal destroyed(obstacle: Node2D)
signal destruction_started(obstacle: Node2D)

var size := Vector2(48.0, 72.0)
var from_ceiling := false
var is_destroying := false
var destruction_elapsed := 0.0
var destruction_fragments: Array[Dictionary] = []

const DESTRUCTION_DURATION := 0.32

func _ready() -> void:
	set_process(false)

func configure(new_size: Vector2, attach_to_ceiling: bool) -> void:
	size = new_size
	from_ceiling = attach_to_ceiling
	queue_redraw()

func advance_motion(_delta: float, movement: float, _player_position: Vector2, _floor_y_at: Callable, _surface_angle_at: Callable, _surface_supported_at: Callable = Callable()) -> void:
	position.x -= movement

func destroy() -> void:
	if is_destroying:
		return
	is_destroying = true
	destruction_started.emit(self)
	_begin_destruction()
	set_process(true)
	queue_redraw()

func is_destroying_now() -> bool:
	return is_destroying

func _begin_destruction() -> void:
	_spawn_destruction_fragments(Vector2.ZERO, [Color("e8a45b"), Color("bd653d"), Color("f4c676")], 8, size)

func _spawn_destruction_fragments(center: Vector2, palette: Array[Color], count: int, spread: Vector2) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(count) + randf_range(-0.25, 0.25)
		destruction_fragments.append({
			"position": center + Vector2(randf_range(-spread.x * 0.5, spread.x * 0.5), randf_range(-spread.y * 0.5, spread.y * 0.5)),
			"velocity": Vector2.from_angle(angle) * randf_range(75.0, 190.0) + Vector2(0.0, -45.0),
			"rotation": randf_range(0.0, TAU),
			"spin": randf_range(-12.0, 12.0),
			"life": DESTRUCTION_DURATION,
			"size": Vector2(randf_range(5.0, 11.0), randf_range(5.0, 10.0)),
			"color": palette[randi_range(0, palette.size() - 1)]
		})

func _process(delta: float) -> void:
	if not is_destroying:
		return
	destruction_elapsed += delta
	for i in range(destruction_fragments.size()):
		var fragment: Dictionary = destruction_fragments[i]
		fragment["position"] = Vector2(fragment["position"]) + Vector2(fragment["velocity"]) * delta
		fragment["velocity"] = Vector2(fragment["velocity"]) + Vector2(0.0, 420.0) * delta
		fragment["rotation"] = float(fragment["rotation"]) + float(fragment["spin"]) * delta
		fragment["life"] = float(fragment["life"]) - delta
		destruction_fragments[i] = fragment
	destruction_fragments = destruction_fragments.filter(func(fragment: Dictionary) -> bool: return float(fragment["life"]) > 0.0)
	queue_redraw()
	if destruction_elapsed >= DESTRUCTION_DURATION or destruction_fragments.is_empty():
		destroyed.emit(self)
		queue_free()

func _draw_destruction_fragments() -> void:
	for fragment in destruction_fragments:
		var life_ratio := clampf(float(fragment["life"]) / DESTRUCTION_DURATION, 0.0, 1.0)
		var fragment_color: Color = fragment["color"]
		fragment_color.a = life_ratio
		draw_set_transform(Vector2(fragment["position"]), float(fragment["rotation"]), Vector2.ONE)
		draw_rect(Rect2(-Vector2(fragment["size"]) * 0.5, Vector2(fragment["size"])), fragment_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_hitbox_rect() -> Rect2:
	var top := 0.0 if from_ceiling else -size.y
	var local_points := [
		Vector2(-size.x * 0.5, top),
		Vector2(size.x * 0.5, top),
		Vector2(-size.x * 0.5, top + size.y),
		Vector2(size.x * 0.5, top + size.y)
	]
	var first_point: Vector2 = to_global(local_points[0])
	var min_point := first_point
	var max_point := first_point
	for point in local_points:
		var world_point: Vector2 = to_global(point)
		min_point = min_point.min(world_point)
		max_point = max_point.max(world_point)
	return Rect2(min_point, max_point - min_point)
