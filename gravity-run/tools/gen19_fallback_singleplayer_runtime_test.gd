extends Node
## Verify that an MP-filtered Gen19 pursuit fallback is resolved and spawned by
## the real singleplayer adapter only when the ordinary spawn horizon is reached.

const MainScene := preload("res://main.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const RunDefinition := preload("res://systems/course_run_definition.gd")
const COURSE_LENGTH := 45000
const SEED_FIRST := 100000001
const SEED_COUNT := 20

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	challenge.call("clear_challenge")
	var builder := Builder.new()
	var selected_seed := 0
	var shared_manifest: Resource
	var shared_fallback: Dictionary = {}
	for offset in range(SEED_COUNT):
		var seed_value := SEED_FIRST + offset
		var built: Dictionary = builder.build(seed_value, COURSE_LENGTH, 19)
		var manifest: Variant = built.get("manifest")
		if manifest == null:
			continue
		for event in manifest.get("events"):
			if bool(event.get("gen19_supported_fallback", false)) and str(event.get("kind", "")) == "block":
				selected_seed = seed_value
				shared_manifest = manifest
				shared_fallback = event
				break
		if selected_seed > 0:
			break
	_check(selected_seed > 0, "bounded cohort includes a supported pursuit-to-block fallback")
	if selected_seed <= 0:
		_finish()
		return
	_check(bool(challenge.call("start_singleplayer_seed_input", str(selected_seed))), "ChallengeService selects current Gen19 seed")
	var game := MainScene.instantiate() as Node
	game.set_physics_process(false)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	_check(int(game.get("_active_seed")) == selected_seed and int(game.get("_active_seed_version")) == 19, "actual main scene starts the selected Gen19 seed")
	var generator = game.get("course_generator")
	# Use the same canonical multiplayer run definition for this adapter parity
	# check, then exercise the real main-scene resolver and spawn code.
	var shared_rules: Resource = builder.call("_make_multiplayer_ruleset", 19)
	var definition: Resource = RunDefinition.new()
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", selected_seed)
	definition.set("generator_version", 19)
	definition.set("ruleset", shared_rules)
	_check(bool(generator.call("configure_run_definition", definition)), "actual main scene accepts the canonical shared run definition")
	generator.call("ensure_horizon", float(COURSE_LENGTH), 500.0, 540.0, 820.0)
	var planned: Array = generator.call("get_planned_events")
	var source: Dictionary = {}
	var source_distance := float(shared_fallback.get("x", 0.0)) - 180.0
	for event in planned:
		if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3 and absf(float(event.get("course_distance", INF)) - source_distance) < 0.5:
			source = event
			break
	if source.is_empty():
		var nearest: Array[Dictionary] = []
		for event in planned:
			if str(event.get("kind", "")) == "ghost" and int(event.get("ghost_variant", 0)) == 3:
				nearest.append({"x": event.get("course_distance", -1.0), "variant": event.get("ghost_variant", -1), "distance": absf(float(event.get("course_distance", INF)) - source_distance)})
		nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
		print("GEN19_FALLBACK_SP_SOURCE_MISMATCH seed=%d active_version=%d target_course_x=%.1f nearest=%s" % [selected_seed, int(game.get("_active_seed_version")), source_distance, JSON.stringify(nearest.slice(0, 5))])
	_check(not source.is_empty(), "SP source generator contains the ghost replaced in the shared manifest")
	if source.is_empty():
		game.queue_free()
		_finish()
		return
	var biome_offset := BiomeRenderer.start_biome_offset_for_seed(selected_seed, 19)
	var resolved: Array[Dictionary] = game.get("_manifest_builder").call("resolve_runtime_events", planned, COURSE_LENGTH, 19, biome_offset)
	var sp_fallback: Dictionary = game.call("_resolve_singleplayer_ghost_event", source)
	_check(bool(sp_fallback.get("gen19_supported_fallback", false)) and str(sp_fallback.get("kind", "")) == "block", "singleplayer source adapter receives the resolved block replacement")
	_check(str(sp_fallback.get("event_id", "")) == str(shared_fallback.get("event_id", "")) and is_equal_approx(float(sp_fallback.get("x", -1.0)), float(shared_fallback.get("x", -2.0))), "SP and MP replacement event id and world x match")
	for event in planned:
		if str(event.get("kind", "")) in ["step", "slope", "gap"] and float(event.get("course_distance", INF)) < source_distance:
			game.call("_spawn_course_event", event)
	var floor_y := float(game.call("_floor_surface_y", float(sp_fallback.get("x", 0.0))))
	_check(is_equal_approx(floor_y, float(sp_fallback.get("y", -1.0))), "SP spawned support matches the shared resolved fallback surface y")
	var early_lead := float(source.get("trigger_lead", 2500.0))
	game.set("course_distance", source_distance - early_lead)
	game.call("_spawn_course_event", source)
	var fallback_x := float(sp_fallback.get("x", -1.0))
	_check(_fallback_node_count(game, fallback_x) == 0, "fallback is not spawned at the ghost warning/early trigger line")
	var event_spawn_lead := Generator.get_viewport_spawn_lead_distance(float(game.get("screen_width")), 180.0, Generator.SLOPE_WIDTH)
	game.set("course_distance", source_distance - event_spawn_lead)
	game.call("_spawn_course_event", source)
	_check(_fallback_node_count(game, fallback_x) == 1, "fallback block spawns once at normal course-event horizon")
	var node := _fallback_node(game, fallback_x)
	if node != null:
		_check(is_equal_approx(node.global_position.x, float(sp_fallback.get("x", -1.0))), "SP block world position matches MP fallback")
		var rect: Rect2 = node.call("get_hitbox_rect")
		_check(is_equal_approx(rect.size.x, float(sp_fallback.get("width", 0.0))) and is_equal_approx(rect.size.y, float(sp_fallback.get("height", 0.0))), "SP fallback block hitbox dimensions match resolved event")
	game.call("_spawn_course_event", source)
	_check(_fallback_node_count(game, fallback_x) == 1, "repeated source dispatch cannot duplicate the fallback")
	var mp_coins: Array = shared_manifest.get("collectibles")
	var mp_excluded := _no_coin_in_block_clearance(mp_coins, shared_fallback)
	_check(mp_excluded, "MP coin catalog excludes the replacement block footprint")
	var planner: RefCounted = game.get("_shared_coin_planner")
	var sp_coins: Array[Dictionary] = planner.extend(float(shared_manifest.get("finish_x")), resolved, 460.0, 80.0, 0)
	_check(_no_coin_in_block_clearance(sp_coins, sp_fallback), "SP coin planner excludes the same replacement block footprint")
	print("GEN19_FALLBACK_SINGLEPLAYER seed=%d event=%s world_x=%.1f early=%d normal_spawn_lead=%.1f sp_coin_count=%d mp_coin_count=%d failures=%d" % [selected_seed, str(sp_fallback.get("event_id", "")), float(sp_fallback.get("x", -1.0)), int(source_distance - early_lead), event_spawn_lead, sp_coins.size(), mp_coins.size(), failures])
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _no_coin_in_block_clearance(coins: Array, block: Dictionary) -> bool:
	var safe_distance := float(block.get("width", 44.0)) * 0.5 + CoinPlanner.COIN_RADIUS
	for coin in coins:
		if absf(float(coin.get("world_x", INF)) - float(block.get("x", 0.0))) < safe_distance:
			return false
	return true

func _fallback_node_count(game: Node, target_x: float) -> int:
	var count := 0
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("breakable") and not obstacle.is_in_group("barrels") and absf(obstacle.global_position.x - target_x) < 0.5:
			count += 1
	return count

func _fallback_node(game: Node, target_x: float) -> Node2D:
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("breakable") and not obstacle.is_in_group("barrels") and absf(obstacle.global_position.x - target_x) < 0.5:
			return obstacle
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	print("GEN19_FALLBACK_SINGLEPLAYER_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
