extends RefCounted
class_name BiomeEncounterMix
## Generation-only encounter weighting. All inputs are course distance/profile
## data; cameras and live player position are deliberately not consulted.

const GEN12_TABLE := {
	"classic": {},
	"cave": {
		"falling_rock": 2.1,
		"saw_blade": 1.7,
		"spike_group": 0.9,
		"haunted_ghost": 0.0,
	},
	"haunted": {
		"haunted_ghost": 3.2,
		"falling_rock": 0.85,
	},
}

static func multiplier(generator_version: int, biome_id: String, profile_id: StringName) -> float:
	if generator_version < 12:
		return 1.0
	var biome_weights: Dictionary = GEN12_TABLE.get(biome_id, {})
	return float(biome_weights.get(String(profile_id), 1.0))
