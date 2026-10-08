extends Node2D
## Runtime side of one campaign stage inside the singleplayer scene (main.gd):
## stars, the finish line, "new hazard" callouts and, on a boss stage, the
## boss script, its plates and its art. main.gd stays the simulation; this
## node only filters what main spawns and reports pickups and the finish.

signal callout(text: String, color: Color)
signal stars_changed(collected: int, total: int)
signal boss_changed(hp: int, max_hp: int)

const GravityStarScript := preload("res://campaign/gravity_star.gd")
const FinishLineScript := preload("res://campaign/finish_line.gd")
const PressurePlateScript := preload("res://campaign/pressure_plate.gd")
const RullarenViewScript := preload("res://campaign/rullaren_view.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const COURSE_START_X := 180.0
const STAR_COIN_CLEARANCE := 44.0
const CALLOUT_GOLD := Color("f5d45e")
const CALLOUT_TEAL := Color("42d6c5")
const CALLOUT_RED := Color("ff647c")

var level: CampaignLevel
var boss: RullarenBoss
var star_mask := 0
var finished := false
var _stars: Array[Node2D] = []
var _finish_line: Node2D
var _boss_view: Node2D
var _plates: Array[Node2D] = []
var _announced_hazards: Dictionary = {}
var _last_plate_distance := -INF

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
	if level.is_boss():
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
	var events := boss.pop_events_until(spawn_line_distance)
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
	callout.emit(tr("New: %s!") % tr(hazard_display_name(hazard_id)), CALLOUT_TEAL)

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
			callout.emit(tr("Gravity star %d/%d!") % [get_star_count(), get_star_total()], CALLOUT_GOLD)
	if boss != null and lethal_fraction > 1.0:
		_tick_boss(runner_world_x - COURSE_START_X, gravity_direction, grounded)
	if lethal_fraction > 1.0 and runner_world_x >= get_finish_world_x():
		finished = true
		return "finished"
	return ""

func _tick_boss(course_distance: float, gravity_direction: int, grounded: bool) -> void:
	var plate_index := _plates.size() - 1
	var result := boss.observe_runner(course_distance, gravity_direction, grounded)
	if result.is_empty():
		return
	if plate_index >= 0 and is_instance_valid(_plates[plate_index]):
		_plates[plate_index].call("set_state", "hit" if result in ["hit", "defeated"] else "missed")
	match result:
		"hit":
			_boss_view.call("notify_hit", boss.hp)
			boss_changed.emit(boss.hp, RullarenBoss.MAX_HP)
			callout.emit(tr("Direct hit! Rullaren speeds up"), CALLOUT_GOLD)
			_add_plate_for_current()
		"missed":
			callout.emit(tr("Missed the plate, it comes around again"), CALLOUT_RED)
			_add_plate_for_current()
		"defeated":
			_boss_view.call("notify_defeated")
			boss_changed.emit(0, RullarenBoss.MAX_HP)
			callout.emit(tr("Rullaren is beaten!"), CALLOUT_GOLD)
			_place_finish_line(COURSE_START_X + boss.finish_distance)

func _add_plate_for_current() -> void:
	if boss == null or boss.plate.is_empty():
		return
	var plate := PressurePlateScript.new() as Node2D
	plate.name = "PressurePlate%d" % _plates.size()
	plate.set("on_ceiling", bool(boss.plate.ceiling))
	plate.set("width", RullarenBoss.PLATE_WIDTH)
	plate.position = Vector2(COURSE_START_X + float(boss.plate.distance), 0.0)
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
	if is_instance_valid(_boss_view):
		var right := view_left + view_width - 10.0
		_boss_view.call("place", right, float(surface_y_at.call(right - 70.0, false)))

class CampaignServiceMath:
	static func count_bits(mask: int) -> int:
		var count := 0
		while mask > 0:
			count += mask & 1
			mask >>= 1
		return count
