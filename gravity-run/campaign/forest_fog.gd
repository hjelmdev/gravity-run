extends Node2D
class_name ForestFog
## Presentation only: a fog bank over the right part of the screen (campaign
## feature "fog"). The fog starts FORWARD_CLEAR px ahead of the runner, so the
## runner and everything within that distance stay clearly visible, and it is
## held back around every hazard that is coming up (the same lights the cave's
## darkness uses). Collision, timing and generation are untouched. The level tool
## only places fog where the generated events are sparse (CampaignFeatures).

const MAX_LIGHTS := 28
const FORWARD_CLEAR := 320.0
## Scales FORWARD_CLEAR (the lantern biome key, set by main per run).
static var clear_scale := 1.0
const RAMP := 380.0
const MAX_ALPHA := 0.72
const SHADER_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec2 runner_pos = vec2(0.0);
uniform float forward_clear = 320.0;
uniform float max_alpha = 0.72;
uniform float time = 0.0;
uniform int light_count = 0;
uniform vec4 lights[28];
varying vec2 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float ahead = smoothstep(runner_pos.x + forward_clear, runner_pos.x + forward_clear + 260.0, world_pos.x);
	float band = 0.82 + 0.18 * sin(world_pos.x * 0.011 + time * 0.6) * cos(world_pos.y * 0.02 - time * 0.4);
	float clear = 0.0;
	for (int i = 0; i < 28; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 light = lights[i];
		clear = max(clear, light.w * (1.0 - smoothstep(light.z * 0.5, light.z, distance(world_pos, light.xy))));
	}
	COLOR = vec4(0.66, 0.64, 0.84, strength * max_alpha * ahead * band * (1.0 - 0.9 * clear));
}
"""

var sections: Array[Vector2] = []
var _material: ShaderMaterial
var _view_left := 0.0
var _view_width := 960.0
var _strength := 0.0
var _time := 0.0

func setup(fog_sections: Array[Vector2]) -> void:
	sections = fog_sections
	z_index = 70
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material
	visible = false
	set_process(true)

static func strength_for(course_distance: float, fog_sections: Array[Vector2]) -> float:
	var best := 0.0
	for section in fog_sections:
		var fade_in := clampf((course_distance - (section.x - RAMP * 0.5)) / RAMP, 0.0, 1.0)
		var fade_out := clampf(((section.y + RAMP * 0.5) - course_distance) / RAMP, 0.0, 1.0)
		best = maxf(best, minf(fade_in, fade_out))
	return best * best * (3.0 - 2.0 * best) if best > 0.0 else 0.0

func get_strength() -> float:
	return _strength

func _process(delta: float) -> void:
	_time += delta

func update_view(view_left: float, view_width: float, runner_position: Vector2, course_distance: float, lights: PackedVector4Array) -> void:
	_view_left = view_left
	_view_width = view_width
	_strength = strength_for(course_distance, sections)
	visible = _strength > 0.001
	if not visible:
		return
	_material.set_shader_parameter("strength", _strength)
	_material.set_shader_parameter("runner_pos", runner_position)
	_material.set_shader_parameter("forward_clear", FORWARD_CLEAR * clear_scale)
	_material.set_shader_parameter("max_alpha", MAX_ALPHA)
	_material.set_shader_parameter("time", _time)
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
