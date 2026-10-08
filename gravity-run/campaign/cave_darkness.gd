extends Node2D
class_name CaveDarkness
## Presentation only: a dark section of the cave (campaign feature "darkness").
## A full-view overlay darkens the world except for light around the runner, a
## forward window ahead of the runner, and extra lights: every hazard that is
## coming up, the gravity stars and the crystals the runner has passed. The
## forward window always covers the 300 px ahead of the runner over the full
## height of the cave, so nothing that can hurt is ever in the dark. Collision,
## timing and generation are untouched.

const MAX_LIGHTS := 28
const RUNNER_RADIUS := 150.0
## How far ahead of the runner everything stays fully visible.
const FORWARD_VISIBLE := 320.0
const RAMP := 380.0
const AMBIENT_ALPHA := 0.9
const SHADER_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec2 runner_pos = vec2(0.0);
uniform float runner_radius = 150.0;
uniform float forward_visible = 320.0;
uniform float ambient_alpha = 0.9;
uniform int light_count = 0;
uniform vec4 lights[28];
varying vec2 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float lit = 1.0 - smoothstep(runner_radius * 0.45, runner_radius, distance(world_pos, runner_pos));
	float ahead = smoothstep(runner_pos.x - 70.0, runner_pos.x + 20.0, world_pos.x) * (1.0 - smoothstep(runner_pos.x + forward_visible - 140.0, runner_pos.x + forward_visible, world_pos.x));
	lit = max(lit, ahead);
	for (int i = 0; i < 28; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 light = lights[i];
		float d = distance(world_pos, light.xy);
		lit = max(lit, light.w * (1.0 - smoothstep(light.z * 0.4, light.z, d)));
	}
	COLOR = vec4(0.01, 0.014, 0.04, strength * ambient_alpha * (1.0 - lit));
}
"""

## Dark sections as [from, to] course distances.
var sections: Array[Vector2] = []
var _material: ShaderMaterial
var _crystals: Node2D
var _view_left := 0.0
var _view_width := 960.0
var _strength := 0.0

func setup(dark_sections: Array[Vector2], crystal_layer: Node2D) -> void:
	sections = dark_sections
	z_index = 80
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material
	_crystals = crystal_layer
	visible = false

## 0 outside the sections, 1 inside, easing over RAMP at both ends.
static func strength_for(course_distance: float, dark_sections: Array[Vector2]) -> float:
	var best := 0.0
	for section in dark_sections:
		var fade_in := clampf((course_distance - (section.x - RAMP * 0.5)) / RAMP, 0.0, 1.0)
		var fade_out := clampf(((section.y + RAMP * 0.5) - course_distance) / RAMP, 0.0, 1.0)
		best = maxf(best, minf(fade_in, fade_out))
	return best * best * (3.0 - 2.0 * best) if best > 0.0 else 0.0

func get_strength() -> float:
	return _strength

## lights: Vector4(x, y, radius, intensity) in world space.
func update_view(view_left: float, view_width: float, runner_position: Vector2, course_distance: float, lights: PackedVector4Array) -> void:
	_view_left = view_left
	_view_width = view_width
	_strength = strength_for(course_distance, sections)
	visible = _strength > 0.001
	if not visible:
		return
	_material.set_shader_parameter("strength", _strength)
	_material.set_shader_parameter("runner_pos", runner_position)
	_material.set_shader_parameter("runner_radius", RUNNER_RADIUS)
	_material.set_shader_parameter("forward_visible", FORWARD_VISIBLE)
	_material.set_shader_parameter("ambient_alpha", AMBIENT_ALPHA)
	var count := mini(lights.size(), MAX_LIGHTS)
	var padded := PackedVector4Array()
	padded.resize(MAX_LIGHTS)
	for index in range(count):
		padded[index] = lights[index]
	_material.set_shader_parameter("lights", padded)
	_material.set_shader_parameter("light_count", count)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(_view_left - 60.0, -600.0, _view_width + 120.0, 1800.0), Color.WHITE)
