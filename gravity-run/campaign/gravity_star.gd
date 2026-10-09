extends Node2D
## A gravity star pickup. Drawn in code as a chunky pixel star so it reads at
## any zoom; it bobs gently and bursts when collected.

signal collected(star_index: int)

const RADIUS := 18.0
const GOLD := Color("ffcd3c")
const GOLD_DARK := Color("c88c1e")
const GOLD_LIGHT := Color("fff1a8")
const OUTLINE := Color("14141c")

var star_index := 0
var _time := 0.0
var _collected := false
var _burst := 0.0

func _ready() -> void:
	z_index = 4
	_time = float(star_index) * 0.7

func is_collected() -> bool:
	return _collected

func collect() -> void:
	if _collected:
		return
	_collected = true
	_burst = 0.0
	collected.emit(star_index)

func get_center() -> Vector2:
	return global_position

func _process(delta: float) -> void:
	_time += delta
	if _collected:
		_burst += delta
		if _burst > 0.6:
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	if _collected:
		var t := clampf(_burst / 0.6, 0.0, 1.0)
		var ring_color := GOLD_LIGHT
		ring_color.a = 1.0 - t
		draw_arc(Vector2.ZERO, 14.0 + t * 46.0, 0.0, TAU, 28, ring_color, 4.0 * (1.0 - t) + 1.0)
		for i in range(8):
			var angle := float(i) * TAU / 8.0
			var spark := Vector2(cos(angle), sin(angle)) * (10.0 + t * 54.0)
			draw_rect(Rect2(spark - Vector2(3, 3), Vector2(6, 6)), ring_color)
		return
	var bob := Vector2(0.0, roundf(sin(_time * 3.2) * 1.5) * 2.0)
	# A pulsing halo of 4 px blocks, then the pixel star with a travelling glint.
	var glow := GOLD
	glow.a = 0.14 + 0.08 * sin(_time * 5.0)
	var step := 4.0
	var halo := RADIUS + 10.0
	for gy in range(-8, 9):
		for gx in range(-8, 9):
			var offset := Vector2(float(gx), float(gy)) * step
			if offset.length() <= halo:
				draw_rect(Rect2(bob + offset - Vector2(step, step) * 0.5, Vector2(step, step)), glow)
	var glint := int(floor(_time * 3.0)) % 6
	var texture := PixelStarArt.texture(glint)
	var side := Vector2(texture.get_size()) * 2.0
	draw_texture_rect(texture, Rect2(bob - side * 0.5, side), false)

## The star picture in the runners' pixel style (1 art pixel = 2 world px):
## five points, a light upper half and a darker lower half, a dark outline and
## a glint that runs across it (frame 0..5; frames 3..5 have no glint).
class PixelStarArt:
	const ART := 22
	static var _textures: Array[Texture2D] = []

	static func texture(frame: int) -> Texture2D:
		if _textures.is_empty():
			for index in range(6):
				var wrapped := CanvasTexture.new()
				wrapped.diffuse_texture = ImageTexture.create_from_image(make(index))
				wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				_textures.append(wrapped)
		return _textures[posmod(frame, 6)]

	static func make(frame: int) -> Image:
		var image := Image.create(ART, ART, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var c := float(ART) * 0.5
		var outer := c - 1.0
		var inner := outer * 0.45
		var points := PackedVector2Array()
		for i in range(10):
			var angle := -PI * 0.5 + float(i) * PI / 5.0
			var r := outer if i % 2 == 0 else inner
			points.append(Vector2(c, c + 0.5) + Vector2(cos(angle), sin(angle)) * r)
		for y in range(ART):
			for x in range(ART):
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				if not Geometry2D.is_point_in_polygon(p, points):
					continue
				var color := GOLD if p.y < c + 1.0 else GOLD_DARK
				if p.y < c - 3.0 and p.x < c:
					color = GOLD_LIGHT
				# The glint: a diagonal light band that moves across.
				if frame < 3 and absf((p.x - p.y) - float(frame * 6 - 6)) < 1.5:
					color = GOLD_LIGHT
				image.set_pixel(x, y, color)
		var edge: Array[Vector2i] = []
		for y in range(ART):
			for x in range(ART):
				if image.get_pixel(x, y).a < 0.5:
					continue
				for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + n
					if q.x < 0 or q.y < 0 or q.x >= ART or q.y >= ART or image.get_pixel(q.x, q.y).a < 0.5:
						edge.append(Vector2i(x, y))
						break
		for p in edge:
			image.set_pixel(p.x, p.y, OUTLINE)
		return image
