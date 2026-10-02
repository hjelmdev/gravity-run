extends RefCounted
class_name MultiplayerV2RoundClock

const TICK_RATE := 60.0
const FIXED_DELTA := 1.0 / TICK_RATE

var started_at_usec := -1
var tick := 0
var accumulator := 0.0
var peak_backlog_seconds := 0.0
var host_offset_usec := 0.0
var offset_uncertainty_usec := INF
var last_round_trip_usec := -1
var minimum_round_trip_usec := -1
var offset_jitter_usec := INF
var _sync_offsets: Array[float] = []
var _round_trip_samples: Array[int] = []

func reset() -> void:
	started_at_usec = -1
	tick = 0
	accumulator = 0.0
	peak_backlog_seconds = 0.0
	host_offset_usec = 0.0
	offset_uncertainty_usec = INF
	last_round_trip_usec = -1
	minimum_round_trip_usec = -1
	offset_jitter_usec = INF
	_sync_offsets.clear()
	_round_trip_samples.clear()

func reset_round() -> void:
	started_at_usec = -1
	tick = 0
	accumulator = 0.0
	peak_backlog_seconds = 0.0

func record_clock_exchange(client_sent_usec: int, host_received_usec: int, host_sent_usec: int, client_received_usec: int) -> void:
	if client_received_usec < client_sent_usec or host_sent_usec < host_received_usec:
		return
	var round_trip := (client_received_usec - client_sent_usec) - (host_sent_usec - host_received_usec)
	if round_trip < 0:
		return
	last_round_trip_usec = round_trip
	_round_trip_samples.append(round_trip)
	while _round_trip_samples.size() > 8:
		_round_trip_samples.pop_front()
	minimum_round_trip_usec = _round_trip_samples.min()
	var offset := (float(host_received_usec - client_sent_usec) + float(host_sent_usec - client_received_usec)) * 0.5
	_sync_offsets.append(offset)
	while _sync_offsets.size() > 8:
		_sync_offsets.pop_front()
	var sorted := _sync_offsets.duplicate()
	sorted.sort()
	host_offset_usec = sorted[int(sorted.size() / 2)]
	# RTT is a transport-delay measurement, not clock-estimator quality. A
	# stable 50ms path can still estimate a common offset well enough to start.
	# Require the sampled offset estimates to remain tightly clustered; fixed
	# path asymmetry cannot be inferred from NTP-style four-timestamp probes.
	var maximum_deviation := 0.0
	for sample_offset in _sync_offsets:
		maximum_deviation = maxf(maximum_deviation, absf(sample_offset - host_offset_usec))
	offset_jitter_usec = maximum_deviation
	offset_uncertainty_usec = offset_jitter_usec

func host_time_to_local_usec(host_usec: int) -> int:
	return int(round(float(host_usec) - host_offset_usec))

func is_synchronized(max_uncertainty_usec: float = 16_667.0) -> bool:
	return _sync_offsets.size() >= 3 and offset_uncertainty_usec <= max_uncertainty_usec

func sample_count() -> int:
	return _sync_offsets.size()

func commit_start(monotonic_usec: int) -> bool:
	if started_at_usec >= 0 or monotonic_usec < 0:
		return false
	started_at_usec = monotonic_usec
	tick = 0
	accumulator = 0.0
	return true

func advance(delta: float, step_limit: int = 12) -> int:
	if started_at_usec < 0 or delta <= 0.0:
		return 0
	accumulator += delta
	peak_backlog_seconds = maxf(peak_backlog_seconds, accumulator)
	var steps := mini(int(accumulator / FIXED_DELTA), maxi(step_limit, 0))
	accumulator -= float(steps) * FIXED_DELTA
	tick += steps
	return steps

func render_fraction() -> float:
	return clampf(accumulator / FIXED_DELTA, 0.0, 1.0)

func tick_at_monotonic_usec(monotonic_usec: int) -> float:
	return maxf(float(monotonic_usec - started_at_usec) / 1_000_000.0 * TICK_RATE, 0.0) if started_at_usec >= 0 else 0.0
