extends Node2D

var player_y := 0.0
var course_distance := 0.0
var biome_name := ""

func set_capture_state(value_y: float, distance: float, theme: String) -> void:
	player_y = value_y
	course_distance = distance
	biome_name = theme
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(0.0, 0.0, size.x, 42.0), Color(0.025, 0.035, 0.055, 0.78))
	draw_string(ThemeDB.fallback_font, Vector2(14.0, 27.0), "MULTIPLAYER | %s | %dm | SEED 100000014" % [biome_name.to_upper(), int(course_distance / 1000.0)], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
	var runner := Rect2(180.0, player_y - 22.0, 34.0, 44.0)
	draw_rect(runner, Color("e8edf3"), true)
	draw_circle(runner.position + Vector2(24.0, 9.0), 2.0, Color("19202a"))
	draw_line(runner.position + Vector2(7.0, 43.0), runner.position + Vector2(1.0, 47.0), Color("e8edf3"), 3.0, true)
	draw_line(runner.position + Vector2(25.0, 43.0), runner.position + Vector2(31.0, 47.0), Color("e8edf3"), 3.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(14.0, size.y - 12.0), "V9 SHARED COURSE PRESENTATION  •  LOCAL REVIEW FIXTURE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.76, 0.83, 0.9, 0.82))
