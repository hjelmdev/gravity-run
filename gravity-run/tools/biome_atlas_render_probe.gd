extends Node2D

const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
var biome: BiomeDefinition

func _draw() -> void:
	if biome == null:
		return
	BiomeRendererScript.draw_surface_tiles(self, biome, false, 63.0, 129.0, 0.0, Callable(self, "_surface_y"), Color.WHITE, 0.0)

func _surface_y(_x: float, _ceiling: bool) -> float:
	return 64.0
