extends RefCounted
class_name SharedCoinPlanner
## Deterministic, presentation-independent coin placement shared by both modes.

const CELL_WIDTH := 360.0
const COIN_ROW_MIN := 2
const COIN_ROW_MAX := 4
const COIN_RADIUS := 13.0
const SURFACE_OFFSET := 34.0
const COURSE_START_OFFSET := 1250.0
const MAX_PLANNED_COINS := 1600
const RISK_ROW_CHANCE := 0.24
const RISK_MIN_EVENT_LEAD := 1020.0
const RISK_MAX_EVENT_LEAD := 1250.0
const RISK_APPROACH_DISTANCE := 300.0
const RISK_EXIT_DISTANCE := 180.0
const RISK_MOVING_HAZARD_MARGIN := 120.0
const SurfaceIndexScript := preload("res://systems/course_surface_index.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var _seed := 0
var _revision := 1
var _density := 1.0
var _row := 0
var _planned_count := 0
var _next_x := 0.0
var _active := false

func reset(seed_value: int, start_x: float, revision: int = 1, density: float = 1.0) -> void:
	_seed = seed_value
	_revision = revision
	_density = clampf(density, 0.5, 2.0)
	_row = 0
	_planned_count = 0
	_next_x = start_x + COURSE_START_OFFSET
	_active = seed_value > 0 and is_finite(start_x)

## Adds only new fixed rows. Call with finalized hazard lookahead before spawning
## any returned row; viewport dimensions never enter this contract.
func extend(end_x: float, events: Array[Dictionary], floor_y: float, ceiling_y: float, max_coins: int = MAX_PLANNED_COINS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _active or end_x <= _next_x or (max_coins > 0 and _planned_count >= max_coins):
		return result
	var surface_index := SurfaceIndexScript.new()
	surface_index.configure(events, floor_y, ceiling_y)
	while _next_x + float(COIN_ROW_MAX - 1) * 38.0 <= end_x:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(hash("shared-coins:%d:%d:%d" % [_seed, _revision, _row])) & 0x7fffffff
		var risk_event: Dictionary = _find_risk_event(_next_x, events, surface_index) if _revision >= 2 and rng.randf() < RISK_ROW_CHANCE else {}
		var row_count := 3 if not risk_event.is_empty() else rng.randi_range(COIN_ROW_MIN, COIN_ROW_MAX)
		var lane := 0 if not risk_event.is_empty() and bool(risk_event.get("from_ceiling", false)) else (1 if not risk_event.is_empty() else rng.randi_range(0, 1))
		for index in range(row_count):
			if max_coins > 0 and _planned_count >= max_coins:
				_active = false
				break
			var coin_x := _next_x + float(index) * 38.0
			if coin_x >= end_x:
				continue
			var floor_info: Dictionary = surface_index.surface_at(coin_x, false)
			var ceiling_info: Dictionary = surface_index.surface_at(coin_x, true)
			if float(floor_info.y) - float(ceiling_info.y) < 190.0:
				continue
			if (lane == 0 and not bool(ceiling_info.get("supported", false))) or (lane == 1 and not bool(floor_info.get("supported", false))):
				continue
			var y := float(ceiling_info.y) + SURFACE_OFFSET if lane == 0 else float(floor_info.y) - SURFACE_OFFSET
			if _position_blocked(coin_x, y, events):
				continue
			var coin := {"entity_id": "coin_%d_%05d_%d" % [_revision, _row, index], "kind": "coin", "world_x": snappedf(coin_x, 0.01), "world_y": snappedf(y, 0.01), "radius": COIN_RADIUS, "value": 1, "cell": _row * 4 + index}
			if _revision >= 2:
				coin["formation"] = "risk" if not risk_event.is_empty() else "line"
				if not risk_event.is_empty():
					coin["risk_event_id"] = str(risk_event.get("event_id", ""))
			result.append(coin)
			_planned_count += 1
		_next_x += (CELL_WIDTH + rng.randf_range(120.0, 320.0)) / _density
		_row += 1
		if max_coins > 0 and _planned_count >= max_coins:
			_active = false
			break
	return result

static func plan(seed_value: int, start_x: float, end_x: float, events: Array[Dictionary], floor_y: float, ceiling_y: float, revision: int = 1, density: float = 1.0) -> Array[Dictionary]:
	var planner := SharedCoinPlanner.new()
	planner.reset(seed_value, start_x, revision, density)
	return planner.extend(end_x, events, floor_y, ceiling_y)

static func _position_blocked(x: float, y: float, events: Array[Dictionary]) -> bool:
	var coin_rect := Rect2(Vector2(x - COIN_RADIUS, y - COIN_RADIUS), Vector2(COIN_RADIUS * 2.0, COIN_RADIUS * 2.0))
	for event in events:
		var kind := str(event.get("kind", ""))
		var event_x := float(event.get("x", 0.0))
		var reach := maxf(float(event.get("width", 0.0)) * 0.5, float(event.get("count", 1)) * float(event.get("spacing", 0.0)) + 40.0)
		if absf(x - event_x) > reach + COIN_RADIUS:
			continue
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var top := float(event.get("y", 0.0)) - height if not bool(event.get("from_ceiling", false)) else float(event.get("y", 0.0))
			if coin_rect.intersects(Rect2(Vector2(event_x - width * 0.5, top), Vector2(width, height))):
				return true
		elif kind == "spikes":
			var triangles := HazardRules.spike_group_triangles(float(event.get("start_x", event_x)), float(event.get("y", 0.0)), int(event.get("count", 1)), float(event.get("spacing", 32.0)), 28.0, 32.0, bool(event.get("from_ceiling", false)))
			for triangle in triangles:
				if HazardRules.triangle_intersects_rect(triangle, coin_rect):
					return true
		elif kind == "rock":
			var corridor := Rect2(event_x - float(event.get("width", 90.0)) * 0.5 - COIN_RADIUS, float(event.get("ceiling_y", 80.0)), float(event.get("width", 90.0)) + COIN_RADIUS * 2.0, float(event.get("floor_y", 460.0)) - float(event.get("ceiling_y", 80.0)))
			if coin_rect.intersects(corridor):
				return true
		elif kind == "step":
			var low := minf(float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
			var high := maxf(float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
			if coin_rect.intersects(Rect2(Vector2(event_x - 2.0, low), Vector2(4.0, high - low))):
				return true
	return false

func _find_risk_event(row_start_x: float, events: Array[Dictionary], surface_index: RefCounted) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for event in events:
		var kind := str(event.get("kind", ""))
		if kind not in ["block", "spikes"]:
			continue
		var lead := float(event.get("x", 0.0)) - (row_start_x + 2.0 * 38.0)
		if lead < RISK_MIN_EVENT_LEAD or lead > RISK_MAX_EVENT_LEAD:
			continue
		if _risk_has_unmodeled_motion(row_start_x, events):
			continue
		if not _risk_support_corridor_clear(row_start_x, surface_index):
			continue
		var ceiling := bool(event.get("from_ceiling", false))
		var clear := true
		for index in range(3):
			var coin_x := row_start_x + float(index) * 38.0
			var surface: Dictionary = surface_index.surface_at(coin_x, ceiling)
			var floor_surface: Dictionary = surface_index.surface_at(coin_x, false)
			var ceiling_surface: Dictionary = surface_index.surface_at(coin_x, true)
			if not bool(surface.get("supported", false)) or not bool(floor_surface.get("supported", false)) or not bool(ceiling_surface.get("supported", false)) or float(floor_surface.y) - float(ceiling_surface.y) < 190.0:
				clear = false
				break
			var y := float(surface.y) + SURFACE_OFFSET if ceiling else float(surface.y) - SURFACE_OFFSET
			if _position_blocked(coin_x, y, events):
				clear = false
				break
		if clear:
			candidates.append(event)
	if candidates.is_empty():
		return {}
	# The seed/cell RNG supplies variation; sorting makes the choice independent
	# of caller event-array order and stable between SP streaming and MP manifests.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("event_id", "")) < str(b.get("event_id", ""))
	)
	return candidates[0]

## Risk rows ask the runner to switch lanes around a moving coin line. Do not
## place one where a moving hazard could overlap that transition window: its
## time-dependent route is not part of this planner's static placement proof.
func _risk_has_unmodeled_motion(row_start_x: float, events: Array[Dictionary]) -> bool:
	var corridor_left := row_start_x - RISK_APPROACH_DISTANCE
	var corridor_right := row_start_x + float(COIN_ROW_MAX - 1) * 38.0 + RISK_EXIT_DISTANCE
	for event in events:
		if str(event.get("kind", "")) not in ["barrels", "rock", "saw", "ghost"]:
			continue
		var center_x := float(event.get("x", 0.0))
		var half_width := maxf(float(event.get("width", 0.0)) * 0.5, float(event.get("count", 1)) * float(event.get("spacing", 0.0)) * 0.5 + 32.0)
		if center_x + half_width + RISK_MOVING_HAZARD_MARGIN >= corridor_left and center_x - half_width - RISK_MOVING_HAZARD_MARGIN <= corridor_right:
			return true
	return false

## Both supported lanes are required throughout approach, pickup, and the
## immediate exit. This is deliberately conservative around gaps and avoids
## assuming a later surface sample implies a traversable lane-change interval.
func _risk_support_corridor_clear(row_start_x: float, surface_index: RefCounted) -> bool:
	var corridor_left := row_start_x - RISK_APPROACH_DISTANCE
	var corridor_right := row_start_x + float(COIN_ROW_MAX - 1) * 38.0 + RISK_EXIT_DISTANCE
	var sample_x := corridor_left
	while sample_x <= corridor_right:
		var floor_surface: Dictionary = surface_index.surface_at(sample_x, false)
		var ceiling_surface: Dictionary = surface_index.surface_at(sample_x, true)
		if not bool(floor_surface.get("supported", false)) or not bool(ceiling_surface.get("supported", false)) or float(floor_surface.y) - float(ceiling_surface.y) < 190.0:
			return false
		sample_x += 64.0
	return true
