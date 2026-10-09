extends Node
## Campaign checks against the real singleplayer scene (main.tscn):
##  - every catalog stage validates, generates and has three stars on safe,
##    reachable coin positions inside the course;
##  - a short synthetic stage runs to the finish line, collects its stars and
##    records the result; the biome stays locked during the run;
##  - stage 1-1 without input ends in a failed attempt that is recorded;
##  - Rullaren can be beaten by a bot that follows its schedule, also after a
##    deliberately missed plate;
##  - unlock rules follow completions.
## Physics is stepped by calling main._physics_process directly (60 Hz).

const MainScene := preload("res://main.tscn")
const Gen := preload("res://systems/course_generator.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const CampaignRunScript := preload("res://campaign/campaign_run.gd")
const LevelTool := preload("res://tools/campaign/campaign_level_tool.gd")
const TICK := 1.0 / 60.0

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _run() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	_check_catalog()
	_check_features_frozen()
	_check_feature_channel()
	_check_bat_sweep()
	await _check_darkness_lights()
	await _check_mine_carts()
	await _check_feature_stage("cave_in", "floor", false)
	await _check_feature_stage("cave_in", "floor", true)
	await _check_feature_stage("bat_swarm", "floor", false)
	await _check_feature_stage("bat_swarm", "floor", true)
	await _check_feature_stage("bat_swarm", "ceiling", false)
	await _check_feature_stage("bat_swarm", "ceiling", true)
	await _check_feature_stage("ghost_hand", "floor", false)
	await _check_feature_stage("ghost_hand", "floor", true)
	await _check_feature_stage("ghost_hand", "ceiling", false)
	await _check_feature_stage("ghost_hand", "ceiling", true)
	await _check_feature_stage("ember_bomb", "floor", false)
	await _check_feature_stage("ember_bomb", "floor", true)
	await _check_feature_stage("ember_bomb", "ceiling", false)
	await _check_feature_stage("ember_bomb", "ceiling", true)
	_check_ash()
	await _check_biome_keys()
	await _check_personal_best_ghost()
	await _check_near_miss()
	_check_hand_sweep()
	await _check_fog_lights()
	await _check_wisp(true)
	await _check_wisp(false)
	await _check_grave_skins()
	await _check_synthetic_stage()
	await _check_failed_attempt()
	await _check_boss(false)
	await _check_boss(true)
	await _check_boss(false, &"4-B")
	await _check_boss(true, &"4-B")
	await _check_stalactite("hit")
	await _check_stalactite("early")
	await _check_stalactite("stay")
	await _check_ghost_king("hit")
	await _check_ghost_king("early")
	_check_unlocks()
	BiomeRendererScript.set_locked_biome(&"")
	print("CAMPAIGN_RUNTIME_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_catalog() -> void:
	var worlds := CampaignCatalog.worlds()
	_check(worlds.size() >= 4 and worlds[0].levels.size() == 7, "catalog has four worlds and the meadow has six stages plus a boss")
	var generator := Gen.new()
	var profiles := generator.get_profile_catalog(CampaignCatalog.CAMPAIGN_GENERATOR_VERSION)
	_check(CampaignCatalog.get_world(&"cave").levels.size() >= 6 and CampaignCatalog.get_world(&"haunted").levels.size() >= 6, "the cave and the haunted woods have six stages each")
	var identities: Dictionary = {}
	var all_levels: Array[CampaignLevel] = []
	for world in worlds:
		all_levels.append_array(world.levels)
	for level in all_levels:
		_check(str(level.ruleset.call("validate", profiles)).is_empty(), "%s ruleset validates" % level.level_id)
		identities[level.get_identity()] = true
		if level.is_boss():
			continue
		_check(level.stars.size() == 3, "%s has three gravity stars" % level.level_id)
		_check(level.length_px >= 15000.0 and level.length_px <= 25000.0, "%s is 30-50 s long" % level.level_id)
		BiomeRendererScript.set_locked_biome(level.get_locked_biome())
		var gen := Gen.new()
		_check(gen.configure_run_definition(level.create_run_definition()), "%s configures the generator" % level.level_id)
		gen.ensure_horizon(level.length_px + 6000.0, 500.0, 900.0, Gen.EVENT_SPAWN_LEAD_DISTANCE)
		var planned: Array[Dictionary] = gen.get_planned_events()
		var foreign := _foreign_encounters(level.world_id)
		var biome_ok := true
		for event in planned:
			if str(event.get("kind", "")) in foreign or str(event.get("id", "")) in foreign:
				biome_ok = false
		_check(biome_ok, "%s only generates %s encounters" % [level.level_id, level.world_id])
		for hazard in level.new_hazards:
			var introduced := false
			for event in planned:
				if str(event.get("id", "")) == hazard and float(event.get("course_distance", INF)) <= level.get_hazard_cutoff_distance():
					introduced = true
			_check(introduced, "%s shows its new hazard %s" % [level.level_id, hazard])
		var builder := Builder.new()
		var resolved: Array[Dictionary] = builder.resolve_runtime_events(planned, ceili(level.length_px + 4500.0), level.generator_version, BiomeRendererScript.start_biome_offset_for_seed(level.seed_value, level.generator_version))
		var safe := true
		var inside := true
		for star in level.stars:
			if CoinPlanner._position_blocked(star.x, star.y, resolved):
				safe = false
			if star.x < 180.0 + 2000.0 or star.x > 180.0 + level.get_hazard_cutoff_distance():
				inside = false
		_check(safe, "%s stars are clear of hazards" % level.level_id)
		var conflicts := LevelTool.gap_conflicts(resolved, 180.0 + level.get_hazard_cutoff_distance())
		_check(conflicts == 0, "%s never has holes in floor and ceiling at once (%d)" % [level.level_id, conflicts])
		_check(inside, "%s stars are inside the course" % level.level_id)
		# Stars are frozen from the stage's own coin plan; they must still be there.
		var coins: Array[Dictionary] = CoinPlanner.plan(level.seed_value, 180.0, 180.0 + level.get_hazard_cutoff_distance(), resolved, 460.0, 80.0, int(level.ruleset.get("coin_revision")), float(level.ruleset.get("coin_density")))
		var on_coin := true
		for star in level.stars:
			var found := false
			for coin in coins:
				if Vector2(float(coin.world_x), float(coin.world_y)).distance_to(star) < 1.0:
					found = true
					break
			on_coin = on_coin and found
		_check(on_coin, "%s stars sit on the stage's planned coin positions" % level.level_id)
		print("STAGE %s seed=%d events=%d" % [level.level_id, level.seed_value, planned.size()])
	_check(identities.size() == all_levels.size(), "stage identities are unique")
	BiomeRendererScript.set_locked_biome(&"")

## Encounter kinds or ids that belong to other biomes than the world's own.
static func _foreign_encounters(world_id: StringName) -> Array:
	match world_id:
		&"cave":
			return ["ghost", "lava_crack", "volcano", "haunted_ghost", "haunted_chaser", "lava_tidal_pool"]
		&"haunted":
			return ["lava_crack", "volcano", "cave_icicle", "lava_tidal_pool"]
		&"volcano":
			return ["ghost", "haunted_ghost", "haunted_chaser", "cave_icicle"]
	return ["ghost", "lava_crack", "volcano", "cave_icicle"]

## Frozen feature positions per cave stage: [kind, at]. A change here is a
## change to the stage, so it has to be deliberate.
const FROZEN_FEATURES := {
	"2-1": [],
	"2-2": [["bat_swarm", 2960.0], ["bat_swarm", 6630.0], ["bat_swarm", 13120.0]],
	"2-3": [["bat_swarm", 4150.0], ["bat_swarm", 6990.0]],
	"2-4": [["cave_in", 9630.0], ["cave_in", 13880.0], ["cave_in", 17350.0]],
	"2-5": [["darkness", 5400.0], ["darkness", 13950.0]],
	"2-6": [["darkness", 13920.0], ["cave_in", 22010.0]],
	"3-1": [],
	"3-2": [],
	"3-3": [["ghost_hand", 6390.0], ["ghost_hand", 8430.0], ["ghost_hand", 13220.0], ["ghost_hand", 14960.0]],
	"3-4": [["fog", 6300.0], ["fog", 8760.0]],
	"3-5": [["wisp", 4950.0], ["wisp", 11250.0], ["wisp", 17550.0]],
	"3-6": [["ghost_hand", 8230.0], ["fog", 11390.0], ["ghost_hand", 18110.0]],
	"4-1": [],
	"4-2": [["ash", 4560.0], ["ash", 11780.0]],
	"4-3": [],
	"4-4": [],
	"4-5": [["ember_bomb", 13960.0], ["ember_bomb", 14910.0], ["ember_bomb", 17190.0], ["ember_bomb", 19240.0]],
	"4-6": [["ember_bomb", 5210.0], ["ash", 12000.0], ["ember_bomb", 18000.0]],
}

func _check_features_frozen() -> void:
	for spec in CampaignCatalog.CAVE_STAGES + CampaignCatalog.HAUNTED_STAGES + CampaignCatalog.LAVA_STAGES:
		var level := CampaignCatalog.get_level(spec.id)
		var frozen: Array = FROZEN_FEATURES.get(str(spec.id), [])
		var actual: Array = []
		for feature in level.features:
			actual.append([str(feature.kind), float(feature.at)])
		_check(actual == frozen, "%s features are frozen at %s" % [spec.id, str(frozen)])
		if level.features.is_empty():
			continue
		var course := LevelTool.plan_level(level)
		var clean := true
		for feature in level.features:
			var problems := CampaignFeatures.conflicts(feature, course.planned, level.stars, level.length_px, course.surface)
			if not problems.is_empty():
				clean = false
				print("  ", spec.id, " ", feature.kind, "@", feature.at, " ", problems)
		_check(clean, "%s features sit in quiet windows clear of generated events, holes, steps, slopes and stars" % spec.id)
		_check(CampaignFeatures.overlaps(level.features).is_empty(), "%s features do not crowd each other" % spec.id)
		# The channel must hand main every event of the stage's features.
		var expected := 0
		for feature in level.features:
			expected += CampaignFeatures.events_of(feature).size()
		var run := CampaignRunScript.new()
		run.setup(level)
		var popped := run.pop_feature_events(1.0e9, 1.0e9)
		_check(popped.size() == expected, "%s pops all %d feature events (%d)" % [spec.id, expected, popped.size()])
		run.free()
	BiomeRendererScript.set_locked_biome(&"")
	_check(CampaignCatalog.get_level(&"2-2").new_features.has("bat_swarm") and CampaignCatalog.get_level(&"2-4").new_features.has("cave_in") and CampaignCatalog.get_level(&"3-3").new_features.has("ghost_hand"), "2-2 introduces the bat swarm, 2-4 the cave-in and 3-3 the ghost hands")
	_check(CampaignRunScript.hazard_display_name("ghost_hand") == "ghost hands" and not CampaignRunScript.hazard_tip("ghost_hand").is_empty(), "the ghost hand has a name and a tip")
	_check(CampaignRunScript.hazard_display_name("bat_swarm") == "bat swarm" and not CampaignRunScript.hazard_tip("cave_in").is_empty() and not CampaignRunScript.hazard_tip("bat_swarm").is_empty(), "the new hazards have a name and a tip")
	_check(CampaignCatalog.get_level(&"4-5").new_features.has("ember_bomb") and CampaignRunScript.hazard_display_name("ember_bomb") == "ember bombs" and not CampaignRunScript.hazard_tip("ember_bomb").is_empty(), "4-5 introduces the ember bombs, with a name and a tip")
	TranslationServer.set_locale("sv")
	_check(tr(CampaignRunScript.hazard_tip("bat_swarm")) != CampaignRunScript.hazard_tip("bat_swarm") and tr("cave-in") == "ras" and tr("bat swarm") == "fladdermussvärm" and tr("ghost hands") == "spökhänder" and tr("Wisp caught") == "Irrbloss fångat" and tr("ember bombs") == "glödbomber", "the new hazard callouts are translated to Swedish")
	TranslationServer.set_locale("en")

## The channel pops events by spawn line or early lead and announces new kinds.
func _check_feature_channel() -> void:
	var level := CampaignCatalog.get_level(&"2-4")
	var run := CampaignRunScript.new()
	run.setup(level)
	var first_at := float(level.features[0].at)
	_check(run.pop_feature_events(0.0, 1000.0).is_empty(), "no feature event pops before its time")
	var early := run.pop_feature_events(first_at - 1500.0, first_at - 1500.0 + 1000.0)
	_check(early.size() == 1 and str(early[0].kind) == "rock" and float(early[0].course_distance) == first_at, "a cave-in's rocks pop early (before the spawn line) so they can wake up (%d)" % early.size())
	early.append_array(run.pop_feature_events(first_at - 1100.0, first_at - 1100.0 + 1000.0))
	_check(early.size() == 3 and run.pop_feature_events(first_at - 1100.0, first_at - 1100.0 + 1000.0).is_empty(), "feature events pop once each")
	var announced: Array[String] = []
	run.callout.connect(func(kind: String, _heading: String, title: String, _description: String) -> void:
		if kind == "hazard":
			announced.append(title))
	run.on_event_spawned(early[0])
	run.on_event_spawned(early[1])
	_check(announced.size() == 1 and announced[0] == "Cave-in", "the first cave-in rock shows the New hazard callout once (%s)" % str(announced))
	run.free()

## The swarm moves while the runner moves: the 60 Hz sweep must see a touch
## that happens only because the swarm slid into the runner.
func _check_bat_sweep() -> void:
	var swarm := BatSwarm.new()
	add_child(swarm)
	swarm.configure_swarm(CampaignFeatures.events_of({"kind": "bat_swarm", "at": 1000.0, "side": "floor"})[0], 1180.0, 460.0)
	swarm.phase = "flying"
	var rect := swarm.get_hitbox_rect()
	var runner_size := Vector2(34.0, 44.0)
	# Runner standing just left of the swarm, the swarm slides 6 px into it.
	var start := Rect2(Vector2(rect.position.x - runner_size.x - 3.0, 416.0), runner_size)
	swarm.advance_motion(1.0 / 60.0, 10.0, Vector2(start.position.x, 438.0), Callable(), Callable())
	var moved := swarm.get_hitbox_rect()
	_check(absf((rect.position.x - moved.position.x) - 6.0) < 0.001, "the swarm slides 0.6x the runner's movement")
	var fraction := swarm.swept_contact_fraction(start, start)
	_check(fraction > 0.4 and fraction < 0.6, "a swarm sliding into a standing runner is caught by the sweep (%.2f)" % fraction)
	var clear := Rect2(Vector2(rect.position.x - runner_size.x - 20.0, 416.0), runner_size)
	_check(swarm.swept_contact_fraction(clear, clear) < 0.0, "a runner clear of the swarm's path is not hit")
	var other_lane := Rect2(Vector2(rect.position.x, 80.0), runner_size)
	_check(swarm.swept_contact_fraction(other_lane, other_lane) < 0.0, "a runner on the other surface is not hit")
	swarm.free()

func _check_darkness_lights() -> void:
	var level := CampaignCatalog.get_level(&"2-5")
	_check(CaveDarkness.FORWARD_VISIBLE >= 250.0, "the dark section always shows at least 250 px ahead of the runner")
	var run := CampaignRunScript.new()
	add_child(run)
	run.setup(level)
	_check(run.has_darkness(), "2-5 has a dark hall")
	var section: Vector2 = run._darkness.sections[0]
	_check(CaveDarkness.strength_for(section.x - 800.0, run._darkness.sections) == 0.0 and CaveDarkness.strength_for((section.x + section.y) * 0.5, run._darkness.sections) == 1.0, "the dark section fades in and out of full darkness")
	var runner_x := 180.0 + section.x + 1000.0
	var hazards: Array[Node2D] = []
	for offset in [140.0, 260.0, 430.0, 700.0]:
		var node := Node2D.new()
		node.position = Vector2(runner_x + offset, 400.0)
		add_child(node)
		hazards.append(node)
	var surface := func(_x: float, ceiling: bool) -> float: return 80.0 if ceiling else 460.0
	run.update_darkness(runner_x - 180.0, 960.0, Vector2(runner_x, 438.0), hazards, surface)
	var material: ShaderMaterial = run._darkness.material
	var lights: PackedVector4Array = material.get_shader_parameter("lights")
	var count := int(material.get_shader_parameter("light_count"))
	var all_lit := true
	for node in hazards:
		var covered := false
		for index in range(count):
			var light := lights[index]
			if Vector2(light.x, light.y).distance_to(node.position) <= light.z * 0.4:
				covered = true
		var inside_window := node.position.x - runner_x <= CaveDarkness.FORWARD_VISIBLE
		all_lit = all_lit and (covered or inside_window)
	_check(all_lit and count >= 3, "every hazard ahead of the runner is lit inside the dark hall (%d lights)" % count)
	for node in hazards:
		node.free()
	run.free()

func _check_hand_sweep() -> void:
	var hand := GhostHand.new()
	add_child(hand)
	hand.configure_hand(CampaignFeatures.events_of({"kind": "ghost_hand", "at": 1000.0, "side": "floor"})[0], 1180.0, 460.0)
	_check(hand.get_hitbox_rect().size == Vector2.ZERO and hand.get_phase() == "dormant", "a ghost hand starts out of sight with no hitbox")
	hand.advance_motion(1.0 / 60.0, 8.0, Vector2(1180.0 + GhostHand.GLOW_START + 40.0, 438.0), Callable(), Callable())
	_check(hand.get_phase() == "glow" and hand.get_hitbox_rect().size == Vector2.ZERO, "the lane glows before the hand reaches out")
	var emerged := [0]
	hand.emerged.connect(func(_h: GhostHand) -> void: emerged[0] += 1)
	hand.advance_motion(1.0 / 60.0, 8.0, Vector2(1180.0 + GhostHand.EMERGE - 4.0, 438.0), Callable(), Callable())
	hand.advance_motion(1.0 / 60.0, 8.0, Vector2(1180.0 + GhostHand.EMERGE + 16.0, 438.0), Callable(), Callable())
	hand.advance_motion(1.0 / 60.0, 8.0, Vector2(1180.0 + GhostHand.EMERGE + 24.0, 438.0), Callable(), Callable())
	_check(emerged[0] == 1 and hand.get_hitbox_rect().size.y > 0.0, "the hand emerges once and gets a hitbox")
	# A hand rising into a standing runner is caught by the sweep.
	var runner := Rect2(Vector2(1180.0 - 3.0, 416.0), Vector2(34.0, 44.0))
	_check(hand.swept_contact_fraction(runner, runner) >= 0.0, "a rising hand is caught by the 60 Hz sweep")
	_check(hand.swept_contact_fraction(Rect2(Vector2(1177.0, 80.0), Vector2(34.0, 44.0)), Rect2(Vector2(1177.0, 80.0), Vector2(34.0, 44.0))) < 0.0, "a runner on the other surface is not hit by the hand")
	hand.advance_motion(1.0 / 60.0, 8.0, Vector2(1180.0 + GhostHand.GONE + 10.0, 438.0), Callable(), Callable())
	_check(hand.get_hitbox_rect().size == Vector2.ZERO, "the hand is gone after the runner has passed")
	hand.free()

func _check_fog_lights() -> void:
	var level := CampaignCatalog.get_level(&"3-4")
	_check(ForestFog.FORWARD_CLEAR >= 300.0, "fog never covers the 300 px ahead of the runner")
	var run := CampaignRunScript.new()
	add_child(run)
	run.setup(level)
	_check(run.has_darkness() and is_instance_valid(run._fog), "3-4 has fog banks")
	var section: Vector2 = run._fog.sections[0]
	_check(ForestFog.strength_for(section.x - 800.0, run._fog.sections) == 0.0 and ForestFog.strength_for((section.x + section.y) * 0.5, run._fog.sections) == 1.0, "the fog fades in and out")
	var runner_x := 180.0 + section.x + 1000.0
	var hazards: Array[Node2D] = []
	for offset in [140.0, 260.0, 430.0, 700.0]:
		var node := Node2D.new()
		node.position = Vector2(runner_x + offset, 400.0)
		add_child(node)
		hazards.append(node)
	var surface := func(_x: float, ceiling: bool) -> float: return 80.0 if ceiling else 460.0
	run.update_darkness(runner_x - 180.0, 960.0, Vector2(runner_x, 438.0), hazards, surface)
	var material: ShaderMaterial = run._fog.material
	var lights: PackedVector4Array = material.get_shader_parameter("lights")
	var count := int(material.get_shader_parameter("light_count"))
	var all_clear := true
	for node in hazards:
		var covered := false
		for index in range(count):
			var light := lights[index]
			if Vector2(light.x, light.y).distance_to(node.position) <= light.z * 0.5:
				covered = true
		all_clear = all_clear and (covered or node.position.x - runner_x <= ForestFog.FORWARD_CLEAR)
	_check(all_clear and count >= 3, "every hazard ahead of the runner is held clear of the fog (%d lights)" % count)
	for node in hazards:
		node.free()
	run.free()

## A wisp copies the runner's lane 0.8 s late. A runner that keeps its lane
## catches it (3 coins), one that flips late misses it.
func _check_wisp(keep_lane: bool) -> void:
	var feature := {"kind": "wisp", "at": 3000.0, "length": 1500.0}
	var level := CampaignLevel.new()
	level.level_id = &"T-W"
	level.world_id = &"test"
	level.title = "Wisp test"
	level.seed_value = 4244
	level.generator_version = CampaignCatalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = CampaignCatalog.make_ruleset(&"T-W", &"haunted", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 7000.0
	level.features.append(feature)
	Campaign.reset_progress()
	Campaign.start_level(level)
	var game: Node = await _make_game()
	var run: Node = game.get("_campaign_run")
	run.set("generated_events_enabled", false)
	var bonus := [0]
	run.connect("bonus_coins", func(amount: int) -> void: bonus[0] += amount)
	var bot := func(g: Node) -> void:
		var player: Node = g.get_node("Player")
		var course := float(player.get("world_x")) - 180.0
		# Late flip: well after the wisp started copying the floor lane, just
		# before it drifts through the runner's place.
		if not keep_lane and course >= 3000.0 + 1180.0 and int(player.call("get_gravity_direction")) > 0 and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
			player.call("_try_flip", -1)
	var ticks := _step(game, 3000, bot)
	if keep_lane:
		_check(bonus[0] == CampaignFeatures.WISP_BONUS_COINS, "a runner that keeps its lane catches the wisp for 3 coins (%d)" % bonus[0])
	else:
		_check(bonus[0] == 0, "a runner that flips late misses the wisp, which copied its old lane (%d)" % bonus[0])
	_check(Campaign.is_completed(level), "the wisp is harmless: the stage is completed (%d ticks)" % ticks)
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

func _check_grave_skins() -> void:
	Campaign.start_level(CampaignCatalog.get_level(&"3-3"))
	var haunted: Node = await _make_game()
	haunted.call("_spawn_obstacle_scene", preload("res://hazards/block.tscn"), 56.0, 90.0, false, 900.0)
	haunted.call("_spawn_obstacle_scene", preload("res://hazards/spikes.tscn"), 28.0, 32.0, false, 1000.0)
	haunted.call("_spawn_obstacle_scene", preload("res://hazards/barrel.tscn"), 54.0, 54.0, false, 1100.0)
	var found: Array[String] = []
	for obstacle in haunted.get("obstacles"):
		found.append(str(obstacle.get("skin")))
	_check(found == ["grave", "grave", ""], "blocks and spikes are gravestones on haunted stages, barrels stay barrels (%s)" % str(found))
	haunted.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()
	Campaign.start_level(CampaignCatalog.get_level(&"2-3"))
	var cave: Node = await _make_game()
	cave.call("_spawn_obstacle_scene", preload("res://hazards/block.tscn"), 56.0, 90.0, false, 900.0)
	cave.call("_spawn_obstacle_scene", preload("res://hazards/spikes.tscn"), 28.0, 32.0, false, 1000.0)
	var plain: Array[String] = []
	for obstacle in cave.get("obstacles"):
		plain.append(str(obstacle.get("skin")))
	_check(plain == ["", ""], "blocks and spikes keep their look on cave stages (%s)" % str(plain))
	cave.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

func _check_mine_carts() -> void:
	var cave_game: Node = null
	Campaign.start_level(CampaignCatalog.get_level(&"2-3"))
	cave_game = await _make_game()
	cave_game.call("_spawn_obstacle_scene", preload("res://hazards/barrel.tscn"), 54.0, 54.0, false, 900.0)
	var cart: Node2D = (cave_game.get("obstacles") as Array).back()
	_check(str(cart.get("skin")) == "mine_cart", "barrels on a cave stage are mine carts")
	_check(cart.is_in_group("barrels") and Vector2(cart.get("size")) == Vector2(54.0, 54.0), "the mine cart is still a barrel for collision")
	cave_game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()
	Campaign.start_level(CampaignCatalog.get_level(&"1-3"))
	var meadow_game: Node = await _make_game()
	meadow_game.call("_spawn_obstacle_scene", preload("res://hazards/barrel.tscn"), 54.0, 54.0, false, 900.0)
	var barrel: Node2D = (meadow_game.get("obstacles") as Array).back()
	_check(str(barrel.get("skin")) == "meadow", "barrels on a meadow stage are pixel-art barrels")
	meadow_game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()
	var endless: Node = await _make_game()
	endless.call("_spawn_obstacle_scene", preload("res://hazards/barrel.tscn"), 54.0, 54.0, false, 900.0)
	var plain: Node2D = (endless.get("obstacles") as Array).back()
	_check(str(plain.get("skin")).is_empty(), "endless barrels stay barrels")
	endless.queue_free()
	await get_tree().process_frame

## A short stage with one hazardous feature and no generated events. A runner
## in the wrong lane dies at the feature; one that follows the feature's safe
## side reaches the flag. `follow` picks which runner this is.
func _check_feature_stage(kind: String, side: String, follow: bool) -> void:
	var feature := {"kind": kind, "at": 3600.0}
	var has_side := kind in ["bat_swarm", "ghost_hand", "ember_bomb"]
	if has_side:
		feature["side"] = side
	var level := CampaignLevel.new()
	level.level_id = &"T-F"
	level.world_id = &"test"
	level.title = "Feature test"
	level.seed_value = 4243
	level.generator_version = CampaignCatalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = CampaignCatalog.make_ruleset(&"T-F", &"cave", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 8000.0
	level.features.append(feature)
	Campaign.reset_progress()
	Campaign.start_level(level)
	var game: Node = await _make_game()
	game.get("_campaign_run").set("generated_events_enabled", false)
	var state := {"camp": not follow}
	# "follow" takes the feature's safe side; otherwise the runner stays on the
	# surface the feature hits (cave-in and floor swarm: the floor; ceiling
	# swarm: the ceiling).
	var wrong_side := -1 if (has_side and side == "ceiling") else 1
	var bot := func(g: Node) -> void:
		var player: Node = g.get_node("Player")
		var course := float(player.get("world_x")) - 180.0
		var required := CampaignFeatures.required_side_at(feature, course)
		var target := wrong_side
		if follow:
			target = required if required != 0 else 1
		if target != int(player.call("get_gravity_direction")) and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
			player.call("_try_flip", target)
	var ticks := _step(game, 3600, bot)
	var died := bool(game.get("game_over")) and not Campaign.is_completed(level)
	var death_distance := float(game.get("course_distance"))
	var label := "%s (%s) %s runner" % [kind, side if has_side else "rocks", "safe-side" if follow else "wrong-lane"]
	if follow:
		_check(Campaign.is_completed(level), "%s reaches the flag (%d ticks)" % [label, ticks])
	else:
		var span := CampaignFeatures.span_of(feature)
		_check(died and death_distance >= span.x and death_distance <= span.y, "%s dies at the feature (course %.0f, span %.0f..%.0f, over %s, completed %s)" % [label, death_distance, span.x, span.y, str(game.get("game_over")), str(Campaign.is_completed(level))])
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

func _make_game() -> Node:
	var game := MainScene.instantiate() as Node
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	return game

func _step(game: Node, ticks: int, bot: Callable = Callable()) -> int:
	var done := 0
	for _i in range(ticks):
		if bool(game.get("game_over")):
			break
		if bot.is_valid():
			bot.call(game)
		game.call("_physics_process", TICK)
		done += 1
		if done % 30 == 0:
			game.call("_process", TICK)
	return done

func _synthetic_stage() -> CampaignLevel:
	var level := CampaignLevel.new()
	level.level_id = &"T-1"
	level.world_id = &"test"
	level.title = "Test stage"
	level.seed_value = 4242
	level.generator_version = CampaignCatalog.CAMPAIGN_GENERATOR_VERSION
	# Ceiling holes never touch a floor runner, so no input is needed.
	level.ruleset = CampaignCatalog.make_ruleset(&"T-1", &"cave", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 6000.0
	level.stars = PackedVector2Array([Vector2(2180.0, 426.0), Vector2(3180.0, 426.0), Vector2(4180.0, 426.0)])
	return level

func _check_synthetic_stage() -> void:
	var level := _synthetic_stage()
	Campaign.start_level(level)
	var game: Node = await _make_game()
	_check(game.get("_campaign_level") == level, "main starts the active campaign stage")
	_check(BiomeRendererScript.locked_biome_id() == &"cave", "the stage locks its biome for presentation")
	_check(int(game.get("_active_seed")) == level.seed_value, "the stage uses its permanent seed")
	var ticks := _step(game, 2000)
	var panel: Node = game.get("_campaign_result_panel")
	_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")), "the runner reaches the flag and sees the result (%d ticks)" % ticks)
	var record := Campaign.get_record(level)
	_check(bool(record.get("completed", false)), "completion is recorded")
	_check(int(record.get("stars_mask", 0)) == 7, "all three stars were collected (mask %d)" % int(record.get("stars_mask", 0)))
	var coins := int((game.get_node("RunState")).get("coins"))
	_check(int(record.get("best_score", 0)) == Campaign.score_for(coins, 3, false), "score is coins x10 + stars x500")
	_check(bool(record.get("first_try", false)), "a clean first completion counts as first try")
	var coin_near_star := false
	for coin in game.get("coins"):
		for star in level.stars:
			if is_instance_valid(coin) and coin.position.distance_to(star) < 30.0:
				coin_near_star = true
	_check(not coin_near_star, "no coin overlaps a star")
	# Retry from the result panel starts the same stage again.
	game.call("retry_run")
	_check(not bool(game.get("game_over")) and game.get("_campaign_level") == level, "retry restarts the same stage")
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

func _check_failed_attempt() -> void:
	var level := CampaignCatalog.get_level(&"1-1")
	Campaign.start_level(level)
	var game: Node = await _make_game()
	_check(BiomeRendererScript.locked_biome_id() == &"meadow", "1-1 is drawn as the meadow")
	var ticks := _step(game, 6000)
	var panel: Node = game.get("_campaign_result_panel")
	_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")), "1-1 without input ends in a failed attempt (%d ticks)" % ticks)
	_check(int(Campaign.get_record(level).get("deaths", 0)) == 1 and not Campaign.is_completed(level), "the failed attempt is recorded as a death, not a completion")
	_check(Campaign.get_attempt_deaths() == 1, "attempt deaths count toward first-try")
	# Coins the runner passed must leave the scene, or a retry of the same
	# course shows them again as uncollectable "double" coins.
	game.call("retry_run")
	await get_tree().process_frame
	_check(_untracked_coins(game) == 0, "no passed coins survive a retry (%d left)" % _untracked_coins(game))
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

## Follows Rullaren's schedule: flips toward the next surface the attacks or
## plate require within a short look-ahead. With skip_first_plate it stays
## off the first plate's side to test the repeat path.
func _boss_bot(game: Node, state: Dictionary) -> void:
	var run: Node = game.get("_campaign_run")
	if not is_instance_valid(run):
		return
	var boss: RullarenBoss = run.get("boss")
	var player: Node = game.get_node("Player")
	var course := float(player.get("world_x")) - 180.0
	var target := 0
	var probe := course
	while probe <= course + 340.0:
		var side := boss.required_side_at(probe)
		if side != 0:
			target = side
			break
		probe += 20.0
	if bool(state.get("skip_first_plate", false)) and not boss.plate.is_empty() and str(boss.plate.state) == "armed" and int(state.get("plates_seen", 0)) == 0:
		if absf(float(boss.plate.distance) - course) < 260.0:
			target = 1 if bool(boss.plate.ceiling) else -1
	if not boss.plate.is_empty() and str(boss.plate.state) != "armed" and int(state.get("last_plate_seen_at", -1)) != int(boss.plate.distance):
		state["last_plate_seen_at"] = int(boss.plate.distance)
	if boss.attempts_in_phase > 0 or boss.hp < RullarenBoss.MAX_HP:
		state["plates_seen"] = 1
	var current := int(player.call("get_gravity_direction"))
	if target != 0 and target != current and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", target)

func _check_boss(skip_first_plate: bool, level_id: StringName = &"1-B") -> void:
	var boss_level := CampaignCatalog.get_level(level_id)
	Campaign.start_level(boss_level)
	var game: Node = await _make_game()
	var state := {"skip_first_plate": skip_first_plate}
	var bot := func(g: Node) -> void: _boss_bot(g, state)
	var ticks := _step(game, 9000, bot)
	var run: Node = game.get("_campaign_run")
	var boss: RullarenBoss = run.get("boss") if is_instance_valid(run) else null
	var label := " after a missed plate" if skip_first_plate else ""
	_check(boss != null and boss.is_defeated(), "%s is beaten by following its schedule%s (%d ticks, hp %d)" % [boss_level.title, label, ticks, boss.hp if boss != null else -1])
	var panel: Node = game.get("_campaign_result_panel")
	_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")) and Campaign.is_completed(boss_level), "the %s boss stage ends at its flag and is recorded%s" % [boss_level.level_id, label])
	var spawned_boss_attacks := 0
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle):
			spawned_boss_attacks += 1
	if skip_first_plate:
		var scheduled := boss.get_scheduled_events().size() if boss != null else 0
		_check(scheduled > 12, "a missed plate repeats the %s phase (%d attacks scheduled)" % [boss_level.level_id, scheduled])
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

## Follows the Stalactite Giant's schedule. mode "hit" plays it right,
## "early" flips away from the first icicle before the warning (the bat
## dives at the wrong side and the round repeats), "stay" never leaves the
## locked side during the first dive (the bat catches the runner).
func _stalactite_bot(game: Node, state: Dictionary) -> void:
	var run: Node = game.get("_campaign_run")
	if not is_instance_valid(run):
		return
	var bat: StalactiteBoss = run.get("boss")
	var player: Node = game.get_node("Player")
	var course := float(player.get("world_x")) - 180.0
	var target := 0
	var probe := course
	while probe <= course + 340.0:
		var side := bat.required_side_at(probe)
		if side != 0:
			target = side
			break
		probe += 20.0
	var first_dive := bat.hp == StalactiteBoss.MAX_HP and bat.attempts_in_phase == 0 and not bat.dive.is_empty()
	if first_dive and str(state.mode) != "hit":
		var icicle_side := -1 if bool(bat.dive.ceiling) else 1
		var warn_start := float(bat.dive.distance) - StalactiteBoss.ARRIVE_LEAD - float(bat.dive.warning)
		if course >= warn_start - 320.0 and course <= float(bat.dive.distance):
			if str(state.mode) == "early":
				target = -icicle_side if course < warn_start + 40.0 else icicle_side
			else:
				target = icicle_side
	var current := int(player.call("get_gravity_direction"))
	if target != 0 and target != current and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", target)

func _check_stalactite(mode: String) -> void:
	var boss_level := CampaignCatalog.get_level(&"2-B")
	_check(boss_level != null and boss_level.boss_id == &"stalactite", "the cave has the Stalactite Giant as its boss")
	if boss_level == null:
		return
	Campaign.start_level(boss_level)
	var game: Node = await _make_game()
	var state := {"mode": mode}
	var bot := func(g: Node) -> void: _stalactite_bot(g, state)
	var ticks := _step(game, 12000, bot)
	var run: Node = game.get("_campaign_run")
	var bat: StalactiteBoss = run.get("boss") if is_instance_valid(run) else null
	var panel: Node = game.get("_campaign_result_panel")
	match mode:
		"hit", "early":
			var label := "" if mode == "hit" else " after diving at the wrong side once"
			_check(bat != null and bat.is_defeated(), "the Stalactite Giant is beaten by luring it into its icicles%s (%d ticks, hp %d)" % [label, ticks, bat.hp if bat != null else -1])
			_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")) and Campaign.is_completed(boss_level), "the cave boss stage ends at its flag and is recorded%s" % label)
			if mode == "early":
				_check(bat != null and bat.get_scheduled_events().size() > 23, "a dive at the wrong side repeats the round (%d attacks scheduled)" % (bat.get_scheduled_events().size() if bat != null else 0))
		"stay":
			_check(bat != null and bat.hp == StalactiteBoss.MAX_HP and bool(game.get("game_over")) and str(bat.dive.get("state", "")) == "caught", "staying on the locked side gets the runner caught by the dive (%d ticks)" % ticks)
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

## Follows the Ghost King's schedule. mode "early" flips away from the first
## lantern so early that the king has already followed (a miss).
func _ghost_king_bot(game: Node, state: Dictionary) -> void:
	var run: Node = game.get("_campaign_run")
	if not is_instance_valid(run):
		return
	var king: GhostKingBoss = run.get("boss")
	var player: Node = game.get_node("Player")
	var course := float(player.get("world_x")) - 180.0
	var target := 0
	var probe := course
	while probe <= course + 340.0:
		var side := king.required_side_at(probe)
		if side != 0:
			target = side
			break
		probe += 20.0
	if str(state.mode) == "early" and king.hp == GhostKingBoss.MAX_HP and king.attempts_in_phase == 0 and not king.lantern.is_empty():
		var distance := float(king.lantern.distance)
		var lantern_side := -1 if bool(king.lantern.ceiling) else 1
		if course >= distance - 1100.0 and course <= distance + 80.0:
			target = lantern_side if course < distance - 900.0 else -lantern_side
	var current := int(player.call("get_gravity_direction"))
	if target != 0 and target != current and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", target)

func _check_ghost_king(mode: String) -> void:
	var boss_level := CampaignCatalog.get_level(&"3-B")
	_check(boss_level != null and boss_level.boss_id == &"ghost_king", "the haunted woods have the Ghost King as their boss")
	if boss_level == null:
		return
	Campaign.start_level(boss_level)
	var game: Node = await _make_game()
	var state := {"mode": mode}
	var bot := func(g: Node) -> void: _ghost_king_bot(g, state)
	var ticks := _step(game, 12000, bot)
	var run: Node = game.get("_campaign_run")
	var king: GhostKingBoss = run.get("boss") if is_instance_valid(run) else null
	var panel: Node = game.get("_campaign_result_panel")
	var label := "" if mode == "hit" else " after a missed lantern"
	_check(king != null and king.is_defeated(), "the Ghost King is beaten by luring him into lanterns%s (%d ticks, hp %d)" % [label, ticks, king.hp if king != null else -1])
	_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")) and bool(panel.get("visible")) and king != null and king.finish_distance > 0.0, "the haunted boss stage ends at its flag%s" % label)
	var fires := 0
	if king != null:
		for event in king.get_scheduled_events():
			if bool(event.get("ghost_fire", false)):
				fires += 1
	_check(fires >= 3, "the king drops ghost fire on the runner's old side (%d)" % fires)
	if mode == "early":
		_check(king != null and king.get_scheduled_events().size() > 0 and fires > 0, "a missed lantern repeats the phase")
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

func _check_unlocks() -> void:
	Campaign.reset_progress()
	var meadow := CampaignCatalog.get_world(&"meadow")
	var cave := CampaignCatalog.get_world(&"cave")
	_check(Campaign.is_level_unlocked(meadow.levels[0]) and not Campaign.is_level_unlocked(meadow.levels[1]), "only 1-1 is open at the start")
	_check(not Campaign.is_world_unlocked(cave), "the cave is locked at the start")
	Campaign.start_level(meadow.levels[0])
	var result := Campaign.record_completion(12, 0b101)
	_check(bool(result.get("next_unlocked_now", false)) and Campaign.is_level_unlocked(meadow.levels[1]), "finishing 1-1 opens 1-2")
	_check(int(result.get("score", 0)) == 12 * 10 + 2 * 500, "result score matches the formula")
	Campaign.start_level(meadow.levels[0])
	var again := Campaign.record_completion(3, 0b010)
	_check(int(again.get("new_stars", 0)) == 1 and Campaign.get_star_count(meadow.levels[0]) == 3, "stars accumulate across completions")
	_check(not bool(again.get("new_best", true)) and Campaign.get_best_score(meadow.levels[0]) == 1120, "best score is kept")
	for level in meadow.levels:
		Campaign.start_level(level)
		var final := Campaign.record_completion(0, 0)
		if level.is_boss():
			_check(final.get("world_unlocked") == cave, "beating the boss unlocks the cave")
	_check(Campaign.is_world_unlocked(cave), "the cave is open after the boss")
	var pingo := CharacterCatalog.get_definition(&"penguin")
	var misse := CharacterCatalog.get_definition(&"cat")
	_check(not CharacterCatalog.is_unlocked(pingo) and not CharacterCatalog.is_unlocked(misse), "Pingo and Misse are locked before their worlds' bosses")
	Campaign.start_level(cave.get_boss())
	Campaign.record_completion(0, 0)
	_check(CharacterCatalog.is_unlocked(pingo) and not CharacterCatalog.is_unlocked(misse), "beating the cave boss unlocks Pingo")
	Campaign.start_level(CampaignCatalog.get_world(&"haunted").get_boss())
	Campaign.record_completion(0, 0)
	_check(CharacterCatalog.is_unlocked(misse), "beating the Ghost King unlocks Misse")
	var bit := CharacterCatalog.get_definition(&"robot")
	_check(not CharacterCatalog.is_unlocked(bit), "Bit is locked before the Magmaormen")
	Campaign.start_level(CampaignCatalog.get_world(&"volcano").get_boss())
	Campaign.record_completion(0, 0)
	_check(CharacterCatalog.is_unlocked(bit), "beating the Magmaormen unlocks Bit")
	Campaign.clear_active()
	Campaign.reset_progress()

func _untracked_coins(game: Node) -> int:
	var tracked := {}
	for coin in game.get("coins"):
		if is_instance_valid(coin):
			tracked[coin.get_instance_id()] = true
	var count := 0
	for child in game.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("coin.gd") and not child.is_queued_for_deletion() and not bool(child.call("is_collected")) and not tracked.has(child.get_instance_id()):
			count += 1
	return count

## Ash is presentation only: it fades in and out over its section and is never
## drawn right in front of the runner.
func _check_ash() -> void:
	var sections: Array[Vector2] = [Vector2(4000.0, 7000.0)]
	_check(AshRain.strength_for(2000.0, sections) == 0.0 and AshRain.strength_for(5500.0, sections) == 1.0 and AshRain.strength_for(7400.0, sections) == 0.0, "ash fades in and out over its section")
	_check(not CampaignFeatures.is_hazardous("ash") and CampaignFeatures.events_of({"kind": "ash", "at": 4000.0}).is_empty(), "ash spawns nothing that can hurt")

## Biome keys: won by beating a world's boss, active on that world's stages
## only (not on the boss stage), and a guarding key saves one hit per stage.
func _check_biome_keys() -> void:
	Campaign.reset_progress()
	var stage := CampaignCatalog.get_level(&"4-1")
	var volcano := CampaignCatalog.get_world(&"volcano")
	_check(BiomeKeys.active_key_for(stage) == "", "no heat shield before the Magmaormen is beaten")
	Campaign.start_level(volcano.get_boss())
	Campaign.record_completion(0, 0)
	_check(BiomeKeys.active_key_for(stage) == "heat_shield" and BiomeKeys.active_key_for(volcano.get_boss()) == "" and BiomeKeys.active_key_for(CampaignCatalog.get_level(&"3-1")) == "", "beating the Magmaormen gives the heat shield on volcano stages only")
	var effects := RunEffects.new()
	effects.configure(null)
	effects.configure_key("heat_shield")
	_check(not effects.on_lethal_contact(false), "the heat shield ignores hazards it does not guard against")
	_check(effects.on_lethal_contact(true), "the heat shield saves one lava hit")
	for _i in range(RunEffects.BUBBLE_INVULNERABLE_TICKS + 1):
		effects.tick()
	_check(not effects.on_lethal_contact(true) and not effects.key_guard_ready(), "the heat shield saves only one hit per stage")
	effects.reset()
	_check(effects.key_guard_ready(), "a new attempt gets the heat shield back")
	effects.configure(null)
	_check(effects.get_key_id() == "" and effects.get_key_hud_entry().is_empty(), "configuring a run clears the key")
	# A runner on the bomb's lane survives the first ember bomb with the key.
	var level := CampaignLevel.new()
	level.level_id = &"T-K"
	level.world_id = &"volcano"
	level.title = "Key test"
	level.seed_value = 4243
	level.generator_version = CampaignCatalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = CampaignCatalog.make_ruleset(&"T-K", &"lava", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 8000.0
	level.features.append({"kind": "ember_bomb", "at": 3600.0, "side": "floor"})
	Campaign.start_level(level)
	var game: Node = await _make_game()
	game.get("_campaign_run").set("generated_events_enabled", false)
	var ticks := _step(game, 3600)
	_check(Campaign.is_completed(level), "a floor runner with the heat shield gets past an ember bomb (%d ticks)" % ticks)
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()
	Campaign.reset_progress()

## The personal-best ghost: a finished stage stores its recording, and the
## next attempt plays it back as a see-through runner that flips like the best.
func _check_personal_best_ghost() -> void:
	PersonalBestGhost.clear_all()
	var level := CampaignLevel.new()
	level.level_id = &"T-G"
	level.world_id = &"test"
	level.title = "Ghost test"
	level.seed_value = 4243
	level.generator_version = CampaignCatalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = CampaignCatalog.make_ruleset(&"T-G", &"cave", ["ceiling_gap"], 0.6, 1.0)
	level.length_px = 6000.0
	Campaign.start_level(level)
	var game: Node = await _make_game()
	game.get("_campaign_run").set("generated_events_enabled", false)
	var ghost: PersonalBestGhost = game.get("_pb_ghost")
	_check(ghost != null and not ghost.has_playback(), "a new stage has no ghost yet")
	# Flip to the ceiling once, so the recording has something to show.
	var flipper := func(g: Node) -> void:
		var player: Node = g.get_node("Player")
		if float(player.get("world_x")) > 1500.0 and int(player.call("get_gravity_direction")) == 1 and bool(player.get("grounded")):
			player.call("_try_flip", -1)
	_step(game, 2400, flipper)
	_check(Campaign.is_completed(level), "the ghost stage is finished")
	game.queue_free()
	await get_tree().process_frame
	Campaign.start_level(level)
	game = await _make_game()
	game.get("_campaign_run").set("generated_events_enabled", false)
	ghost = game.get("_pb_ghost")
	_check(ghost.has_playback(), "the next attempt has the best run as a ghost")
	_step(game, 400)
	ghost.show_at(60.0)
	_check(ghost.visible and ghost.position.y > 400.0, "the ghost runs on the floor early on (y %.0f)" % ghost.position.y)
	ghost.show_at(400.0)
	_check(ghost.visible and ghost.position.y < 200.0, "and on the ceiling after the best run's flip (y %.0f)" % ghost.position.y)
	ghost.show_at(1.0e6)
	_check(not ghost.visible, "the ghost is gone after the best run ended")
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()
	Campaign.reset_progress()
	PersonalBestGhost.clear_all()

class NearMissProbe extends Node2D:
	var rect := Rect2()
	func get_hitbox_rect() -> Rect2:
		return rect

## Near miss: right after a flip, passing a hazard within a few pixels gives one
## callout per hazard; touching it or passing far away does not.
func _check_near_miss() -> void:
	Campaign.clear_active()
	var game: Node = await _make_game()
	var player: Node = game.get_node("Player")
	var player_rect: Rect2 = player.call("get_player_rect")
	var close := NearMissProbe.new()
	close.rect = Rect2(Vector2(player_rect.position.x, player_rect.end.y + 6.0), Vector2(40.0, 40.0))
	close.position = close.rect.get_center()
	var far := NearMissProbe.new()
	far.rect = Rect2(Vector2(player_rect.position.x, player_rect.end.y + 80.0), Vector2(40.0, 40.0))
	far.position = far.rect.get_center()
	game.add_child(close)
	game.add_child(far)
	(game.get("obstacles") as Array).append_array([far, close])
	game.set("_last_gravity_direction", -int(player.call("get_gravity_direction")))
	game.call("_check_near_miss", player_rect)
	game.call("_check_near_miss", player_rect)
	_check(int(game.get("near_miss_count")) == 1, "a hazard passed by a few pixels right after a flip is one near miss")
	game.queue_free()
	await get_tree().process_frame
