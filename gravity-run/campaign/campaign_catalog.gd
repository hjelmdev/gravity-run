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
	},
	{
		"id": &"2-3", "title": "Mine Run", "intro": "Mine carts roll through the tunnels",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"barrel_chain": 2.0},
		"density": 1.3, "margin": 1.15, "length": 19500.0,
		"seed": 2377,
		"stars": [Vector2(5403.52, 114.00), Vector2(10652.77, 114.00), Vector2(14306.41, 296.00)],
	},
	{
		"id": &"2-4", "title": "Cave-in", "intro": "Rocks and icicles fall together",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"weights": {"falling_rock": 1.6, "cave_icicle": 1.6},
		"density": 1.4, "margin": 1.1, "length": 21000.0,
		"seed": 2463,
		"stars": [Vector2(5487.91, 114.00), Vector2(11542.10, 222.00), Vector2(15658.60, 150.00)],
	},
	{
		"id": &"2-5", "title": "Crystal Hall", "intro": "A dark hall lit by crystals",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.45, "margin": 1.05, "length": 22500.0,
		"seed": 2507,
		"stars": [Vector2(5559.09, 114.00), Vector2(12068.22, 254.00), Vector2(18011.33, 106.00)],
	},
	{
		"id": &"2-6", "title": "Cave Exam", "intro": "Everything the cave has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "cave_icicle"], "new": [],
		"density": 1.5, "margin": 1.0, "length": 24000.0,
		"seed": 2601,
		"stars": [Vector2(6048.69, 426.00), Vector2(12638.04, 114.00), Vector2(18938.52, 426.00)],
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
	},
	{
		"id": &"3-4", "title": "The Fog", "intro": "Fog hides the way ahead",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.4, "margin": 1.05, "length": 21000.0,
		"seed": 3458,
		"stars": [Vector2(5581.50, 114.00), Vector2(11978.54, 222.00), Vector2(16104.22, 222.00)],
	},
	{
		"id": &"3-5", "title": "Will-o'-the-Wisp", "intro": "A wisp copies your side",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.5, "margin": 1.0, "length": 22500.0,
		"seed": 3575,
		"stars": [Vector2(7339.76, 114.00), Vector2(12027.32, 114.00), Vector2(17186.89, 222.00)],
	},
	{
		"id": &"3-6", "title": "Forest Exam", "intro": "Everything the forest has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade", "haunted_ghost", "haunted_chaser"], "new": [],
		"density": 1.6, "margin": 0.95, "length": 25000.0,
		"seed": 3640,
		"stars": [Vector2(6454.64, 426.00), Vector2(13416.85, 254.00), Vector2(20476.66, 426.00)],
	},
]

## Stage tables per world: [world_id, generation biome, stages].
static func stage_tables() -> Array:
	return [[&"meadow", &"classic", MEADOW_STAGES], [&"cave", &"cave", CAVE_STAGES], [&"haunted", &"haunted", HAUNTED_STAGES]]

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
	result.append(haunted)
	# Later worlds are on the map already; their stages arrive in later phases.
	result.append(_make_world(&"volcano", 4, "The Volcano", &"lava", "map_volcano", LAVA_MAP_NODES, Color("ff814f")))
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
