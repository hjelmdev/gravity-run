extends Resource
class_name MultiplayerCourseManifest

const CourseGenerator := preload("res://systems/course_generator.gd")
const CoinPlanner := preload("res://systems/shared_coin_planner.gd")

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
	if manifest_version not in [2, 3] or not data.get("world", {}) is Dictionary:
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
	if manifest_version not in [2, 3] or (generator_version >= CourseGenerator.GENERATOR_VERSION and manifest_version != 3) or (generator_version <= CourseGenerator.PREVIOUS_GENERATOR_VERSION and manifest_version != 2):
		return "The course generator and manifest versions are incompatible."
	var previous_x := -INF
	for event in events:
		if not event is Dictionary or not event.has("event_id") or not event.has("kind") or not event.has("x"):
			return "A manifest event is missing its stable identity or geometry."
		var event_x := float(event.x)
		if not is_finite(event_x) or event_x < start_x or event_x > finish_x + 1000.0 or event_x < previous_x:
			return "Manifest events must be finite, ordered, and inside the course bounds."
		if str(event.kind) not in ["spikes", "block", "barrels", "gap", "step", "slope", "rock"] or (str(event.kind) == "rock" and generator_version < CourseGenerator.GENERATOR_VERSION):
			return "The manifest contains an unsupported dynamic or unknown event type."
		if str(event.kind) == "rock":
			var width := float(event.get("width", NAN))
			var height := float(event.get("height", NAN))
			var warning := int(event.get("warning_ticks", -1))
			var fall := int(event.get("fall_ticks", -1))
			if not is_finite(width) or not is_finite(height) or width < 60.0 or width > 140.0 or height < 60.0 or height > 150.0 or warning < 20 or warning > 90 or fall < 8 or fall > 45 or not is_finite(float(event.get("floor_y", NAN))) or not is_finite(float(event.get("ceiling_y", NAN))):
				return "The falling rock has invalid versioned geometry or timing."
		previous_x = event_x
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
