extends CanvasLayer
## Compiles the game's shaders while the game loads instead of the first time
## they show up. The browser (WebGL) compiles a shader program on its first
## draw, which is a visible hitch mid-run: the first dark cave section, the
## first fog bank or the first runner in a new skin. This layer draws each
## material once, a few pixels large and almost transparent, for a few frames
## and then frees itself. Drawing (not just creating) the material is what
## triggers the compile, and the draw must be on screen or it is culled.

const FRAMES := 3
## Not 0: the renderer skips items that are fully transparent.
const NEAR_CLEAR := 0.004
const SkinPalette := preload("res://player/skin_palette.gd")

var _frames_left := FRAMES
var _canvas: Node2D

func _ready() -> void:
	layer = -100
	_canvas = Node2D.new()
	_canvas.name = "WarmupCanvas"
	add_child(_canvas)
	var sources: Array[String] = [CaveDarkness.SHADER_CODE, ForestFog.SHADER_CODE]
	var index := 0
	for code in sources:
		var shader := Shader.new()
		shader.code = code
		var material := ShaderMaterial.new()
		material.shader = shader
		# strength 0: both overlays output alpha 0.
		material.set_shader_parameter("strength", 0.0)
		_add_quad(material, index)
		index += 1
	for skin in range(SkinPalette.SKIN_COUNT):
		var sprite := Sprite2D.new()
		sprite.texture = PlaceholderTexture2D.new()
		(sprite.texture as PlaceholderTexture2D).size = Vector2(2.0, 2.0)
		sprite.material = SkinPalette.make_material(skin)
		sprite.self_modulate = Color(1.0, 1.0, 1.0, NEAR_CLEAR)
		sprite.position = Vector2(2.0 + float(index) * 3.0, 2.0)
		_canvas.add_child(sprite)
		index += 1
	# The common draw_* variants (antialiased lines, arcs, polygons).
	_canvas.draw.connect(_draw_primitives)

func _add_quad(material: ShaderMaterial, index: int) -> void:
	var quad := Polygon2D.new()
	quad.polygon = PackedVector2Array([Vector2.ZERO, Vector2(2.0, 0.0), Vector2(2.0, 2.0), Vector2(0.0, 2.0)])
	quad.position = Vector2(2.0 + float(index) * 3.0, 2.0)
	quad.material = material
	_canvas.add_child(quad)

func _draw_primitives() -> void:
	var clear := Color(1.0, 1.0, 1.0, NEAR_CLEAR)
	_canvas.draw_line(Vector2(40.0, 2.0), Vector2(44.0, 4.0), clear, 2.0, true)
	_canvas.draw_arc(Vector2(50.0, 3.0), 2.0, 0.0, TAU, 8, clear, 1.0, true)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(56.0, 2.0), Vector2(58.0, 2.0), Vector2(57.0, 4.0)]), clear)
	_canvas.draw_circle(Vector2(62.0, 3.0), 1.5, clear)

func _process(_delta: float) -> void:
	_canvas.queue_redraw()
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()
