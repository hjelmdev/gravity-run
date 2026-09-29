extends SceneTree

func _initialize() -> void:
	root.add_child(preload("res://tools/unified_webrtc_rpc_fixture.gd").new())
