extends Node

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const DestructibleRules := preload("res://systems/multiplayer_v2/v2_destructible_rules.gd")
const Presentation := preload("res://systems/race_course_presentation.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var selected: Resource
	var selected_barrel: Dictionary = {}
	var selected_block: Dictionary = {}
	for seed_value in range(100000001, 100000241):
		var result: Dictionary = Builder.new().build(seed_value, 100000, Generator.GENERATOR_VERSION_13)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			continue
		_validate_spiked_support_corridors(manifest)
		for event_index in range(manifest.events.size()):
			var event: Dictionary = manifest.events[event_index]
			if str(event.get("kind", "")) != "barrels" or not bool(event.get("spiked", false)) or float(event.get("motion_speed_multiplier", 1.0)) <= 1.05:
				continue
			if event_index == 0:
				continue
			var target: Dictionary = manifest.events[event_index - 1]
			if str(target.get("kind", "")) != "block" or bool(target.get("from_ceiling", false)):
				continue
			var delta := float(event.x) - float(target.x)
			if delta >= 70.0 and delta <= 240.0:
				selected = manifest
				selected_barrel = event
				selected_block = target
			if selected != null:
				break
		if selected != null:
			break
	_check(selected != null, "bounded seed search finds a generated floor spiked barrel paired with a breakable block")
	if selected != null:
		_check(str(selected.call("validate")).is_empty(), "spiked barrel manifest passes the canonical manifest validator")
		var simulation := WorldSimulation.new()
		_check(str(simulation.configure(selected)).is_empty(), "shared multiplayer world accepts the generated spiked-barrel manifest")
		var presentation := Presentation.new()
		get_tree().root.add_child(presentation)
		_check(str(presentation.load_manifest(selected)).is_empty(), "the same manifest loads into the shared MP presentation scene")
		var barrel_node: Variant = presentation.event_nodes.get("%s_0" % str(selected_barrel.event_id))
		_check(is_instance_valid(barrel_node) and bool(barrel_node.get("is_spiked")), "shared presentation renders the same barrel scene with the spiked variant")
		var found_block_destroyed := false
		var barrel_alive_after_block := false
		var active_barrel: Dictionary = {}
		var recovered_after_block := WorldSimulation.new()
		var baseline_restored := false
		var speed_multiplier := float(selected_barrel.get("motion_speed_multiplier", 1.0))
		var spawn_distance := float(selected_barrel.x) - float(selected_barrel.get("spawn_lead_distance", 820.0)) * (speed_multiplier - 1.0) - float(selected.start_x)
		var last_tick := mini(30000, ceili(spawn_distance / 500.0 * 60.0) + 300)
		for next_tick in range(1, last_tick + 1):
			simulation.step_to(next_tick)
			presentation.set_world_state(simulation.state_snapshot())
			var block_state: Dictionary = simulation.entity_ledger.entities.get(str(selected_block.event_id), {})
			if str(block_state.get("state", "active")) == "destroyed":
				found_block_destroyed = true
				for barrel in simulation.barrels:
					if str(barrel.get("event_id", "")) == str(selected_barrel.event_id) and not bool(barrel.get("destroyed", true)):
						barrel_alive_after_block = true
				break
			if found_block_destroyed:
				break
		_check(found_block_destroyed, "spiked barrel deterministically destroys its paired block through the world ledger")
		_check(barrel_alive_after_block, "spiked barrel remains active and rolling after block destruction")
		_check(is_instance_valid(barrel_node) and bool(barrel_node.get("is_spiked")) and not bool(barrel_node.call("is_destroying_now")), "MP presentation keeps the barrel visible and spiked after its block commit")
		if barrel_alive_after_block:
			for barrel in simulation.barrels:
				if str(barrel.get("event_id", "")) == str(selected_barrel.event_id) and not bool(barrel.get("destroyed", true)):
					active_barrel = barrel
					break
			var post_block_baseline: Dictionary = simulation.entity_ledger.baseline()
			baseline_restored = str(recovered_after_block.configure(selected)).is_empty() and recovered_after_block.apply_baseline(post_block_baseline)
			_check(baseline_restored, "baseline immediately after block impact restores successfully")
		if barrel_alive_after_block:
			var recovered_block_state: Dictionary = {}
			if baseline_restored:
				recovered_block_state = recovered_after_block.entity_ledger.entities.get(str(selected_block.event_id), {})
			var recovered_barrel_alive := false
			if baseline_restored:
				for barrel in recovered_after_block.barrels:
					if str(barrel.get("event_id", "")) == str(selected_barrel.event_id) and not bool(barrel.get("destroyed", true)):
						recovered_barrel_alive = true
			_check(str(recovered_block_state.get("state", "active")) == "destroyed" and recovered_barrel_alive, "post-impact baseline keeps block destroyed and spiked barrel active before lethal contact")
			var x_after_block := float(active_barrel.get("x", 0.0))
			var continue_until := simulation.tick + 6
			for next_tick in range(simulation.tick + 1, continue_until + 1):
				simulation.step_to(next_tick)
				presentation.set_world_state(simulation.state_snapshot())
			for barrel in simulation.barrels:
				if str(barrel.get("event_id", "")) == str(selected_barrel.event_id) and not bool(barrel.get("destroyed", true)):
					active_barrel = barrel
					break
			_check(not active_barrel.is_empty() and float(active_barrel.get("x", x_after_block)) < x_after_block, "spiked barrel continues moving across world x for six shared simulation ticks after breaking the block")
		if barrel_alive_after_block:
			var radius := 36.0
			var player_state := {"world_x": float(active_barrel.x), "y": float(active_barrel.y) - radius, "gravity_direction": 1, "grounded": true}
			var contact := simulation.player_contact_at(player_state, simulation.tick)
			_check(str(contact.get("kind", "")) == "shared_interaction" and str(contact.get("reason", "")) == "barrel_contact", "spiked barrel remains lethal under the shared barrel contact rule")
			var lethal_policy := DestructibleRules.policy_for("spiked_barrel")
			_check(int(lethal_policy.get("player_contact", -1)) == DestructibleRules.ContactResult.CONSUME_AND_LETHAL and str(lethal_policy.get("destruction_policy", "")) == "consume_on_lethal_contact", "spiked-barrel lethal/consume behavior is explicit in the multiplayer destructible policy")
			var barrel_entity_id := str(active_barrel.get("entity_id", ""))
			var lethal_request := DestructibleRules.make_request("review-round", barrel_entity_id, int(active_barrel.get("incarnation", 1)), "lethal_contact", simulation.tick, 9, simulation.entity_ledger.revision, "spiked-lethal-1")
			var lethal_result := DestructibleRules.host_commit(simulation.entity_ledger, lethal_request, {"state": "dead", "reason": "barrel_contact"})
			_check(bool(lethal_result.get("accepted", false)) and str(lethal_result.get("commit", {}).get("state_after", "")) == "destroyed", "validated spiked-barrel contact produces one host-authoritative lethal commit")
			var revision_after_lethal := simulation.entity_ledger.revision
			var duplicate_lethal := DestructibleRules.host_commit(simulation.entity_ledger, lethal_request)
			_check(not bool(duplicate_lethal.get("accepted", true)) and str(duplicate_lethal.get("reason", "")) == "already_consumed" and simulation.entity_ledger.revision == revision_after_lethal, "replayed lethal contact cannot consume or commit the spiked barrel twice")
			var lethal_commit: Dictionary = lethal_result.get("commit", {})
			if not lethal_commit.is_empty():
				_check(simulation.apply_world_commit(lethal_commit) == "duplicate", "service-style second commit application is idempotent after the host ledger decision")
			var saved_baseline: Dictionary = simulation.entity_ledger.baseline()
			var recovered := WorldSimulation.new()
			_check(str(recovered.configure(selected)).is_empty() and recovered.apply_baseline(saved_baseline), "world baseline restores the consumed spiked barrel and previously destroyed breakable block")
			if is_instance_valid(barrel_node):
				presentation.set_world_state(recovered.state_snapshot())
				_check(not bool(barrel_node.visible) or bool(barrel_node.call("is_destroying_now")), "recovered canonical baseline renders the consumed spiked barrel as gone")
	for old_version in [Generator.GENERATOR_VERSION_12, Generator.GENERATOR_VERSION_11]:
		var old_manifest: Variant = Builder.new().build(100000003, 100000, old_version).get("manifest")
		var has_old_spike := false
		if old_manifest != null:
			for event in old_manifest.events:
				has_old_spike = has_old_spike or (str(event.get("kind", "")) == "barrels" and bool(event.get("spiked", false)))
		_check(old_manifest != null and has_old_spike == (old_version == Generator.GENERATOR_VERSION_12), "frozen Gen12/11 variant catalogs are unchanged")
	var short_manifest: Variant = Builder.new().build(100000003, 45000, Generator.GENERATOR_VERSION_13).get("manifest")
	var long_manifest: Variant = Builder.new().build(100000003, 100000, Generator.GENERATOR_VERSION_13).get("manifest")
	_check(short_manifest != null and long_manifest != null and _course_prefix_signature(short_manifest, 45000.0) == _course_prefix_signature(long_manifest, 45000.0), "Gen13 supported-barrel and gap placement is deterministic across finite-course prefix lengths")
	print("SPIKED_BARREL_SHARED_SIMULATION_TEST failures=%d seed=%s barrel=%s block=%s" % [failures.size(), str(selected.seed_value) if selected != null else "none", str(selected_barrel.get("event_id", "")), str(selected_block.get("event_id", ""))])
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)

func _validate_spiked_support_corridors(manifest: Resource) -> void:
	var surface_index := SurfaceIndex.new()
	surface_index.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
	for index in range(manifest.events.size()):
		var barrel: Dictionary = manifest.events[index]
		if str(barrel.get("kind", "")) != "barrels" or not bool(barrel.get("spiked", false)):
			continue
		if index == 0 or str(manifest.events[index - 1].get("kind", "")) != "block" or bool(manifest.events[index - 1].get("from_ceiling", false)):
			_check(false, "Gen13 spiked barrel %s retains its paired floor block" % str(barrel.get("event_id", "")))
			continue
		var block: Dictionary = manifest.events[index - 1]
		var multiplier := maxf(float(barrel.get("motion_speed_multiplier", 1.0)), 1.0)
		var count := maxi(int(barrel.get("count", 1)), 1)
		var spacing := float(barrel.get("spacing", HazardRules.BARREL_CHAIN_SPACING))
		var radius := HazardRules.barrel_radius(float(barrel.get("width", HazardRules.BARREL_WIDTH)), float(barrel.get("height", HazardRules.BARREL_WIDTH)))
		# These match V2WorldSimulation's first chain barrel and its circle contact with the block.
		var spawn_x := float(barrel.x) + float(barrel.get("spawn_lead_distance", 820.0)) * (multiplier - 1.0) - float(count - 1) * spacing * 0.5
		var impact_x := float(block.x) + float(block.get("width", 44.0)) * 0.5 + radius
		var supported := spawn_x > impact_x
		var sample_x := impact_x
		while supported and sample_x <= spawn_x:
			if not bool(surface_index.surface_at(sample_x, false).get("supported", false)):
				supported = false
				break
			sample_x += 8.0
		_check(supported, "Gen13 spiked barrel %s stays supported from actual first-chain spawn through block-circle impact" % str(barrel.get("event_id", "")))

func _course_prefix_signature(manifest: Resource, end_x: float) -> String:
	var signature: Array = []
	for event in manifest.events:
		if float(event.get("x", 0.0)) > float(manifest.start_x) + end_x:
			break
		if str(event.get("kind", "")) in ["barrels", "gap", "block"]:
			signature.append([str(event.get("event_id", "")), str(event.get("kind", "")), float(event.get("x", 0.0)), float(event.get("width", 0.0)), bool(event.get("spiked", false)), float(event.get("motion_speed_multiplier", 1.0))])
	return JSON.stringify(signature)
