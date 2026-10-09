extends Node2D
## Runtime side of one campaign stage inside the singleplayer scene (main.gd):
## stars, the finish line, "new hazard" callouts and, on a boss stage, the
## boss script, its plates and its art. main.gd stays the simulation; this
## node only filters what main spawns and reports pickups and the finish.

## kind: "hazard", "star", "stage" or "boss"; texts are already translated.
signal callout(kind: String, heading: String, title: String, description: String)
signal stars_changed(collected: int, total: int)
signal boss_changed(hp: int, max_hp: int)
## A scripted feature wants a sound (main.gd plays it when the sound exists).
signal feature_cue(sound: String, key: String)
## The runner touched a wisp: main adds the coins.
signal bonus_coins(amount: int)

const GravityStarScript := preload("res://campaign/gravity_star.gd")
const FinishLineScript := preload("res://campaign/finish_line.gd")
const FinishConfettiScript := preload("res://campaign/finish_confetti.gd")
const PressurePlateScript := preload("res://campaign/pressure_plate.gd")
const RullarenViewScript := preload("res://campaign/rullaren_view.gd")
const MagmaWormViewScript := preload("res://campaign/magma_worm_view.gd")
const SnowGiantViewScript := preload("res://campaign/snow_giant_view.gd")
const StalactiteViewScript := preload("res://campaign/stalactite_view.gd")
const GiantIcicleScript := preload("res://campaign/giant_icicle.gd")
const GhostKingViewScript := preload("res://campaign/ghost_king_view.gd")
const BossLanternScript := preload("res://campaign/boss_lantern.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CaveDarknessScript := preload("res://campaign/cave_darkness.gd")
const CaveCrystalsScript := preload("res://campaign/cave_crystals.gd")
const CaveInDustScript := preload("res://campaign/cave_in_dust.gd")
const ForestFogScript := preload("res://campaign/forest_fog.gd")
const AshRainScript := preload("res://campaign/ash_rain.gd")
const WispScript := preload("res://campaign/wisp.gd")
const COURSE_START_X := 180.0
## Rullaren's thrown barrels: the throw covers this much course distance
## (about 0.3 s of running), then the barrel is an ordinary obstacle. Views
## narrower than the minimum keep the old spawn so a barrel never appears near
## the runner.
const THROW_FLIGHT_DISTANCE := 150.0
const THROW_MIN_VIEW_WIDTH := 700.0
const STAR_COIN_CLEARANCE := 44.0

var level: CampaignLevel
## RullarenBoss or StalactiteBoss (same scheduling interface).
var boss
var star_mask := 0
var finished := false
## Tests turn this off to run a stage with its scripted features alone.
var generated_events_enabled := true
var _stars: Array[Node2D] = []
var _finish_line: Node2D
var _confetti: Node2D
var _view_left := 0.0
var _view_size := Vector2(960.0, 540.0)
var _boss_view: Node2D
var _plates: Array[Node2D] = []
var _icicles: Array[Node2D] = []
var _lanterns: Array[Node2D] = []
var _announced_hazards: Dictionary = {}
var _last_plate_distance := -INF
var _last_course_distance := 0.0
var _thrown_barrels: Array[Dictionary] = []
var _throw_serial := 0
## Feature events not yet handed to main, ordered by course distance.
var _feature_events: Array[Dictionary] = []
var _cued_features: Dictionary = {}
var _dust_lines: Array[Node2D] = []
var _darkness: CaveDarkness
var _crystals: CaveCrystals
var _fog: ForestFog
var _ash: AshRain
var _runner_x := 0.0
## Wisps: {feature, node, collected, y} per wisp feature. The lane history is
## one entry per physics tick (the runner's gravity direction).
var _wisps: Array[Dictionary] = []
var _lane_history: Array[int] = []
var _surface_y_at := Callable()

func setup(stage: CampaignLevel) -> void:
	level = stage
	star_mask = 0
	finished = false
	for index in range(level.stars.size()):
		var star := GravityStarScript.new() as Node2D
		star.set("star_index", index)
		star.position = level.stars[index]
		star.name = "GravityStar%d" % index
		add_child(star)
		_stars.append(star)
	if level.is_boss() and level.boss_id == &"ghost_king":
		boss = GhostKingBoss.new()
		boss.reset()
		_boss_view = GhostKingViewScript.new() as Node2D
		_boss_view.name = "GhostKing"
		add_child(_boss_view)
		_add_lantern_for_current()
	elif level.is_boss() and level.boss_id == &"stalactite":
		boss = StalactiteBoss.new()
		boss.reset()
		_boss_view = StalactiteViewScript.new() as Node2D
		_boss_view.name = "StalactiteGiant"
		add_child(_boss_view)
		_add_icicle_for_current()
	elif level.is_boss() and level.boss_id == &"snow_giant":
		boss = SnowGiantBoss.new()
		boss.reset()
		_boss_view = SnowGiantViewScript.new() as Node2D
		_boss_view.name = "SnowGiant"
		add_child(_boss_view)
		_add_plate_for_current()
	elif level.is_boss() and level.boss_id == &"magma_worm":
		boss = MagmaWormBoss.new()
		boss.reset()
		_boss_view = MagmaWormViewScript.new() as Node2D
		_boss_view.name = "MagmaWorm"
		add_child(_boss_view)
		_add_plate_for_current()
	elif level.is_boss():
		boss = RullarenBoss.new()
		boss.reset()
		_boss_view = RullarenViewScript.new() as Node2D
		_boss_view.name = "Rullaren"
		add_child(_boss_view)
		_add_plate_for_current()
	else:
		_place_finish_line(level.get_finish_world_x())
		_setup_features()

func _setup_features() -> void:
	_feature_events.clear()
	_cued_features.clear()
	var dark_sections: Array[Vector2] = []
	var fog_sections: Array[Vector2] = []
	var ash_sections: Array[Vector2] = []
	var ash_style := "ash"
	for feature in level.features:
		var kind := str(feature.get("kind", ""))
		if not CampaignFeatures.is_known(kind):
			continue
		for event in CampaignFeatures.events_of(feature):
			_feature_events.append(event)
		if kind == "darkness":
			dark_sections.append(Vector2(float(feature.at), float(feature.at) + CampaignFeatures.length_of(feature)))
		elif kind == "fog":
			fog_sections.append(Vector2(float(feature.at), float(feature.at) + CampaignFeatures.length_of(feature)))
		elif kind == "ash" or kind == "snowstorm":
			ash_style = "snow" if kind == "snowstorm" else "ash"
			ash_sections.append(Vector2(float(feature.at), float(feature.at) + CampaignFeatures.length_of(feature)))
		elif kind == "wisp":
			var wisp := WispScript.new() as Node2D
			wisp.name = "Wisp%d" % _wisps.size()
			wisp.visible = false
			add_child(wisp)
			_wisps.append({"feature": feature, "node": wisp, "collected": false, "y": 0.0, "x": 0.0, "previous": Vector2(INF, INF), "position": Vector2(INF, INF)})
		elif kind == "cave_in" or kind == "avalanche":
			var dust := CaveInDustScript.new() as Node2D
			dust.name = "CaveInDust%d" % _dust_lines.size()
			dust.set("snowy", kind == "avalanche")
			var first := COURSE_START_X + float(feature.at)
			var last := first + float(CampaignFeatures.rock_count(feature) - 1) * CampaignFeatures.ROCK_SPACING
			dust.call("configure", first - 50.0, last + 50.0)
			add_child(dust)
			_dust_lines.append(dust)
	_feature_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.course_distance) < float(b.course_distance))
	if not ash_sections.is_empty():
		_ash = AshRainScript.new() as AshRain
		_ash.name = "AshRain"
		_ash.style = ash_style
		_ash.call("setup", ash_sections, level.seed_value)
		add_child(_ash)
	if not fog_sections.is_empty():
		_fog = ForestFogScript.new() as ForestFog
		_fog.name = "ForestFog"
		_fog.call("setup", fog_sections)
		add_child(_fog)
	if not dark_sections.is_empty():
		_crystals = CaveCrystalsScript.new() as CaveCrystals
		_crystals.name = "CaveCrystals"
		_crystals.call("setup", dark_sections, level.seed_value)
		add_child(_crystals)
		_darkness = CaveDarknessScript.new() as CaveDarkness
		_darkness.name = "CaveDarkness"
		_darkness.call("setup", dark_sections, _crystals)
		add_child(_darkness)

func _place_finish_line(world_x: float) -> void:
	_finish_line = FinishLineScript.new() as Node2D
	_finish_line.name = "FinishLine"
	_finish_line.position = Vector2(world_x, 0.0)
	add_child(_finish_line)

## The runner crossed the line: confetti from the flag across the screen.
func celebrate() -> void:
	if not is_instance_valid(_confetti):
		_confetti = FinishConfettiScript.new() as Node2D
		_confetti.name = "FinishConfetti"
		add_child(_confetti)
	var line_x := _finish_line.position.x if is_instance_valid(_finish_line) else _view_left + _view_size.x * 0.3
	_confetti.position = Vector2(_view_left, 0.0)
	_confetti.call("burst", Vector2(line_x - _view_left, _view_size.y * 0.5), _view_size)

func get_boss_max_hp() -> int:
	return int(boss.call("get_max_hp")) if boss != null else 0

func get_star_total() -> int:
	return level.stars.size() if level != null else 0

func get_star_count() -> int:
	return CampaignServiceMath.count_bits(star_mask)

func get_finish_world_x() -> float:
	if level == null:
		return INF
	if boss != null:
		return COURSE_START_X + boss.finish_distance if boss.finish_distance >= 0.0 else INF
	return level.get_finish_world_x()

## Progress toward the flag, 0..1 (boss stages report the boss instead).
func get_progress(course_distance: float) -> float:
	if level == null or boss != null or level.length_px <= 0.0:
		return 0.0
	return clampf(course_distance / level.length_px, 0.0, 1.0)

## Generated encounters only on normal stages, and none in the calm run-in to
## the finish line.
func allows_event(event: Dictionary) -> bool:
	if level == null:
		return true
	if boss != null or not generated_events_enabled:
		return false
	return float(event.get("course_distance", 0.0)) <= level.get_hazard_cutoff_distance()

func allows_coin(world_x: float, world_y: float) -> bool:
	if level == null:
		return true
	if boss != null:
		return false
	if world_x - COURSE_START_X > level.get_hazard_cutoff_distance():
		return false
	for star_position in level.stars:
		if Vector2(world_x, world_y).distance_to(star_position) < STAR_COIN_CLEARANCE:
			return false
	return true

func pop_boss_events(spawn_line_distance: float) -> Array[Dictionary]:
	if boss == null:
		return []
	var events: Array[Dictionary] = boss.pop_events_until(spawn_line_distance)
	if is_instance_valid(_boss_view):
		for event in events:
			# Barrels make the drum jerk when they are thrown, not when planned.
			if str(event.get("kind", "")) != "barrels" or not (boss is RullarenBoss) or _view_size.x < THROW_MIN_VIEW_WIDTH:
				_boss_view.call("notify_fired")
				break
	return events

## Rullaren only. Holds a barrel that main would have spawned at the screen
## edge: spec has x (its spawn x), course_distance (when it would have spawned),
## height, speed and spiked. Returns false when the barrel should spawn at once.
func queue_thrown_barrel(spec: Dictionary) -> bool:
	if not (boss is RullarenBoss) or not is_instance_valid(_boss_view) or _view_size.x < THROW_MIN_VIEW_WIDTH:
		return false
	var speed := maxf(float(spec.speed), 1.0)
	var hatch_x := _view_size.x - RullarenViewScript.HATCH_FROM_VIEW_RIGHT
	# Spawned at world x on course distance c0, the barrel would stand at world
	# x - (speed - 1) * (c - c0) on course distance c, i.e. at screen x
	# x - (speed - 1) * (c - c0) - c. It reaches the hatch at this c:
	spec["release"] = (float(spec.x) + (speed - 1.0) * float(spec.course_distance) - hatch_x) / speed
	spec["speed"] = speed
	spec["thrown"] = false
	_throw_serial += 1
	spec["id"] = _throw_serial
	_thrown_barrels.append(spec)
	return true

## Once per tick with the runner's course distance. Starts the throws of the
## barrels that reached the hatch and returns the ones that landed, with x on
## the path they would have rolled today, to be spawned as normal barrels.
func update_thrown_barrels(course_distance: float) -> Array[Dictionary]:
	var landed: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for spec in _thrown_barrels:
		if not bool(spec.thrown) and course_distance >= float(spec.release):
			spec["thrown"] = true
			if is_instance_valid(_boss_view):
				_boss_view.call("start_throw", spec)
			SfxController.play_event("rullaren_throw", "campaign|rullaren_throw|%d" % int(spec.id), true)
		if bool(spec.thrown) and course_distance >= float(spec.release) + THROW_FLIGHT_DISTANCE:
			var travelled := course_distance - float(spec.course_distance)
			var radius := HazardRules.barrel_radius(54.0, float(spec.height))
			if is_instance_valid(_boss_view):
				_boss_view.call("end_throw", int(spec.id))
			landed.append({"x": float(spec.x) - (float(spec.speed) - 1.0) * travelled, "height": spec.height, "speed": spec.speed, "spiked": spec.spiked, "roll": -(float(spec.speed) - 1.0) * travelled / radius})
		else:
			waiting.append(spec)
	_thrown_barrels = waiting
	return landed
## Scripted feature events whose time has come: either the spawn line reached
## them, or they need to exist earlier ("early_lead", e.g. rocks that wake up
## long before they land). Main spawns them like boss events.
func pop_feature_events(course_distance: float, spawn_line_distance: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	if _feature_events.is_empty():
		return ready
	var remaining: Array[Dictionary] = []
	for event in _feature_events:
		var at := float(event.course_distance)
		if spawn_line_distance >= at or course_distance + float(event.get("early_lead", 0.0)) >= at:
			ready.append(event)
		else:
			remaining.append(event)
	_feature_events = remaining
	return ready

## Called for every event main actually spawns.
func on_event_spawned(event: Dictionary) -> void:
	if level == null:
		return
	# Scripted features announce their kind (the first swarm, the first cave-in),
	# generated events their profile id.
	var hazard_id := str(event.get("feature", event.get("id", "")))
	if hazard_id.is_empty() or _announced_hazards.has(hazard_id):
		return
	if not (level.new_hazards.has(hazard_id) or level.new_features.has(hazard_id)):
		return
	_announced_hazards[hazard_id] = true
	callout.emit("hazard", tr("New hazard"), _sentence_case(tr(hazard_display_name(hazard_id))), tr(hazard_tip(hazard_id)))

static func _sentence_case(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)

## One-line hint shown with the "New hazard" banner.
static func hazard_tip(hazard_id: String) -> String:
	match hazard_id:
		"spike_group": return "Flip to the other side to pass them"
		"block": return "A wall in your lane: switch sides in time"
		"floor_gap", "ceiling_gap": return "No ground there: run on the other side"
		"barrel_chain": return "They roll at you: get off the floor"
		"terrain_step": return "Steps stop you: flip over them"
		"terrain_slope": return "The track tilts: keep your footing"
		"falling_rock": return "Watch the warning and leave the floor"
		"saw_blade": return "It moves along the surface: time your flip"
		"cave_icicle": return "It cracks loose and falls: leave the floor below it"
		"cave_in": return "Dust in the ceiling: the rocks come down, so run on the ceiling"
		"avalanche": return "Snow trickles down: the avalanche hits the floor, so run on the ceiling"
		"ghost_hand": return "A purple glow in one lane: a hand reaches out, so take the other"
		"bat_swarm": return "They sweep along one side: be on the other"
		"haunted_ghost": return "Ghosts float through one side: take the other"
		"haunted_chaser": return "It hunts you from behind: keep switching sides"
		"lava_crack": return "Glowing cracks burn: run on the other side"
		"lava_volcano": return "It erupts from the floor: be on the ceiling"
		"lava_tidal_pool": return "The lava rises: get off the floor in time"
		"ember_bomb": return "A red ring in one lane: an ember bomb lands there, so take the other"
	return ""

static func hazard_display_name(hazard_id: String) -> String:
	match hazard_id:
		"spike_group": return "spikes"
		"block": return "blocks"
		"floor_gap": return "hole in the floor"
		"ceiling_gap": return "hole in the ceiling"
		"barrel_chain": return "rolling barrels"
		"terrain_step": return "steps"
		"terrain_slope": return "slopes"
		"falling_rock": return "falling rock"
		"saw_blade": return "saw blade"
		"cave_icicle": return "icicles"
		"cave_in": return "cave-in"
		"avalanche": return "avalanche"
		"ghost_hand": return "ghost hands"
		"bat_swarm": return "bat swarm"
		"haunted_ghost": return "floating ghosts"
		"haunted_chaser": return "chasing ghost"
		"lava_crack": return "lava cracks"
		"lava_volcano": return "volcanoes"
		"lava_tidal_pool": return "lava pools"
		"ember_bomb": return "ember bombs"
	return hazard_id.replace("_", " ")

## One physics tick. Collects stars with the same swept test as coins, drives
## the boss script and reports "finished" when the runner crosses the line.
func physics_tick(previous_rect: Rect2, final_rect: Rect2, lethal_fraction: float, runner_world_x: float, gravity_direction: int, grounded: bool) -> String:
	if level == null or finished:
		return ""
	_runner_x = runner_world_x
	_cue_features(runner_world_x - COURSE_START_X)
	var displacement := final_rect.position - previous_rect.position
	for star in _stars:
		if not is_instance_valid(star) or bool(star.call("is_collected")):
			continue
		var fraction := HazardRules.swept_rect_circle_fraction(previous_rect, displacement, star.global_position, GravityStarScript.RADIUS)
		if fraction >= 0.0 and fraction < lethal_fraction - 0.000001:
			star.call("collect")
			star_mask |= 1 << int(star.get("star_index"))
			stars_changed.emit(get_star_count(), get_star_total())
			callout.emit("star", tr("Gravity star"), "%d / %d" % [get_star_count(), get_star_total()], "")
	_last_course_distance = runner_world_x - COURSE_START_X
	if not _wisps.is_empty():
		_tick_wisps(previous_rect, final_rect, lethal_fraction, runner_world_x - COURSE_START_X, gravity_direction)
	if boss != null and lethal_fraction > 1.0:
		if boss is GhostKingBoss:
			_tick_ghost_king(runner_world_x - COURSE_START_X, gravity_direction)
		elif boss is StalactiteBoss:
			if _tick_stalactite(runner_world_x - COURSE_START_X, gravity_direction):
				return "caught"
		else:
			_tick_boss(runner_world_x - COURSE_START_X, gravity_direction, grounded)
	if lethal_fraction > 1.0 and runner_world_x >= get_finish_world_x():
		finished = true
		return "finished"
	return ""

## Wisps float ahead of the runner, drift back through the runner's place and
## copy the runner's lane 0.8 s late. Position and pickup use only the course
## distance and the lane history, so a run is the same every time.
func _tick_wisps(previous_rect: Rect2, final_rect: Rect2, lethal_fraction: float, course_distance: float, gravity_direction: int) -> void:
	_lane_history.append(gravity_direction)
	var tick := _lane_history.size() - 1
	var lane := _lane_history[maxi(tick - CampaignFeatures.WISP_DELAY_TICKS, 0)]
	for wisp in _wisps:
		var offset := CampaignFeatures.wisp_offset(wisp.feature, course_distance)
		if offset == INF:
			wisp.position = Vector2(INF, INF)
			wisp.previous = Vector2(INF, INF)
			continue
		var floor_y := float(_surface_y_at.call(COURSE_START_X + course_distance + offset, false)) if _surface_y_at.is_valid() else 460.0
		var ceiling_y := float(_surface_y_at.call(COURSE_START_X + course_distance + offset, true)) if _surface_y_at.is_valid() else 80.0
		var target_y := floor_y - 30.0 if lane > 0 else ceiling_y + 30.0
		var y := float(wisp.y)
		y = target_y if float(wisp.position.x) == INF else lerpf(y, target_y, 0.14)
		wisp.y = y
		wisp.previous = wisp.position
		wisp.position = Vector2(_runner_x + offset, y)
		if bool(wisp.collected) or lethal_fraction <= 1.0:
			continue
		var start: Vector2 = wisp.previous if float(wisp.previous.x) != INF else wisp.position
		var relative: Vector2 = (final_rect.position - previous_rect.position) - (wisp.position - start)
		var fraction := HazardRules.swept_rect_circle_fraction(previous_rect, relative, start, Wisp.RADIUS)
		if fraction >= 0.0:
			wisp.collected = true
			(wisp.node as Wisp).collect()
			bonus_coins.emit(CampaignFeatures.WISP_BONUS_COINS)
			callout.emit("star", tr("Wisp caught"), tr("+%d coins") % CampaignFeatures.WISP_BONUS_COINS, "")

## The rumble of a cave-in starts when its first rock wakes up.
func _cue_features(course_distance: float) -> void:
	for feature in level.features:
		var kind := str(feature.get("kind", ""))
		if kind != "cave_in" and kind != "avalanche":
			continue
		var at := float(feature.at)
		var key := "%s|%.0f" % [kind, at]
		if course_distance >= at - CampaignFeatures.ROCK_TRIGGER_LEAD and course_distance < at + 400.0 and not _cued_features.has(key):
			_cued_features[key] = true
			feature_cue.emit("cave_in_rumble", key)

func _tick_boss(course_distance: float, gravity_direction: int, grounded: bool) -> void:
	var rullaren := boss as RullarenBoss
	var plate_index := _plates.size() - 1
	var result: String = rullaren.observe_runner(course_distance, gravity_direction, grounded)
	if result.is_empty():
		return
	if plate_index >= 0 and is_instance_valid(_plates[plate_index]):
		_plates[plate_index].call("set_state", "hit" if result in ["hit", "defeated"] else "missed")
	match result:
		"hit":
			_boss_view.call("notify_hit", rullaren.hp)
			if boss is MagmaWormBoss or boss is SnowGiantBoss:
				SfxController.play_event("magma_roar", "campaign|worm_roar|%d" % rullaren.hp, true)
			boss_changed.emit(rullaren.hp, RullarenBoss.MAX_HP)
			callout.emit("boss", tr("Direct hit!"), _boss_hit_line(), tr("%d hits left") % rullaren.hp)
			_add_plate_for_current()
		"missed":
			callout.emit("boss", tr("Missed the plate"), tr("It comes around again"), tr("Be on the glowing side when you pass it"))
			_add_plate_for_current()
		"defeated":
			_boss_view.call("notify_defeated")
			boss_changed.emit(0, RullarenBoss.MAX_HP)
			callout.emit("boss", tr("Boss beaten"), _boss_beaten_line(), tr("Run to the finish"))
			_place_finish_line(COURSE_START_X + rullaren.finish_distance)

func _boss_hit_line() -> String:
	if boss is MagmaWormBoss:
		return tr("The worm grows angrier")
	if boss is SnowGiantBoss:
		return tr("The giant stamps in rage")
	return tr("Rullaren speeds up")

func _boss_beaten_line() -> String:
	if boss is MagmaWormBoss:
		return tr("Magmaormen is beaten!")
	if boss is SnowGiantBoss:
		return tr("The Snow Giant is beaten!")
	return tr("Rullaren is beaten!")

## Stalaktitjätten: true when its dive caught the runner.
func _tick_stalactite(course_distance: float, gravity_direction: int) -> bool:
	var bat := boss as StalactiteBoss
	var icicle_index := _icicles.size() - 1
	var icicle: Node2D = _icicles[icicle_index] if icicle_index >= 0 and is_instance_valid(_icicles[icicle_index]) else null
	var result := bat.observe_runner(course_distance, gravity_direction, true)
	match result:
		"warning":
			_boss_view.call("notify_warning", bool(bat.dive.locked_ceiling), COURSE_START_X + float(bat.dive.distance) - StalactiteBoss.ARRIVE_LEAD)
			SfxController.play_event("cave_bat_screech", "campaign|bat_warning|%d" % int(bat.dive.distance), true)
		"caught":
			_boss_view.call("notify_dive", false)
			return true
		"hit", "defeated":
			_boss_view.call("notify_dive", true)
			if icicle != null:
				icicle.call("shatter")
			SfxController.play_event("cave_icicle_shatter", "campaign|icicle_shatter|%d" % int(bat.dive.distance), true)
			_boss_view.call("notify_hit", bat.hp)
			boss_changed.emit(bat.hp, StalactiteBoss.MAX_HP)
			if result == "hit":
				callout.emit("boss", tr("Direct hit!"), tr("The giant gets angrier"), tr("%d hits left") % bat.hp)
				_add_icicle_for_current()
			else:
				_boss_view.call("notify_defeated")
				callout.emit("boss", tr("Boss beaten"), tr("The Stalactite Giant is beaten!"), tr("Run to the finish"))
				_place_finish_line(COURSE_START_X + bat.finish_distance)
		"missed":
			_boss_view.call("notify_dive", false)
			if icicle != null:
				icicle.call("fade_out")
			callout.emit("boss", tr("It dived at the wrong side"), tr("The icicle comes back"), tr("Wait on the icicle's side, then flip away"))
			_add_icicle_for_current()
	return false

func _tick_ghost_king(course_distance: float, gravity_direction: int) -> void:
	var king := boss as GhostKingBoss
	var lantern_index := _lanterns.size() - 1
	var lantern: Node2D = _lanterns[lantern_index] if lantern_index >= 0 and is_instance_valid(_lanterns[lantern_index]) else null
	var result := king.observe_runner(course_distance, gravity_direction, true)
	match result:
		"fire":
			_boss_view.call("notify_fired")
		"hit", "defeated":
			if lantern != null:
				lantern.call("flare")
			SfxController.play_event("lantern_chime", "campaign|lantern|%d" % int(king.lantern.distance), true)
			_boss_view.call("notify_hit", king.hp)
			boss_changed.emit(king.hp, GhostKingBoss.MAX_HP)
			if result == "hit":
				callout.emit("boss", tr("Caught in the light!"), tr("The Ghost King follows faster"), tr("%d hits left") % king.hp)
				_add_lantern_for_current()
			else:
				_boss_view.call("notify_defeated")
				callout.emit("boss", tr("Boss beaten"), tr("The Ghost King is beaten!"), tr("Run to the finish"))
				_place_finish_line(COURSE_START_X + king.finish_distance)
		"missed":
			if lantern != null:
				lantern.call("fade_out")
			SfxController.play_event("ghost_king_laugh", "campaign|king_laugh|%d" % int(king.lantern.distance), true)
			callout.emit("boss", tr("He slipped past the lantern"), tr("Another lantern comes"), tr("Be on its side, then flip away just before it"))
			_add_lantern_for_current()

func _add_lantern_for_current() -> void:
	var king := boss as GhostKingBoss
	if king == null or king.lantern.is_empty():
		return
	var lantern := BossLanternScript.new() as Node2D
	lantern.name = "BossLantern%d" % _lanterns.size()
	lantern.set("on_ceiling", bool(king.lantern.ceiling))
	lantern.position = Vector2(COURSE_START_X + float(king.lantern.distance), 0.0)
	add_child(lantern)
	_lanterns.append(lantern)

func _add_icicle_for_current() -> void:
	var bat := boss as StalactiteBoss
	if bat == null or bat.dive.is_empty():
		return
	var icicle := GiantIcicleScript.new() as Node2D
	icicle.name = "GiantIcicle%d" % _icicles.size()
	icicle.set("on_ceiling", bool(bat.dive.ceiling))
	icicle.position = Vector2(COURSE_START_X + float(bat.dive.distance), 0.0)
	add_child(icicle)
	_icicles.append(icicle)
	_boss_view.call("set_icicle", icicle)

func _add_plate_for_current() -> void:
	var rullaren := boss as RullarenBoss
	if rullaren == null or rullaren.plate.is_empty():
		return
	var plate := PressurePlateScript.new() as Node2D
	plate.name = "PressurePlate%d" % _plates.size()
	plate.set("on_ceiling", bool(rullaren.plate.ceiling))
	plate.set("width", RullarenBoss.PLATE_WIDTH)
	plate.position = Vector2(COURSE_START_X + float(rullaren.plate.distance), 0.0)
	add_child(plate)
	_plates.append(plate)

## Keeps surface-attached art on the surfaces and the boss at the view edge.
func update_presentation(view_left: float, view_width: float, surface_y_at: Callable) -> void:
	_view_left = view_left
	_view_size = Vector2(view_width, _view_size.y)
	if is_instance_valid(_confetti):
		_confetti.position = Vector2(view_left, 0.0)
	if is_instance_valid(_finish_line):
		var x := _finish_line.position.x
		_finish_line.call("set_surfaces", float(surface_y_at.call(x, false)), float(surface_y_at.call(x, true)))
	for plate in _plates:
		if is_instance_valid(plate):
			plate.set("surface_y", float(surface_y_at.call(plate.position.x, bool(plate.get("on_ceiling")))))
	var runner_x := _runner_x
	_surface_y_at = surface_y_at
	if is_instance_valid(_ash):
		_ash.update_view(view_left, view_width, runner_x)
	for wisp in _wisps:
		var node := wisp.node as Wisp
		var render_offset := CampaignFeatures.wisp_offset(wisp.feature, view_left)
		node.visible = render_offset != INF and float(wisp.position.x) != INF
		if node.visible:
			node.position = Vector2(view_left + COURSE_START_X + render_offset, float(wisp.y))
	for dust in _dust_lines:
		if is_instance_valid(dust):
			dust.call("update_view", runner_x, float(surface_y_at.call(float(dust.get("x_from")), true)))
	if is_instance_valid(_crystals):
		_crystals.call("update_view", runner_x, surface_y_at)
	for lantern in _lanterns:
		if is_instance_valid(lantern):
			lantern.call("set_surfaces", float(surface_y_at.call(lantern.position.x, false)), float(surface_y_at.call(lantern.position.x, true)))
	for icicle in _icicles:
		if is_instance_valid(icicle):
			icicle.call("set_surfaces", float(surface_y_at.call(icicle.position.x, false)), float(surface_y_at.call(icicle.position.x, true)))
	if is_instance_valid(_boss_view) and boss is GhostKingBoss:
		var king_edge := view_left + view_width - 10.0
		_boss_view.call("place", king_edge, float(surface_y_at.call(king_edge - 70.0, true)), float(surface_y_at.call(king_edge - 70.0, false)), (boss as GhostKingBoss).king_on_ceiling(_last_course_distance))
	elif is_instance_valid(_boss_view) and boss is StalactiteBoss:
		var edge := view_left + view_width - 10.0
		_boss_view.call("place", edge, float(surface_y_at.call(edge - 90.0, true)), float(surface_y_at.call(edge - 90.0, false)), view_left)
	elif is_instance_valid(_boss_view):
		var right := view_left + view_width - 10.0
		_boss_view.set("view_left", view_left)
		_boss_view.call("place", right, float(surface_y_at.call(right - 70.0, false)))

func has_darkness() -> bool:
	return is_instance_valid(_darkness) or is_instance_valid(_fog)

## Darkness: the hazards that are coming up, the stars and the passed crystals
## become lights, so nothing that can hurt is ever hidden. `hazards` is every
## node that can hurt or block (obstacles, holes, steps and slopes).
func update_darkness(view_left: float, view_width: float, runner_position: Vector2, hazards: Array, surface_y_at: Callable) -> void:
	if level == null or not has_darkness():
		return
	var overlay: Node2D = _darkness if is_instance_valid(_darkness) else _fog
	var course_distance := runner_position.x - COURSE_START_X
	var strength := CaveDarkness.strength_for(course_distance, overlay.sections) if overlay == _darkness else ForestFog.strength_for(course_distance, overlay.sections)
	if strength <= 0.001:
		overlay.call("update_view", view_left, view_width, runner_position, course_distance, PackedVector4Array())
		return
	var lights := PackedVector4Array()
	var ahead := runner_position.x + HAZARD_LIGHT_AHEAD
	for node in hazards:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var x: float = node.global_position.x
		if x < runner_position.x - 120.0 or x > ahead:
			continue
		lights.append_array(_hazard_lights(node, surface_y_at))
	for star in _stars:
		if is_instance_valid(star) and not bool(star.call("is_collected")) and star.global_position.x > view_left - 100.0 and star.global_position.x < view_left + view_width + 100.0:
			lights.append(Vector4(star.global_position.x, star.global_position.y, 110.0, 1.0))
	if is_instance_valid(_crystals):
		_crystals.call("collect_lights", view_left, view_width, lights)
	overlay.call("update_view", view_left, view_width, runner_position, course_distance, lights)

const HAZARD_LIGHT_AHEAD := 950.0

static func _hazard_lights(node: Node2D, surface_y_at: Callable) -> PackedVector4Array:
	var result := PackedVector4Array()
	var x := node.global_position.x
	if node.has_method("get_hitbox_rect"):
		var rect: Rect2 = node.call("get_hitbox_rect")
		if rect.size != Vector2.ZERO:
			result.append(Vector4(rect.get_center().x, rect.get_center().y, maxf(rect.size.x, rect.size.y) * 0.5 + 95.0, 1.0))
			return result
	if node.is_in_group("falling_rocks"):
		var event: Dictionary = node.get("event")
		var floor_y := float(event.get("floor_y", 460.0))
		result.append(Vector4(x, node.global_position.y, 130.0, 1.0))
		result.append(Vector4(x, floor_y - 60.0, 120.0, 1.0))
		return result
	if node.is_in_group("barrels"):
		result.append(Vector4(x, node.global_position.y - 30.0, 120.0, 1.0))
		return result
	if node.is_in_group("saw_blades") or node.is_in_group("ghost_hazards"):
		result.append(Vector4(x, node.global_position.y, 140.0, 1.0))
		return result
	# Holes, steps and slopes: light the whole lane height at their position.
	result.append(Vector4(x, float(surface_y_at.call(x, false)) - 20.0, 170.0, 1.0))
	result.append(Vector4(x, float(surface_y_at.call(x, true)) + 20.0, 170.0, 1.0))
	return result

class CampaignServiceMath:
	static func count_bits(mask: int) -> int:
		var count := 0
		while mask > 0:
			count += mask & 1
			mask >>= 1
		return count
