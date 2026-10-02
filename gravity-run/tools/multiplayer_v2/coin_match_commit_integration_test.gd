extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldScript := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const MatchScript := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")
const LocalRunner := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const CoinPresentationRouter := preload("res://systems/confirmed_coin_presentation.gd")

var collected_signals := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var built: Dictionary = Builder.new().build(42, 10000, 8)
	if built.get("manifest") == null:
		_finish(["manifest build failed: %s" % built.get("error", "unknown")])
		return
	var manifest: Resource = built.manifest
	var used_coin_ids: Dictionary = {}
	var first_fixture := _isolated_coin_contact(manifest, null, used_coin_ids)
	var coin: Dictionary = first_fixture.get("coin", {})
	if coin.is_empty():
		_finish(["could not find an isolated real coin-contact fixture"])
		return
	used_coin_ids[str(coin.entity_id)] = true
	var world = WorldScript.new()
	if not str(world.configure(manifest)).is_empty():
		_finish(["world configuration failed"])
		return
	MultiplayerV2Service.call("configure_world_simulation", world)
	var old_process := MultiplayerV2Service.is_processing()
	MultiplayerV2Service.set_process(false)
	MultiplayerV2Service.set("identity_user_id", "coin-presentation-host")
	MultiplayerV2Service.set("session", {"round_id": "coin-presentation-test", "local_peer_id": 1, "role": "host"})
	MultiplayerV2Service.set("_round_id", "coin-presentation-test")
	MultiplayerV2Service.set("_active", true)
	MultiplayerV2Service.set("room_state", {"owner_user_id": "coin-presentation-host", "phase": "RUNNING", "members": [{"user_id": "coin-presentation-host", "player_slot": 1}]})
	MultiplayerV2Service.set("current_manifest", manifest)
	MultiplayerV2Service.set("_pending_interactions", [])
	MultiplayerV2Service.set("_interaction_results", {})
	MultiplayerV2Service.set("_last_input_sequence_by_peer", {1: 0})
	MultiplayerV2Service.set("terminal_status", {})
	var presentation = PresentationScript.new()
	presentation.load_manifest(manifest)
	add_child(presentation)
	var coin_node: Node2D = presentation.event_nodes[str(coin.entity_id)]
	var match_scene = MatchScript.new()
	match_scene.set("_round_id", "coin-presentation-test")
	match_scene.set("_world", world)
	match_scene.set("_course_presentation", presentation)
	var runner := LocalRunner.new()
	runner.configure("coin-presentation-test", 1, float(manifest.start_x), float(manifest.initial_floor_y))
	runner.simulation_tick = 11
	match_scene.set("_runner", runner)
	match_scene.set("_pending_coin_claims", {})
	coin_node.connect("collected", func(_value: int) -> void: collected_signals += 1)
	var match_commit_callback := Callable(match_scene, "_on_world_commit")
	var match_result_callback := Callable(match_scene, "_on_interaction_resolved")
	MultiplayerV2Service.world_event_committed.connect(match_commit_callback)
	MultiplayerV2Service.world_interaction_resolved.connect(match_result_callback)
	var start: Dictionary = first_fixture.start
	var finish: Dictionary = first_fixture.finish
	world.tick = 11
	MultiplayerV2Service.set("_validated_motion_history", {1: [
		{"round_id": "coin-presentation-test", "owner_peer_id": 1, "simulation_tick": 10, "history_tick": 10.0, "world_x": float(start.world_x), "y": float(start.y)},
		{"round_id": "coin-presentation-test", "owner_peer_id": 1, "simulation_tick": 11, "history_tick": 11.0, "world_x": float(finish.world_x), "y": float(finish.y)}
	]})
	var real_contacts: Array[Dictionary] = world.coin_contacts_swept(start, finish)
	var found_contact := false
	for contact in real_contacts:
		if str(contact.get("entity_id", "")) == str(coin.entity_id):
			found_contact = true
	if not found_contact:
		failures.append("fixture path did not create a real swept contact")
	match_scene.call("_submit_coin_claims", start, finish, 2.0)
	var pending_claims: Dictionary = match_scene.get("_pending_coin_claims")
	var pending: Dictionary = pending_claims.get(str(coin.entity_id), {})
	if pending.is_empty() or not bool(pending.get("predicted", false)):
		failures.append("local swept contact did not immediately start request-scoped visual prediction")
	if not bool(coin_node.get("is_being_collected")):
		failures.append("coin did not burst on the local contact frame")
	if not world.entity_ledger.is_active(str(coin.entity_id), 1):
		failures.append("visual prediction changed the authoritative ledger before host confirmation")
	await get_tree().create_timer(0.42).timeout # 120 ms arbitration plus 300 ms simulated network latency.
	if not is_instance_valid(coin_node):
		failures.append("unconfirmed visual prediction freed the coin before its decision")
	if coin_node.visible:
		failures.append("completed pending prediction should hold the coin hidden awaiting host decision")
	MultiplayerV2Service.call("_drain_interaction_claims")
	await get_tree().process_frame
	if is_instance_valid(coin_node):
		failures.append("confirmed completed predicted burst did not release its visual node")
	var state: Dictionary = world.entity_ledger.entities[str(coin.entity_id)]
	if int(state.get("award_value", 0)) != 1 or int(state.get("winner_peer_id", 0)) != 1:
		failures.append("animation route changed authoritative winner/reward")
	var duplicate_burst: bool = bool(CoinPresentationRouter.new().present({"action": "collect", "entity_id": str(coin.entity_id), "commit_id": "late-duplicate"}, "duplicate", presentation))
	if duplicate_burst:
		failures.append("duplicate/out-of-order confirmation started another coin effect")
	match_scene.call("_on_interaction_resolved", str(pending.get("request_id", "")), false, "late_rejection", {})
	if world.entity_ledger.is_active(str(coin.entity_id), 1):
		failures.append("late rejection resurrected the confirmed collected coin")
	if collected_signals != 0:
		failures.append("visual prediction emitted the single-player reward signal")
	# A denied claim for an authoritative active coin restores the same node and canonical position.
	MultiplayerV2Service.set_process(false)
	var denied_fixture := _isolated_coin_contact(manifest, world, used_coin_ids)
	var denied_coin: Dictionary = denied_fixture.get("coin", {})
	if denied_coin.is_empty():
		_finish(["could not find isolated denied-coin fixture"])
		return
	used_coin_ids[str(denied_coin.entity_id)] = true
	var denied_node: Node2D = presentation.event_nodes[str(denied_coin.entity_id)]
	denied_node.connect("collected", func(_value: int) -> void: collected_signals += 1)
	var denied_start: Dictionary = denied_fixture.start
	var denied_finish: Dictionary = denied_fixture.finish
	match_scene.call("_submit_coin_claims", denied_start, denied_finish, 2.0)
	var denied_pending: Dictionary = (match_scene.get("_pending_coin_claims") as Dictionary).get(str(denied_coin.entity_id), {})
	await get_tree().create_timer(0.42).timeout
	match_scene.call("_on_interaction_resolved", str(denied_pending.get("request_id", "")), false, "unverified_contact", {})
	if not denied_node.visible or bool(denied_node.get("is_being_collected")) or not world.entity_ledger.is_active(str(denied_coin.entity_id), 1):
		failures.append("denied active coin did not restore after the pending burst")
	var active_baseline: Dictionary = {"entities": {str(denied_coin.entity_id): world.entity_ledger.entities[str(denied_coin.entity_id)]}}
	presentation.call("set_world_state", active_baseline)
	if not denied_node.visible or bool(denied_node.get("is_being_collected")):
		failures.append("active baseline resync changed the restored coin into a false pickup")
	# A lost tie carries the canonical other-player commit; keep the predicted coin gone without replaying it.
	var lost_fixture := _isolated_coin_contact(manifest, world, used_coin_ids)
	var lost_coin: Dictionary = lost_fixture.get("coin", {})
	if lost_coin.is_empty():
		_finish(["could not find isolated lost-claim fixture"])
		return
	used_coin_ids[str(lost_coin.entity_id)] = true
	var lost_node: Node2D = presentation.event_nodes[str(lost_coin.entity_id)]
	lost_node.connect("collected", func(_value: int) -> void: collected_signals += 1)
	var lost_start: Dictionary = lost_fixture.start
	var lost_finish: Dictionary = lost_fixture.finish
	match_scene.call("_submit_coin_claims", lost_start, lost_finish, 2.0)
	var lost_pending: Dictionary = (match_scene.get("_pending_coin_claims") as Dictionary).get(str(lost_coin.entity_id), {})
	var lost_commit := {"world_revision": 2, "commit_id": "integration-coin-lost", "entity_id": str(lost_coin.entity_id), "incarnation": 1, "action": "collect", "effective_tick": 12, "state_before": "active", "state_after": "collected", "winner_peer_id": 1, "award_value": 1, "request_id": "other-player-request", "round_id": "coin-presentation-test"}
	var lost_progress_before := float(lost_node.get("burst_elapsed"))
	var lost_sparks_before := (lost_node.get("sparks") as Array).size()
	match_scene.call("_on_interaction_resolved", str(lost_pending.get("request_id", "")), false, "coin_claim_lost", lost_commit)
	if world.entity_ledger.is_active(str(lost_coin.entity_id), 1):
		failures.append("losing prediction restored a coin already collected by another player")
	if not bool(lost_node.get("is_being_collected")) or float(lost_node.get("burst_elapsed")) < lost_progress_before or (lost_node.get("sparks") as Array).size() != lost_sparks_before:
		failures.append("lost-claim confirmation did not preserve the original single burst")
	if collected_signals != 0:
		failures.append("denied/lost predictions incremented real coin rewards")
	var already_gone_fixture := _isolated_coin_contact(manifest, world, used_coin_ids)
	var already_gone_coin: Dictionary = already_gone_fixture.get("coin", {})
	if not already_gone_coin.is_empty():
		used_coin_ids[str(already_gone_coin.entity_id)] = true
		var already_gone_node: Node2D = presentation.event_nodes[str(already_gone_coin.entity_id)]
		var already_gone_start: Dictionary = already_gone_fixture.start
		var already_gone_finish: Dictionary = already_gone_fixture.finish
		match_scene.call("_submit_coin_claims", already_gone_start, already_gone_finish, 2.0)
		var already_gone_pending: Dictionary = (match_scene.get("_pending_coin_claims") as Dictionary).get(str(already_gone_coin.entity_id), {})
		await get_tree().create_timer(0.42).timeout
		match_scene.call("_on_interaction_resolved", str(already_gone_pending.get("request_id", "")), false, "already_collected", {})
		await get_tree().process_frame
		if is_instance_valid(already_gone_node) or not world.entity_ledger.is_active(str(already_gone_coin.entity_id), 1):
			failures.append("already-collected rejection restored stale local coin or changed its authoritative ledger")
	presentation.call("reset")
	presentation.call("load_manifest", manifest)
	var reset_coin: Node2D = presentation.event_nodes[str(coin.entity_id)]
	if not is_instance_valid(reset_coin) or not reset_coin.visible or bool(reset_coin.get("is_being_collected")):
		failures.append("new round/reset retained an old coin burst state")
	if not (presentation.get("_confirmed_coin_bursts") as Dictionary).is_empty() or not (presentation.get("_coin_visual_predictions") as Dictionary).is_empty():
		failures.append("new round/reset retained coin presentation dedupe state")
	MultiplayerV2Service.world_event_committed.disconnect(match_commit_callback)
	MultiplayerV2Service.world_interaction_resolved.disconnect(match_result_callback)
	match_scene.free()
	presentation.queue_free()
	MultiplayerV2Service.configure_world_simulation(null)
	MultiplayerV2Service.set("current_manifest", null)
	MultiplayerV2Service.set("room_state", {})
	MultiplayerV2Service.set("session", {})
	MultiplayerV2Service.set("_round_id", "")
	MultiplayerV2Service.set("_active", false)
	MultiplayerV2Service.set("_pending_interactions", [])
	MultiplayerV2Service.set("_coin_award_queue", [])
	await get_tree().process_frame
	MultiplayerV2Service.set_process(old_process)
	_finish(failures)

func _isolated_coin_contact(manifest: Resource, world: Variant, excluded: Dictionary) -> Dictionary:
	for candidate in manifest.collectibles:
		var entity_id := str(candidate.get("entity_id", ""))
		if excluded.has(entity_id):
			continue
		var start := {"world_x": float(candidate.get("world_x", 0.0)) - 4.0, "y": float(candidate.get("world_y", 0.0))}
		var finish := {"world_x": float(candidate.get("world_x", 0.0)) + 4.0, "y": float(candidate.get("world_y", 0.0))}
		var probe_world: Variant = world
		if probe_world == null:
			probe_world = WorldScript.new()
			probe_world.configure(manifest)
		var contacts: Array[Dictionary] = probe_world.coin_contacts_swept(start, finish)
		if contacts.size() == 1 and str(contacts[0].get("entity_id", "")) == entity_id:
			return {"coin": candidate, "start": start, "finish": finish}
	return {}

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("coin_match_commit_integration_test: PASS (swept local prediction, delayed real service commit, denial restore, lost winner, no reward signal)")
		get_tree().quit(0)
		return
	for failure in failures: push_error(failure)
	get_tree().quit(1)
