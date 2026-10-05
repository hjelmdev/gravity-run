extends RefCounted
class_name TouchGestureLifecycle
## Shared touch state machine for SP and MP. The press is only begun from
## _unhandled_input; releases are observed in _input so GUI consumption cannot
## strand an active finger. A deferred cancellation handles consumed releases.

signal diagnostic(event_name: String, details: Dictionary)

const DEFAULT_STALE_TIMEOUT_USEC := 5_000_000

var active_index := -1
var start_position := Vector2.ZERO
var started_usec := -1
var _release_sequence := 0
var _pending_release: Dictionary = {}

func begin(index: int, position: Vector2, now_usec: int = -1) -> bool:
	var now := now_usec if now_usec >= 0 else Time.get_ticks_usec()
	if active_index != -1:
		if index != active_index:
			_emit("rejected", {"reason": "second_finger", "finger": index, "active_finger": active_index})
			return false
		# A platform can reuse an index after omitting its previous lift event.
		# Same-index down is therefore a safe boundary at which to recover.
		cancel("same_index_reused")
	if not _pending_release.is_empty():
		cancel("new_press_before_release_dispatch")
	active_index = index
	start_position = position
	started_usec = now
	_emit("begin", {"finger": index, "x": position.x, "y": position.y})
	return true

func observe_release(index: int, position: Vector2) -> int:
	if active_index == -1 or index != active_index:
		return -1
	_release_sequence += 1
	_pending_release = {
		"token": _release_sequence,
		"finger": index,
		"position": position,
		"delta": position - start_position,
		"duration_usec": maxi(Time.get_ticks_usec() - started_usec, 0),
	}
	return _release_sequence

func consume_release(index: int) -> Dictionary:
	if _pending_release.is_empty() or int(_pending_release.get("finger", -1)) != index:
		return {}
	var result := _pending_release.duplicate(true)
	_clear()
	_emit("end", {"finger": index, "dx": Vector2(result.delta).x, "dy": Vector2(result.delta).y, "duration_usec": int(result.duration_usec)})
	return result

func cancel_if_release_pending(token: int, reason: String = "gui_consumed_release") -> bool:
	if _pending_release.is_empty() or int(_pending_release.get("token", -1)) != token:
		return false
	return cancel(reason)

func cancel_finger(index: int, reason: String = "platform_cancel") -> bool:
	if active_index != index:
		return false
	return cancel(reason)

func cancel(reason: String) -> bool:
	if active_index == -1 and _pending_release.is_empty():
		return false
	var finger := active_index
	var duration := maxi(Time.get_ticks_usec() - started_usec, 0) if started_usec >= 0 else 0
	_clear()
	_emit("cancel", {"reason": reason, "finger": finger, "duration_usec": duration})
	return true

func expire(now_usec: int, timeout_usec: int = DEFAULT_STALE_TIMEOUT_USEC) -> bool:
	if active_index == -1 or started_usec < 0 or now_usec - started_usec < timeout_usec:
		return false
	return cancel("stale_timeout")

func is_active() -> bool:
	return active_index != -1

func pending_token() -> int:
	return int(_pending_release.get("token", -1))

func _clear() -> void:
	active_index = -1
	start_position = Vector2.ZERO
	started_usec = -1
	_pending_release.clear()

func _emit(event_name: String, details: Dictionary) -> void:
	diagnostic.emit(event_name, details)
