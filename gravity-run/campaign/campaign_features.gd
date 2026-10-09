extends RefCounted
class_name CampaignFeatures
## Scripted campaign features: events a stage adds at fixed course distances on
## top of its generated encounters (the generator never changes for these).
## A feature is frozen catalog data, e.g. {"kind": "cave_in", "at": 8200.0}.
## CampaignRun pops the events of a feature as the spawn line reaches them and
## main.gd spawns them like any course event. This file is the single place that
## knows what a kind looks like: the events it expands to, the stretch of course
## it occupies (its span), and which surface a runner must be on. Kinds are data
## (KINDS), so other worlds can add their own without touching the channel.
##
## Kinds:
##   cave_in    3-4 falling rocks in quick succession (the ordinary falling rock),
##              with a dust crack in the ceiling as warning.
##   bat_swarm  a flapping swarm that sweeps down one lane ("side": floor|ceiling).
##   darkness   presentation only: a dark section lit around the runner.
##   ghost_hand a purple glow warns a lane, then a ghost hand reaches out of it
##              ("side": floor|ceiling).
##   wisp       harmless: a wisp floats ahead and copies the runner's lane with a
##              delay; touching it gives bonus coins. Decided by CampaignRun.
##   fog        presentation only: a fog bank over the right part of the screen.
##              Only placed where the generated events are sparse (fog_min_gap).
##   ember_bomb a red ring warns a lane while a glowing bomb falls in, then a
##              burning mound blocks that lane for a moment ("side": floor|ceiling).
##              Same timing and hitbox as the ghost hand.
##   ash        presentation only: ash drifting down over the screen.

## True for kinds that can kill: they need a quiet stretch of course.
const KINDS := {
	"cave_in": {"hazardous": true, "before": 420.0, "after": 140.0, "default_count": 3},
	"bat_swarm": {"hazardous": true, "before": 560.0, "after": 90.0},
	"darkness": {"hazardous": false, "default_length": 3200.0},
	"ghost_hand": {"hazardous": true, "before": 360.0, "after": 70.0, "margin": 30.0},
	"wisp": {"hazardous": false, "default_length": 1500.0},
	"fog": {"hazardous": false, "default_length": 2000.0, "sparse": true},
	"ember_bomb": {"hazardous": true, "before": 360.0, "after": 70.0, "margin": 30.0},
	"ash": {"hazardous": false, "default_length": 3000.0},
}

## Falling rocks of a cave-in: spacing, size and timing. The rocks use the
## generator's rock model, only their warning is shorter and their lead is set
## so that the whole row has landed before the fastest runner arrives.
const ROCK_SPACING := 170.0
const ROCK_WIDTH := 84.0
const ROCK_HEIGHT := 100.0
const ROCK_TRIGGER_LEAD := 1150.0
const ROCK_WARNING_TICKS := 54
const ROCK_FALL_TICKS := 20
const ROCK_BURIAL := 24.0
## Bat swarm size. The swarm roosts at "at", wakes when the runner is
## BAT_TRIGGER_DISTANCE away and then sweeps toward the runner.
const BAT_WIDTH := 300.0
const BAT_HEIGHT := 84.0
const BAT_TRIGGER_DISTANCE := 520.0
## Distance the runner covers while the swarm rustles before it takes off.
const BAT_WARNING_DISTANCE := 180.0

## Ghost hand size (timing lives in hazards/ghost_hand.gd).
const HAND_WIDTH := 60.0
const HAND_HEIGHT := 120.0
const HAND_EARLY_LEAD := 800.0
## Wisp: it starts WISP_START_OFFSET px ahead of the runner and drifts back
## through the runner's position; it copies the runner's lane WISP_DELAY_TICKS
## (0.8 s) late. Touching it gives WISP_BONUS_COINS.
const WISP_START_OFFSET := 460.0
const WISP_END_OFFSET := -60.0
const WISP_DELAY_TICKS := 48
const WISP_BONUS_COINS := 3
## Fog is the haunted stand-in for a +0.1 reaction margin (generation cannot
## change): inside fog every gap between generated events must be at least this
## factor times the stage's own 40th-percentile gap, so fog avoids the tight
## clusters of a stage and sits over its roomier stretches.
const FOG_GAP_FACTOR := 1.1
const FOG_GAP_PERCENTILE := 0.4

## Clearance rules shared by the level tool and the tests.
const EVENT_MARGIN := 80.0
const STAR_MARGIN := 120.0
const FEATURE_MARGIN := 250.0
const MIN_START := 2400.0
const FINISH_MARGIN := 240.0
## Lane height (floor to ceiling) a hazardous feature needs where it acts.
## A buried rock is 76 px high and the runner 44, so 200 leaves a safe route
## along the other surface. main.gd applies ROCK_MIN_LANE to feature rocks
## (generated rocks keep their own 260 rule).
const ROCK_MIN_LANE := 200.0
const MIN_LANE_CLEARANCE := {"cave_in": ROCK_MIN_LANE, "bat_swarm": 200.0, "ghost_hand": 200.0, "ember_bomb": 200.0}

static func is_hazardous(kind: String) -> bool:
	return bool((KINDS.get(kind, {}) as Dictionary).get("hazardous", false))

static func is_known(kind: String) -> bool:
	return KINDS.has(kind)

static func rock_count(feature: Dictionary) -> int:
	return clampi(int(feature.get("count", (KINDS["cave_in"] as Dictionary).default_count)), 3, 4)

static func length_of(feature: Dictionary) -> float:
	return float(feature.get("length", (KINDS.get(str(feature.get("kind", "")), {}) as Dictionary).get("default_length", 0.0)))

## The stretch of course distance [from, to] the feature occupies, including
## the warning and the runner's reaction time before it.
static func span_of(feature: Dictionary) -> Vector2:
	var kind := str(feature.get("kind", ""))
	var at := float(feature.get("at", 0.0))
	var def: Dictionary = KINDS.get(kind, {})
	match kind:
		"cave_in":
			var last := at + float(rock_count(feature) - 1) * ROCK_SPACING
			return Vector2(at - float(def.before), last + ROCK_WIDTH * 0.5 + float(def.after))
		"bat_swarm":
			return Vector2(at - float(def.before), at + BAT_WIDTH * 0.5 + float(def.after))
		"ghost_hand", "ember_bomb":
			return Vector2(at - float(def.before), at + HAND_WIDTH * 0.5 + float(def.after))
		"darkness", "wisp", "fog", "ash":
			return Vector2(at, at + length_of(feature))
	return Vector2(at, at)

## Where the hazard itself acts (rocks landing, the swarm sweeping).
static func critical_range_of(feature: Dictionary) -> Vector2:
	var at := float(feature.get("at", 0.0))
	match str(feature.get("kind", "")):
		"cave_in":
			return Vector2(at - 60.0, at + float(rock_count(feature) - 1) * ROCK_SPACING + 60.0)
		"bat_swarm":
			return Vector2(at - 300.0, at + BAT_WIDTH * 0.5)
		"ghost_hand", "ember_bomb":
			return Vector2(at - 60.0, at + 60.0)
	return span_of(feature)

## Course events main.gd spawns for a feature, in order. "early_lead" is how
## far before its course distance an event must already exist.
static func events_of(feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind := str(feature.get("kind", ""))
	var at := float(feature.get("at", 0.0))
	match kind:
		"cave_in":
			for index in range(rock_count(feature)):
				result.append({
					"kind": "rock", "id": "falling_rock", "feature": "cave_in",
					"course_distance": at + float(index) * ROCK_SPACING,
					"width": ROCK_WIDTH, "height": ROCK_HEIGHT, "from_ceiling": false,
					"trigger_lead": ROCK_TRIGGER_LEAD, "warning_ticks": ROCK_WARNING_TICKS,
					"fall_ticks": ROCK_FALL_TICKS, "burial_depth": ROCK_BURIAL,
					"early_lead": ROCK_TRIGGER_LEAD + 400.0, "feature_event": true,
				})
		"bat_swarm":
			result.append({
				"kind": "bat_swarm", "id": "bat_swarm", "feature": "bat_swarm",
				"course_distance": at, "width": BAT_WIDTH, "height": BAT_HEIGHT,
				"from_ceiling": str(feature.get("side", "ceiling")) == "ceiling",
				"trigger_distance": BAT_TRIGGER_DISTANCE,
				"early_lead": BAT_TRIGGER_DISTANCE + 300.0, "feature_event": true,
			})
		"ghost_hand":
			result.append({
				"kind": "ghost_hand", "id": "ghost_hand", "feature": "ghost_hand",
				"course_distance": at, "width": HAND_WIDTH, "height": HAND_HEIGHT,
				"from_ceiling": str(feature.get("side", "floor")) == "ceiling",
				"early_lead": HAND_EARLY_LEAD, "feature_event": true,
			})
		"ember_bomb":
			result.append({
				"kind": "ember_bomb", "id": "ember_bomb", "feature": "ember_bomb",
				"course_distance": at, "width": HAND_WIDTH, "height": HAND_HEIGHT * 0.75,
				"from_ceiling": str(feature.get("side", "floor")) == "ceiling",
				"early_lead": HAND_EARLY_LEAD, "feature_event": true,
			})
	return result

## Which surface the runner has to be on near a course distance to survive this
## feature: 1 floor, -1 ceiling, 0 either. Used by test bots.
static func required_side_at(feature: Dictionary, course_distance: float) -> int:
	var kind := str(feature.get("kind", ""))
	var at := float(feature.get("at", 0.0))
	match kind:
		"cave_in":
			var last := at + float(rock_count(feature) - 1) * ROCK_SPACING
			if course_distance >= at - 400.0 and course_distance <= last + ROCK_WIDTH * 0.5 + 90.0:
				return -1
		"bat_swarm":
			if course_distance >= at - BAT_TRIGGER_DISTANCE and course_distance <= at + 260.0:
				return 1 if str(feature.get("side", "ceiling")) == "ceiling" else -1
		"ghost_hand", "ember_bomb":
			if course_distance >= at - 330.0 and course_distance <= at + 80.0:
				return 1 if str(feature.get("side", "floor")) == "ceiling" else -1
	return 0

## Wisp offset ahead of the runner at a course distance (negative once it has
## drifted past), or INF when the wisp is not out.
static func wisp_offset(feature: Dictionary, course_distance: float) -> float:
	var at := float(feature.get("at", 0.0))
	var length := length_of(feature)
	if course_distance < at or course_distance > at + length:
		return INF
	return lerpf(WISP_START_OFFSET, WISP_END_OFFSET, (course_distance - at) / length)

## Extent of course distance a generated encounter threatens, padded for things
## that travel (barrels roll toward the runner, saws move along a surface).
static func event_extent(event: Dictionary) -> Vector2:
	var distance := float(event.get("course_distance", 0.0))
	var half := float(event.get("width", 48.0)) * 0.5
	var kind := str(event.get("kind", ""))
	var low := distance - half
	var high := distance + half
	if kind == "rock":
		return Vector2(distance - 110.0, distance + 110.0)
	for threat in event.get("threats", []):
		low = minf(low, float(threat.get("start", low)))
		high = maxf(high, float(threat.get("end", high)))
	if kind == "barrels":
		low -= 250.0
	elif kind in ["step", "slope", "gap"]:
		low -= 60.0
		high += 60.0
	return Vector2(low, high)

## Reasons a feature does not fit its stage; empty when it is fair. `planned`
## are the stage's generated events, `stars` the world-space star positions,
## `surface` an optional Callable(x, ceiling) -> y for lane clearance.
static func conflicts(feature: Dictionary, planned: Array, stars: PackedVector2Array, length_px: float, surface: Callable = Callable()) -> Array[String]:
	var problems: Array[String] = []
	var kind := str(feature.get("kind", ""))
	if not is_known(kind):
		problems.append("unknown kind %s" % kind)
		return problems
	var span := span_of(feature)
	var cutoff := length_px - 1200.0
	if span.x < MIN_START:
		problems.append("starts too early (%.0f)" % span.x)
	if span.y > cutoff - FINISH_MARGIN:
		problems.append("runs into the finish run-in (%.0f)" % span.y)
	if bool((KINDS[kind] as Dictionary).get("sparse", false)):
		problems.append_array(_fog_problems(span, planned, cutoff))
	if not is_hazardous(kind):
		return problems
	for event in planned:
		var distance := float(event.get("course_distance", INF))
		if distance > cutoff:
			continue
		var extent := event_extent(event)
		var margin := float((KINDS[kind] as Dictionary).get("margin", EVENT_MARGIN))
		if extent.y + margin > span.x and extent.x - margin < span.y:
			problems.append("%s at %.0f" % [str(event.get("id", event.get("kind", ""))), distance])
	for star in stars:
		var star_distance := star.x - 180.0
		if star_distance + STAR_MARGIN > span.x and star_distance - STAR_MARGIN < span.y:
			problems.append("star at %.0f" % star_distance)
	if surface.is_valid():
		var critical := critical_range_of(feature)
		var needed := float(MIN_LANE_CLEARANCE.get(kind, 0.0))
		var x := critical.x
		while x <= critical.y:
			var clearance := float(surface.call(180.0 + x, false)) - float(surface.call(180.0 + x, true))
			if clearance < needed:
				problems.append("narrow lane (%.0f) at %.0f" % [clearance, x])
				break
			x += 40.0
	return problems

## Gaps between consecutive generated events (extent to extent, 0 when they
## overlap), over the whole stage.
static func event_gaps(planned: Array, cutoff: float) -> Array[float]:
	var extents: Array[Vector2] = []
	for event in planned:
		if float(event.get("course_distance", INF)) <= cutoff:
			extents.append(event_extent(event))
	extents.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var gaps: Array[float] = []
	for index in range(1, extents.size()):
		gaps.append(maxf(extents[index].x - extents[index - 1].y, 0.0))
	return gaps

## The smallest gap allowed between generated events inside fog.
static func fog_min_gap(planned: Array, cutoff: float) -> float:
	var gaps := event_gaps(planned, cutoff)
	if gaps.is_empty():
		return 0.0
	gaps.sort()
	return gaps[int(float(gaps.size()) * FOG_GAP_PERCENTILE)] * FOG_GAP_FACTOR

static func _fog_problems(span: Vector2, planned: Array, cutoff: float) -> Array[String]:
	var problems: Array[String] = []
	var minimum := fog_min_gap(planned, cutoff)
	var extents: Array[Vector2] = []
	for event in planned:
		if float(event.get("course_distance", INF)) > cutoff:
			continue
		var extent := event_extent(event)
		if extent.y >= span.x and extent.x <= span.y:
			extents.append(extent)
	extents.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for index in range(1, extents.size()):
		var gap := extents[index].x - extents[index - 1].y
		if gap < minimum:
			problems.append("fog over a tight gap (%.0f < %.0f) at %.0f" % [gap, minimum, extents[index].x])
	return problems

## Features of one stage must not crowd each other either.
static func overlaps(features: Array) -> Array[String]:
	var problems: Array[String] = []
	for i in range(features.size()):
		for j in range(i + 1, features.size()):
			var a: Dictionary = features[i]
			var b: Dictionary = features[j]
			var sa := span_of(a)
			var sb := span_of(b)
			var margin := FEATURE_MARGIN if (is_hazardous(str(a.kind)) or is_hazardous(str(b.kind))) else 0.0
			if sa.y + margin > sb.x and sb.y + margin > sa.x:
				problems.append("%s at %.0f overlaps %s at %.0f" % [a.kind, a.at, b.kind, b.at])
	return problems

## Free stretches of a stage (course distance) where a feature with this span
## length would be fair, ordered by position. Used by the level tool.
static func quiet_windows(planned: Array, stars: PackedVector2Array, length_px: float) -> Array[Vector2]:
	var blocked: Array[Vector2] = []
	var cutoff := length_px - 1200.0
	for event in planned:
		if float(event.get("course_distance", INF)) > cutoff:
			continue
		var extent := event_extent(event)
		blocked.append(Vector2(extent.x - EVENT_MARGIN, extent.y + EVENT_MARGIN))
	for star in stars:
		blocked.append(Vector2(star.x - 180.0 - STAR_MARGIN, star.x - 180.0 + STAR_MARGIN))
	blocked.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var windows: Array[Vector2] = []
	var cursor := MIN_START
	var limit := cutoff - FINISH_MARGIN
	for block in blocked:
		if block.x > cursor:
			windows.append(Vector2(cursor, minf(block.x, limit)))
		cursor = maxf(cursor, block.y)
	if cursor < limit:
		windows.append(Vector2(cursor, limit))
	return windows
