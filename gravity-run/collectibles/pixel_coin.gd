extends RefCounted
class_name PixelCoin
## The coin in the runners' pixel style (one art pixel = 2 world pixels, dark
## outline), drawn in code as a turning coin: FRAMES pictures from face-on to
## edge-on and back. Cached textures with nearest filtering.

const ART := 12
const FRAMES := 8
const FPS := 9.0
## Widths of the coin face per frame (a full turn).
const WIDTHS := [12, 10, 7, 3, 2, 3, 7, 10]
const OUTLINE := Color8(92, 60, 18)
const GOLD := Color8(245, 205, 82)
const GOLD_LIGHT := Color8(255, 240, 170)
const GOLD_DARK := Color8(200, 146, 48)
const EDGE := Color8(176, 120, 38)

static var _frames: Array[Texture2D] = []

static func frame_texture(index: int) -> Texture2D:
	if _frames.is_empty():
		for frame in range(FRAMES):
			var wrapped := CanvasTexture.new()
			wrapped.diffuse_texture = ImageTexture.create_from_image(make_frame(frame))
			wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_frames.append(wrapped)
	return _frames[posmod(index, FRAMES)]

## The frame shown at a time (seconds) for a coin; `phase` staggers coins so
## a row does not turn in lockstep.
static func frame_at(seconds: float, phase: float) -> int:
	return int(floor(seconds * FPS + phase)) % FRAMES

static func make_frame(frame: int) -> Image:
	var image := Image.create(ART, ART, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var w: int = WIDTHS[frame]
	var half := float(w) * 0.5
	var c := float(ART) * 0.5
	for y in range(ART):
		for x in range(ART):
			var p := Vector2((float(x) + 0.5 - c) / maxf(half, 0.5), (float(y) + 0.5 - c) / c)
			if p.length() > 1.0:
				continue
			var color := GOLD
			if w <= 3:
				color = EDGE
			elif p.length() > 0.72:
				color = GOLD_DARK if p.x + p.y > 0.2 else GOLD_LIGHT
			elif absf(p.x) < 0.22 and absf(p.y) < 0.5:
				# The embossed bar in the middle.
				color = GOLD_LIGHT if w >= 10 else GOLD_DARK
			image.set_pixel(x, y, color)
	# A glint on the face-on frames.
	if w >= 10:
		image.set_pixel(int(c) - 3, int(c) - 3, Color.WHITE)
	_outline(image)
	return image

static func _outline(image: Image) -> void:
	var edge: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.5:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + n
				if q.x < 0 or q.y < 0 or q.x >= image.get_width() or q.y >= image.get_height() or image.get_pixel(q.x, q.y).a < 0.5:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		image.set_pixel(p.x, p.y, OUTLINE)
