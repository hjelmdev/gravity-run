extends Node2D

signal collected(pickup_index: int)

const PICKUP_SIZE := Vector2(30.0, 30.0)
var pickup_index := 0
var is_collected := false

func configure(index: int) -> void:
	pickup_index = index

func get_hitbox_rect() -> Rect2:
	return Rect2(global_position - PICKUP_SIZE * 0.5, PICKUP_SIZE)

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	collected.emit(pickup_index)
	queue_free()

func _draw() -> void:
	var half := PICKUP_SIZE * 0.5
	draw_rect(Rect2(-half, PICKUP_SIZE), Color("806526"), true)
	draw_rect(Rect2(-half, Vector2(PICKUP_SIZE.x, 8.0)), Color("f5d45e"), true)
	draw_rect(Rect2(-half, PICKUP_SIZE), Color("ffeaa0"), false, 2.0)
	draw_rect(Rect2(-3.0, 7.0, 6.0, 8.0), Color("ffeaa0"), true)
