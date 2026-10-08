extends Node
## Screenshots of the equipment step 2 items in the real singleplayer scene:
## the HUD effect row, the gravity anchor glide, the touch button and the
## regret boots ring. Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 \
##     res://tools/equipment_step2_capture.tscn -- /tmp/step2

const MainScene := preload("res://main.tscn")

var _out_dir := "/tmp/equipment_step2"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")

func _entry(item_id: String, slot: String, effect_id: String) -> Dictionary:
	return {
		"item_id": item_id, "slot_type": slot, "rarity": "rare",
		"name_key": "item.%s.name" % item_id, "description_key": "item.%s.description" % item_id,
		"icon_key": item_id, "stat_modifiers": {}, "effect_id": effect_id, "effect_level": 1,
		"catalog_version": 3,
	}

func _run() -> void:
	Campaign.persist = false
	var entries: Array = [
		_entry("helmet_bubble_01", "helmet", "bubble_shield"),
		_entry("boots_regret_01", "boots", "regret_flip"),
		_entry("backpack_anchor_01", "backpack", "gravity_anchor"),
	]
	var items: Array = []
	var equipment := {}
	for entry in entries:
		items.append({"instance_id": "owned-%s" % entry.item_id, "item_id": entry.item_id})
		equipment[entry.slot_type] = "owned-%s" % entry.item_id
	InventoryService.inventory_state = {"catalog": entries, "items": items, "equipment": equipment, "wallet_coins": 0}
	var game := MainScene.instantiate() as Node
	get_tree().root.add_child(game)
	var player: Node = game.get_node("Player")
	await _frames(40)
	await _shot("1_run_hud")
	player.call("_try_flip", -1)
	await _frames(6)
	player.call("_try_flip", 1)
	await _frames(3)
	await _shot("2_regret_ring")
	await _frames(60)
	player.call("try_use_anchor")
	await _frames(25)
	await _shot("3_anchor_glide")
	await _frames(40)
	await _shot("4_anchor_recharging")
	get_tree().quit()

func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out_dir, label])
	print("saved ", label)
