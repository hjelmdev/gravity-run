extends Resource
class_name MultiplayerCourseManifest

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
@export var manifest_hash := ""

func to_canonical_dictionary() -> Dictionary:
	return {
		"protocol_version": protocol_version,
		"manifest_version": 2,
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

func to_canonical_json() -> String:
	return JSON.stringify(to_canonical_dictionary(), "", true, true)

func calculate_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(to_canonical_json().to_utf8_buffer())
	return context.finish().hex_encode()

func load_canonical_dictionary(data: Dictionary) -> bool:
	if int(data.get("manifest_version", -1)) != 2 or not data.get("world", {}) is Dictionary:
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
	manifest_hash = calculate_hash()
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
	var previous_x := -INF
	for event in events:
		if not event is Dictionary or not event.has("event_id") or not event.has("kind") or not event.has("x"):
			return "A manifest event is missing its stable identity or geometry."
		var event_x := float(event.x)
		if not is_finite(event_x) or event_x < start_x or event_x > finish_x + 1000.0 or event_x < previous_x:
			return "Manifest events must be finite, ordered, and inside the course bounds."
		if str(event.kind) not in ["spikes", "block", "barrels", "gap", "step", "slope"]:
			return "The manifest contains an unsupported dynamic or unknown event type."
		previous_x = event_x
	if manifest_hash.length() != 64 or calculate_hash() != manifest_hash:
		return "The multiplayer manifest hash does not match its canonical contents."
	return ""
