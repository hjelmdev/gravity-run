extends SceneTree
## Generates a biome's pixel-art ground in the runners' style (1 art pixel =
## 2 screen pixels, a dark outline, flat colours with one highlight and one
## shade step) from the biome's PixelPalette. Not part of the game.
##
##   godot --headless --path . -s res://tools/pixel_tiles/generate_biome_tiles.gd -- <biome_id>
##
## Writes (for biome_id "meadow"):
##   assets/biomes/meadow/meadow_surface.png  the grass cap atlas: VARIANTS tiles
##       of TILE_W x TILE_H art pixels side by side. The renderer stretches each
##       tile over one 64 x 40 world cell along the surface (and flips it for the
##       ceiling). Row RISE is the surface line; the rows above it are blade tips
##       that stick up past the surface, the rows below hang down into the dirt.
##   assets/biomes/meadow/meadow_dirt.png     a seamless dirt tile that fills the
##       ground under the grass cap (world-anchored, repeated).
## Everything is seeded, so running it again gives the same pictures.

const TILE_W := 32
const TILE_H := 20
## Art rows above the surface line (blade tips).
const RISE := 4
const VARIANTS := 8
const DIRT_SIZE := 64
## The palette the art is drawn with (set from the biome before drawing).
static var p: PixelPalette


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var biome_id := StringName(args[0] if not args.is_empty() else "meadow")
	var biome := BiomeRenderer.definition_for_id(biome_id)
	if biome == null or biome.biome_id != biome_id or biome.pixel_palette == null:
		push_error("Biome %s has no pixel_palette." % biome_id)
		quit(1)
		return
	p = biome.pixel_palette
	var out_dir := "res://assets/biomes/%s/" % biome_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var surface := Image.create(TILE_W * VARIANTS, TILE_H, false, Image.FORMAT_RGBA8)
	surface.fill(Color(0, 0, 0, 0))
	for variant in range(VARIANTS):
		draw_cap(surface, variant * TILE_W, variant)
	surface.save_png(out_dir + "%s_surface.png" % biome_id)
	var dirt := make_dirt()
	dirt.save_png(out_dir + "%s_dirt.png" % biome_id)
	print("wrote %s_surface.png (%dx%d) and %s_dirt.png (%dx%d)" % [biome_id, surface.get_width(), surface.get_height(), biome_id, DIRT_SIZE, DIRT_SIZE])
	quit(0)

## Seamless dirt: a base colour, soft darker clumps, light grains and a few
## outlined pebbles at random, well-spaced places. Everything wraps around.
static func make_dirt() -> Image:
	var image := Image.create(DIRT_SIZE, DIRT_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(p.fill)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7021 + p.seed_offset
	for _i in range(34):
		var cx := rng.randi_range(0, DIRT_SIZE - 1)
		var cy := rng.randi_range(0, DIRT_SIZE - 1)
		var w := rng.randi_range(2, 5)
		for dy in range(2):
			for dx in range(maxi(w - dy * 2, 1)):
				_wrap_put(image, cx + dx + dy, cy + dy, p.fill_shade)
	for _i in range(110):
		_wrap_put(image, rng.randi_range(0, DIRT_SIZE - 1), rng.randi_range(0, DIRT_SIZE - 1), p.fill_light if rng.randf() < 0.5 else p.fill_dark)
	var placed: Array[Vector2i] = []
	var tries := 0
	while placed.size() < p.pebble_count and tries < 400:
		tries += 1
		var at := Vector2i(rng.randi_range(0, DIRT_SIZE - 1), rng.randi_range(0, DIRT_SIZE - 1))
		var free := true
		for other in placed:
			var dx := absi(at.x - other.x)
			var dy := absi(at.y - other.y)
			dx = mini(dx, DIRT_SIZE - dx)
			dy = mini(dy, DIRT_SIZE - dy)
			if dx < 14 and dy < 12:
				free = false
				break
		if free:
			placed.append(at)
			_pebble(image, at, rng.randi_range(2, 4), rng.randi_range(2, 3))
	return image

static func _pebble(image: Image, at: Vector2i, w: int, h: int) -> void:
	for y in range(-1, h + 1):
		for x in range(-1, w + 1):
			if (x == -1 or x == w) and (y == -1 or y == h):
				continue
			var edge := x == -1 or x == w or y == -1 or y == h
			var color := p.fill_dark if edge else p.pebble
			if not edge and (x == 0 or y == 0):
				color = p.pebble_light
			elif not edge and (x == w - 1 or y == h - 1):
				color = p.pebble_dark
			_wrap_put(image, at.x + x, at.y + y, color)

static func _wrap_put(image: Image, x: int, y: int, color: Color) -> void:
	image.set_pixel(posmod(x, image.get_width()), posmod(y, image.get_height()), color)

static func _put(image: Image, left: int, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < TILE_W and y >= 0 and y < TILE_H:
		image.set_pixel(left + x, y, color)

## One grass cap. Above the surface line: outlined blade tips in small clumps.
## On it: the outline. Below it: a bright top, then grass that hangs into the
## dirt in uneven, outlined tufts. Below the grass the cap is see-through, so
## the world-anchored dirt fill shows. Variants add flowers and clover. Columns
## 0 and TILE_W-1 have the same depth in every variant, so tiles join cleanly.
static func draw_cap(image: Image, left: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + variant * 131 + p.seed_offset
	var s := RISE
	# Tuft depth per column below the surface line, a random walk in steps of 3
	# columns that starts and ends at the same depth.
	var depth: Array[int] = []
	var d := 6
	for x in range(TILE_W):
		if x == 0 or x == TILE_W - 1:
			d = 6
		elif x % 3 == 0:
			d = clampi(d + rng.randi_range(-2, 2), 4, 11)
		depth.append(d)
	for x in range(TILE_W):
		for y in range(s, TILE_H):
			var r := y - s
			var color := Color(0, 0, 0, 0)
			if r == 0 or r == depth[x]:
				color = p.ground_outline
			elif r < depth[x]:
				if r == 1:
					color = p.surface_hi
				elif r <= 3:
					color = p.surface
				elif r == depth[x] - 1:
					color = p.surface_dark
				else:
					color = p.surface_mid
			elif r == depth[x] + 1:
				color = Color(0.1, 0.05, 0.02, 0.3)
			_put(image, left, x, y, color)
	# Tuft sides: outline where neighbouring depths differ.
	for x in range(1, TILE_W):
		var a := depth[x - 1]
		var b := depth[x]
		if a != b:
			var column := x if b > a else x - 1
			for r in range(mini(a, b), maxi(a, b) + 1):
				_put(image, left, column, s + r, p.ground_outline)
	# Light strokes inside the grass.
	for _i in range(5 + variant % 3):
		var bx := rng.randi_range(1, TILE_W - 2)
		var length := rng.randi_range(1, 2)
		for r in range(2, mini(2 + length, depth[bx] - 1)):
			_put(image, left, bx, s + r, p.surface_hi)
	# Blade tips above the surface: clumps of 2-3 blades, 1 to RISE-1 pixels
	# tall, each outlined on its sides and top. Kept off the tile edges.
	var clumps := (3 + variant % 3) if p.blade_tips else 0
	for _c in range(clumps):
		var cx := rng.randi_range(2, TILE_W - 7)
		var blades := rng.randi_range(2, 3)
		for b in range(blades):
			var bx := cx + b * 2
			var height := rng.randi_range(1, RISE - 1)
			for h in range(1, height + 1):
				_put(image, left, bx, s - h, p.surface if h < height else p.surface_hi)
				if image.get_pixel(left + bx - 1, s - h).a < 0.5:
					_put(image, left, bx - 1, s - h, p.ground_outline)
				if image.get_pixel(left + bx + 1, s - h).a < 0.5:
					_put(image, left, bx + 1, s - h, p.ground_outline)
			_put(image, left, bx, s - height - 1, p.ground_outline)
			# The blade's foot replaces the surface outline with grass.
			_put(image, left, bx, s, p.surface)
	# Flowers: a stem above the surface and a plus-shaped bloom with an outline.
	var flowers: int = p.flower_counts[variant % p.flower_counts.size()] if not p.flower_counts.is_empty() else 0
	for _f in range(flowers):
		var fx := rng.randi_range(3, TILE_W - 4)
		var petal: Color = p.flower_colors[rng.randi_range(0, p.flower_colors.size() - 1)]
		var top := s - 2
		_put(image, left, fx, s, p.surface)
		for offset in [Vector2i(0, -2), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var q: Vector2i = Vector2i(fx, top) + offset
			if q.y >= 0 and q.y < s:
				_put(image, left, q.x, q.y, p.ground_outline)
		for offset in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var q: Vector2i = Vector2i(fx, top) + offset
			_put(image, left, q.x, q.y, petal)
		_put(image, left, fx, top, p.flower_center)
		_put(image, left, fx, s - 1, p.stem)
	# Clover on two variants: dark three-leaf marks in the grass.
	if p.clover and variant in [5, 6]:
		var cx := rng.randi_range(4, TILE_W - 5)
		for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var q: Vector2i = Vector2i(cx, 3) + offset
			if q.y < depth[q.x]:
				_put(image, left, q.x, s + q.y, p.surface_dark)
