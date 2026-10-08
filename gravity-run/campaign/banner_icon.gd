extends Control
## Small badge for the campaign banner: a warning sign (new hazard), a gravity
## star, a finish flag (stage) or Rullaren's lamp (boss). Drawn in code.

var kind := "hazard"
var accent := Color("ff9f43")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, Color("0d1422"))
	draw_arc(c, r - 1.5, 0.0, TAU, 40, accent, 3.0)
	match kind:
		"star":
			var points := PackedVector2Array()
			for i in range(10):
				var angle := -PI * 0.5 + float(i) * PI / 5.0
				points.append(c + Vector2(cos(angle), sin(angle)) * (r * 0.62 if i % 2 == 0 else r * 0.28))
			draw_colored_polygon(points, Color("ffcd3c"))
		"stage":
			draw_line(c + Vector2(-r * 0.3, r * 0.5), c + Vector2(-r * 0.3, -r * 0.5), Color("edf3ff"), 3.0)
			for row in range(3):
				for column in range(3):
					var cell := r * 0.2
					var origin := c + Vector2(-r * 0.27 + float(column) * cell, -r * 0.5 + float(row) * cell)
					draw_rect(Rect2(origin, Vector2(cell, cell)), Color("edf3ff") if (row + column) % 2 == 0 else Color("14141c"))
		"boss":
			draw_rect(Rect2(c - Vector2(r * 0.42, r * 0.42), Vector2(r * 0.84, r * 0.84)), Color("8c5a46"))
			draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.12), Vector2(r * 0.2, r * 0.12)), Color("ff5a46"))
			draw_rect(Rect2(c + Vector2(r * 0.1, -r * 0.12), Vector2(r * 0.2, r * 0.12)), Color("ff5a46"))
		_:
			var tri := PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.55, r * 0.45), c + Vector2(-r * 0.55, r * 0.45)])
			draw_colored_polygon(tri, accent)
			draw_rect(Rect2(c + Vector2(-r * 0.06, -r * 0.25), Vector2(r * 0.12, r * 0.38)), Color("14141c"))
			draw_rect(Rect2(c + Vector2(-r * 0.06, r * 0.2), Vector2(r * 0.12, r * 0.12)), Color("14141c"))
