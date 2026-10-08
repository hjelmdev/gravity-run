extends Node2D
class_name CaveInDust
## Presentation only: the warning of a cave-in. A crack runs along the ceiling
## over the stretch where the rocks will come down, with dust trickling from it.
## It shows from far ahead of the first rock until the runner is past the last.
## The rocks themselves are ordinary falling rocks (see CampaignFeatures).

const SHOW_AHEAD := 1500.0
const CRACK_COLOR := Color("15100e")
const DUST_COLOR := Color("b9a58a")

## World x of the crack's ends.
var x_from := 0.0
var x_to := 0.0
var _runner_x := 0.0
var _ceiling_y := 80.0
var _time := 0.0
var _active := false

func configure(world_from: float, world_to: float) -> void:
	x_from = world_from
	x_to = world_to
	z_index = 2
	set_process(true)

func update_view(runner_x: float, ceiling_y: float) -> void:
	_runner_x = runner_x
	_ceiling_y = ceiling_y
	var was_active := _active
	_active = runner_x > x_from - SHOW_AHEAD and runner_x < x_to + 40.0
	if _active or was_active:
		queue_redraw()

func _process(delta: float) -> void:
	if _active:
		_time += delta
		queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var nearness := clampf(1.0 - (x_from - _runner_x) / SHOW_AHEAD, 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(_time * 9.0)
	# The crack: a jagged dark line with a thin pale edge.
	var points := PackedVector2Array()
	var x := x_from - 30.0
	var step := 0
	while x <= x_to + 30.0:
		points.append(Vector2(x, _ceiling_y + 6.0 + (7.0 if step % 2 == 0 else 1.0)))
		x += 22.0
		step += 1
	if points.size() >= 2:
		draw_polyline(points, Color(CRACK_COLOR, 0.95), 8.0)
		draw_polyline(points, Color(DUST_COLOR, 0.75 * pulse), 3.0)
		draw_rect(Rect2(Vector2(x_from - 30.0, _ceiling_y), Vector2(x_to - x_from + 60.0, 18.0)), Color(DUST_COLOR, 0.16 * pulse))
	# Dust trickling down from the crack. Deterministic positions, moving in time.
	var count := int((x_to - x_from) / 14.0) + 6
	for index in range(count):
		var seed_value := float(index) * 12.9898
		var column := x_from - 20.0 + fposmod(sin(seed_value) * 43758.5453, x_to - x_from + 40.0)
		var fall := fposmod(_time * (50.0 + 30.0 * fposmod(seed_value, 1.0)) + float(index) * 17.0, 90.0)
		var alpha := (1.0 - fall / 90.0) * (0.35 + 0.5 * nearness)
		draw_rect(Rect2(Vector2(column, _ceiling_y + 10.0 + fall), Vector2(4.0, 4.0)), Color(DUST_COLOR, minf(alpha * 1.4, 1.0)))
