extends Node2D
## Finish line: a chequered banner between floor and ceiling at the stage end.

var floor_y := 460.0
var ceiling_y := 80.0
var _time := 0.0

func _ready() -> void:
	# Drawn after the scene's own backdrop/track pass, below the runner.
	z_index = 0

func set_surfaces(new_floor_y: float, new_ceiling_y: float) -> void:
	if is_equal_approx(floor_y, new_floor_y) and is_equal_approx(ceiling_y, new_ceiling_y):
		return
	floor_y = new_floor_y
	ceiling_y = new_ceiling_y
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

## Pixel style (2 px grid, dark outline): a chequered cloth from floor to
## ceiling that ripples row by row, a wooden pole on each side with a pennant
## that flaps in steps, and a wooden sign with the word.
const OUTLINE := Color("14141c")
const CLOTH_DARK := Color("1d1d29")
const CLOTH_LIGHT := Color("f4f7ff")
const POLE := Color("8a5a36")
const POLE_LIGHT := Color("b47a4a")
const PENNANT := Color("42d6c5")
const PENNANT_DARK := Color("2a9d92")
const SIGN := Color("c08850")
const SIGN_DARK := Color("8a5a36")

func _draw() -> void:
	var cell := 12.0
	var top := ceiling_y
	var height := floor_y - ceiling_y
	var rows := int(ceil(height / cell))
	var half := cell * 1.5
	# Poles first, then the cloth between them.
	for side in [-1.0, 1.0]:
		var x: float = side * (half + 6.0)
		draw_rect(Rect2(Vector2(x - 4.0, top), Vector2(8.0, height)), OUTLINE)
		draw_rect(Rect2(Vector2(x - 2.0, top), Vector2(4.0, height)), POLE)
		draw_rect(Rect2(Vector2(x - 2.0, top), Vector2(2.0, height)), POLE_LIGHT)
	for row in range(rows):
		var ripple := roundf(sin(float(row) * 0.7 - _time * 5.0)) * 2.0
		var y := top + float(row) * cell
		var row_h := minf(cell, floor_y - y)
		for column in range(3):
			var dark := (row + column) % 2 == 0
			var rect := Rect2(Vector2(-half + float(column) * cell + ripple, y), Vector2(cell, row_h))
			draw_rect(rect, CLOTH_DARK if dark else CLOTH_LIGHT)
		draw_rect(Rect2(Vector2(-half - 2.0 + ripple, y), Vector2(2.0, row_h)), OUTLINE)
		draw_rect(Rect2(Vector2(half + ripple, y), Vector2(2.0, row_h)), OUTLINE)
	# Pennants: stacked rows that get shorter, flapping in 2 px steps.
	var flap := int(floor(_time * 6.0)) % 2
	for side in [1.0, -1.0]:
		var base_y: float = floor_y - 76.0 if side > 0.0 else ceiling_y + 52.0
		var x0 := half + 10.0
		for r in range(12):
			var length := 46.0 - absf(float(r) - 5.5) * 7.0 - float(flap) * 4.0
			var y := base_y + float(r) * 2.0
			draw_rect(Rect2(Vector2(x0, y), Vector2(length + 2.0, 2.0)), OUTLINE)
			if length > 2.0:
				draw_rect(Rect2(Vector2(x0, y), Vector2(length, 2.0)), PENNANT if r < 6 else PENNANT_DARK)
	# The sign.
	var label_y := roundf((ceiling_y + floor_y) * 0.25) * 2.0
	var board := Rect2(Vector2(-48.0, label_y - 16.0), Vector2(96.0, 28.0))
	draw_rect(board.grow(2.0), OUTLINE)
	draw_rect(board, SIGN)
	draw_rect(Rect2(board.position + Vector2(0.0, board.size.y - 4.0), Vector2(board.size.x, 4.0)), SIGN_DARK)
	draw_rect(Rect2(board.position, Vector2(board.size.x, 2.0)), SIGN.lightened(0.2))
	for nail in [Vector2(-42.0, label_y - 10.0), Vector2(40.0, label_y - 10.0)]:
		draw_rect(Rect2(nail, Vector2(2.0, 2.0)), OUTLINE)
	draw_string(ThemeDB.fallback_font, Vector2(-48.0, label_y + 4.0), tr("FINISH"), HORIZONTAL_ALIGNMENT_CENTER, 96.0, 15, OUTLINE)
