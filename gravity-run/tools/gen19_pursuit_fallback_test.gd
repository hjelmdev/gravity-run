extends SceneTree
## Exercise the Gen19-only deterministic replacement when a full two-lane chase
## is rejected, and prove the fallback is withheld when its safe ceiling route
## lacks support.

const Builder := preload("res://systems/course_manifest_builder.gd")

var failures := 0

func _initialize() -> void:
	var builder := Builder.new()
	var supported_events := _close_pursuits()
	var first: Array[Dictionary] = builder.filter_unsafe_gen19_pursuits(supported_events)
	var second: Array[Dictionary] = builder.filter_unsafe_gen19_pursuits(supported_events)
	var fallback_count := 0
	var fallback_found := false
	for event in first:
		if bool(event.get("gen19_supported_fallback", false)):
			fallback_count += 1
			fallback_found = str(event.get("kind", "")) == "block" and str(event.get("event_id", "")) == "pursuit_b"
	_check(first == second, "supported fallback is deterministic across repeated resolutions")
	_check(fallback_count == 1 and fallback_found, "too-close second chase is replaced by one existing single-lane block")
	var unsupported := _close_pursuits()
	unsupported.append({"event_id": "ceiling_gap", "kind": "gap", "x": 7500.0, "width": 180.0, "from_ceiling": true})
	var rejected: Array[Dictionary] = builder.filter_unsafe_gen19_pursuits(unsupported)
	var unsupported_fallbacks := 0
	for event in rejected:
		if bool(event.get("gen19_supported_fallback", false)) and str(event.get("event_id", "")) == "pursuit_b":
			unsupported_fallbacks += 1
	_check(unsupported_fallbacks == 0, "no fallback for the pursuit whose route overlaps an unsupported ceiling gap")
	print("GEN19_PURSUIT_FALLBACK_TEST fallback_count=%d unsupported_fallbacks=%d failures=%d" % [fallback_count, unsupported_fallbacks, failures])
	quit(1 if failures > 0 else 0)

func _close_pursuits() -> Array[Dictionary]:
	return [
		{"event_id": "pursuit_a", "kind": "ghost", "ghost_variant": 3, "x": 5000.0, "width": 72.0, "trigger_lead": 2500.0, "warning_ticks": 90, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "floor_y": 460.0, "ceiling_y": 80.0},
		{"event_id": "pursuit_b", "kind": "ghost", "ghost_variant": 3, "x": 7500.0, "width": 72.0, "trigger_lead": 2500.0, "warning_ticks": 90, "pursuit_start_lag": 330.0, "pursuit_speed_delta": 220.0, "floor_y": 460.0, "ceiling_y": 80.0},
	]

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
