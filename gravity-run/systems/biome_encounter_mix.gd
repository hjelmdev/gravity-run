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

const GEN14_OVERLAY := {
	"classic": {"lava_crack": 0.0, "lava_volcano": 0.0},
	"cave": {"lava_crack": 0.0, "lava_volcano": 0.0},
	"haunted": {"lava_crack": 0.0, "lava_volcano": 0.0},
	"lava": {"haunted_ghost": 0.0, "lava_crack": 2.4, "lava_volcano": 1.7, "falling_rock": 0.45, "saw_blade": 0.65, "spike_group": 0.75},
}

const GEN16_HAZARD_OVERLAY := {
	"classic": {"spike_group": 1.4, "block": 1.4, "barrel_chain": 1.4, "falling_rock": 1.4, "saw_blade": 1.4, "terrain_step": 0.7, "terrain_slope": 0.7},
	"cave": {"spike_group": 1.4, "block": 1.4, "barrel_chain": 1.4, "falling_rock": 1.4, "saw_blade": 1.4, "terrain_step": 0.7, "terrain_slope": 0.7},
	"haunted": {"haunted_ghost": 1.5, "spike_group": 1.4, "block": 1.4, "barrel_chain": 1.4, "falling_rock": 1.4, "saw_blade": 1.4, "terrain_step": 0.7, "terrain_slope": 0.7},
	"lava": {"lava_crack": 1.4, "lava_volcano": 1.4, "spike_group": 1.4, "block": 1.4, "barrel_chain": 1.4, "falling_rock": 1.4, "saw_blade": 1.4, "terrain_step": 0.7, "terrain_slope": 0.7},
}

static func multiplier(generator_version: int, biome_id: String, profile_id: StringName) -> float:
	if generator_version < 12:
		return 1.0
	if generator_version >= 16:
		var base_weights: Dictionary = GEN12_TABLE.get(biome_id, {})
		var lava_overlay: Dictionary = GEN14_OVERLAY.get(biome_id, {})
		var generation_overlay: Dictionary = GEN16_HAZARD_OVERLAY.get(biome_id, {})
		return float(base_weights.get(String(profile_id), 1.0)) * float(lava_overlay.get(String(profile_id), 1.0)) * float(generation_overlay.get(String(profile_id), 1.0))
	if generator_version >= 14:
		var base_weights: Dictionary = GEN12_TABLE.get(biome_id, {})
		var overlay: Dictionary = GEN14_OVERLAY.get(biome_id, {})
		return float(base_weights.get(String(profile_id), 1.0)) * float(overlay.get(String(profile_id), 1.0))
	var biome_weights: Dictionary = GEN12_TABLE.get(biome_id, {})
	return float(biome_weights.get(String(profile_id), 1.0))
