extends RefCounted
class_name CourseSurfaceIndex

const BOUNDARY_EPSILON := 0.00001

var _floor_y := 0.0
var _ceiling_y := 0.0
var _floor_profile: Dictionary = {}
var _ceiling_profile: Dictionary = {}
var _events: Array = []

func configure(events: Array, initial_floor_y: float, initial_ceiling_y: float) -> void:
	_events = events
	_floor_y = initial_floor_y
	_ceiling_y = initial_ceiling_y
	_floor_profile = _build_profile(false)
	_ceiling_profile = _build_profile(true)

func surface_at(x: float, ceiling: bool) -> Dictionary:
	var profile: Dictionary = _ceiling_profile if ceiling else _floor_profile
	var boundaries: Array = profile.get("boundaries", [])
	if boundaries.is_empty():
		return {"y": _ceiling_y if ceiling else _floor_y, "supported": true}
	var low := 0
	var high := boundaries.size()
	while low < high:
		var middle := (low + high) >> 1
		var boundary := float(boundaries[middle])
		if absf(x - boundary) <= BOUNDARY_EPSILON:
			return linear_surface_at(_events, _floor_y, _ceiling_y, x, ceiling)
		if boundary < x:
			low = middle + 1
		else:
			high = middle
	if low == 0:
		return {"y": float(profile.get("initial_y", 0.0)), "supported": true}
	if low >= boundaries.size():
		return profile.get("final_surface", {"y": float(profile.get("initial_y", 0.0)), "supported": true}).duplicate()
	var starts: Array = profile.get("interval_starts", [])
	var ends: Array = profile.get("interval_ends", [])
	var supports: Array = profile.get("interval_supports", [])
	var index := low - 1
	var start_x := float(boundaries[index])
	var end_x := float(boundaries[index + 1])
	var weight := clampf((x - start_x) / maxf(end_x - start_x, 0.000001), 0.0, 1.0)
	return {"y": lerpf(float(starts[index]), float(ends[index]), weight), "supported": bool(supports[index])}

func support_boundaries(ceiling: bool) -> Array[float]:
	var profile: Dictionary = _ceiling_profile if ceiling else _floor_profile
	var result: Array[float] = []
	for value in profile.get("boundaries", []):
		result.append(float(value))
	return result

func interval_is_supported(start_x: float, end_x: float, ceiling: bool) -> bool:
	var left := minf(start_x, end_x)
	var right := maxf(start_x, end_x)
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if str(event.get("kind", "")) != "gap" or bool(event.get("from_ceiling", false)) != ceiling:
			continue
		var gap_left := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
		var gap_right := gap_left + float(event.get("width", 0.0))
		if right >= gap_left and left <= gap_right:
			return false
	return bool(surface_at(left, ceiling).get("supported", false)) and bool(surface_at(right, ceiling).get("supported", false))

func lowest_surface_y_over_interval(start_x: float, end_x: float, ceiling: bool) -> float:
	var left := minf(start_x, end_x)
	var right := maxf(start_x, end_x)
	var lowest_y := maxf(float(surface_at(left, ceiling).get("y", 0.0)), float(surface_at(right, ceiling).get("y", 0.0)))
	for boundary in support_boundaries(ceiling):
		if boundary < left or boundary > right:
			continue
		for sample_x in [boundary - BOUNDARY_EPSILON * 2.0, boundary, boundary + BOUNDARY_EPSILON * 2.0]:
			if sample_x >= left and sample_x <= right:
				lowest_y = maxf(lowest_y, float(surface_at(sample_x, ceiling).get("y", lowest_y)))
	return lowest_y

func _build_profile(ceiling: bool) -> Dictionary:
	var boundaries: Array[float] = []
	for event_value in _events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				boundaries.append(float(event.get("x", 0.0)))
			"slope":
				boundaries.append(float(event.get("start_x", 0.0)))
				boundaries.append(float(event.get("end_x", event.get("start_x", 0.0))))
			"gap":
				var gap_start := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
				boundaries.append(gap_start)
				boundaries.append(gap_start + float(event.get("width", 0.0)))
	boundaries.sort()
	var unique_boundaries: Array[float] = []
	for value in boundaries:
		if unique_boundaries.is_empty() or absf(value - unique_boundaries.back()) > BOUNDARY_EPSILON:
			unique_boundaries.append(value)
	var initial_y := _ceiling_y if ceiling else _floor_y
	var interval_starts: Array[float] = []
	var interval_ends: Array[float] = []
	var interval_supports: Array[bool] = []
	for index in range(maxi(unique_boundaries.size() - 1, 0)):
		var start_x := unique_boundaries[index]
		var end_x := unique_boundaries[index + 1]
		var inset := minf((end_x - start_x) * 0.25, 0.001)
		var left := linear_surface_at(_events, _floor_y, _ceiling_y, start_x + inset, ceiling)
		var right := linear_surface_at(_events, _floor_y, _ceiling_y, end_x - inset, ceiling)
		var middle := linear_surface_at(_events, _floor_y, _ceiling_y, (start_x + end_x) * 0.5, ceiling)
		interval_starts.append(float(left.y))
		interval_ends.append(float(right.y))
		interval_supports.append(bool(middle.supported))
	var final_surface := {"y": initial_y, "supported": true}
	if not unique_boundaries.is_empty():
		final_surface = linear_surface_at(_events, _floor_y, _ceiling_y, float(unique_boundaries.back()) + 0.001, ceiling)
	return {"boundaries": unique_boundaries, "interval_starts": interval_starts, "interval_ends": interval_ends, "interval_supports": interval_supports, "initial_y": initial_y, "final_surface": final_surface}

static func linear_surface_at(events: Array, initial_floor_y: float, initial_ceiling_y: float, x: float, ceiling: bool) -> Dictionary:
	var y := initial_ceiling_y if ceiling else initial_floor_y
	var supported := true
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if bool(event.get("from_ceiling", false)) != ceiling:
			continue
		match str(event.get("kind", "")):
			"step":
				if x >= float(event.get("x", 0.0)):
					y = float(event.get("end_y", y))
			"slope":
				var start_x := float(event.get("start_x", 0.0))
				var end_x := float(event.get("end_x", start_x))
				if x >= start_x and x <= end_x and end_x > start_x:
					y = lerpf(float(event.get("start_y", y)), float(event.get("end_y", y)), (x - start_x) / (end_x - start_x))
				elif x > end_x:
					y = float(event.get("end_y", y))
			"gap":
				var gap_start := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
				if x >= gap_start and x <= gap_start + float(event.get("width", 0.0)):
					supported = false
	return {"y": y, "supported": supported}
