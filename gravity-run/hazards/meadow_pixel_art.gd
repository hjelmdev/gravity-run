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
##   barrel  a barrel seen end-on (hoop, planks, bung), spiked or rubber

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
const WOOD := Color8(198, 124, 64)
const IRON := Color8(78, 84, 98)
const RUBBER := Color8(64, 183, 174)
const RUBBER_DULL := Color8(57, 124, 120)
const RUBBER_DARK := Color8(20, 63, 87)

static var _cache: Dictionary = {}

## A texture ready for drawing (nearest filtering), w x h world pixels.
static func block_texture(size: Vector2, ceiling: bool, variant: int) -> Texture2D:
	return _cached("block|%d|%d|%s|%d" % [int(size.x), int(size.y), str(ceiling), variant], func() -> Image: return make_block(_art(size.x), _art(size.y), ceiling, variant))

## A boulder filling w x h world pixels.
static func boulder_texture(size: Vector2) -> Texture2D:
	return _cached("boulder|%d|%d" % [int(size.x), int(size.y)], func() -> Image: return make_boulder(_art(size.x), _art(size.y)))

static func spike_texture(size: Vector2, ceiling: bool) -> Texture2D:
	return _cached("spike|%d|%d|%s" % [int(size.x), int(size.y), str(ceiling)], func() -> Image: return make_spike(_art(size.x), _art(size.y), ceiling))

## A square texture of a barrel seen end-on, `radius` world pixels; `kind` is
## "wood", "spiked", "rubber" or "retired".
static func barrel_texture(radius: float, kind: String) -> Texture2D:
	return _cached("barrel|%d|%s" % [int(radius), kind], func() -> Image: return make_barrel(_art(radius), kind))

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

## Rough stone pillar: stacked stones of uneven size, each with a lit top-left
## and a shaded bottom-right and its corners knocked off, jagged sides, a
## broken free end with a chipped chunk, a few cracks, moss creeping up from
## the attached end and patches on the sides, grass tufts on the broken top.
## Drawn for a floor block; a ceiling block is the same picture flipped.
static func make_block(w: int, h: int, ceiling: bool, variant: int) -> Image:
	var image := _blank(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4111 + w * 31 + h * 7 + variant * 1009
	# Silhouette: per-row side insets (jagged sides) and per-column top drop
	# (broken free end).
	var inset_left: Array[int] = []
	var inset_right: Array[int] = []
	var side_l := 0
	var side_r := 0
	for y in range(h):
		if y % 3 == 0:
			side_l = rng.randi_range(0, 2) if y > 2 else 1
			side_r = rng.randi_range(0, 2) if y > 2 else 1
		inset_left.append(side_l)
		inset_right.append(side_r)
	var top: Array[int] = []
	var drop := rng.randi_range(0, 2)
	for x in range(w):
		if x % 2 == 0:
			drop = clampi(drop + rng.randi_range(-1, 1), 0, 3)
		top.append(drop)
	# A chipped chunk out of one top corner.
	var chunk_w := rng.randi_range(3, maxi(3, w / 3))
	var chunk_h := rng.randi_range(3, 6)
	var chunk_left := rng.randf() < 0.5
	for x in range(chunk_w):
		var column := x if chunk_left else w - 1 - x
		top[column] = maxi(top[column], chunk_h - x / 2)
	# Stones: rows of uneven height, stones of uneven width, staggered.
	var y0 := 0
	var row := 0
	while y0 < h:
		var row_h := rng.randi_range(4, 7)
		var x0 := -rng.randi_range(0, 4) if row % 2 == 1 else 0
		while x0 < w:
			var stone_w := rng.randi_range(5, 10)
			var shade := rng.randf_range(-0.08, 0.08)
			for y in range(y0, mini(y0 + row_h, h)):
				for x in range(maxi(x0, 0), mini(x0 + stone_w, w)):
					var ry := y - y0
					var rx := x - x0
					var last_y := ry == row_h - 1
					var last_x := rx == stone_w - 1
					# Knocked-off corners between stones.
					if (rx == 0 or last_x) and (ry == 0 or last_y):
						image.set_pixel(x, y, MORTAR)
						continue
					var color := STONE
					if last_y or last_x:
						color = MORTAR
					elif ry == 0 or rx == 0:
						color = STONE_LIGHT
					elif ry == row_h - 2 or rx == stone_w - 2:
						color = STONE_DARK
					image.set_pixel(x, y, color.lightened(shade) if shade > 0.0 else color.darkened(-shade))
			x0 += stone_w
		y0 += row_h
		row += 1
	# Cracks: short diagonal runs.
	for _i in range(maxi(1, w * h / 260)):
		var cx := rng.randi_range(2, w - 3)
		var cy := rng.randi_range(4, h - 4)
		var dir := 1 if rng.randf() < 0.5 else -1
		for step in range(rng.randi_range(3, 6)):
			_put(image, cx + (step / 2) * dir, cy + step, MORTAR)
	# Moss from the attached end, and patches on the sides.
	for x in range(w):
		var moss := rng.randi_range(1, 4) + (2 if (x / 3) % 2 == 0 else 0)
		for y in range(h - moss, h):
			image.set_pixel(x, y, MOSS if y > h - moss else MOSS_DARK)
	for _i in range(maxi(1, h / 18)):
		var py := rng.randi_range(6, h - 8)
		var left_side := rng.randf() < 0.5
		for y in range(py, py + rng.randi_range(2, 4)):
			for x in range(rng.randi_range(2, 3)):
				_put(image, x if left_side else w - 1 - x, y, MOSS if x == 0 else MOSS_DARK)
	# Cut the silhouette.
	for y in range(h):
		for x in range(w):
			if x < inset_left[y] or x >= w - inset_right[y] or y < top[x]:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	# Grass tufts on the broken top.
	for x in range(w):
		if rng.randf() < 0.55:
			var t := top[x]
			if x >= inset_left[t] and x < w - inset_right[t]:
				_put(image, x, t, MOSS)
				if rng.randf() < 0.5:
					_put(image, x, t + 1, GRASS_HI)
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

## A barrel seen end-on, square with side 2r: an iron hoop round the rim,
## planks across the lid with dark seams, a bung, lit top-left and shaded
## bottom-right, outlined. "spiked" adds iron spikes out of the hoop,
## "rubber" is the teal rubber barrel with light stripes, "retired" its
## muted parked state.
static func make_barrel(r: int, kind: String) -> Image:
	var pad := 4 if kind == "spiked" else 1
	var size := r * 2 + pad * 2
	var image := _blank(size, size)
	var c := float(size) * 0.5
	var rf := float(r)
	var rubber := kind in ["rubber", "retired"]
	var lid := RUBBER if kind == "rubber" else (RUBBER_DULL if kind == "retired" else WOOD)
	var lid_light := lid.lightened(0.2)
	var lid_dark := lid.darkened(0.22)
	var hoop := RUBBER_DARK if rubber else IRON
	var plank := maxi(3, r / 3)
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c)
			var d := p.length()
			if d > rf:
				continue
			var color := lid
			if d > rf - 2.5:
				color = hoop if d > rf - 1.5 else hoop.lightened(0.25)
			elif rubber:
				color = lid_light if posmod(x - int(c) + r, plank * 2) < 2 else lid
			elif posmod(y - int(c) + r, plank) == 0:
				color = BARK_DARK
			if color == lid and (p.x + p.y) < -rf * 0.6:
				color = lid_light
			elif color == lid and (p.x + p.y) > rf * 0.7:
				color = lid_dark
			image.set_pixel(x, y, color)
	# The bung.
	if not rubber:
		_put(image, int(c) + r / 3, int(c) - 1, BARK_DARK)
		_put(image, int(c) + r / 3 + 1, int(c) - 1, BARK_DARK)
	if kind == "spiked":
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0 + 0.2)
			for step in range(4):
				var p := Vector2(c, c) + direction * (rf + float(step))
				_put(image, int(p.x), int(p.y), STEEL_LIGHT if step < 3 else STEEL)
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
