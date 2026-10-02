extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Resource = Builder.new().build(43, 45000, 8).manifest
	_check(manifest != null, "build current shared course manifest")
	if manifest == null or manifest.collectibles.is_empty():
		_finish()
		return
	var entity_id := str(manifest.collectibles[0].get("entity_id", ""))
	var host: RefCounted = World.new()
	var guest: RefCounted = World.new()
	_check(str(host.configure(manifest)).is_empty() and str(guest.configure(manifest)).is_empty(), "configure host and guest ledgers")
	var host_view: Node2D = _make_presentation(manifest, "HostCoinPresentation")
	var guest_view: Node2D = _make_presentation(manifest, "GuestCoinPresentation")
	var host_coin: Node = host_view.get("event_nodes").get(entity_id)
	var guest_coin: Node = guest_view.get("event_nodes").get(entity_id)
	var gameplay_signals := [0]
	host_coin.collected.connect(func(_value: int) -> void: gameplay_signals[0] += 1)
	guest_coin.collected.connect(func(_value: int) -> void: gameplay_signals[0] += 1)
	var commit := {"world_revision": 1, "commit_id": "coin-burst-test", "entity_id": entity_id, "incarnation": 1, "action": "collect", "state_before": "active", "state_after": "collected", "winner_peer_id": 2, "award_value": 1, "effective_tick": 10}
	var host_result := str(host.apply_world_commit(commit))
	var guest_result := str(guest.apply_world_commit(commit))
	_check(host_result == "applied" and guest_result == "applied", "same confirmed coin commit applies on host and guest")
	_check(int(host.entity_ledger.entities[entity_id].get("winner_peer_id", 0)) == 2 and int(guest.entity_ledger.entities[entity_id].get("award_value", 0)) == 1, "visual integration preserves authoritative winner and one-coin ledger award")
	_check(bool(host_view.call("play_confirmed_coin_collection", entity_id, "coin-burst-test")), "host starts shared coin burst")
	_check(bool(guest_view.call("play_confirmed_coin_collection", entity_id, "coin-burst-test")), "guest starts shared coin burst")
	_check(bool(host_coin.get("is_being_collected")) and bool(guest_coin.get("is_being_collected")), "both actual shared coin nodes run the SP collection animation")
	_check(host_coin.get("sparks").size() == 8 and guest_coin.get("sparks").size() == 8, "both peers get the same eight short-lived visual sparks")
	_check(gameplay_signals[0] == 0, "visual-only animation does not emit or duplicate the coin reward")
	_check(str(host.apply_world_commit(commit)) == "duplicate" and str(guest.apply_world_commit(commit)) == "duplicate", "replayed network commit is classified as duplicate")
	_check(not bool(host_view.call("play_confirmed_coin_collection", entity_id, "coin-burst-test")) and not bool(guest_view.call("play_confirmed_coin_collection", entity_id, "coin-burst-test")), "duplicate commit does not replay the burst")
	_check(host_coin.get("sparks").size() == 8 and guest_coin.get("sparks").size() == 8, "duplicate leaves each burst unchanged")
	host_view.call("set_world_state", host.state_snapshot())
	guest_view.call("set_world_state", guest.state_snapshot())
	_check(bool(host_coin.visible) and bool(guest_coin.visible), "nonactive per-frame world state does not hide an in-progress burst")
	var reconnect: RefCounted = World.new()
	reconnect.configure(manifest)
	_check(bool(reconnect.apply_baseline(host.entity_ledger.baseline())), "reconnect restores the collected coin ledger snapshot")
	var reconnect_view := _make_presentation(manifest, "ReconnectCoinPresentation")
	var reconnect_coin: Node = reconnect_view.get("event_nodes").get(entity_id)
	reconnect_view.call("set_world_state", reconnect.state_snapshot())
	_check(not reconnect_coin.visible and not bool(reconnect_coin.get("is_being_collected")) and reconnect_coin.get("sparks").is_empty(), "baseline/reconnect hides an old pickup without replaying a burst")
	_check(gameplay_signals[0] == 0, "visual and reconnect paths do not fire gameplay coin signals")
	_finish()

func _make_presentation(manifest: Resource, node_name: String) -> Node2D:
	var view := Presentation.new() as Node2D
	view.name = node_name
	root.add_child(view)
	_check(str(view.call("load_manifest", manifest)).is_empty(), "%s loads manifest" % node_name)
	return view

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)

func _finish() -> void:
	print("coin_burst_presentation_test failures=%d" % failures)
	quit(0 if failures == 0 else 1)
