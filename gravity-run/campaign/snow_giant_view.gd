extends "res://campaign/rullaren_view.gd"
## Snöjätten drawn in code on Rullaren's 4 px grid: a shaggy giant of snow with
## an ice-blue face, frosty horns and a snowball in its left fist where
## Rullaren has its barrel drum. It throws the snowballs from there (Rullaren's
## throw, drawn as snowballs) and breathes frost. Same size and anchor as
## Rullaren, so CampaignRun places it the same way.

const FUR := Color("eef6ff")
const FUR_SHADE := Color("b9d0ec")
const FUR_DARK := Color("8aa6cc")
const FACE := Color("6f8fbf")
const FACE_DARK := Color("4b6596")
const HORN := Color("d6f2ff")
const GIANT_OUTLINE := Color("1c2a44")
const GIANT_EYE := Color("7ff0ff")
const SNOWBALL := Color("f4faff")
const SNOWBALL_SHADE := Color("a9c4e6")

func _draw_machine(flash: bool) -> void:
	var fur := Color.WHITE if flash else FUR
	var shade := Color("e8e8e8") if flash else FUR_SHADE
	var stomp := int(_time * 3.0) % 2
	# Legs: two shaggy stumps, stamping in turn.
	for leg in [Vector2(9, 31), Vector2(22, 31)]:
		var lift := 1.0 if (int(leg.x) == 9) == (stomp == 0) else 0.0
		_px(leg.x - 1.0, leg.y - lift, 9, 9 - (1.0 - lift), GIANT_OUTLINE)
		_px(leg.x, leg.y - lift, 7, 7, shade)
		_px(leg.x, leg.y - lift, 3, 7, fur)
	# Body: a big round mound of fur with shaggy tufts.
	_disc(18.0, 21.0, 13.0, GIANT_OUTLINE)
	_disc(18.0, 21.0, 12.0, shade)
	_disc(16.0, 19.0, 10.0, fur)
	for tuft in range(7):
		var tx := 7.0 + float(tuft) * 3.6
		_px(tx, 31.0 + float(tuft % 2), 2, 2, FUR_DARK)
	# Head with an ice-blue face, frosty horns.
	_disc(19.0, 9.0, 8.5, GIANT_OUTLINE)
	_disc(19.0, 9.0, 7.5, fur)
	_px(12, 7, 11, 8, GIANT_OUTLINE)
	_px(13, 8, 9, 6, FACE)
	_px(13, 13, 9, 1, FACE_DARK)
	_px(11, 1, 2, 4, GIANT_OUTLINE)
	_px(12, 0, 1, 4, HORN)
	_px(26, 1, 2, 4, GIANT_OUTLINE)
	_px(26, 0, 1, 4, HORN)
	var blink := fmod(_time, 3.1) < 0.12
	var eye := Color.WHITE if flash else GIANT_EYE
	if not blink:
		_px(14, 9, 2, 2, eye)
		_px(19, 9, 2, 2, eye)
		_px(14, 8, 3, 1, GIANT_OUTLINE)
		_px(18, 8, 3, 1, GIANT_OUTLINE)
	# A roaring mouth with icy teeth; it opens wider when it throws.
	var fire := clampf(1.0 - _fire_time / 0.35, 0.0, 1.0)
	var open := 1.0 + roundf(fire * 2.0)
	_px(14, 12, 7, open, GIANT_OUTLINE)
	_px(15, 12, 1, 1, HORN)
	_px(19, 12, 1, 1, HORN)
	# The throwing arm reaching to the left, a snowball in the fist.
	var reach := fire * 2.0
	_px(4.0 - reach, 19, 9, 5, GIANT_OUTLINE)
	_px(5.0 - reach, 20, 8, 3, shade)
	var ball_x := 4.0 - reach
	_disc(ball_x, 27.0, 6.2, GIANT_OUTLINE)
	_disc(ball_x, 27.0, 5.2, SNOWBALL)
	_disc(ball_x + 1.0, 28.0, 3.0, SNOWBALL_SHADE)
	_disc(ball_x - 0.5, 26.5, 2.6, SNOWBALL)

## Thrown snowballs: the pixel snowball of the frost palette, turning as it flies.
func _draw_thrown_barrels() -> void:
	var floor_local := float(HEIGHT_PX) * PIXEL
	for id in _throws:
		var spec: Dictionary = _throws[id]
		var speed := float(spec.speed)
		var progress := (view_left - float(spec.release)) / 150.0
		var world_x := float(spec.x) - (speed - 1.0) * (view_left - float(spec.course_distance))
		var center := Vector2(world_x - position.x, floor_local - BARREL_RADIUS - throw_lift(progress))
		var roll := -(speed - 1.0) * (view_left - float(spec.course_distance)) / BARREL_RADIUS
		var art := PixelHazardArt.barrel_texture(PixelHazardArt.palette(), BARREL_RADIUS, "spiked" if bool(spec.spiked) else "wood")
		var side := Vector2(art.get_size()) * PixelHazardArt.ART_SCALE
		draw_set_transform(center, roll, Vector2.ONE)
		draw_texture_rect(art, Rect2(-side * 0.5, side), false)
		draw_set_transform(Vector2.ZERO)

## Frosty breath instead of smoke.
func _draw_smoke() -> void:
	var base := Vector2(13.0, 12.0) * PIXEL
	for i in range(4):
		var t := fmod(_time * 0.7 + float(i) / 4.0, 1.0)
		var puff := base + Vector2(-t * 70.0, -t * 20.0 + sin(t * 8.0 + float(i)) * 4.0)
		var c := Color(0.9, 0.97, 1.0, (1.0 - t) * 0.6 * modulate.a)
		var size := 4.0 + t * 8.0
		draw_rect(Rect2(puff - Vector2(size, size) * 0.5, Vector2(size, size)), c)
