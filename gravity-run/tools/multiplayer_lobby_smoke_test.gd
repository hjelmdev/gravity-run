extends Node

func _ready() -> void:
	var lobby_scene := load("res://ui/multiplayer_lobby.tscn") as PackedScene
	assert(lobby_scene != null, "multiplayer lobby scene should load")
	var lobby := lobby_scene.instantiate()
	add_child(lobby)
	await get_tree().process_frame
	assert(lobby.get_child_count() > 0, "lobby should build its UI on initialization")
	print("Multiplayer lobby UI smoke test passed.")
	get_tree().quit()
