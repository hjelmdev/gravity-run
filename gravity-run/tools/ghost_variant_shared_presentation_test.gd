extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var result: Dictionary = Builder.new().build(100000005, 45000, 16)
	_check(result.get("manifest") is Resource, "Gen16 manifest builds for shared presentation")
	if result.get("manifest") is Resource:
		var manifest: Resource = result.manifest
		var expected: Dictionary = {}
		for event_value in manifest.events:
			if event_value is Dictionary and str(event_value.get("kind", "")) == "ghost":
				expected[str(event_value.get("event_id", ""))] = int(event_value.get("skin_variant", -1))
		_check(not expected.is_empty(), "the selected manifest contains a ghost event")
		var presentation := Presentation.new()
		add_child(presentation)
		var error := str(presentation.call("load_manifest", manifest))
		_check(error.is_empty(), "shared MP presentation accepts the generated Gen16 manifest")
		var nodes: Dictionary = presentation.get("event_nodes")
		var matched := 0
		for event_id in expected:
			if not nodes.has(event_id):
				continue
			var ghost: Node = nodes[event_id]
			_check(ghost.is_in_group("ghost_hazards"), "manifest ghost is represented by the shared ghost scene")
			_check(int(ghost.get("skin_variant")) == int(expected[event_id]), "shared MP scene displays the deterministic event skin")
			_check(ghost.get("event") is Dictionary, "shared scene retains canonical event identity and collision parameters")
			matched += 1
		_check(matched == expected.size(), "every manifest ghost has exactly one shared presentation node")
		presentation.queue_free()
	if failures == 0:
		print("GHOST_VARIANT_SHARED_PRESENTATION PASS ghosts=%d seed=GR16-100000005" % (result.manifest.events.filter(func(value): return value is Dictionary and str(value.get("kind", "")) == "ghost").size() if result.get("manifest") is Resource else 0))
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
