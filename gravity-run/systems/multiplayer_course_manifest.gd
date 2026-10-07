extends Resource
class_name MultiplayerCourseManifest

const CourseGenerator := preload("res://systems/course_generator.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const CourseSurfaceIndexScript := preload("res://systems/course_surface_index.gd")
const LavaHazardModelScript := preload("res://systems/lava_hazard_model.gd")

@export var protocol_version := 2
@export var generator_version := 0
@export var match_rules_version := 2
@export var course_identity := ""
@export var seed_value: int = 0
@export var course_length_px := 0
@export var world_width := 960.0
@export var world_height := 540.0
@export var start_x := 180.0
@export var finish_x := 0.0
@export var initial_floor_y := 460.0
@export var initial_ceiling_y := 80.0
@export var ruleset_fingerprint := ""
@export var events: Array[Dictionary] = []
@export var collectibles: Array[Dictionary] = []
@export var manifest_hash := ""
var manifest_version := 3

var _verified_wire_hash := ""
var _verified_contents: Dictionary = {}

func to_canonical_dictionary() -> Dictionary:
	var data := {
		"protocol_version": protocol_version,
		"manifest_version": manifest_version,
		"match_rules_version": match_rules_version,
		"generator_version": generator_version,
		"course_identity": course_identity,
		"seed": seed_value,
		"course_length_px": course_length_px,
		"world": {
			"width": world_width,
			"height": world_height,
			"start_x": start_x,
			"finish_x": finish_x,
			"floor_y": initial_floor_y,
			"ceiling_y": initial_ceiling_y,
		},
		"ruleset_fingerprint": ruleset_fingerprint,
		"events": events.duplicate(true),
	}
	if manifest_version >= 3:
		data["collectibles"] = collectibles.duplicate(true)
	return data

func to_canonical_json() -> String:
	return JSON.stringify(to_canonical_dictionary(), "", true, true)

func calculate_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(to_canonical_json().to_utf8_buffer())
	return context.finish().hex_encode()

func load_canonical_dictionary(data: Dictionary, expected_wire_hash := "", wire_payload := PackedByteArray()) -> bool:
	manifest_version = int(data.get("manifest_version", -1))
	if manifest_version not in [2, 3, 4, 5, 6, 7, 8, 9, 10] or not data.get("world", {}) is Dictionary:
		return false
	if not expected_wire_hash.is_empty():
		if expected_wire_hash.length() != 64 or wire_payload.is_empty():
			return false
		var wire_context := HashingContext.new()
		wire_context.start(HashingContext.HASH_SHA256)
		wire_context.update(wire_payload)
		if wire_context.finish().hex_encode() != expected_wire_hash:
			return false
	var world: Dictionary = data.world
	protocol_version = int(data.get("protocol_version", 0))
	match_rules_version = int(data.get("match_rules_version", 0))
	generator_version = int(data.get("generator_version", 0))
	course_identity = str(data.get("course_identity", ""))
	seed_value = int(data.get("seed", 0))
	course_length_px = int(data.get("course_length_px", 0))
	world_width = float(world.get("width", 0.0))
	world_height = float(world.get("height", 0.0))
	start_x = float(world.get("start_x", 0.0))
	finish_x = float(world.get("finish_x", 0.0))
	initial_floor_y = float(world.get("floor_y", 0.0))
	initial_ceiling_y = float(world.get("ceiling_y", 0.0))
	ruleset_fingerprint = str(data.get("ruleset_fingerprint", ""))
	var raw_events: Variant = data.get("events", [])
	if not raw_events is Array:
		return false
	events.clear()
	for event in raw_events:
		if not event is Dictionary:
			return false
		events.append(event.duplicate(true))
	collectibles.clear()
	var raw_collectibles: Variant = data.get("collectibles", [])
	if manifest_version >= 3 and not raw_collectibles is Array:
		return false
	if raw_collectibles is Array:
		for collectible in raw_collectibles:
			if not collectible is Dictionary:
				return false
			collectibles.append(collectible.duplicate(true))
	if expected_wire_hash.is_empty():
		manifest_hash = calculate_hash()
	else:
		# Verify the exact bytes received. JSON float formatting may differ between
		# Godot's native and browser builds even when the parsed course is identical.
		manifest_hash = expected_wire_hash
		_verified_wire_hash = expected_wire_hash
		_verified_contents = to_canonical_dictionary().duplicate(true)
	return validate().is_empty()

func validate() -> String:
	if protocol_version != 2 or match_rules_version != 2:
		return "Unsupported multiplayer course protocol or rules version."
	if generator_version < 1 or seed_value <= 0:
		return "The course needs a supported generator version and positive seed."
	if course_length_px < 10000 or course_length_px > 1000000:
		return "The multiplayer course length is outside supported limits."
	if not is_finite(world_width) or not is_finite(world_height) or world_width <= 0.0 or world_height <= 0.0:
		return "The multiplayer world dimensions are invalid."
	if events.size() > 4000:
		return "The multiplayer manifest has too many events."
	if manifest_version not in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] or (generator_version == CourseGenerator.GENERATOR_VERSION_20 and manifest_version != 13) or (generator_version == CourseGenerator.GENERATOR_VERSION_19 and manifest_version != 12) or (generator_version == CourseGenerator.GENERATOR_VERSION_18 and manifest_version != 11) or (generator_version == CourseGenerator.GENERATOR_VERSION_17 and manifest_version != 10) or (generator_version == CourseGenerator.GENERATOR_VERSION_16 and manifest_version != 9) or (generator_version == CourseGenerator.GENERATOR_VERSION_15 and manifest_version != 8) or (generator_version == CourseGenerator.GENERATOR_VERSION_14 and manifest_version != 7) or (generator_version >= CourseGenerator.GENERATOR_VERSION_12 and generator_version < CourseGenerator.GENERATOR_VERSION_14 and manifest_version != 6) or (generator_version >= CourseGenerator.GENERATOR_VERSION_10 and generator_version < CourseGenerator.GENERATOR_VERSION_12 and manifest_version != 5) or (generator_version >= CourseGenerator.GENERATOR_VERSION_9 and generator_version < CourseGenerator.GENERATOR_VERSION_10 and manifest_version != 4) or (generator_version >= CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION and generator_version < CourseGenerator.GENERATOR_VERSION_9 and manifest_version != 3) or (generator_version < CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION and manifest_version != 2):
		return "The course generator and manifest versions are incompatible."
	var biome_start_offset := BiomeRendererScript.start_biome_offset_for_seed(seed_value, generator_version)
	var previous_x := -INF
	for event in events:
		if not event is Dictionary or not event.has("event_id") or not event.has("kind") or not event.has("x"):
			return "A manifest event is missing its stable identity or geometry."
		var event_x := float(event.x)
		if not is_finite(event_x) or event_x < start_x or event_x > finish_x + 1000.0 or event_x < previous_x:
			return "Manifest events must be finite, ordered, and inside the course bounds."
		if str(event.kind) not in ["spikes", "block", "barrels", "gap", "step", "slope", "rock", "saw", "ghost", "lava_crack", "volcano"] or (str(event.kind) == "rock" and generator_version < CourseGenerator.PUBLISHED_SHARED_GENERATOR_VERSION) or (str(event.kind) == "saw" and generator_version < CourseGenerator.GENERATOR_VERSION_9) or (str(event.kind) == "ghost" and generator_version < CourseGenerator.GENERATOR_VERSION_11) or (str(event.kind) in ["lava_crack", "volcano"] and generator_version < CourseGenerator.GENERATOR_VERSION_14):
			return "The manifest contains an unsupported dynamic or unknown event type."
		if str(event.kind) == "barrels" and bool(event.get("spiked", false)) and (generator_version < CourseGenerator.GENERATOR_VERSION_12 or not (event.get("spiked") is bool)):
			return "The manifest contains an invalid spiked-barrel variant."
		if str(event.kind) == "rock":
			var width := float(event.get("width", NAN))
			var height := float(event.get("height", NAN))
			var warning := int(event.get("warning_ticks", -1))
			var fall := int(event.get("fall_ticks", -1))
			var max_warning_ticks := 120 if generator_version >= 8 else 90
			if not is_finite(width) or not is_finite(height) or width < 60.0 or width > 140.0 or height < 60.0 or height > 150.0 or warning < 20 or warning > max_warning_ticks or fall < 8 or fall > 45 or not is_finite(float(event.get("floor_y", NAN))) or not is_finite(float(event.get("ceiling_y", NAN))):
				return "The falling rock has invalid versioned geometry or timing."
			if generator_version in [CourseGenerator.GENERATOR_VERSION_17, CourseGenerator.GENERATOR_VERSION_18, CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20] and int(event.get("rock_variant", 0)) == 1:
				var floor_supported_value: Variant = event.get("floor_supported", null)
				if not (event.get("rock_variant") is int) or not bool(event.get("from_ceiling", false)) or not (floor_supported_value is bool) or int(event.get("lodged_ticks", -1)) < 120 or int(event.get("lodged_ticks", -1)) > 360:
					return "The Gen17 icicle has invalid support or lifecycle data."
			elif generator_version >= CourseGenerator.GENERATOR_VERSION_17 and event.has("rock_variant"):
				return "The Gen17 rock variant is unsupported."
		if str(event.kind) == "saw":
			var spawn_x := float(event.get("spawn_x", NAN))
			var floor_y := float(event.get("floor_y", NAN))
			var ceiling_y := float(event.get("ceiling_y", NAN))
			var spawn_lead := float(event.get("spawn_lead", NAN))
			if not is_finite(spawn_x) or not is_finite(floor_y) or not is_finite(ceiling_y) or not is_finite(spawn_lead) or spawn_lead < 1200.0 or spawn_lead > 2000.0 or absf(spawn_x - float(event.x)) < 1000.0 or floor_y - ceiling_y < 260.0:
				return "The saw blade has invalid versioned geometry."
			if generator_version >= CourseGenerator.GENERATOR_VERSION_10:
				var variant := str(event.get("saw_variant", ""))
				var radius := float(event.get("saw_radius", NAN))
				if variant not in ["floor_embedded", "ceiling_embedded", "ceiling_gap_drop"] or not is_finite(radius) or not is_equal_approx(radius, 34.0) or (variant == "floor_embedded" and bool(event.get("from_ceiling", false))) or (variant != "floor_embedded" and not bool(event.get("from_ceiling", false))):
					return "The v10 saw is missing its explicit supported variant or collision radius."
				var has_gap := event.has("roof_gap_x") and event.has("roof_gap_width")
				if (variant == "ceiling_gap_drop") != has_gap:
					return "Only the v10 ceiling-drop saw may include an authored roof gap."
				if variant == "ceiling_gap_drop" and (not is_equal_approx(float(event.get("roof_gap_x", 0.0)), float(event.get("x", 0.0)) + SawModel.V10_DROP_ROOF_GAP_OFFSET) or not is_equal_approx(float(event.get("roof_gap_width", 0.0)), SawModel.V10_DROP_ROOF_GAP_WIDTH)):
					return "The v10 ceiling-drop saw has invalid gap placement."
			if bool(event.get("from_ceiling", false)) and (generator_version < CourseGenerator.GENERATOR_VERSION_10 or str(event.get("saw_variant", "")) == "ceiling_gap_drop"):
				var gap_x := float(event.get("roof_gap_x", NAN))
				var gap_width := float(event.get("roof_gap_width", NAN))
				var gap_offset := gap_x - float(event.x)
				if not is_finite(gap_x) or not is_finite(gap_width) or gap_offset < 600.0 or gap_offset > 1300.0 or gap_x >= spawn_x or gap_width < 80.0 or gap_width > 120.0:
					return "The ceiling-origin saw is missing its safe roof-gap route."
		if str(event.kind) == "ghost":
			var ghost_width := float(event.get("width", NAN))
			var ghost_height := float(event.get("height", NAN))
			var trigger_lead := float(event.get("trigger_lead", NAN))
			var warning_ticks := int(event.get("warning_ticks", -1))
			var danger_ticks := int(event.get("danger_ticks", -1))
			var fade_ticks := int(event.get("fade_ticks", -1))
			var legacy_ghost_timing := generator_version < CourseGenerator.GENERATOR_VERSION_16 and trigger_lead >= 1600.0 and trigger_lead <= 3200.0 and warning_ticks >= 90 and warning_ticks <= 180 and danger_ticks >= 180 and danger_ticks <= 600 and not event.has("skin_variant")
			var gen16_ghost_timing := generator_version == CourseGenerator.GENERATOR_VERSION_16 and is_equal_approx(trigger_lead, 1250.0) and warning_ticks == 60 and danger_ticks == 300 and event.get("skin_variant") is int and int(event.get("skin_variant")) in [0, 1, 2]
			var gen17_variant: Variant = event.get("ghost_variant", null)
			var gen17_ghost_timing := generator_version == CourseGenerator.GENERATOR_VERSION_17 and gen17_variant is int and int(gen17_variant) in [0, 1] and event.get("skin_variant") is int and int(event.get("skin_variant")) in [0, 1, 2] and ((int(gen17_variant) == 0 and is_equal_approx(trigger_lead, 1250.0) and warning_ticks == 60 and danger_ticks == 300 and int(event.get("blocked_lanes", 0)) in [CourseGenerator.FLOOR_LANE, CourseGenerator.CEILING_LANE]) or (int(gen17_variant) == 1 and is_equal_approx(trigger_lead, 1700.0) and warning_ticks == 54 and danger_ticks == 210 and is_equal_approx(float(event.get("chase_speed", NAN)), 760.0) and is_equal_approx(float(event.get("chase_start_lag", NAN)), 220.0) and int(event.get("blocked_lanes", 0)) == CourseGenerator.FLOOR_LANE))
			var gen18_variant: Variant = event.get("ghost_variant", null)
			var flyby_lag: Variant = event.get("flyby_start_lag", null)
			var flyby_delta: Variant = event.get("flyby_speed_delta", null)
			var ghost_from_ceiling: Variant = event.get("from_ceiling", null)
			var gen18_ghost_timing := false
			if generator_version == CourseGenerator.GENERATOR_VERSION_18 and gen18_variant is int and event.get("skin_variant") is int and int(event.get("skin_variant")) in [0, 1, 2]:
				var stationary_timing: bool = int(gen18_variant) == 0 and is_equal_approx(trigger_lead, 1250.0) and warning_ticks == 60 and danger_ticks == 300 and int(event.get("blocked_lanes", 0)) in [CourseGenerator.FLOOR_LANE, CourseGenerator.CEILING_LANE]
				var flyby_timing: bool = int(gen18_variant) == 2 and is_equal_approx(trigger_lead, 1500.0) and warning_ticks == 72 and danger_ticks == 120 and (flyby_lag is int or flyby_lag is float) and is_finite(float(flyby_lag)) and is_equal_approx(float(flyby_lag), 130.0) and (flyby_delta is int or flyby_delta is float) and is_finite(float(flyby_delta)) and is_equal_approx(float(flyby_delta), 500.0) and int(event.get("blocked_lanes", 0)) == CourseGenerator.BOTH_LANES and ghost_from_ceiling is bool
				gen18_ghost_timing = stationary_timing or flyby_timing
			var gen19_variant: Variant = event.get("ghost_variant", null)
			var pursuit_lag: Variant = event.get("pursuit_start_lag", null)
			var pursuit_delta: Variant = event.get("pursuit_speed_delta", null)
			if generator_version in [CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20] and gen19_variant is int and event.get("skin_variant") is int and int(event.get("skin_variant")) in [0, 1, 2]:
				var stationary_gen19: bool = int(gen19_variant) == 0 and is_equal_approx(trigger_lead, 1250.0) and warning_ticks == 60 and danger_ticks == 300 and int(event.get("blocked_lanes", 0)) in [CourseGenerator.FLOOR_LANE, CourseGenerator.CEILING_LANE]
				var pursuit_gen19: bool = int(gen19_variant) == 3 and is_equal_approx(trigger_lead, 2500.0) and warning_ticks == 90 and danger_ticks == 200 and (pursuit_lag is int or pursuit_lag is float) and is_finite(float(pursuit_lag)) and is_equal_approx(float(pursuit_lag), 330.0) and (pursuit_delta is int or pursuit_delta is float) and is_finite(float(pursuit_delta)) and is_equal_approx(float(pursuit_delta), 220.0) and int(event.get("blocked_lanes", 0)) == CourseGenerator.BOTH_LANES and ghost_from_ceiling is bool
				gen18_ghost_timing = stationary_gen19 or pursuit_gen19
			if not is_finite(ghost_width) or not is_finite(ghost_height) or not is_finite(trigger_lead) or ghost_width < 56.0 or ghost_width > 100.0 or ghost_height < 72.0 or ghost_height > 120.0 or not (legacy_ghost_timing or gen16_ghost_timing or gen17_ghost_timing or gen18_ghost_timing) or fade_ticks < 20 or fade_ticks > 90 or int(event.get("blocked_lanes", 0)) not in [1, 2, 3] or BiomeRendererScript.biome_id_for_generator(event_x - start_x + biome_start_offset, generator_version) != "haunted":
				return "The ghost hazard has invalid versioned geometry, timing, or biome."
		if str(event.kind) == "lava_crack":
			var crack_width := float(event.get("width", NAN))
			var hot_depth := float(event.get("hot_depth", NAN))
			var crack_y := float(event.get("y", NAN))
			var visual_depth := float(event.get("visual_depth", 0.0))
			var from_ceiling_value: Variant = event.get("from_ceiling", null)
			if not (from_ceiling_value is bool):
				return "The lava crack has invalid versioned geometry or biome."
			var from_ceiling := bool(from_ceiling_value)
			var width_valid := crack_width >= 96.0 and crack_width <= 150.0 if generator_version < CourseGenerator.GENERATOR_VERSION_15 else crack_width >= 150.0 and crack_width <= 180.0
			var depth_valid := hot_depth >= 8.0 and hot_depth <= 20.0 if generator_version < CourseGenerator.GENERATOR_VERSION_15 else hot_depth >= 12.0 and hot_depth <= 24.0
			var revision_valid := not event.has("lava_crack_revision") and not event.has("visual_depth") if generator_version < CourseGenerator.GENERATOR_VERSION_15 else int(event.get("lava_crack_revision", -1)) == 1 and visual_depth >= 24.0 and visual_depth <= 44.0
			if not is_finite(crack_width) or not is_finite(hot_depth) or not is_finite(crack_y) or not is_finite(visual_depth) or not width_valid or not depth_valid or not revision_valid or crack_y < 40.0 or crack_y > 500.0 or int(event.get("blocked_lanes", 0)) != (2 if from_ceiling else 1) or BiomeRendererScript.biome_id_for_generator(event_x - start_x + biome_start_offset, generator_version) != "lava":
				return "The lava crack has invalid versioned geometry or biome."
			if generator_version in [CourseGenerator.GENERATOR_VERSION_17, CourseGenerator.GENERATOR_VERSION_18, CourseGenerator.GENERATOR_VERSION_19, CourseGenerator.GENERATOR_VERSION_20] and event.has("lava_variant"):
				var variant: Variant = event.get("lava_variant")
				if not (variant is int) or int(variant) != 1 or from_ceiling or not (event.get("pool_period_ticks") is int) or int(event.get("pool_period_ticks", 0)) < 120 or int(event.get("pool_period_ticks", 0)) > 240 or float(event.get("pool_min_depth", NAN)) < 4.0 or float(event.get("pool_max_depth", NAN)) > 36.0 or float(event.get("pool_min_depth", NAN)) > float(event.get("pool_max_depth", NAN)) or int(event.get("pool_phase_ticks", -1)) < 0:
					return "The Gen17 tidal pool has invalid phase or hot-area geometry."
			elif generator_version < CourseGenerator.GENERATOR_VERSION_17 and event.has("lava_variant"):
				return "The tidal lava variant requires Gen17."
		if str(event.kind) == "volcano":
			var volcano_width := float(event.get("width", NAN))
			var volcano_height := float(event.get("height", NAN))
			var floor_y := float(event.get("floor_y", NAN))
			var ceiling_y := float(event.get("ceiling_y", NAN))
			var lead := float(event.get("eruption_lead", NAN))
			var period := int(event.get("eruption_period_ticks", -1))
			var lifetime := int(event.get("projectile_lifetime_ticks", -1))
			var projectile_speed := float(event.get("projectile_speed", NAN))
			var vertical_speed := float(event.get("projectile_vertical_speed", NAN))
			var projectile_gravity := float(event.get("projectile_gravity", NAN))
			var projectile_radius := float(event.get("projectile_radius", NAN))
			var ceiling_runner_bottom := ceiling_y + RunnerMotion.SIZE.y
			var common_volcano_valid := is_finite(volcano_width) and is_finite(volcano_height) and is_finite(floor_y) and is_finite(ceiling_y) and is_finite(lead) and is_finite(projectile_speed) and is_finite(vertical_speed) and is_finite(projectile_gravity) and is_finite(projectile_radius) and volcano_width >= 100.0 and volcano_width <= 150.0 and volcano_height >= 56.0 and volcano_height <= 96.0 and floor_y - ceiling_y >= 300.0 and lead >= 1200.0 and lead <= 2400.0 and period >= 120 and period <= 220 and lifetime >= 40 and lifetime <= 70 and int(event.get("blocked_lanes", 0)) == 1 and BiomeRendererScript.biome_id_for_generator(event_x - start_x + biome_start_offset, generator_version) == "lava"
			var trajectory_valid := true
			if generator_version < CourseGenerator.GENERATOR_VERSION_15:
				var legacy_apex_top := floor_y - volcano_height * 0.78 - vertical_speed * vertical_speed / maxf(2.0 * projectile_gravity, 1.0) - projectile_radius
				trajectory_valid = not event.has("projectile_fan_revision") and not event.has("projectile_arcs") and projectile_speed >= 200.0 and projectile_speed <= 420.0 and vertical_speed >= 400.0 and vertical_speed <= 430.0 and projectile_gravity >= 900.0 and projectile_gravity <= 1200.0 and projectile_radius >= 10.0 and projectile_radius <= 18.0 and legacy_apex_top >= ceiling_runner_bottom + 24.0
			else:
				var fan_revision: Variant = event.get("projectile_fan_revision", null)
				var raw_arcs: Variant = event.get("projectile_arcs", null)
				trajectory_valid = fan_revision is int and int(fan_revision) == 1 and raw_arcs is Array and raw_arcs.size() == 3 and lifetime == 60
				if trajectory_valid:
					for arc_value in raw_arcs:
						if not arc_value is Dictionary:
							trajectory_valid = false
							break
						var arc: Dictionary = arc_value
						var arc_speed := float(arc.get("horizontal_speed", NAN))
						var arc_vertical := float(arc.get("vertical_speed", NAN))
						var arc_gravity := float(arc.get("gravity", NAN))
						var arc_radius := float(arc.get("radius", NAN))
						var arc_lifetime := int(arc.get("lifetime_ticks", -1))
						var arc_apex := floor_y - volcano_height * 0.78 - arc_vertical * arc_vertical / maxf(2.0 * arc_gravity, 1.0) - arc_radius
						if not is_finite(arc_speed) or not is_finite(arc_vertical) or not is_finite(arc_gravity) or not is_finite(arc_radius) or arc_speed < 180.0 or arc_speed > 480.0 or arc_vertical < 350.0 or arc_vertical > 620.0 or arc_gravity < 850.0 or arc_gravity > 1250.0 or arc_radius < 9.0 or arc_radius > 18.0 or arc_lifetime < 40 or arc_lifetime > 70 or arc_apex < ceiling_runner_bottom + 24.0:
							trajectory_valid = false
							break
					trajectory_valid = trajectory_valid and absf(projectile_speed - 450.0) < 0.01 and absf(vertical_speed - 580.0) < 0.01 and absf(projectile_gravity - 1100.0) < 0.01 and absf(projectile_radius - 15.0) < 0.01
			if not common_volcano_valid or not trajectory_valid:
				return "The volcano has invalid versioned geometry, projectile timing, or biome."
		previous_x = event_x
	if generator_version >= CourseGenerator.GENERATOR_VERSION_15:
		var surface_index := CourseSurfaceIndexScript.new()
		surface_index.configure(events, initial_floor_y, initial_ceiling_y)
		for event in events:
			if str(event.get("kind", "")) == "volcano" and not LavaHazardModelScript.gen15_ceiling_route_is_supported(event, surface_index, start_x):
				return "The Gen15 volcano fan has an unsupported or unsafe ceiling route across its projectile envelope."
			if generator_version >= CourseGenerator.GENERATOR_VERSION_17:
				var event_x := float(event.get("x", 0.0))
				var kind := str(event.get("kind", ""))
				if kind == "ghost" and int(event.get("ghost_variant", 0)) == 1:
					var width := float(event.get("width", 72.0))
					var begin_x := event_x - float(event.get("trigger_lead", 1700.0)) - float(event.get("chase_start_lag", 220.0)) - width * 0.5
					var finish_x := event_x - float(event.get("trigger_lead", 1700.0)) - float(event.get("chase_start_lag", 220.0)) + float(event.get("chase_speed", 760.0)) * float(event.get("danger_ticks", 150)) / 60.0 + width * 0.5
					if not bool(surface_index.call("interval_is_supported", begin_x, finish_x, true)) or not bool(surface_index.call("interval_is_supported", begin_x, finish_x, false)):
						return "The Gen17 chaser lacks supported chase terrain or a continuous ceiling escape route."
				elif kind == "rock" and int(event.get("rock_variant", 0)) == 1:
					var icicle_half_width := float(event.get("width", 52.0)) * 0.5
					var actual_floor_support := bool(surface_index.call("interval_is_supported", event_x - icicle_half_width, event_x + icicle_half_width, false))
					var actual_ceiling_support := bool(surface_index.call("surface_at", event_x, true).get("supported", false))
					if actual_floor_support != bool(event.get("floor_supported", false)) or not actual_ceiling_support:
						return "The Gen17 icicle support declaration does not match resolved terrain."
				elif kind == "lava_crack" and int(event.get("lava_variant", 0)) == 1:
					var half_width := float(event.get("width", 160.0)) * 0.5 + RunnerMotion.SIZE.x * 0.5
					if not bool(surface_index.call("interval_is_supported", event_x - half_width, event_x + half_width, true)):
						return "The Gen17 tidal pool lacks a continuous ceiling escape route."
	var seen_collectibles: Dictionary = {}
	if collectibles.size() > CoinPlanner.MAX_PLANNED_COINS or (manifest_version == 2 and not collectibles.is_empty()):
		return "The multiplayer manifest has an invalid collectible set."
	for collectible in collectibles:
		var entity_id := str(collectible.get("entity_id", ""))
		var x := float(collectible.get("world_x", NAN))
		var y := float(collectible.get("world_y", NAN))
		var radius := float(collectible.get("radius", NAN))
		var value := int(collectible.get("value", 0))
		if entity_id.is_empty() or seen_collectibles.has(entity_id) or str(collectible.get("kind", "")) != "coin" or not is_finite(x) or not is_finite(y) or not is_finite(radius) or radius <= 0.0 or value != 1 or x < start_x or x > finish_x:
			return "The multiplayer manifest contains an invalid coin."
		seen_collectibles[entity_id] = true
	var hash_matches := calculate_hash() == manifest_hash if _verified_wire_hash.is_empty() else (
		_verified_wire_hash == manifest_hash and _verified_contents == to_canonical_dictionary()
	)
	if manifest_hash.length() != 64 or not hash_matches:
		return "The multiplayer manifest hash does not match its canonical contents."
	return ""
