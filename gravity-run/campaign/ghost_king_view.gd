extends Node2D
## Placeholder pixel art for the Ghost King, a crowned ghost drawn in code on
## a 4 px grid. He floats just behind the runner and drifts to the side he
## copies from the runner, one delay late. A faint echo of the runner's
## path shows where he is heading. Drawn in world coordinates.

const PIXEL := 4.0
const OUTLINE := Color("1a1030")
const BODY := Color("d9d2ff")
const BODY_SHADE := Color("9f8fe0")
const CROWN := Color("ffd23f")
const CROWN_DARK := Color("c08a1a")
const EYE := Color("2c1a4f")
const GLOW := Color("8cffc9")

var hp := 3
var _time := 0.0
var _hit_time := 10.0
var _intro_time := 0.0
var _defeat_time := -1.0
var _fire_time := 10.0
var _right_x := 0.0
var _ceiling_y := 80.0
var _floor_y := 460.0
## 0 on the floor side, 1 on the ceiling side; eased toward the target.
var _height := 0.0
var _target_ceiling := false

func _ready() -> void:
	z_index = 6

func notify_hit(new_hp: int) -> void:
	hp = new_hp
	_hit_time = 0.0

func notify_defeated() -> void:
	hp = 0
	_defeat_time = 0.0

func notify_fired() -> void:
	_fire_time = 0.0

func is_gone() -> bool:
	return _defeat_time > 2.6

func place(right_x: float, ceiling_y: float, floor_y: float, king_on_ceiling: bool) -> void:
	_right_x = right_x
	_ceiling_y = ceiling_y
	_floor_y = floor_y
	_target_ceiling = king_on_ceiling

func _process(delta: float) -> void:
	_time += delta
	_hit_time += delta
	_intro_time += delta
	_fire_time += delta
	if _defeat_time >= 0.0:
		_defeat_time += delta
	var target := 1.0 if _target_ceiling else 0.0
	_height = move_toward(_height, target, delta * 4.5)
	queue_redraw()

func _draw() -> void:
	if is_gone():
		return
	var eased := _height * _height * (3.0 - 2.0 * _height)
	var low_y := _floor_y - 70.0
	var high_y := _ceiling_y + 70.0
	var center := Vector2(_right_x - 70.0, lerpf(low_y, high_y, eased) + sin(_time * 2.4) * 8.0)
	var slide := maxf(0.0, 1.0 - _intro_time / 1.4)
	center.x -= slide * slide * 300.0
	if _hit_time < 0.5:
		center += Vector2(sin(_time * 80.0), cos(_time * 66.0)) * 7.0 * (1.0 - _hit_time / 0.5)
	var alpha := 0.92
	if _defeat_time >= 0.0:
		alpha *= clampf(1.0 - _defeat_time / 2.2, 0.0, 1.0)
		center.y -= _defeat_time * 40.0
	draw_circle(center, 70.0, Color(GLOW, 0.08 * alpha))
	if _fire_time < 0.4:
		draw_circle(center, 40.0 + _fire_time * 120.0, Color(GLOW, (0.4 - _fire_time) * alpha))
	var p := func(x: float, y: float, w: float, h: float, color: Color) -> void:
		draw_rect(Rect2(center + Vector2(x, y) * PIXEL, Vector2(w, h) * PIXEL), Color(color, color.a * alpha))
	# Sheet-like body with a wavy hem.
	p.call(-9.0, -9.0, 18.0, 19.0, OUTLINE)
	p.call(-8.0, -8.0, 16.0, 17.0, BODY)
	p.call(4.0, -6.0, 4.0, 15.0, BODY_SHADE)
	var wave := int(_time * 6.0) % 2
	for index in range(5):
		var x := -9.0 + float(index) * 4.0
		var drop := 2.0 if (index + wave) % 2 == 0 else 0.0
		p.call(x, 10.0, 3.0, 1.0 + drop, OUTLINE)
		p.call(x + 1.0, 10.0, 2.0, drop, BODY)
	# Arms reaching forward (left, toward the runner).
	p.call(-13.0, -1.0, 5.0, 3.0, OUTLINE)
	p.call(-12.0, 0.0, 4.0, 1.0, BODY)
	# Face.
	var eye := EYE if _hit_time > 0.35 else Color("ff4f6a")
	p.call(-5.0, -4.0, 3.0, 3.0, eye)
	p.call(1.0, -4.0, 3.0, 3.0, eye)
	p.call(-3.0, 2.0, 5.0, 2.0, EYE)
	# Crown.
	p.call(-7.0, -13.0, 14.0, 4.0, OUTLINE)
	p.call(-6.0, -12.0, 12.0, 3.0, CROWN)
	for spike: float in [-6.0, -1.0, 4.0]:
		p.call(spike, -15.0, 2.0, 3.0, CROWN)
	p.call(-6.0, -10.0, 12.0, 1.0, CROWN_DARK)
	# HP gems on the crown.
	for index in range(3):
		p.call(-5.0 + float(index) * 4.0, -12.0, 2.0, 1.0, Color("ff4f6a") if index < hp else Color("3a3f4c"))
