extends RullarenBoss
class_name SnowGiantBoss
## Snöjätten, the frost mountain boss: a giant of snow at the right edge of the
## screen. It is Rullaren's script with other attacks: it throws snowballs
## (Rullaren's thrown barrels, drawn as snowballs), stamps loose avalanches
## (the frost world's scripted feature: rocks onto the floor) and ice shards
## from the ceiling, then an ice plate on the floor or ceiling. Running over
## the plate on its side hits the giant; three hits defeat it, and a missed
## plate repeats the phase. Scheduling, hits and misses are RullarenBoss's.

## Attack rows: [offset, kind, count, height, spiked]
## kind: "barrels" (floor), "ceiling_block", "ceiling_spikes", "avalanche".
const GIANT_PHASES := [
	{
		"title": "Snowball volley",
		"plate_offset": 3000.0, "plate_ceiling": false,
		"attacks": [[0.0, "barrels", 1, 54.0, false], [900.0, "barrels", 2, 54.0, false], [1900.0, "barrels", 1, 76.0, false]],
	},
	{
		"title": "Avalanche",
		"plate_offset": 3700.0, "plate_ceiling": true,
		"attacks": [[0.0, "avalanche", 3, 0.0, false], [1300.0, "ceiling_spikes", 5, 32.0, false], [2200.0, "barrels", 2, 76.0, false]],
	},
	{
		"title": "Blizzard",
		"plate_offset": 4300.0, "plate_ceiling": false,
		"attacks": [[0.0, "barrels", 1, 76.0, true], [800.0, "ceiling_block", 1, 132.0, false], [1700.0, "avalanche", 3, 0.0, false], [3000.0, "barrels", 2, 54.0, true]],
	},
]

## The phase table (a subclass with other attacks overrides this).
func _phases() -> Array:
	return GIANT_PHASES

## The scripted rock feature its "avalanche" rows drop.
func _rock_feature() -> String:
	return "avalanche"

func get_phase_title() -> String:
	var phases := _phases()
	return str(phases[mini(phase, phases.size() - 1)].title)

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = _phases()[phase]
	for attack in spec.attacks:
		var distance := anchor + float(attack[0])
		var events: Array[Dictionary] = []
		if str(attack[1]) == "avalanche":
			for event in CampaignFeatures.events_of({"kind": _rock_feature(), "at": distance, "count": int(attack[2])}):
				event["boss_attack"] = true
				events.append(event)
		else:
			events.append(_make_event(distance, str(attack[1]), int(attack[2]), float(attack[3]), bool(attack[4])))
		for event in events:
			_pending.append(event)
			_scheduled.append(event)
	plate = {"distance": anchor + float(spec.plate_offset), "ceiling": bool(spec.plate_ceiling), "state": "armed"}

var _runner_distance := 0.0

func observe_runner(course_distance: float, gravity_direction: int, grounded: bool) -> String:
	_runner_distance = course_distance
	return super.observe_runner(course_distance, gravity_direction, grounded)

## Avalanche rocks must exist long before they land ("early_lead"), like the
## feature's; everything else waits for the spawn line.
func pop_events_until(spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for event in _pending:
		var at := float(event.course_distance)
		if at <= spawn_line_distance or _runner_distance + float(event.get("early_lead", 0.0)) >= at:
			ready.append(event)
		else:
			waiting.append(event)
	_pending = waiting
	return ready

## Which surface a runner must be on near a course distance to survive the
## scheduled attacks: 1 floor, -1 ceiling, 0 either. Used by the test bot.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		if str(event.get("kind", "")) == "rock":
			var d := float(event.course_distance)
			if course_distance >= d - 400.0 and course_distance <= d + CampaignFeatures.ROCK_WIDTH * 0.5 + 90.0:
				return -1
	return super.required_side_at(course_distance)
