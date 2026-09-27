extends RefCounted
class_name CourseManifestBuilder

const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const CourseRulesetScript := preload("res://systems/course_generation_ruleset.gd")
const CourseRunDefinitionScript := preload("res://systems/course_run_definition.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")

const PLAYER_START_X := 180.0
const WORLD_WIDTH := 960.0
const WORLD_HEIGHT := 540.0
const FLOOR_START_Y := WORLD_HEIGHT - 80.0
const CEILING_START_Y := 80.0
const SLOPE_WIDTH := 440.0
const SPIKE_GROUP_SPACING := 32.0
const STEP_SPIKE_CLEARANCE := 32.0

func build(seed_value: int, course_length_px: int, generator_version: int = CourseGenerator.GENERATOR_VERSION) -> Dictionary:
	if seed_value <= 0:
		return {"manifest": null, "error": "A positive deterministic seed is required."}
	if course_length_px < 10000 or course_length_px > 1000000:
		return {"manifest": null, "error": "The course length is outside supported limits."}
	var ruleset := _make_multiplayer_ruleset()
	var definition := CourseRunDefinitionScript.new() as Resource
	definition.set("scenario_id", &"multiplayer_race")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", generator_version)
	definition.set("ruleset", ruleset)
	var definition_error := str(definition.call("validate"))
	if not definition_error.is_empty():
		return {"manifest": null, "error": definition_error}

	var generator := CourseGeneratorScript.new() as CourseGenerator
	if not generator.configure_run_definition(definition):
		return {"manifest": null, "error": "Could not configure deterministic multiplayer course generation."}
	generator.ensure_horizon(float(course_length_px), 500.0, CourseGenerator.REFERENCE_TRACK_HEIGHT, CourseGenerator.EVENT_SPAWN_LEAD_DISTANCE)
	var source_events: Array[Dictionary] = generator.get_planned_events()
	var manifest := ManifestScript.new() as MultiplayerCourseManifest
	manifest.generator_version = generator_version
	manifest.course_identity = str(definition.call("get_course_identity"))
	manifest.seed_value = seed_value
	manifest.course_length_px = course_length_px
	manifest.start_x = PLAYER_START_X
	manifest.finish_x = PLAYER_START_X + float(course_length_px)
	manifest.ruleset_fingerprint = str(ruleset.call("get_fingerprint"))
	manifest.events = _resolve_events(source_events, course_length_px)
	manifest.manifest_hash = manifest.calculate_hash()
	var manifest_error := str(manifest.call("validate"))
	if not manifest_error.is_empty():
		return {"manifest": null, "error": manifest_error}
	return {"manifest": manifest, "error": ""}

func _make_multiplayer_ruleset() -> Resource:
	var ruleset := CourseRulesetScript.new() as Resource
	ruleset.set("ruleset_id", &"multiplayer_race")
	ruleset.set("revision", 1)
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray([
		"spike_group", "block", "floor_gap", "ceiling_gap", "terrain_step", "terrain_slope",
	]))
	return ruleset

func _resolve_events(source_events: Array[Dictionary], course_length_px: int) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	var floor_y := FLOOR_START_Y
	var ceiling_y := CEILING_START_Y
	var event_index := 0
	for source in source_events:
		var course_distance := float(source.get("course_distance", 0.0))
		if course_distance > float(course_length_px):
			break
		var event_x := PLAYER_START_X + course_distance
		var kind := str(source.get("kind", ""))
		var from_ceiling := bool(source.get("from_ceiling", false))
		var surface_y := ceiling_y if from_ceiling else floor_y
		var event_prefix := "event_%05d" % event_index
		match kind:
			"spikes":
				var count := int(source.get("count", 4))
				var width := float((count - 1) * 32 + 28)
				resolved.append({
					"event_id": event_prefix,
					"kind": "spikes",
					"x": event_x,
					"start_x": event_x - width * 0.5,
					"y": surface_y,
					"count": count,
					"spacing": SPIKE_GROUP_SPACING,
					"width": width,
					"from_ceiling": from_ceiling,
				})
			"block":
				resolved.append({
					"event_id": event_prefix,
					"kind": "block",
					"x": event_x,
					"y": surface_y,
					"width": float(source.get("width", 48.0)),
					"height": float(source.get("height", 72.0)),
					"from_ceiling": from_ceiling,
				})
			"gap":
				resolved.append({
					"event_id": event_prefix,
					"kind": "gap",
					"x": event_x,
					"width": float(source.get("width", 160.0)),
					"from_ceiling": from_ceiling,
				})
			"step":
				var start_y := surface_y
				var change := float(source.get("height", 84.0))
				var low_limit := 40.0 if from_ceiling else 330.0
				var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
				var end_y := start_y + change if from_ceiling else start_y - change
				end_y = clampf(end_y, low_limit, high_limit)
				if absf(end_y - start_y) < 40.0:
					end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
				resolved.append({
					"event_id": event_prefix,
					"kind": "step",
					"x": event_x,
					"start_y": start_y,
					"end_y": end_y,
					"from_ceiling": from_ceiling,
					"spiked": bool(source.get("spiked_step", false)),
				})
				if bool(source.get("spiked_step", false)):
					var spike_count := int(source.get("count", 4))
					var spike_width := float((spike_count - 1) * SPIKE_GROUP_SPACING)
					var points_left := (end_y < start_y) != from_ceiling
					var spike_start_x := event_x + STEP_SPIKE_CLEARANCE if points_left else event_x - spike_width - STEP_SPIKE_CLEARANCE
					resolved.append({
						"event_id": event_prefix + "_spikes",
						"kind": "spikes",
						"x": spike_start_x,
						"start_x": spike_start_x,
					"y": end_y if points_left else start_y,
					"count": spike_count,
					"spacing": SPIKE_GROUP_SPACING,
					"width": spike_width + 28.0,
					"from_ceiling": from_ceiling,
				})
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y
			"slope":
				var start_y := surface_y
				var low_limit := 40.0 if from_ceiling else 330.0
				var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
				var direction := float(source.get("slope_direction", 1.0))
				var end_y := clampf(start_y + direction * float(source.get("height", 65.0)), low_limit, high_limit)
				if absf(end_y - start_y) < 40.0:
					end_y = clampf(start_y - direction * 45.0, low_limit, high_limit)
				resolved.append({
					"event_id": event_prefix,
					"kind": "slope",
					"x": event_x,
					"start_x": event_x - SLOPE_WIDTH * 0.5,
					"end_x": event_x + SLOPE_WIDTH * 0.5,
					"start_y": start_y,
					"end_y": end_y,
					"from_ceiling": from_ceiling,
				})
				if from_ceiling:
					ceiling_y = end_y
				else:
					floor_y = end_y
			_:
				push_error("Unsupported multiplayer course event kind '%s'." % kind)
		event_index += 1
	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.x), float(b.x)):
			return float(a.x) < float(b.x)
		return str(a.event_id) < str(b.event_id)
	)
	return resolved
