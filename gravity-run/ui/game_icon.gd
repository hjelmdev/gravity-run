extends Control
class_name GameIcon

@export var icon_key := "unknown"
@export var icon_family := "item"
@export var unlocked := true

func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 32.0
	if scale_factor <= 0.0:
		return
	draw_set_transform(Vector2((size.x - 32.0 * scale_factor) * 0.5, (size.y - 32.0 * scale_factor) * 0.5), 0.0, Vector2.ONE * scale_factor)
	if icon_family == "achievement_status":
		_draw_status()
	elif icon_family == "achievement_category":
		_draw_category()
	elif icon_family == "chevron":
		draw_polyline(PackedVector2Array([Vector2(11, 6), Vector2(21, 16), Vector2(11, 26)]), Color("42d6c5"), 3.0, true)
	else:
		_draw_item()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_item() -> void:
	var ink := Color("edf3ff")
	var accent := Color("42d6c5")
	var key := icon_key
	if key in ["helmet_copper_01", "helmet_scout_01", "helmet_night_01"]:
		draw_arc(Vector2(16, 16), 11.0, PI, TAU, 24, ink, 2.0, true)
		draw_line(Vector2(5, 16), Vector2(27, 16), accent, 2.0, true)
		draw_line(Vector2(9, 14), Vector2(12, 8), ink, 2.0, true)
		draw_line(Vector2(16, 13), Vector2(16, 5), accent if key == "helmet_scout_01" else ink, 1.7, true)
		draw_line(Vector2(23, 14), Vector2(20, 8), ink, 2.0, true)
		if key == "helmet_night_01":
			draw_arc(Vector2(16, 16), 6.0, PI, TAU, 16, accent, 1.5, true)
		elif key == "helmet_copper_01":
			draw_circle(Vector2(16, 16), 1.4, accent)
		elif key == "helmet_scout_01":
			draw_line(Vector2(4, 13), Vector2(1, 10), accent, 2.0, true)
	elif key in ["boots_canvas_01", "boots_runner_01", "boots_gravity_01"]:
		draw_line(Vector2(10, 4), Vector2(10, 19), ink, 4.0, true)
		draw_line(Vector2(10, 19), Vector2(25, 23), ink, 4.0, true)
		draw_line(Vector2(25, 23), Vector2(26, 27), accent, 3.0, true)
		draw_line(Vector2(6, 28), Vector2(28, 28), accent, 2.0, true)
		if key == "boots_runner_01":
			draw_line(Vector2(8, 22), Vector2(17, 22), accent, 2.0, true)
		elif key == "boots_gravity_01":
			draw_line(Vector2(7, 25), Vector2(16, 25), accent, 2.0, true)
	elif not EffectIcons.effect_for_icon_key(key).is_empty():
		EffectIcons.draw_glyph(self, EffectIcons.effect_for_icon_key(key), Vector2(16, 16), 28.0, ink, accent)
	else:
		# Deliberate neutral item marker for unknown future catalogue keys.
		draw_rect(Rect2(5, 5, 22, 22), Color("8292aa"), false, 2.0)
		draw_line(Vector2(11, 16), Vector2(21, 16), ink, 2.0, true)

func _draw_status() -> void:
	var ink := Color("f5d45e") if unlocked else Color("718098")
	if unlocked:
		var points := PackedVector2Array([Vector2(16, 2), Vector2(19, 11), Vector2(29, 11), Vector2(21, 17), Vector2(24, 28), Vector2(16, 22), Vector2(8, 28), Vector2(11, 17), Vector2(3, 11), Vector2(13, 11)])
		draw_colored_polygon(points, ink)
	else:
		draw_arc(Vector2(16, 17), 11.0, PI, TAU, 24, ink, 2.0, true)
		draw_line(Vector2(5, 17), Vector2(27, 17), ink, 2.0, true)
		draw_line(Vector2(8, 17), Vector2(8, 26), ink, 2.0, true)
		draw_line(Vector2(24, 17), Vector2(24, 26), ink, 2.0, true)
		draw_arc(Vector2(16, 17), 8.0, 0.0, PI, 18, ink, 2.0, true)

func _draw_category() -> void:
	var ink := Color("42d6c5")
	match icon_key:
		"coins_earned":
			draw_circle(Vector2(13, 16), 9.0, Color("f5d45e"))
			draw_circle(Vector2(13, 16), 5.0, ink)
			draw_circle(Vector2(21, 20), 7.0, Color("f5d45e"))
		"gravity_flips":
			draw_arc(Vector2(16, 16), 10.0, 0.2, 2.8, 18, ink, 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(7, 3), Vector2(16, 6), Vector2(9, 12)]), ink)
			draw_arc(Vector2(16, 16), 10.0, 3.35, 5.95, 18, Color("f5d45e"), 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(25, 29), Vector2(16, 26), Vector2(23, 20)]), Color("f5d45e"))
		"hazards_discovered":
			draw_colored_polygon(PackedVector2Array([Vector2(16, 3), Vector2(29, 27), Vector2(3, 27)]), Color("ff7b72"))
			draw_line(Vector2(16, 11), Vector2(16, 19), Color("111b2b"), 2.4, true)
			draw_circle(Vector2(16, 23), 1.4, Color("111b2b"))
		"distance_run":
			draw_circle(Vector2(10, 21), 5.0, Color("edf3ff"))
			draw_circle(Vector2(10, 21), 2.0, Color("18243a"))
			draw_line(Vector2(10, 20), Vector2(18, 14), ink, 3.0, true)
			draw_line(Vector2(16, 14), Vector2(22, 17), ink, 3.0, true)
			draw_line(Vector2(19, 14), Vector2(22, 8), Color("f5d45e"), 2.0, true)
		"distance_total":
			draw_line(Vector2(5, 26), Vector2(12, 18), ink, 3.0, true)
			draw_line(Vector2(12, 18), Vector2(18, 22), ink, 3.0, true)
			draw_line(Vector2(18, 22), Vector2(27, 8), ink, 3.0, true)
			draw_circle(Vector2(27, 8), 3.0, Color("f5d45e"))
		_:
			var neutral := PackedVector2Array([Vector2(16, 4), Vector2(28, 16), Vector2(16, 28), Vector2(4, 16), Vector2(16, 4)])
			draw_polyline(neutral, Color("8292aa"), 2.0, true)
