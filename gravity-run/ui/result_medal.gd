extends Control

@export_range(1, 3) var place := 1

func _draw() -> void:
	var gold := Color("f5d45e")
	var silver := Color("c7d2e0")
	var bronze := Color("d89462")
	var medal: Color = [gold, silver, bronze][place - 1]
	if place == 1:
		# Simple cup silhouette made from polygons and lines, avoiding emoji-font fallback.
		draw_colored_polygon(PackedVector2Array([Vector2(10, 5), Vector2(26, 5), Vector2(24, 17), Vector2(12, 17)]), medal)
		draw_line(Vector2(10, 8), Vector2(5, 8), medal, 3)
		draw_line(Vector2(5, 8), Vector2(7, 15), medal, 3)
		draw_line(Vector2(7, 15), Vector2(13, 17), medal, 3)
		draw_line(Vector2(26, 8), Vector2(31, 8), medal, 3)
		draw_line(Vector2(31, 8), Vector2(29, 15), medal, 3)
		draw_line(Vector2(29, 15), Vector2(23, 17), medal, 3)
		draw_rect(Rect2(17, 17, 3, 7), medal)
		draw_rect(Rect2(12, 24, 13, 3), medal)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(12, 7), Vector2(17, 15), Vector2(14, 29), Vector2(9, 25)]), Color("e36a80"))
		draw_colored_polygon(PackedVector2Array([Vector2(21, 15), Vector2(26, 7), Vector2(29, 25), Vector2(24, 29)]), Color("e36a80"))
		draw_circle(Vector2(19, 16), 11, medal)
		draw_circle(Vector2(19, 16), 7, Color("18243a"))
