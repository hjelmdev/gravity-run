extends Node2D
## Placeholder pixel art for Rullaren, drawn in code on a 4 px grid. It rides
## at the right edge of the view on the floor; barrels roll out from behind it.

const PIXEL := 4.0
const WIDTH_PX := 36
const HEIGHT_PX := 39
const OUTLINE := Color("14141c")
const METAL := Color("8c5a46")
const METAL_LIGHT := Color("b47a5a")
const METAL_DARK := Color("5e3a32")
const STEEL := Color("5a6274")
const STEEL_LIGHT := Color("8a94aa")
const BARREL := Color("b8783f")
const BARREL_DARK := Color("7c4a26")
const EYE := Color("ff5a46")
const LAMP_ON := Color("ff647c")
const LAMP_OFF := Color("3a3f4c")

var hp := 3
var max_hp := 3
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

func is_gone() -> bool:
	return _defeat_time > 2.6

## Bottom-right anchor: the machine stands on floor_y, right edge at right_x.
func place(right_x: float, floor_y: float) -> void:
	var slide := maxf(0.0, 1.0 - _intro_time / 1.4)
	position = Vector2(right_x - float(WIDTH_PX) * PIXEL + slide * slide * 260.0, floor_y - float(HEIGHT_PX) * PIXEL)

func _process(delta: float) -> void:
	_time += delta
	_hit_time += delta
	_intro_time += delta
	_fire_time += delta
	if _defeat_time >= 0.0:
		_defeat_time += delta
	queue_redraw()

func _px(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(Vector2(x, y) * PIXEL, Vector2(w, h) * PIXEL), color)

func _disc(cx: float, cy: float, r: float, color: Color) -> void:
	for y in range(int(cy - r - 1.0), int(cy + r + 2.0)):
		for x in range(int(cx - r - 1.0), int(cx + r + 2.0)):
			if pow(float(x) + 0.5 - cx, 2.0) + pow(float(y) + 0.5 - cy, 2.0) <= r * r:
				_px(float(x), float(y), 1.0, 1.0, color)

func _draw() -> void:
	if is_gone():
		return
	var shake := Vector2.ZERO
	if _hit_time < 0.45:
		shake = Vector2(sin(_time * 90.0), cos(_time * 77.0)) * 6.0 * (1.0 - _hit_time / 0.45)
	var tilt := 0.0
	var sink := 0.0
	var alpha := 1.0
	if _defeat_time >= 0.0:
		tilt = minf(_defeat_time * 0.35, 0.5)
		sink = _defeat_time * _defeat_time * 30.0
		alpha = clampf(1.0 - (_defeat_time - 1.6), 0.0, 1.0)
		shake += Vector2(sin(_time * 60.0), cos(_time * 53.0)) * 3.0
	var pivot := Vector2(float(WIDTH_PX) * PIXEL * 0.5, float(HEIGHT_PX) * PIXEL)
	# Rotate about the bottom centre: p -> pivot + offset + R * (p - pivot).
	draw_set_transform(pivot + shake + Vector2(0.0, sink) - pivot.rotated(tilt), tilt, Vector2.ONE)
	var flash := _hit_time < 0.12
	modulate = Color(1, 1, 1, alpha)
	_draw_machine(flash)
	draw_set_transform(Vector2.ZERO)
	_draw_smoke()
	_draw_hp_lamps()

func _draw_machine(flash: bool) -> void:
	var metal := Color.WHITE if flash else METAL
	var metal_light := Color.WHITE if flash else METAL_LIGHT
	var metal_dark := Color("dddddd") if flash else METAL_DARK
	# Treads and wheels.
	_px(1, 32, 34, 7, OUTLINE)
	_px(2, 33, 32, 5, STEEL)
	_px(2, 33, 32, 1, STEEL_LIGHT)
	var roll := int(_time * 10.0) % 4
	for i in range(8):
		_px(3.0 + float(i) * 4.0 + float(roll), 37, 2, 1, OUTLINE)
	for wheel_x in [6.0, 14.0, 22.0, 30.0]:
		_disc(wheel_x, 35.0, 2.0, STEEL_LIGHT)
		_px(wheel_x - 0.5, 34.5, 1, 1, OUTLINE)
	# Smokestack.
	_px(24, 1, 6, 9, OUTLINE)
	_px(25, 2, 4, 8, STEEL)
	_px(23, 0, 8, 2, OUTLINE)
	_px(24, 0, 6, 1, STEEL_LIGHT)
	# Body.
	_px(3, 9, 31, 24, OUTLINE)
	_px(4, 10, 29, 22, metal)
	_px(4, 10, 29, 2, metal_light)
	_px(4, 30, 29, 2, metal_dark)
	_px(18, 12, 1, 18, metal_dark)
	for rivet in [Vector2(6, 13), Vector2(30, 13), Vector2(6, 28), Vector2(30, 28), Vector2(20, 13), Vector2(20, 28)]:
		_px(rivet.x, rivet.y, 1, 1, metal_light)
	# Visor and angry eyes.
	_px(9, 14, 20, 6, OUTLINE)
	_px(10, 15, 18, 4, Color("23202a"))
	var blink := fmod(_time, 3.4) < 0.12
	var eye := Color.WHITE if flash else EYE
	if not blink:
		_px(12, 16, 4, 2, eye)
		_px(22, 16, 4, 2, eye)
		_px(12, 15, 1, 1, eye)
		_px(25, 15, 1, 1, eye)
	# Grille mouth.
	_px(12, 22, 14, 4, OUTLINE)
	for i in range(6):
		_px(13.0 + float(i) * 2.0, 23, 1, 2, STEEL_LIGHT)
	# The barrel drum at the hatch (left side, facing the runner).
	var fire := clampf(1.0 - _fire_time / 0.35, 0.0, 1.0)
	var drum_x := 4.0 - fire * 2.0
	_disc(drum_x, 27.0, 6.2, OUTLINE)
	_disc(drum_x, 27.0, 5.2, BARREL)
	var band := int(_time * 8.0) % 3
	for i in range(-1, 2):
		var by := 27.0 + float(i) * 3.0 + float(band) - 1.0
		_px(drum_x - 4.0, by, 8, 1, BARREL_DARK)
	_px(drum_x - 2.0, 23.0, 2, 1, Color("e2aa64"))

func _draw_smoke() -> void:
	var base := Vector2(27.0, 0.0) * PIXEL
	var count := 5 if _defeat_time < 0.0 else 9
	for i in range(count):
		var t := fmod(_time * 0.8 + float(i) / float(count), 1.0)
		var puff := base + Vector2(-t * 60.0 + sin(t * 9.0 + float(i)) * 6.0, -t * 90.0)
		var c := Color("d8dde6") if _defeat_time < 0.0 else Color("4a4e58")
		c.a = (1.0 - t) * 0.8 * modulate.a
		var size := (4.0 + t * 10.0)
		draw_rect(Rect2(puff - Vector2(size, size) * 0.5, Vector2(size, size)).abs(), c)

func _draw_hp_lamps() -> void:
	if _defeat_time >= 0.0:
		return
	for i in range(max_hp):
		var lamp := Vector2(6.0 + float(i) * 8.0, -6.0) * PIXEL
		draw_rect(Rect2(lamp - Vector2(10, 10), Vector2(20, 20)), OUTLINE)
		var lit := i < hp
		var c := LAMP_ON if lit else LAMP_OFF
		if i == hp and _hit_time < 0.6 and fmod(_hit_time, 0.2) < 0.1:
			c = Color.WHITE
		draw_rect(Rect2(lamp - Vector2(7, 7), Vector2(14, 14)), c)
		if lit:
			draw_rect(Rect2(lamp - Vector2(5, 5), Vector2(4, 4)), Color(1, 1, 1, 0.6))
