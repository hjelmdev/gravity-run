extends "res://hazards/ghost_hand.gd"
class_name EmberBomb
## Volcano hazard (scripted feature "ember_bomb"): a glowing bomb that lands in
## one lane. A red ring in the lane warns first while the bomb falls in from the
## far side of the screen, then it bursts into a molten mound that burns for a
## short while and cools down. The runner on the other surface is safe.
## Timing, hitbox and the swept test are the ghost hand's (a pure function of
## how far the runner is from it); only the look differs.

## How far the bomb falls in (from the other lane's side) during the warning.
const FALL_HEIGHT := 260.0

func configure_hand(value: Dictionary, world_x: float, surface_y: float) -> void:
	super.configure_hand(value, world_x, surface_y)
	add_to_group("ember_bombs")

func _draw() -> void:
	var dir := 1.0 if from_ceiling else -1.0
	var pulse := 0.6 + 0.4 * sin(_clock * 16.0)
	if phase == "glow" or phase == "rising" or phase == "up":
		var strength := _glow if phase == "glow" else 1.0
		# Target ring in the lane the bomb lands in.
		for ring in range(3):
			var radius := 22.0 + float(ring) * 13.0
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(1.0, 0.3, 0.12, 0.55 * strength * pulse), 3.0)
		draw_rect(Rect2(Vector2(-size.x * 0.9, -4.0 if not from_ceiling else 0.0), Vector2(size.x * 1.8, 4.0)), Color(1.0, 0.45, 0.15, 0.85 * strength * pulse))
	if phase == "glow":
		# The bomb falls toward the lane with a short ember trail.
		var t := _glow
		var bomb := Vector2(0.0, dir * FALL_HEIGHT * (1.0 - t))
		for trail in range(4):
			var back := bomb - Vector2(0.0, dir * 18.0 * float(trail + 1))
			draw_circle(back, 9.0 - float(trail) * 2.0, Color(1.0, 0.55, 0.15, 0.35 - float(trail) * 0.07))
		draw_circle(bomb, 13.0, Color(0.22, 0.08, 0.05, 0.95))
		draw_circle(bomb, 8.0, Color(1.0, 0.42, 0.1, 0.9 * pulse))
		return
	if _reach <= 0.01:
		return
	_draw_mound(size.y * _reach, dir, pulse)

## The burning mound: a dark crust with glowing cracks and licking flames.
func _draw_mound(height: float, dir: float, pulse: float) -> void:
	var w := size.x
	var cooling := 1.0 if phase != "sinking" else _reach
	var crust := Color(0.18, 0.07, 0.05, 0.95)
	var glow := Color(1.0, 0.45 + 0.2 * pulse, 0.1, 0.95 * cooling)
	var points := PackedVector2Array([
		Vector2(-w * 0.55, 0.0),
		Vector2(-w * 0.4, dir * height * 0.55),
		Vector2(-w * 0.12, dir * height),
		Vector2(w * 0.14, dir * height * 0.9),
		Vector2(w * 0.42, dir * height * 0.5),
		Vector2(w * 0.55, 0.0),
	])
	draw_colored_polygon(points, crust)
	draw_line(Vector2(-w * 0.3, dir * height * 0.25), Vector2(-w * 0.05, dir * height * 0.7), glow, 3.0)
	draw_line(Vector2(-w * 0.05, dir * height * 0.7), Vector2(w * 0.22, dir * height * 0.45), glow, 3.0)
	draw_line(Vector2(w * 0.05, dir * height * 0.2), Vector2(w * 0.3, dir * height * 0.3), glow, 2.0)
	var flicker := 1.0 if int(_clock * 10.0) % 2 == 0 else 0.8
	for index in range(3):
		var base := Vector2((float(index) - 1.0) * w * 0.25, dir * height * (0.85 if index == 1 else 0.6))
		draw_circle(base + Vector2(0.0, dir * 8.0 * flicker), 6.0 * cooling, Color(1.0, 0.7, 0.2, 0.8 * cooling))
