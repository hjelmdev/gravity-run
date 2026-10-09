extends RullarenBoss
class_name ThunderbirdBoss
## Åskfågeln, the Cloud Realm boss: a great bird of storm that circles at the
## right of the screen and calls lightning down ahead of the runner. It is
## Rullaren's script with other attacks: each phase schedules lightning strikes
## (the cloud world's scripted hazard), ceiling spikes and blocks at fixed
## offsets, then a feather plate on the floor or ceiling. Running over the plate
## on its side hits the bird; three hits defeat it, and a missed plate repeats
## the phase. Scheduling, hits and misses are RullarenBoss's.

## Attack rows: [offset, kind, side or count]
## kind: "strike" (side "floor"|"ceiling"), "volley" (strikes alternating
## sides, count), "ceiling_spikes" (count), "floor_block".
const BIRD_PHASES := [
	{
		"title": "First thunder",
		"plate_offset": 3300.0, "plate_ceiling": true,
		"attacks": [[0.0, "strike", "floor"], [800.0, "strike", "ceiling"], [1600.0, "volley", 3]],
	},
	{
		"title": "Rolling storm",
		"plate_offset": 3800.0, "plate_ceiling": false,
		"attacks": [[0.0, "volley", 3], [2000.0, "ceiling_spikes", 5], [2800.0, "strike", "ceiling"]],
	},
	{
		"title": "Eye of the storm",
		"plate_offset": 4300.0, "plate_ceiling": true,
		"attacks": [[0.0, "volley", 4], [2600.0, "floor_block", 1], [3400.0, "strike", "floor"]],
	},
]
## Course distance between the strikes of a volley.
const VOLLEY_SPACING := 700.0

func get_phase_title() -> String:
	return str(BIRD_PHASES[mini(phase, BIRD_PHASES.size() - 1)].title)

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = BIRD_PHASES[phase]
	for attack in spec.attacks:
		for event in _bird_events(anchor + float(attack[0]), str(attack[1]), attack[2]):
			_pending.append(event)
			_scheduled.append(event)
	plate = {"distance": anchor + float(spec.plate_offset), "ceiling": bool(spec.plate_ceiling), "state": "armed"}

func _bird_events(distance: float, kind: String, arg: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match kind:
		"strike":
			result.append(_strike(distance, str(arg) == "ceiling"))
		"volley":
			for index in range(int(arg)):
				result.append(_strike(distance + float(index) * VOLLEY_SPACING, index % 2 == 1))
		"floor_block":
			result.append({"kind": "block", "id": "block", "course_distance": distance, "width": 56.0, "height": 120.0, "from_ceiling": false, "boss_attack": true})
		_:
			var count := int(arg)
			result.append({"kind": "spikes", "id": "spike_group", "course_distance": distance, "count": count, "width": float((count - 1) * 32 + 28), "height": 32.0, "from_ceiling": true, "boss_attack": true})
	return result

func _strike(distance: float, ceiling: bool) -> Dictionary:
	return {
		"kind": "lightning", "id": "lightning", "course_distance": distance,
		"width": CampaignFeatures.HAND_WIDTH, "height": CampaignFeatures.HAND_HEIGHT, "from_ceiling": ceiling,
		"early_lead": CampaignFeatures.HAND_EARLY_LEAD, "boss_attack": true,
	}

## Which surface a runner must be on near a course distance to survive the
## scheduled attacks: 1 floor, -1 ceiling, 0 either. Used by the test bot.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		var d := float(event.course_distance)
		var half := float(event.width) * 0.5
		if str(event.kind) == "lightning":
			if course_distance >= d - 330.0 and course_distance <= d + 80.0:
				return 1 if bool(event.from_ceiling) else -1
		elif course_distance >= d - half - 90.0 and course_distance <= d + half + 60.0:
			return 1 if bool(event.from_ceiling) else -1
	if not plate.is_empty() and str(plate.state) == "armed" and absf(course_distance - float(plate.distance)) <= PLATE_WIDTH * 0.5:
		return -1 if bool(plate.ceiling) else 1
	return 0
