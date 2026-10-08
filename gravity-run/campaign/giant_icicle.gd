extends Node2D
## The Stalactite Giant's weak point: a giant icicle with a glowing crack, on
## the ceiling or standing on the floor. It is scenery, not a hazard: the
## runner passes beside it. When the bat dives into it, it shatters.

const ICE := Color("bfe8f6")
const ICE_LIGHT := Color("eefaff")
const ICE_DARK := Color("6fa9c9")
const OUTLINE := Color("1b2a3c")
const CRACK := Color("8fb4ff")
const HEIGHT := 150.0
const WIDTH := 66.0

var on_ceiling := true
var floor_y := 460.0
var ceiling_y := 80.0
var _time := 0.0
var _shatter_time := -1.0
var _fade_time := -1.0

func _ready() -> void:
	z_index = 2

func set_surfaces(floor_value: float, ceiling_value: float) -> void:
	floor_y = floor_value
	ceiling_y = ceiling_value

func shatter() -> void:
	if _shatter_time < 0.0:
		_shatter_time = 0.0

func fade_out() -> void:
	if _fade_time < 0.0 and _shatter_time < 0.0:
		_fade_time = 0.0

func _process(delta: float) -> void:
	_time += delta
	if _shatter_time >= 0.0:
		_shatter_time += delta
	if _fade_time >= 0.0:
		_fade_time += delta
	queue_redraw()

## Points of the icicle with its base on the surface; dir is +1 hanging down
## from the ceiling and -1 standing up from the floor.
func _shape(base_y: float, dir: float) -> PackedVector2Array:
	var half := WIDTH * 0.5
	return PackedVector2Array([
		Vector2(-half, base_y), Vector2(half, base_y),
		Vector2(half * 0.62, base_y + dir * HEIGHT * 0.45),
		Vector2(half * 0.3, base_y + dir * HEIGHT * 0.8),
		Vector2(0.0, base_y + dir * HEIGHT),
		Vector2(-half * 0.34, base_y + dir * HEIGHT * 0.7),
		Vector2(-half * 0.7, base_y + dir * HEIGHT * 0.35),
	])

func _draw() -> void:
	var dir := 1.0 if on_ceiling else -1.0
	var base_y := ceiling_y if on_ceiling else floor_y
	if _shatter_time >= 0.0:
		_draw_shards(base_y, dir)
		return
	var alpha := 1.0 if _fade_time < 0.0 else maxf(0.0, 1.0 - _fade_time / 0.6)
	if alpha <= 0.0:
		return
	var glow := 0.5 + 0.5 * sin(_time * 5.0)
	# Halo so the weak point reads from far away.
	draw_circle(Vector2(0.0, base_y + dir * HEIGHT * 0.45), 64.0, Color(CRACK, (0.10 + 0.10 * glow) * alpha))
	var points := _shape(base_y, dir)
	draw_colored_polygon(points, Color(ICE, alpha))
	var light := PackedVector2Array([points[0], Vector2(-WIDTH * 0.12, base_y), Vector2(-WIDTH * 0.08, base_y + dir * HEIGHT * 0.6), points[5]])
	draw_colored_polygon(light, Color(ICE_LIGHT, 0.8 * alpha))
	var dark := PackedVector2Array([Vector2(WIDTH * 0.22, base_y), points[1], points[2], points[3]])
	draw_colored_polygon(dark, Color(ICE_DARK, 0.85 * alpha))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(OUTLINE, alpha), 3.0)
	# The glowing crack.
	var crack := PackedVector2Array([
		Vector2(-6.0, base_y + dir * 14.0), Vector2(6.0, base_y + dir * 40.0),
		Vector2(-4.0, base_y + dir * 62.0), Vector2(8.0, base_y + dir * 88.0),
		Vector2(0.0, base_y + dir * 108.0),
	])
	draw_polyline(crack, Color(CRACK, (0.6 + 0.4 * glow) * alpha), 5.0)
	draw_polyline(crack, Color(ICE_LIGHT, alpha), 2.0)

func _draw_shards(base_y: float, dir: float) -> void:
	var t := _shatter_time
	if t > 1.4:
		return
	var alpha := clampf(1.0 - (t - 0.8) / 0.6, 0.0, 1.0)
	for index in range(9):
		var angle := -PI * 0.5 + (float(index) - 4.0) * 0.32
		var speed := 220.0 + float(index % 3) * 70.0
		var origin := Vector2(0.0, base_y + dir * HEIGHT * (0.2 + 0.08 * float(index % 4)))
		var offset := Vector2(cos(angle) * speed * t, -dir * sin(angle) * speed * t * 0.4 + dir * 520.0 * t * t)
		var size := 10.0 + float(index % 3) * 6.0
		var spin := t * (4.0 + float(index))
		var shard := PackedVector2Array([Vector2(0, -size), Vector2(size * 0.5, size * 0.6), Vector2(-size * 0.5, size * 0.6)])
		var moved := PackedVector2Array()
		for point in shard:
			moved.append(origin + offset + point.rotated(spin))
		draw_colored_polygon(moved, Color(ICE, alpha))
	draw_circle(Vector2(0.0, base_y + dir * HEIGHT * 0.45), 40.0 + t * 120.0, Color(ICE_LIGHT, maxf(0.0, 0.5 - t)))
