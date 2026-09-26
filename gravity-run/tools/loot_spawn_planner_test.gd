extends SceneTree

const PlannerScript := preload("res://systems/loot_spawn_planner.gd")

func _initialize() -> void:
	var first = PlannerScript.new()
	var second = PlannerScript.new()
	first.reset(123456)
	second.reset(123456)
	first.ensure_horizon(100000.0)
	second.ensure_horizon(100000.0)
	var events: Array[Dictionary] = first.get_planned_events()
	var repeated: Array[Dictionary] = second.get_planned_events()
	_check(events == repeated, "loot event sequence must be deterministic for the same run seed")
	_check(events.size() == PlannerScript.MAX_PICKUP_ATTEMPTS, "loot planner must cap planned attempts")
	if not events.is_empty():
		_check(float(events[0].course_distance) >= PlannerScript.FIRST_PICKUP_MIN_DISTANCE, "first loot event must respect minimum distance")
		_check(float(events[0].course_distance) <= PlannerScript.FIRST_PICKUP_MAX_DISTANCE, "first loot event must respect maximum distance")
	var popped := first.pop_events_until(float(events[0].course_distance))
	_check(popped.size() == 1, "planner should emit only events up to spawn line")
	_check(first.pop_events_until(100000.0).size() == events.size() - popped.size(), "remaining events should be emitted once")
	print("Loot spawn planner tests passed.")
	quit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
