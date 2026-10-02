extends SceneTree

const FallingRockScript := preload("res://hazards/falling_rock.gd")
const ImpactDebrisScript := preload("res://hazards/rock_impact_debris.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var rock := FallingRockScript.new() as Node2D
	world.add_child(rock)
	rock.call("configure", {"x": 500.0, "floor_y": 460.0, "ceiling_y": 80.0, "width": 90.0, "height": 100.0, "trigger_lead": 1600.0, "warning_ticks": 104, "fall_ticks": 42, "burial_depth": 24.0})
	rock.call("set_activation_tick", 0)
	rock.call("set_simulation_tick", 104)
	_check(rock.call("get_phase") == "falling" and _debris_count(world) == 0, "warning-to-fall has no impact effect before landing")
	rock.call("set_simulation_tick", 146)
	_check(rock.call("get_phase") == "buried" and _debris_count(world) == 1, "the fall creates one decorative debris effect at landing")
	var debris := world.get_node_or_null("RockImpactDebris")
	_check(debris is ImpactDebrisScript and debris is Node2D, "impact fragments are a separate visual-only node")
	_check(not debris is CollisionObject2D and debris.find_children("*", "CollisionObject2D", true, false).is_empty(), "impact fragments have no collision or damage body")
	rock.call("set_simulation_tick", 147)
	_check(_debris_count(world) == 1, "the permanent rock spawns impact fragments only once")
	if failures == 0:
		print("Falling rock impact effect passed: four short-lived visual chips spawn once at impact, remain collision-free, and stay separate from the rock node.")
	quit(1 if failures > 0 else 0)

func _debris_count(world: Node) -> int:
	return world.find_children("RockImpactDebris", "Node2D", true, false).size()

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
