extends SceneTree

const Pulse := preload("res://systems/rock_warning_pulse.gd")

var failures := 0

func _initialize() -> void:
	var pulse := Pulse.new()
	_check(not pulse.is_active(), "a new round starts without a HUD warning")
	_check(is_equal_approx(Pulse.screen_center(Vector2(960.0, 540.0)).x, 480.0), "landscape warning is horizontally centered")
	_check(is_equal_approx(Pulse.screen_center(Vector2(540.0, 960.0)).y, 220.8), "portrait warning stays in the upper free area")
	_check(pulse.observe_warning_events([{"event_id": "round-1/rock-a", "phase": "warning"}]), "first warning event starts one pulse")
	_check(pulse.is_active(), "warning is active after the event arrives")
	pulse.advance(0.21)
	var alpha := pulse.alpha()
	_check(not pulse.observe_warning_events([{"event_id": "round-1/rock-a", "phase": "warning"}]), "duplicate snapshots do not start another pulse")
	_check(is_equal_approx(pulse.alpha(), alpha), "duplicate snapshots preserve pulse timing")
	_check(not pulse.observe_warning_events([{"event_id": "round-1/rock-b", "phase": "warning"}]), "simultaneous warning events coalesce into the current brief alert")
	_check(pulse.seen_event_count() == 2, "both event identities are recorded for deduplication")
	pulse.advance(Pulse.DURATION_SECONDS)
	_check(not pulse.is_active(), "the warning fades completely within its bounded duration")
	pulse.reset()
	_check(pulse.seen_event_count() == 0, "round reset clears event deduplication")
	_check(pulse.observe_warning_events([{"event_id": "round-1/rock-a", "phase": "warning"}]), "a later round can reuse an event id after reset")
	if failures == 0:
		print("Rock warning pulse tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
