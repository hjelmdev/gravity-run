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
## Lengths grow from 90 s to 120 s at the base 500 px/s.
const MEADOW_STAGES := [
	{
		"id": &"1-1", "title": "First Steps", "intro": "New: spikes and blocks",
		"profiles": ["spike_group", "block"], "new": ["spike_group", "block"],
		"density": 0.7, "margin": 1.5, "length": 45000.0,
		"seed": 1101,
		"stars": [Vector2(11816.34, 426.00), Vector2(23943.43, 114.00), Vector2(36422.73, 114.00)],
	},
	{
		"id": &"1-2", "title": "Mind the Gap", "intro": "New: holes in the floor and ceiling",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap"], "new": ["floor_gap", "ceiling_gap"],
		"density": 0.8, "margin": 1.35, "length": 48000.0,
		"seed": 1217,
		"stars": [Vector2(12379.74, 426.00), Vector2(25808.38, 114.00), Vector2(35180.72, 114.00)],
	},
	{
		"id": &"1-3", "title": "Rolling Barrels", "intro": "New: rolling barrels",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain"], "new": ["barrel_chain"],
		"density": 0.9, "margin": 1.25, "length": 51000.0,
		"seed": 1305,
		"stars": [Vector2(12894.01, 114.00), Vector2(26901.53, 114.00), Vector2(41992.90, 426.00)],
	},
	{
		"id": &"1-4", "title": "Ups and Downs", "intro": "New: steps and slopes",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope"], "new": ["terrain_step", "terrain_slope"],
		"density": 1.0, "margin": 1.15, "length": 54000.0,
		"seed": 1413,
		"stars": [Vector2(13680.25, 466.00), Vector2(29253.45, 106.00), Vector2(41230.62, 341.00)],
	},
	{
		"id": &"1-5", "title": "Falling Rocks", "intro": "New: falling rocks and saw blades",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": ["falling_rock", "saw_blade"],
		"density": 1.1, "margin": 1.05, "length": 57000.0,
		"seed": 1510,
		"stars": [Vector2(14557.17, 79.67), Vector2(30225.40, 119.00), Vector2(44709.36, 254.00)],
	},
	{
		"id": &"1-6", "title": "Meadow Exam", "intro": "Everything the meadow has taught you",
		"profiles": ["spike_group", "block", "floor_gap", "ceiling_gap", "barrel_chain", "terrain_step", "terrain_slope", "falling_rock", "saw_blade"], "new": [],
		"density": 1.25, "margin": 1.0, "length": 60000.0,
		"seed": 1602,
		"stars": [Vector2(14988.49, 154.00), Vector2(32063.18, 254.00), Vector2(45359.16, 118.00)],
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

static func make_ruleset(stage_id: StringName, biome_id: StringName, profiles: Array, density: float, margin: float) -> Resource:
	var ruleset := RulesetScript.new() as Resource
	ruleset.set("ruleset_id", StringName("campaign_%s" % String(stage_id).replace("-", "_")))
	ruleset.set("revision", 1)
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray(profiles))
	ruleset.set("event_density", density)
	ruleset.set("reaction_margin", margin)
	ruleset.set("coin_revision", CAMPAIGN_COIN_REVISION)
	ruleset.set("locked_biome", biome_id)
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
	level.ruleset = make_ruleset(spec.id, biome_id, spec.profiles, float(spec.density), float(spec.margin))
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
