extends Node2D
class_name RaceCoursePresentation

const SpikeScene := preload("res://hazards/spikes.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const CoinScene := preload("res://collectibles/coin.tscn")
const FallingRockScript := preload("res://hazards/falling_rock.gd")
const LedgeScene := preload("res://terrain/ledge.tscn")
const SlopeScene := preload("res://terrain/slope.tscn")
const TrackGapScript := preload("res://terrain/track_gap.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseSurfaceRenderer := preload("res://systems/course_surface_renderer.gd")
const SurfaceIndexScript := preload("res://systems/course_surface_index.gd")
const FallingRockModel := preload("res://systems/falling_rock_model.gd")
const RockWarningIcon := preload("res://systems/rock_warning_icon.gd")
const RockWarningPulseScript := preload("res://systems/rock_warning_pulse.gd")

var manifest: Resource
var event_nodes: Dictionary = {}
var _confirmed_coin_bursts: Dictionary = {}
var _coin_visual_predictions: Dictionary = {}
var terrain_events: Array[Dictionary] = []
var gap_events: Array[Dictionary] = []
var _render_ceiling_gaps: Array[Dictionary] = []
var _render_floor_gaps: Array[Dictionary] = []
var _render_terrain_boundaries: Array[float] = []
var _render_step_positions: Array[float] = []
var _camera_left := 0.0
var _world_height := 720.0
var _render_profile_total_usec := 0
var _render_profile_max_usec := 0
var _render_profile_draw_count := 0
var _render_profile_surface_queries := 0
var _render_profile_enabled := false
var _start_draw_deadline_usec := -1
var _first_start_draw_profile: Dictionary = {}
var _surface_index
var _rock_warning_states: Array[Dictionary] = []
var _rock_warning_pulse: RefCounted = RockWarningPulseScript.new()
var _rock_warning_accessibility_button: Button

func _ready() -> void:
	set_process(true)
	_rock_warning_accessibility_button = Button.new()
	_rock_warning_accessibility_button.name = "RockWarningAccessibility"
	_rock_warning_accessibility_button.text = ""
	_rock_warning_accessibility_button.tooltip_text = tr("Falling rock")
	_rock_warning_accessibility_button.accessibility_name = tr("Falling rock")
	_rock_warning_accessibility_button.focus_mode = Control.FOCUS_ALL
	_rock_warning_accessibility_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rock_warning_accessibility_button.flat = true
	_rock_warning_accessibility_button.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_rock_warning_accessibility_button.size = Vector2(48.0, 48.0)
	_rock_warning_accessibility_button.visible = false
	add_child(_rock_warning_accessibility_button)

func _process(delta: float) -> void:
	if bool(_rock_warning_pulse.call("advance", delta)):
		queue_redraw()
		_update_rock_warning_accessibility_marker()

static func create_hazard(scene: PackedScene, at_position: Vector2, size: Vector2, from_ceiling: bool, surface_rotation: float = 0.0) -> Node2D:
	var hazard := scene.instantiate() as Node2D
	hazard.position = at_position
	hazard.call("configure", size, from_ceiling)
	hazard.rotation = surface_rotation
	return hazard

static func rock_warning_marker_center(camera_left: float, viewport_size: Vector2, floor_y: float) -> Vector2:
	return Vector2(maxf(camera_left, 0.0) + viewport_size.x - 56.0, floor_y - 70.0)

static func rock_warning_hud_center(camera_left: float, viewport_size: Vector2) -> Vector2:
	return RockWarningPulseScript.world_center(camera_left, viewport_size)

func load_manifest(course_manifest: Resource) -> String:
	reset()
	manifest = course_manifest
	if manifest == null:
		return "missing_manifest"
	var validation := str(manifest.call("validate"))
	if not validation.is_empty():
		manifest = null
		return validation
	_world_height = float(manifest.world_height)
	_surface_index = SurfaceIndexScript.new()
	_surface_index.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
	var floor_y := float(manifest.initial_floor_y)
	var ceiling_y := float(manifest.initial_ceiling_y)
	for event_value in manifest.events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var kind := str(event.get("kind", ""))
		if kind in ["step", "slope"]:
			terrain_events.append(event)
		elif kind == "gap":
			gap_events.append(event)
		var event_id := str(event.get("event_id", ""))
		var x := float(event.get("x", 0.0))
		var from_ceiling := bool(event.get("from_ceiling", false))
		var surface_y := ceiling_y if from_ceiling else floor_y
		match kind:
			"spikes":
				var start_x := float(event.get("start_x", x))
				for index in range(int(event.get("count", 1))):
					var spike := create_hazard(SpikeScene, Vector2(start_x + float(index) * float(event.get("spacing", 32.0)), float(event.get("y", surface_y))), Vector2(CourseGenerator.SPIKE_WIDTH, CourseGenerator.SPIKE_HEIGHT), from_ceiling)
					spike.name = "Spike_%s_%d" % [event_id, index]
					_tag_presentation_target(spike, "%s:%d" % [event_id, index], kind, false)
					add_child(spike)
					event_nodes["%s_%d" % [event_id, index]] = spike
			"block":
				var block := create_hazard(BlockScene, Vector2(x, float(event.get("y", surface_y))), Vector2(float(event.get("width", 48.0)), float(event.get("height", 72.0))), from_ceiling)
				block.name = "Block_%s" % event_id
				_tag_presentation_target(block, event_id, kind, false)
				add_child(block)
				event_nodes[event_id] = block
			"barrels":
				var count := int(event.get("count", 1))
				var spacing := float(event.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
				var chain_width := float(count - 1) * spacing
				var speed_multiplier := float(event.get("motion_speed_multiplier", 1.0))
				var spawn_offset := float(event.get("spawn_lead_distance", 820.0)) * (speed_multiplier - 1.0)
				for index in range(count):
					var barrel_id := "%s_%d" % [event_id, index]
					var barrel := create_hazard(BarrelScene, Vector2(x + spawn_offset - chain_width * 0.5 + float(index) * spacing, float(event.get("y", floor_y))), Vector2(HazardRules.BARREL_WIDTH, float(event.get("height", HazardRules.BARREL_WIDTH))), false)
					barrel.call("set_motion_speed_multiplier", speed_multiplier)
					barrel.name = "Barrel_%s" % barrel_id
					_tag_presentation_target(barrel, barrel_id, "barrel", true)
					add_child(barrel)
					event_nodes[barrel_id] = barrel
			"gap":
				var gap := TrackGapScript.new() as Node2D
				gap.position = Vector2(x, 0.0)
				gap.call("configure", float(event.get("width", 160.0)), from_ceiling)
				gap.name = "Gap_%s" % event_id
				_tag_presentation_target(gap, event_id, kind, false)
				add_child(gap)
				event_nodes[event_id] = gap
			"step":
				var step := LedgeScene.instantiate() as Node2D
				var start_y := float(event.get("start_y", surface_y))
				var end_y := float(event.get("end_y", start_y))
				step.position = Vector2(x, 0.0)
				step.call("configure_step", start_y, end_y, from_ceiling, bool(event.get("spiked", false)))
				step.name = "Step_%s" % event_id
				_tag_presentation_target(step, event_id, kind, false)
				add_child(step)
				event_nodes[event_id] = step
				if from_ceiling: ceiling_y = end_y
				else: floor_y = end_y
			"slope":
				var slope := SlopeScene.instantiate() as Node2D
				var start_y := float(event.get("start_y", surface_y))
				var end_y := float(event.get("end_y", start_y))
				slope.position.x = float(event.get("start_x", x - 220.0))
				slope.call("configure", start_y, end_y, from_ceiling)
				slope.name = "Slope_%s" % event_id
				_tag_presentation_target(slope, event_id, kind, false)
				add_child(slope)
				event_nodes[event_id] = slope
				if from_ceiling: ceiling_y = end_y
				else: floor_y = end_y
			"rock":
				var rock := FallingRockScript.new() as Node2D
				rock.call("configure", event)
				rock.name = "FallingRock_%s" % event_id
				_tag_presentation_target(rock, event_id, kind, false)
				add_child(rock)
				event_nodes[event_id] = rock
	for collectible in manifest.collectibles:
		var coin := CoinScene.instantiate() as Node2D
		var entity_id := str(collectible.get("entity_id", ""))
		coin.position = Vector2(float(collectible.get("world_x", 0.0)), float(collectible.get("world_y", 0.0)))
		coin.name = "Coin_%s" % entity_id
		_tag_presentation_target(coin, entity_id, "coin", false)
		add_child(coin)
		event_nodes[entity_id] = coin
	for event in gap_events:
		var half_width := float(event.get("width", 0.0)) * 0.5
		var interval := {"start": float(event.get("x", 0.0)) - half_width, "end": float(event.get("x", 0.0)) + half_width}
		if bool(event.get("from_ceiling", false)):
			_render_ceiling_gaps.append(interval)
		else:
			_render_floor_gaps.append(interval)
	for event in terrain_events:
		if str(event.get("kind", "")) == "slope":
			_render_terrain_boundaries.append(float(event.get("start_x", 0.0)))
			_render_terrain_boundaries.append(float(event.get("end_x", 0.0)))
		else:
			_render_step_positions.append(float(event.get("x", 0.0)))
	_render_ceiling_gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
	_render_floor_gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
	_render_terrain_boundaries.sort()
	_render_step_positions.sort()
	return ""

func _tag_presentation_target(node: Node2D, stable_id: String, kind: String, moving: bool) -> void:
	# One metadata contract lets diagnostics include existing and future course
	# entities without adding a probe for every hazard type.
	node.set_meta("presentation_target", true)
	node.set_meta("presentation_target_id", stable_id)
	node.set_meta("presentation_target_kind", kind)
	node.set_meta("presentation_target_moving", moving)
	node.set_meta("presentation_target_obstacle", kind in ["block", "spikes", "barrel", "rock"])

func set_camera_left(camera_left: float) -> void:
	_camera_left = maxf(camera_left, 0.0)
	_update_rock_warning_accessibility_marker()
	queue_redraw()

func set_render_profile_enabled(enabled: bool) -> void:
	_render_profile_enabled = enabled

func begin_start_profile(deadline_usec: int) -> void:
	_start_draw_deadline_usec = deadline_usec
	_first_start_draw_profile.clear()

func take_start_draw_profile() -> Dictionary:
	var result := _first_start_draw_profile.duplicate(false)
	_first_start_draw_profile.clear()
	return result

func set_world_state(world_state: Dictionary) -> void:
	var rocks: Variant = world_state.get("rocks", [])
	_rock_warning_states.clear()
	if rocks is Array:
		for rock_state in rocks:
			if not rock_state is Dictionary:
				continue
			var rock_node: Variant = event_nodes.get(str(rock_state.get("event_id", "")))
			if is_instance_valid(rock_node) and rock_node.has_method("apply_world_state"):
				rock_node.call("apply_world_state", rock_state)
			if FallingRockModel.offscreen_marker_active(str(rock_state.get("phase", ""))):
				_rock_warning_states.append(rock_state)
	_rock_warning_pulse.call("observe_warning_events", _rock_warning_states)
	_update_rock_warning_accessibility_marker()
	queue_redraw()
	var barrels: Variant = world_state.get("barrels", [])
	if barrels is Array:
		for state_value in barrels:
			if not state_value is Dictionary:
				continue
			var state: Dictionary = state_value
			var node_value: Variant = event_nodes.get(str(state.get("entity_id", "")))
			if not is_instance_valid(node_value) or not node_value is Node2D:
				continue
			var node: Node2D = node_value
			node.call("apply_replicated_motion", Vector2(float(state.get("x", node.position.x)), float(state.get("y", node.position.y))), float(state.get("roll_angle", 0.0)), float(state.get("rotation", 0.0)), bool(state.get("spawned", false)))
			if bool(state.get("destroyed", false)):
				apply_destroyed_entity(str(state.get("entity_id", "")))
	var destroyed: Variant = world_state.get("destroyed_event_ids", [])
	if destroyed is Array:
		for event_id in destroyed:
			apply_destroyed_entity(str(event_id))
	var entities: Variant = world_state.get("entities", {})
	if entities is Dictionary:
		for entity_id in entities:
			if str(entities[entity_id].get("state", "active")) == "active":
				continue
			var entity_kind := str(entities[entity_id].get("kind", ""))
			var node_value: Variant = event_nodes.get(str(entity_id))
			if entity_kind == "coin" and is_instance_valid(node_value) and node_value is Node2D:
				if not bool(node_value.get("is_being_collected")):
					node_value.visible = false
			else:
				apply_destroyed_entity(str(entity_id))

func play_confirmed_coin_collection(entity_id: String, commit_id: String = "", request_id: String = "", round_id: String = "", incarnation: int = -1) -> bool:
	if entity_id.is_empty() or _confirmed_coin_bursts.has(entity_id):
		return false
	var coin: Variant = event_nodes.get(entity_id)
	if not is_instance_valid(coin) or not coin.has_method("animate_collection"):
		return false
	if _coin_visual_predictions.has(entity_id):
		var prediction: Dictionary = _coin_visual_predictions[entity_id]
		if (not round_id.is_empty() and str(prediction.get("round_id", "")) != round_id) or (incarnation >= 0 and int(prediction.get("incarnation", -1)) != incarnation):
			return false
		coin.visible = true
		coin.call("confirm_visual_prediction")
		_coin_visual_predictions.erase(entity_id)
	else:
		coin.visible = true
		if not bool(coin.call("animate_collection")):
			return false
	_confirmed_coin_bursts[entity_id] = {"commit_id": commit_id, "request_id": request_id, "round_id": round_id, "incarnation": incarnation}
	return true

func predict_coin_collection(entity_id: String, incarnation: int, round_id: String, request_id: String) -> bool:
	if entity_id.is_empty() or request_id.is_empty() or _coin_visual_predictions.has(entity_id) or _confirmed_coin_bursts.has(entity_id):
		return false
	var coin: Variant = event_nodes.get(entity_id)
	if not is_instance_valid(coin) or not coin.has_method("begin_visual_prediction"):
		return false
	if not bool(coin.call("begin_visual_prediction", request_id)):
		return false
	_coin_visual_predictions[entity_id] = {"incarnation": incarnation, "round_id": round_id, "request_id": request_id}
	return true

func resolve_coin_visual_prediction(entity_id: String, incarnation: int, round_id: String, request_id: String, still_active: bool) -> bool:
	var prediction: Dictionary = _coin_visual_predictions.get(entity_id, {})
	if prediction.is_empty() or int(prediction.get("incarnation", -1)) != incarnation or str(prediction.get("round_id", "")) != round_id or str(prediction.get("request_id", "")) != request_id:
		return false
	var coin: Variant = event_nodes.get(entity_id)
	_coin_visual_predictions.erase(entity_id)
	if not is_instance_valid(coin):
		return false
	if still_active:
		return bool(coin.call("reject_visual_prediction", request_id))
	coin.call("confirm_visual_prediction")
	_confirmed_coin_bursts[entity_id] = {"commit_id": "resolved_elsewhere", "request_id": request_id, "round_id": round_id, "incarnation": incarnation}
	return true

func apply_destroyed_entity(entity_id: String) -> void:
	var node_value: Variant = event_nodes.get(entity_id)
	if is_instance_valid(node_value) and node_value is Node2D:
		_destroy_node(node_value)
		return
	for child_id in event_nodes:
		if str(child_id).begins_with(entity_id + "_"):
			node_value = event_nodes[child_id]
			if is_instance_valid(node_value) and node_value is Node2D:
				_destroy_node(node_value)

func _destroy_node(node: Node2D) -> void:
	if node.has_method("is_destroying_now") and not bool(node.call("is_destroying_now")):
		node.call("destroy")

func reset() -> void:
	for child in get_children():
		if child == _rock_warning_accessibility_button:
			continue
		child.queue_free()
	event_nodes.clear()
	_confirmed_coin_bursts.clear()
	_coin_visual_predictions.clear()
	terrain_events.clear()
	gap_events.clear()
	_render_ceiling_gaps.clear()
	_render_floor_gaps.clear()
	_render_terrain_boundaries.clear()
	_render_step_positions.clear()
	manifest = null
	_surface_index = null
	_rock_warning_states.clear()
	_rock_warning_pulse.call("reset")
	_update_rock_warning_accessibility_marker()

func _draw() -> void:
	if manifest == null:
		return
	var draw_started_usec := Time.get_ticks_usec() if _render_profile_enabled else 0
	CourseSurfaceRenderer.draw_track_cached(self, _camera_left, get_viewport_rect().size, _render_ceiling_gaps, _render_floor_gaps, _render_terrain_boundaries, _render_step_positions, Callable(self, "_surface_y_at"), 0.0)
	_draw_rock_warning_markers()
	_draw_rock_hud_warning()
	var finish_screen_x := float(manifest.finish_x) - _camera_left
	if finish_screen_x >= 0.0 and finish_screen_x <= get_viewport_rect().size.x:
		draw_line(Vector2(float(manifest.finish_x), 0.0), Vector2(float(manifest.finish_x), _world_height), Color("f5d45e"), 4.0)
	if _render_profile_enabled:
		var draw_elapsed_usec := maxi(Time.get_ticks_usec() - draw_started_usec, 0)
		_render_profile_total_usec += draw_elapsed_usec
		_render_profile_max_usec = maxi(_render_profile_max_usec, draw_elapsed_usec)
		_render_profile_draw_count += 1
		if _start_draw_deadline_usec >= 0 and _first_start_draw_profile.is_empty():
			_first_start_draw_profile = {"at_usec": Time.get_ticks_usec(), "duration_usec": draw_elapsed_usec, "relative_to_deadline_usec": Time.get_ticks_usec() - _start_draw_deadline_usec, "kind": "terrain_and_finish_line_draw"}

func _draw_rock_warning_markers() -> void:
	var view_width := get_viewport_rect().size.x
	for state in _rock_warning_states:
		var event: Dictionary = state.get("event", {})
		var x := float(state.get("x", 0.0))
		if x - _camera_left <= view_width:
			continue
		var floor_y := float(event.get("floor_y", _world_height - 80.0))
		var marker_center := rock_warning_marker_center(_camera_left, get_viewport_rect().size, floor_y)
		RockWarningIcon.draw(self, marker_center, 48.0)
		RockWarningIcon.draw_forward_chevron(self, marker_center + Vector2(30.0, 0.0), 9.0)

func _draw_rock_hud_warning() -> void:
	if not bool(_rock_warning_pulse.call("is_active")):
		return
	var viewport_size := get_viewport_rect().size
	var center := rock_warning_hud_center(_camera_left, viewport_size)
	var pulse_scale := float(_rock_warning_pulse.call("scale"))
	RockWarningIcon.draw(self, center, 56.0 * pulse_scale, Color("ff814f"), float(_rock_warning_pulse.call("alpha")))

func _update_rock_warning_accessibility_marker() -> void:
	if not is_instance_valid(_rock_warning_accessibility_button):
		return
	_rock_warning_accessibility_button.visible = false
	if bool(_rock_warning_pulse.call("is_active")):
		var hud_center := rock_warning_hud_center(_camera_left, get_viewport_rect().size)
		_rock_warning_accessibility_button.position = hud_center - Vector2(24.0, 24.0)
		_rock_warning_accessibility_button.visible = true
		return
	var view_size := get_viewport_rect().size
	for state in _rock_warning_states:
		var event: Dictionary = state.get("event", {})
		var rock_x := float(state.get("x", 0.0))
		if rock_x < _camera_left:
			continue
		var center: Vector2
		if rock_x - _camera_left > view_size.x:
			center = rock_warning_marker_center(_camera_left, view_size, float(event.get("floor_y", _world_height - 80.0)))
		else:
			center = Vector2(rock_x, float(event.get("floor_y", _world_height - 80.0)) - 68.0)
		_rock_warning_accessibility_button.position = center - Vector2(24.0, 24.0)
		_rock_warning_accessibility_button.visible = true
		return

func take_render_profile() -> Dictionary:
	var result := {"terrain_draw_count": _render_profile_draw_count, "terrain_total_usec": _render_profile_total_usec, "terrain_max_usec": _render_profile_max_usec, "surface_query_count": _render_profile_surface_queries}
	_render_profile_total_usec = 0
	_render_profile_max_usec = 0
	_render_profile_draw_count = 0
	_render_profile_surface_queries = 0
	return result

func _surface_y_at(x: float, ceiling: bool) -> float:
	if _render_profile_enabled:
		_render_profile_surface_queries += 1
	if _surface_index != null:
		return float(_surface_index.surface_at(x, ceiling).get("y", _world_height * 0.5))
	var y := float(manifest.initial_ceiling_y) if ceiling else float(manifest.initial_floor_y)
	for event in terrain_events:
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
	return y
