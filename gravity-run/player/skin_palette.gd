extends RefCounted

const SHADER := preload("res://player/skin_palette.gdshader")
const HUE_SHIFTS: Array[float] = [0.0, 0.28, 0.52, 0.75]
const SKIN_COUNT := 4

static func make_material(skin_id: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("hue_shift", HUE_SHIFTS[posmod(skin_id, SKIN_COUNT)])
	return material
