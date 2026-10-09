extends Node2D
## The Ghost King's weak point: a lantern hanging from the ceiling or standing
## on the floor. Scenery, not a hazard. When the king drifts into it, it
## flares up and traps him in the light.

const OUTLINE := Color("14101c")
const METAL := Color("4a4a5e")
const GLASS := Color("ffe08a")
const GLOW := Color("ffd76a")

var on_ceiling := false
var floor_y := 460.0
var ceiling_y := 80.0
var _time := 0.0
var _flare_time := -1.0
var _fade_time := -1.0
## "lure": be on my side now (the lantern pulses); "flip": flip away now (an
## arrow flashes toward the other surface); "": nothing to do yet.
var cue := ""

func _ready() -> void:
	z_index = 2

func set_surfaces(floor_value: float, ceiling_value: float) -> void:
	floor_y = floor_value
	ceiling_y = ceiling_value

func flare() -> void:
	if _flare_time < 0.0:
		_flare_time = 0.0

func fade_out() -> void:
	if _fade_time < 0.0 and _flare_time < 0.0:
		_fade_time = 0.0

func _process(delta: float) -> void:
	_time += delta
	if _flare_time >= 0.0:
		_flare_time += delta
	if _fade_time >= 0.0:
		_fade_time += delta
	queue_redraw()

func _draw() -> void:
	var alpha := 1.0 if _fade_time < 0.0 else maxf(0.0, 1.0 - _fade_time / 0.6)
	if alpha <= 0.0:
		return
	var dir := 1.0 if on_ceiling else -1.0
	var base_y := ceiling_y if on_ceiling else floor_y
	# A chain or post, then the lantern body 70 px from the surface.
	var body_center := Vector2(0.0, base_y + dir * 78.0)
	draw_line(Vector2(0.0, base_y), Vector2(0.0, body_center.y - dir * 26.0), Color(OUTLINE, alpha), 6.0)
	draw_line(Vector2(0.0, base_y), Vector2(0.0, body_center.y - dir * 26.0), Color(METAL, alpha), 3.0)
	var flicker := 0.8 + 0.2 * sin(_time * 9.0) * sin(_time * 3.7)
	var glow_radius := 58.0 * flicker
	if _flare_time >= 0.0:
		glow_radius += minf(_flare_time, 0.4) * 400.0 * maxf(0.0, 1.0 - _flare_time / 1.6)
	draw_circle(body_center, glow_radius, Color(GLOW, 0.16 * alpha))
	draw_circle(body_center, glow_radius * 0.6, Color(GLOW, 0.20 * alpha))
	var body := Rect2(body_center - Vector2(18.0, 24.0), Vector2(36.0, 48.0))
	draw_rect(body.grow(3.0), Color(OUTLINE, alpha))
	draw_rect(body, Color(METAL, alpha))
	draw_rect(body.grow(-6.0), Color(GLASS, (0.75 + 0.25 * flicker) * alpha))
	draw_rect(Rect2(body.position + Vector2(-6.0, -6.0), Vector2(48.0, 6.0)), Color(OUTLINE, alpha))
	draw_rect(Rect2(body.position + Vector2(-6.0, 48.0), Vector2(48.0, 6.0)), Color(OUTLINE, alpha))
	draw_circle(body_center, 6.0, Color(1.0, 1.0, 1.0, 0.9 * alpha))
	if _flare_time < 0.0 and _fade_time < 0.0:
		_draw_cue(body_center, dir)

## The flip cue: while luring, a pulsing ring on the lantern; at the flip, a
## flashing double chevron pointing away from the lantern's surface.
func _draw_cue(body_center: Vector2, dir: float) -> void:
	if cue == "lure":
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(body_center, 40.0 + 6.0 * pulse, 0.0, TAU, 32, Color(GLOW, 0.5 + 0.4 * pulse), 4.0)
	elif cue == "flip" and fmod(_time, 0.24) < 0.16:
		var away := -dir
		for step in range(2):
			var tip := body_center + Vector2(0.0, away * (70.0 + float(step) * 26.0))
			var wing := Vector2(26.0, -away * 22.0)
			draw_polyline(PackedVector2Array([tip + Vector2(-wing.x, wing.y), tip, tip + wing]), Color(OUTLINE, 0.9), 12.0)
			draw_polyline(PackedVector2Array([tip + Vector2(-wing.x, wing.y), tip, tip + wing]), Color(1.0, 0.95, 0.6), 6.0)
