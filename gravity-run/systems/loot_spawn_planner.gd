extends RefCounted
class_name LootSpawnPlanner
## A separate deterministic stream for loot placements; never uses course RNG.

const FIRST_PICKUP_MIN_DISTANCE := 6000.0
const FIRST_PICKUP_MAX_DISTANCE := 9000.0
const PICKUP_GAP_MIN_DISTANCE := 6000.0
const PICKUP_GAP_MAX_DISTANCE := 9000.0
const MAX_PICKUP_ATTEMPTS := 2
const SEED_SALT := 0x4C4F4F54

var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _next_index := 1
var _next_distance := 0.0
var _next_pop_index := 0

func reset(run_seed: int) -> void:
	_rng.seed = int(run_seed) ^ SEED_SALT
	_events.clear()
	_next_index = 1
	_next_pop_index = 0
	_next_distance = _rng.randf_range(FIRST_PICKUP_MIN_DISTANCE, FIRST_PICKUP_MAX_DISTANCE)

func ensure_horizon(horizon_distance: float) -> void:
	while _next_index <= MAX_PICKUP_ATTEMPTS and _next_distance <= horizon_distance:
		_events.append({"pickup_index": _next_index, "course_distance": _next_distance})
		_next_index += 1
		_next_distance += _rng.randf_range(PICKUP_GAP_MIN_DISTANCE, PICKUP_GAP_MAX_DISTANCE)

func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while _next_pop_index < _events.size() and float(_events[_next_pop_index].course_distance) <= spawn_line_distance:
		ready.append(_events[_next_pop_index])
		_next_pop_index += 1
	return ready

func random_between(minimum: float, maximum: float) -> float:
	return _rng.randf_range(minimum, maximum)

func get_planned_events() -> Array[Dictionary]:
	return _events.duplicate(true)
