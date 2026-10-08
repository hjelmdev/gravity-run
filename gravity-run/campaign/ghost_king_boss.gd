extends RefCounted
class_name GhostKingBoss
## Spökkungen, the haunted woods boss: a crowned ghost that floats ahead of
## the runner and copies the runner's side with a delay, all fight long. Like
## the other bosses it is a script: phases schedule ordinary course events at
## fixed course distances, and while his trail is active he drops ghost fire
## on the side he is on, which is the side the runner was on a moment ago.
##
## The weak point is a lantern on the ceiling or on the floor. When the
## runner passes it, the king is where the runner was one delay earlier. If
## he is on the lantern's side and the runner no longer is, the light catches
## him: one hit. So: be on the lantern's side, then flip away shortly before
## it. Missing it repeats the phase. Three hits defeat him, and every hit
## shortens his delay. Everything is a function of course distance and the
## runner's flips, so the fight is deterministic for a given input.

const INTRO_DISTANCE := 2600.0
const PHASE_GAP := 2200.0
const RUNOUT_DISTANCE := 2400.0
const MAX_HP := 3
## How far behind the runner the king's side lags, in course px (at the base
## 500 px/s: 0.7 s, 0.55 s, 0.4 s).
const DELAYS := [350.0, 275.0, 200.0]
const LANTERN_WIDTH := 150.0
## Ghost fire is dropped this far ahead of the runner, every TRAIL_SPACING.
const TRAIL_AHEAD := 640.0
const TRAIL_SPACING := 560.0
## No fire within this distance of a scheduled attack or the lantern.
const TRAIL_CLEARANCE := 420.0

## attacks: [offset, kind, count]; kind "ceiling_spikes" / "ceiling_block"
## (be on the floor) or "floor_spikes" / "floor_block" (be on the ceiling).
## trail: [start offset, end offset] of the ghost fire, or [] for none.
const PHASES := [
	{
		"title": "Ghost trail",
		"lantern_offset": 3300.0, "lantern_ceiling": false,
		"trail": [0.0, 2300.0],
		"attacks": [],
	},
	{
		"title": "Ghost wave",
		"lantern_offset": 3400.0, "lantern_ceiling": true,
		"trail": [],
		"attacks": [[0.0, "ceiling_block", 1], [700.0, "floor_spikes", 4], [1400.0, "ceiling_spikes", 5], [2100.0, "floor_block", 1], [2700.0, "ceiling_spikes", 3]],
	},
	{
		"title": "Last dance",
		"lantern_offset": 3900.0, "lantern_ceiling": false,
		"trail": [0.0, 1500.0],
		"attacks": [[2100.0, "floor_spikes", 4], [2800.0, "ceiling_block", 1]],
	},
]

var hp := MAX_HP
var phase := 0
var attempts_in_phase := 0
## {"distance": float, "ceiling": bool, "state": "armed"|"hit"|"missed"}
var lantern: Dictionary = {}
var finish_distance := -1.0
var _pending: Array[Dictionary] = []
var _scheduled: Array[Dictionary] = []
## Runner side changes as [course distance, on_ceiling] pairs, oldest first.
var _history: Array = []
var _trail_from := INF
var _trail_to := -INF
var _next_trail := INF

func reset() -> void:
	hp = MAX_HP
	phase = 0
	attempts_in_phase = 0
	finish_distance = -1.0
	_pending.clear()
	_scheduled.clear()
	_history = [[-INF, false]]
	_schedule_phase(INTRO_DISTANCE)

func is_defeated() -> bool:
	return hp <= 0

func get_max_hp() -> int:
	return MAX_HP

func get_phase_title() -> String:
	return str(PHASES[mini(phase, PHASES.size() - 1)].title)

func delay_distance() -> float:
	return float(DELAYS[clampi(MAX_HP - hp, 0, DELAYS.size() - 1)])

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = PHASES[phase]
	for attack in spec.attacks:
		var event := _make_event(anchor + float(attack[0]), str(attack[1]), int(attack[2]))
		_add(event)
	var trail: Array = spec.trail
	if trail.is_empty():
		_trail_from = INF
		_trail_to = -INF
	else:
		_trail_from = anchor + float(trail[0])
		_trail_to = anchor + float(trail[1])
	_next_trail = _trail_from
	lantern = {"distance": anchor + float(spec.lantern_offset), "ceiling": bool(spec.lantern_ceiling), "state": "armed"}

func _add(event: Dictionary) -> void:
	# Keep the queue ordered by course distance.
	var index := _pending.size()
	while index > 0 and float(_pending[index - 1].course_distance) > float(event.course_distance):
		index -= 1
	_pending.insert(index, event)
	_scheduled.append(event)

func _make_event(distance: float, kind: String, count: int) -> Dictionary:
	var from_ceiling := kind.begins_with("ceiling")
	if kind.ends_with("block"):
		return {"kind": "block", "id": "block", "course_distance": distance, "width": 56.0, "height": 132.0 if from_ceiling else 96.0, "from_ceiling": from_ceiling, "boss_attack": true}
	return {"kind": "spikes", "id": "spike_group", "course_distance": distance, "count": count, "width": float((count - 1) * 32 + 28), "height": 32.0, "from_ceiling": from_ceiling, "boss_attack": true}

## The king's side: where the runner was one delay ago (true = ceiling).
func king_on_ceiling(course_distance: float) -> bool:
	var at := course_distance - delay_distance()
	var side := false
	for change in _history:
		if float(change[0]) <= at:
			side = bool(change[1])
		else:
			break
	return side

func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while not _pending.is_empty() and float(_pending[0].course_distance) <= spawn_line_distance:
		ready.append(_pending.pop_front())
	return ready

## Call once per physics tick. Returns "hit", "missed", "defeated", "fire"
## (ghost fire was just dropped) or "".
func observe_runner(course_distance: float, gravity_direction: int, _grounded: bool) -> String:
	var on_ceiling := gravity_direction < 0
	if bool(_history[_history.size() - 1][1]) != on_ceiling:
		_history.append([course_distance, on_ceiling])
	var result := ""
	if course_distance >= _next_trail and course_distance <= _trail_to:
		_next_trail = course_distance + TRAIL_SPACING
		var at := course_distance + TRAIL_AHEAD
		if _trail_is_clear(at):
			var fire := _make_event(at, "ceiling_spikes" if king_on_ceiling(course_distance) else "floor_spikes", 3)
			fire["ghost_fire"] = true
			_add(fire)
			result = "fire"
	if lantern.is_empty() or str(lantern.state) != "armed":
		return result
	var lantern_distance := float(lantern.distance)
	if course_distance < lantern_distance:
		return result
	var lantern_ceiling := bool(lantern.ceiling)
	if king_on_ceiling(course_distance) == lantern_ceiling and on_ceiling != lantern_ceiling:
		lantern.state = "hit"
		hp -= 1
		attempts_in_phase = 0
		if hp <= 0:
			finish_distance = lantern_distance + RUNOUT_DISTANCE
			return "defeated"
		phase += 1
		_schedule_phase(lantern_distance + PHASE_GAP)
		return "hit"
	lantern.state = "missed"
	attempts_in_phase += 1
	_schedule_phase(lantern_distance + PHASE_GAP)
	return "missed"

func _trail_is_clear(at: float) -> bool:
	for event in _scheduled:
		if absf(float(event.course_distance) - at) < TRAIL_CLEARANCE:
			return false
	return lantern.is_empty() or absf(float(lantern.distance) - at) > TRAIL_CLEARANCE + 300.0

func get_scheduled_events() -> Array[Dictionary]:
	return _scheduled.duplicate()

## Which surface a runner must be on near a course distance: 1 floor, -1
## ceiling, 0 either. Used by the test bot: before the lantern its side,
## then away from it after the king's delay has started to run.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		var d := float(event.course_distance)
		var half := float(event.width) * 0.5
		if course_distance >= d - half - 90.0 and course_distance <= d + half + 60.0:
			return 1 if bool(event.from_ceiling) else -1
	if not lantern.is_empty() and str(lantern.state) == "armed":
		var side := -1 if bool(lantern.ceiling) else 1
		var distance := float(lantern.distance)
		var flip_at := distance - delay_distance() + 90.0
		if course_distance >= distance - 700.0 and course_distance <= flip_at - 60.0:
			return side
		if course_distance >= flip_at and course_distance <= distance + 80.0:
			return -side
	return 0
