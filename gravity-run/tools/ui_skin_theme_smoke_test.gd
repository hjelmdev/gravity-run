extends Node
## Smoke test for the skin picker / preference and the menu theme.
## godot --headless --path . res://tools/ui_skin_theme_smoke_test.tscn
var failures: Array[String] = []

func _ready() -> void:
	var original := PlayerProfile.preferred_skin_id
	var original_character := PlayerProfile.selected_character_id
	if not PlayerProfile.set_selected_character_id(&"nova"):
		failures.append("could not select nova")
	var theme_path := str(ProjectSettings.get_setting("gui/theme/custom", ""))
	if theme_path.is_empty() or load(theme_path) == null:
		failures.append("custom theme missing")
	var hub: Control = load("res://ui/game_hub.tscn").instantiate()
	add_child(hub)
	await get_tree().process_frame
	hub.call("_cycle_skin", 1)
	if PlayerProfile.preferred_skin_id != posmod(original + 1, 4):
		failures.append("skin did not advance")
	hub.call("_cycle_skin", -1)
	if PlayerProfile.preferred_skin_id != original:
		failures.append("skin did not return")
	PlayerProfile.set_preferred_skin_id(3)
	hub.call("_apply_skin_preview")
	for i in 30:
		await get_tree().process_frame
	var game: Node = load("res://main.tscn").instantiate()
	add_child(game)
	for i in 120:
		await get_tree().physics_frame
	var player := game.get_node("Player")
	if int(player.get("_skin_id")) != 3:
		failures.append("run did not use preferred skin (got %s)" % str(player.get("_skin_id")))
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if sprite.sprite_frames != CharacterCatalog.get_definition(&"nova").sprite_frames or not is_equal_approx(sprite.scale.x, 2.0):
		failures.append("run did not use the selected character")
	var bag: Control = load("res://ui/inventory_screen.tscn").instantiate()
	add_child(bag)
	await get_tree().process_frame
	bag.call("_cycle_character", 1)
	if PlayerProfile.selected_character_id != &"nova_mini":
		failures.append("bag picker did not advance (got %s)" % PlayerProfile.selected_character_id)
	bag.call("_cycle_character", 1)
	bag.call("_cycle_character", 1)
	if PlayerProfile.selected_character_id != &"nova":
		failures.append("bag picker did not wrap (got %s)" % PlayerProfile.selected_character_id)
	for i in 10:
		await get_tree().process_frame
	PlayerProfile.set_selected_character_id(original_character)
	PlayerProfile.set_preferred_skin_id(original)
	for f in failures:
		push_error(f)
	print("UI_SMOKE failures=%d" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)
