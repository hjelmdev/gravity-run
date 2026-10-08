extends "res://hazards/hazard.gd"

## Presentation only. "grave" draws the block as a gravestone (haunted campaign
## stages); the hitbox is unchanged.
var skin := ""

func _begin_destruction() -> void:
	var top := 0.0 if from_ceiling else -size.y
	_spawn_destruction_fragments(Vector2(0.0, top + size.y * 0.5), [Color("ffad5c"), Color("cf753b"), Color("ffd092")], 10, size)

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var top := 0.0 if from_ceiling else -size.y
	if skin == "grave":
		_draw_gravestone(top)
		return
	draw_rect(Rect2(Vector2(-size.x * 0.5, top), size), Color("ffad5c"))
	draw_rect(Rect2(Vector2(-size.x * 0.5 + 7.0, top + 8.0), size - Vector2(14.0, 16.0)), Color("cf753b"))

## A headstone filling the block's rectangle: arched top, engraved cross.
func _draw_gravestone(top: float) -> void:
	var w := size.x
	var h := size.y
	var left := -w * 0.5
	var arch := minf(w * 0.5, h * 0.4)
	var stone := Color("8b90a6")
	var edge := Color("4d5166")
	var points := PackedVector2Array()
	# The arch is at the free end: the top of a floor block, the bottom of a ceiling one.
	var lane_sign := 1.0 if from_ceiling else -1.0
	var arch_start := lane_sign * (h - arch)
	points.append(Vector2(left, 0.0))
	points.append(Vector2(-left, 0.0))
	points.append(Vector2(-left, arch_start))
	var steps := 8
	for index in range(1, steps):
		var angle := PI * float(index) / float(steps)
		points.append(Vector2(cos(angle) * w * 0.5, arch_start + lane_sign * sin(angle) * arch))
	points.append(Vector2(left, arch_start))
	draw_colored_polygon(points, stone)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, edge, 2.5, true)
	# Engraved cross, a moss patch and a crack.
	var center_y := top + h * 0.5 + (arch * -0.2 if not from_ceiling else arch * 0.2)
	draw_line(Vector2(0.0, center_y - h * 0.18), Vector2(0.0, center_y + h * 0.18), edge, 3.0)
	draw_line(Vector2(-w * 0.2, center_y - h * 0.08), Vector2(w * 0.2, center_y - h * 0.08), edge, 3.0)
	draw_rect(Rect2(Vector2(left + 2.0, 0.0 - 6.0 if not from_ceiling else 0.0), Vector2(w - 4.0, 6.0)), Color("4f6a52"))
