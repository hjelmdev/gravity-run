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
var _sync_offsets: Array[float] = []

func reset() -> void:
	started_at_usec = -1
	tick = 0
	accumulator = 0.0
	peak_backlog_seconds = 0.0
	host_offset_usec = 0.0
	offset_uncertainty_usec = INF
	_sync_offsets.clear()

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
	var offset := (float(host_received_usec - client_sent_usec) + float(host_sent_usec - client_received_usec)) * 0.5
	_sync_offsets.append(offset)
	while _sync_offsets.size() > 8:
		_sync_offsets.pop_front()
	var sorted := _sync_offsets.duplicate()
	sorted.sort()
	host_offset_usec = sorted[int(sorted.size() / 2)]
	var uncertainty := float(round_trip) * 0.5
	if _sync_offsets.size() == 1 or uncertainty < offset_uncertainty_usec:
		offset_uncertainty_usec = uncertainty

func host_time_to_local_usec(host_usec: int) -> int:
	return int(round(float(host_usec) - host_offset_usec))

func is_synchronized(max_uncertainty_usec: float = 16_667.0) -> bool:
	return _sync_offsets.size() >= 3 and offset_uncertainty_usec <= max_uncertainty_usec

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
