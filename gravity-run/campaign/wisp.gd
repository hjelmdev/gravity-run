extends Node2D
class_name Wisp
## Presentation of the will-o'-the-wisp (campaign feature "wisp"): a harmless
## green flame that floats ahead of the runner and copies the runner's lane with
## a delay. Position and pickup are decided by CampaignRun each physics tick; this
## node only draws.

const RADIUS := 24.0
var collected := false
var _clock := 0.0
var _burst := 0.0

func _ready() -> void:
	z_index = 5
	set_process(true)

func collect() -> void:
	collected = true
	_burst = 0.0

func _process(delta: float) -> void:
	_clock += delta
	if collected:
		_burst += delta
	queue_redraw()

func _draw() -> void:
	if collected:
		var t := clampf(_burst / 0.5, 0.0, 1.0)
		if t >= 1.0:
			return
		for index in range(8):
			var angle := TAU * float(index) / 8.0
			draw_circle(Vector2.RIGHT.rotated(angle) * (10.0 + 46.0 * t), 4.0 * (1.0 - t) + 1.0, Color(0.7, 1.0, 0.75, 1.0 - t))
		return
	var bob := sin(_clock * 4.0) * 4.0
	var center := Vector2(0.0, bob)
	for ring in range(4):
		draw_circle(center, RADIUS * (1.9 - 0.35 * float(ring)), Color(0.45, 1.0, 0.6, 0.07 + 0.05 * float(ring)))
	# Flame: a teardrop with a bright core and a flickering tail.
	var flicker := 1.0 + 0.12 * sin(_clock * 17.0)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -RADIUS * 1.5 * flicker), center + Vector2(RADIUS * 0.8, -RADIUS * 0.1),
		center + Vector2(RADIUS * 0.5, RADIUS * 0.7), center + Vector2(-RADIUS * 0.5, RADIUS * 0.7), center + Vector2(-RADIUS * 0.8, -RADIUS * 0.1),
	]), Color(0.4, 0.95, 0.6, 0.9))
	draw_circle(center + Vector2(0.0, 2.0), RADIUS * 0.55, Color(0.85, 1.0, 0.85, 0.95))
	draw_rect(Rect2(center + Vector2(-7.0, -2.0), Vector2(4.0, 5.0)), Color(0.08, 0.2, 0.12))
	draw_rect(Rect2(center + Vector2(3.0, -2.0), Vector2(4.0, 5.0)), Color(0.08, 0.2, 0.12))
