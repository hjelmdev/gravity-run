extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge := root.get_node("ChallengeService")
	_check(challenge.start_challenge_from_code("GR7-100000000"), "the documented v7 seed is accepted by the normal challenge parser")
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_check(int(game.get("_active_seed_version")) == 7 and int(game.get("_active_seed")) == 100000000, "the normal SP scene starts the exact deterministic v7 seed")
	var seen_phases: Dictionary = {}
	var rock: Node2D
	for _frame in range(480):
		await physics_frame
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("falling_rocks"):
				rock = obstacle
				seen_phases[str(rock.call("get_phase"))] = true
				break
		if rock != null and seen_phases.has("buried"):
			break
	_check(rock != null, "ordinary singleplayer runtime instantiates the first planned v7 rock")
	if rock != null:
		var event: Dictionary = rock.get("event")
		print("Observed SP rock phases=%s activation=%d event=%s" % [str(seen_phases.keys()), int(rock.call("get_activation_tick")), str(event)])
		_check(is_equal_approx(float(event.get("x", 0.0)) - 180.0, 2000.0), "GR7-100000000 first planned stone is 2000px from run start")
		_check(int(event.get("warning_ticks", 0)) == 90 and int(event.get("fall_ticks", 0)) == 42, "SP runtime uses versioned 1.5s warning and 0.7s fall")
		_check(seen_phases.has("warning") and seen_phases.has("falling") and seen_phases.has("buried"), "SP runtime shows warning, fall and permanent buried phases")
		_check(str(rock.call("get_phase")) == "buried" and rock.is_in_group("falling_rocks"), "landed stone remains a live lethal obstacle")
	if failures == 0:
		print("Singleplayer v7 rock runtime passed: GR7-100000000; 2000px; warning/falling/buried.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
