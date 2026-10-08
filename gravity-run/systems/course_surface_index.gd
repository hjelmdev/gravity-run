extends RefCounted
class_name CourseSurfaceIndex

const BOUNDARY_EPSILON := 0.00001

var _floor_y := 0.0
var _ceiling_y := 0.0
var _floor_profile: Dictionary = {}
var _ceiling_profile: Dictionary = {}
var _events: Array = []
# Step/slope/gap records per lane, in the original order. linear_surface_at only
# reads those records for the requested lane, so scanning these short lists is
# equivalent to scanning every event and keeps configure() close to linear.
var _floor_surface_events: Array = []
var _ceiling_surface_events: Array = []

# Recently built lane profiles. Singleplayer rebuilds an index several times per
# second from lists that only change at the far end of the course, so intervals
# that end before the first changed surface record are reused as-is (their
# samples cannot be reached by the changed records, see _min_coordinate()).
const PROFILE_CACHE_SIZE := 8
static var _profile_cache: Array = []
## Tests can turn reuse off to compare against fresh profiles.
static var profile_cache_enabled := true
var _use_profile_cache := true

## use_profile_cache=false skips the shared profile cache for short-lived
## windows so they do not evict the long-lived lineages that benefit from it.
func configure(events: Array, initial_floor_y: float, initial_ceiling_y: float, use_profile_cache: bool = true) -> void:
	_use_profile_cache = use_profile_cache and profile_cache_enabled
	_events = events
	_floor_surface_events = []
	_ceiling_surface_events = []
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var kind := str((event_value as Dictionary).get("kind", ""))
		if kind != "step" and kind != "slope" and kind != "gap":
			continue
		if bool((event_value as Dictionary).get("from_ceiling", false)):
			_ceiling_surface_events.append(event_value)
		else:
			_floor_surface_events.append(event_value)
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
			return linear_surface_at(_lane_events(ceiling), _floor_y, _ceiling_y, x, ceiling)
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
	result.assign(profile.get("boundaries", []))
	return result

## Sorted support boundaries inside [start_x, end_x] (or the open interval when
## inclusive is false), found by binary search instead of scanning every one.
func support_boundaries_between(start_x: float, end_x: float, ceiling: bool, inclusive: bool = true) -> Array[float]:
	var profile: Dictionary = _ceiling_profile if ceiling else _floor_profile
	var boundaries: Array = profile.get("boundaries", [])
	var result: Array[float] = []
	if boundaries.is_empty() or end_x < start_x:
		return result
	var first := boundaries.bsearch(start_x, inclusive)
	var last := boundaries.bsearch(end_x, not inclusive)
	if last > first:
		result.assign(boundaries.slice(first, last))
	return result

func interval_is_supported(start_x: float, end_x: float, ceiling: bool) -> bool:
	var left := minf(start_x, end_x)
	var right := maxf(start_x, end_x)
	for event_value in _lane_events(ceiling):
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
	for boundary in support_boundaries_between(left, right, ceiling, true):
		for sample_x in [boundary - BOUNDARY_EPSILON * 2.0, boundary, boundary + BOUNDARY_EPSILON * 2.0]:
			if sample_x >= left and sample_x <= right:
				lowest_y = maxf(lowest_y, float(surface_at(sample_x, ceiling).get("y", lowest_y)))
	return lowest_y

func _lane_events(ceiling: bool) -> Array:
	return _ceiling_surface_events if ceiling else _floor_surface_events

func _build_profile(ceiling: bool) -> Dictionary:
	var lane_events := _lane_events(ceiling)
	var boundaries: Array[float] = []
	for event_value in lane_events:
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
	var cached := _find_cached_profile(lane_events, ceiling) if _use_profile_cache else {}
	var cached_profile: Dictionary = cached.get("profile", {})
	var cached_boundaries: Array = cached_profile.get("boundaries", [])
	var changed_from := float(cached.get("changed_from", -INF))
	for index in range(maxi(unique_boundaries.size() - 1, 0)):
		var start_x := unique_boundaries[index]
		var end_x := unique_boundaries[index + 1]
		if end_x < changed_from and index + 1 < cached_boundaries.size() and float(cached_boundaries[index]) == start_x and float(cached_boundaries[index + 1]) == end_x:
			interval_starts.append(float(cached_profile["interval_starts"][index]))
			interval_ends.append(float(cached_profile["interval_ends"][index]))
			interval_supports.append(bool(cached_profile["interval_supports"][index]))
			continue
		var inset := minf((end_x - start_x) * 0.25, 0.001)
		var left := linear_surface_at(lane_events, _floor_y, _ceiling_y, start_x + inset, ceiling)
		var right := linear_surface_at(lane_events, _floor_y, _ceiling_y, end_x - inset, ceiling)
		var middle := linear_surface_at(lane_events, _floor_y, _ceiling_y, (start_x + end_x) * 0.5, ceiling)
		interval_starts.append(float(left.y))
		interval_ends.append(float(right.y))
		interval_supports.append(bool(middle.supported))
	var final_surface := {"y": initial_y, "supported": true}
	if not unique_boundaries.is_empty():
		final_surface = linear_surface_at(lane_events, _floor_y, _ceiling_y, float(unique_boundaries.back()) + 0.001, ceiling)
	var profile := {"boundaries": unique_boundaries, "interval_starts": interval_starts, "interval_ends": interval_ends, "interval_supports": interval_supports, "initial_y": initial_y, "final_surface": final_surface}
	if not _use_profile_cache:
		return profile
	_profile_cache.push_front({"ceiling": ceiling, "floor_y": _floor_y, "ceiling_y": _ceiling_y, "events": lane_events.duplicate(), "profile": profile})
	if _profile_cache.size() > PROFILE_CACHE_SIZE:
		_profile_cache.resize(PROFILE_CACHE_SIZE)
	return profile

## Returns the cached profile sharing the longest identical record prefix with
## lane_events, plus the lowest x any differing record can influence.
func _find_cached_profile(lane_events: Array, ceiling: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_prefix := -1
	for entry_value in _profile_cache:
		var entry: Dictionary = entry_value
		if bool(entry["ceiling"]) != ceiling or float(entry["floor_y"]) != _floor_y or float(entry["ceiling_y"]) != _ceiling_y:
			continue
		var cached_events: Array = entry["events"]
		var limit := mini(cached_events.size(), lane_events.size())
		var prefix := 0
		while prefix < limit and is_same(cached_events[prefix], lane_events[prefix]):
			prefix += 1
		if prefix > best_prefix:
			best_prefix = prefix
			best = entry
	if best.is_empty():
		return {}
	var changed_from := INF
	for index in range(best_prefix, lane_events.size()):
		changed_from = minf(changed_from, _min_coordinate(lane_events[index]))
	var cached_events: Array = best["events"]
	for index in range(best_prefix, cached_events.size()):
		changed_from = minf(changed_from, _min_coordinate(cached_events[index]))
	return {"profile": best["profile"], "changed_from": changed_from}

## Lowest x at which a surface record can change linear_surface_at() or add a
## profile boundary: steps apply from x, slopes from min(start, end), gaps from
## their nearer edge.
static func _min_coordinate(event_value: Variant) -> float:
	if not event_value is Dictionary:
		return INF
	var event: Dictionary = event_value
	match str(event.get("kind", "")):
		"step":
			return float(event.get("x", 0.0))
		"slope":
			var start_x := float(event.get("start_x", 0.0))
			return minf(start_x, float(event.get("end_x", start_x)))
		"gap":
			var gap_start := float(event.get("x", 0.0)) - float(event.get("width", 0.0)) * 0.5
			return minf(gap_start, gap_start + float(event.get("width", 0.0)))
	return INF

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
