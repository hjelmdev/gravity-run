extends Node2D
class_name AshRain
## Presentation only: grey ash and a few embers drift down over the screen
## during a section of a volcano stage (campaign feature "ash"). It never hides
## anything for long: the flakes are small and thin, and the layer fades out
## within ASH_CLEAR px ahead of the runner so the lane right in front stays
## clean. Collision, timing and generation are untouched.

const FLAKES := 140
const RAMP := 420.0
const MAX_ALPHA := 0.55
const ASH_CLEAR := 220.0
## Course distance of the world origin (CampaignRun.COURSE_START_X).
const COURSE_START_X := 180.0

var sections: Array[Vector2] = []
var _flakes: Array[Vector3] = []
var _time := 0.0
var _strength := 0.0
var _view := Rect2(0.0, 0.0, 960.0, 540.0)
var _runner_x := 0.0

func setup(ash_sections: Array[Vector2], seed_value: int) -> void:
	sections = ash_sections
	z_index = 68
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	for index in range(FLAKES):
		# x and y as fractions of the view, z the flake's fall speed factor.
		_flakes.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.4)))
	visible = false
	set_process(true)

static func strength_for(course_distance: float, ash_sections: Array[Vector2]) -> float:
	var best := 0.0
	for section in ash_sections:
		var fade_in := clampf((course_distance - (section.x - RAMP * 0.5)) / RAMP, 0.0, 1.0)
		var fade_out := clampf(((section.y + RAMP * 0.5) - course_distance) / RAMP, 0.0, 1.0)
		best = maxf(best, minf(fade_in, fade_out))
	return best * best * (3.0 - 2.0 * best) if best > 0.0 else 0.0

func get_strength() -> float:
	return _strength

## Called by CampaignRun every physics tick with the camera view.
func update_view(view_left: float, view_width: float, runner_x: float) -> void:
	_view = Rect2(view_left, 0.0, view_width, 540.0)
	_runner_x = runner_x
	_strength = strength_for(runner_x - COURSE_START_X, sections)
	visible = _strength > 0.001

func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()

func _draw() -> void:
	for index in range(_flakes.size()):
		var flake := _flakes[index]
		var fall := fmod(flake.y + _time * 0.09 * flake.z, 1.0)
		var sway := sin(_time * 1.3 + float(index)) * 10.0
		var x := _view.position.x + fmod(flake.x * _view.size.x - _time * 40.0 * flake.z, _view.size.x)
		if x < _view.position.x:
			x += _view.size.x
		x += sway
		var y := -20.0 + fall * (_view.size.y + 40.0)
		var near := clampf((x - (_runner_x + 40.0)) / ASH_CLEAR, 0.0, 1.0)
		var alpha := MAX_ALPHA * _strength * near
		if alpha <= 0.01:
			continue
		if index % 11 == 0:
			draw_circle(Vector2(x, y), 2.2, Color(1.0, 0.55, 0.2, alpha))
		else:
			draw_rect(Rect2(x, y, 3.0, 2.0), Color(0.62, 0.6, 0.6, alpha * 0.8))
