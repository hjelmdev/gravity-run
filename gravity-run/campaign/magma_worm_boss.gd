extends RullarenBoss
class_name MagmaWormBoss
## Magmaormen, the volcano boss: a worm of magma that rises out of the lava
## behind the runner and spits ember bombs ahead of it. It is Rullaren's script
## with other attacks: each phase schedules ember bombs (the scripted volcano
## hazard), ceiling spikes and blocks at fixed offsets, then a glowing scale on
## the floor or ceiling. Running over the scale on its side hits the worm;
## three hits defeat it, and a missed scale repeats the phase. Scheduling, hits
## and misses are RullarenBoss's, so CampaignRun drives both the same way.

const BOMB_WIDTH := 60.0
const BOMB_HEIGHT := 90.0

## Attack rows: [offset, kind, side or count]
## kind: "bomb" (side "floor"|"ceiling"), "fan" (bombs alternating sides,
## count), "ceiling_spikes" (count), "floor_block".
const WORM_PHASES := [
	{
		"title": "Ember fan",
		"plate_offset": 3300.0, "plate_ceiling": false,
		"attacks": [[0.0, "bomb", "floor"], [800.0, "bomb", "ceiling"], [1600.0, "fan", 3]],
	},
	{
		"title": "Burning ground",
		"plate_offset": 3700.0, "plate_ceiling": true,
		"attacks": [[0.0, "fan", 2], [1000.0, "floor_block", 1], [1800.0, "ceiling_spikes", 5], [2700.0, "bomb", "floor"]],
	},
	{
		"title": "Eruption",
		"plate_offset": 4100.0, "plate_ceiling": false,
		"attacks": [[0.0, "fan", 3], [2000.0, "ceiling_spikes", 6], [2500.0, "floor_block", 1], [3200.0, "bomb", "ceiling"]],
	},
]
## Course distance between the bombs of a fan.
const FAN_SPACING := 720.0

func get_phase_title() -> String:
	return str(WORM_PHASES[mini(phase, WORM_PHASES.size() - 1)].title)

func _schedule_phase(anchor: float) -> void:
	var spec: Dictionary = WORM_PHASES[phase]
	for attack in spec.attacks:
		for event in _worm_events(anchor + float(attack[0]), str(attack[1]), attack[2]):
			_pending.append(event)
			_scheduled.append(event)
	plate = {"distance": anchor + float(spec.plate_offset), "ceiling": bool(spec.plate_ceiling), "state": "armed"}

func _worm_events(distance: float, kind: String, arg: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match kind:
		"bomb":
			result.append(_bomb(distance, str(arg) == "ceiling"))
		"fan":
			for index in range(int(arg)):
				result.append(_bomb(distance + float(index) * FAN_SPACING, index % 2 == 1))
		"floor_block":
			result.append({"kind": "block", "id": "block", "course_distance": distance, "width": 56.0, "height": 120.0, "from_ceiling": false, "boss_attack": true})
		_:
			var count := int(arg)
			result.append({"kind": "spikes", "id": "spike_group", "course_distance": distance, "count": count, "width": float((count - 1) * 32 + 28), "height": 32.0, "from_ceiling": true, "boss_attack": true})
	return result

func _bomb(distance: float, ceiling: bool) -> Dictionary:
	return {
		"kind": "ember_bomb", "id": "ember_bomb", "course_distance": distance,
		"width": BOMB_WIDTH, "height": BOMB_HEIGHT, "from_ceiling": ceiling,
		"early_lead": CampaignFeatures.HAND_EARLY_LEAD, "boss_attack": true,
	}

## Which surface a runner must be on near a course distance to survive the
## scheduled attacks: 1 floor, -1 ceiling, 0 either. Used by the test bot.
func required_side_at(course_distance: float) -> int:
	for event in _scheduled:
		var d := float(event.course_distance)
		var half := float(event.width) * 0.5
		if str(event.kind) == "ember_bomb":
			if course_distance >= d - 330.0 and course_distance <= d + 80.0:
				return 1 if bool(event.from_ceiling) else -1
		elif course_distance >= d - half - 90.0 and course_distance <= d + half + 60.0:
			return 1 if bool(event.from_ceiling) else -1
	if not plate.is_empty() and str(plate.state) == "armed" and absf(course_distance - float(plate.distance)) <= PLATE_WIDTH * 0.5:
		return -1 if bool(plate.ceiling) else 1
	return 0
