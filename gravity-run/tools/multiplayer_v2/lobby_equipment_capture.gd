extends Node
## Screenshots of the multiplayer lobby room view with the Equipment toggle: host
## with it off, host with it on, and a guest (read-only). Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/multiplayer_v2/lobby_equipment_capture.tscn -- out_dir

const LobbyScene := preload("res://ui/multiplayer_v2/multiplayer_v2_lobby.tscn")

var out_dir := "user://lobby_captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _room(equipment: Variant) -> Dictionary:
	var members: Array = []
	for slot in [1, 2, 3]:
		members.append({"user_id": "user-%d" % slot, "display_name": ["Adam", "Misse", "Pingo"][slot - 1], "player_slot": slot, "is_ready": slot != 3, "ready_cycle": 1, "ready_content_revision": 1, "returned_for_cycle": 1, "is_connected": true, "loadout_hash": "h", "ready_loadout_hash": "h", "skin_id": slot - 1, "loaded_manifest_hash": "m"})
	var room := {"room_id": "00000000-0000-0000-0000-0000000000c1", "room_session_id": "capture", "room_code": "ABCD1234", "owner_user_id": "user-1", "phase": "OPEN", "lobby_generation": 1, "state_revision": 1, "lobby_cycle": 1, "content_revision": 1, "max_players": 5, "manifest_hash": "m", "members": members}
	if equipment != null:
		room["equipment_enabled"] = equipment
	return room

func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("CAPTURED ", out_dir.path_join(name + ".png"))

func _run() -> void:
	TranslationServer.set_locale("en")
	var lobby: Control = LobbyScene.instantiate()
	add_child(lobby)
	await _frames(3)
	var service := get_tree().root.get_node("MultiplayerV2Service")
	service.identity_user_id = "user-1"
	service.room_state = _room(null)
	service.room_changed.emit(service.room_state)
	await _shot("host_off_missing_field")
	service.room_state = _room(true)
	service.room_changed.emit(service.room_state)
	await _shot("host_on")
	service.identity_user_id = "user-2"
	service.room_changed.emit(service.room_state)
	await _shot("guest_on_readonly")
	service.room_state = _room(false)
	service.room_changed.emit(service.room_state)
	await _shot("guest_off_readonly")
	service.room_state = {}
	get_tree().quit()
