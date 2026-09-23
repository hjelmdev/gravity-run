extends "res://hazards/hazard.gd"

func _begin_destruction() -> void:
	var top := 0.0 if from_ceiling else -size.y
	_spawn_destruction_fragments(Vector2(0.0, top + size.y * 0.5), [Color("ffad5c"), Color("cf753b"), Color("ffd092")], 10, size)

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var top := 0.0 if from_ceiling else -size.y
	draw_rect(Rect2(Vector2(-size.x * 0.5, top), size), Color("ffad5c"))
	draw_rect(Rect2(Vector2(-size.x * 0.5 + 7.0, top + 8.0), size - Vector2(14.0, 16.0)), Color("cf753b"))
