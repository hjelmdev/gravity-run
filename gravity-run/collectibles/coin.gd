extends Node2D

signal collected(value: int)

const COIN_SIZE := Vector2(24.0, 24.0)
const COIN_VALUE := 1
const BURST_DURATION := 0.22

var is_being_collected := false
var burst_elapsed := 0.0
var coin_face_scale_y := 1.0
var coin_alpha := 1.0
var sparks: Array[Dictionary] = []

func get_hitbox_rect() -> Rect2:
	return Rect2(global_position - COIN_SIZE * 0.5, COIN_SIZE)

func is_collected() -> bool:
	return is_being_collected

func collect() -> void:
	if not animate_collection():
		return
	collected.emit(COIN_VALUE)

func animate_collection() -> bool:
	if is_being_collected:
		return false
	is_being_collected = true
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + randf_range(-0.3, 0.3)
		sparks.append({
			"position": Vector2.ZERO,
			"velocity": Vector2.from_angle(angle) * randf_range(55.0, 105.0),
			"life": BURST_DURATION,
			"size": randf_range(3.0, 5.0)
		})
	set_process(true)
	return true

func _process(delta: float) -> void:
	if not is_being_collected:
		return
	burst_elapsed += delta
	coin_face_scale_y = absf(cos(burst_elapsed * 16.0))
	coin_alpha = clampf(1.0 - burst_elapsed / 0.16, 0.0, 1.0)
	for i in range(sparks.size()):
		var spark: Dictionary = sparks[i]
		spark["position"] = Vector2(spark["position"]) + Vector2(spark["velocity"]) * delta
		spark["velocity"] = Vector2(spark["velocity"]) + Vector2(0.0, 55.0) * delta
		spark["life"] = float(spark["life"]) - delta
		sparks[i] = spark
	sparks = sparks.filter(func(spark: Dictionary) -> bool: return float(spark["life"]) > 0.0)
	position.y -= 95.0 * delta
	queue_redraw()
	if burst_elapsed >= BURST_DURATION and sparks.is_empty():
		queue_free()

func _draw() -> void:
	for spark in sparks:
		var life_ratio := clampf(float(spark["life"]) / BURST_DURATION, 0.0, 1.0)
		var size := float(spark["size"]) * life_ratio
		var center := Vector2(spark["position"])
		var diamond := PackedVector2Array([
			center + Vector2(0.0, -size),
			center + Vector2(size * 0.3, -size * 0.3),
			center + Vector2(size * 0.75, 0.0),
			center + Vector2(size * 0.3, size * 0.3),
			center + Vector2(0.0, size),
			center + Vector2(-size * 0.3, size * 0.3),
			center + Vector2(-size * 0.75, 0.0),
			center + Vector2(-size * 0.3, -size * 0.3)
		])
		var spark_color := Color("ffeaa0")
		spark_color.a = life_ratio
		draw_colored_polygon(diamond, spark_color)

	var coin_color := Color("f5d45e")
	coin_color.a = coin_alpha
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, maxf(coin_face_scale_y, 0.06)))
	draw_circle(Vector2.ZERO, 12.0, coin_color)
	coin_color = Color("b88936")
	coin_color.a = coin_alpha
	draw_circle(Vector2.ZERO, 7.0, coin_color)
	coin_color = Color("ffeaa0")
	coin_color.a = coin_alpha
	draw_circle(Vector2.ZERO, 4.0, coin_color)
	draw_rect(Rect2(-1.25, -5.0, 2.5, 10.0), coin_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
