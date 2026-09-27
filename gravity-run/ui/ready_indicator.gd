extends Control

@export var is_ready := false
@export var is_online := true

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	if is_ready:
		draw_circle(center, radius, Color("164a38"))
		draw_line(center + Vector2(-5, 0), center + Vector2(-1, 4), Color("53e08d"), 2.8, true)
		draw_line(center + Vector2(-1, 4), center + Vector2(6, -5), Color("53e08d"), 2.8, true)
	else:
		var color := Color("607086") if is_online else Color("394557")
		draw_arc(center, radius, 0.0, TAU, 24, color, 2.0, true)
