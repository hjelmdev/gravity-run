extends RefCounted
class_name CampaignCatalog
## Every campaign world and stage. Stages are data: change a row here (or run
## tools/campaign/campaign_level_tool.gd to pick a new seed and stars) and the
## map, progress and runtime follow. Seeds and stars are frozen values chosen by
## the tool; changing them changes the stage identity and resets its records.

const RulesetScript := preload("res://systems/course_generation_ruleset.gd")
const CAMPAIGN_GENERATOR_VERSION := 21
const CAMPAIGN_COIN_REVISION := 2

## Map node centres in 320x180 map pixels (tools/campaign/generate_world_maps.py
## paints the path through the same points).
const MEADOW_MAP_NODES := [Vector2(38, 138), Vector2(78, 112), Vector2(118, 134), Vector2(158, 100), Vector2(200, 122), Vector2(238, 92), Vector2(286, 66)]
const CAVE_MAP_NODES := [Vector2(34, 70), Vector2(74, 98), Vector2(116, 74), Vector2(156, 110), Vector2(196, 84), Vector2(238, 118), Vector2(284, 92)]
const HAUNTED_MAP_NODES := [Vector2(36, 120), Vector2(78, 92), Vector2(118, 124), Vector2(160, 96), Vector2(202, 130), Vector2(242, 100), Vector2(286, 74)]
const LAVA_MAP_NODES := [Vector2(36, 96), Vector2(76, 128), Vector2(118, 100), Vector2(158, 132), Vector2(200, 104), Vector2(240, 134), Vector2(286, 104)]
const FROST_MAP_NODES := [Vector2(34, 126), Vector2(76, 100), Vector2(118, 128), Vector2(160, 96), Vector2(202, 124), Vector2(244, 94), Vector2(286, 70)]
const CLOUD_MAP_NODES := [Vector2(36, 90), Vector2(78, 118), Vector2(120, 88), Vector2(162, 116), Vector2(204, 86), Vector2(246, 112), Vector2(286, 80)]

## Ängen. Each stage adds one hazard family; 1-6 is the exam with everything.
## Lengths grow from 30 s to 45 s at the base 500 px/s.
const MEADOW_STAGES := [
	{
		"id": &"1-1", "title": "First Steps", "intro": "New: spikes and blocks",
		"profiles": ["spike_group", "block"], "new": ["spike_group", "block"],
		"density": 0.85, "margin": 1.5, "length": 15000.0,
		"seed": 1101,
		"stars": [Vector2(3848.11, 114.00), Vector2(8357.47, 114.00), Vector2(13507.03, 114.00)],
	},
	{
		"id": &"1-2", "title": "Mind the Gap", "intro": "New: holes in the floor and ceiling",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap"], "new": ["floor_gap", "ceiling_gap"],
		"density": 0.95, "margin": 1.35, "length": 16500.0,
		"seed": 1224,
		"stars": [Vector2(4982.69, 114.00), Vector2(9085.43, 114.00), Vector2(13707.24, 114.00)],
	},
	{
		"id": &"1-3", "title": "Rolling Barrels", "intro": "New: rolling barrels",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain"], "new": ["barrel_chain"],
		"density": 1.05, "margin": 1.25, "length": 18000.0,
		"seed": 1308,
		"stars": [Vector2(4788.44, 114.00), Vector2(9715.36, 114.00), Vector2(16025.47, 426.00)],
	},
	{
		"id": &"1-4", "title": "Ups and Downs", "intro": "New: steps and slopes",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope"], "new": ["terrain_step", "terrain_slope"],
		"density": 1.15, "margin": 1.15, "length": 19500.0,
		"seed": 1418,
		"stars": [Vector2(5182.72, 296.00), Vector2(11206.41, 434.80), Vector2(16213.76, 466.00)],
	},
	{
		"id": &"1-5", "title": "Falling Rocks", "intro": "New: falling rocks and saw blades",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": ["falling_rock", "saw_blade"],
		"density": 1.4, "margin": 1.05, "length": 21000.0,
		"seed": 1527,
		"stars": [Vector2(5524.46, 114.00), Vector2(11281.27, 114.00), Vector2(17664.89, 114.00)],
	},
	{
		"id": &"1-6", "title": "Meadow Exam", "intro": "Everything the meadow has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"density": 1.4, "margin": 1.0, "length": 22500.0,
		"seed": 1605,
		"stars": [Vector2(5765.90, 222.00), Vector2(11956.02, 222.00), Vector2(18287.82, 222.00)],
	},
]

## Grottan. The player already knows every general hazard, so the cave starts
## around 1-4's level and teaches one new generated hazard (icicles); the rest
## of the cave's surprises are scripted features (see campaign_run.gd).
## "weights" multiplies a profile's weight on top of the new-hazard boost.
## "features" are scripted extras (campaign_features.gd) frozen by
## `campaign_level_tool.gd -- features`; "new_features" are the feature kinds a
## stage introduces with a "New hazard" callout.
const CAVE_STAGES := [
	{
		"id": &"2-1", "title": "Dripstones", "intro": "New: icicles",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": ["cave_icicle"],
		"weights": {"cave_icicle": 2.0},
		"density": 1.15, "margin": 1.3, "length": 16500.0,
		"seed": 2157,
		"stars": [Vector2(4328.59, 426.00), Vector2(9565.05, 114.00), Vector2(12598.14, 114.00)],
	},
	{
		"id": &"2-2", "title": "Tight Tunnels", "intro": "Steps and slopes come thick and fast",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"terrain_step": 2.0, "terrain_slope": 2.0},
		"density": 1.2, "margin": 1.2, "length": 18000.0,
		"seed": 2254,
		"stars": [Vector2(4881.66, 150.97), Vector2(10253.75, 254.00), Vector2(13663.87, 418.00)],
		"features": [{"kind": "bat_swarm", "at": 2960.0, "side": "ceiling"}, {"kind": "bat_swarm", "at": 6630.0, "side": "ceiling"}, {"kind": "bat_swarm", "at": 13120.0, "side": "floor"}],
		"new_features": ["bat_swarm"],
	},
	{
		"id": &"2-3", "title": "Mine Run", "intro": "Mine carts roll through the tunnels",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"barrel_chain": 2.0},
		"density": 1.3, "margin": 1.15, "length": 19500.0,
		"seed": 2377,
		"stars": [Vector2(5403.52, 114.00), Vector2(10652.77, 114.00), Vector2(14306.41, 296.00)],
		"features": [{"kind": "bat_swarm", "at": 4150.0, "side": "ceiling"}, {"kind": "bat_swarm", "at": 6990.0, "side": "floor"}],
	},
	{
		"id": &"2-4", "title": "Cave-in", "intro": "Rocks and icicles fall together",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"falling_rock": 1.6, "cave_icicle": 1.6},
		"density": 1.4, "margin": 1.1, "length": 21000.0,
		"seed": 2463,
		"stars": [Vector2(5487.91, 114.00), Vector2(11542.10, 222.00), Vector2(15658.60, 150.00)],
		"features": [{"kind": "cave_in", "at": 9630.0, "count": 3}, {"kind": "cave_in", "at": 13880.0, "count": 4}, {"kind": "cave_in", "at": 17350.0, "count": 3}],
		"new_features": ["cave_in"],
	},
	{
		"id": &"2-5", "title": "Crystal Hall", "intro": "A dark hall lit by crystals",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.45, "margin": 1.05, "length": 22500.0,
		"seed": 2507,
		"stars": [Vector2(5559.09, 114.00), Vector2(12068.22, 254.00), Vector2(18011.33, 106.00)],
		"features": [{"kind": "darkness", "at": 5400.0, "length": 3600.0}, {"kind": "darkness", "at": 13950.0, "length": 4200.0}],
	},
	{
		"id": &"2-6", "title": "Cave Exam", "intro": "Everything the cave has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.5, "margin": 1.0, "length": 24000.0,
		"seed": 2601,
		"stars": [Vector2(6048.69, 426.00), Vector2(12638.04, 114.00), Vector2(18938.52, 426.00)],
		"features": [{"kind": "darkness", "at": 13920.0, "length": 3200.0}, {"kind": "cave_in", "at": 22010.0, "count": 3}],
	},
]

## Spökskogen. Ghosts are the new generated hazards (flyby and pursuit); the
## forest's other surprises are scripted features.
const HAUNTED_STAGES := [
	{
		"id": &"3-1", "title": "Ghost Path", "intro": "New: floating ghosts",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost"], "new": ["haunted_ghost"],
		"density": 1.1, "margin": 1.2, "length": 16500.0,
		"seed": 3178,
		"stars": [Vector2(4408.56, 114.00), Vector2(9649.64, 114.00), Vector2(13719.91, 114.00)],
	},
	{
		"id": &"3-2", "title": "Hunted", "intro": "New: a ghost that chases you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": ["haunted_chaser"],
		"density": 1.2, "margin": 1.15, "length": 18000.0,
		"seed": 3204,
		"stars": [Vector2(4477.82, 426.00), Vector2(9682.19, 114.00), Vector2(13358.47, 296.00)],
	},
	{
		"id": &"3-3", "title": "Graveyard", "intro": "Hands reach out of the ground",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.3, "margin": 1.1, "length": 19500.0,
		"seed": 3355,
		"stars": [Vector2(5131.34, 426.00), Vector2(10121.03, 114.00), Vector2(17541.81, 114.00)],
		"features": [{"kind": "ghost_hand", "at": 6390.0, "side": "floor"}, {"kind": "ghost_hand", "at": 8430.0, "side": "ceiling"}, {"kind": "ghost_hand", "at": 13220.0, "side": "floor"}, {"kind": "ghost_hand", "at": 14960.0, "side": "ceiling"}],
		"new_features": ["ghost_hand"],
	},
	{
		"id": &"3-4", "title": "The Fog", "intro": "Fog hides the way ahead",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.4, "margin": 1.05, "length": 21000.0,
		"seed": 3458,
		"stars": [Vector2(5581.50, 114.00), Vector2(11978.54, 222.00), Vector2(16104.22, 222.00)],
		"features": [{"kind": "fog", "at": 6300.0, "length": 2000.0}, {"kind": "fog", "at": 8760.0, "length": 2400.0}],
	},
	{
		"id": &"3-5", "title": "Will-o'-the-Wisp", "intro": "A wisp copies your side",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.5, "margin": 1.0, "length": 22500.0,
		"seed": 3575,
		"stars": [Vector2(7339.76, 114.00), Vector2(12027.32, 114.00), Vector2(17186.89, 222.00)],
		"features": [{"kind": "wisp", "at": 4950.0, "length": 1500.0}, {"kind": "wisp", "at": 11250.0, "length": 1500.0}, {"kind": "wisp", "at": 17550.0, "length": 1500.0}],
	},
	{
		"id": &"3-6", "title": "Forest Exam", "intro": "Everything the forest has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.6, "margin": 0.95, "length": 25000.0,
		"seed": 3640,
		"stars": [Vector2(6454.64, 426.00), Vector2(13416.85, 254.00), Vector2(20476.66, 426.00)],
		"features": [{"kind": "ghost_hand", "at": 8230.0, "side": "ceiling"}, {"kind": "fog", "at": 11390.0, "length": 2000.0}, {"kind": "ghost_hand", "at": 18110.0, "side": "floor"}],
	},
]

## Vulkanen. Lava is the new generated hazard family (cracks, volcanoes and
## tidal pools); ash and ember bombs are scripted features.
const LAVA_STAGES := [
	{
		"id": &"4-1", "title": "Glowing Path", "intro": "New: lava cracks",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack"], "new": ["lava_crack"],
		"density": 1.2, "margin": 1.15, "length": 17500.0,
		"seed": 4101,
		"stars": [Vector2(4477.53, 426.00), Vector2(9245.25, 114.00), Vector2(13581.01, 114.00)],
	},
	{
		"id": &"4-2", "title": "Ash Rain", "intro": "Ash falls from the sky",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack"], "new": [],
		"density": 1.3, "margin": 1.1, "length": 19000.0,
		"seed": 4203,
		"stars": [Vector2(4793.76, 426.00), Vector2(10125.44, 250.00), Vector2(14279.96, 250.00)],
		"features": [{"kind": "ash", "at": 4560.0, "length": 3400.0}, {"kind": "ash", "at": 11780.0, "length": 3800.0}],
	},
	{
		"id": &"4-3", "title": "Eruption", "intro": "New: volcanoes",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack", "lava_volcano"], "new": ["lava_volcano"],
		"density": 1.4, "margin": 1.05, "length": 20500.0,
		"seed": 4311,
		"stars": [Vector2(5372.43, 114.00), Vector2(10943.24, 74.00), Vector2(16407.16, 74.00)],
	},
	{
		"id": &"4-4", "title": "Tide of Fire", "intro": "New: rising lava pools",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack", "lava_volcano", "lava_tidal_pool"], "new": ["lava_tidal_pool"],
		"density": 1.5, "margin": 1.0, "length": 22000.0,
		"seed": 4415,
		"stars": [Vector2(5602.36, 114.00), Vector2(11811.91, 114.00), Vector2(18515.43, 114.00)],
	},
	{
		"id": &"4-5", "title": "Ember Storm", "intro": "Ember bombs rain down",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack", "lava_volcano", "lava_tidal_pool"], "new": [],
		"density": 1.6, "margin": 0.95, "length": 23500.0,
		"seed": 4515,
		"stars": [Vector2(5970.42, 426.00), Vector2(12583.10, 151.00), Vector2(18518.54, 151.00)],
		"features": [{"kind": "ember_bomb", "at": 13960.0, "side": "floor"}, {"kind": "ember_bomb", "at": 14910.0, "side": "ceiling"}, {"kind": "ember_bomb", "at": 17190.0, "side": "floor"}, {"kind": "ember_bomb", "at": 19240.0, "side": "ceiling"}],
		"new_features": ["ember_bomb"],
	},
	{
		"id": &"4-6", "title": "Volcano Exam", "intro": "Everything the volcano has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "lava_crack", "lava_volcano", "lava_tidal_pool"], "new": [],
		"density": 1.8, "margin": 0.85, "length": 25000.0,
		"seed": 4615,
		"stars": [Vector2(6235.64, 426.00), Vector2(13959.76, 74.00), Vector2(21040.71, 74.00)],
		"features": [{"kind": "ember_bomb", "at": 5210.0, "side": "ceiling"}, {"kind": "ash", "at": 12000.0, "length": 3000.0}, {"kind": "ember_bomb", "at": 18000.0, "side": "floor"}],
	},
]

## Frostfjället. Generated with the cave mix (icicles), drawn snowy by the
## frost palette: barrels roll as snowballs, spikes are ice shards. Avalanches
## and snowstorms are scripted features.
const FROST_STAGES := [
	{
		"id": &"5-1", "title": "Snowfield", "intro": "Snowballs roll down the mountain",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"barrel_chain": 2.0},
		"density": 1.4, "margin": 1.05, "length": 18000.0,
		"seed": 5114,
		"stars": [Vector2(4461.49, 426.00), Vector2(10362.66, 114.00), Vector2(14803.46, 114.00)],
	},
	{
		"id": &"5-2", "title": "Icicle Pass", "intro": "Ice hangs over every step",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"cave_icicle": 2.0, "falling_rock": 1.4},
		"density": 1.5, "margin": 1.0, "length": 19500.0,
		"seed": 5211,
		"stars": [Vector2(5103.48, 114.00), Vector2(10849.44, 114.00), Vector2(16026.53, 114.00)],
	},
	{
		"id": &"5-3", "title": "Avalanche", "intro": "The mountain lets go of its snow",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.55, "margin": 0.98, "length": 21000.0,
		"seed": 5307,
		"stars": [Vector2(5719.80, 89.50), Vector2(11335.80, 119.00), Vector2(18276.65, 466.00)],
		"features": [{"kind": "avalanche", "at": 6800.0, "count": 3}, {"kind": "avalanche", "at": 13980.0, "count": 3}, {"kind": "avalanche", "at": 16930.0, "count": 4}],
		"new_features": ["avalanche"],
	},
	{
		"id": &"5-4", "title": "Whiteout", "intro": "A snowstorm sweeps the slope",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.65, "margin": 0.94, "length": 22500.0,
		"seed": 5412,
		"stars": [Vector2(5564.23, 426.00), Vector2(12045.24, 178.00), Vector2(18319.57, 254.00)],
		"features": [{"kind": "snowstorm", "at": 5850.0, "length": 3400.0}, {"kind": "snowstorm", "at": 14400.0, "length": 3800.0}],
	},
	{
		"id": &"5-5", "title": "Frozen Steps", "intro": "Steep steps and sliding snow",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"terrain_step": 1.8, "terrain_slope": 1.8},
		"density": 1.75, "margin": 0.9, "length": 24000.0,
		"seed": 5514,
		"stars": [Vector2(6090.18, 114.00), Vector2(14268.56, 186.00), Vector2(19951.08, 146.00)],
		"features": [{"kind": "avalanche", "at": 13050.0, "count": 3}, {"kind": "avalanche", "at": 20320.0, "count": 4}],
	},
	{
		"id": &"5-6", "title": "Mountain Exam", "intro": "Everything the mountain has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.9, "margin": 0.84, "length": 25000.0,
		"seed": 5607,
		"stars": [Vector2(6624.24, 426.00), Vector2(13591.89, 186.00), Vector2(18565.70, 186.00)],
		"features": [{"kind": "avalanche", "at": 9530.0, "count": 3}, {"kind": "snowstorm", "at": 12500.0, "length": 3000.0}, {"kind": "avalanche", "at": 16890.0, "count": 3}],
	},
]

## Molnriket. Generated with the classic mix, drawn as cloud tops at sunset by
## the clouds palette. Lightning and wind gusts are scripted features.
const CLOUD_STAGES := [
	{
		"id": &"6-1", "title": "Cloud Walk", "intro": "Soft clouds, but the holes are real",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"weights": {"floor_gap": 1.6, "ceiling_gap": 1.6},
		"density": 1.55, "margin": 1.0, "length": 18000.0,
		"seed": 6107,
		"stars": [Vector2(4527.93, 426.00), Vector2(10322.80, 222.00), Vector2(16084.47, 426.00)],
	},
	{
		"id": &"6-2", "title": "Thunderhead", "intro": "The storm clouds wake up",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"density": 1.6, "margin": 0.97, "length": 19500.0,
		"seed": 6214,
		"stars": [Vector2(4790.70, 296.00), Vector2(10373.31, 114.00), Vector2(15966.27, 214.00)],
		"features": [{"kind": "lightning", "at": 8300.0, "side": "floor"}, {"kind": "lightning", "at": 11690.0, "side": "ceiling"}, {"kind": "lightning", "at": 16280.0, "side": "floor"}],
		"new_features": ["lightning"],
	},
	{
		"id": &"6-3", "title": "Sky Islands", "intro": "Hop between floating islands",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"weights": {"terrain_step": 1.7, "terrain_slope": 1.7},
		"density": 1.68, "margin": 0.94, "length": 21000.0,
		"seed": 6303,
		"stars": [Vector2(5121.64, 114.00), Vector2(11328.17, 74.00), Vector2(16648.58, 146.00)],
	},
	{
		"id": &"6-4", "title": "Wind Song", "intro": "Gusts whistle past the clouds",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"weights": {"barrel_chain": 1.6, "saw_blade": 1.5},
		"density": 1.75, "margin": 0.9, "length": 22500.0,
		"seed": 6405,
		"stars": [Vector2(5975.54, 114.00), Vector2(10705.61, 146.00), Vector2(19113.76, 296.00)],
		"features": [{"kind": "gust", "at": 5400.0, "length": 3400.0}, {"kind": "gust", "at": 13950.0, "length": 3800.0}],
	},
	{
		"id": &"6-5", "title": "Storm Front", "intro": "Lightning all along the front",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"density": 1.85, "margin": 0.86, "length": 24000.0,
		"seed": 6515,
		"stars": [Vector2(6559.01, 214.00), Vector2(11926.19, 254.00), Vector2(21547.00, 466.00)],
		"features": [{"kind": "lightning", "at": 3310.0, "side": "ceiling"}, {"kind": "lightning", "at": 9120.0, "side": "floor"}, {"kind": "gust", "at": 12480.0, "length": 2600.0}, {"kind": "lightning", "at": 20900.0, "side": "ceiling"}, {"kind": "lightning", "at": 22320.0, "side": "floor"}],
	},
	{
		"id": &"6-6", "title": "Sky Exam", "intro": "Everything the sky has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"density": 1.95, "margin": 0.82, "length": 25000.0,
		"seed": 6613,
		"stars": [Vector2(6195.02, 362.00), Vector2(13896.09, 74.00), Vector2(22414.40, 74.00)],
		"features": [{"kind": "lightning", "at": 5030.0, "side": "floor"}, {"kind": "gust", "at": 11500.0, "length": 3000.0}, {"kind": "lightning", "at": 19190.0, "side": "ceiling"}, {"kind": "lightning", "at": 21850.0, "side": "floor"}],
	},
]

## Stage tables per world: [world_id, generation biome, stages].
static func stage_tables() -> Array:
	return [[&"meadow", &"classic", MEADOW_STAGES], [&"cave", &"cave", CAVE_STAGES], [&"haunted", &"haunted", HAUNTED_STAGES], [&"volcano", &"lava", LAVA_STAGES], [&"frost", &"cave", FROST_STAGES], [&"clouds", &"classic", CLOUD_STAGES]]

static var _worlds: Array[CampaignWorld] = []

static func worlds() -> Array[CampaignWorld]:
	if _worlds.is_empty():
		_worlds = _build_worlds()
	return _worlds

static func get_world(world_id: StringName) -> CampaignWorld:
	for world in worlds():
		if world.world_id == world_id:
			return world
	return null

static func get_level(level_id: StringName) -> CampaignLevel:
	for world in worlds():
		var level := world.get_level(level_id)
		if level != null:
			return level
	return null

static func world_of(level: CampaignLevel) -> CampaignWorld:
	return get_world(level.world_id) if level != null else null

## The stage after this one in the same world, or null after the boss.
static func next_level(level: CampaignLevel) -> CampaignLevel:
	var world := world_of(level)
	if world == null:
		return null
	var index := world.levels.find(level)
	return world.levels[index + 1] if index >= 0 and index + 1 < world.levels.size() else null

static func _build_worlds() -> Array[CampaignWorld]:
	var result: Array[CampaignWorld] = []
	var meadow := _make_world(&"meadow", 1, "The Meadow", &"classic", "map_meadow", MEADOW_MAP_NODES, Color("42d6c5"))
	var index := 1
	for spec in MEADOW_STAGES:
		meadow.levels.append(_make_stage(&"meadow", &"classic", index, spec))
		index += 1
	meadow.levels.append(_make_boss(&"meadow", &"classic", index, &"1-B", "Rullaren", "Boss: the barrel machine", &"rullaren"))
	# The meadow is drawn with its own daylight look; encounters stay classic.
	for level in meadow.levels:
		level.presentation_biome = &"meadow"
	result.append(meadow)
	var cave := _make_world(&"cave", 2, "The Cave", &"cave", "map_cave", CAVE_MAP_NODES, Color("8fb4ff"))
	_add_stages(cave, CAVE_STAGES)
	cave.levels.append(_make_boss(&"cave", &"cave", cave.levels.size() + 1, &"2-B", "Stalactite Giant", "Boss: the giant bat", &"stalactite"))
	# The cave campaign look is presentation only; encounters use the cave mix.
	for level in cave.levels:
		level.presentation_biome = &"cave_campaign"
	result.append(cave)
	var haunted := _make_world(&"haunted", 3, "Haunted Woods", &"haunted", "map_haunted", HAUNTED_MAP_NODES, Color("b69cff"))
	_add_stages(haunted, HAUNTED_STAGES)
	haunted.levels.append(_make_boss(&"haunted", &"haunted", haunted.levels.size() + 1, &"3-B", "Ghost King", "Boss: the king who copies you", &"ghost_king"))
	# Presentation only; encounters use the haunted mix.
	for level in haunted.levels:
		level.presentation_biome = &"haunted_campaign"
	result.append(haunted)
	var volcano := _make_world(&"volcano", 4, "The Volcano", &"lava", "map_volcano", LAVA_MAP_NODES, Color("ff814f"))
	_add_stages(volcano, LAVA_STAGES)
	volcano.levels.append(_make_boss(&"volcano", &"lava", volcano.levels.size() + 1, &"4-B", "Magmaormen", "Boss: the magma worm", &"magma_worm"))
	# Presentation only; encounters use the lava mix.
	for level in volcano.levels:
		level.presentation_biome = &"volcano_campaign"
	result.append(volcano)
	var frost := _make_world(&"frost", 5, "Frost Mountain", &"cave", "map_frost", FROST_MAP_NODES, Color("9fe3ff"))
	_add_stages(frost, FROST_STAGES)
	if not frost.levels.is_empty():
		frost.levels.append(_make_boss(&"frost", &"cave", frost.levels.size() + 1, &"5-B", "Snow Giant", "Boss: the giant who throws snowballs", &"snow_giant"))
	# Presentation only; encounters use the cave mix.
	for level in frost.levels:
		level.presentation_biome = &"frost_campaign"
	result.append(frost)
	var clouds := _make_world(&"clouds", 6, "Cloud Realm", &"classic", "map_clouds", CLOUD_MAP_NODES, Color("ffb48a"))
	_add_stages(clouds, CLOUD_STAGES)
	if not clouds.levels.is_empty():
		clouds.levels.append(_make_boss(&"clouds", &"classic", clouds.levels.size() + 1, &"6-B", "Thunderbird", "Boss: the bird that rides the storm", &"thunderbird"))
	# Presentation only; encounters use the classic mix.
	for level in clouds.levels:
		level.presentation_biome = &"clouds_campaign"
	result.append(clouds)
	return result

## Adds a world's stages. A stage only joins once the level tool has frozen
## its stars, so a world can be filled in stage by stage.
static func _add_stages(world: CampaignWorld, specs: Array) -> void:
	var index := 1
	for spec in specs:
		if (spec.stars as Array).is_empty():
			continue
		world.levels.append(_make_stage(world.world_id, world.biome_id, index, spec))
		index += 1

static func _make_world(world_id: StringName, number: int, title: String, biome_id: StringName, map_name: String, nodes: Array, accent: Color) -> CampaignWorld:
	var world := CampaignWorld.new()
	world.world_id = world_id
	world.number = number
	world.title = title
	world.biome_id = biome_id
	var map_path := "res://assets/campaign/%s.png" % map_name
	if ResourceLoader.exists(map_path):
		world.map_texture = load(map_path)
	world.map_nodes = PackedVector2Array(nodes)
	world.accent = accent
	return world

## Hazards a stage introduces show up more often there, so the stage is
## actually about them (barrel chains attach to blocks/spikes and keep their
## own rate).
const NEW_HAZARD_WEIGHT := 2.5

static func stage_weights(spec: Dictionary) -> Dictionary:
	var weights: Dictionary = {}
	for hazard in spec.get("new", []):
		if hazard != "barrel_chain":
			weights[hazard] = NEW_HAZARD_WEIGHT
	var extra: Dictionary = spec.get("weights", {})
	for hazard in extra:
		weights[hazard] = float(weights.get(hazard, 1.0)) * float(extra[hazard])
	return weights

static func make_ruleset(stage_id: StringName, biome_id: StringName, profiles: Array, density: float, margin: float, weights: Dictionary = {}) -> Resource:
	var ruleset := RulesetScript.new() as Resource
	ruleset.set("ruleset_id", StringName("campaign_%s" % String(stage_id).replace("-", "_")))
	ruleset.set("revision", 1)
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray(profiles))
	ruleset.set("event_density", density)
	ruleset.set("reaction_margin", margin)
	ruleset.set("coin_revision", CAMPAIGN_COIN_REVISION)
	ruleset.set("locked_biome", biome_id)
	ruleset.set("profile_weight_multipliers", weights.duplicate())
	return ruleset

static func _make_stage(world_id: StringName, biome_id: StringName, index: int, spec: Dictionary) -> CampaignLevel:
	var level := CampaignLevel.new()
	level.level_id = spec.id
	level.world_id = world_id
	level.index_in_world = index
	level.title = spec.title
	level.intro = spec.intro
	level.seed_value = int(spec.seed)
	level.generator_version = CAMPAIGN_GENERATOR_VERSION
	level.ruleset = make_ruleset(spec.id, biome_id, spec.profiles, float(spec.density), float(spec.margin), stage_weights(spec))
	level.length_px = float(spec.length)
	level.stars = PackedVector2Array(spec.stars)
	level.new_hazards = PackedStringArray(spec.new)
	level.new_features = PackedStringArray(spec.get("new_features", []))
	level.features.assign(spec.get("features", []))
	return level

static func _make_boss(world_id: StringName, biome_id: StringName, index: int, level_id: StringName, title: String, intro: String, boss_id: StringName) -> CampaignLevel:
	var level := CampaignLevel.new()
	level.level_id = level_id
	level.world_id = world_id
	level.index_in_world = index
	level.title = title
	level.intro = intro
	level.seed_value = 1
	level.generator_version = CAMPAIGN_GENERATOR_VERSION
	# A boss stage spawns only scripted attacks; the ruleset still pins the
	# biome and gives the stage a valid run identity.
	level.ruleset = make_ruleset(level_id, biome_id, ["block"], 0.5, 1.0)
	level.length_px = 0.0
	level.boss_id = boss_id
	return level
