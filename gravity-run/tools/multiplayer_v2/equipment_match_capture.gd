extends Node
## Screenshots of the multiplayer race with Equipment on and a bubble helmet: the
## ready bubble with its HUD slot, and the moment after it absorbed a hit.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/multiplayer_v2/equipment_match_capture.tscn -- out_dir

const Builder := preload("res://systems/course_manifest_builder.gd")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")

var out_dir := "user://match_captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _shot(name: String) -> void:
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("CAPTURED ", out_dir.path_join(name + ".png"))

func _run() -> void:
	var entry := {"item_id": "helmet_bubble_01", "slot_type": "helmet", "rarity": "rare", "name_key": "item.helmet_bubble_01.name", "description_key": "item.helmet_bubble_01.description", "icon_key": "helmet_bubble_01", "stat_modifiers": {}, "effect_id": "bubble_shield", "effect_level": 1, "catalog_version": 3}
	InventoryService.inventory_state = {"catalog": [entry], "items": [{"instance_id": "owned-1", "item_id": "helmet_bubble_01"}], "equipment": {"helmet": "owned-1"}, "wallet_coins": 0}
	var built: Dictionary = Builder.new().build(100000014, 12000, 15)
	MultiplayerV2Service.current_manifest = built.manifest
	MultiplayerV2Service.session = {"role": "host", "round_id": "capture", "local_peer_id": 1}
	MultiplayerV2Service.room_state = {"phase": "RUNNING", "room_id": "fixture-room", "lobby_generation": 1, "members": [{"user_id": "u1", "display_name": "Adam", "player_slot": 1, "skin_id": 0}]}
	MultiplayerV2Service._round_coordinator.round_descriptor = {"round_id": "capture", "players": [], "equipment_enabled": true}
	var race: Node = MatchScene.instantiate()
	add_child(race)
	await get_tree().process_frame
	race.set("_frozen_roster", MultiplayerV2Service.room_state.members.duplicate(true))
	race.set("_round_started", true)
	for _i in range(60):
		race.call("_step_local_round_impl")
	race.call("queue_redraw")
	await _shot("bubble_ready")
	var guard := 0
	while guard < 400 and not bool(race.get("_run_effects").call("is_invulnerable")):
		race.call("_step_local_round_impl")
		guard += 1
	for _i in range(6):
		race.call("_step_local_round_impl")
	race.call("queue_redraw")
	await _shot("bubble_popped")
	get_tree().quit()
