extends RefCounted
class_name RockWarningIcon
## Small reusable sign used by the in-world and off-screen rock warnings: a
## pixel-art warning triangle (dark outline, a band in the danger colour, a warm
## yellow face, a falling rock over a down arrow) in the runners' style.

const ART := 24
static var _textures: Dictionary = {}

static func draw(canvas: CanvasItem, center: Vector2, size: float, danger_color: Color = Color("ff814f"), opacity: float = 1.0) -> void:
	var texture := _texture(danger_color)
	var side := roundf(size / float(ART)) * float(ART) if size >= float(ART) else size
	canvas.draw_texture_rect(texture, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, Color(1.0, 1.0, 1.0, clampf(opacity, 0.0, 1.0)))

## The former vector sign (kept for reference and tools).
static func draw_vector(canvas: CanvasItem, center: Vector2, size: float, danger_color: Color = Color("ff814f"), opacity: float = 1.0) -> void:
	var half := size * 0.5
	var alpha := clampf(opacity, 0.0, 1.0)
	var triangle := PackedVector2Array([
		center + Vector2(0.0, -half),
		center + Vector2(half * 0.88, half * 0.55),
		center + Vector2(-half * 0.88, half * 0.55),
	])
	canvas.draw_colored_polygon(triangle, Color(0.09, 0.12, 0.16, 0.96 * alpha))
	var outline := triangle.duplicate()
	outline.append(triangle[0])
	var outline_color := danger_color
	outline_color.a *= alpha
	canvas.draw_polyline(outline, outline_color, maxf(2.0, size * 0.065), true)
	var stone_color := Color("ffe1a3", alpha)
	var small_stone := PackedVector2Array([
		center + Vector2(-size * 0.23, -size * 0.04),
		center + Vector2(-size * 0.18, -size * 0.15),
		center + Vector2(-size * 0.08, -size * 0.13),
		center + Vector2(-size * 0.06, -size * 0.03),
	])
	var second_stone := PackedVector2Array([
		center + Vector2(size * 0.04, -size * 0.20),
		center + Vector2(size * 0.15, -size * 0.18),
		center + Vector2(size * 0.19, -size * 0.08),
		center + Vector2(size * 0.08, -size * 0.06),
	])
	canvas.draw_colored_polygon(small_stone, stone_color)
	canvas.draw_colored_polygon(second_stone, stone_color)
	var shaft_top := center + Vector2(size * 0.04, -size * 0.03)
	var shaft_bottom := center + Vector2(size * 0.04, size * 0.19)
	canvas.draw_line(shaft_top, shaft_bottom, stone_color, maxf(2.0, size * 0.055), true)
	canvas.draw_line(shaft_bottom, center + Vector2(-size * 0.07, size * 0.09), stone_color, maxf(2.0, size * 0.055), true)
	canvas.draw_line(shaft_bottom, center + Vector2(size * 0.15, size * 0.09), stone_color, maxf(2.0, size * 0.055), true)

static func draw_forward_chevron(canvas: CanvasItem, center: Vector2, size: float, color: Color = Color("ff814f")) -> void:
	canvas.draw_line(center + Vector2(-size * 0.5, -size * 0.5), center + Vector2(size * 0.5, 0.0), color, maxf(2.0, size * 0.12), true)
	canvas.draw_line(center + Vector2(size * 0.5, 0.0), center + Vector2(-size * 0.5, size * 0.5), color, maxf(2.0, size * 0.12), true)

static func _texture(danger_color: Color) -> Texture2D:
	var key := danger_color.to_html()
	if not _textures.has(key):
		var wrapped := CanvasTexture.new()
		wrapped.diffuse_texture = ImageTexture.create_from_image(make_sign(danger_color))
		wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_textures[key] = wrapped
	return _textures[key]

## The sign, ART x ART pixels: a rounded-off triangle with a 1 px dark outline,
## a 2 px band in the danger colour (lit on the left), a yellow face and the
## pictogram (an outlined rock, then a down arrow).
static func make_sign(danger_color: Color) -> Image:
	var image := Image.create(ART, ART, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var outline := Color8(20, 20, 28)
	var face := Color8(255, 214, 90)
	var face_shade := Color8(232, 178, 64)
	var ink := Color8(44, 30, 28)
	var band_light := danger_color.lightened(0.25)
	var top := 1.0
	var bottom := float(ART) - 1.0
	for y in range(ART):
		for x in range(ART):
			var fy := float(y) + 0.5
			if fy < top or fy > bottom + 1.0:
				continue
			var t := (fy - top) / (bottom + 1.0 - top)
			var half := 1.0 + t * (float(ART) * 0.5 - 1.5)
			var dx := absf(float(x) + 0.5 - float(ART) * 0.5)
			if dx > half:
				continue
			var inset := minf(half - dx, (bottom + 1.0 - fy) * 1.6)
			var color := face
			if inset < 1.0:
				color = outline
			elif inset < 2.4:
				color = band_light if float(x) < float(ART) * 0.5 else danger_color
			elif fy > bottom - 3.0:
				color = face_shade
			image.set_pixel(x, y, color)
	# Pictogram: a rock (outlined blob) above a down arrow.
	var rock := ["..kkkk..", ".kRRLRk.", "kRLRRRRk", "kRRRRRRk", ".kRRRRk.", "..kkkk.."]
	var arrow := ["..kk..", "..kk..", "..kk..", "kkkkkk", ".kkkk.", "..kk.."]
	var rock_color := Color8(150, 142, 132)
	for row in range(rock.size()):
		for col in range(str(rock[row]).length()):
			var ch: String = str(rock[row])[col]
			if ch == "k":
				image.set_pixel(8 + col, 9 + row, ink)
			elif ch == "R":
				image.set_pixel(8 + col, 9 + row, rock_color)
			elif ch == "L":
				image.set_pixel(8 + col, 9 + row, rock_color.lightened(0.35))
	for row in range(arrow.size()):
		for col in range(str(arrow[row]).length()):
			if str(arrow[row])[col] == "k":
				image.set_pixel(9 + col, 15 + row, ink)
	return image
