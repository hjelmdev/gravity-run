extends Node

const ItemPresentationScript := preload("res://ui/item_presentation.gd")
var presentation_failures := 0

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
	var magnet_payload: Dictionary = {"item_id": "backpack_magnet_01", "slot_type": "backpack", "rarity": "uncommon", "name_key": "item.backpack_magnet_01.name", "description_key": "item.backpack_magnet_01.description", "icon_key": "backpack_magnet_01", "stat_modifiers": {}, "effect_id": "coin_magnet", "effect_level": 1, "catalog_version": 3}
	screen.set("_state", {
		"equipment": {"backpack": "owned-pack", "cape": "owned-cape"},
		"items": [{"instance_id": "owned-pack", "item_id": "backpack_magnet_01"}, {"instance_id": "owned-cape", "item_id": "cape_x"}],
		"catalog": [magnet_payload, {"item_id": "cape_x", "slot_type": "cape", "name_key": "x", "description_key": "y"}]
	})
	screen.call("_render")
	await get_tree().process_frame
	var backpack_tooltip: String = ItemPresentationScript.tooltip(magnet_payload)
	if not ("Coin Magnet" in backpack_tooltip and "Backpack" in backpack_tooltip and "Pulls in coins within 90 px" in backpack_tooltip):
		push_error("Backpack effect item should show its slot and effect: %s" % backpack_tooltip)
		get_tree().quit(1)
		return
	_test_item_presentation()
	if presentation_failures > 0:
		get_tree().quit(1)
		return
	print("Inventory equipment stats UI test passed.")
	get_tree().quit()

func _test_item_presentation() -> void:
	var fixtures := [
		{"item_id": "helmet_copper_01", "slot_type": "helmet", "rarity": "common", "name_key": "item.helmet_copper_01.name", "description_key": "item.helmet_copper_01.description", "stat_modifiers": {}},
		{"item_id": "helmet_scout_01", "slot_type": "helmet", "rarity": "uncommon", "name_key": "item.helmet_scout_01.name", "description_key": "item.helmet_scout_01.description", "stat_modifiers": {}},
		{"item_id": "helmet_night_01", "slot_type": "helmet", "rarity": "rare", "name_key": "item.helmet_night_01.name", "description_key": "item.helmet_night_01.description", "stat_modifiers": {}},
		{"item_id": "boots_canvas_01", "slot_type": "boots", "rarity": "common", "name_key": "item.boots_canvas_01.name", "description_key": "item.boots_canvas_01.description", "stat_modifiers": {"run_speed_percent": 100}},
		{"item_id": "boots_runner_01", "slot_type": "boots", "rarity": "uncommon", "name_key": "item.boots_runner_01.name", "description_key": "item.boots_runner_01.description", "stat_modifiers": {"run_speed_percent": 250}},
		{"item_id": "boots_gravity_01", "slot_type": "boots", "rarity": "rare", "name_key": "item.boots_gravity_01.name", "description_key": "item.boots_gravity_01.description", "stat_modifiers": {"flip_cooldown_percent": -300}},
	]
	TranslationServer.set_locale("en")
	var english_names := ["Copper Helmet", "Scout Hood", "Night Visor", "Canvas Boots", "Runner Boots", "Gravity Boots"]
	for index in range(fixtures.size()):
		_check(ItemPresentationScript.item_name(fixtures[index]) == english_names[index], "English item name %d should be localized" % index)
	var canvas_tooltip := ItemPresentationScript.tooltip(fixtures[3])
	_check("Canvas Boots" in canvas_tooltip and "Boots · Common" in canvas_tooltip and "Comfortable canvas shoes." in canvas_tooltip and "Run speed +1%" in canvas_tooltip, "canvas boots tooltip should include name, slot, rarity, description, and actual modifier")
	_check(ItemPresentationScript.effects(fixtures[4])[0].text == "Run speed +2.5%", "runner boots should format 250 basis points as +2.5 percent")
	var quarter_percent: Dictionary = fixtures[4].duplicate(true)
	quarter_percent["stat_modifiers"] = {"run_speed_percent": 25}
	_check(ItemPresentationScript.effects(quarter_percent)[0].text == "Run speed +0.25%", "small valid modifiers should retain their actual hundredth-percent value")
	var gravity_effect: Dictionary = ItemPresentationScript.effects(fixtures[5])[0]
	_check(gravity_effect.text == "Gravity flip cooldown −3%" and bool(gravity_effect.beneficial), "negative gravity cooldown should be shown as a beneficial reduction")
	_check(ItemPresentationScript.effects(fixtures[0]).is_empty() and "No stat bonuses" in ItemPresentationScript.tooltip(fixtures[0]), "neutral helmet should not invent an effect")
	var malformed := {"item_id": "private_internal_item", "name_key": "missing.item.name", "description_key": "missing.item.description", "slot_type": "boots", "stat_modifiers": {"future_effect": 900}}
	_check(ItemPresentationScript.item_name(malformed) == "Item name unavailable", "missing localized item names should use neutral user text")
	_check(ItemPresentationScript.item_description(malformed) == "Item description unavailable", "missing item descriptions should not expose IDs or keys")
	_check(ItemPresentationScript.effects(malformed).is_empty(), "unsupported modifier IDs should not be shown as active effects")
	var invalid_fractional: Dictionary = fixtures[3].duplicate(true)
	invalid_fractional["stat_modifiers"] = {"run_speed_percent": 100.5}
	_check(ItemPresentationScript.effects(invalid_fractional).is_empty(), "fractional modifiers rejected by the gameplay validator should not be shown")
	TranslationServer.set_locale("sv")
	var swedish_tooltip := ItemPresentationScript.tooltip(fixtures[3])
	_check("Lärkor" in swedish_tooltip and "Löphastighet +1%" in swedish_tooltip, "Swedish tooltip should contain the localized name and modifier")
	var swedish_cooldown: Dictionary = ItemPresentationScript.effects(fixtures[5])[0]
	_check(swedish_cooldown.text == "Väntetid mellan gravitationsbyten −3%" and bool(swedish_cooldown.beneficial), "Swedish cooldown effect should clearly show a beneficial reduction")

func _check(condition: bool, message: String) -> void:
	if not condition:
		presentation_failures += 1
		push_error(message)
