extends "res://hazards/hazard.gd"

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

## Presentation only. "grave" draws each spike as a stone cross-spear (haunted
## campaign stages), "pixel" as the biome's pixel-art steel spike; the triangle hitbox
## is unchanged.
var skin := ""

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var points: PackedVector2Array
	if from_ceiling:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, size.y)])
	else:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, -size.y)])
	if skin == "pixel":
		draw_texture_rect(PixelHazardArt.spike_texture(PixelHazardArt.palette(), size, from_ceiling), Rect2(Vector2(-size.x * 0.5, 0.0 if from_ceiling else -size.y), size), false)
		return
	if skin == "grave":
		draw_colored_polygon(points, Color("8b90a6"))
		draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color("d5d9ea"), 2.5)
		# A crossbar inside the triangle makes it a cross.
		var along := 0.5
		var bar_y: float = lerpf(points[0].y, points[2].y, along)
		var half := size.x * 0.5 * (1.0 - along) * 0.9
		draw_line(Vector2(-half, bar_y), Vector2(half, bar_y), Color("4d5166"), 3.0)
		return
	draw_colored_polygon(points, Color("ff647c"))
	draw_line(points[0], points[2], Color("ffd0d8"), 3.0)

func intersects_rect(rect: Rect2) -> bool:
	var points := _world_triangle()
	return HazardRules.triangle_intersects_rect(points, rect)

func _world_triangle() -> PackedVector2Array:
	var local_points := PackedVector2Array([
		Vector2(-size.x * 0.5, 0.0),
		Vector2(size.x * 0.5, 0.0),
		Vector2(0.0, size.y if from_ceiling else -size.y),
	])
	var triangle := PackedVector2Array()
	for point in local_points:
		triangle.append(to_global(point))
	return triangle

func get_world_triangles() -> Array[PackedVector2Array]:
	return [_world_triangle()]
