extends RefCounted
class_name MultiplayerV2RemoteTrack

const DEFAULT_BUFFER_SECONDS := 0.075
const MAX_EXTRAPOLATION_SECONDS := 0.1
const MAX_HISTORY := 64
const RECOVERY_X_RATE_FACTOR := 0.85
const RECOVERY_Y_RATE := 720.0
const POSE_EPSILON := 0.25

var samples: Array[Dictionary] = []
var render_tick := 0.0
var target_delay_ticks := DEFAULT_BUFFER_SECONDS * 60.0
var initialized := false
var shared_presentation_tick := -1.0
var presentation_mode := "initial"
var correction_magnitude := 0.0
var correction_elapsed_seconds := 0.0

var _displayed_pose: Dictionary = {}
var _recovery_correction := Vector2.ZERO
var _stale_episode := false
var _last_transition := "initial"
var vertical_projector: Callable

func reset() -> void:
	samples.clear()
	render_tick = 0.0
	initialized = false
	shared_presentation_tick = -1.0
	presentation_mode = "initial"
	correction_magnitude = 0.0
	correction_elapsed_seconds = 0.0
	_displayed_pose.clear()
	_recovery_correction = Vector2.ZERO
	_stale_episode = false
	_last_transition = "initial"

func seed(sample: Dictionary) -> bool:
	if not samples.is_empty():
		return false
	var seeded := sample.duplicate(true)
	seeded["simulation_tick"] = 0
	seeded["sample_seq"] = 0
	seeded["locomotion_state"] = "running"
	if not add_sample(seeded):
		return false
	presentation_mode = "seeded"
	_displayed_pose = _sample_raw_at_tick(0.0)
	return true

func set_shared_presentation_tick(value: float) -> void:
	shared_presentation_tick = maxf(value, 0.0)
	if not samples.is_empty():
		render_tick = shared_presentation_tick
		initialized = true
		if _displayed_pose.is_empty():
			_displayed_pose = _sample_raw_at_tick(render_tick)

func add_sample(sample: Dictionary) -> bool:
	var tick := int(sample.get("simulation_tick", -1))
	var sequence := int(sample.get("sample_seq", -1))
	if tick < 0 or sequence < 0 or not is_finite(float(sample.get("world_x", NAN))) or not is_finite(float(sample.get("y", NAN))):
		return false
	for existing in samples:
		if int(existing.get("sample_seq", -2)) == sequence:
			return false
	var insert_at := samples.size()
	for i in range(samples.size()):
		if tick < int(samples[i].get("simulation_tick", 0)):
			insert_at = i
			break
	samples.insert(insert_at, sample.duplicate(true))
	while samples.size() > MAX_HISTORY:
		samples.pop_front()
	if shared_presentation_tick >= 0.0:
		render_tick = shared_presentation_tick
		initialized = true
	elif not initialized:
		render_tick = float(tick) - target_delay_ticks
		initialized = true
	if _stale_episode and str(sample.get("locomotion_state", "running")) == "running":
		var recovered_target := _sample_raw_at_tick(render_tick)
		if not bool(recovered_target.get("stale", true)) and not _displayed_pose.is_empty():
			_recovery_correction = Vector2(float(_displayed_pose.get("world_x", 0.0)) - float(recovered_target.get("world_x", 0.0)), float(_displayed_pose.get("y", 0.0)) - float(recovered_target.get("y", 0.0)))
			correction_magnitude = _recovery_correction.length()
			correction_elapsed_seconds = 0.0
			_stale_episode = false
			presentation_mode = "recovery" if correction_magnitude > POSE_EPSILON else "interpolation"
			_last_transition = "stale_hold_to_recovery"
	return true

func advance(delta: float) -> void:
	if not initialized:
		return
	if shared_presentation_tick < 0.0 and delta > 0.0:
		render_tick += delta * 60.0
	advance_presentation(delta)

func advance_presentation(delta: float) -> Dictionary:
	if samples.is_empty():
		return {"valid": false, "stale": true, "render_mode": "initial"}
	if shared_presentation_tick >= 0.0:
		render_tick = shared_presentation_tick
	var raw := _sample_raw_at_tick(render_tick)
	var state := str(raw.get("locomotion_state", "running"))
	if state != "running":
		presentation_mode = "terminal" if state in ["blocked", "pending_barrel", "dead", "finished"] else "interpolation"
		_stale_episode = false
		_recovery_correction = Vector2.ZERO
		correction_magnitude = 0.0
		_displayed_pose = raw.duplicate(true)
		return _decorate_pose(_displayed_pose, raw, false)
	if bool(raw.get("stale", false)):
		if not _stale_episode:
			_stale_episode = true
			_last_transition = "projection_to_stale_hold"
		presentation_mode = "stale_hold"
		_recovery_correction = Vector2.ZERO
		correction_magnitude = 0.0
		_displayed_pose = raw.duplicate(true)
		return _decorate_pose(_displayed_pose, raw, true)
	if _stale_episode:
		# A sample can become fresh before add_sample is observed at this render time.
		_stale_episode = false
		_recovery_correction = Vector2(float(_displayed_pose.get("world_x", raw.world_x)) - float(raw.world_x), float(_displayed_pose.get("y", raw.y)) - float(raw.y))
		correction_magnitude = _recovery_correction.length()
		correction_elapsed_seconds = 0.0
		presentation_mode = "recovery" if correction_magnitude > POSE_EPSILON else "interpolation"
		_last_transition = "stale_hold_to_recovery"
	if presentation_mode == "recovery":
		var previous_x := float(_displayed_pose.get("world_x", raw.get("world_x", 0.0)))
		var corrected_x := float(raw.get("world_x", 0.0)) + _recovery_correction.x
		if corrected_x < previous_x:
			# Only stale-packet recovery is held forward. Normal samples and terminal
			# contacts are never clamped against a global previous-position maximum.
			_recovery_correction.x += previous_x - corrected_x
			corrected_x = previous_x
		var corrected_y := float(raw.get("y", 0.0)) + _recovery_correction.y
		_displayed_pose = raw.duplicate(true)
		_displayed_pose["world_x"] = corrected_x
		_displayed_pose["y"] = corrected_y
		var speed := maxf(float(raw.get("velocity_x", 0.0)), 0.0)
		_recovery_correction.x = move_toward(_recovery_correction.x, 0.0, speed * delta * RECOVERY_X_RATE_FACTOR)
		_recovery_correction.y = move_toward(_recovery_correction.y, 0.0, RECOVERY_Y_RATE * delta)
		correction_elapsed_seconds += maxf(delta, 0.0)
		correction_magnitude = _recovery_correction.length()
		if correction_magnitude <= POSE_EPSILON:
			_recovery_correction = Vector2.ZERO
			correction_magnitude = 0.0
			presentation_mode = "interpolation"
			_last_transition = "recovery_complete"
	else:
		presentation_mode = "seeded" if samples.size() == 1 and render_tick <= 0.0 else str(raw.get("render_mode", "interpolation"))
		_displayed_pose = raw.duplicate(true)
	return _decorate_pose(_displayed_pose, raw, false)

func sample_at_render_time() -> Dictionary:
	if samples.is_empty():
		return {"valid": false, "stale": true, "render_mode": "initial"}
	if _displayed_pose.is_empty():
		_displayed_pose = _sample_raw_at_tick(render_tick)
	return _decorate_pose(_displayed_pose, _sample_raw_at_tick(render_tick), presentation_mode == "stale_hold")

func consume_transition() -> String:
	var transition := _last_transition
	_last_transition = ""
	return transition

func _sample_raw_at_tick(target_tick: float) -> Dictionary:
	if samples.is_empty():
		return {"valid": false, "stale": true}
	var before: Dictionary = samples[0]
	var after: Dictionary = {}
	for sample in samples:
		if float(sample.get("simulation_tick", 0.0)) <= target_tick:
			before = sample
		elif after.is_empty():
			after = sample
			break
	if not after.is_empty():
		var span := float(after.simulation_tick) - float(before.simulation_tick)
		var weight := clampf((target_tick - float(before.simulation_tick)) / maxf(span, 0.001), 0.0, 1.0)
		# Discrete movement state belongs to the latest sample at or before the
		# presentation tick. Only continuous pose values are interpolated.
		var result := before.duplicate(true)
		for key in ["world_x", "y", "velocity_x", "velocity_y"]:
			result[key] = lerpf(float(before.get(key, after.get(key, 0.0))), float(after.get(key, 0.0)), weight)
		result["valid"] = true
		result["stale"] = false
		result["render_tick"] = target_tick
		result["render_mode"] = "interpolation"
		return result
	var elapsed_ticks := maxf(target_tick - float(before.get("simulation_tick", 0.0)), 0.0)
	var elapsed := elapsed_ticks / 60.0
	var result := before.duplicate(true)
	var is_running := str(before.get("locomotion_state", "running")) == "running"
	var projected_seconds := minf(elapsed, MAX_EXTRAPOLATION_SECONDS) if is_running else 0.0
	result["world_x"] = float(before.get("world_x", 0.0)) + maxf(float(before.get("velocity_x", 0.0)), 0.0) * projected_seconds
	# Project vertical motion with the same simulation rules as the game. The
	# caller supplies world support geometry; after the normal freshness window
	# both axes hold and the track becomes stale as before.
	if projected_seconds > 0.0 and vertical_projector.is_valid():
		var projected: Dictionary = vertical_projector.call(before.duplicate(true), float(before.get("simulation_tick", 0.0)) + projected_seconds * 60.0)
		for key in ["y", "velocity_y", "grounded"]:
			if projected.has(key):
				result[key] = projected[key]
	else:
		result["y"] = float(before.get("y", 0.0))
		result["velocity_y"] = 0.0
	result["valid"] = true
	result["stale"] = elapsed > MAX_EXTRAPOLATION_SECONDS or not is_running
	result["render_tick"] = target_tick
	result["render_mode"] = "projection" if elapsed <= MAX_EXTRAPOLATION_SECONDS and is_running else "stale_hold"
	return result

func _decorate_pose(pose: Dictionary, raw: Dictionary, stale: bool) -> Dictionary:
	var result := pose.duplicate(true)
	result["valid"] = bool(raw.get("valid", true))
	result["stale"] = stale
	result["render_tick"] = render_tick
	result["render_mode"] = presentation_mode
	result["correction_magnitude"] = correction_magnitude
	result["correction_elapsed_seconds"] = correction_elapsed_seconds
	return result
