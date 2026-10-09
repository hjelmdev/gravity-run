extends "res://hazards/hazard.gd"

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

## Presentation only. "grave" draws each spike as a stone cross-spear (haunted
## campaign stages), "pixel" as the biome's pixel-art steel spike, "ghost_fire"
## as a flickering purple flame (the Ghost King's fire); the triangle hitbox
## is unchanged.
var skin := ""
var _flame_time := 0.0

func _process(delta: float) -> void:
	super._process(delta)
	if skin == "ghost_fire" and not is_destroying:
		_flame_time += delta
		queue_redraw()

func _draw() -> void:
	if is_destroying:
		_draw_destruction_fragments()
		return
	var points: PackedVector2Array
	if from_ceiling:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, size.y)])
	else:
		points = PackedVector2Array([Vector2(-size.x * 0.5, 0.0), Vector2(size.x * 0.5, 0.0), Vector2(0.0, -size.y)])
	if skin == "ghost_fire":
		_draw_ghost_fire()
		return
	if skin == "pixel":
		draw_texture_rect(PixelHazardArt.spike_texture(PixelHazardArt.palette_at(self), size, from_ceiling), Rect2(Vector2(-size.x * 0.5, 0.0 if from_ceiling else -size.y), size), false)
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

## A purple ghost flame filling the spike's triangle in 4 px blocks: a dark
## violet rim, a lilac body and a pale core, its rows swaying and its tip
## licking up and down. The hitbox stays the triangle.
func _draw_ghost_fire() -> void:
	var px := 4.0
	var dir := 1.0 if from_ceiling else -1.0
	var rows := int(size.y / px)
	var lick := sin(_flame_time * 11.0) * 0.08
	for row in range(rows):
		var t := (float(row) + 0.5) / float(rows)
		var reach := size.x * 0.5 * (1.0 - t) * (1.0 + lick)
		if reach < px * 0.5:
			continue
		var sway := roundf(sin(_flame_time * 8.0 + t * 5.0) * 2.0 * t) * 2.0
		var y := dir * float(row + 1) * px if not from_ceiling else float(row) * px
		var left := roundf((-reach + sway) / px) * px
		var width := maxf(roundf(reach * 2.0 / px) * px, px)
		draw_rect(Rect2(Vector2(left - px * 0.5, y), Vector2(width + px, px)), Color(0.24, 0.1, 0.42, 0.95))
		draw_rect(Rect2(Vector2(left, y), Vector2(width, px)), Color(0.66, 0.42, 1.0, 0.95))
		if width > px * 2.0:
			draw_rect(Rect2(Vector2(left + px, y), Vector2(width - px * 2.0, px)), Color(0.86, 0.76, 1.0, 0.95))
	draw_rect(Rect2(Vector2(-px * 0.5, dir * size.y * (1.05 + lick) - px * 0.5), Vector2(px, px)), Color(0.86, 0.76, 1.0, 0.8))
