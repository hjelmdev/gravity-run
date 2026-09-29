extends RefCounted
class_name MultiplayerV2WorldSimulation

const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const LedgerScript := preload("res://systems/multiplayer_v2/v2_world_event_ledger.gd")

const TICK_RATE := 60.0
const FIXED_DELTA := 1.0 / TICK_RATE

var manifest: Resource
var tick := 0
var elapsed := 0.0
var barrels: Array[Dictionary] = []
var entity_ledger: MultiplayerV2WorldEventLedger = LedgerScript.new()
var _entity_by_event: Dictionary = {}
var _barrel_history: Dictionary = {}

func configure(course_manifest: Resource) -> String:
	if course_manifest == null or not course_manifest.has_method("validate"):
		return "manifest_missing"
	var error := str(course_manifest.call("validate"))
	if not error.is_empty():
		return error
	manifest = course_manifest
	tick = 0
	elapsed = 0.0
	barrels.clear()
	_barrel_history.clear()
	_entity_by_event.clear()
	var entities: Array[Dictionary] = []
	for event in manifest.events:
		var event_id := str(event.get("event_id", ""))
		if event_id.is_empty():
			continue
		var kind := str(event.get("kind", ""))
		if kind == "barrels":
			var count := clampi(int(event.get("count", 1)), 1, 6)
			var spacing := float(event.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
			var width := HazardRules.BARREL_WIDTH
			var height := float(event.get("height", width))
			var multiplier := maxf(float(event.get("motion_speed_multiplier", 1.0)), 1.0)
			var lead := float(event.get("spawn_lead_distance", 820.0))
			for index in range(count):
				var entity_id := "%s_%d" % [event_id, index]
				var barrel := {"entity_id": entity_id, "event_id": event_id, "incarnation": 1, "kind": "barrel", "x": float(event.get("x", 0.0)) + lead * (multiplier - 1.0) - float(count - 1) * spacing * 0.5 + float(index) * spacing, "y": float(event.get("y", manifest.initial_floor_y)), "width": width, "height": height, "motion_speed_multiplier": multiplier, "spawn_time": maxf(0.0, float(event.get("x", 0.0)) - lead - float(manifest.start_x)) / Motion.BASE_RUN_SPEED, "spawned": false, "fall_velocity": 0.0, "falling": false, "roll_angle": 0.0, "rotation": 0.0, "destroyed": false}
				barrels.append(barrel)
				entities.append({"entity_id": entity_id, "incarnation": 1, "kind": "barrel", "health": 1})
				_entity_by_event[entity_id] = {"kind": "barrel", "event_id": event_id}
		elif kind in ["block", "step"]:
			entities.append({"entity_id": event_id, "incarnation": 1, "kind": kind, "health": 1})
			_entity_by_event[event_id] = {"kind": kind, "event_id": event_id}
	entity_ledger.reset(entities)
	_barrel_history[0] = barrels.duplicate(true)
	return ""

func step_to(next_tick: int) -> bool:
	if manifest == null or next_tick != tick + 1:
		return false
	tick = next_tick
	elapsed = float(tick) * FIXED_DELTA
	for barrel in barrels:
		if bool(barrel.get("destroyed", false)):
			continue
		if not bool(barrel.get("spawned", false)):
			if elapsed < float(barrel.get("spawn_time", INF)):
				continue
			barrel.spawned = true
		var movement := Motion.BASE_RUN_SPEED * FIXED_DELTA
		var projected_x := float(barrel.x) - movement * (float(barrel.motion_speed_multiplier) - 1.0)
		var floor_info := surface_at(projected_x, false)
		HazardRules.advance_barrel(barrel, FIXED_DELTA, movement, float(floor_info.y), _surface_angle_at(projected_x, false), bool(floor_info.supported))
		_resolve_barrel_interactions(barrel)
	_barrel_history[tick] = barrels.duplicate(true)
	while _barrel_history.size() > 121:
		var oldest: int = int(_barrel_history.keys().min())
		_barrel_history.erase(oldest)
	return true

func surface_at(x: float, ceiling: bool) -> Dictionary:
	var y := float(manifest.initial_ceiling_y) if ceiling else float(manifest.initial_floor_y)
	var supported := true
	for event in manifest.events:
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				if x >= float(event.get("x", 0.0)):
					y = float(event.get("end_y", y))
			"slope":
				var start_x := float(event.get("start_x", 0.0))
				var end_x := float(event.get("end_x", start_x))
				if x >= start_x and x <= end_x and end_x > start_x:
					y = lerpf(float(event.get("start_y", y)), float(event.get("end_y", y)), (x - start_x) / (end_x - start_x))
				elif x > end_x:
					y = float(event.get("end_y", y))
			"gap":
				var start_x := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
				if x >= start_x and x <= start_x + float(event.get("width", 0.0)):
					supported = false
	return {"y": y, "supported": supported}

func player_contact(player_state: Dictionary) -> Dictionary:
	return _player_contact_against(player_state, barrels)

func player_contact_at(player_state: Dictionary, simulation_tick: int) -> Dictionary:
	if not _barrel_history.has(simulation_tick):
		return {"kind": "history_missing"}
	return _player_contact_against(player_state, _barrel_history[simulation_tick])

func _player_contact_against(player_state: Dictionary, barrel_state: Array) -> Dictionary:
	if manifest == null:
		return {}
	var width := Motion.SIZE.x
	var height := Motion.SIZE.y
	var rect := Rect2(Vector2(float(player_state.get("world_x", 0.0)) - width * 0.5, float(player_state.get("y", 0.0)) - height * 0.5), Vector2(width, height))
	for event in manifest.events:
		var kind := str(event.get("kind", ""))
		var event_id := str(event.get("event_id", ""))
		if kind in ["block", "step"] and not entity_ledger.is_active(event_id):
			continue
		if kind == "spikes":
			var triangles := HazardRules.spike_group_triangles(float(event.get("start_x", event.get("x", 0.0))), float(event.get("y", 0.0)), int(event.get("count", 1)), float(event.get("spacing", CourseGeneratorScript.SPIKE_GROUP_SPACING)), CourseGeneratorScript.SPIKE_WIDTH, CourseGeneratorScript.SPIKE_HEIGHT, bool(event.get("from_ceiling", false)))
			if HazardRules.player_impact(rect, "spikes", Rect2(), triangles) == HazardRules.PlayerImpact.LETHAL:
				return {"kind": "terminal", "reason": "spikes", "entity_id": event_id, "event_id": event_id}
		elif kind == "block":
			var block_height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - block_height if not bool(event.get("from_ceiling", false)) else edge_y
			var block_rect := Rect2(Vector2(float(event.get("x", 0.0)) - float(event.get("width", 48.0)) * 0.5, block_y), Vector2(float(event.get("width", 48.0)), block_height))
			if HazardRules.player_impact(rect, "block", block_rect) == HazardRules.PlayerImpact.LETHAL:
				return {"kind": "terminal", "reason": "block", "entity_id": event_id, "event_id": event_id}
		elif kind == "step":
			var step_rect := HazardRules.step_wall_rect(float(event.get("x", 0.0)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
			var blocked := HazardRules.player_impact(rect, "step", step_rect, [], Vector2.ZERO, 0.0, false, int(player_state.get("gravity_direction", 1)), bool(event.get("from_ceiling", false)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0))) == HazardRules.PlayerImpact.BLOCKED
			if blocked:
				return {"kind": "blocked", "reason": "step", "entity_id": event_id}
			if bool(event.get("spiked", false)):
				var triangles := HazardRules.step_spike_triangles(float(event.get("x", 0.0)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)), bool(event.get("from_ceiling", false)))
				if HazardRules.player_impact(rect, "spikes", Rect2(), triangles) == HazardRules.PlayerImpact.LETHAL:
					return {"kind": "terminal", "reason": "step_spikes", "entity_id": event_id, "event_id": event_id}
	for barrel in barrel_state:
		if not bool(barrel.get("spawned", false)) or bool(barrel.get("destroyed", false)) or not entity_ledger.is_active(str(barrel.get("entity_id", "")), int(barrel.get("incarnation", 1))):
			continue
		var center := HazardRules.barrel_center(Vector2(float(barrel.x), float(barrel.y)), float(barrel.width), float(barrel.height))
		var radius := HazardRules.barrel_radius(float(barrel.width), float(barrel.height))
		if HazardRules.player_impact(rect, "barrel", Rect2(), [], center, radius) == HazardRules.PlayerImpact.LETHAL:
			return {"kind": "shared_interaction", "reason": "barrel_contact", "entity_id": str(barrel.entity_id), "event_id": str(barrel.event_id), "incarnation": int(barrel.incarnation)}
	return {}

func apply_world_commit(commit: Dictionary) -> String:
	var result := entity_ledger.apply_commit(commit)
	if result not in ["applied", "duplicate"]:
		return result
	var entity_id := str(commit.get("entity_id", ""))
	if str(entity_ledger.entities.get(entity_id, {}).get("state", "")) == "destroyed":
		for barrel in barrels:
			if str(barrel.get("entity_id", "")) == entity_id:
				barrel.destroyed = true
		return result
	return result

func apply_baseline(value: Dictionary) -> bool:
	if not entity_ledger.restore_baseline(value):
		return false
	for barrel in barrels:
		var entity: Dictionary = entity_ledger.entities.get(str(barrel.entity_id), {})
		barrel.destroyed = str(entity.get("state", "active")) != "active"
	return true

func apply_deterministic_destruction(entity_id: String, simulation_tick: int) -> String:
	if not entity_ledger.is_active(entity_id):
		return "already_destroyed"
	var commit := {"world_revision": entity_ledger.revision + 1, "commit_id": "det-%s-%d" % [entity_id, simulation_tick], "entity_id": entity_id, "incarnation": 1, "action": "destroy", "effective_tick": simulation_tick, "reason": "deterministic_world_collision", "state_before": "active", "state_after": "destroyed"}
	return apply_world_commit(commit)

func state_snapshot() -> Dictionary:
	return {"tick": tick, "elapsed": elapsed, "revision": entity_ledger.revision, "barrels": barrels.duplicate(true), "entities": entity_ledger.entities.duplicate(true)}

func state_hash() -> String:
	var entities := entity_ledger.entities.keys()
	entities.sort()
	var normalized := []
	for entity_id in entities:
		var state: Dictionary = entity_ledger.entities[entity_id]
		normalized.append({"id": str(entity_id), "incarnation": int(state.incarnation), "kind": str(state.kind), "state": str(state.state), "hp": int(state.shared_health)})
	var barrel_state := []
	for barrel in barrels:
		barrel_state.append({"id": str(barrel.entity_id), "x": int(round(float(barrel.x) * 16.0)), "y": int(round(float(barrel.y) * 16.0)), "spawned": bool(barrel.spawned), "falling": bool(barrel.falling), "destroyed": bool(barrel.destroyed)})
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify({"tick": tick, "revision": entity_ledger.revision, "entities": normalized, "barrels": barrel_state}).to_utf8_buffer())
	return context.finish().hex_encode()

func _surface_angle_at(x: float, ceiling: bool) -> float:
	for event in manifest.events:
		if str(event.get("kind", "")) != "slope" or bool(event.get("from_ceiling", false)) != ceiling:
			continue
		var start_x := float(event.get("start_x", 0.0))
		var end_x := float(event.get("end_x", start_x))
		if x >= start_x and x <= end_x and end_x > start_x:
			return atan2(float(event.get("end_y", 0.0)) - float(event.get("start_y", 0.0)), end_x - start_x)
	return 0.0

func _resolve_barrel_interactions(barrel: Dictionary) -> void:
	var radius := HazardRules.barrel_radius(float(barrel.width), float(barrel.height))
	var center := HazardRules.barrel_center(Vector2(float(barrel.x), float(barrel.y)), float(barrel.width), float(barrel.height))
	for event in manifest.events:
		var event_id := str(event.get("event_id", ""))
		if str(event.get("kind", "")) == "spikes":
			var triangles := HazardRules.spike_group_triangles(float(event.get("start_x", event.get("x", 0.0))), float(event.get("y", 0.0)), int(event.get("count", 1)), float(event.get("spacing", CourseGeneratorScript.SPIKE_GROUP_SPACING)), CourseGeneratorScript.SPIKE_WIDTH, CourseGeneratorScript.SPIKE_HEIGHT, bool(event.get("from_ceiling", false)))
			if HazardRules.barrel_impact(center, radius, "spikes", Rect2(), triangles) == HazardRules.BarrelImpact.BARREL_DESTROYED:
				barrel.destroyed = true
				apply_deterministic_destruction(str(barrel.entity_id), tick)
				return
		elif str(event.get("kind", "")) == "block" and entity_ledger.is_active(event_id):
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			var target := Rect2(Vector2(float(event.get("x", 0.0)) - width * 0.5, block_y), Vector2(width, height))
			if HazardRules.barrel_impact(center, radius, "block", target) == HazardRules.BarrelImpact.BARREL_AND_TARGET_DESTROYED:
				barrel.destroyed = true
				apply_deterministic_destruction(str(barrel.entity_id), tick)
				apply_deterministic_destruction(event_id, tick)
				return
	for event in manifest.events:
		if str(event.get("kind", "")) != "step" or not entity_ledger.is_active(str(event.get("event_id", ""))):
			continue
		var rect := HazardRules.step_wall_rect(float(event.get("x", 0.0)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
		var floor_drop := not bool(event.get("from_ceiling", false)) and float(event.get("start_y", 0.0)) > float(event.get("end_y", 0.0))
		if not floor_drop and HazardRules.barrel_impact(center, radius, "step", rect) == HazardRules.BarrelImpact.BARREL_DESTROYED:
			barrel.destroyed = true
			apply_deterministic_destruction(str(barrel.entity_id), tick)
			return
