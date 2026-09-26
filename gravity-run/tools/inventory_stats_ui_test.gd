extends Node

const InventoryScreenScene := preload("res://ui/inventory_screen.tscn")

func _ready() -> void:
	await get_tree().process_frame
	var screen := InventoryScreenScene.instantiate()
	add_child(screen)
	var catalog_payload: Dictionary = JSON.parse_string('{"item_id":"boots_canvas_01","slot_type":"boots","rarity":"common","name_key":"item.boots_canvas_01.name","description_key":"item.boots_canvas_01.description","icon_key":"boots_canvas_01","stat_modifiers":{"run_speed_percent":100},"catalog_version":2}')
	screen.set("_state", {
		"equipment": {"boots": "owned-boots"},
		"items": [{"instance_id": "owned-boots", "item_id": "boots_canvas_01"}],
		"catalog": [catalog_payload]
	})
	var result: Dictionary = screen.call("_resolve_equipment")
	if int(result.get("totals", {}).get("run_speed_percent", -1)) != 10100 or int(result.get("bonuses", {}).get("run_speed_percent", -1)) != 100:
		push_error("Equipped Lärkor should resolve to 101 percent speed and a 100 basis-point bonus: %s" % [result])
		get_tree().quit(1)
		return
	print("Inventory equipment stats UI test passed.")
	get_tree().quit()
