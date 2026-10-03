extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const SawModel := preload("res://systems/saw_blade_model.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(1, 45000, 9)
	var manifest: Resource = built.get("manifest")
	_check(manifest != null, "v9 route manifest builds: %s" % str(built.get("error", "")))
	if manifest == null:
		quit(1)
		return
	var world := WorldSimulation.new() as MultiplayerV2WorldSimulation
	_check(str(world.configure(manifest)).is_empty(), "shared world simulation configures manifest")
	var saw_models: Dictionary = {}
	var target_tick := 0
	var ceiling_saw_id := ""
	var floor_saw_id := ""
	for saw in world.saws:
		var event: Dictionary = saw.event
		var event_id := str(saw.event_id)
		var initial := SawModel.initial_state(event, float(manifest.get("start_x")), 0, 12)
		saw_models[event_id] = {"event": event, "state": initial, "saw_fall": false}
		target_tick = maxi(target_tick, 160)
		var activation_commit := {"world_revision": world.entity_ledger.revision + 1, "commit_id": "shared-saw-%s" % event_id, "entity_id": event_id, "incarnation": 1, "action": "activate_saw", "effective_tick": 12, "saw_activation_tick": 12, "state_before": "active", "state_after": "active"}
		_check(world.apply_world_commit(activation_commit) == "applied", "host commit drives shared saw activation")
		if bool(event.get("from_ceiling", false)) and ceiling_saw_id.is_empty(): ceiling_saw_id = event_id
		if not bool(event.get("from_ceiling", false)) and floor_saw_id.is_empty(): floor_saw_id = event_id
	_check(not ceiling_saw_id.is_empty(), "representative seed has a ceiling-origin saw")
	_check(not floor_saw_id.is_empty(), "representative seed has a floor-origin saw")
	for tick in range(1, target_tick + 1):
		_check(world.step_to(tick), "world advances one deterministic tick")
		for saw_value in world.saws:
			var event_id := str(saw_value.event_id)
			var direct: Dictionary = saw_models[event_id]
			direct.state = SawModel.advance(direct.event, direct.state, tick, Callable(world, "surface_at"))
			var replicated: Dictionary = saw_value.state
			_check(direct.state == replicated, "MP world and shared SawBladeModel agree at tick %d" % tick)
			if bool(direct.state.get("falling", false)):
				direct.saw_fall = true
				saw_models[event_id] = direct
	var ceiling_state: Dictionary = saw_models.get(ceiling_saw_id, {}).get("state", {})
	var ceiling_record: Dictionary = saw_models.get(ceiling_saw_id, {})
	_check(bool(ceiling_record.get("saw_fall", false)), "ceiling blade loses support and falls through its authored gap")
	_check(not bool(ceiling_state.get("falling", true)) and not bool(ceiling_state.get("removed", true)) and not bool(ceiling_state.get("ceiling_lane", true)), "ceiling blade lands on the floor and keeps moving")
	var floor_state: Dictionary = saw_models.get(floor_saw_id, {}).get("state", {})
	_check(bool(floor_state.get("active", false)) and not bool(floor_state.get("falling", true)) and not bool(floor_state.get("ceiling_lane", true)), "floor blade rolls along floor support")
	if failures == 0:
		print("SAW_SHARED_TICK_PASS tick=%d ceiling=%s floor=%s" % [target_tick, ceiling_saw_id, floor_saw_id])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	if failures <= 12:
		push_error("FAIL: " + message)
