extends RefCounted
class_name RockWarningIcon
## Small reusable vector sign used by the in-world and off-screen rock warnings.

static func draw(canvas: CanvasItem, center: Vector2, size: float, danger_color: Color = Color("ff814f"), opacity: float = 1.0) -> void:
	var half := size * 0.5
	var alpha := clampf(opacity, 0.0, 1.0)
	var triangle := PackedVector2Array([
		center + Vector2(0.0, -half),
		center + Vector2(half * 0.88, half * 0.55),
		center + Vector2(-half * 0.88, half * 0.55),
	])
	canvas.draw_colored_polygon(triangle, Color(0.09, 0.12, 0.16, 0.96 * alpha))
	var outline := triangle.duplicate()
	outline.append(triangle[0])
	var outline_color := danger_color
	outline_color.a *= alpha
	canvas.draw_polyline(outline, outline_color, maxf(2.0, size * 0.065), true)
	var stone_color := Color("ffe1a3", alpha)
	var small_stone := PackedVector2Array([
		center + Vector2(-size * 0.23, -size * 0.04),
		center + Vector2(-size * 0.18, -size * 0.15),
		center + Vector2(-size * 0.08, -size * 0.13),
		center + Vector2(-size * 0.06, -size * 0.03),
	])
	var second_stone := PackedVector2Array([
		center + Vector2(size * 0.04, -size * 0.20),
		center + Vector2(size * 0.15, -size * 0.18),
		center + Vector2(size * 0.19, -size * 0.08),
		center + Vector2(size * 0.08, -size * 0.06),
	])
	canvas.draw_colored_polygon(small_stone, stone_color)
	canvas.draw_colored_polygon(second_stone, stone_color)
	var shaft_top := center + Vector2(size * 0.04, -size * 0.03)
	var shaft_bottom := center + Vector2(size * 0.04, size * 0.19)
	canvas.draw_line(shaft_top, shaft_bottom, stone_color, maxf(2.0, size * 0.055), true)
	canvas.draw_line(shaft_bottom, center + Vector2(-size * 0.07, size * 0.09), stone_color, maxf(2.0, size * 0.055), true)
	canvas.draw_line(shaft_bottom, center + Vector2(size * 0.15, size * 0.09), stone_color, maxf(2.0, size * 0.055), true)

static func draw_forward_chevron(canvas: CanvasItem, center: Vector2, size: float, color: Color = Color("ff814f")) -> void:
	canvas.draw_line(center + Vector2(-size * 0.5, -size * 0.5), center + Vector2(size * 0.5, 0.0), color, maxf(2.0, size * 0.12), true)
	canvas.draw_line(center + Vector2(size * 0.5, 0.0), center + Vector2(-size * 0.5, size * 0.5), color, maxf(2.0, size * 0.12), true)
