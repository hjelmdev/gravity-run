extends Node2D
## Runtime side of one campaign stage inside the singleplayer scene (main.gd):
## stars, the finish line, "new hazard" callouts and, on a boss stage, the
## boss script, its plates and its art. main.gd stays the simulation; this
## node only filters what main spawns and reports pickups and the finish.

## kind: "hazard", "star", "stage" or "boss"; texts are already translated.
signal callout(kind: String, heading: String, title: String, description: String)
signal stars_changed(collected: int, total: int)
signal boss_changed(hp: int, max_hp: int)

const GravityStarScript := preload("res://campaign/gravity_star.gd")
const FinishLineScript := preload("res://campaign/finish_line.gd")
const PressurePlateScript := preload("res://campaign/pressure_plate.gd")
const RullarenViewScript := preload("res://campaign/rullaren_view.gd")
const StalactiteViewScript := preload("res://campaign/stalactite_view.gd")
const GiantIcicleScript := preload("res://campaign/giant_icicle.gd")
const GhostKingViewScript := preload("res://campaign/ghost_king_view.gd")
const BossLanternScript := preload("res://campaign/boss_lantern.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const COURSE_START_X := 180.0
const STAR_COIN_CLEARANCE := 44.0

var level: CampaignLevel
## RullarenBoss or StalactiteBoss (same scheduling interface).
var boss
var star_mask := 0
var finished := false
var _stars: Array[Node2D] = []
var _finish_line: Node2D
var _boss_view: Node2D
var _plates: Array[Node2D] = []
var _icicles: Array[Node2D] = []
var _lanterns: Array[Node2D] = []
var _announced_hazards: Dictionary = {}
var _last_plate_distance := -INF
var _last_course_distance := 0.0

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
	elif level.is_boss():
		boss = RullarenBoss.new()
		boss.reset()
		_boss_view = RullarenViewScript.new() as Node2D
		_boss_view.name = "Rullaren"
		add_child(_boss_view)
		_add_plate_for_current()
	else:
		_place_finish_line(level.get_finish_world_x())

func _place_finish_line(world_x: float) -> void:
	_finish_line = FinishLineScript.new() as Node2D
	_finish_line.name = "FinishLine"
	_finish_line.position = Vector2(world_x, 0.0)
	add_child(_finish_line)

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
	if boss != null:
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
	if not events.is_empty() and is_instance_valid(_boss_view):
		_boss_view.call("notify_fired")
	return events

## Called for every event main actually spawns.
func on_event_spawned(event: Dictionary) -> void:
	if level == null or level.new_hazards.is_empty():
		return
	var hazard_id := str(event.get("id", ""))
	if hazard_id.is_empty() or _announced_hazards.has(hazard_id) or not level.new_hazards.has(hazard_id):
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
		"haunted_ghost": return "Ghosts float through one side: take the other"
		"haunted_chaser": return "It hunts you from behind: keep switching sides"
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
		"haunted_ghost": return "floating ghosts"
		"haunted_chaser": return "chasing ghost"
	return hazard_id.replace("_", " ")

## One physics tick. Collects stars with the same swept test as coins, drives
## the boss script and reports "finished" when the runner crosses the line.
func physics_tick(previous_rect: Rect2, final_rect: Rect2, lethal_fraction: float, runner_world_x: float, gravity_direction: int, grounded: bool) -> String:
	if level == null or finished:
		return ""
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
			boss_changed.emit(rullaren.hp, RullarenBoss.MAX_HP)
			callout.emit("boss", tr("Direct hit!"), tr("Rullaren speeds up"), tr("%d hits left") % rullaren.hp)
			_add_plate_for_current()
		"missed":
			callout.emit("boss", tr("Missed the plate"), tr("It comes around again"), tr("Be on the glowing side when you pass it"))
			_add_plate_for_current()
		"defeated":
			_boss_view.call("notify_defeated")
			boss_changed.emit(0, RullarenBoss.MAX_HP)
			callout.emit("boss", tr("Boss beaten"), tr("Rullaren is beaten!"), tr("Run to the finish"))
			_place_finish_line(COURSE_START_X + rullaren.finish_distance)

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
	if is_instance_valid(_finish_line):
		var x := _finish_line.position.x
		_finish_line.call("set_surfaces", float(surface_y_at.call(x, false)), float(surface_y_at.call(x, true)))
	for plate in _plates:
		if is_instance_valid(plate):
			plate.set("surface_y", float(surface_y_at.call(plate.position.x, bool(plate.get("on_ceiling")))))
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
		_boss_view.call("place", right, float(surface_y_at.call(right - 70.0, false)))

class CampaignServiceMath:
	static func count_bits(mask: int) -> int:
		var count := 0
		while mask > 0:
			count += mask & 1
			mask >>= 1
		return count
