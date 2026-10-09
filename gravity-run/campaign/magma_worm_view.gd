extends Node2D
## Magmaormen drawn in code: a segmented worm of magma that rises out of the
## lava at the left edge of the screen, behind the runner, and sways. It spits
## an ember (notify_fired), flashes when hit and sinks back when beaten. Same
## interface as rullaren_view.gd, so CampaignRun places it the same way (the
## "right_x" anchor is ignored; the worm sits at view_left).

const SEGMENTS := 9
const SEGMENT_RADIUS := 26.0
const RISE_HEIGHT := 300.0
const LEFT_MARGIN := 70.0
const CRUST := Color("3a1a14")
const CRUST_LIGHT := Color("5c2a1c")
const MAGMA := Color("ff7a2a")
const MAGMA_HOT := Color("ffd46a")
const EYE := Color("fff3b0")
const LAMP_ON := Color("ff9a3c")
const LAMP_OFF := Color("3a3f4c")

var hp := 3
var max_hp := 3
var view_left := 0.0
var _floor_y := 460.0
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
	_floor_y = floor_y
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

func _draw() -> void:
	if is_gone():
		return
	var rise := _rise()
	var flash := _hit_time < 0.14
	var shake := Vector2.ZERO
	if _hit_time < 0.45:
		shake = Vector2(sin(_time * 90.0), cos(_time * 77.0)) * 6.0 * (1.0 - _hit_time / 0.45)
	# The lava pool it rises from.
	draw_rect(Rect2(Vector2(-90.0, -10.0), Vector2(180.0, 20.0)), Color(1.0, 0.45, 0.12, 0.85))
	draw_rect(Rect2(Vector2(-70.0, -14.0), Vector2(140.0, 6.0)), Color(1.0, 0.75, 0.3, 0.6 + 0.3 * sin(_time * 5.0)))
	# Body: segments from the pool up to the head, swaying.
	var points: Array[Vector2] = []
	for index in range(SEGMENTS):
		var t := float(index) / float(SEGMENTS - 1)
		var sway := sin(_time * 2.2 - t * 3.0) * 26.0 * t
		points.append(shake + Vector2(sway + t * 40.0, -t * RISE_HEIGHT * rise))
	for index in range(SEGMENTS):
		var p := points[index]
		var radius := SEGMENT_RADIUS * (1.0 - float(index) * 0.035)
		var crust := Color.WHITE if flash else (CRUST if index % 2 == 0 else CRUST_LIGHT)
		draw_circle(p, radius, crust)
		var glow := MAGMA.lerp(MAGMA_HOT, 0.5 + 0.5 * sin(_time * 6.0 + float(index)))
		draw_circle(p + Vector2(0.0, -2.0), radius * 0.45, glow)
		# Glowing scales on the back.
		draw_line(p + Vector2(-radius * 0.7, -radius * 0.3), p + Vector2(-radius * 0.2, -radius * 0.8), glow, 3.0)
	_draw_head(points[SEGMENTS - 1], flash)
	_draw_hp_lamps(points[SEGMENTS - 1] + Vector2(-20.0, -70.0))

func _draw_head(at: Vector2, flash: bool) -> void:
	var open := clampf(1.0 - _fire_time / 0.4, 0.0, 1.0)
	var crust := Color.WHITE if flash else CRUST
	draw_circle(at, SEGMENT_RADIUS * 1.25, crust)
	# Jaw toward the runner (right); it opens when it spits.
	var jaw := PackedVector2Array([at + Vector2(10.0, -8.0), at + Vector2(52.0, -16.0 - 18.0 * open), at + Vector2(48.0, 10.0 + 18.0 * open), at + Vector2(10.0, 12.0)])
	draw_colored_polygon(jaw, crust)
	draw_line(at + Vector2(16.0, 2.0), at + Vector2(46.0, 2.0), MAGMA_HOT if open > 0.1 else MAGMA, 4.0 + 6.0 * open)
	draw_circle(at + Vector2(6.0, -14.0), 6.0, EYE)
	draw_circle(at + Vector2(8.0, -14.0), 3.0, Color("1a0a06"))
	# Horn ridge.
	for index in range(3):
		var base := at + Vector2(-18.0 + float(index) * 12.0, -SEGMENT_RADIUS * 1.1)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-5.0, 0.0), base + Vector2(0.0, -14.0), base + Vector2(5.0, 0.0)]), MAGMA)
	if open > 0.0:
		draw_circle(at + Vector2(60.0, -2.0), 10.0 * open, Color(1.0, 0.6, 0.2, 0.8 * open))

func _draw_hp_lamps(at: Vector2) -> void:
	for index in range(max_hp):
		draw_circle(at + Vector2(float(index) * 18.0, 0.0), 6.0, LAMP_ON if index < hp else LAMP_OFF)
