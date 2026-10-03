extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const GhostModel := preload("res://systems/ghost_hazard_model.gd")

var failures: Array[String] = []
var _warning_sounds := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Resource
	var ghost_event: Dictionary = {}
	for seed in [1, 42, 918273645, 100000014]:
		var built: Dictionary = Builder.new().build(seed, 45000, Generator.GENERATOR_VERSION)
		manifest = built.get("manifest")
		if manifest == null:
			continue
		for event in manifest.events:
			if str(event.get("kind", "")) == "ghost":
				ghost_event = event
				break
		if not ghost_event.is_empty():
			break
	_check(manifest != null and not ghost_event.is_empty(), "known gen11 fixtures include a deterministic ghost event")
	if ghost_event.is_empty():
		_finish()
		return
	PlayerProfile.set("sfx_enabled", true)
	PlayerProfile.set("sfx_volume", 0.7)
	SfxController.begin_round("ghost-presentation-round")
	SfxController.event_started.connect(_on_sfx_started)
	var presentation := Presentation.new()
	var singleplayer_ghost: Node2D
	add_child(presentation)
	presentation.set_audio_round_id("ghost-presentation-round")
	presentation.set_camera_left(float(ghost_event.get("x", 0.0)) - 120.0)
	var manifest_error := str(presentation.load_manifest(manifest))
	_check(manifest_error.is_empty(), "shared MP presentation loads gen11 ghost manifest")
	var node: Node = presentation.event_nodes.get(str(ghost_event.event_id))
	_check(is_instance_valid(node) and node.has_method("apply_world_state"), "MP maps ghost event to the reusable hazard scene")
	if is_instance_valid(node):
		var warning_state := GhostModel.state(ghost_event, 20, 20)
		presentation.set_world_state({"ghosts": [warning_state]})
		_check(str(node.get("phase")) == GhostModel.WARNING and node.visible, "shared scene presents the tick-authoritative warning phase")
		_check(bool(presentation.get("_ghost_warning_pulse").call("is_active")), "MP presentation raises the shared centered warning pulse when authoritative warning begins")
		_check(node.call("get_hitbox_rect").size == Vector2.ZERO, "warning presentation remains nonlethal")
		var mp_danger_state := GhostModel.state(ghost_event, 20, 140)
		presentation.set_world_state({"ghosts": [mp_danger_state]})
		_check(str(node.get("phase")) == GhostModel.DANGEROUS and node.call("get_hitbox_rect").size == Vector2(float(ghost_event.width), float(ghost_event.height)), "shared scene collision follows the authoritative danger tick")
		presentation.set_world_state({"ghosts": [GhostModel.state(ghost_event, 20, 20)]})
		_check(_warning_sounds == 1 and str(node.get("phase")) == GhostModel.DANGEROUS and node.call("get_hitbox_rect").size != Vector2.ZERO, "stale warning snapshot cannot rewind dangerous state or replay round-scoped SFX")
		presentation.set_world_state({"ghosts": [mp_danger_state]})
		var mp_danger_rect: Rect2 = node.call("get_hitbox_rect")
		singleplayer_ghost = GhostScene.instantiate()
		add_child(singleplayer_ghost)
		singleplayer_ghost.call("configure", ghost_event)
		singleplayer_ghost.call("set_activation_tick", 20)
		singleplayer_ghost.call("set_simulation_tick", 140)
		_check(str(singleplayer_ghost.get("phase")) == GhostModel.DANGEROUS and singleplayer_ghost.call("get_hitbox_rect") == mp_danger_rect, "SP/MP scene collision is identical at the same event tick")
		presentation.set_world_state({"ghosts": [GhostModel.state(ghost_event, 20, 685)]})
		_check(not node.visible and node.call("get_hitbox_rect").size == Vector2.ZERO, "expired ghost disappears and stays harmless")
		presentation.set_world_state({"ghosts": [mp_danger_state]})
		presentation.set_world_state({"ghosts": [GhostModel.state(ghost_event, 20, 20)]})
		_check(not node.visible and node.call("get_hitbox_rect").size == Vector2.ZERO, "stale danger and warning snapshots never revive an expired ghost")
	presentation.queue_free()
	singleplayer_ghost.queue_free()
	_finish()

func _on_sfx_started(event_name: String, _event_key: String) -> void:
	if event_name == "ghost_warning":
		_warning_sounds += 1

func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("GHOST_PRESENTATION_SHARED_TEST failures=%d warning_sounds=%d" % [failures.size(), _warning_sounds])
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
