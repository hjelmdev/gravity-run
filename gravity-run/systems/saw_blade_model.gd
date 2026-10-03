extends RefCounted
class_name SawBladeModel
## Deterministic 60 Hz saw motion shared by SP and MP. The course supplies
## surface support; only the presentation node draws the blade.

const RADIUS := 30.0
const WIDTH := 64.0
const HORIZONTAL_SPEED := 180.0
const GRAVITY := 1500.0
const START_OFFSET := 1100.0
const ROOF_GAP_OFFSET := 900.0
const ROOF_GAP_WIDTH := 96.0
const SPAWN_LEAD := 1200.0
const ACTIVATION_DELAY_TICKS := 12
const TICK_RATE := 60.0
const WORLD_HEIGHT := 540.0

static func spawn_tick(event: Dictionary, course_start_x: float) -> int:
	# Kept as a compatibility accessor for diagnostics; activation is now
	# triggered by the first authoritative runner crossing the course threshold.
	return int(event.get("activation_tick", -1))

static func initial_state(event: Dictionary, _course_start_x: float, tick := 0, activation_tick := -1) -> Dictionary:
	var ceiling := bool(event.get("from_ceiling", false))
	var x := float(event.get("spawn_x", float(event.get("x", 0.0)) + START_OFFSET))
	var surface_y := float(event.get("ceiling_y", 80.0)) if ceiling else float(event.get("floor_y", 460.0))
	return {"tick": tick, "activation_tick": activation_tick, "active": false, "removed": false, "x": x, "y": surface_y + RADIUS if ceiling else surface_y - RADIUS, "fall_velocity": 0.0, "falling": false, "ceiling_lane": ceiling, "roll_angle": 0.0}

static func advance(event: Dictionary, from_state: Dictionary, target_tick: int, surface_query: Callable) -> Dictionary:
	var state := from_state.duplicate(true)
	var current_tick := int(state.get("tick", 0))
	if target_tick < current_tick:
		return state
	# Dormant saws have no per-tick motion to replay. Jump directly to the
	# activation boundary, which matters for late baselines and SP instantiation.
	var scheduled_activation := int(state.get("activation_tick", -1))
	if not bool(state.get("active", false)) and scheduled_activation < 0:
		state["tick"] = target_tick
		return state
	if not bool(state.get("active", false)) and scheduled_activation >= 0 and target_tick < scheduled_activation:
		state["tick"] = target_tick
		return state
	if not bool(state.get("active", false)) and scheduled_activation >= 0 and current_tick < scheduled_activation:
		current_tick = scheduled_activation - 1
		state["tick"] = current_tick
	while current_tick < target_tick:
		current_tick += 1
		state["tick"] = current_tick
		if bool(state.get("removed", false)):
			continue
		var activation_tick := int(state.get("activation_tick", -1))
		if activation_tick < 0 or current_tick < activation_tick:
			continue
		if not bool(state.get("active", false)):
			state["active"] = true
			var initial_x := float(state.get("x", 0.0))
			_align_to_surface(state, initial_x, surface_query)
			continue
		var delta := 1.0 / TICK_RATE
		var x := float(state.get("x", 0.0)) - HORIZONTAL_SPEED * delta
		state["x"] = x
		state["roll_angle"] = float(state.get("roll_angle", 0.0)) - HORIZONTAL_SPEED / RADIUS * delta
		if bool(state.get("falling", false)):
			var old_bottom := float(state.get("y", 0.0)) + RADIUS
			var velocity := float(state.get("fall_velocity", 0.0)) + GRAVITY * delta
			var y := float(state.get("y", 0.0)) + velocity * delta
			state["fall_velocity"] = velocity
			state["y"] = y
			var floor_info: Dictionary = surface_query.call(x, false)
			var floor_y := float(floor_info.get("y", WORLD_HEIGHT - 80.0))
			if bool(floor_info.get("supported", false)) and old_bottom <= floor_y and y + RADIUS >= floor_y:
				state["y"] = floor_y - RADIUS
				state["fall_velocity"] = 0.0
				state["falling"] = false
				state["ceiling_lane"] = false
			elif y - RADIUS > WORLD_HEIGHT + RADIUS:
				state["removed"] = true
		else:
			_align_to_surface(state, x, surface_query)
	return state

static func contact_activation_tick(current_tick: int) -> int:
	return maxi(current_tick, 0) + ACTIVATION_DELAY_TICKS

static func _align_to_surface(state: Dictionary, x: float, surface_query: Callable) -> void:
	var ceiling := bool(state.get("ceiling_lane", false))
	var surface: Dictionary = surface_query.call(x, ceiling)
	if bool(surface.get("supported", false)):
		var y := float(surface.get("y", 0.0))
		state["y"] = y + RADIUS if ceiling else y - RADIUS
		return
	state["falling"] = true
	state["fall_velocity"] = 0.0

static func hitbox(state: Dictionary) -> Rect2:
	if not bool(state.get("active", false)) or bool(state.get("removed", false)):
		return Rect2()
	return Rect2(Vector2(float(state.get("x", 0.0)), float(state.get("y", 0.0))) - Vector2.ONE * RADIUS, Vector2.ONE * (RADIUS * 2.0))

static func phase(state: Dictionary) -> String:
	if bool(state.get("removed", false)):
		return "removed"
	if not bool(state.get("active", false)):
		return "dormant"
	if bool(state.get("falling", false)):
		return "falling"
	return "ceiling_roll" if bool(state.get("ceiling_lane", false)) else "floor_roll"
