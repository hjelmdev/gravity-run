extends Control

func _draw() -> void:
	var icon_color := Color("edf3ff")
	draw_rect(Rect2(4.0, 3.0, 14.0, 17.0), icon_color, false, 2.0)
	draw_rect(Rect2(8.0, 7.0, 13.0, 15.0), icon_color, false, 2.0)
	draw_line(Vector2(11.0, 12.0), Vector2(18.0, 12.0), icon_color, 1.5)
	draw_line(Vector2(11.0, 16.0), Vector2(18.0, 16.0), icon_color, 1.5)
