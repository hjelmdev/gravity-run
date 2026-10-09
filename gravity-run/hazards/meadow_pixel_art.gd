extends RefCounted
class_name MeadowPixelArt
## Pixel art for the meadow's hazards, drawn in code at run time in the same
## style as the runners and the meadow ground (tools/pixel_tiles): one art
## pixel is ART_SCALE world pixels, a dark outline, flat colours with one
## highlight and one shade. Hazards come in many sizes, so each picture is made
## for the hazard's exact size and cached. Presentation only: hitboxes are the
## hazards' own.
##
##   block   a mossy stone pillar with a grass tuft on its free end
##   spike   a steel spike with a lit and a shaded face
##   boulder a rounded rock with moss on top, for falling rocks
##   log     the cut end of a rolling log (bark ring, growth rings, crack),
##           optionally with thorns

const ART_SCALE := 2.0
const OUTLINE := Color8(23, 40, 33)
const STONE := Color8(150, 146, 136)
const STONE_LIGHT := Color8(196, 192, 178)
const STONE_DARK := Color8(104, 100, 96)
const MORTAR := Color8(84, 80, 78)
const MOSS := Color8(96, 164, 70)
const MOSS_DARK := Color8(58, 120, 56)
const GRASS_HI := Color8(170, 226, 92)
const STEEL := Color8(176, 186, 198)
const STEEL_LIGHT := Color8(232, 238, 244)
const STEEL_DARK := Color8(108, 116, 132)
const BARK := Color8(104, 66, 42)
const BARK_DARK := Color8(70, 44, 30)
const WOOD := Color8(222, 184, 124)
const WOOD_RING := Color8(186, 140, 86)
const WOOD_CORE := Color8(160, 112, 66)
const THORN := Color8(236, 226, 196)

static var _cache: Dictionary = {}

## A texture ready for drawing (nearest filtering), w x h world pixels.
static func block_texture(size: Vector2, ceiling: bool, variant: int) -> Texture2D:
	return _cached("block|%d|%d|%s|%d" % [int(size.x), int(size.y), str(ceiling), variant], func() -> Image: return make_block(_art(size.x), _art(size.y), ceiling, variant))

## A boulder filling w x h world pixels.
static func boulder_texture(size: Vector2) -> Texture2D:
	return _cached("boulder|%d|%d" % [int(size.x), int(size.y)], func() -> Image: return make_boulder(_art(size.x), _art(size.y)))

static func spike_texture(size: Vector2, ceiling: bool) -> Texture2D:
	return _cached("spike|%d|%d|%s" % [int(size.x), int(size.y), str(ceiling)], func() -> Image: return make_spike(_art(size.x), _art(size.y), ceiling))

## A square texture of the log's cut end, `radius` world pixels.
static func log_texture(radius: float, thorns: bool) -> Texture2D:
	return _cached("log|%d|%s" % [int(radius), str(thorns)], func() -> Image: return make_log(_art(radius), thorns))

static func _art(world: float) -> int:
	return maxi(int(round(world / ART_SCALE)), 2)

static func _cached(key: String, make: Callable) -> Texture2D:
	if not _cache.has(key):
		var wrapped := CanvasTexture.new()
		wrapped.diffuse_texture = ImageTexture.create_from_image(make.call())
		wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_cache[key] = wrapped
	return _cache[key]

static func _blank(w: int, h: int) -> Image:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image

static func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, color)

## Stone pillar: staggered bricks with mortar lines, light top-left edges and
## dark bottom-right edges on every brick, moss creeping up from the attached
## end and a grass tuft on the free end. Drawn for a floor block; a ceiling
## block is the same picture flipped.
static func make_block(w: int, h: int, ceiling: bool, variant: int) -> Image:
	var image := _blank(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4111 + w * 31 + h * 7 + variant * 1009
	var brick_h := 6
	var brick_w := maxi(8, w / 2)
	for y in range(h):
		for x in range(w):
			var color := STONE
			var row := y / brick_h
			var ry := y % brick_h
			var offset := (brick_w / 2) if row % 2 == 1 else 0
			var rx := posmod(x + offset, brick_w)
			if ry == brick_h - 1 or rx == brick_w - 1:
				color = MORTAR
			elif ry == 0 or rx == 0:
				color = STONE_LIGHT
			elif ry == brick_h - 2 or rx == brick_w - 2:
				color = STONE_DARK
			image.set_pixel(x, y, color)
	# A few pits and cracks.
	for _i in range(maxi(1, w * h / 120)):
		var px := rng.randi_range(2, w - 3)
		var py := rng.randi_range(2, h - 3)
		_put(image, px, py, STONE_DARK)
		if rng.randf() < 0.5:
			_put(image, px + 1, py + 1, STONE_DARK)
	# Moss from the bottom (the attached end), in uneven columns.
	for x in range(w):
		var moss := rng.randi_range(1, 4) + (2 if (x / 3) % 2 == 0 else 0)
		for y in range(h - moss, h):
			image.set_pixel(x, y, MOSS if y > h - moss else MOSS_DARK)
	# Grass tuft on the free end (row 0..1), overhanging a little.
	for x in range(w):
		image.set_pixel(x, 0, MOSS)
		image.set_pixel(x, 1, GRASS_HI if x % 3 != 1 else MOSS)
		if rng.randf() < 0.45:
			_put(image, x, 2, MOSS_DARK)
	_outline(image)
	if ceiling:
		image.flip_y()
	return image

## Steel spike filling the triangle (base at the attached end): left face lit,
## right face shaded, a glint near the tip, outlined.
static func make_spike(w: int, h: int, ceiling: bool) -> Image:
	var image := _blank(w, h)
	var half := float(w) * 0.5
	for y in range(h):
		# Row y = 0 is the tip; the base is at the bottom.
		var t := (float(y) + 0.5) / float(h)
		var reach := half * t
		for x in range(w):
			var dx := float(x) + 0.5 - half
			if absf(dx) > reach:
				continue
			var color := STEEL
			if dx < -reach * 0.25:
				color = STEEL_LIGHT
			elif dx > reach * 0.35:
				color = STEEL_DARK
			image.set_pixel(x, y, color)
	_put(image, int(half) - 1, int(h * 0.3), Color.WHITE)
	_outline(image)
	if ceiling:
		image.flip_y()
	return image

## The cut end of a log, square with side 2r: bark ring, two growth rings, a
## dark core and a crack, outlined. Optional thorns stick out of the bark.
static func make_log(r: int, thorns: bool) -> Image:
	var pad := 4 if thorns else 1
	var size := r * 2 + pad * 2
	var image := _blank(size, size)
	var c := float(size) * 0.5
	var rf := float(r)
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			if d > rf:
				continue
			var color := WOOD
			if d > rf - 2.5:
				color = BARK if (x + y) % 3 != 0 else BARK_DARK
			elif absf(d - rf * 0.62) < 0.7 or absf(d - rf * 0.32) < 0.7:
				color = WOOD_RING
			elif d < rf * 0.14 + 0.5:
				color = WOOD_CORE
			image.set_pixel(x, y, color)
	# A crack from the core outwards.
	for i in range(int(rf * 0.7)):
		_put(image, int(c) + i / 2, int(c) - i, WOOD_CORE)
	if thorns:
		for index in range(8):
			var angle := TAU * float(index) / 8.0 + 0.2
			var direction := Vector2.RIGHT.rotated(angle)
			for step in range(4):
				var p := Vector2(c, c) + direction * (rf + float(step))
				_put(image, int(p.x), int(p.y), THORN)
	_outline(image)
	return image

## A one-pixel dark outline around every opaque pixel, inside the image (the
## outermost opaque pixels become outline, so the size never grows).
static func _outline(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var edge: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if image.get_pixel(x, y).a < 0.5:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + n
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or image.get_pixel(q.x, q.y).a < 0.5:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		image.set_pixel(p.x, p.y, OUTLINE)

## A rounded boulder filling the box: lit from the top left, shaded bottom
## right, a few cracks and a moss cap, outlined.
static func make_boulder(w: int, h: int) -> Image:
	var image := _blank(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331 + w * 13 + h
	var c := Vector2(float(w), float(h)) * 0.5
	for y in range(h):
		for x in range(w):
			var p := (Vector2(float(x) + 0.5, float(y) + 0.5) - c) / c
			# A lumpy superellipse: flatter bottom, bumpy outline.
			var bump := 0.06 * sin(atan2(p.y, p.x) * 5.0 + 1.3)
			var d := pow(absf(p.x), 2.2) + pow(absf(p.y), 2.2)
			if d > 1.0 - bump:
				continue
			var light := -p.x * 0.5 - p.y * 0.7
			var color := STONE
			if light > 0.35:
				color = STONE_LIGHT
			elif light < -0.35:
				color = STONE_DARK
			if p.y < -0.55 + 0.1 * sin(p.x * 9.0):
				color = MOSS if p.y < -0.7 else MOSS_DARK
			image.set_pixel(x, y, color)
	for _i in range(2):
		var x := rng.randi_range(int(w * 0.3), int(w * 0.7))
		var y := rng.randi_range(int(h * 0.3), int(h * 0.5))
		for step in range(maxi(3, h / 5)):
			_put(image, x + (step % 2), y + step, STONE_DARK)
	_outline(image)
	return image
