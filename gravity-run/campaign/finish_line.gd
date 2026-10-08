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

func _draw() -> void:
	var cell := 12.0
	var top := ceiling_y
	var height := floor_y - ceiling_y
	var rows := int(ceil(height / cell))
	for row in range(rows):
		for column in range(3):
			var dark := (row + column) % 2 == 0
			var rect := Rect2(Vector2(-cell * 1.5 + float(column) * cell, top + float(row) * cell), Vector2(cell, minf(cell, floor_y - (top + float(row) * cell))))
			draw_rect(rect, Color("14141c") if dark else Color("f4f7ff"))
	draw_rect(Rect2(Vector2(-cell * 1.5 - 3.0, top), Vector2(cell * 3.0 + 6.0, height)), Color("14141c"), false, 3.0)
	# A pennant on each surface, waving.
	var wave := sin(_time * 6.0) * 4.0
	for side in [1.0, -1.0]:
		var base_y := floor_y - 60.0 if side > 0.0 else ceiling_y + 60.0
		var flag := PackedVector2Array([Vector2(cell * 1.5 + 3.0, base_y - 14.0 * side), Vector2(cell * 1.5 + 44.0, base_y - (6.0 - wave * 0.3) * side), Vector2(cell * 1.5 + 3.0, base_y + 2.0 * side)])
		draw_colored_polygon(flag, Color("42d6c5"))
	var label_y := (ceiling_y + floor_y) * 0.5
	draw_rect(Rect2(Vector2(-46.0, label_y - 14.0), Vector2(92.0, 24.0)), Color("14141c"))
	draw_string(ThemeDB.fallback_font, Vector2(-46.0, label_y + 4.0), tr("FINISH"), HORIZONTAL_ALIGNMENT_CENTER, 92.0, 15, Color("f5d45e"))
