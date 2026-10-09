extends "res://hazards/ghost_hand.gd"
class_name LightningStrike
## Cloud Realm hazard (scripted feature "lightning"): lightning strikes one
## lane. While a dark storm cloud gathers over the far side and sparks crackle
## along the lane, a dashed zigzag shows where the bolt will land; then a bolt
## cracks down into the lane and leaves a crackling electric column for a short
## while. The runner on the other surface is safe. Timing, hitbox and the swept
## test are the ghost hand's (a pure function of how far the runner is from
## it); only the look differs.

const BOLT := Color(1.0, 0.96, 0.62)
const BOLT_CORE := Color(1.0, 1.0, 1.0)
const BOLT_GLOW := Color(0.62, 0.78, 1.0)
const CLOUD := Color(0.28, 0.26, 0.4)
const CLOUD_LIGHT := Color(0.44, 0.42, 0.58)
const OUTLINE := Color(0.16, 0.14, 0.3)
## How far the bolt reaches above the column (never into the other lane).
const SKY_REACH := 50.0

func configure_hand(value: Dictionary, world_x: float, surface_y: float) -> void:
	super.configure_hand(value, world_x, surface_y)
	add_to_group("lightning_strikes")

## A zigzag from `from` toward `to` in px-snapped steps; the same each frame
## within a flicker step (the bolt jumps a few times a second).
func _zigzag(from: Vector2, to: Vector2, segments: int, jitter: float, salt: int) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	for index in range(1, segments):
		var t := float(index) / float(segments)
		var side := 1.0 if (index + salt) % 2 == 0 else -1.0
		var wobble := side * jitter * (0.5 + 0.5 * absf(sin(float(index * 7 + salt * 3))))
		points.append((from.lerp(to, t) + Vector2(wobble, 0.0)).snapped(Vector2(2.0, 2.0)))
	points.append(to)
	return points

func _draw() -> void:
	var dir := 1.0 if from_ceiling else -1.0
	var flicker := int(_clock * 14.0)
	var pulse := 0.6 + 0.4 * sin(_clock * 18.0)
	if phase == "glow":
		var strength := _glow
		# The storm cloud gathering over the lane, on the far side of the screen.
		var cloud_y := dir * (size.y + 50.0)
		var grow := 0.6 + 0.4 * strength
		var parts := [
			[Rect2(-36.0, -8.0, 72.0, 16.0), CLOUD],
			[Rect2(-24.0, -18.0, 32.0, 12.0), CLOUD_LIGHT],
			[Rect2(0.0, -14.0, 24.0, 8.0), CLOUD_LIGHT],
			[Rect2(-32.0, 6.0, 64.0, 4.0), OUTLINE],
		]
		for part in parts:
			var rect: Rect2 = part[0]
			var scaled := Rect2(rect.position * grow + Vector2(0.0, cloud_y), rect.size * grow)
			draw_rect(scaled.grow(2.0), Color(OUTLINE, 0.8 * strength))
		for part in parts:
			var rect: Rect2 = part[0]
			draw_rect(Rect2(rect.position * grow + Vector2(0.0, cloud_y), rect.size * grow), Color(part[1], 0.9 * strength))
		# The dashed path the bolt will take, and sparks along the lane.
		var path := _zigzag(Vector2(0.0, cloud_y), Vector2.ZERO, 7, 10.0, 1)
		for index in range(path.size() - 1):
			if index % 2 == 0:
				draw_line(path[index], path[index + 1], Color(BOLT, 0.5 * strength * pulse), 2.0)
		draw_rect(Rect2(Vector2(-size.x * 0.9, -4.0 if not from_ceiling else 0.0), Vector2(size.x * 1.8, 4.0)), Color(BOLT_GLOW, 0.85 * strength * pulse))
		for spark in range(4):
			var spark_x := (float((flicker + spark * 5) % 9) / 8.0 - 0.5) * size.x * 1.6
			draw_rect(Rect2(Vector2(spark_x, dir * (4.0 + float(spark % 2) * 6.0)) - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(BOLT, strength))
		return
	if _reach <= 0.01:
		return
	var height := size.y * _reach
	var fade := 1.0 if phase != "sinking" else _reach
	# A faint bolt from the sky down to the column, then the bright column.
	var sky := _zigzag(Vector2(0.0, dir * (height + SKY_REACH)), Vector2(0.0, dir * height), 3, 10.0, flicker % 3)
	draw_polyline(sky, Color(OUTLINE, 0.5 * fade), 6.0)
	draw_polyline(sky, Color(BOLT, 0.8 * fade), 2.0)
	draw_rect(Rect2(Vector2(-size.x * 0.5, 0.0 if from_ceiling else -height), Vector2(size.x, height)), Color(BOLT_GLOW, 0.4 * fade))
	for strand in range(2):
		var bolt := _zigzag(Vector2((float(strand) - 0.5) * size.x * 0.3, dir * height), Vector2((float(strand) - 0.5) * size.x * 0.5, 0.0), 5, size.x * 0.22, flicker + strand)
		draw_polyline(bolt, Color(OUTLINE, 0.9 * fade), 10.0)
		draw_polyline(bolt, Color(BOLT_GLOW, 0.9 * fade), 7.0)
		draw_polyline(bolt, Color(BOLT, fade), 4.0)
		draw_polyline(bolt, Color(BOLT_CORE, fade), 2.0)
	# Scorch flash where it hits the lane.
	draw_rect(Rect2(Vector2(-size.x * 0.7, -6.0 if not from_ceiling else 0.0), Vector2(size.x * 1.4, 6.0)), Color(BOLT, 0.9 * fade * pulse))
