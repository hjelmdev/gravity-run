extends Node

const MainScene := preload("res://main.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const BlockScene := preload("res://hazards/block.tscn")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := MainScene.instantiate() as Node2D
	get_tree().root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await get_tree().process_frame
	var obstacles: Array = game.get("obstacles")
	obstacles.clear()
	var slopes: Array = game.get("slopes")
	slopes.clear()
	var spike_barrel := BarrelScene.instantiate() as Node2D
	spike_barrel.call("configure", Vector2(54.0, 54.0), false)
	spike_barrel.call("set_spiked", true)
	spike_barrel.position = Vector2(1000.0, 460.0)
	var block := BlockScene.instantiate() as Node2D
	block.call("configure", Vector2(48.0, 72.0), false)
	block.position = Vector2(1000.0, 460.0)
	game.add_child(spike_barrel)
	game.add_child(block)
	obstacles.append(spike_barrel)
	obstacles.append(block)
	game.call("_resolve_obstacle_interactions")
	_check(bool(block.call("is_destroying_now")), "singleplayer spiked barrel destroys the explicitly breakable block")
	_check(not bool(spike_barrel.call("is_destroying_now")), "singleplayer spiked barrel keeps rolling after the block")
	_check(bool(spike_barrel.get("is_spiked")), "SP uses the same existing barrel scene's variant data")
	var ordinary_barrel := BarrelScene.instantiate() as Node2D
	ordinary_barrel.call("configure", Vector2(54.0, 54.0), false)
	ordinary_barrel.position = Vector2(2000.0, 460.0)
	var ordinary_block := BlockScene.instantiate() as Node2D
	ordinary_block.call("configure", Vector2(48.0, 72.0), false)
	ordinary_block.position = Vector2(2000.0, 460.0)
	game.add_child(ordinary_barrel)
	game.add_child(ordinary_block)
	obstacles = game.get("obstacles")
	obstacles.clear()
	obstacles.append(ordinary_barrel)
	obstacles.append(ordinary_block)
	game.call("_resolve_obstacle_interactions")
	_check(bool(ordinary_block.call("is_destroying_now")) and bool(ordinary_barrel.call("is_destroying_now")), "ordinary barrel retains its previous destroy-with-block behavior")
	print("SINGLEPLAYER_SPIKED_BARREL_RUNTIME_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
