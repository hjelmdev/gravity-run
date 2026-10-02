extends Control

func _draw() -> void:
	var center := size * 0.5
	draw_polyline(PackedVector2Array([center + Vector2(-5, -2), center + Vector2(0, 3), center + Vector2(5, -2)]), Color("edf3ff"), 2.0, true)
