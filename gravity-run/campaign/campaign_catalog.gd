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
	# Later worlds are on the map already; their stages arrive in later phases.
	result.append(_make_world(&"cave", 2, "The Cave", &"cave", "map_cave", CAVE_MAP_NODES, Color("8fb4ff")))
	result.append(_make_world(&"haunted", 3, "Haunted Woods", &"haunted", "map_haunted", HAUNTED_MAP_NODES, Color("b69cff")))
	result.append(_make_world(&"volcano", 4, "The Volcano", &"lava", "map_volcano", LAVA_MAP_NODES, Color("ff814f")))
	return result

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
