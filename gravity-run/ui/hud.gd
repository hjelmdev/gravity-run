extends Node2D

var distance_m := 0.0
var run_coins := 0
var bank_coins := 0
var gravity_direction := 1
var cooldown_left := 0.0
var game_over := false
var run_blocked := false
var seed_scores: Array[Dictionary] = []
var seed_version := 0
var seed_value := 0
var seed_scores_loaded := false
var seed_scores_error := false
var pass_flash_name := ""
var pass_flash_left := 0.0
var loot_pending_count := 0
var speed_debug_visible := false
var speed_debug_actual := 0.0
var speed_debug_base := 0.0
var speed_debug_equipment_percent := 100.0

func _ready() -> void:
	PlayerAccountProfile.profile_changed.connect(_on_account_profile_changed)
	AccountProgress.progress_changed.connect(_on_account_progress_changed)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	ChallengeService.leaderboard_received.connect(_on_seed_leaderboard_received)
	bank_coins = AccountProgress.wallet_coins
	set_process(false)

func show_pass_flash(nickname: String) -> void:
	pass_flash_name = nickname
	pass_flash_left = 1.8
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	pass_flash_left = maxf(pass_flash_left - delta, 0.0)
	if pass_flash_left <= 0.0:
		pass_flash_name = ""
		set_process(false)
	queue_redraw()

func update_stats(new_distance_m: float, new_coins: int) -> void:
	distance_m = new_distance_m
	run_coins = new_coins
	queue_redraw()

func set_loot_pending_count(count: int) -> void:
	loot_pending_count = maxi(count, 0)
	queue_redraw()

func set_speed_debug_visible(enabled: bool) -> void:
	speed_debug_visible = enabled
	queue_redraw()

func set_speed_debug_values(actual_speed: float, base_speed: float, equipment_percent: float) -> void:
	speed_debug_actual = actual_speed
	speed_debug_base = base_speed
	speed_debug_equipment_percent = equipment_percent
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

func set_seed(seed_generator_version: int, run_seed: int) -> void:
	seed_version = seed_generator_version
	seed_value = run_seed
	seed_scores.clear()
	seed_scores_loaded = false
	seed_scores_error = false
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var viewport_width := viewport_size.x
	var viewport_height := viewport_size.y
	draw_string(ThemeDB.fallback_font, Vector2(20.0, 22.0), "GRAVITY RUN", HORIZONTAL_ALIGNMENT_LEFT, 135.0, 17, Color("f4f7ff"))
	var player_name := PlayerAccountProfile.nickname if PlayerAccountProfile.has_profile else PlayerProfile.leaderboard_name
	if not player_name.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(160.0, 22.0), tr("PLAYER: %s") % player_name, HORIZONTAL_ALIGNMENT_LEFT, 135.0, 11, Color("42d6c5"))
	draw_string(ThemeDB.fallback_font, Vector2(300.0, 22.0), tr("COINS  %02d") % run_coins, HORIZONTAL_ALIGNMENT_LEFT, 82.0, 11, Color("f5d45e"))
	# Leave room for the inventory/shop/pause buttons anchored at the top-right.
	draw_string(ThemeDB.fallback_font, Vector2(viewport_width - 360.0, 22.0), tr("DISTANCE  %06d m") % int(distance_m / 10.0), HORIZONTAL_ALIGNMENT_RIGHT, 190.0, 15, Color("b8c7dc"))
	if speed_debug_visible:
		var debug_rect := Rect2(14.0, 29.0, 360.0, 24.0)
		draw_rect(debug_rect, Color("101827", 0.92))
		var debug_text := "F3 DEBUG  ·  %.1f / %.1f px/s  ·  gear %.0f%%" % [speed_debug_actual, speed_debug_base, speed_debug_equipment_percent]
		draw_string(ThemeDB.fallback_font, Vector2(21.0, 46.0), debug_text, HORIZONTAL_ALIGNMENT_LEFT, 348.0, 12, Color("8ee0a1"))
	if loot_pending_count > 0:
		draw_string(ThemeDB.fallback_font, Vector2(viewport_width - 250.0, 42.0), tr("LOOT PENDING · %d") % loot_pending_count, HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 10, Color("42d6c5"))
	_draw_seed_chase_strip(viewport_width, viewport_height)
	if pass_flash_left > 0.0:
		var flash_phase := sin(Time.get_ticks_msec() / 75.0) * 0.5 + 0.5
		var flash_color := Color("f5d45e", 0.75 + flash_phase * 0.25)
		var flash_text := tr("YOU PASSED %s!") % pass_flash_name
		draw_string(ThemeDB.fallback_font, Vector2(2.0, 114.0), flash_text, HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 19, Color("101827", 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 112.0), flash_text, HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 19, flash_color)
	if run_blocked and not game_over:
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 88.0), tr("BLOCKED — FLIP GRAVITY"), HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 20, Color("ffcf70"))
	if game_over:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.02, 0.04, 0.08, 0.76))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, viewport_height * 0.42), tr("RUN OVER"), HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 42, Color("ff647c"))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, viewport_height * 0.51), tr("Distance: %d m") % int(distance_m / 10.0), HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 22, Color("f4f7ff"))
		draw_string(ThemeDB.fallback_font, Vector2(0.0, viewport_height * 0.60), tr("Tap the screen, press ENTER or SPACE to try again"), HORIZONTAL_ALIGNMENT_CENTER, viewport_width, 17, Color("b8c7dc"))

func _draw_seed_chase_strip(viewport_width: float, viewport_height: float) -> void:
	var track_left := 205.0
	var track_right := maxf(track_left + 160.0, viewport_width - 185.0)
	var track_width := track_right - track_left
	var track_y := viewport_height - 20.0
	var current_m := int(distance_m / 10.0)
	var next_score: Dictionary = {}
	for score in seed_scores:
		var score_distance := int(score.get("best_distance_m", 0))
		if score_distance <= current_m:
			continue
		if next_score.is_empty() or score_distance < int(next_score.get("best_distance_m", 0)):
			next_score = score
	if not next_score.is_empty():
		var gap := int(next_score.get("best_distance_m", 0)) - current_m
		draw_string(ThemeDB.fallback_font, Vector2(390.0, 22.0), tr("NEXT: %s · %d m") % [str(next_score.get("player_name", "")), gap], HORIZONTAL_ALIGNMENT_LEFT, maxf(100.0, viewport_width - 680.0), 10, Color("f5d45e"))
	elif seed_scores.is_empty():
		var note := tr("SEED SCORES UNAVAILABLE") if seed_scores_error else tr("FIRST RUN ON THIS SEED") if seed_scores_loaded else tr("SEED LEADERBOARD")
		draw_string(ThemeDB.fallback_font, Vector2(390.0, 22.0), note, HORIZONTAL_ALIGNMENT_LEFT, maxf(100.0, viewport_width - 680.0), 9, Color("b8c7dc"))

	if seed_scores.is_empty():
		var empty_message := tr("Could not load this seed's leaderboard") if seed_scores_error else tr("No shared runs on this seed yet") if seed_scores_loaded else ""
		if not empty_message.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(track_left, viewport_height - 34.0), empty_message, HORIZONTAL_ALIGNMENT_LEFT, track_width, 9, Color("8292aa"))
	else:
		var best_distance := 1000
		for score in seed_scores:
			best_distance = maxi(best_distance, int(score.get("best_distance_m", 0)) + 150)
		best_distance = maxi(best_distance, current_m + 250)
		best_distance = ceili(float(best_distance) / 500.0) * 500
		draw_line(Vector2(track_left, track_y), Vector2(track_right, track_y), Color("53647d"), 2.0, true)
		var marker_scores: Array[Dictionary] = []
		for score_index in range(mini(seed_scores.size(), 5)):
			marker_scores.append(seed_scores[score_index])
		marker_scores.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("best_distance_m", 0)) < int(right.get("best_distance_m", 0))
		)
		var rank_colors := [Color("f5d45e"), Color("42d6c5"), Color("ff647c"), Color("b69cff"), Color("8ee0a1")]
		var label_y := viewport_height - 35.0
		var label_entries: Array[Dictionary] = []
		for index in range(marker_scores.size()):
			var score: Dictionary = marker_scores[index]
			var ratio := clampf(float(score.get("best_distance_m", 0)) / float(best_distance), 0.0, 1.0)
			var marker_x := track_left + ratio * track_width
			var rank := 1
			for other_score in seed_scores:
				var other_distance := int(other_score.get("best_distance_m", 0))
				var this_distance := int(score.get("best_distance_m", 0))
				if other_distance > this_distance or (other_distance == this_distance and str(other_score.get("player_name", "")) < str(score.get("player_name", ""))):
					rank += 1
			var marker_color: Color = rank_colors[mini(rank - 1, rank_colors.size() - 1)]
			draw_line(Vector2(marker_x, track_y - 5.0), Vector2(marker_x, track_y + 5.0), marker_color, 2.0, true)
			var label_text := "#%d %s %dm" % [rank, str(score.get("player_name", "")).left(4), int(score.get("best_distance_m", 0))]
			var label_width := clampf(ThemeDB.fallback_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x + 6.0, 42.0, 82.0)
			label_entries.append({"marker_x": marker_x, "text": label_text, "width": label_width, "color": marker_color})
		var previous_label_right := track_left
		for label_entry in label_entries:
			var preferred_left := float(label_entry["marker_x"]) - float(label_entry["width"]) * 0.5
			var label_left := maxf(preferred_left, previous_label_right + 3.0)
			label_entry["left"] = label_left
			previous_label_right = label_left + float(label_entry["width"])
		var overflow := maxf(previous_label_right - track_right, 0.0)
		for label_entry in label_entries:
			label_entry["left"] = float(label_entry["left"]) - overflow
		var left_underflow := maxf(track_left - float(label_entries[0]["left"]), 0.0)
		for label_entry in label_entries:
			label_entry["left"] = float(label_entry["left"]) + left_underflow
		for label_entry in label_entries:
			var connector_color: Color = label_entry["color"]
			connector_color.a = 0.62
			var label_center := float(label_entry["left"]) + float(label_entry["width"]) * 0.5
			draw_line(Vector2(float(label_entry["marker_x"]), track_y - 5.0), Vector2(label_center, label_y + 2.0), connector_color, 1.0, true)
			draw_string(ThemeDB.fallback_font, Vector2(float(label_entry["left"]), label_y), str(label_entry["text"]), HORIZONTAL_ALIGNMENT_CENTER, float(label_entry["width"]), 8, label_entry["color"])
		var you_ratio := clampf(float(current_m) / float(best_distance), 0.0, 1.0)
		var you_x := track_left + you_ratio * track_width
		draw_colored_polygon(PackedVector2Array([Vector2(you_x - 4.0, track_y + 8.0), Vector2(you_x + 4.0, track_y + 8.0), Vector2(you_x, track_y + 2.0)]), Color("ff647c"))
		draw_string(ThemeDB.fallback_font, Vector2(you_x - 18.0, viewport_height - 4.0), tr("YOU"), HORIZONTAL_ALIGNMENT_CENTER, 36.0, 8, Color("ff9aaa"))

func _on_seed_leaderboard_received(version: int, seed: int, rows: Array, error_message: String) -> void:
	if version != seed_version or seed != seed_value:
		return
	seed_scores.clear()
	for row in rows:
		if row is Dictionary:
			seed_scores.append(row)
	seed_scores_loaded = true
	seed_scores_error = not error_message.is_empty()
	queue_redraw()

func _on_account_profile_changed(_nickname: String, _has_profile: bool) -> void:
	queue_redraw()

func _on_account_progress_changed(wallet_coins: int, _total_distance_m: int, _best_distance_m: int) -> void:
	bank_coins = wallet_coins
	queue_redraw()

func _on_auth_state_changed(authenticated: bool, _email: String) -> void:
	if not authenticated:
		bank_coins = 0
	else:
		bank_coins = AccountProgress.wallet_coins
	queue_redraw()
