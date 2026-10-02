extends SceneTree

const Provider := preload("res://systems/multiplayer_v2/v2_coin_award_provider.gd")

class LoopbackHttpStub extends Node:
	var server := TCPServer.new()
	var port := -1
	var requests: Array[String] = []
	var _clients: Array[StreamPeerTCP] = []
	var _buffers: Dictionary = {}
	var _pending: Array[Dictionary] = []

	func start() -> bool:
		for candidate in range(48200, 48300):
			if server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				set_process(true)
				return true
		return false

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			var peer := server.take_connection()
			if peer != null:
				_clients.append(peer)
				_buffers[peer.get_instance_id()] = PackedByteArray()
		for peer in _clients.duplicate():
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_clients.erase(peer)
				_buffers.erase(peer.get_instance_id())
				continue
			var available: int = peer.get_available_bytes()
			if available > 0:
				var read_result: Array = peer.get_data(available)
				if int(read_result[0]) == OK:
					var key: int = peer.get_instance_id()
					_buffers[key] = PackedByteArray(_buffers.get(key, PackedByteArray())) + PackedByteArray(read_result[1])
					_try_schedule_response(peer)
		for pending in _pending.duplicate():
			if Time.get_ticks_usec() < int(pending.due_usec):
				continue
			var target: StreamPeerTCP = pending.peer
			if target.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				target.put_data(str(pending.response).to_utf8_buffer())
				target.disconnect_from_host()
			_pending.erase(pending)

	func _try_schedule_response(peer: StreamPeerTCP) -> void:
		var key: int = peer.get_instance_id()
		var raw: PackedByteArray = _buffers.get(key, PackedByteArray())
		var raw_text := raw.get_string_from_utf8()
		var header_end := raw_text.find("\r\n\r\n")
		if header_end < 0:
			return
		var headers_text := raw_text.substr(0, header_end)
		var content_length := 0
		for line in headers_text.split("\r\n"):
			if str(line).to_lower().begins_with("content-length:"):
				content_length = int(str(line).split(":", false, 1)[1].strip_edges())
		var body_start := headers_text.to_utf8_buffer().size() + 4
		if raw.size() < body_start + content_length:
			return
		var request_parts: PackedStringArray = str(headers_text.split("\r\n", false, 1)[0]).split(" ")
		if request_parts.size() < 2:
			return
		var path := str(request_parts[1])
		var rpc_name := path.get_file()
		requests.append(rpc_name)
		var status := 200
		var body := {"ok": true, "rpc": rpc_name}
		var delay_usec := 0
		if rpc_name == "fail_rpc":
			status = 503
			body = {"message": "stub backend failure"}
		elif rpc_name == "slow_rpc":
			delay_usec = 400_000
		var body_text := JSON.stringify(body)
		var reason := "OK" if status == 200 else "Service Unavailable"
		var response := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, reason, body_text.to_utf8_buffer().size(), body_text]
		_pending.append({"peer": peer, "response": response, "due_usec": Time.get_ticks_usec() + delay_usec})
		_buffers.erase(key)

var failures := 0
var provider: Node
var stub: LoopbackHttpStub
var completions: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var chain_actions: Array[String] = []
var reentrant_chain := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stub = LoopbackHttpStub.new()
	var endpoint := ""
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--rpc-endpoint="):
			endpoint = str(argument).trim_prefix("--rpc-endpoint=")
	if endpoint.is_empty():
		endpoint = OS.get_environment("GRAVITY_RUN_TEST_RPC_URL")
	if endpoint.is_empty():
		root.add_child(stub)
		_check(stub.start(), "a loopback HTTP server binds for real HTTPRequest coverage")
		endpoint = "http://127.0.0.1:%d" % stub.port
	provider = Provider.new()
	root.add_child(provider)
	await process_frame
	provider._project_url = endpoint
	provider._request.timeout = 2.0
	provider.request_finished.connect(_on_finished)
	provider.request_timing.connect(_on_timing)
	reentrant_chain = true
	provider.call_rpc("coin_link_request", "request_rpc", {"step": 1}, "test-token", "bind-context")
	await _wait_for_completion_count(3, 3.0)
	_check(chain_actions == ["coin_link_request", "coin_link_resolve", "coin_round_register"], "the real provider completes the request → resolve → register chain")
	var chain_contexts: Array[String] = []
	for row in completions.slice(0, 3):
		chain_contexts.append(str(row.context))
	_check(chain_contexts == ["bind-context", "bind-context-resolve", "bind-context-register"], "reentrant callbacks dispatch each queued RPC in order")
	for action in chain_actions:
		var matching := completions.filter(func(row: Dictionary) -> bool: return str(row.action) == action)
		_check(matching.size() == 1 and bool(matching[0].success) and str(matching[0].context).begins_with("bind-context"), "each successful chain stage completes once with original action and context: " + action)
		var timing_rows := timings.filter(func(row: Dictionary) -> bool: return str(row.action) == action)
		_check(timing_rows.size() == 1 and str(timing_rows[0].context) == str(matching[0].context) and int(timing_rows[0].http_usec) > 0, "HTTP timing retains action/context and measured duration: " + action)
	reentrant_chain = false

	var before := completions.size()
	provider.call_rpc("coin_link_resolve", "fail_rpc", {}, "test-token", "http-failure")
	await _wait_for_completion_count(before + 1, 2.0)
	var failed: Dictionary = completions.back()
	_check(not bool(failed.success) and str(failed.action) == "coin_link_resolve" and str(failed.context) == "http-failure" and int(failed.data.get("http_status", 0)) == 503, "HTTP error response retains its completion metadata and status: " + JSON.stringify(failed))
	_check(_timing_count("coin_link_resolve", "http-failure") == 1, "HTTP failure still emits exactly one matching timing record")

	before = completions.size()
	provider._request.timeout = 0.12
	provider.call_rpc("coin_round_register", "slow_rpc", {}, "test-token", "http-timeout")
	await _wait_for_completion_count(before + 1, 2.0)
	var timed_out: Dictionary = completions.back()
	_check(not bool(timed_out.success) and str(timed_out.action) == "coin_round_register" and str(timed_out.context) == "http-timeout", "HTTPRequest timeout emits the original action and context: " + JSON.stringify(timed_out))
	var timeout_timing: Dictionary = _find_timing("coin_round_register", "http-timeout")
	_check(not timeout_timing.is_empty() and int(timeout_timing.http_usec) >= 100_000, "timeout HTTP duration is measured")
	provider._request.timeout = 2.0

	before = completions.size()
	provider.call_rpc("coin_awards_settle", "hold_rpc", {}, "test-token", "queue-hold")
	provider.call_rpc("coin_awards_settle", "settle_rpc", {}, "test-token", "queue-settle")
	provider.call_rpc("coin_round_register", "register_rpc", {}, "test-token", "queue-register")
	provider.call_rpc("coin_link_request", "request_rpc", {}, "test-token", "queue-link")
	await _wait_for_completion_count(before + 4, 3.0)
	var queued_contexts: Array[String] = []
	for row in completions.slice(before, before + 4):
		queued_contexts.append(str(row.context))
	_check(queued_contexts == ["queue-hold", "queue-register", "queue-link", "queue-settle"], "startup RPC priority retains FIFO order and delays queued settlement only until startup actions finish")
	for context in ["queue-hold", "queue-register", "queue-link", "queue-settle"]:
		_check(completions.filter(func(row: Dictionary) -> bool: return str(row.context) == context).size() == 1, "queued action completes exactly once: " + context)

	# Keep this last: Godot's URL parser can print an expected error when
	# HTTPRequest rejects a malformed URL synchronously.
	before = completions.size()
	var timing_before := timings.size()
	provider._project_url = "not a URL"
	provider.call_rpc("coin_link_request", "request_rpc", {}, "test-token", "immediate-error")
	_check(completions.size() == before + 1 and not bool(completions.back().success) and str(completions.back().action) == "coin_link_request" and str(completions.back().context) == "immediate-error", "synchronous HTTPRequest start failure retains original request metadata")
	_check(timings.size() == timing_before + 1 and str(timings.back().action) == "coin_link_request" and str(timings.back().context) == "immediate-error" and int(timings.back().http_usec) == 0, "synchronous start failure emits one matching zero-HTTP timing")

	if failures == 0:
		print("Coin provider HTTP transport passed: real loopback HTTPRequest chain, reentrant queue, FIFO/start priority, HTTP failure/timeout, synchronous start error and preserved action/context/timing.")
	else:
		push_error("Coin provider HTTP transport failures: %d" % failures)
	quit(1 if failures > 0 else 0)

func _on_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	completions.append({"action": action, "success": success, "data": data if data is Dictionary else {}, "message": message, "context": context})
	if not reentrant_chain or not success:
		return
	match action:
		"coin_link_request":
			chain_actions.append(action)
			provider.call_rpc("coin_link_resolve", "resolve_rpc", {"step": 2}, "test-token", "bind-context-resolve")
		"coin_link_resolve":
			chain_actions.append(action)
			provider.call_rpc("coin_round_register", "register_rpc", {"step": 3}, "test-token", "bind-context-register")
		"coin_round_register":
			if context == "bind-context-register":
				chain_actions.append(action)

func _on_timing(action: String, context: String, queue_usec: int, http_usec: int) -> void:
	timings.append({"action": action, "context": context, "queue_usec": queue_usec, "http_usec": http_usec})

func _timing_count(action: String, context: String) -> int:
	return timings.filter(func(row: Dictionary) -> bool: return str(row.action) == action and str(row.context) == context).size()

func _find_timing(action: String, context: String) -> Dictionary:
	for row in timings:
		if str(row.action) == action and str(row.context) == context:
			return row
	return {}

func _wait_for_completion_count(count: int, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while completions.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	_check(completions.size() >= count, "provider completes %d request(s) before timeout" % count)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
