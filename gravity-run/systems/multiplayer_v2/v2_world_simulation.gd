extends RefCounted
class_name MultiplayerV2WorldSimulation

const Motion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const LedgerScript := preload("res://systems/multiplayer_v2/v2_world_event_ledger.gd")
const SurfaceIndexScript := preload("res://systems/course_surface_index.gd")
const FallingRockModel := preload("res://systems/falling_rock_model.gd")
const SawBladeModel := preload("res://systems/saw_blade_model.gd")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")

const TICK_RATE := 60.0
const FIXED_DELTA := 1.0 / TICK_RATE

var manifest: Resource
var _previous_render_barrels: Dictionary = {}
var tick := 0
var elapsed := 0.0
var barrels: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var rocks: Array[Dictionary] = []
var saws: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var _previous_saw_states: Dictionary = {}
var _saw_history: Dictionary = {}
var entity_ledger: MultiplayerV2WorldEventLedger = LedgerScript.new()
var _entity_by_event: Dictionary = {}
var _barrel_history: Dictionary = {}
var _surface_index

func configure(course_manifest: Resource) -> String:
	if course_manifest == null or not course_manifest.has_method("validate"):
		return "manifest_missing"
	var error := str(course_manifest.call("validate"))
	if not error.is_empty():
		return error
	manifest = course_manifest
	_surface_index = SurfaceIndexScript.new()
	_surface_index.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
	tick = 0
	elapsed = 0.0
	barrels.clear()
	coins.clear()
	rocks.clear()
	saws.clear()
	ghosts.clear()
	_previous_saw_states.clear()
	_saw_history.clear()
	_previous_render_barrels.clear()
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
		elif kind in ["block", "step", "rock", "saw", "ghost"]:
			entities.append({"entity_id": event_id, "incarnation": 1, "kind": kind, "health": 1})
			_entity_by_event[event_id] = {"kind": kind, "event_id": event_id}
			if kind == "rock":
				rocks.append(event.duplicate(true))
			elif kind == "saw":
				saws.append({"event_id": event_id, "event": event.duplicate(true), "state": SawBladeModel.initial_state(event, float(manifest.start_x), 0)})
			elif kind == "ghost":
				ghosts.append(event.duplicate(true))
	for collectible in manifest.collectibles:
		var coin: Dictionary = collectible.duplicate(true)
		coin["incarnation"] = 1
		coins.append(coin)
		entities.append({"entity_id": str(coin.entity_id), "incarnation": 1, "kind": "coin", "health": 0})
	entity_ledger.reset(entities)
	_barrel_history[0] = barrels.duplicate(true)
	_record_saw_history(0)
	return ""

func step_to(next_tick: int) -> bool:
	if manifest == null or next_tick != tick + 1:
		return false
	_previous_render_barrels.clear()
	_previous_saw_states.clear()
	for saw in saws:
		var saw_id := str(saw.get("event_id", ""))
		_previous_saw_states[saw_id] = (saw.get("state", {}) as Dictionary).duplicate(true)
	for barrel in barrels:
		_previous_render_barrels[str(barrel.get("entity_id", ""))] = barrel.duplicate(true)
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
	for saw in saws:
		var saw_event: Dictionary = saw.get("event", {})
		saw["state"] = SawBladeModel.advance(saw_event, saw.get("state", {}), tick, Callable(self, "surface_at"))
	_record_saw_history(tick)
	_barrel_history[tick] = barrels.duplicate(true)
	while _barrel_history.size() > 121:
		var oldest: int = int(_barrel_history.keys().min())
		_barrel_history.erase(oldest)
	return true

func render_state(fraction: float) -> Dictionary:
	var rendered := barrels.duplicate(true)
	for barrel in rendered:
		var previous: Dictionary = _previous_render_barrels.get(str(barrel.get("entity_id", "")), barrel)
		if bool(previous.get("spawned", false)) and not bool(barrel.get("destroyed", false)):
			for key in ["x", "y", "roll_angle", "rotation"]:
				barrel[key] = lerpf(float(previous.get(key, barrel.get(key, 0.0))), float(barrel.get(key, 0.0)), clampf(fraction, 0.0, 1.0))
	var rendered_rocks: Array[Dictionary] = []
	for event in rocks:
		var entity_id := str(event.get("event_id", ""))
		var state: Dictionary = entity_ledger.entities.get(entity_id, {})
		var activation_tick := int(state.get("rock_activation_tick", -1))
		var render_tick := float(tick - 1) + clampf(fraction, 0.0, 1.0)
		var center := FallingRockModel.center_at(event, activation_tick, render_tick)
		rendered_rocks.append({"event_id": entity_id, "activation_tick": activation_tick, "tick": render_tick, "phase": FallingRockModel.phase_at(event, activation_tick, floori(render_tick)), "x": center.x, "y": center.y, "rect": FallingRockModel.hitbox_at(event, activation_tick, render_tick), "event": event})
	var rendered_saws: Array[Dictionary] = []
	for saw in saws:
		var saw_id := str(saw.get("event_id", ""))
		var current_state: Dictionary = saw.get("state", {}).duplicate(true)
		var previous_state: Dictionary = _previous_saw_states.get(saw_id, current_state)
		if bool(current_state.get("active", false)) and bool(previous_state.get("active", false)):
			for key in ["x", "y", "roll_angle"]:
				current_state[key] = lerpf(float(previous_state.get(key, current_state.get(key, 0.0))), float(current_state.get(key, 0.0)), clampf(fraction, 0.0, 1.0))
		rendered_saws.append({"event_id": saw_id, "state": current_state, "event": saw.get("event", {})})
	var rendered_ghosts: Array[Dictionary] = []
	for event in ghosts:
		var event_id := str(event.get("event_id", ""))
		var entity: Dictionary = entity_ledger.entities.get(event_id, {})
		var activation_tick := int(entity.get("ghost_activation_tick", -1))
		rendered_ghosts.append({"event_id": event_id, "event": event, "state": GhostModel.state(event, activation_tick, tick)})
	return {"barrels": rendered, "coins": coins, "rocks": rendered_rocks, "saws": rendered_saws, "ghosts": rendered_ghosts, "entities": entity_ledger.entities}

func barrel_presentation_probe(entity_id: String, presentation_tick: float, fraction: float) -> Dictionary:
	var current: Dictionary = {}
	for barrel in barrels:
		if str(barrel.get("entity_id", "")) == entity_id:
			current = barrel
			break
	if current.is_empty():
		return {}
	var previous: Dictionary = _previous_render_barrels.get(entity_id, current)
	var current_copy: Dictionary = current.duplicate(true)
	var previous_copy: Dictionary = previous.duplicate(true)
	var displayed := current_copy.duplicate(true)
	if bool(previous_copy.get("spawned", false)) and not bool(current_copy.get("destroyed", false)):
		for key in ["x", "y", "roll_angle", "rotation"]:
			displayed[key] = lerpf(float(previous_copy.get(key, displayed.get(key, 0.0))), float(current_copy.get(key, 0.0)), clampf(fraction, 0.0, 1.0))
	return {"entity_id": entity_id, "simulation_tick": tick, "presentation_tick": presentation_tick, "presentation_fraction": clampf(fraction, 0.0, 1.0), "previous": _barrel_probe_pose(previous_copy), "current": _barrel_probe_pose(current_copy), "displayed": _barrel_probe_pose(displayed)}

static func _barrel_probe_pose(barrel: Dictionary) -> Dictionary:
	return {"x": float(barrel.get("x", 0.0)), "y": float(barrel.get("y", 0.0)), "roll_angle": float(barrel.get("roll_angle", 0.0)), "rotation": float(barrel.get("rotation", 0.0)), "spawned": bool(barrel.get("spawned", false)), "falling": bool(barrel.get("falling", false)), "destroyed": bool(barrel.get("destroyed", false))}

static func presentation_fraction(presentation_tick: float, latest_simulation_tick: int) -> float:
	return clampf(presentation_tick - float(latest_simulation_tick - 1), 0.0, 1.0)

func surface_at(x: float, ceiling: bool) -> Dictionary:
	if _surface_index != null:
		return _surface_index.surface_at(x, ceiling)
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
	return _player_contact_against(player_state, barrels, tick)

func player_contact_at(player_state: Dictionary, simulation_tick: int) -> Dictionary:
	if not _barrel_history.has(simulation_tick) or not _saw_history.has(simulation_tick):
		return {"kind": "history_missing"}
	return _player_contact_against(player_state, _barrel_history[simulation_tick], simulation_tick)

func coin_contacts_swept(previous_state: Dictionary, proposed_state: Dictionary) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	var start := Vector2(float(previous_state.get("world_x", 0.0)), float(previous_state.get("y", 0.0)))
	var finish := Vector2(float(proposed_state.get("world_x", 0.0)), float(proposed_state.get("y", 0.0)))
	var rect := Rect2(start - Motion.SIZE * 0.5, Motion.SIZE)
	var range_min := minf(start.x, finish.x) - Motion.SIZE.x * 0.5 - 14.0
	var range_max := maxf(start.x, finish.x) + Motion.SIZE.x * 0.5 + 14.0
	var low := 0
	var high := coins.size()
	while low < high:
		var middle := (low + high) >> 1
		if float(coins[middle].get("world_x", 0.0)) < range_min: low = middle + 1
		else: high = middle
	for index in range(low, coins.size()):
		var coin: Dictionary = coins[index]
		if float(coin.get("world_x", 0.0)) > range_max:
			break
		var entity_id := str(coin.get("entity_id", ""))
		if not entity_ledger.is_active(entity_id, int(coin.get("incarnation", 1))):
			continue
		var center := Vector2(float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)))
		var fraction := HazardRules.swept_rect_circle_fraction(rect, finish - start, center, float(coin.get("radius", 13.0)))
		if fraction >= 0.0:
			var pose := start.lerp(finish, fraction)
			contacts.append({"entity_id": entity_id, "incarnation": int(coin.get("incarnation", 1)), "fraction": fraction, "world_x": pose.x, "y": pose.y})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.fraction), float(b.fraction)):
			return float(a.fraction) < float(b.fraction)
		return str(a.entity_id) < str(b.entity_id)
	)
	return contacts

func coin_contact_swept(entity_id: String, previous_state: Dictionary, proposed_state: Dictionary) -> Dictionary:
	for contact in coin_contacts_swept(previous_state, proposed_state):
		if str(contact.entity_id) == entity_id:
			return contact
	return {}

func _player_contact_against(player_state: Dictionary, barrel_state: Array, simulation_tick: int = -1) -> Dictionary:
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
		if kind == "rock":
			var rock_entity: Dictionary = entity_ledger.entities.get(event_id, {})
			var activation_tick := int(rock_entity.get("rock_activation_tick", -1))
			var rock_tick := simulation_tick if simulation_tick >= 0 else tick
			var rock_rect := FallingRockModel.hitbox_at(event, activation_tick, rock_tick)
			if rock_rect.size != Vector2.ZERO and HazardRules.player_impact(rect, "block", rock_rect) == HazardRules.PlayerImpact.LETHAL:
				return {"kind": "terminal", "reason": "falling_rock", "entity_id": event_id, "event_id": event_id}
			continue
		if kind == "saw":
			var saw_state := _saw_state_for_event(event_id, simulation_tick)
			if bool(saw_state.get("active", false)) and not bool(saw_state.get("removed", false)) and HazardRules.circle_intersects_rect(Vector2(float(saw_state.get("x", 0.0)), float(saw_state.get("y", 0.0))), SawBladeModel.radius_for_state(saw_state), rect):
				return {"kind": "terminal", "reason": "saw_blade", "entity_id": event_id, "event_id": event_id}
			continue
		if kind == "ghost":
			var ghost_entity: Dictionary = entity_ledger.entities.get(event_id, {})
			var ghost_tick := simulation_tick if simulation_tick >= 0 else tick
			var ghost_activation := int(ghost_entity.get("ghost_activation_tick", -1))
			var ghost_rect := GhostModel.hitbox(event, ghost_tick, ghost_activation)
			if ghost_rect.size != Vector2.ZERO and HazardRules.player_impact(rect, "block", ghost_rect) == HazardRules.PlayerImpact.LETHAL:
				return {"kind": "terminal", "reason": "ghost", "entity_id": event_id, "event_id": event_id}
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

func first_static_terminal_contact(previous: Dictionary, proposed: Dictionary) -> Dictionary:
	if manifest == null:
		return {}
	var start := Vector2(float(previous.world_x), float(previous.y))
	var end := Vector2(float(proposed.world_x), float(proposed.y))
	var rect := Rect2(start - Motion.SIZE * 0.5, Motion.SIZE)
	var best: Dictionary = {}
	var first_fraction := 2.0
	for event in manifest.events:
		var kind := str(event.get("kind", ""))
		var entity_id := str(event.get("event_id", ""))
		if kind == "rock":
			var rock_entity: Dictionary = entity_ledger.entities.get(entity_id, {})
			var activation_tick := int(rock_entity.get("rock_activation_tick", -1))
			var rock_fraction := FallingRockModel.swept_contact_fraction(event, activation_tick, maxi(tick - 1, 0), tick, start, end, Motion.SIZE)
			if rock_fraction >= 0.0 and rock_fraction < first_fraction:
				first_fraction = rock_fraction
				var rock_pose := start.lerp(end, rock_fraction)
				best = {"kind": "terminal", "reason": "falling_rock", "entity_id": entity_id, "event_id": entity_id, "fraction": rock_fraction, "world_x": rock_pose.x, "y": rock_pose.y}
			continue
		if kind == "saw":
			var previous_saw := _saw_state_for_event(entity_id, maxi(tick - 1, 0))
			var current_saw := _saw_state_for_event(entity_id, tick)
			if bool(current_saw.get("active", false)) and not bool(current_saw.get("removed", false)):
				var current_center := Vector2(float(current_saw.get("x", 0.0)), float(current_saw.get("y", 0.0)))
				var previous_center := current_center
				if bool(previous_saw.get("active", false)) and not bool(previous_saw.get("removed", false)):
					previous_center = Vector2(float(previous_saw.get("x", current_center.x)), float(previous_saw.get("y", current_center.y)))
				var fraction := HazardRules.swept_rect_circle_fraction(rect, end - start - (current_center - previous_center), previous_center, SawBladeModel.radius_for_state(current_saw))
				if fraction >= 0.0 and fraction < first_fraction:
					first_fraction = fraction
					var saw_pose := start.lerp(end, fraction)
					best = {"kind": "terminal", "reason": "saw_blade", "entity_id": entity_id, "event_id": entity_id, "fraction": fraction, "world_x": saw_pose.x, "y": saw_pose.y}
			continue
		if kind == "ghost":
			var ghost_entity: Dictionary = entity_ledger.entities.get(entity_id, {})
			var activation_tick := int(ghost_entity.get("ghost_activation_tick", -1))
			if activation_tick >= 0 and GhostModel.phase_at(event, activation_tick, tick) == GhostModel.DANGEROUS:
				var ghost_rect := GhostModel.hitbox(event, tick, activation_tick)
				var previous_dangerous := GhostModel.phase_at(event, activation_tick, maxi(tick - 1, 0)) == GhostModel.DANGEROUS
				var fraction := -1.0
				if previous_dangerous:
					var ghost_polygon := PackedVector2Array([ghost_rect.position, Vector2(ghost_rect.end.x, ghost_rect.position.y), ghost_rect.end, Vector2(ghost_rect.position.x, ghost_rect.end.y)])
					fraction = HazardRules.swept_rect_polygon_fraction(rect, end - start, ghost_polygon)
				elif HazardRules.player_impact(Rect2(end - Motion.SIZE * 0.5, Motion.SIZE), "block", ghost_rect) == HazardRules.PlayerImpact.LETHAL:
					# The phase becomes lethal on this tick; do not retroactively
					# treat the previous warning-phase pose as a collision.
					fraction = 1.0
				if fraction >= 0.0 and fraction < first_fraction:
					first_fraction = fraction
					var ghost_pose := start.lerp(end, fraction)
					best = {"kind": "terminal", "reason": "ghost", "entity_id": entity_id, "event_id": entity_id, "fraction": fraction, "world_x": ghost_pose.x, "y": ghost_pose.y}
			continue
		if kind in ["block", "step"] and not entity_ledger.is_active(entity_id):
			continue
		# Cull distant events before constructing their polygon groups.
		var event_x := float(event.get("start_x", event.get("x", 0.0)))
		var reach := float(event.get("width", 48.0)) + float(event.get("count", 1)) * float(event.get("spacing", CourseGeneratorScript.SPIKE_GROUP_SPACING)) + 64.0
		if maxf(start.x, end.x) + Motion.SIZE.x < event_x - reach or minf(start.x, end.x) - Motion.SIZE.x > event_x + reach:
			continue
		var polygons: Array[PackedVector2Array] = []
		var reason := kind
		if kind == "block":
			var height := float(event.get("height", 72.0))
			var width := float(event.get("width", 48.0))
			var edge_y := float(event.get("y", 0.0))
			var y := edge_y if bool(event.get("from_ceiling", false)) else edge_y - height
			var bounds := Rect2(float(event.get("x", 0.0)) - width * 0.5, y, width, height)
			polygons.append(PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]))
		elif kind == "spikes":
			polygons = HazardRules.spike_group_triangles(float(event.get("start_x", event.get("x", 0.0))), float(event.get("y", 0.0)), int(event.get("count", 1)), float(event.get("spacing", CourseGeneratorScript.SPIKE_GROUP_SPACING)), CourseGeneratorScript.SPIKE_WIDTH, CourseGeneratorScript.SPIKE_HEIGHT, bool(event.get("from_ceiling", false)))
		elif kind == "step" and bool(event.get("spiked", false)):
			reason = "step_spikes"
			polygons = HazardRules.step_spike_triangles(float(event.get("x", 0.0)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)), bool(event.get("from_ceiling", false)))
		for polygon in polygons:
			var fraction := HazardRules.swept_rect_polygon_fraction(rect, end - start, polygon)
			if fraction < 0.0 or fraction >= first_fraction:
				continue
			var pose := start.lerp(end, fraction)
			if kind == "step":
				var contact_state := proposed.duplicate(true)
				contact_state.world_x = pose.x
				contact_state.y = pose.y
				if str(player_contact(contact_state).get("kind", "")) == "blocked":
					continue
			first_fraction = fraction
			var geometry: Array = []
			for vertex in polygon:
				geometry.append([vertex.x, vertex.y])
			best = {"kind": "terminal", "reason": reason, "entity_id": entity_id, "event_id": entity_id, "fraction": fraction, "world_x": pose.x, "y": pose.y, "geometry": geometry}
	return best

func apply_world_commit(commit: Dictionary) -> String:
	var result := entity_ledger.apply_commit(commit)
	if result not in ["applied", "duplicate"]:
		return result
	var entity_id := str(commit.get("entity_id", ""))
	if result == "applied" and str(commit.get("action", "")) == "activate_saw":
		_rebuild_saw_history_for_event(entity_id)
	if str(entity_ledger.entities.get(entity_id, {}).get("state", "")) == "destroyed":
		for barrel in barrels:
			if str(barrel.get("entity_id", "")) == entity_id:
				barrel.destroyed = true
		return result
	return result

func apply_baseline(value: Dictionary) -> bool:
	if not entity_ledger.restore_baseline(value):
		return false
	_rebuild_saw_history()
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
	return {"tick": tick, "elapsed": elapsed, "revision": entity_ledger.revision, "barrels": barrels.duplicate(true), "saws": saws.duplicate(true), "entities": entity_ledger.entities.duplicate(true)}

func state_hash() -> String:
	var entities := entity_ledger.entities.keys()
	entities.sort()
	var normalized := []
	for entity_id in entities:
		var state: Dictionary = entity_ledger.entities[entity_id]
		normalized.append({"id": str(entity_id), "incarnation": int(state.incarnation), "kind": str(state.kind), "state": str(state.state), "hp": int(state.shared_health), "winner_peer_id": int(state.get("winner_peer_id", 0)), "award_value": int(state.get("award_value", 0)), "rock_activation_tick": int(state.get("rock_activation_tick", -1)), "saw_activation_tick": int(state.get("saw_activation_tick", -1))})
	var barrel_state := []
	for barrel in barrels:
		barrel_state.append({"id": str(barrel.entity_id), "x": int(round(float(barrel.x) * 16.0)), "y": int(round(float(barrel.y) * 16.0)), "spawned": bool(barrel.spawned), "falling": bool(barrel.falling), "destroyed": bool(barrel.destroyed)})
	var saw_state := []
	for saw in saws:
		var state: Dictionary = saw.get("state", {})
		saw_state.append({"id": str(saw.get("event_id", "")), "x": int(round(float(state.get("x", 0.0)) * 16.0)), "y": int(round(float(state.get("y", 0.0)) * 16.0)), "active": bool(state.get("active", false)), "falling": bool(state.get("falling", false)), "removed": bool(state.get("removed", false)), "ceiling_lane": bool(state.get("ceiling_lane", false))})
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify({"tick": tick, "revision": entity_ledger.revision, "entities": normalized, "barrels": barrel_state, "saws": saw_state}).to_utf8_buffer())
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

func _saw_state_for_event(event_id: String, at_tick: int = -1) -> Dictionary:
	if at_tick >= 0 and _saw_history.has(at_tick):
		var historical: Dictionary = _saw_history[at_tick]
		if historical.has(event_id):
			return historical[event_id]
	for saw in saws:
		if str(saw.get("event_id", "")) == event_id:
			return saw.get("state", {})
	return {}

func _record_saw_history(at_tick: int) -> void:
	var snapshot: Dictionary = {}
	for saw in saws:
		snapshot[str(saw.get("event_id", ""))] = (saw.get("state", {}) as Dictionary).duplicate(true)
	_saw_history[at_tick] = snapshot
	while _saw_history.size() > 121:
		var oldest: int = int(_saw_history.keys().min())
		_saw_history.erase(oldest)

func _rebuild_saw_history() -> void:
	_saw_history.clear()
	var states: Dictionary = {}
	var saw_by_id: Dictionary = {}
	var first_kept_tick := maxi(tick - 120, 0)
	for saw in saws:
		var saw_id := str(saw.get("event_id", ""))
		var event: Dictionary = saw.get("event", {})
		var activation_tick := int(entity_ledger.entities.get(saw_id, {}).get("saw_activation_tick", -1))
		var initial: Dictionary = SawBladeModel.initial_state(event, float(manifest.start_x), 0, activation_tick)
		states[saw_id] = SawBladeModel.advance(event, initial, maxi(first_kept_tick - 1, 0), Callable(self, "surface_at"))
		saw_by_id[saw_id] = saw
	if tick == 0:
		for saw in saws:
			saw["state"] = states[str(saw.get("event_id", ""))]
		_record_saw_history(0)
		return
	for current_tick in range(first_kept_tick, tick + 1):
		for saw_id_value in states.keys():
			var saw_id := str(saw_id_value)
			var saw: Dictionary = saw_by_id[saw_id]
			states[saw_id] = SawBladeModel.advance(saw.get("event", {}), states[saw_id], current_tick, Callable(self, "surface_at"))
		for saw in saws:
			saw["state"] = states[str(saw.get("event_id", ""))]
		_record_saw_history(current_tick)
	for saw in saws:
		saw["state"] = states[str(saw.get("event_id", ""))]

func _rebuild_saw_history_for_event(event_id: String) -> void:
	var target: Dictionary = {}
	for saw in saws:
		if str(saw.get("event_id", "")) == event_id:
			target = saw
			break
	if target.is_empty():
		return
	var event: Dictionary = target.get("event", {})
	var activation_tick := int(entity_ledger.entities.get(event_id, {}).get("saw_activation_tick", -1))
	var state: Dictionary = SawBladeModel.initial_state(event, float(manifest.start_x), 0, activation_tick)
	var first_kept_tick := maxi(tick - 120, 0)
	state = SawBladeModel.advance(event, state, maxi(first_kept_tick - 1, 0), Callable(self, "surface_at"))
	if first_kept_tick == 0:
		var initial_snapshot: Dictionary = _saw_history.get(0, {}).duplicate(true)
		initial_snapshot[event_id] = state.duplicate(true)
		_saw_history[0] = initial_snapshot
	for current_tick in range(maxi(first_kept_tick, 1), tick + 1):
		state = SawBladeModel.advance(event, state, current_tick, Callable(self, "surface_at"))
		var snapshot: Dictionary = _saw_history.get(current_tick, {}).duplicate(true)
		snapshot[event_id] = state.duplicate(true)
		_saw_history[current_tick] = snapshot
	if tick == 0:
		var snapshot_zero: Dictionary = _saw_history.get(0, {}).duplicate(true)
		snapshot_zero[event_id] = state.duplicate(true)
		_saw_history[0] = snapshot_zero
	target["state"] = state
	while _saw_history.size() > 121:
		_saw_history.erase(int(_saw_history.keys().min()))

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
