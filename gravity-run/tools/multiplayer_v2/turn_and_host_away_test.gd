extends SceneTree
## TURN credentials are merged into the shared ICE list (STUN stays, stale TURN
## entries are replaced), and a guest learns that the host's tab is hidden.

const ServiceScript := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const TransportScript := preload("res://systems/multiplayer_v2/v2_webrtc_transport.gd")
const TurnScript := preload("res://systems/multiplayer_v2/v2_turn_credentials.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_turn_merge()
	await _test_host_away()
	print("TURN_AND_HOST_AWAY_TEST failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _test_turn_merge() -> void:
	var list: Array = TransportScript.STUN_SERVERS.duplicate(true)
	var turn: Node = TurnScript.new(list)
	turn.apply([
		{"urls": ["stun:stun.cloudflare.com:3478", "turn:turn.cloudflare.com:3478?transport=udp", "turns:turn.cloudflare.com:443?transport=tcp"], "username": "u1", "credential": "c1"},
		{"urls": "stun:only.example:3478"},
		"junk",
	])
	_check(list.size() == 2, "one TURN entry is added next to STUN (%d entries)" % list.size())
	var added: Dictionary = list[1]
	_check((added.urls as Array).size() == 2 and str(added.username) == "u1" and str(added.credential) == "c1", "only turn: urls are kept, with their credentials")
	turn.apply([{"urls": ["turn:new.example:3478"], "username": "u2", "credential": "c2"}])
	_check(list.size() == 2 and str((list[1] as Dictionary).username) == "u2", "a refresh replaces the old TURN entry")
	turn.apply([])
	_check(list == TransportScript.STUN_SERVERS, "an empty answer leaves plain STUN")
	turn.free()
	_check(TransportScript.ice_servers.size() >= 1 and str((TransportScript.ice_servers[0] as Dictionary).urls[0]).begins_with("stun:"), "the transport starts with STUN")

func _test_host_away() -> void:
	var service: Node = ServiceScript.new()
	root.add_child(service)
	await process_frame
	var seen: Array[bool] = []
	service.host_away_changed.connect(func(away: bool) -> void: seen.append(away))
	service.call("_handle_guest_control", "HOST_AWAY", {"away": true})
	_check(bool(service.get("host_away")) and seen == [true], "a guest hears that the host is away")
	service.call("_handle_guest_control", "HOST_AWAY", {"away": false})
	_check(not bool(service.get("host_away")) and seen == [true, false], "and that the host is back")
	service.set("session", {"role": "guest"})
	service.call("notify_page_hidden", true)
	_check(seen == [true, false], "a guest's own tab going hidden sends nothing")
	service.queue_free()
	await process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)
