extends SceneTree
## Picks a seed and three gravity-star positions for each campaign stage.
##
##   godot --headless --path . -s res://tools/campaign/campaign_level_tool.gd -- [seeds_per_stage] [stage_id]
##
## For every candidate seed it generates the whole stage with the stage's own
## ruleset (biome locked), resolves it exactly as singleplayer does and plans
## the stage's coins. Stars are taken from those coin positions, which the coin
## planner already keeps clear of hazards and on a supported surface:
##   star 1: an ordinary coin early in the stage,
##   star 2: a ceiling-lane coin mid-stage (you have to be upside down),
##   star 3: the middle coin of a "risk" row late in the stage when one exists
##           (a row that sits in front of a hazard and forces a late flip).
## The best seed is printed as catalog-ready data. Not part of the game.

const Gen := preload("res://systems/course_generator.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const Catalog := preload("res://campaign/campaign_catalog.gd")
const FLOOR_Y := 460.0
const CEILING_Y := 80.0
const START_X := 180.0
const STAR_WINDOWS := [Vector2(0.16, 0.34), Vector2(0.44, 0.62), Vector2(0.72, 0.90)]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds_per_stage := int(args[0]) if args.size() > 0 else 12
	var only_stage := args[1] if args.size() > 1 else ""
	for spec in Catalog.MEADOW_STAGES:
		if not only_stage.is_empty() and String(spec.id) != only_stage:
			continue
		var best: Dictionary = {}
		var base_seed := int(spec.seed) - (int(spec.seed) % 100)
		for offset in range(seeds_per_stage):
			var result := evaluate(spec, &"classic", base_seed + 1 + offset)
			print("CANDIDATE %s seed=%d score=%.1f events=%d intro=%s stars=%d risk=%s fallbacks=%d" % [spec.id, result.seed, result.score, result.events, str(result.intro), result.stars.size(), str(result.risk_star), result.fallbacks])
			if best.is_empty() or float(result.score) > float(best.score):
				best = result
		print("BEST %s seed=%d score=%.1f events=%d counts=%s" % [spec.id, best.seed, best.score, best.events, str(best.counts)])
		var star_text: Array[String] = []
		for star in best.stars:
			star_text.append("Vector2(%.2f, %.2f)" % [star.x, star.y])
		print("DATA %s \"seed\": %d,\n\t\t\"stars\": [%s]," % [spec.id, best.seed, ", ".join(star_text)])
	quit(0)

static func evaluate(spec: Dictionary, biome: StringName, seed_value: int) -> Dictionary:
	var ruleset := Catalog.make_ruleset(spec.id, biome, spec.profiles, float(spec.density), float(spec.margin))
	var level := CampaignLevel.new()
	level.level_id = spec.id
	level.seed_value = seed_value
	level.generator_version = Catalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = ruleset
	level.length_px = float(spec.length)
	return evaluate_level(level, spec.new)

static func evaluate_level(level: CampaignLevel, new_hazards: Array) -> Dictionary:
	BiomeRendererScript.set_locked_biome(level.get_locked_biome())
	var gen = Gen.new()
	if not gen.configure_run_definition(level.create_run_definition()):
		return {"seed": level.seed_value, "score": -INF, "events": 0, "intro": {}, "stars": [], "risk_star": false, "fallbacks": 999, "counts": {}}
	var cutoff := level.get_hazard_cutoff_distance()
	gen.ensure_horizon(level.length_px + 6000.0, 500.0, 900.0, Gen.EVENT_SPAWN_LEAD_DISTANCE)
	var planned: Array[Dictionary] = gen.get_planned_events()
	var counts: Dictionary = {}
	var intro: Dictionary = {}
	var in_course := 0
	for event in planned:
		var distance := float(event.get("course_distance", INF))
		if distance > cutoff:
			continue
		in_course += 1
		var id := str(event.get("id", event.get("kind", "")))
		counts[id] = int(counts.get(id, 0)) + 1
		if not intro.has(id):
			intro[id] = distance
	var builder = Builder.new()
	var offset := BiomeRendererScript.start_biome_offset_for_seed(level.seed_value, level.generator_version)
	var resolved: Array[Dictionary] = builder.resolve_runtime_events(planned, ceili(level.length_px + 4500.0), level.generator_version, offset)
	var coin_revision := int(level.ruleset.get("coin_revision"))
	var coins: Array[Dictionary] = CoinPlanner.plan(level.seed_value, START_X, START_X + cutoff, resolved, FLOOR_Y, CEILING_Y, coin_revision, float(level.ruleset.get("coin_density")))
	var picked := pick_stars(coins, level.length_px)
	var stats: Dictionary = gen.get_generation_stats()
	var fallbacks := int(stats.get("fallback_events", 0))
	# Score: stars found, a risk star, every new hazard introduced in the first
	# quarter and seen at least three times, no fallback encounters.
	var score := float(picked.stars.size()) * 10.0
	if picked.risk:
		score += 6.0
	for hazard in new_hazards:
		var first := float(intro.get(hazard, INF))
		var seen := int(counts.get(hazard, 0))
		score += 8.0 if first <= level.length_px * 0.25 else (-4.0 if first == INF else 0.0)
		score += minf(float(seen), 6.0)
	score -= float(fallbacks) * 20.0
	return {"seed": level.seed_value, "score": score, "events": in_course, "intro": intro, "stars": picked.stars, "risk_star": picked.risk, "fallbacks": fallbacks, "counts": counts}

static func pick_stars(coins: Array[Dictionary], length_px: float) -> Dictionary:
	var rows: Dictionary = {}
	for coin in coins:
		var parts := str(coin.get("entity_id", "")).split("_")
		if parts.size() < 4:
			continue
		var row := int(parts[2])
		if not rows.has(row):
			rows[row] = []
		rows[row].append(coin)
	var stars: Array[Vector2] = []
	var used_risk := false
	for window_index in range(STAR_WINDOWS.size()):
		var window: Vector2 = STAR_WINDOWS[window_index]
		var left := START_X + length_px * window.x
		var right := START_X + length_px * window.y
		var center := (left + right) * 0.5
		var best_coin: Dictionary = {}
		var best_rank := -INF
		for row in rows:
			var row_coins: Array = rows[row]
			if row_coins.size() < 2:
				continue
			var middle: Dictionary = row_coins[row_coins.size() / 2]
			var x := float(middle.world_x)
			if x < left or x > right:
				continue
			var is_risk := str(middle.get("formation", "")) == "risk"
			var is_ceiling := float(middle.world_y) < (FLOOR_Y + CEILING_Y) * 0.5
			var rank := -absf(x - center) / 1000.0
			match window_index:
				1:
					rank += 6.0 if is_ceiling else 0.0
				2:
					rank += 8.0 if is_risk else (3.0 if is_ceiling else 0.0)
			if rank > best_rank:
				best_rank = rank
				best_coin = middle
		if not best_coin.is_empty():
			stars.append(Vector2(float(best_coin.world_x), float(best_coin.world_y)))
			if window_index == 2 and str(best_coin.get("formation", "")) == "risk":
				used_risk = true
	return {"stars": stars, "risk": used_risk}
