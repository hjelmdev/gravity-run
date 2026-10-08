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
	await _check_synthetic_stage()
	await _check_failed_attempt()
	await _check_boss(false)
	await _check_boss(true)
	_check_unlocks()
	BiomeRendererScript.set_locked_biome(&"")
	print("CAMPAIGN_RUNTIME_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_catalog() -> void:
	var worlds := CampaignCatalog.worlds()
	_check(worlds.size() >= 4 and worlds[0].levels.size() == 7, "catalog has four worlds and the meadow has six stages plus a boss")
	var generator := Gen.new()
	var profiles := generator.get_profile_catalog(CampaignCatalog.CAMPAIGN_GENERATOR_VERSION)
	var identities: Dictionary = {}
	for level in worlds[0].levels:
		_check(str(level.ruleset.call("validate", profiles)).is_empty(), "%s ruleset validates" % level.level_id)
		identities[level.get_identity()] = true
		if level.is_boss():
			continue
		_check(level.stars.size() == 3, "%s has three gravity stars" % level.level_id)
		_check(level.length_px >= 15000.0 and level.length_px <= 22500.0, "%s is 30-45 s long" % level.level_id)
		BiomeRendererScript.set_locked_biome(level.get_locked_biome())
		var gen := Gen.new()
		_check(gen.configure_run_definition(level.create_run_definition()), "%s configures the generator" % level.level_id)
		gen.ensure_horizon(level.length_px + 6000.0, 500.0, 900.0, Gen.EVENT_SPAWN_LEAD_DISTANCE)
		var planned: Array[Dictionary] = gen.get_planned_events()
		var biome_ok := true
		for event in planned:
			if str(event.get("kind", "")) in ["ghost", "lava_crack", "volcano"] or str(event.get("id", "")) == "cave_icicle":
				biome_ok = false
		_check(biome_ok, "%s only generates meadow encounters" % level.level_id)
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
	_check(identities.size() == worlds[0].levels.size(), "stage identities are unique")
	BiomeRendererScript.set_locked_biome(&"")

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

func _check_boss(skip_first_plate: bool) -> void:
	var boss_level := CampaignCatalog.get_level(&"1-B")
	Campaign.start_level(boss_level)
	var game: Node = await _make_game()
	var state := {"skip_first_plate": skip_first_plate}
	var bot := func(g: Node) -> void: _boss_bot(g, state)
	var ticks := _step(game, 9000, bot)
	var run: Node = game.get("_campaign_run")
	var boss: RullarenBoss = run.get("boss") if is_instance_valid(run) else null
	var label := " after a missed plate" if skip_first_plate else ""
	_check(boss != null and boss.is_defeated(), "Rullaren is beaten by following its schedule%s (%d ticks, hp %d)" % [label, ticks, boss.hp if boss != null else -1])
	var panel: Node = game.get("_campaign_result_panel")
	_check(bool(game.get("game_over")) and is_instance_valid(panel) and bool(panel.get("visible")) and Campaign.is_completed(boss_level), "the boss stage ends at its flag and is recorded%s" % label)
	var spawned_boss_attacks := 0
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle):
			spawned_boss_attacks += 1
	if skip_first_plate:
		var scheduled := boss.get_scheduled_events().size() if boss != null else 0
		_check(scheduled > 12, "a missed plate repeats the phase (%d attacks scheduled)" % scheduled)
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
	Campaign.clear_active()
	Campaign.reset_progress()
