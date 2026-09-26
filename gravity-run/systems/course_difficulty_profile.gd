extends Resource
class_name CourseDifficultyProfile
## Optional, composable difficulty multipliers for CourseGenerator.
## A generator with no profile assigned retains its original behavior.

@export_range(0.5, 2.5, 0.05) var event_density := 1.0
@export_range(0.75, 1.5, 0.05) var hazard_size := 1.0
## Chance that a both-lane profile blocks the lane opposite the previous event.
@export_range(0.0, 1.0, 0.05) var lane_alternation := 0.0
## Scales the extra reaction-time allowance, not the player's physical limits.
@export_range(0.0, 2.0, 0.05) var reaction_margin := 1.0
## Optional per-profile weight multipliers, keyed by profile_id string.
@export var profile_weight_multipliers: Dictionary = {}

func get_profile_weight_multiplier(profile_id: StringName) -> float:
	return maxf(0.0, float(profile_weight_multipliers.get(String(profile_id), 1.0)))
