extends Node2D
## Private review scene for visually checking rock phases and shared collectibles.

const Rock := preload("res://hazards/falling_rock.gd")

func _ready() -> void:
	var labels := ["DORMANT", "WARNING", "FALLING", "BURIED"]
	var phases := ["dormant", "warning", "falling", "buried"]
	var ticks := [0, 12, 48, 68]
	var view_size := get_viewport_rect().size
	var floor_y := view_size.y * 0.8
	for index in range(4):
		var x := view_size.x * (0.125 + float(index) * 0.25)
		var rock := Rock.new()
		rock.configure({"id": "review-rock-%d" % index, "x": x, "floor_y": floor_y, "ceiling_y": view_size.y * 0.18, "width": 90.0, "height": 100.0, "warning_ticks": 36, "fall_ticks": 20, "burial_depth": 24.0})
		if phases[index] == "dormant":
			rock.set_activation_tick(-1)
		else:
			rock.set_activation_tick(0)
		rock.set_simulation_tick(ticks[index])
		add_child(rock)
		rock.set_meta("review_label", labels[index])
	queue_redraw()

func _draw() -> void:
	var view_size := get_viewport_rect().size
	var floor_y := view_size.y * 0.8
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("111b28"))
	draw_rect(Rect2(Vector2(0.0, floor_y), Vector2(view_size.x, view_size.y - floor_y)), Color("35443d"))
	draw_line(Vector2(0.0, floor_y), Vector2(view_size.x, floor_y), Color("a8cda9"), 3.0)
	for index in range(4):
		var x := view_size.x * (0.125 + float(index) * 0.25)
		draw_string(ThemeDB.fallback_font, Vector2(x - 48.0, view_size.y - 35.0), ["DORMANT", "WARNING", "FALLING", "BURIED"][index], HORIZONTAL_ALIGNMENT_CENTER, 96.0, 16, Color("e8edf2"))
	for coin_ratio in [0.08, 0.14, 0.20, 0.75, 0.81, 0.87]:
		var x := view_size.x * float(coin_ratio)
		draw_circle(Vector2(x, floor_y - 44.0), 12.0, Color("f5c84b"))
		draw_circle(Vector2(x - 3.0, floor_y - 48.0), 3.0, Color("fff1a7"))
	draw_string(ThemeDB.fallback_font, Vector2(24.0, 40.0), "Shared gameplay review · coins and falling-rock lifecycle", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("e8edf2"))
