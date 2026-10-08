extends Node
## Screenshots of the character view and the pause menu. Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/ui_capture.tscn -- out_dir

const InventoryScreenScene := preload("res://ui/inventory_screen.tscn")
var out_dir := "user://ui_captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file_name + ".png"))
	print("CAPTURED ", out_dir.path_join(file_name + ".png"))

func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _run() -> void:
	AuthService.is_authenticated = true
	var screen := InventoryScreenScene.instantiate()
	add_child(screen)
	await _frames(3)
	var helmet: Dictionary = JSON.parse_string('{"item_id":"helmet_copper_01","slot_type":"helmet","rarity":"common","name_key":"item.helmet_copper_01.name","description_key":"item.helmet_copper_01.description","icon_key":"helmet_copper_01","stat_modifiers":{},"catalog_version":2}')
	var boots: Dictionary = JSON.parse_string('{"item_id":"boots_canvas_01","slot_type":"boots","rarity":"common","name_key":"item.boots_canvas_01.name","description_key":"item.boots_canvas_01.description","icon_key":"boots_canvas_01","stat_modifiers":{"run_speed_percent":100},"catalog_version":2}')
	screen.set("_state", {
		"equipment": {"helmet": "h1", "boots": "b1"},
		"items": [{"instance_id": "h1", "item_id": "helmet_copper_01"}, {"instance_id": "b1", "item_id": "boots_canvas_01"}],
		"catalog": [helmet, boots],
	})
	screen.call("_render")
	await _frames(4)
	await _save("character_view")
	screen.queue_free()
	await _frames(2)
	var pause: CanvasLayer = (load("res://ui/pause_menu.tscn") as PackedScene).instantiate()
	add_child(pause)
	await _frames(2)
	pause.call("_set_paused", true)
	await _frames(4)
	await _save("pause_menu")
	pause.call("_show_control_options")
	await _frames(4)
	await _save("pause_options")
	_report_panel(pause)
	pause.call("_show_smoothness_diagnostics")
	await _frames(4)
	await _save("pause_diagnostics")
	pause.queue_free()
	await _frames(2)
	get_tree().quit(0)

func _report_panel(pause: Node) -> void:
	var panel: Control = pause.get("pause_panel")
	print("PANEL ", panel.get_global_rect(), " viewport ", get_viewport().get_visible_rect().size)
