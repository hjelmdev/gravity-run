extends Node2D
## A gravity star pickup. Drawn in code as a chunky pixel star so it reads at
## any zoom; it bobs gently and bursts when collected.

signal collected(star_index: int)

const RADIUS := 18.0
const GOLD := Color("ffcd3c")
const GOLD_DARK := Color("c88c1e")
const GOLD_LIGHT := Color("fff1a8")
const OUTLINE := Color("14141c")

var star_index := 0
var _time := 0.0
var _collected := false
var _burst := 0.0

func _ready() -> void:
	z_index = 4
	_time = float(star_index) * 0.7

func is_collected() -> bool:
	return _collected

func collect() -> void:
	if _collected:
		return
	_collected = true
	_burst = 0.0
	collected.emit(star_index)

func get_center() -> Vector2:
	return global_position

func _process(delta: float) -> void:
	_time += delta
	if _collected:
		_burst += delta
		if _burst > 0.6:
			queue_free()
			return
	queue_redraw()

func _star_points(radius: float, inner: float, rotation_offset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + float(i) * PI / 5.0 + rotation_offset
		var r := radius if i % 2 == 0 else inner
		# Snap to a 3 px grid so the star stays pixel-crisp next to the sprites.
		points.append((Vector2(cos(angle), sin(angle)) * r / 3.0).round() * 3.0)
	return points

func _draw() -> void:
	if _collected:
		var t := clampf(_burst / 0.6, 0.0, 1.0)
		var ring_color := GOLD_LIGHT
		ring_color.a = 1.0 - t
		draw_arc(Vector2.ZERO, 14.0 + t * 46.0, 0.0, TAU, 28, ring_color, 4.0 * (1.0 - t) + 1.0)
		for i in range(8):
			var angle := float(i) * TAU / 8.0
			var spark := Vector2(cos(angle), sin(angle)) * (10.0 + t * 54.0)
			draw_rect(Rect2(spark - Vector2(3, 3), Vector2(6, 6)), ring_color)
		return
	var bob := Vector2(0.0, roundf(sin(_time * 3.2) * 3.0))
	var spin := sin(_time * 1.7) * 0.18
	var glow := GOLD
	glow.a = 0.16 + 0.08 * sin(_time * 5.0)
	draw_circle(bob, RADIUS + 10.0, glow)
	var top := _star_points(RADIUS - 3.0, 6.0, spin)
	for i in range(top.size()):
		top[i] += bob + Vector2(0, -2)
	var base := _star_points(RADIUS, 8.0, spin)
	for i in range(base.size()):
		base[i] += bob
	var outline := _star_points(RADIUS + 3.0, 10.0, spin)
	for i in range(outline.size()):
		outline[i] += bob
	draw_colored_polygon(outline, OUTLINE)
	draw_colored_polygon(base, GOLD_DARK)
	draw_colored_polygon(top, GOLD)
	draw_rect(Rect2(bob + Vector2(-6, -9), Vector2(3, 3)), GOLD_LIGHT)
	draw_rect(Rect2(bob + Vector2(-3, -6), Vector2(3, 3)), GOLD_LIGHT)
