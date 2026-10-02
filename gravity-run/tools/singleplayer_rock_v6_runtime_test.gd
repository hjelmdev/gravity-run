extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge := root.get_node("ChallengeService")
	_check(challenge.start_challenge_from_code("GR6-100000000"), "the documented v6 seed is accepted as a normal challenge code")
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_check(int(game.get("_active_seed_version")) == 6 and int(game.get("_active_seed")) == 100000000, "the normal singleplayer scene starts the exact reproducible v6 seed")
	var seen_phases: Dictionary = {}
	var rock: Node2D
	var wait_limit := 360
	for _frame in range(wait_limit):
		await physics_frame
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("falling_rocks"):
				rock = obstacle
				seen_phases[str(rock.call("get_phase"))] = true
				break
		if rock != null and seen_phases.has("buried"):
			break
	_check(rock != null, "the ordinary SP runtime instantiated the planned seed rock")
	if rock != null:
		var rock_event: Dictionary = rock.get("event")
		var distance_from_start := float(rock_event.get("x", 0.0)) - 180.0
		_check(is_equal_approx(distance_from_start, 1400.0), "the selected encounter is the first event at 1400 px from the start")
		_check(seen_phases.has("warning") and seen_phases.has("falling") and seen_phases.has("buried"), "the normal scene passes through visible warning, falling, and permanent buried phases")
		_check(rock.is_in_group("falling_rocks") and str(rock.call("get_phase")) == "buried", "the buried rock remains a live obstacle after landing")
		_check(rock.get("activation_tick") >= 0, "the normal player-distance trigger activates the rock schedule")
	if failures == 0:
		print("Singleplayer v6 rock runtime passed: GR6-100000000, first stone at 1400px; phases=%s" % str(seen_phases.keys()))
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
