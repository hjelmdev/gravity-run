extends SceneTree
## Picks a seed and three gravity-star positions for each campaign stage.
##
##   godot --headless --path . -s res://tools/campaign/campaign_level_tool.gd -- [seeds_per_stage] [stage_id or prefix, e.g. 2-]
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
##
## Scripted features (campaign_features.gd) are placed afterwards, on the frozen
## seed and stars of each stage:
##
##   godot --headless --path . -s res://tools/campaign/campaign_level_tool.gd -- features [stage_id or prefix]
##
## For every stage in FEATURE_PLAN it plans the stage's course, finds the quiet
## windows (no generated event, gap, slope/step or star within a safe margin of
## the feature's whole span), puts each feature at the quiet position nearest its
## target fraction of the stage and prints catalog-ready "features" data.

const Gen := preload("res://systems/course_generator.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const Catalog := preload("res://campaign/campaign_catalog.gd")
const FLOOR_Y := 460.0
const CEILING_Y := 80.0
const START_X := 180.0
const STAR_WINDOWS := [Vector2(0.16, 0.34), Vector2(0.44, 0.62), Vector2(0.72, 0.90)]
const WORLD_HEIGHT := 540.0
## [kind, target fraction of the stage, extras]. Hazardous features snap to the
## nearest quiet position; darkness is presentation only and stays where put.
const FEATURE_PLAN := {
	"2-2": [["bat_swarm", 0.28, {"side": "ceiling"}], ["bat_swarm", 0.52, {"side": "floor"}], ["bat_swarm", 0.78, {"side": "ceiling"}]],
	"2-3": [["bat_swarm", 0.40, {"side": "floor"}], ["bat_swarm", 0.72, {"side": "ceiling"}]],
	"2-4": [["cave_in", 0.30, {"count": 3}], ["cave_in", 0.58, {"count": 4}], ["cave_in", 0.80, {"count": 3}]],
	"2-5": [["darkness", 0.24, {"length": 3600.0}], ["darkness", 0.62, {"length": 4200.0}]],
	"3-3": [["ghost_hand", 0.22, {"side": "floor"}], ["ghost_hand", 0.42, {"side": "ceiling"}], ["ghost_hand", 0.62, {"side": "floor"}], ["ghost_hand", 0.82, {"side": "ceiling"}]],
	"3-4": [["fog", 0.30, {"length": 2000.0}], ["fog", 0.62, {"length": 2400.0}]],
	"3-5": [["wisp", 0.22, {"length": 1500.0}], ["wisp", 0.50, {"length": 1500.0}], ["wisp", 0.78, {"length": 1500.0}]],
	"3-6": [["ghost_hand", 0.30, {"side": "ceiling"}], ["fog", 0.50, {"length": 2000.0}], ["ghost_hand", 0.72, {"side": "floor"}]],
	"2-6": [["cave_in", 0.93, {"count": 3}], ["darkness", 0.58, {"length": 3200.0}], ["bat_swarm", 0.30, {"side": "floor"}], ["bat_swarm", 0.84, {"side": "ceiling"}]],
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "features":
		var only := args[1] if args.size() > 1 else ""
		for table in Catalog.stage_tables():
			for spec in table[2]:
				if FEATURE_PLAN.has(str(spec.id)) and (only.is_empty() or String(spec.id).begins_with(only)):
					_print_features(spec, table[1])
		quit(0)
		return
	var seeds_per_stage := int(args[0]) if args.size() > 0 else 12
	var only_stage := args[1] if args.size() > 1 else ""
	for table in Catalog.stage_tables():
		var biome: StringName = table[1]
		for spec in table[2]:
			if not only_stage.is_empty() and not String(spec.id).begins_with(only_stage):
				continue
			_search(spec, biome, seeds_per_stage)
	quit(0)

func _search(spec: Dictionary, biome: StringName, seeds_per_stage: int) -> void:
	var best: Dictionary = {}
	var base_seed := int(spec.seed) - (int(spec.seed) % 100)
	for offset in range(seeds_per_stage):
		var result := evaluate(spec, biome, base_seed + 1 + offset)
		print("CANDIDATE %s seed=%d score=%.1f events=%d intro=%s stars=%d risk=%s fallbacks=%d" % [spec.id, result.seed, result.score, result.events, str(result.intro), result.stars.size(), str(result.risk_star), result.fallbacks])
		if best.is_empty() or float(result.score) > float(best.score):
			best = result
	print("BEST %s seed=%d score=%.1f events=%d counts=%s" % [spec.id, best.seed, best.score, best.events, str(best.counts)])
	var star_text: Array[String] = []
	for star in best.stars:
		star_text.append("Vector2(%.2f, %.2f)" % [star.x, star.y])
	print("DATA %s \"seed\": %d,\n\t\t\"stars\": [%s]," % [spec.id, best.seed, ", ".join(star_text)])

static func evaluate(spec: Dictionary, biome: StringName, seed_value: int) -> Dictionary:
	var ruleset := Catalog.make_ruleset(spec.id, biome, spec.profiles, float(spec.density), float(spec.margin), Catalog.stage_weights(spec))
	var level := CampaignLevel.new()
	level.level_id = spec.id
	level.seed_value = seed_value
	level.generator_version = Catalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = ruleset
	level.length_px = float(spec.length)
	return evaluate_level(level, spec.new, (spec.get("weights", {}) as Dictionary).keys())

static func evaluate_level(level: CampaignLevel, new_hazards: Array, focus_hazards: Array = []) -> Dictionary:
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
	# A stage about some hazards (its "weights") should show them often, and
	# among otherwise equal seeds the fuller course reads better.
	for hazard in focus_hazards:
		score += minf(float(counts.get(hazard, 0)), 6.0)
	score += float(in_course) * 0.2
	score -= maxf(0.0, level.length_px / 1100.0 - float(in_course)) * 2.0
	score -= float(fallbacks) * 20.0
	var conflicts := gap_conflicts(resolved, START_X + cutoff)
	score -= float(conflicts) * 100.0
	return {"seed": level.seed_value, "score": score, "gap_conflicts": conflicts, "events": in_course, "intro": intro, "stars": picked.stars, "risk_star": picked.risk, "fallbacks": fallbacks, "counts": counts}

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

## Gen21 can leave a floor hole and a ceiling hole (a plain gap or the roof
## hole a dropping saw cuts) so close together that there is no surface on
## either side and the only way through is a ~0.14 s flip window. Campaign
## seeds must not contain that pattern. Works on resolved runtime events.
const GAP_CLEARANCE := 450.0

static func gap_conflicts(resolved: Array, cutoff_x: float) -> int:
	var floor_gaps: Array[Vector2] = []
	var ceiling_gaps: Array[Vector2] = []
	for event in resolved:
		var x := float(event.get("x", INF))
		if x > cutoff_x:
			continue
		var kind := str(event.get("kind", ""))
		if kind == "gap":
			var half := float(event.get("width", 0.0)) * 0.5
			if bool(event.get("from_ceiling", false)):
				ceiling_gaps.append(Vector2(x - half, x + half))
			else:
				floor_gaps.append(Vector2(x - half, x + half))
		elif kind == "saw" and event.has("roof_gap_x"):
			var roof_half := float(event.get("roof_gap_width", 0.0)) * 0.5
			ceiling_gaps.append(Vector2(float(event.roof_gap_x) - roof_half, float(event.roof_gap_x) + roof_half))
	var conflicts := 0
	for a in floor_gaps:
		for b in ceiling_gaps:
			if a.x - GAP_CLEARANCE < b.y and b.x - GAP_CLEARANCE < a.y:
				conflicts += 1
	return conflicts

## Plans a stage's course with its frozen seed and returns what feature
## placement needs: the generated events, the surface index and the level.
static func plan_course(spec: Dictionary, biome: StringName) -> Dictionary:
	var level := CampaignLevel.new()
	level.level_id = spec.id
	level.seed_value = int(spec.seed)
	level.generator_version = Catalog.CAMPAIGN_GENERATOR_VERSION
	level.ruleset = Catalog.make_ruleset(spec.id, biome, spec.profiles, float(spec.density), float(spec.margin), Catalog.stage_weights(spec))
	level.length_px = float(spec.length)
	return plan_level(level)

## Same for an already built level.
static func plan_level(level: CampaignLevel) -> Dictionary:
	BiomeRendererScript.set_locked_biome(level.get_locked_biome())
	var gen = Gen.new()
	gen.configure_run_definition(level.create_run_definition())
	gen.ensure_horizon(level.length_px + 6000.0, 500.0, 900.0, Gen.EVENT_SPAWN_LEAD_DISTANCE)
	var planned: Array[Dictionary] = gen.get_planned_events()
	var builder = Builder.new()
	var offset := BiomeRendererScript.start_biome_offset_for_seed(level.seed_value, level.generator_version)
	var resolved: Array[Dictionary] = builder.resolve_runtime_events(planned, ceili(level.length_px + 4500.0), level.generator_version, offset)
	var surface_index := CourseSurfaceIndex.new()
	surface_index.configure(resolved, FLOOR_Y, CEILING_Y)
	return {"level": level, "planned": planned, "surface": func(x: float, ceiling: bool) -> float: return float(surface_index.surface_at(x, ceiling).get("y", 0.0))}

## Quiet position for every planned feature of a stage (stars and seed come
## from the catalog spec and stay untouched).
static func pick_features(spec: Dictionary, biome: StringName) -> Array[Dictionary]:
	var course := plan_course(spec, biome)
	var length := float(spec.length)
	var stars := PackedVector2Array(spec.stars)
	var chosen: Array[Dictionary] = []
	for entry in FEATURE_PLAN.get(str(spec.id), []):
		var kind := str(entry[0])
		var extras: Dictionary = entry[2]
		var target := length * float(entry[1])
		var best: Dictionary = {}
		var best_distance := INF
		var at := CampaignFeatures.MIN_START
		while at < length - 1200.0:
			var feature := {"kind": kind, "at": at}
			feature.merge(extras)
			var distance := absf(at - target)
			if distance < best_distance and CampaignFeatures.conflicts(feature, course.planned, stars, length, course.surface).is_empty():
				var trial := chosen.duplicate()
				trial.append(feature)
				if CampaignFeatures.overlaps(trial).is_empty():
					best = feature
					best_distance = distance
			at += 10.0
		if best.is_empty():
			push_warning("%s: no quiet position for %s near %.0f" % [spec.id, kind, target])
			continue
		chosen.append(best)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
	return chosen

func _print_features(spec: Dictionary, biome: StringName) -> void:
	var features := pick_features(spec, biome)
	var parts: Array[String] = []
	for feature in features:
		var keys: Array[String] = []
		for key in ["kind", "at", "side", "count", "length"]:
			if feature.has(key):
				var value: Variant = feature[key]
				keys.append("\"%s\": %s" % [key, ("\"%s\"" % value) if value is String else ("%.1f" % float(value) if key in ["at", "length"] else str(value))])
		parts.append("{%s}" % ", ".join(keys))
		var span := CampaignFeatures.span_of(feature)
		print("FEATURE %s %s at=%.0f span=%.0f..%.0f" % [spec.id, feature.kind, feature.at, span.x, span.y])
	print("DATA %s \"features\": [%s]," % [spec.id, ", ".join(parts)])
