extends Node2D
class_name RaceCoursePresentation

const SpikeScene := preload("res://hazards/spikes.tscn")
const BlockScene := preload("res://hazards/block.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const LedgeScene := preload("res://terrain/ledge.tscn")
const SlopeScene := preload("res://terrain/slope.tscn")
const TrackGapScript := preload("res://terrain/track_gap.gd")
const CourseGenerator := preload("res://systems/course_generator.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const CourseSurfaceRenderer := preload("res://systems/course_surface_renderer.gd")
const SurfaceIndexScript := preload("res://systems/course_surface_index.gd")

var manifest: Resource
var event_nodes: Dictionary = {}
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
var _surface_index

static func create_hazard(scene: PackedScene, at_position: Vector2, size: Vector2, from_ceiling: bool, surface_rotation: float = 0.0) -> Node2D:
	var hazard := scene.instantiate() as Node2D
	hazard.position = at_position
	hazard.call("configure", size, from_ceiling)
	hazard.rotation = surface_rotation
	return hazard

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
					add_child(spike)
					event_nodes["%s_%d" % [event_id, index]] = spike
			"block":
				var block := create_hazard(BlockScene, Vector2(x, float(event.get("y", surface_y))), Vector2(float(event.get("width", 48.0)), float(event.get("height", 72.0))), from_ceiling)
				block.name = "Block_%s" % event_id
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
					add_child(barrel)
					event_nodes[barrel_id] = barrel
			"gap":
				var gap := TrackGapScript.new() as Node2D
				gap.position = Vector2(x, 0.0)
				gap.call("configure", float(event.get("width", 160.0)), from_ceiling)
				gap.name = "Gap_%s" % event_id
				add_child(gap)
				event_nodes[event_id] = gap
			"step":
				var step := LedgeScene.instantiate() as Node2D
				var start_y := float(event.get("start_y", surface_y))
				var end_y := float(event.get("end_y", start_y))
				step.position = Vector2(x, 0.0)
				step.call("configure_step", start_y, end_y, from_ceiling, bool(event.get("spiked", false)))
				step.name = "Step_%s" % event_id
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
				add_child(slope)
				event_nodes[event_id] = slope
				if from_ceiling: ceiling_y = end_y
				else: floor_y = end_y
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

func set_camera_left(camera_left: float) -> void:
	_camera_left = maxf(camera_left, 0.0)
	queue_redraw()

func set_render_profile_enabled(enabled: bool) -> void:
	_render_profile_enabled = enabled

func set_world_state(world_state: Dictionary) -> void:
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
			if str(entities[entity_id].get("state", "active")) != "active":
				apply_destroyed_entity(str(entity_id))

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
		child.queue_free()
	event_nodes.clear()
	terrain_events.clear()
	gap_events.clear()
	_render_ceiling_gaps.clear()
	_render_floor_gaps.clear()
	_render_terrain_boundaries.clear()
	_render_step_positions.clear()
	manifest = null
	_surface_index = null

func _draw() -> void:
	if manifest == null:
		return
	var draw_started_usec := Time.get_ticks_usec() if _render_profile_enabled else 0
	CourseSurfaceRenderer.draw_track_cached(self, _camera_left, get_viewport_rect().size, _render_ceiling_gaps, _render_floor_gaps, _render_terrain_boundaries, _render_step_positions, Callable(self, "_surface_y_at"), 0.0)
	var finish_screen_x := float(manifest.finish_x) - _camera_left
	if finish_screen_x >= 0.0 and finish_screen_x <= get_viewport_rect().size.x:
		draw_line(Vector2(float(manifest.finish_x), 0.0), Vector2(float(manifest.finish_x), _world_height), Color("f5d45e"), 4.0)
	if _render_profile_enabled:
		var draw_elapsed_usec := maxi(Time.get_ticks_usec() - draw_started_usec, 0)
		_render_profile_total_usec += draw_elapsed_usec
		_render_profile_max_usec = maxi(_render_profile_max_usec, draw_elapsed_usec)
		_render_profile_draw_count += 1

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
