extends Node2D
## Sandmasken drawn in code on a 4 px grid: a giant ringed worm that bursts out
## of a dune at the left edge of the screen, behind the runner, and sways. Its
## round maw full of teeth faces the runner and gapes when it attacks
## (notify_fired); it flashes when hit and sinks back into the sand when
## beaten. Same interface as rullaren_view.gd (like the Magmaormen, the
## "right_x" anchor is ignored; the worm sits at view_left).

const PIXEL := 4.0
const SEGMENTS := 8
const RISE_HEIGHT := 290.0
const LEFT_MARGIN := 70.0
const OUTLINE := Color("3a2414")
const HIDE := Color("c98a4b")
const HIDE_LIGHT := Color("e3ad6a")
const HIDE_DARK := Color("9a6234")
const BELLY := Color("f0cf95")
const MAW := Color("5a1f1a")
const TOOTH := Color("fff4dc")
const SAND := Color("f2cf8a")
const SAND_DARK := Color("d9a75e")
const LAMP_ON := Color("ffd36a")
const LAMP_OFF := Color("3a3f4c")

var hp := 3
var max_hp := 3
var view_left := 0.0
var _time := 0.0
var _hit_time := 10.0
var _intro_time := 0.0
var _defeat_time := -1.0
var _fire_time := 10.0

func _ready() -> void:
	z_index = 6

func notify_hit(new_hp: int) -> void:
	hp = new_hp
	_hit_time = 0.0

func notify_defeated() -> void:
	hp = 0
	_hit_time = 0.0
	_defeat_time = 0.0

func notify_fired() -> void:
	_fire_time = 0.0

func start_throw(_spec: Dictionary) -> void:
	_fire_time = 0.0

func end_throw(_id: int) -> void:
	pass

func is_gone() -> bool:
	return _defeat_time > 2.6

func place(_right_x: float, floor_y: float) -> void:
	position = Vector2(view_left + LEFT_MARGIN, floor_y)

func _process(delta: float) -> void:
	_time += delta
	_hit_time += delta
	_intro_time += delta
	_fire_time += delta
	if _defeat_time >= 0.0:
		_defeat_time += delta
	queue_redraw()

## Height the worm has risen to, 0..1 (rises in the intro, sinks when beaten).
func _rise() -> float:
	var up := clampf(_intro_time / 1.6, 0.0, 1.0)
	up = up * up * (3.0 - 2.0 * up)
	if _defeat_time >= 0.0:
		up *= clampf(1.0 - _defeat_time / 2.2, 0.0, 1.0)
	return up

## A filled disc of PIXEL blocks around a point.
func _disc(center: Vector2, radius: float, color: Color) -> void:
	var c := (center / PIXEL).round()
	var r := radius / PIXEL
	for y in range(int(-r) - 1, int(r) + 2):
		for x in range(int(-r) - 1, int(r) + 2):
			if float(x * x + y * y) <= r * r:
				draw_rect(Rect2((c + Vector2(x, y)) * PIXEL, Vector2(PIXEL, PIXEL)), color)

func _draw() -> void:
	if is_gone():
		return
	var rise := _rise()
	var flash := _hit_time < 0.14
	var shake := Vector2.ZERO
	if _hit_time < 0.45:
		shake = Vector2(sin(_time * 90.0), cos(_time * 77.0)) * 6.0 * (1.0 - _hit_time / 0.45)
	# Body: ringed segments from the dune up to the head, swaying.
	var points: Array[Vector2] = []
	for index in range(SEGMENTS):
		var t := float(index) / float(SEGMENTS - 1)
		var sway := sin(_time * 2.0 - t * 3.0) * 24.0 * t
		points.append(shake + Vector2(sway + t * 36.0, -t * RISE_HEIGHT * rise))
	for index in range(SEGMENTS - 1):
		var p := points[index]
		var radius := 30.0 - float(index) * 0.8
		_disc(p, radius + PIXEL, OUTLINE)
		_disc(p, radius, Color.WHITE if flash else (HIDE if index % 2 == 0 else HIDE_DARK))
		_disc(p + Vector2(-radius * 0.35, -radius * 0.35), radius * 0.45, Color.WHITE if flash else HIDE_LIGHT)
		# A pale belly stripe on the side facing the runner.
		draw_rect(Rect2(((p + Vector2(radius * 0.5, -radius * 0.4)) / PIXEL).round() * PIXEL, Vector2(PIXEL * 2.0, radius * 0.8)), BELLY)
	_draw_head(points[SEGMENTS - 1], flash)
	# The dune it bursts from, in front of its lowest segments.
	for column in range(-26, 27):
		var height := (1.0 - pow(float(column) / 26.0, 2.0)) * 30.0 + 6.0 + sin(float(column) * 0.7 + _time * 3.0) * 2.0
		var x := float(column) * PIXEL
		draw_rect(Rect2(Vector2(x, -roundf(height / PIXEL) * PIXEL), Vector2(PIXEL, roundf(height / PIXEL) * PIXEL + 40.0)), SAND)
		draw_rect(Rect2(Vector2(x, -roundf(height / PIXEL) * PIXEL), Vector2(PIXEL, PIXEL)), SAND_DARK if column % 3 == 0 else SAND.lightened(0.15))
	# Sand trickling off the body while it rises.
	for grain in range(8):
		var t := fmod(_time * 1.3 + float(grain) / 8.0, 1.0)
		var source := points[2 + grain % 4]
		draw_rect(Rect2((source + Vector2(-20.0 + float(grain) * 6.0, t * 80.0)) / PIXEL * PIXEL, Vector2(PIXEL, PIXEL)), Color(SAND, 1.0 - t))
	_draw_hp_lamps(points[SEGMENTS - 1] + Vector2(-24.0, -76.0))

func _draw_head(at: Vector2, flash: bool) -> void:
	var gape := clampf(1.0 - _fire_time / 0.45, 0.0, 1.0)
	_disc(at, 40.0, OUTLINE)
	_disc(at, 36.0, Color.WHITE if flash else HIDE)
	_disc(at + Vector2(-12.0, -12.0), 16.0, Color.WHITE if flash else HIDE_LIGHT)
	# The round maw facing the runner, with a ring of teeth.
	var maw := at + Vector2(16.0, 0.0)
	var maw_radius := 16.0 + 8.0 * gape
	_disc(maw, maw_radius + PIXEL, OUTLINE)
	_disc(maw, maw_radius, MAW)
	for tooth in range(8):
		var direction := Vector2.RIGHT.rotated(TAU * float(tooth) / 8.0 + _time * 0.6)
		draw_rect(Rect2(((maw + direction * (maw_radius - PIXEL)) / PIXEL).round() * PIXEL, Vector2(PIXEL, PIXEL)), TOOTH)
	# Small eyes above the maw.
	draw_rect(Rect2(((at + Vector2(4.0, -28.0)) / PIXEL).round() * PIXEL, Vector2(PIXEL, PIXEL)), Color("1a0f08"))
	draw_rect(Rect2(((at + Vector2(16.0, -26.0)) / PIXEL).round() * PIXEL, Vector2(PIXEL, PIXEL)), Color("1a0f08"))

func _draw_hp_lamps(at: Vector2) -> void:
	if _defeat_time >= 0.0:
		return
	for index in range(max_hp):
		var lamp := at + Vector2(float(index) * 24.0, 0.0)
		draw_rect(Rect2(lamp - Vector2(10, 10), Vector2(20, 20)), OUTLINE)
		draw_rect(Rect2(lamp - Vector2(7, 7), Vector2(14, 14)), LAMP_ON if index < hp else LAMP_OFF)
