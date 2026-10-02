extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldScript := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const MatchScript := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var built: Dictionary = Builder.new().build(42, 10000, 8)
	if built.get("manifest") == null:
		_finish(["manifest build failed: %s" % built.get("error", "unknown")])
		return
	var manifest: Resource = built.manifest
	var coin: Dictionary = manifest.collectibles[0]
	var world = WorldScript.new()
	if not str(world.configure(manifest)).is_empty():
		_finish(["world configuration failed"])
		return
	MultiplayerV2Service.call("configure_world_simulation", world)
	MultiplayerV2Service.set("session", {"round_id": "coin-presentation-test", "local_peer_id": 2})
	MultiplayerV2Service.set("_round_id", "coin-presentation-test")
	var presentation = PresentationScript.new()
	presentation.load_manifest(manifest)
	add_child(presentation)
	var coin_node: Node2D = presentation.event_nodes[str(coin.entity_id)]
	var match_scene = MatchScript.new()
	match_scene.set("_round_id", "coin-presentation-test")
	match_scene.set("_world", world)
	match_scene.set("_course_presentation", presentation)
	var match_commit_callback := Callable(match_scene, "_on_world_commit")
	MultiplayerV2Service.world_event_committed.connect(match_commit_callback)
	var commit := {"world_revision": 1, "commit_id": "integration-coin-1", "entity_id": str(coin.entity_id), "incarnation": 1, "action": "collect", "effective_tick": 10, "state_before": "active", "state_after": "collected", "winner_peer_id": 1, "award_value": 1, "request_id": "integration-request", "round_id": "coin-presentation-test"}
	MultiplayerV2Service.call("_handle_guest_control", "WORLD_COMMIT", commit)
	if not bool(coin_node.get("is_being_collected")):
		failures.append("actual guest service->commit signal->match path did not animate shared-ledger duplicate")
	var progress_before := float(coin_node.get("burst_elapsed"))
	await get_tree().process_frame
	MultiplayerV2Service.call("_handle_guest_control", "WORLD_COMMIT", commit)
	if not bool(coin_node.get("is_being_collected")):
		failures.append("duplicate service delivery stopped active burst")
	if float(coin_node.get("burst_elapsed")) < progress_before:
		failures.append("duplicate service delivery restarted burst")
	var state: Dictionary = world.entity_ledger.entities[str(coin.entity_id)]
	if int(state.get("award_value", 0)) != 1 or int(state.get("winner_peer_id", 0)) != 1:
		failures.append("animation route changed authoritative winner/reward")
	MultiplayerV2Service.world_event_committed.disconnect(match_commit_callback)
	match_scene.free()
	presentation.queue_free()
	_finish(failures)

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("coin_match_commit_integration_test: PASS (actual service guest handler -> signal -> match -> shared coin node)")
		get_tree().quit(0)
		return
	for failure in failures: push_error(failure)
	get_tree().quit(1)
