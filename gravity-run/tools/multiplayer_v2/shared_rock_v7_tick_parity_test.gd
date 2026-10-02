extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const RockModel := preload("res://systems/falling_rock_model.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var built: Dictionary = Builder.new().build(100000000, 45000)
	_check(str(built.get("error", "")).is_empty(), "v7 deterministic manifest builds for host and guest simulation")
	var manifest: Resource = built.get("manifest")
	if manifest == null:
		quit(1)
		return
	var rock_event: Dictionary = {}
	for event in manifest.get("events"):
		if str(event.get("kind", "")) == "rock":
			rock_event = event
			break
	_check(not rock_event.is_empty(), "documented v7 course contains a rock")
	if rock_event.is_empty():
		quit(1)
		return
	var host := World.new()
	var guest := World.new()
	_check(str(host.configure(manifest)).is_empty() and str(guest.configure(manifest)).is_empty(), "host and guest configure the same immutable manifest")
	var event_id := str(rock_event.get("event_id", ""))
	var activation_tick := 7
	var commit := {"entity_id": event_id, "incarnation": 1, "action": "activate_rock", "state_before": "active", "state_after": "active", "world_revision": 1, "simulation_tick": activation_tick, "rock_activation_tick": activation_tick}
	_check(host.apply_world_commit(commit) == "applied" and guest.apply_world_commit(commit) == "applied", "one shared activation commit applies on both peers")
	for _tick in range(140):
		host.step_to(host.tick + 1)
		guest.step_to(guest.tick + 1)
	var host_rock: Dictionary = host.render_state(0.0).rocks[0]
	var guest_rock: Dictionary = guest.render_state(0.0).rocks[0]
	_check(host_rock.activation_tick == guest_rock.activation_tick and host_rock.phase == "buried" and guest_rock.phase == "buried", "same authoritative tick advances both copies through the slower fall to buried")
	_check(host_rock.rect == guest_rock.rect and host_rock.rect.size.y == float(rock_event.height) - float(rock_event.burial_depth), "permanent lethal hitbox remains identical on host and guest")
	_check(int(rock_event.get("trigger_lead", 0)) == 1800 and int(rock_event.get("warning_ticks", 0)) == 90 and int(rock_event.get("fall_ticks", 0)) == 42, "new timing and trigger lead are encoded in the shared manifest")
	if failures == 0:
		print("V7 multiplayer rock tick parity passed: one WORLD_COMMIT, both peers buried at tick 139 with identical permanent geometry.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
