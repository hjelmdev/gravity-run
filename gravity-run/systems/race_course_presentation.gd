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

var manifest: Resource
var event_nodes: Dictionary = {}
var terrain_events: Array[Dictionary] = []
var gap_events: Array[Dictionary] = []
var _camera_left := 0.0
var _world_height := 720.0

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
					var spike := SpikeScene.instantiate() as Node2D
					spike.position = Vector2(start_x + float(index) * float(event.get("spacing", 32.0)), float(event.get("y", surface_y)))
					spike.call("configure", Vector2(CourseGenerator.SPIKE_WIDTH, CourseGenerator.SPIKE_HEIGHT), from_ceiling)
					spike.name = "Spike_%s_%d" % [event_id, index]
					add_child(spike)
					event_nodes["%s_%d" % [event_id, index]] = spike
			"block":
				var block := BlockScene.instantiate() as Node2D
				block.position = Vector2(x, float(event.get("y", surface_y)))
				block.call("configure", Vector2(float(event.get("width", 48.0)), float(event.get("height", 72.0))), from_ceiling)
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
					var barrel := BarrelScene.instantiate() as Node2D
					barrel.position = Vector2(x + spawn_offset - chain_width * 0.5 + float(index) * spacing, float(event.get("y", floor_y)))
					barrel.call("configure", Vector2(HazardRules.BARREL_WIDTH, float(event.get("height", HazardRules.BARREL_WIDTH))), false)
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
	return ""

func set_camera_left(camera_left: float) -> void:
	_camera_left = maxf(camera_left, 0.0)
	queue_redraw()

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
	manifest = null

func _draw() -> void:
	if manifest == null:
		return
	var gaps: Array[Dictionary] = []
	for event in gap_events:
		var half_width := float(event.get("width", 0.0)) * 0.5
		gaps.append({"start": float(event.get("x", 0.0)) - half_width, "end": float(event.get("x", 0.0)) + half_width, "ceiling": bool(event.get("from_ceiling", false))})
	var boundaries: Array[float] = []
	var steps: Array[float] = []
	for event in terrain_events:
		if str(event.get("kind", "")) == "slope":
			boundaries.append(float(event.get("start_x", 0.0)))
			boundaries.append(float(event.get("end_x", 0.0)))
		else:
			steps.append(float(event.get("x", 0.0)))
	CourseSurfaceRenderer.draw_track(self, _camera_left, get_viewport_rect().size, gaps, boundaries, steps, Callable(self, "_surface_y_at"), 0.0)
	var finish_screen_x := float(manifest.finish_x) - _camera_left
	if finish_screen_x >= 0.0 and finish_screen_x <= get_viewport_rect().size.x:
		draw_line(Vector2(finish_screen_x, 0.0), Vector2(finish_screen_x, _world_height), Color("f5d45e"), 4.0)

func _surface_y_at(x: float, ceiling: bool) -> float:
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
