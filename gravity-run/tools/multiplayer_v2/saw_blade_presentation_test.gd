extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(1, 45000, 9)
	var manifest: Resource = built.get("manifest")
	_check(manifest != null, "manifest builds: %s" % str(built.get("error", "")))
	if manifest == null:
		quit(1)
		return
	var world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(world.configure(manifest)).is_empty(), "shared simulation configures")
	var presentation := PresentationScript.new() as RaceCoursePresentation
	root.add_child(presentation)
	_check(str(presentation.load_manifest(manifest)).is_empty(), "real MP presentation loads v9 manifest")
	var target_saw: Dictionary = {}
	for saw in world.saws:
		if bool(saw.event.get("from_ceiling", false)):
			target_saw = saw
			break
	_check(not target_saw.is_empty(), "fixture contains a ceiling-origin saw")
	if target_saw.is_empty():
		quit(1)
		return
	var saw_id := str(target_saw.event_id)
	var activation_tick := 12
	var activate_commit := {"world_revision": world.entity_ledger.revision + 1, "commit_id": "presentation-saw-%s" % saw_id, "entity_id": saw_id, "incarnation": 1, "action": "activate_saw", "effective_tick": activation_tick, "saw_activation_tick": activation_tick, "state_before": "active", "state_after": "active"}
	_check(world.apply_world_commit(activate_commit) == "applied", "host world commit activates the presentation saw")
	for tick in range(1, 105):
		world.step_to(tick)
	presentation.call("set_world_state", world.render_state(0.5))
	var saw_node: Variant = presentation.event_nodes.get(saw_id)
	_check(is_instance_valid(saw_node) and saw_node.scene_file_path == "res://hazards/saw_blade.tscn", "MP instantiates the same SawBlade scene as SP")
	if is_instance_valid(saw_node):
		_check(bool(saw_node.state.get("falling", false)), "MP scene receives the shared falling phase")
		_check(saw_node.visible, "active MP saw is visible")
	for tick in range(105, 181):
		world.step_to(tick)
	presentation.call("set_world_state", world.render_state(0.5))
	if is_instance_valid(saw_node):
		_check(not bool(saw_node.state.get("falling", true)) and not bool(saw_node.state.get("ceiling_lane", true)), "MP scene receives floor landing after ceiling gap")
		_check(absf(saw_node.global_position.x - float(saw_node.state.get("x", 0.0))) < 0.01, "MP presentation follows shared world coordinates")
	presentation.reset()
	_check(presentation.event_nodes.is_empty(), "MP reset clears saw event nodes for a new round")
	if failures == 0:
		print("SAW_MP_PRESENTATION_PASS scene/resolved event/world tick/ceiling-gap landing/reset")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
