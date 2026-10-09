extends Node2D
## Åskfågeln drawn in code on a 4 px grid: a great storm bird, dark blue with
## a golden crest and lightning-yellow wing edges, hovering at the right of
## the screen above the runner's lanes. It flaps, sparks crackle round it,
## its eyes flash and its beak opens when it calls lightning (notify_fired),
## it flashes when hit and spirals away when beaten. Same interface as
## rullaren_view.gd, so CampaignRun places it the same way.

const PIXEL := 4.0
const OUTLINE := Color("141a33")
const BODY := Color("2c3f7a")
const BODY_LIGHT := Color("4766b0")
const BELLY := Color("8fb2ff")
const WING_EDGE := Color("ffe45c")
const CREST := Color("ffc23a")
const BEAK := Color("ffb02e")
const EYE := Color("fffbd0")
const SPARK := Color("fff38a")
const LAMP_ON := Color("ffe45c")
const LAMP_OFF := Color("3a3f4c")
## Hover height above the floor, and distance from the view's right edge.
const HOVER := 250.0
const RIGHT_MARGIN := 150.0

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

func place(right_x: float, floor_y: float) -> void:
	var swoop := maxf(0.0, 1.0 - _intro_time / 1.4)
	position = Vector2(right_x - RIGHT_MARGIN + swoop * swoop * 300.0, floor_y - HOVER - swoop * 160.0)

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

func _draw() -> void:
	if is_gone():
		return
	var bob := roundf(sin(_time * 3.0) * 2.0)
	var offset := Vector2(0.0, bob * PIXEL)
	if _hit_time < 0.45:
		offset += Vector2(sin(_time * 90.0), cos(_time * 77.0)) * 6.0 * (1.0 - _hit_time / 0.45)
	var spin := 0.0
	if _defeat_time >= 0.0:
		spin = _defeat_time * 4.0
		offset += Vector2(_defeat_time * 120.0, -_defeat_time * _defeat_time * 60.0)
		modulate = Color(1, 1, 1, clampf(1.0 - (_defeat_time - 1.6), 0.0, 1.0))
	draw_set_transform(offset, spin, Vector2.ONE)
	_draw_bird(_hit_time < 0.12)
	draw_set_transform(Vector2.ZERO)
	_draw_sparks(offset)
	_draw_hp_lamps()

func _draw_bird(flash: bool) -> void:
	var body := Color.WHITE if flash else BODY
	var light := Color.WHITE if flash else BODY_LIGHT
	var up := fmod(_time * 2.6, 1.0) < 0.5
	# Wings: two wedges of feathers, raised or lowered, with a lightning-yellow
	# trailing edge and a lighter stripe.
	var tilt := -0.7 if up else 0.45
	for pass_index in range(2):
		for side in [-1.0, 1.0]:
			for i in range(15):
				var x: float = side * (3.0 + float(i))
				var top := -3.0 + tilt * float(i)
				var height := maxf(6.0 - float(i) * 0.3, 2.0)
				if pass_index == 0:
					_px(x - 1.0, top - 1.0, 3.0, height + 2.0, OUTLINE)
				else:
					_px(x, top, 1.0, height, body)
					_px(x, top, 1.0, 1.0, light)
					_px(x, top + height - 1.0, 1.0, 1.0, WING_EDGE)
					if i % 4 == 3:
						_px(x, top + height, 1.0, 1.0, WING_EDGE)
	# Body and belly.
	_px(-5, -4, 10, 9, OUTLINE)
	_px(-4, -3, 8, 7, body)
	_px(-3, 0, 6, 4, BELLY)
	# Tail feathers pointing back (right) with yellow tips.
	_px(4, 2, 5, 3, OUTLINE)
	_px(5, 2, 3, 2, light)
	_px(8, 2, 1, 2, WING_EDGE)
	# Head facing the runner (left), golden crest, beak that opens to call.
	_px(-9, -9, 7, 6, OUTLINE)
	_px(-8, -8, 5, 4, body)
	for crest in range(3):
		_px(-7.0 + float(crest) * 2.0, -11.0 - float(crest % 2), 1, 2, CREST)
	var open := clampf(1.0 - _fire_time / 0.4, 0.0, 1.0)
	_px(-12, -7, 4, 2, OUTLINE)
	_px(-11, -7, 3, 1, BEAK)
	if open > 0.1:
		_px(-11, -5, 3, 1, BEAK)
		_px(-14, -6, 2, 1, SPARK)
	var eye := Color.WHITE if flash else (SPARK if open > 0.1 else EYE)
	_px(-7, -7, 1, 1, eye)
	# Talons.
	_px(-2, 5, 1, 2, BEAK)
	_px(1, 5, 1, 2, BEAK)

## Little sparks crackling around the bird, more when it calls lightning.
func _draw_sparks(offset: Vector2) -> void:
	var count := 3 + (4 if _fire_time < 0.4 else 0)
	for index in range(count):
		var angle := float(index) * 2.1 + floorf(_time * 8.0) * 1.3
		var at := offset + Vector2(cos(angle) * 70.0, sin(angle) * 44.0)
		var c := Color(SPARK, 0.85 * modulate.a)
		draw_rect(Rect2((at / PIXEL).round() * PIXEL, Vector2(PIXEL, PIXEL)), c)
		draw_rect(Rect2((at / PIXEL).round() * PIXEL + Vector2(PIXEL, -PIXEL), Vector2(PIXEL, PIXEL)), Color(c, c.a * 0.6))

func _draw_hp_lamps() -> void:
	if _defeat_time >= 0.0:
		return
	for i in range(max_hp):
		var lamp := Vector2(-6.0 + float(i) * 6.0, -18.0) * PIXEL
		draw_rect(Rect2(lamp - Vector2(10, 10), Vector2(20, 20)), OUTLINE)
		var c := LAMP_ON if i < hp else LAMP_OFF
		if i == hp and _hit_time < 0.6 and fmod(_hit_time, 0.2) < 0.1:
			c = Color.WHITE
		draw_rect(Rect2(lamp - Vector2(7, 7), Vector2(14, 14)), c)
