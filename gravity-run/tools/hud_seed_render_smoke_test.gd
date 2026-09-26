extends SceneTree

const HudScript := preload("res://ui/hud.gd")

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var hud := HudScript.new() as Node2D
	hud.set("seed_version", 1)
	hud.set("seed_value", 123456789)
	hud.set("seed_scores_loaded", true)
	hud.set("distance_m", 4820.0)
	hud.set("seed_scores", [
		{"player_name": "Yellmen", "best_distance_m": 733, "attempts": 1},
		{"player_name": "Alexandra", "best_distance_m": 730, "attempts": 2},
		{"player_name": "Nova", "best_distance_m": 612, "attempts": 1},
		{"player_name": "Kim", "best_distance_m": 425, "attempts": 4},
		{"player_name": "A_B", "best_distance_m": 318, "attempts": 1}
	])
	root.add_child(hud)
	await process_frame
	hud.queue_redraw()
	await process_frame
	print("HUD seed leaderboard render smoke test passed.")
	quit()
