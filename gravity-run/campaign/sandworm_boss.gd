extends SnowGiantBoss
class_name SandwormBoss
## Sandmasken, the desert boss: a giant worm that bursts out of the dunes
## behind the runner. It is the Snow Giant's script with other attacks (and so
## Rullaren's): it shakes sandfalls loose (the desert's scripted rock
## feature), raises cactus spikes from the ceiling and dune walls on the floor,
## then a glowing scale on the floor or ceiling. Running over the scale on its
## side hits the worm; three hits defeat it, and a missed scale repeats the
## phase. It throws nothing, so no barrels.

## Attack rows: [offset, kind, count, height, spiked]
## kind: "avalanche" (a sandfall here), "ceiling_spikes", "ceiling_block".
const WORM_PHASES := [
	{
		"title": "Tremor",
		"plate_offset": 3300.0, "plate_ceiling": false,
		"attacks": [[0.0, "avalanche", 3, 0.0, false], [1500.0, "ceiling_spikes", 5, 32.0, false], [2300.0, "ceiling_block", 1, 132.0, false]],
	},
	{
		"title": "Dune quake",
		"plate_offset": 4000.0, "plate_ceiling": true,
		"attacks": [[0.0, "ceiling_spikes", 6, 32.0, false], [900.0, "avalanche", 3, 0.0, false], [2300.0, "ceiling_block", 1, 132.0, false], [3000.0, "avalanche", 3, 0.0, false]],
	},
	{
		"title": "Sea of sand",
		"plate_offset": 4500.0, "plate_ceiling": false,
		"attacks": [[0.0, "avalanche", 4, 0.0, false], [1400.0, "ceiling_spikes", 6, 32.0, false], [2200.0, "avalanche", 3, 0.0, false], [3500.0, "ceiling_block", 1, 132.0, false]],
	},
]

func _phases() -> Array:
	return WORM_PHASES

func _rock_feature() -> String:
	return "sandfall"
