extends Node

const MainScene := preload("res://main.tscn")
const SpikeScene := preload("res://hazards/spikes.tscn")
const GhostScene := preload("res://hazards/ghost_hazard.tscn")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := MainScene.instantiate() as Node2D
	game.set("demo_mode", true)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var runner: Node2D = game.get("player")
	var player_rect: Rect2 = runner.call("get_player_rect")
	var spike := SpikeScene.instantiate() as Node2D
	spike.call("configure", Vector2(28.0, 32.0), true)
	spike.position = Vector2(player_rect.end.x + 90.0, 110.0)
	game.add_child(spike)
	var only_spike: Array[Node2D] = [spike]
	game.set("obstacles", only_spike)
	_check(bool(game.call("_demo_obstacle_from_ceiling", spike)), "direct from_ceiling property keeps ceiling spike lane")
	_check(float(game.call("_demo_side_risk", -1)) > 0.0, "ceiling spike contributes risk to its own lane")
	_check(is_zero_approx(float(game.call("_demo_side_risk", 1))), "ceiling spike does not contribute risk to floor lane")
	spike.queue_free()
	await get_tree().process_frame
	var ghost := GhostScene.instantiate() as Node2D
	ghost.call("configure", {"event_id": "demo-risk-ghost", "kind": "ghost", "x": player_rect.end.x + 120.0, "y": 110.0, "width": 72.0, "height": 96.0, "from_ceiling": true, "warning_ticks": 120, "danger_ticks": 500})
	ghost.call("set_activation_tick", 0)
	ghost.call("set_simulation_tick", 120)
	game.add_child(ghost)
	var only_ghost: Array[Node2D] = [ghost]
	game.set("obstacles", only_ghost)
	_check(bool(game.call("_demo_obstacle_from_ceiling", ghost)), "ghost event fallback preserves ceiling lane without a property")
	_check(float(game.call("_demo_side_risk", -1)) > 0.0, "ceiling ghost contributes risk to its own lane")
	_check(is_zero_approx(float(game.call("_demo_side_risk", 1))), "ceiling ghost does not contribute risk to floor lane")
	game.queue_free()
	await get_tree().process_frame
	print("GEN16_DEMO_SIDE_RISK failures=%d direct_spike_property=PASS ghost_event_fallback=PASS" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
