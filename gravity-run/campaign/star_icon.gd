extends Control
## A gravity star icon for menus and the result screen (filled or empty).
## Optional pop-in animation after pop_delay seconds.

@export var filled := true
@export var pop_delay := -1.0
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(pop_delay >= 0.0)

func _process(delta: float) -> void:
	_time += delta
	if _time > pop_delay + 0.5:
		set_process(false)
	queue_redraw()

static func star_points(center: Vector2, radius: float, inner_ratio: float = 0.46) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		var r := radius if i % 2 == 0 else radius * inner_ratio
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points

func _draw() -> void:
	var scale_factor := 1.0
	if pop_delay >= 0.0:
		var t := clampf((_time - pop_delay) / 0.35, 0.0, 1.0)
		scale_factor = 0.0 if t <= 0.0 else (1.0 + sin(t * PI) * 0.35) * t + (1.0 - t) * 0.0
		if not filled:
			scale_factor = 1.0
	var radius := minf(size.x, size.y) * 0.46 * scale_factor
	if radius <= 0.5:
		return
	var center := size * 0.5
	var outline := star_points(center, radius + 3.0)
	draw_colored_polygon(outline, Color("14141c"))
	if filled:
		draw_colored_polygon(star_points(center, radius), Color("c88c1e"))
		draw_colored_polygon(star_points(center - Vector2(0, radius * 0.08), radius * 0.82), Color("ffcd3c"))
		draw_circle(center + Vector2(-radius * 0.25, -radius * 0.3), radius * 0.12, Color("fff1a8"))
	else:
		draw_colored_polygon(star_points(center, radius), Color("343c50"))
