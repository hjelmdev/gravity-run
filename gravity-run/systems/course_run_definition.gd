extends Resource
class_name CourseRunDefinition
## Immutable-by-convention input contract for one deterministic course run.
## Endless/challenge runs create this at runtime; fixed campaign stages can be
## authored as resources with a permanent seed and ruleset reference.

const CourseGeneratorScript = preload("res://systems/course_generator.gd")

@export var scenario_id: StringName = &"endless"
@export_range(1, 2147483647, 1) var seed_value := 1
@export_range(1, 1000, 1) var generator_version := CourseGeneratorScript.GENERATOR_VERSION
@export var ruleset: Resource

func validate() -> String:
	if scenario_id == StringName():
		return "A run definition needs a stable scenario ID."
	if seed_value <= 0:
		return "A deterministic run needs a positive seed."
	if generator_version < 1:
		return "A run definition needs a supported generator version."
	if ruleset == null:
		return "A run definition needs a generation ruleset."
	if not ruleset.has_method("get_fingerprint"):
		return "The run ruleset must expose a stable fingerprint."
	return ""

## Comparison key excludes scenario_id: different entry points using identical
## generation rules and seed describe the same course.
func get_course_identity() -> String:
	if ruleset == null or not ruleset.has_method("get_fingerprint"):
		return ""
	return "%d:%s:%d" % [generator_version, str(ruleset.call("get_fingerprint")), seed_value]
