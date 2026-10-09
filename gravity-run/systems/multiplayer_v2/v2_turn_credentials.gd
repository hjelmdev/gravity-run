extends Node
## Adds TURN servers to the WebRTC transport's ICE server list, fetched from
## the Supabase Edge Function "turn-credentials" (supabase/functions/
## turn-credentials, the same function as Block Pact). Players on mobile
## networks or company Wi-Fi often cannot connect with STUN alone; TURN relays
## their traffic. The credentials are short-lived, so they are refreshed before
## they expire. If the function is missing or not set up (no Cloudflare TURN
## key), nothing changes and WebRTC keeps running with STUN only.

signal updated(count: int)

const LeaderboardConfig := preload("res://systems/leaderboard_config.gd")
const FUNCTION_PATH := "/functions/v1/turn-credentials"
const RETRY_SECONDS := 300.0

## The list every new peer connection is initialized with (changed in place).
var ice_servers: Array
var _added: Array = []
var _timer: Timer

func _init(p_ice_servers: Array) -> void:
	ice_servers = p_ice_servers

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(refresh)
	add_child(_timer)
	if DisplayServer.get_name() != "headless":
		refresh()

func refresh() -> void:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + LeaderboardConfig.PUBLISHABLE_KEY,
		"Authorization: Bearer " + LeaderboardConfig.PUBLISHABLE_KEY,
		"Content-Type: application/json",
	])
	if http.request(LeaderboardConfig.PROJECT_URL + FUNCTION_PATH, headers, HTTPClient.METHOD_POST, "{}") != OK:
		http.queue_free()
		_timer.start(RETRY_SECONDS)
		return
	var result: Array = await http.request_completed
	http.queue_free()
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if int(result[1]) != 200 or not data is Dictionary or not (data as Dictionary).get("iceServers") is Array:
		_timer.start(RETRY_SECONDS)
		return
	apply(data.iceServers)
	var ttl := float((data as Dictionary).get("ttl", 0))
	if ttl > 0.0:
		_timer.start(maxf(60.0, ttl * 0.5))

## Replaces the TURN servers added last time with `servers` (only entries with
## turn: urls are kept; STUN is already in the list).
func apply(servers: Array) -> void:
	for server in _added:
		ice_servers.erase(server)
	_added.clear()
	for server: Variant in servers:
		if not server is Dictionary or not (server as Dictionary).has("urls"):
			continue
		var urls: Array = server.urls if server.urls is Array else [server.urls]
		var turn := urls.filter(func(url: Variant) -> bool: return str(url).begins_with("turn"))
		if turn.is_empty():
			continue
		var entry := {"urls": turn}
		if server.has("username"):
			entry["username"] = str(server.username)
		if server.has("credential"):
			entry["credential"] = str(server.credential)
		ice_servers.append(entry)
		_added.append(entry)
	updated.emit(_added.size())
