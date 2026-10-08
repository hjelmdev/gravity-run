extends Node2D
## Placeholder pixel art for the Stalactite Giant, a huge bat drawn in code on
## a 4 px grid. It hangs from the ceiling at the right edge of the view. When
## it locks on, a red stripe marks the side it will dive at; the dive itself is
## a short swoop along that side, into the icicle or past the runner.
## Drawn in world coordinates (the node stays at the origin).

const PIXEL := 4.0
const OUTLINE := Color("120c1c")
const FUR := Color("4a3566")
const FUR_DARK := Color("2e2142")
const WING := Color("3a2850")
const WING_SKIN := Color("5b3f7a")
const EYE := Color("ff4f6a")
const FANG := Color("f2f2f2")
const WARNING := Color("ff3b4f")

var hp := 3
var _time := 0.0
var _hit_time := 10.0
var _intro_time := 0.0
var _defeat_time := -1.0
var _fire_time := 10.0
var _right_x := 0.0
var _ceiling_y := 80.0
var _floor_y := 460.0
var _view_left := 0.0
var _warning := false
var _warning_ceiling := true
var _warning_time := 0.0
var _arrive_x := 0.0
var _dive_time := -1.0
var _dive_ceiling := true
var _dive_into_icicle := false
var _icicle: Node2D

func _ready() -> void:
	z_index = 6

func set_icicle(icicle: Node2D) -> void:
	_icicle = icicle

func notify_warning(locked_ceiling: bool, arrive_world_x: float) -> void:
	_warning = true
	_warning_ceiling = locked_ceiling
	_warning_time = 0.0
	_arrive_x = arrive_world_x

func notify_dive(into_icicle: bool) -> void:
	_warning = false
	_dive_time = 0.0
	_dive_ceiling = _warning_ceiling
	_dive_into_icicle = into_icicle

func notify_hit(new_hp: int) -> void:
	hp = new_hp
	_hit_time = 0.0

func notify_defeated() -> void:
	hp = 0
	_defeat_time = 0.0

func notify_fired() -> void:
	_fire_time = 0.0

func is_gone() -> bool:
	return _defeat_time > 2.8

func place(right_x: float, ceiling_y: float, floor_y: float, view_left: float) -> void:
	_right_x = right_x
	_ceiling_y = ceiling_y
	_floor_y = floor_y
	_view_left = view_left

func _process(delta: float) -> void:
	_time += delta
	_hit_time += delta
	_intro_time += delta
	_fire_time += delta
	_warning_time += delta
	if _dive_time >= 0.0:
		_dive_time += delta
		if _dive_time > 1.3:
			_dive_time = -1.0
	if _defeat_time >= 0.0:
		_defeat_time += delta
	queue_redraw()

func _draw() -> void:
	if _warning:
		_draw_warning()
	if is_gone():
		return
	var width := 44.0 * PIXEL
	var center := Vector2(_right_x - width * 0.5, _ceiling_y + 18.0 * PIXEL)
	var slide := maxf(0.0, 1.0 - _intro_time / 1.4)
	center.y -= slide * slide * 220.0
	var flap := sin(_time * (14.0 if _warning else 5.0))
	var upside_down := true
	if _dive_time >= 0.0:
		# Swoop out along the locked side, then back up to the ceiling.
		var lane_y := (_ceiling_y + 70.0) if _dive_ceiling else (_floor_y - 70.0)
		var target := Vector2(maxf(_view_left + 120.0, _arrive_x), lane_y)
		var out := clampf(_dive_time / 0.32, 0.0, 1.0)
		var back := clampf((_dive_time - 0.55) / 0.6, 0.0, 1.0)
		center = center.lerp(target, out * out).lerp(center, back)
		flap = sin(_time * 24.0)
		upside_down = back > 0.5 or out < 0.2
	if _hit_time < 0.5:
		center += Vector2(sin(_time * 90.0), cos(_time * 70.0)) * 7.0 * (1.0 - _hit_time / 0.5)
	var alpha := 1.0
	if _defeat_time >= 0.0:
		center.y += _defeat_time * _defeat_time * 160.0
		alpha = clampf(1.0 - (_defeat_time - 1.6) / 1.2, 0.0, 1.0)
	_draw_bat(center, flap, upside_down, alpha)

func _draw_warning() -> void:
	var pulse := 0.5 + 0.5 * sin(_warning_time * 18.0)
	var top := _ceiling_y if _warning_ceiling else _floor_y - 96.0
	var rect := Rect2(_view_left, top, _right_x - _view_left + 20.0, 96.0)
	draw_rect(rect, Color(WARNING, 0.10 + 0.12 * pulse))
	var edge_y := top + 96.0 if _warning_ceiling else top
	draw_line(Vector2(_view_left, edge_y), Vector2(_right_x + 20.0, edge_y), Color(WARNING, 0.55 + 0.4 * pulse), 4.0)
	# Chevrons pointing at the runner along the locked side.
	var mid := top + 48.0
	var x := _right_x - 60.0 - fmod(_warning_time * 420.0, 90.0)
	while x > _view_left + 40.0:
		draw_polyline(PackedVector2Array([Vector2(x + 14.0, mid - 16.0), Vector2(x, mid), Vector2(x + 14.0, mid + 16.0)]), Color(WARNING, 0.75), 5.0)
		x -= 90.0

## Bat on a pixel grid around center; upside_down hangs it from its feet.
func _draw_bat(center: Vector2, flap: float, upside_down: bool, alpha: float) -> void:
	var s := -1.0 if upside_down else 1.0
	var p := func(x: float, y: float, w: float, h: float, color: Color) -> void:
		var top_left := center + Vector2(x * PIXEL, (y if s > 0.0 else -(y + h)) * PIXEL)
		draw_rect(Rect2(top_left, Vector2(w, h) * PIXEL), Color(color, color.a * alpha))
	# Wings: three ribs per side, flapping.
	var lift := flap * 3.0
	for side: float in [-1.0, 1.0]:
		for rib in range(4):
			var rx := side * (6.0 + float(rib) * 4.0)
			var ry := -4.0 + lift * (0.4 + float(rib) * 0.25) - float(rib) * 0.6
			var h := 8.0 - float(rib)
			p.call(rx - 2.0 if side > 0.0 else rx - 2.0, ry - 1.0, 4.0, h + 2.0, OUTLINE)
			p.call(rx - 1.0, ry, 3.0, h, WING_SKIN if rib % 2 == 0 else WING)
		p.call(side * 22.0 - 1.0, -6.0 + lift * 1.4, 3.0, 2.0, OUTLINE)
	# Body.
	p.call(-7.0, -8.0, 14.0, 17.0, OUTLINE)
	p.call(-6.0, -7.0, 12.0, 15.0, FUR)
	p.call(-4.0, -2.0, 8.0, 8.0, FUR_DARK)
	# Head with ears.
	p.call(-6.0, -14.0, 12.0, 8.0, OUTLINE)
	p.call(-5.0, -13.0, 10.0, 6.0, FUR)
	p.call(-6.0, -18.0, 3.0, 5.0, OUTLINE)
	p.call(3.0, -18.0, 3.0, 5.0, OUTLINE)
	p.call(-5.0, -17.0, 1.0, 3.0, WING_SKIN)
	p.call(4.0, -17.0, 1.0, 3.0, WING_SKIN)
	var eye := EYE if _hit_time > 0.3 else Color.WHITE
	if _warning:
		eye = Color("ffd23f") if int(_warning_time * 10.0) % 2 == 0 else EYE
	p.call(-4.0, -12.0, 2.0, 2.0, eye)
	p.call(2.0, -12.0, 2.0, 2.0, eye)
	p.call(-2.0, -8.0, 1.0, 2.0, FANG)
	p.call(1.0, -8.0, 1.0, 2.0, FANG)
	# Feet gripping the ceiling.
	p.call(-4.0, 9.0, 2.0, 3.0, OUTLINE)
	p.call(2.0, 9.0, 2.0, 3.0, OUTLINE)
	# HP pips on its belly.
	for index in range(3):
		p.call(-4.0 + float(index) * 3.0, 3.0, 2.0, 2.0, Color("ff647c") if index < hp else Color("3a3f4c"))
