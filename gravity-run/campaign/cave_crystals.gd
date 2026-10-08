extends Node2D
class_name CaveCrystals
## Presentation only: crystal clusters along the dark sections of a cave stage.
## They sit above the darkness overlay and light up as the runner passes, then
## fade slowly to a dim glow. Positions are fixed by the section so the stage
## looks the same on every run.

const FADE_DISTANCE := 1800.0
const CRYSTAL_SPACING := 300.0
const APPROACH := 200.0
const BASE_COLORS := [Color("8fb4ff"), Color("b69cff"), Color("6fd3ff")]

## [{x (world), ceiling, hue, size}]
var crystals: Array[Dictionary] = []
var _runner_x := 0.0
var _surface_y_at := Callable()
var _time := 0.0

func setup(dark_sections: Array[Vector2], seed_value: int) -> void:
	z_index = 81
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for section in dark_sections:
		var x := section.x + 160.0
		while x < section.y:
			crystals.append({
				"x": 180.0 + x + rng.randf_range(-60.0, 60.0),
				"ceiling": rng.randf() < 0.4,
				"hue": rng.randi_range(0, BASE_COLORS.size() - 1),
				"size": rng.randf_range(0.8, 1.3),
			})
			x += CRYSTAL_SPACING + rng.randf_range(-70.0, 90.0)
	set_process(true)


func glow_of(crystal: Dictionary, runner_x: float) -> float:
	var distance := runner_x - float(crystal.x)
	if distance < -APPROACH:
		return 0.0
	if distance < 0.0:
		return 1.0 - (-distance / APPROACH)
	return clampf(1.0 - distance / FADE_DISTANCE, 0.0, 1.0) * 0.75 + 0.25

func update_view(runner_x: float, surface_y_at: Callable) -> void:
	_runner_x = runner_x
	_surface_y_at = surface_y_at
	queue_redraw()

## Lights for the darkness shader from the crystals near the view.
func collect_lights(view_left: float, view_width: float, into: PackedVector4Array) -> void:
	if not _surface_y_at.is_valid():
		return
	for crystal in crystals:
		var x := float(crystal.x)
		if x < view_left - 160.0 or x > view_left + view_width + 160.0:
			continue
		var glow := glow_of(crystal, _runner_x)
		if glow <= 0.02:
			continue
		var on_ceiling := bool(crystal.ceiling)
		var base_y := float(_surface_y_at.call(x, on_ceiling))
		var center_y := base_y + (24.0 if on_ceiling else -24.0)
		into.append(Vector4(x, center_y, 60.0 + 120.0 * glow, glow))

func _process(delta: float) -> void:
	_time += delta

func _draw() -> void:
	if not _surface_y_at.is_valid():
		return
	for crystal in crystals:
		var x := float(crystal.x)
		if absf(x - _runner_x) > 1400.0:
			continue
		var glow := glow_of(crystal, _runner_x)
		var on_ceiling := bool(crystal.ceiling)
		var base_y := float(_surface_y_at.call(x, on_ceiling))
		var dir := 1.0 if on_ceiling else -1.0
		var color: Color = BASE_COLORS[int(crystal.hue)]
		var size := float(crystal.size)
		var pulse := 0.9 + 0.1 * sin(_time * 3.0 + x)
		var bright := color.lerp(Color.WHITE, 0.35 * glow)
		bright.a = 0.28 + 0.72 * glow * pulse
		if glow > 0.05:
			draw_circle(Vector2(x, base_y + dir * 22.0 * size), 46.0 * size * glow, Color(color.r, color.g, color.b, 0.16 * glow))
		var shards := [Vector2(-9.0, 26.0), Vector2(0.0, 40.0), Vector2(10.0, 22.0)]
		for shard in shards:
			var half := 5.5 * size
			var tip := Vector2(x + shard.x * size, base_y + dir * shard.y * size)
			var left := Vector2(x + shard.x * size - half, base_y)
			var right := Vector2(x + shard.x * size + half, base_y)
			draw_colored_polygon(PackedVector2Array([left, tip, right]), bright)
			var edge := bright.lightened(0.35)
			draw_line(left, tip, edge, 1.5)
			draw_line(Vector2(tip.x, tip.y), Vector2(tip.x - half * 0.2, base_y + dir * (shard.y * size) * 0.4), edge, 1.0)
