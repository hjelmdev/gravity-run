extends Node
## Supabase RPC transport for the verified shared-coin account and award contract.

const Config := preload("res://systems/leaderboard_config.gd")
signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
signal request_timing(action: String, context: String, queue_usec: int, http_usec: int)

var _request: HTTPRequest
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "MultiplayerV2CoinRequest"
	_request.timeout = 5.0
	_request.accept_gzip = false
	_request.process_mode = Node.PROCESS_MODE_ALWAYS
	_request.request_completed.connect(_on_completed)
	add_child(_request)

func call_rpc(action: String, rpc_name: String, payload: Dictionary, token: String, context: String = "") -> void:
	if token.is_empty():
		request_finished.emit(action, false, null, "An authenticated multiplayer identity is required.", context)
		return
	var item := {"action": action, "rpc": rpc_name, "payload": payload, "token": token, "context": context}
	item["queued_usec"] = Time.get_ticks_usec()
	if action == "coin_awards_settle":
		if str(_active.get("action", "")) == action and str(_active.get("context", "")) == context:
			return
		for queued in _queue:
			if str(queued.get("action", "")) == action and str(queued.get("context", "")) == context:
				return
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		if _queue.size() >= 128:
			request_finished.emit(action, false, null, "Coin RPC retry queue is full.", context)
			return
		var insert_at := _queue.size()
		if _is_startup_action(action):
			for index in range(_queue.size()):
				if not _is_startup_action(str(_queue[index].get("action", ""))):
					insert_at = index
					break
		_queue.insert(insert_at, item)
		return
	_start(item)

func _start(item: Dictionary) -> void:
	_active = item
	_active["started_usec"] = Time.get_ticks_usec()
	var headers := PackedStringArray(["apikey: " + Config.PUBLISHABLE_KEY, "Authorization: Bearer " + str(item.token), "Content-Type: application/json", "Accept: application/json"])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, str(item.rpc)]
	var err := _request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(item.payload))
	if err != OK:
		_active.clear()
		request_timing.emit(str(item.action), str(item.context), maxi(Time.get_ticks_usec() - int(item.get("queued_usec", Time.get_ticks_usec())), 0), 0)
		request_finished.emit(str(item.action), false, {"error_code": "request_start_failed", "error": err}, "Could not start coin RPC request (%d)." % err, str(item.context))
		_dispatch_next.call_deferred()

func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var item := _active
	_active.clear()
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var queue_usec := maxi(int(item.get("started_usec", Time.get_ticks_usec())) - int(item.get("queued_usec", Time.get_ticks_usec())), 0)
	var http_usec := maxi(Time.get_ticks_usec() - int(item.get("started_usec", Time.get_ticks_usec())), 0)
	request_timing.emit(str(item.get("action", "")), str(item.get("context", "")), queue_usec, http_usec)
	var message := ""
	if not ok:
		message = str(data.get("message", "Coin RPC failed (HTTP %d)." % response_code)) if data is Dictionary else "Coin RPC network failure (%d/%d)." % [result, response_code]
		if not data is Dictionary:
			data = {}
		data["http_status"] = response_code
		data["http_result"] = result
	request_finished.emit(str(item.get("action", "")), ok, data, message, str(item.get("context", "")))
	_dispatch_next.call_deferred()

func _dispatch_next() -> void:
	if _queue.is_empty() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_start(_queue.pop_front())

static func _is_startup_action(action: String) -> bool:
	return action in ["coin_link_request", "coin_link_resolve", "coin_round_register"]
