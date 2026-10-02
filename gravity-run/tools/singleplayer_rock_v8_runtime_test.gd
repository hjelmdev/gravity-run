extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge := root.get_node("ChallengeService")
	_check(challenge.start_challenge_from_code("GR8-100000000"), "the documented v8 seed is accepted by the normal challenge parser")
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_check(int(game.get("_active_seed_version")) == 8 and int(game.get("_active_seed")) == 100000000, "the normal SP scene starts the exact deterministic v8 seed")
	var seen_phases: Dictionary = {}
	var rock: Node2D
	var debris_seen := false
	var central_warning_seen := false
	for _frame in range(520):
		await physics_frame
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("falling_rocks"):
				rock = obstacle
				seen_phases[str(rock.call("get_phase"))] = true
				break
		var pulse: RefCounted = game.get("_rock_warning_pulse")
		if bool(pulse.call("is_active")) and bool((game.get("_rock_warning_accessibility_button") as Control).visible):
			central_warning_seen = true
		if is_instance_valid(rock) and rock.get_parent().get_node_or_null("RockImpactDebris") != null:
			debris_seen = true
		if is_instance_valid(rock) and seen_phases.has("buried"):
			break
	_check(rock != null, "ordinary singleplayer runtime instantiates the first planned v8 rock")
	if rock != null:
		var event: Dictionary = rock.get("event")
		print("Observed SP v8 rock phases=%s activation=%d x=%.1f" % [str(seen_phases.keys()), int(rock.call("get_activation_tick")), float(event.get("x", 0.0))])
		_check(is_equal_approx(float(event.get("x", 0.0)) - 180.0, 2000.0), "GR8-100000000 first planned stone is 2000px from run start")
		_check(int(event.get("warning_ticks", 0)) == 104 and int(event.get("fall_ticks", 0)) == 42 and is_equal_approx(float(event.get("trigger_lead", 0.0)), 1600.0), "SP runtime uses the v8 later visible warning and slower fall")
		_check(seen_phases.has("warning") and seen_phases.has("falling") and seen_phases.has("buried"), "SP runtime shows warning, fall and permanent buried phases")
		_check(central_warning_seen, "ordinary SP warning phase shows the brief central HUD pulse")
		_check(str(rock.call("get_phase")) == "buried" and rock.is_in_group("falling_rocks"), "landed stone remains a live lethal obstacle")
		_check(debris_seen, "SP impact spawns the one-time collision-free decorative chips")
	if failures == 0:
		print("Singleplayer v8 rock runtime passed: GR8-100000000; 2000px; warning/falling/buried and impact debris.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
