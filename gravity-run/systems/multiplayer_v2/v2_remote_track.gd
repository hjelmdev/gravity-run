extends RefCounted
class_name MultiplayerV2RemoteTrack

const DEFAULT_BUFFER_SECONDS := 0.075
const MAX_EXTRAPOLATION_SECONDS := 0.1
const MAX_HISTORY := 64

var samples: Array[Dictionary] = []
var render_tick := 0.0
var target_delay_ticks := DEFAULT_BUFFER_SECONDS * 60.0
var initialized := false
var shared_presentation_tick := -1.0

func reset() -> void:
	samples.clear()
	render_tick = 0.0
	initialized = false
	shared_presentation_tick = -1.0

func set_shared_presentation_tick(value: float) -> void:
	shared_presentation_tick = maxf(value, 0.0)
	if not samples.is_empty():
		render_tick = shared_presentation_tick
		initialized = true

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
	return true

func advance(delta: float) -> void:
	if initialized and shared_presentation_tick < 0.0 and delta > 0.0:
		render_tick += delta * 60.0

func sample_at_render_time() -> Dictionary:
	if samples.is_empty():
		return {"valid": false, "stale": true}
	var before: Dictionary = samples[0]
	var after: Dictionary = {}
	for sample in samples:
		if float(sample.simulation_tick) <= render_tick:
			before = sample
		elif after.is_empty():
			after = sample
			break
	if not after.is_empty():
		var span := float(after.simulation_tick) - float(before.simulation_tick)
		var weight := clampf((render_tick - float(before.simulation_tick)) / maxf(span, 0.001), 0.0, 1.0)
		var result := after.duplicate(true)
		for key in ["world_x", "y", "velocity_x", "velocity_y"]:
			result[key] = lerpf(float(before.get(key, after.get(key, 0.0))), float(after.get(key, 0.0)), weight)
		result["valid"] = true
		result["stale"] = false
		result["render_tick"] = render_tick
		return result
	var elapsed := maxf(render_tick - float(before.simulation_tick), 0.0) / 60.0
	var result := before.duplicate(true)
	if elapsed <= MAX_EXTRAPOLATION_SECONDS and str(before.get("locomotion_state", "running")) == "running":
		result.world_x = float(before.get("world_x", 0.0)) + float(before.get("velocity_x", 0.0)) * elapsed
		result.y = float(before.get("y", 0.0)) + float(before.get("velocity_y", 0.0)) * elapsed
		result["stale"] = false
	else:
		result["stale"] = true
	result["valid"] = true
	result["render_tick"] = render_tick
	return result
