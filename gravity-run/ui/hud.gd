extends Node2D

var distance_m := 0.0
var run_coins := 0
var gravity_direction := 1
var cooldown_left := 0.0
var game_over := false
var run_blocked := false

func update_stats(new_distance_m: float, new_coins: int) -> void:
	distance_m = new_distance_m
	run_coins = new_coins
	queue_redraw()

func update_player_status(new_gravity_direction: int, new_cooldown_left: float) -> void:
	gravity_direction = new_gravity_direction
	cooldown_left = new_cooldown_left
	queue_redraw()

func show_game_over(_final_distance_m: float, _final_coins: int) -> void:
	game_over = true
	queue_redraw()

func hide_game_over() -> void:
	game_over = false
	queue_redraw()

func set_run_blocked(blocked: bool) -> void:
	if run_blocked == blocked:
		return
	run_blocked = blocked
	queue_redraw()

func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(28.0, 38.0), "GRAVITY RUN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color("f4f7ff"))
	draw_string(ThemeDB.fallback_font, Vector2(280.0, 38.0), "COINS  %02d" % run_coins, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("f5d45e"))
	draw_string(ThemeDB.fallback_font, Vector2(710.0, 38.0), "DISTANS  %06d m" % int(distance_m / 10.0), HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 17, Color("b8c7dc"))
	var gravity_label := "GRAVITET: GOLV" if gravity_direction > 0 else "GRAVITET: TAK"
	draw_string(ThemeDB.fallback_font, Vector2(28.0, 518.0), gravity_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("42d6c5"))
	var ready_label := "REDO" if cooldown_left <= 0.0 else "%.1f s" % cooldown_left
	draw_string(ThemeDB.fallback_font, Vector2(800.0, 518.0), "VÄNDNING  " + ready_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("b8c7dc"))
	if run_blocked and not game_over:
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 88.0), "BLOCKERAD — VÄND GRAVITATIONEN", HORIZONTAL_ALIGNMENT_CENTER, 960.0, 20, Color("ffcf70"))
	if game_over:
		draw_rect(Rect2(0.0, 0.0, 960.0, 540.0), Color(0.02, 0.04, 0.08, 0.76))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 225.0), "RUN SLUT", HORIZONTAL_ALIGNMENT_CENTER, 960.0, 42, Color("ff647c"))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 274.0), "Distans: %d m" % int(distance_m / 10.0), HORIZONTAL_ALIGNMENT_CENTER, 960.0, 22, Color("f4f7ff"))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 326.0), "Tryck ENTER eller mellanslag för att försöka igen", HORIZONTAL_ALIGNMENT_CENTER, 960.0, 17, Color("b8c7dc"))
