extends RefCounted
class_name PixelHazardArt
## Pixel art for the hazards of every pixel-style biome, drawn in code at run
## time from the biome's PixelPalette, in the same style as the runners and the
## ground (tools/pixel_tiles): one art pixel is ART_SCALE world pixels, a dark
## outline, flat colours with one highlight and one shade. Hazards come in many
## sizes, so each picture is made for the hazard's exact size and palette and
## cached. Presentation only: hitboxes are the hazards' own.
##
##   block   a rough stone pillar, the palette's growth creeping over it
##   spike   a steel spike with a lit and a shaded face (or a stone cross,
##           an ice shard, a cactus: PixelPalette.spike_style)
##   saw     a circular saw blade
##   boulder a faceted rock with a cap of growth, for falling rocks
##   barrel  a barrel seen end-on (hoop, planks, bung), spiked or rubber (or
##           a snowball, a tumbleweed: PixelPalette.barrel_style)
##   icicle  a jagged icicle for the cave's falling ice
##   cart    a mine cart with an ore pile, and its spoked wheels

const ART_SCALE := 2.0

## The palette the picture being made is drawn with.
static var pal: PixelPalette

static var _cache: Dictionary = {}
static var _default_palette: PixelPalette

## The palette to draw with: the locked biome's, or the default (meadow) one.
static func palette() -> PixelPalette:
	var locked := BiomeRenderer.locked_pixel_palette()
	if locked != null:
		return locked
	if _default_palette == null:
		_default_palette = PixelPalette.new()
	return _default_palette

## A texture ready for drawing (nearest filtering), w x h world pixels.
static func block_texture(palette: PixelPalette, size: Vector2, ceiling: bool, variant: int) -> Texture2D:
	return _cached(palette, "block|%d|%d|%s|%d" % [int(size.x), int(size.y), str(ceiling), variant], func() -> Image: return make_grave(_art(size.x), _art(size.y), ceiling, variant) if palette.block_style == "grave" else make_block(_art(size.x), _art(size.y), ceiling, variant))

## A saw blade of `radius` world pixels (teeth reach past it), square texture.
static func saw_texture(palette: PixelPalette, radius: float) -> Texture2D:
	return _cached(palette, "saw|%d" % int(radius), func() -> Image: return make_saw(_art(radius)))

## A boulder filling w x h world pixels.
static func boulder_texture(palette: PixelPalette, size: Vector2) -> Texture2D:
	return _cached(palette, "boulder|%d|%d" % [int(size.x), int(size.y)], func() -> Image: return make_boulder(_art(size.x), _art(size.y)))

static func spike_texture(palette: PixelPalette, size: Vector2, ceiling: bool) -> Texture2D:
	return _cached(palette, "spike|%d|%d|%s" % [int(size.x), int(size.y), str(ceiling)], func() -> Image: return make_spike_styled(palette.spike_style, _art(size.x), _art(size.y), ceiling))

## An icicle filling w x h world pixels (wide end at the top).
static func icicle_texture(palette: PixelPalette, size: Vector2) -> Texture2D:
	return _cached(palette, "icicle|%d|%d" % [int(size.x), int(size.y)], func() -> Image: return make_icicle(_art(size.x), _art(size.y)))

## A mine cart (without wheels) in a square of side 2*radius + padding; "teal"
## is the rubber variant.
static func cart_texture(palette: PixelPalette, radius: float, teal: bool, spiked := false) -> Texture2D:
	return _cached(palette, "cart|%d|%s|%s" % [int(radius), str(teal), str(spiked)], func() -> Image: return make_cart(_art(radius), teal, spiked))

## A cart wheel of `radius` world pixels, square texture.
static func wheel_texture(palette: PixelPalette, radius: float) -> Texture2D:
	return _cached(palette, "wheel|%d" % int(radius), func() -> Image: return make_wheel(maxi(_art(radius), 3)))

## A square texture of a barrel seen end-on, `radius` world pixels; `kind` is
## "wood", "spiked", "rubber" or "retired".
static func barrel_texture(palette: PixelPalette, radius: float, kind: String) -> Texture2D:
	return _cached(palette, "barrel|%d|%s" % [int(radius), kind], func() -> Image: return make_barrel_styled(palette.barrel_style, _art(radius), kind))

static func _art(world: float) -> int:
	return maxi(int(round(world / ART_SCALE)), 2)

static func _cached(palette: PixelPalette, key: String, make: Callable) -> Texture2D:
	key = palette.cache_key() + "|" + key
	if not _cache.has(key):
		pal = palette
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
						image.set_pixel(x, y, pal.mortar)
						continue
					var color := pal.stone
					if last_y or last_x:
						color = pal.mortar
					elif ry == 0 or rx == 0:
						color = pal.stone_light
					elif ry == row_h - 2 or rx == stone_w - 2:
						color = pal.stone_dark
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
			_put(image, cx + (step / 2) * dir, cy + step, pal.mortar)
	# Moss from the attached end, and patches on the sides.
	for x in range(w):
		var moss := rng.randi_range(1, 4) + (2 if (x / 3) % 2 == 0 else 0)
		for y in range(h - moss, h):
			image.set_pixel(x, y, pal.growth if y > h - moss else pal.growth_dark)
	for _i in range(maxi(1, h / 18)):
		var py := rng.randi_range(6, h - 8)
		var left_side := rng.randf() < 0.5
		for y in range(py, py + rng.randi_range(2, 4)):
			for x in range(rng.randi_range(2, 3)):
				_put(image, x if left_side else w - 1 - x, y, pal.growth if x == 0 else pal.growth_dark)
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
				_put(image, x, t, pal.growth)
				if rng.randf() < 0.5:
					_put(image, x, t + 1, pal.surface_hi)
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
			var color := pal.steel
			if dx < -reach * 0.25:
				color = pal.steel_light
			elif dx > reach * 0.35:
				color = pal.steel_dark
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
	var lid := pal.rubber if kind == "rubber" else (pal.rubber_dull if kind == "retired" else pal.wood)
	var lid_light := lid.lightened(0.2)
	var lid_dark := lid.darkened(0.22)
	var hoop := pal.rubber_dark if rubber else pal.iron
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
				color = pal.wood_dark
			if color == lid and (p.x + p.y) < -rf * 0.6:
				color = lid_light
			elif color == lid and (p.x + p.y) > rf * 0.7:
				color = lid_dark
			image.set_pixel(x, y, color)
	# The bung.
	if not rubber:
		_put(image, int(c) + r / 3, int(c) - 1, pal.wood_dark)
		_put(image, int(c) + r / 3 + 1, int(c) - 1, pal.wood_dark)
	if kind == "spiked":
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0 + 0.2)
			for step in range(4):
				var p := Vector2(c, c) + direction * (rf + float(step))
				_put(image, int(p.x), int(p.y), pal.steel_light if step < 3 else pal.steel)
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
		image.set_pixel(p.x, p.y, pal.hazard_outline)

## A chunky, faceted rock filling the box: an irregular polygon outline, each
## facet (a wedge from an off-centre ridge point to one edge) flat-shaded by
## how much it faces the light from the top left, darker ridge lines between
## facets, a small moss clump and a crack; outlined. It reads as a rock from
## any side, hanging in the ceiling or lying on the floor.
static func make_boulder(w: int, h: int) -> Image:
	var image := _blank(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331 + w * 13 + h
	var c := Vector2(float(w), float(h)) * 0.5
	var corners := 9
	var outline := PackedVector2Array()
	for i in range(corners):
		var angle := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(corners) - PI * 0.5
		var reach := rng.randf_range(0.8, 1.0)
		outline.append(c + Vector2(cos(angle) * (c.x - 1.0), sin(angle) * (c.y - 1.0)) * reach)
	var ridge := c + Vector2(-0.12 * c.x, -0.18 * c.y)
	var light := Vector2(-0.6, -0.8).normalized()
	var tones := [pal.stone_dark.darkened(0.15), pal.stone_dark, pal.stone, pal.stone_light]
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if not Geometry2D.is_point_in_polygon(p, outline):
				continue
			# The facet: the edge whose wedge (ridge, a, b) holds the pixel.
			var tone := 2
			for i in range(corners):
				var a := outline[i]
				var b := outline[(i + 1) % corners]
				if Geometry2D.point_is_inside_triangle(p, ridge, a, b):
					var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
					var facing := normal.dot(light)
					tone = 3 if facing > 0.45 else (2 if facing > -0.1 else (1 if facing > -0.6 else 0))
					break
			image.set_pixel(x, y, tones[tone])
	# Ridge lines to a few corners only (all of them read as an umbrella).
	for index in [1, 4, 6]:
		var corner := outline[index]
		var steps := int(ridge.distance_to(corner))
		for s in range(steps):
			var q := ridge.lerp(corner, float(s) / float(maxi(steps, 1)))
			var current := image.get_pixel(int(q.x), int(q.y))
			if current.a > 0.5:
				image.set_pixel(int(q.x), int(q.y), current.darkened(0.12))
	# A crack down one lit facet.
	var crack := ridge + Vector2(c.x * 0.25, -c.y * 0.1)
	for s in range(maxi(3, h / 4)):
		_put(image, int(crack.x) + (s / 2) % 2, int(crack.y) + s, pal.stone_dark.darkened(0.2))
	# A moss cap over the top quarter, hanging down in uneven drips, with a lit
	# upper rim: the side that was stuck in the ceiling grass.
	for x in range(w):
		var drip := int(float(h) * 0.24) + (2 if (x / 3) % 2 == 0 else 0) + rng.randi_range(-1, 1)
		for y in range(drip):
			if image.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, pal.growth_dark if y >= drip - 1 else (pal.surface_hi if y < int(float(h) * 0.08) else pal.growth))
	_outline(image)
	return image

## Side of the saw texture in art pixels for a blade of radius r (teeth reach
## SAW_TOOTH_REACH past r).
const SAW_TOOTH_REACH := 1.14
static func saw_side(r: int) -> int:
	return int(ceil(float(r) * SAW_TOOTH_REACH)) * 2 + 2

## A circular saw: ten raked teeth, a bright rim, a darker inner disc with
## three lightening holes, a hub with an axle bolt; lit from the top left,
## outlined.
static func make_saw(r: int) -> Image:
	var side := saw_side(r)
	var image := _blank(side, side)
	var c := float(side) * 0.5
	var rf := float(r)
	var teeth := 10
	for y in range(side):
		for x in range(side):
			var p := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c)
			var d := p.length()
			var angle := fposmod(atan2(p.y, p.x), TAU)
			var tooth := fposmod(angle * float(teeth) / TAU, 1.0)
			# Raked tooth: the edge climbs slowly and drops sharply.
			var edge := rf * (0.9 + (SAW_TOOTH_REACH - 0.9) * tooth)
			if d > edge:
				continue
			var light := (-p.x - p.y) / (rf * 1.4)
			var color := pal.steel
			if d > rf * 0.84:
				color = pal.steel_light if light > -0.2 else pal.steel
			elif d > rf * 0.78:
				color = pal.steel_dark
			elif d > rf * 0.3:
				color = pal.steel.darkened(0.12) if light < 0.25 else pal.steel
				# Lightening holes.
				for hole in range(3):
					var at := Vector2.from_angle(TAU * float(hole) / 3.0 + 0.5) * rf * 0.54
					if p.distance_to(at) < rf * 0.13:
						color = Color(0, 0, 0, 0)
			elif d > rf * 0.16:
				color = pal.iron
			else:
				color = pal.axle
			image.set_pixel(x, y, color)
	_outline(image)
	return image

## A mine cart filling the barrel's circle (radius r, square side 2r + 2): a
## tapered body of planks with an iron rim, an ore pile heaped above it, lit
## top-left, outlined. The wheels are separate pictures so they can turn.
static func make_cart(r: int, teal: bool, spiked := false) -> Image:
	# A spiked cart gets room for steel spikes sticking out of its front and back.
	var side := r * 2 + 2 + (14 if spiked else 0)
	var image := _blank(side, side)
	var c := float(side) * 0.5
	var rf := float(r)
	var body := pal.rubber if teal else pal.wood.darkened(0.15)
	var body_light := body.lightened(0.2)
	var body_dark := body.darkened(0.25)
	var rim := pal.rubber_dark if teal else pal.iron
	var ore := pal.stone if teal else Color8(214, 172, 74)
	var ore_light := ore.lightened(0.3)
	var top := int(c - rf * 0.38)
	var bottom := int(c + rf - rf * 0.42)
	# Ore pile: a bumpy mound above the rim.
	for x in range(side):
		var u := (float(x) + 0.5 - c) / (rf * 0.8)
		if absf(u) > 1.0:
			continue
		var height := int(rf * (0.34 * (1.0 - u * u)) + 2.0 * sin(float(x) * 1.7))
		for y in range(top - height, top):
			_put(image, x, y, ore_light if (x + y) % 5 == 0 else ore)
	# Body: tapered rows.
	for y in range(top, bottom + 1):
		var t := float(y - top) / float(maxi(bottom - top, 1))
		var half := rf * lerpf(0.92, 0.68, t)
		for x in range(side):
			var dx := float(x) + 0.5 - c
			if absf(dx) > half:
				continue
			var color := body
			if y - top <= 1:
				color = rim
			elif int(dx + rf) % maxi(int(rf * 0.5), 3) == 0:
				color = body_dark
			elif dx < -half * 0.5:
				color = body_light
			image.set_pixel(x, y, color)
	if spiked:
		# Two big spikes out of each end wall, pointing forwards and backwards.
		for row in [top + 3, bottom - 2]:
			var half_here := rf * lerpf(0.92, 0.68, float(row - top) / float(maxi(bottom - top, 1)))
			for dir in [-1, 1]:
				var base_x := int(c + float(dir) * half_here)
				for k in range(7):
					var spread := 3 - k / 2
					for dy in range(-spread, spread + 1):
						_put(image, base_x + dir * (k + 1), row + dy, pal.steel_light if dy < 0 else pal.steel)
	_outline(image)
	return image

## A spoked wheel of radius r art pixels (square side 2r + 2): iron tyre, a
## lighter hub and two crossed spokes, outlined.
static func make_wheel(r: int) -> Image:
	var side := r * 2 + 2
	var image := _blank(side, side)
	var c := float(side) * 0.5
	var rf := float(r)
	for y in range(side):
		for x in range(side):
			var p := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c)
			var d := p.length()
			if d > rf:
				continue
			var color := pal.iron
			if d < rf * 0.4:
				color = pal.steel_light
			elif absf(p.x) < 1.0 or absf(p.y) < 1.0:
				color = pal.steel
			elif d < rf - 1.5:
				color = Color(0, 0, 0, 0)
			image.set_pixel(x, y, color)
	_outline(image)
	return image

## An icicle: the vector icicle's jagged outline (wide at the top, a point at
## the bottom), a lit left face and a shaded right face, a light streak and a
## dark crack, outlined.
static func make_icicle(w: int, h: int) -> Image:
	var image := _blank(w, h)
	var s := Vector2(float(w), float(h))
	var outline := PackedVector2Array([
		Vector2(s.x * 0.08, 0.0), Vector2(s.x * 0.92, 0.0), Vector2(s.x * 0.83, s.y * 0.48),
		Vector2(s.x * 0.68, s.y * 0.66), Vector2(s.x * 0.53, s.y * 0.91), Vector2(s.x * 0.47, s.y),
		Vector2(s.x * 0.39, s.y * 0.91), Vector2(s.x * 0.28, s.y * 0.67), Vector2(s.x * 0.15, s.y * 0.49),
	])
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if not Geometry2D.is_point_in_polygon(p, outline):
				continue
			var color := pal.ice
			if p.x < s.x * 0.36:
				color = pal.ice_light
			elif p.x > s.x * 0.62:
				color = pal.ice_dark
			image.set_pixel(x, y, color)
	for step in range(int(s.y * 0.35)):
		_put(image, int(s.x * 0.3) + step / 3, int(s.y * 0.12) + step, pal.ice_dark)
	for step in range(int(s.y * 0.3)):
		_put(image, int(s.x * 0.55) + step / 4, int(s.y * 0.1) + step, Color.WHITE)
	_outline(image)
	return image

## A headstone filling the block: an arched top on the free end, stone shaded
## from the top left, an engraved cross, moss at the foot and a crack,
## outlined. Drawn for a floor block; a ceiling block is flipped.
static func make_grave(w: int, h: int, ceiling: bool, variant: int) -> Image:
	var image := _blank(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113 + w * 17 + h * 5 + variant * 211
	var arch := mini(w / 2, maxi(h / 3, 3))
	var cx := float(w) * 0.5
	for y in range(h):
		for x in range(w):
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			if fy < float(arch):
				var dy := float(arch) - fy
				if Vector2(fx - cx, dy).length() > cx:
					continue
			var color := pal.stone
			if x <= 1 or y <= 1:
				color = pal.stone_light
			elif x >= w - 2:
				color = pal.stone_dark
			image.set_pixel(x, y, color)
	# Engraved cross in the upper half.
	var top := arch + 2
	var bar := top + maxi(h / 8, 2)
	for y in range(top, mini(top + maxi(h / 3, 6), h - 3)):
		_put(image, int(cx), y, pal.mortar)
	for x in range(int(cx) - maxi(w / 6, 2), int(cx) + maxi(w / 6, 2) + 1):
		_put(image, x, bar, pal.mortar)
	# A crack and moss at the foot.
	var crack_x := rng.randi_range(2, w - 3)
	for step in range(maxi(3, h / 6)):
		_put(image, crack_x + (step / 2) % 2, h / 2 + step, pal.stone_dark)
	for x in range(w):
		var moss := rng.randi_range(1, 3)
		for y in range(h - moss, h):
			if image.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, pal.growth if y > h - moss else pal.growth_dark)
	_outline(image)
	if ceiling:
		image.flip_y()
	return image

## A stone cross-spear filling the triangle: a spike of weathered stone (lit
## left face, shaded right) with a crossbar halfway up, outlined.
static func make_cross(w: int, h: int, ceiling: bool) -> Image:
	var image := _blank(w, h)
	var half := float(w) * 0.5
	for y in range(h):
		var t := (float(y) + 0.5) / float(h)
		var reach := half * t
		for x in range(w):
			var dx := float(x) + 0.5 - half
			if absf(dx) > reach:
				continue
			var color := pal.stone
			if dx < -reach * 0.25:
				color = pal.stone_light
			elif dx > reach * 0.35:
				color = pal.stone_dark
			image.set_pixel(x, y, color)
	var bar_y := int(float(h) * 0.5)
	for x in range(int(half * 0.35), int(float(w) - half * 0.35)):
		_put(image, x, bar_y, pal.mortar)
		_put(image, x, bar_y + 1, pal.stone_dark)
	_outline(image)
	if ceiling:
		image.flip_y()
	return image

## A spike in the palette's spike_style ("steel", "cross", "ice", "cactus").
static func make_spike_styled(style: String, w: int, h: int, ceiling: bool) -> Image:
	match style:
		"cross": return make_cross(w, h, ceiling)
		"ice": return make_ice_spike(w, h, ceiling)
		"cactus": return make_cactus(w, h, ceiling)
	return make_spike(w, h, ceiling)

## A barrel in the palette's barrel_style. Rubber barrels keep their own look
## everywhere (they bounce, so they must read as rubber).
static func make_barrel_styled(style: String, r: int, kind: String) -> Image:
	if kind in ["wood", "spiked"]:
		match style:
			"snowball": return make_snowball(r, kind == "spiked")
			"tumbleweed": return make_tumbleweed(r, kind == "spiked")
	return make_barrel(r, kind)

## An ice shard filling the triangle: a tall main shard with a lit left face,
## a shaded right face and a bright ridge, a shorter shard leaning on each
## side, white glints; outlined.
static func make_ice_spike(w: int, h: int, ceiling: bool) -> Image:
	var image := _blank(w, h)
	var half := float(w) * 0.5
	var shards := [Vector3(half, 0.0, half * 0.62), Vector3(half * 0.55, float(h) * 0.38, half * 0.5), Vector3(half * 1.45, float(h) * 0.3, half * 0.5)]
	for shard in shards:
		var cx: float = shard.x
		var top: float = shard.y
		var base_half: float = shard.z
		for y in range(int(top), h):
			var t := (float(y) + 0.5 - top) / maxf(float(h) - top, 1.0)
			var reach := base_half * t
			for x in range(w):
				var dx := float(x) + 0.5 - cx
				if absf(dx) > reach:
					continue
				# The whole spike must stay inside the hazard's triangle.
				if absf(float(x) + 0.5 - half) > half * (float(y) + 0.5) / float(h) + 0.5:
					continue
				var color := pal.ice
				if dx < -reach * 0.15:
					color = pal.ice_light
				elif dx > reach * 0.4:
					color = pal.ice_dark
				if absf(dx) < 0.6 and t < 0.7:
					color = Color.WHITE
				image.set_pixel(x, y, color)
	_put(image, int(half) - 2, int(h * 0.55), Color.WHITE)
	_put(image, int(half * 0.5), int(h * 0.8), Color.WHITE)
	_outline(image)
	if ceiling:
		image.flip_y()
	return image

## A spiny cactus in the spike's place: a rounded column with two arms, ribs
## of light and dark green, pale spines along the edges; outlined. Drawn in
## the palette's tree colours, like the cacti of the backdrop.
static func make_cactus(w: int, h: int, ceiling: bool) -> Image:
	var image := _blank(w, h)
	var cx := float(w) * 0.5
	var col := maxf(float(w) * 0.17, 2.0)
	var arm := maxf(float(w) * 0.09, 1.5)
	var body: Array[Rect2] = [
		Rect2(cx - col, float(h) * 0.06, col * 2.0, float(h)),
		Rect2(float(w) * 0.16, float(h) * 0.56, cx - float(w) * 0.16, arm * 2.0),
		Rect2(float(w) * 0.16, float(h) * 0.34, arm * 2.0, float(h) * 0.22 + arm * 2.0),
		Rect2(cx, float(h) * 0.66, float(w) * 0.84 - cx, arm * 2.0),
		Rect2(float(w) * 0.84 - arm * 2.0, float(h) * 0.44, arm * 2.0, float(h) * 0.22 + arm * 2.0),
	]
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var inside := false
			for rect in body:
				if rect.has_point(p):
					inside = true
					break
			# A round top on the column.
			if inside and p.y < float(h) * 0.06 + col and Vector2(p.x - cx, p.y - (float(h) * 0.06 + col)).length() > col:
				inside = false
			if not inside:
				continue
			var color := pal.tree_canopy
			var rib := posmod(x - int(cx), 3)
			if rib == 0:
				color = pal.tree_canopy.darkened(0.25)
			elif p.x < cx - col * 0.4 and absf(p.x - cx) <= col:
				color = pal.tree_light
			image.set_pixel(x, y, color)
	_outline(image)
	# Spines just outside the outline, every few pixels.
	for y in range(2, h, 3):
		for x in range(w):
			if image.get_pixel(x, y).a > 0.5 and x > 0 and image.get_pixel(x - 1, y).a < 0.5:
				_put(image, x - 1, y, pal.steel_light)
				break
		for x in range(w - 1, -1, -1):
			if image.get_pixel(x, y).a > 0.5 and x < w - 1 and image.get_pixel(x + 1, y).a < 0.5:
				_put(image, x + 1, y, pal.steel_light)
				break
	if ceiling:
		image.flip_y()
	return image

## A rolling snowball, square with side 2r: packed snow lit from the top left
## with a blue shade, a few clumps and grit stuck in it; "spiked" has ice
## shards frozen into it.
static func make_snowball(r: int, spiked: bool) -> Image:
	var pad := 4 if spiked else 1
	var size := r * 2 + pad * 2
	var image := _blank(size, size)
	var c := float(size) * 0.5
	var rf := float(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5101 + r
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c)
			var d := p.length()
			if d > rf:
				continue
			var color := pal.ice_light
			var light := (p.x + p.y) / rf
			if light < -0.7:
				color = Color.WHITE
			elif light > 0.55:
				color = pal.ice_dark
			elif light > 0.1:
				color = pal.ice
			image.set_pixel(x, y, color)
	# Clumps (a lighter and a shaded pixel) and grit.
	for index in range(maxi(3, r / 2)):
		var p := Vector2(c, c) + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.2, 0.75) * rf
		_put(image, int(p.x), int(p.y), pal.ice_dark if index % 3 == 0 else Color.WHITE)
		_put(image, int(p.x) + 1, int(p.y) + 1, pal.ice)
		if index % 4 == 1:
			_put(image, int(p.x) - 1, int(p.y), pal.pebble_dark)
	if spiked:
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0 + 0.2)
			for step in range(4):
				var p := Vector2(c, c) + direction * (rf + float(step) - 1.0)
				_put(image, int(p.x), int(p.y), pal.ice_light if step < 2 else pal.ice_dark)
	_outline(image)
	return image

## A tumbleweed, square with side 2r: a ball of tangled dry twigs (loops of
## light and dark straw with gaps you can see through); "spiked" has thorns.
static func make_tumbleweed(r: int, spiked: bool) -> Image:
	var pad := 4 if spiked else 1
	var size := r * 2 + pad * 2
	var image := _blank(size, size)
	var c := Vector2(float(size), float(size)) * 0.5
	var rf := float(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7703 + r
	var straw := pal.wood.lightened(0.25)
	# Loops: arcs of random circles inside the ball.
	for loop in range(10 + r / 2):
		var centre := c + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.0, 0.45) * rf
		var radius := rng.randf_range(0.35, 0.6) * rf
		var start := rng.randf() * TAU
		var color := straw if loop % 3 != 0 else pal.wood_dark
		for s in range(int(radius * 5.0)):
			var p := centre + Vector2.RIGHT.rotated(start + float(s) / (radius * 5.0) * PI * 1.4) * radius
			if p.distance_to(c) <= rf - 0.5:
				_put(image, int(p.x), int(p.y), color)
	# A rim so the ball reads as round.
	for s in range(int(rf * 7.0)):
		var p := c + Vector2.RIGHT.rotated(float(s) / (rf * 7.0) * TAU) * (rf - 1.0)
		if s % 5 != 0:
			_put(image, int(p.x), int(p.y), pal.wood if s % 3 else straw)
	if spiked:
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0 + 0.2)
			for step in range(4):
				var p := c + direction * (rf + float(step) - 1.0)
				_put(image, int(p.x), int(p.y), pal.steel_light if step < 3 else pal.steel)
	# No outline: the twigs are thin, an outline would turn them all dark.
	return image
