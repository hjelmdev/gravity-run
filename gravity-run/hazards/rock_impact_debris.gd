extends Node2D
## Decorative landing chips. This node has no collision and is independent of the rock renderer.

const LIFETIME := 0.48
const GRAVITY := 720.0
const COLORS := [Color("a89b83"), Color("817a6e"), Color("c0ad8b"), Color("756f66")]
const INITIAL_VELOCITIES := [Vector2(-104.0, -155.0), Vector2(-48.0, -205.0), Vector2(56.0, -180.0), Vector2(112.0, -132.0)]
const OFFSETS := [Vector2(-12.0, -3.0), Vector2(-4.0, -8.0), Vector2(5.0, -7.0), Vector2(13.0, -2.0)]
const ICE_COLORS := [Color("e7fbff"), Color("a6dcec"), Color("d0f3fa"), Color("8ccbe0")]

var _age := 0.0
var _ice_mode := false
## Meadow pixel style: square chips with an outline, grass bits and dust puffs.
var _pixel_mode := false

const PIXEL_CHIPS := [Vector2(-130.0, -210.0), Vector2(-70.0, -260.0), Vector2(-20.0, -300.0), Vector2(40.0, -270.0), Vector2(95.0, -230.0), Vector2(150.0, -180.0)]
const GRASS_BITS := [Vector2(-90.0, -150.0), Vector2(-30.0, -190.0), Vector2(60.0, -170.0), Vector2(120.0, -140.0)]
const PIXEL_STONE := [Color8(150, 142, 132), Color8(196, 192, 178), Color8(104, 98, 92)]
const PIXEL_GRASS := [Color8(108, 190, 72), Color8(170, 226, 92)]
const PIXEL_OUTLINE := Color8(23, 40, 33)

func configure_pixel(value: bool) -> void:
	_pixel_mode = value

func configure_ice(value: bool) -> void:
	_ice_mode = value

func _ready() -> void:
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var fade := 1.0 - clampf(_age / LIFETIME, 0.0, 1.0)
	if _pixel_mode:
		_draw_pixel(fade)
		return
	for index in range(INITIAL_VELOCITIES.size()):
		var velocity: Vector2 = INITIAL_VELOCITIES[index]
		var origin: Vector2 = OFFSETS[index] + velocity * _age + Vector2(0.0, 0.5 * GRAVITY * _age * _age)
		var rotation := (float(index) - 1.5) * _age * 3.1
		var chip := PackedVector2Array([
			origin + Vector2(-3.2, -1.4).rotated(rotation),
			origin + Vector2(1.6, -2.4).rotated(rotation),
			origin + Vector2(3.1, 1.0).rotated(rotation),
			origin + Vector2(-1.0, 2.3).rotated(rotation),
		])
		var color: Color = ICE_COLORS[index] if _ice_mode else COLORS[index]
		color.a = fade
		draw_colored_polygon(chip, color)

## Snapped to the 2 px art grid, so the chips read as pixels like the rock.
func _draw_pixel(fade: float) -> void:
	var t := _age
	# Dust: puffs that roll out to both sides of the rock along the ground.
	for index in range(4):
		var side := -1.0 if index < 2 else 1.0
		var x := side * (44.0 + float(index % 2) * 18.0 + t * 80.0)
		var radius := 6.0 + t * 26.0 - float(index % 2) * 3.0
		var dust := Color(0.86, 0.8, 0.68, 0.55 * fade)
		_pixel_disc(Vector2(x, -4.0 - t * 20.0), radius, dust)
	# Stone chips with an outline.
	for index in range(PIXEL_CHIPS.size()):
		var velocity: Vector2 = PIXEL_CHIPS[index]
		var p: Vector2 = velocity * t + Vector2(0.0, 0.5 * GRAVITY * t * t) + Vector2(signf(velocity.x) * 34.0, -6.0)
		var s := 6.0 if index % 2 == 0 else 4.0
		var corner := ((p - Vector2(s, s) * 0.5) / 2.0).round() * 2.0
		var outline := PIXEL_OUTLINE
		outline.a = fade
		draw_rect(Rect2(corner - Vector2(2.0, 2.0), Vector2(s + 4.0, s + 4.0)), outline)
		var color: Color = PIXEL_STONE[index % PIXEL_STONE.size()]
		color.a = fade
		draw_rect(Rect2(corner, Vector2(s, s)), color)
	# Grass bits torn up by the landing.
	for index in range(GRASS_BITS.size()):
		var velocity: Vector2 = GRASS_BITS[index]
		var p: Vector2 = velocity * t + Vector2(0.0, 0.5 * GRAVITY * t * t) + Vector2(signf(velocity.x) * 30.0, 0.0)
		var corner := (p / 2.0).round() * 2.0
		var color: Color = PIXEL_GRASS[index % PIXEL_GRASS.size()]
		color.a = fade
		draw_rect(Rect2(corner, Vector2(2.0, 4.0)), color)

## A filled circle built from 4 px blocks, so dust looks pixelated too.
func _pixel_disc(center: Vector2, radius: float, color: Color) -> void:
	var step := 4.0
	var r := ceilf(radius / step)
	for gy in range(-int(r), int(r) + 1):
		for gx in range(-int(r), int(r) + 1):
			var offset := Vector2(float(gx), float(gy)) * step
			if offset.length() <= radius and offset.y <= 2.0:
				draw_rect(Rect2((center / step).round() * step + offset, Vector2(step, step)), color)
