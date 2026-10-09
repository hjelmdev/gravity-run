extends SceneTree
## Lobby toggle "Equipment on/off": default off, the host's choice reaches the
## room state and the frozen round descriptor, and a missing field means off.

const ServiceScript := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const RoomSettings := preload("res://systems/multiplayer_v2/v2_room_settings.gd")
const LobbyProviderScript := preload("res://systems/multiplayer_v2/v2_lobby_provider.gd")

## Stands in for the Supabase RPCs: set_equipment flips the stored flag and bumps
## the revisions like the SQL does; prepare moves the room to PREPARING_COURSE.
class FakeLobbyProvider extends Node:
	signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)
	signal request_timing(action: String, context: String, queue_usec: int, request_usec: int)
	var owner_service: Node
	var equipment_calls: Array[bool] = []
	var send_equipment_field := true
	func set_equipment(_room_id: String, enabled: bool, _cycle: int, _token: String, context: String) -> void:
		equipment_calls.append(enabled)
		var room: Dictionary = owner_service.room_state.duplicate(true)
		if send_equipment_field:
			room["equipment_enabled"] = enabled
		room["content_revision"] = int(room.get("content_revision", 0)) + 1
		room["state_revision"] = int(room.get("state_revision", 0)) + 1
		_complete.call_deferred("set_equipment", {"room": room}, context)
	func start_prepare(_room_id: String, _token: String, context: String) -> void:
		var room: Dictionary = owner_service.room_state.duplicate(true)
		room["phase"] = "PREPARING_COURSE"
		room["lobby_generation"] = int(room.lobby_generation) + 1
		room["state_revision"] = int(room.state_revision) + 1
		_complete.call_deferred("prepare_round", {"room": room}, context)
	func _complete(action: String, data: Dictionary, context: String) -> void:
		await get_tree().create_timer(0.02).timeout
		request_finished.emit(action, true, data, "", context)

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_settings_helper()
	_test_provider_payload()
	await _test_service_plumbing()
	await _test_missing_field_is_off()
	print("EQUIPMENT_TOGGLE_TEST failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _test_settings_helper() -> void:
	_check(not RoomSettings.equipment_enabled({}), "a room without the field is off")
	_check(not RoomSettings.equipment_enabled({"equipment_enabled": false}), "false is off")
	_check(RoomSettings.equipment_enabled({"equipment_enabled": true}), "true is on")
	for malformed in ["true", 1, null, "on", [true]]:
		_check(not RoomSettings.equipment_enabled({"equipment_enabled": malformed}), "malformed value %s counts as off" % str(malformed))
	var clean_descriptor := {"round_id": "r"}
	RoomSettings.apply_to_descriptor(clean_descriptor, {"equipment_enabled": false})
	_check(clean_descriptor == {"round_id": "r"}, "a clean round leaves the descriptor byte-identical")
	var missing_descriptor := {"round_id": "r"}
	RoomSettings.apply_to_descriptor(missing_descriptor, {})
	_check(missing_descriptor == {"round_id": "r"}, "a room without the field leaves the descriptor untouched")
	var on_descriptor := {"round_id": "r"}
	RoomSettings.apply_to_descriptor(on_descriptor, {"equipment_enabled": true})
	_check(bool(on_descriptor.get("equipment_enabled", false)), "an equipment round freezes the flag into the descriptor")
	_check(bool(RoomSettings.run_config(on_descriptor).get("equipment_enabled", false)), "the run config of an equipment round is on")
	_check(not bool(RoomSettings.run_config(clean_descriptor).get("equipment_enabled", true)), "the run config of a clean round is off")
	_check(not bool(RoomSettings.run_config({}).get("equipment_enabled", true)), "an empty descriptor gives a clean run config")

func _test_provider_payload() -> void:
	var provider: Node = LobbyProviderScript.new()
	_check(provider.has_method("set_equipment"), "the lobby provider exposes set_equipment")
	provider.free()

func _make_service(owner_id: String, room_extra: Dictionary) -> Node:
	var service: Node = ServiceScript.new()
	root.add_child(service)
	await process_frame
	var members: Array = [{"user_id": "host-user", "display_name": "Host", "player_slot": 1, "is_ready": true, "ready_cycle": 1, "ready_content_revision": 1, "returned_for_cycle": 1, "is_connected": true, "loadout_hash": "", "ready_loadout_hash": ""}]
	var room := {"room_id": "00000000-0000-0000-0000-0000000000e1", "room_session_id": "equipment-test", "owner_user_id": "host-user", "phase": "OPEN", "lobby_generation": 1, "state_revision": 1, "lobby_cycle": 1, "content_revision": 1, "game_version": ServiceScript.V2_GAME_VERSION, "seed": 5, "course_length_px": 45000, "manifest_hash": "", "members": members}
	room.merge(room_extra, true)
	service.room_state = room
	service.identity_user_id = owner_id
	service.identity_is_anonymous = true
	var identity: Node = service._identity_adapter
	identity.user_id = owner_id
	identity.access_token = "token-" + owner_id
	identity.expires_at = int(Time.get_unix_time_from_system()) + 3600
	service._lobby_provider.queue_free()
	var fake := FakeLobbyProvider.new()
	fake.owner_service = service
	service.add_child(fake)
	fake.request_finished.connect(service._on_lobby_request_finished)
	fake.request_timing.connect(service._on_lobby_request_timing)
	service._lobby_provider = fake
	return service

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await create_timer(0.03).timeout

func _test_service_plumbing() -> void:
	var service: Node = await _make_service("host-user", {})
	_check(not service.is_equipment_enabled(), "a new room defaults to equipment off")
	_check(service.set_equipment_enabled(true), "the host may switch equipment on in the open lobby")
	await _wait_frames(6)
	_check(service.is_equipment_enabled(), "the toggle reaches the room state")
	_check(RoomSettings.equipment_enabled(service.room_state), "the room state reads as on")
	_check(int(service.room_state.content_revision) == 2, "toggling bumps the content revision so everyone confirms again")
	_check(service._lobby_provider.equipment_calls == [true], "exactly one RPC was sent")
	_check(not service.set_equipment_enabled(true), "setting the same value again sends nothing")
	_check(service._lobby_provider.equipment_calls.size() == 1, "no duplicate RPC for an unchanged toggle")
	# The frozen round descriptor carries the setting to every peer.
	service.room_state.members = [{"user_id": "host-user", "display_name": "Host", "player_slot": 1, "is_ready": true, "ready_cycle": 1, "ready_content_revision": 2, "returned_for_cycle": 1, "is_connected": true, "loadout_hash": "", "ready_loadout_hash": ""}]
	service._start_attempt_id = "equipment-attempt"
	service._begin_identity_action("prepare_round", {"room_id": str(service.room_state.room_id), "attempt_id": "equipment-attempt"})
	await _wait_frames(8)
	var descriptor: Dictionary = service.get_active_round_descriptor()
	_check(not descriptor.is_empty(), "the prepared round has a descriptor")
	_check(bool(RoomSettings.run_config(descriptor).get("equipment_enabled", false)), "the equipment setting reaches the round's run config")
	service.set_equipment_enabled(false)
	_check(not service.is_equipment_enabled() or str(service.room_state.phase) != "OPEN", "toggling is only possible in the open lobby")
	service._active = false
	service.queue_free()
	# A guest cannot change the host setting.
	var guest: Node = await _make_service("guest-user", {})
	_check(not guest.set_equipment_enabled(true), "only the host can change the toggle")
	_check(guest._lobby_provider.equipment_calls.is_empty(), "a guest sends no RPC")
	guest.queue_free()
	# Not allowed once the room left the open lobby.
	var late: Node = await _make_service("host-user", {"phase": "PREPARING_COURSE"})
	_check(not late.set_equipment_enabled(true), "no toggling after the lobby closed")
	late.queue_free()

func _test_missing_field_is_off() -> void:
	# A server without the column answers without the field: still off.
	var service: Node = await _make_service("host-user", {})
	service._lobby_provider.send_equipment_field = false
	service.set_equipment_enabled(true)
	await _wait_frames(6)
	_check(not service.is_equipment_enabled(), "a response without the field leaves equipment off")
	service.room_state.members = [{"user_id": "host-user", "display_name": "Host", "player_slot": 1, "is_ready": true, "ready_cycle": 1, "ready_content_revision": 2, "returned_for_cycle": 1, "is_connected": true, "loadout_hash": "", "ready_loadout_hash": ""}]
	service._start_attempt_id = "clean-attempt"
	service._begin_identity_action("prepare_round", {"room_id": str(service.room_state.room_id), "attempt_id": "clean-attempt"})
	await _wait_frames(8)
	var descriptor: Dictionary = service.get_active_round_descriptor()
	_check(not descriptor.is_empty() and not descriptor.has("equipment_enabled"), "a clean round's descriptor has no equipment key")
	_check(not bool(RoomSettings.run_config(descriptor).get("equipment_enabled", true)), "a clean round's run config is off")
	service._active = false
	service.queue_free()

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
