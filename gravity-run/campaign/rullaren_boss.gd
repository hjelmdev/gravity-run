extends RefCounted
class_name RullarenBoss
## Rullaren, the meadow boss: a barrel machine that rides at the right edge of
## the screen. It is a script, not new physics. Each phase schedules ordinary
## course events (barrel chains, ceiling blocks and ceiling spikes) at fixed
## offsets, then a pressure plate on the floor or ceiling. Running over the
## plate on its side hits the machine; three hits defeat it. Missing a plate
## repeats the phase. All positions are course distances, so the fight is
## deterministic for a given sequence of hits and misses.

const INTRO_DISTANCE := 2600.0
## Space after a plate before the next wave, so the next events are always
## planned beyond any viewport's spawn line (they never pop in on screen).
const PHASE_GAP := 2200.0
const RUNOUT_DISTANCE := 2400.0
const MAX_HP := 3
const PLATE_WIDTH := 150.0
const BARREL_SPEED := 1.4

## Attack rows: [offset, kind, count, height, spiked]
## kind: "barrels" (floor), "ceiling_block", "ceiling_spikes".
const PHASES := [
	{
		"title": "Barrel rain",
		"plate_offset": 2900.0, "plate_ceiling": false,
		"attacks": [[0.0, "barrels", 1, 54.0, false], [900.0, "barrels", 1, 76.0, false], [1800.0, "barrels", 2, 54.0, false]],
	},
	{
		"title": "Spit and roll",
		"plate_offset": 3500.0, "plate_ceiling": true,
		"attacks": [[0.0, "barrels", 2, 76.0, false], [850.0, "ceiling_block", 1, 132.0, false], [1700.0, "barrels", 3, 54.0, false], [2600.0, "ceiling_spikes", 5, 32.0, false]],
	},
	{
		"title": "Full throttle",
		"plate_offset": 3800.0, "plate_ceiling": false,
		"attacks": [[0.0, "barrels", 1, 76.0, true], [700.0, "ceiling_block", 1, 132.0, false], [1400.0, "barrels", 2, 76.0, false], [2100.0, "ceiling_spikes", 6, 32.0, false], [2800.0, "barrels", 3, 54.0, true]],
	},
]

var hp := MAX_HP
var phase := 0
var attempts_in_phase := 0
## {"distance": float, "ceiling": bool, "state": "armed"|"hit"|"missed"}
var plate: Dictionary = {}
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

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = PHASES[phase]
	for attack in spec.attacks:
		var event := _make_event(anchor + float(attack[0]), str(attack[1]), int(attack[2]), float(attack[3]), bool(attack[4]))
		_pending.append(event)
		_scheduled.append(event)
	plate = {"distance": anchor + float(spec.plate_offset), "ceiling": bool(spec.plate_ceiling), "state": "armed"}

func _make_event(distance: float, kind: String, count: int, height: float, spiked: bool) -> Dictionary:
	match kind:
		"barrels":
			return {"kind": "barrels", "id": "barrel_chain", "course_distance": distance, "count": count, "width": 54.0 + float(count - 1) * 70.0, "height": height, "motion_speed_multiplier": BARREL_SPEED, "spiked": spiked, "from_ceiling": false, "boss_attack": true}
		"ceiling_block":
			return {"kind": "block", "id": "block", "course_distance": distance, "width": 56.0, "height": height, "from_ceiling": true, "boss_attack": true}
		_:
			return {"kind": "spikes", "id": "spike_group", "course_distance": distance, "count": count, "width": float((count - 1) * 32 + 28), "height": height, "from_ceiling": true, "boss_attack": true}

## Events whose course distance has reached the spawn line, in order.
func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while not _pending.is_empty() and float(_pending[0].course_distance) <= spawn_line_distance:
		ready.append(_pending.pop_front())
	return ready

## Call once per physics tick with the runner's course distance. Returns
## "hit", "missed", "defeated" or "".
func observe_runner(course_distance: float, gravity_direction: int, grounded: bool) -> String:
	if plate.is_empty() or str(plate.state) != "armed":
		return ""
	var plate_distance := float(plate.distance)
	var half := PLATE_WIDTH * 0.5
	var on_side := (gravity_direction < 0) == bool(plate.ceiling)
	if course_distance >= plate_distance - half and course_distance <= plate_distance + half and on_side and grounded:
		plate.state = "hit"
		hp -= 1
		attempts_in_phase = 0
		if hp <= 0:
			finish_distance = plate_distance + RUNOUT_DISTANCE
			return "defeated"
		phase += 1
		_schedule_phase(plate_distance + PHASE_GAP)
		return "hit"
	if course_distance > plate_distance + half:
		plate.state = "missed"
		attempts_in_phase += 1
		_schedule_phase(plate_distance + PHASE_GAP)
		return "missed"
	return ""

## Every attack scheduled so far (for tests and the presentation).
func get_scheduled_events() -> Array[Dictionary]:
	return _scheduled.duplicate()

## Which surface a runner must be on near a course distance to survive the
## scheduled attacks: 1 floor, -1 ceiling, 0 either. Used by the test bot.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		var d := float(event.course_distance)
		var half := float(event.width) * 0.5
		if str(event.kind) == "barrels":
			if course_distance >= d - half - 140.0 and course_distance <= d + half + 120.0:
				return -1
		elif course_distance >= d - half - 90.0 and course_distance <= d + half + 60.0:
			return 1
	if not plate.is_empty() and str(plate.state) == "armed" and absf(course_distance - float(plate.distance)) <= PLATE_WIDTH * 0.5:
		return -1 if bool(plate.ceiling) else 1
	return 0
