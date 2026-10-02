extends Node2D
## Decorative landing chips. This node has no collision and is independent of the rock renderer.

const LIFETIME := 0.48
const GRAVITY := 720.0
const COLORS := [Color("a89b83"), Color("817a6e"), Color("c0ad8b"), Color("756f66")]
const INITIAL_VELOCITIES := [Vector2(-104.0, -155.0), Vector2(-48.0, -205.0), Vector2(56.0, -180.0), Vector2(112.0, -132.0)]
const OFFSETS := [Vector2(-12.0, -3.0), Vector2(-4.0, -8.0), Vector2(5.0, -7.0), Vector2(13.0, -2.0)]

var _age := 0.0

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
		var color: Color = COLORS[index]
		color.a = fade
		draw_colored_polygon(chip, color)
