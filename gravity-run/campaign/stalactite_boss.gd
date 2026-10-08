extends RefCounted
class_name StalactiteBoss
## Stalaktitjätten, the cave boss: a giant bat that hangs from the ceiling at
## the right edge of the view. Like Rullaren it is a script, not new physics:
## each phase schedules ordinary course events (falling icicles and rocks,
## ceiling spikes and blocks) at fixed course distances, then a dive at a
## giant icicle.
##
## The dive is the weak point. A giant icicle with a glowing crack hangs at a
## marked spot, on the ceiling or on the floor. When the warning starts the bat
## locks onto the side the runner is on; when the dive arrives it sweeps that
## side. A runner still there is caught. A runner who stood on the icicle's
## side when the warning started and flipped away in time makes the bat crash
## into the icicle: one hit. Flipping too early makes the bat dive at the
## wrong side and the icicle comes back on the next round. Three hits defeat
## it, and every hit shortens the warning. All positions are course
## distances, so the fight is deterministic for a given sequence of choices.

const INTRO_DISTANCE := 2600.0
## Space after a dive before the next wave, so the next events are always
## planned beyond any viewport's spawn line (they never pop in on screen).
const PHASE_GAP := 2200.0
const RUNOUT_DISTANCE := 2400.0
const MAX_HP := 3
## The dive reaches the runner this far before the icicle.
const ARRIVE_LEAD := 90.0
## Warning distance (course px) before the dive arrives, by hits taken. The
## icicle comes into view about 780 px ahead, so it is always visible first.
const WARNING_DISTANCES := [640.0, 540.0, 440.0]
## Icicles in a row are spaced so the runner can stay on the ceiling past them.
const ICICLE_SPACING := 230.0
const ICICLE_LODGED_TICKS := 70

## Attack rows: [offset, kind, count]
## kind: "icicles" (fall to the floor: be on the ceiling), "rocks" (same),
## "ceiling_spikes" and "ceiling_block" (be on the floor).
const PHASES := [
	{
		"title": "Icicle rows",
		"dive_offset": 3400.0, "dive_ceiling": true,
		"attacks": [[0.0, "icicles", 2], [1000.0, "ceiling_spikes", 4], [1800.0, "icicles", 3]],
	},
	{
		"title": "Wing beat",
		"dive_offset": 3900.0, "dive_ceiling": false,
		"attacks": [[0.0, "rocks", 1], [650.0, "ceiling_spikes", 4], [1300.0, "icicles", 2], [2000.0, "ceiling_block", 1], [2650.0, "rocks", 2]],
	},
	{
		"title": "Frenzy",
		"dive_offset": 4500.0, "dive_ceiling": true,
		"attacks": [[0.0, "icicles", 2], [750.0, "ceiling_spikes", 5], [1350.0, "rocks", 2], [2050.0, "ceiling_block", 1], [2650.0, "icicles", 3], [3600.0, "ceiling_spikes", 4]],
	},
]

var hp := MAX_HP
var phase := 0
var attempts_in_phase := 0
## {"distance": float, "ceiling": bool, "warning": float,
##  "state": "armed"|"warning"|"hit"|"missed", "locked_ceiling": bool}
var dive: Dictionary = {}
## Course distance of the finish line once the boss is defeated, else -1.
var finish_distance := -1.0
var _pending: Array[Dictionary] = []
var _scheduled: Array[Dictionary] = []

func reset() -> void:
	hp = MAX_HP
	phase = 0
	attempts_in_phase = 0
	finish_distance = -1.0
	_pending.clear()
	_scheduled.clear()
	_schedule_phase(INTRO_DISTANCE)

func is_defeated() -> bool:
	return hp <= 0

func get_max_hp() -> int:
	return MAX_HP

func get_phase_title() -> String:
	return str(PHASES[mini(phase, PHASES.size() - 1)].title)

func warning_distance() -> float:
	return float(WARNING_DISTANCES[clampi(MAX_HP - hp, 0, WARNING_DISTANCES.size() - 1)])

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = PHASES[phase]
	for attack in spec.attacks:
		for event in _make_events(anchor + float(attack[0]), str(attack[1]), int(attack[2])):
			_pending.append(event)
			_scheduled.append(event)
	dive = {"distance": anchor + float(spec.dive_offset), "ceiling": bool(spec.dive_ceiling), "warning": warning_distance(), "state": "armed", "locked_ceiling": false}

func _make_events(distance: float, kind: String, count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match kind:
		"icicles", "rocks":
			var icicle := kind == "icicles"
			for index in range(count):
				var event := {"kind": "rock", "id": "falling_rock", "course_distance": distance + float(index) * ICICLE_SPACING, "width": 64.0 if icicle else 90.0, "height": 116.0 if icicle else 100.0, "boss_attack": true}
				if icicle:
					event["rock_variant"] = 1
					event["lodged_ticks"] = ICICLE_LODGED_TICKS
				events.append(event)
		"ceiling_block":
			events.append({"kind": "block", "id": "block", "course_distance": distance, "width": 56.0, "height": 132.0, "from_ceiling": true, "boss_attack": true})
		_:
			events.append({"kind": "spikes", "id": "spike_group", "course_distance": distance, "count": count, "width": float((count - 1) * 32 + 28), "height": 32.0, "from_ceiling": true, "boss_attack": true})
	return events

## Events whose course distance has reached the spawn line, in order.
func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while not _pending.is_empty() and float(_pending[0].course_distance) <= spawn_line_distance:
		ready.append(_pending.pop_front())
	return ready

## Call once per physics tick with the runner's course distance and side.
## Returns "warning" when the bat locks on, then "hit", "missed", "defeated"
## or "caught" (the runner was on the side the bat dived at), else "".
func observe_runner(course_distance: float, gravity_direction: int, _grounded: bool) -> String:
	if dive.is_empty():
		return ""
	var on_ceiling := gravity_direction < 0
	var dive_distance := float(dive.distance)
	match str(dive.state):
		"armed":
			if course_distance >= dive_distance - ARRIVE_LEAD - float(dive.warning):
				dive.state = "warning"
				dive.locked_ceiling = on_ceiling
				return "warning"
		"warning":
			if course_distance >= dive_distance - ARRIVE_LEAD:
				if on_ceiling == bool(dive.locked_ceiling):
					dive.state = "caught"
					return "caught"
				if bool(dive.locked_ceiling) == bool(dive.ceiling):
					dive.state = "hit"
					hp -= 1
					attempts_in_phase = 0
					if hp <= 0:
						finish_distance = dive_distance + RUNOUT_DISTANCE
						return "defeated"
					phase += 1
					_schedule_phase(dive_distance + PHASE_GAP)
					return "hit"
				dive.state = "missed"
				attempts_in_phase += 1
				_schedule_phase(dive_distance + PHASE_GAP)
				return "missed"
	return ""

## Every attack scheduled so far (for tests and the presentation).
func get_scheduled_events() -> Array[Dictionary]:
	return _scheduled.duplicate()

## Which surface a runner must be on near a course distance to survive the
## scheduled attacks and land a hit: 1 floor, -1 ceiling, 0 either. Used by
## the test bot. Before the warning the icicle's side, after it the other.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		var d := float(event.course_distance)
		var half := float(event.width) * 0.5
		if str(event.kind) == "rock":
			if course_distance >= d - half - 160.0 and course_distance <= d + half + 120.0:
				return -1
		elif course_distance >= d - half - 90.0 and course_distance <= d + half + 60.0:
			return 1
	if not dive.is_empty() and str(dive.state) in ["armed", "warning"]:
		var icicle_side := -1 if bool(dive.ceiling) else 1
		var warn_start := float(dive.distance) - ARRIVE_LEAD - float(dive.warning)
		if course_distance >= warn_start - 320.0 and course_distance <= warn_start + 40.0:
			return icicle_side
		if course_distance >= warn_start + 160.0 and course_distance <= float(dive.distance) + 60.0:
			return -icicle_side
	return 0
