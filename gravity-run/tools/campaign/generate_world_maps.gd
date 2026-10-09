extends SceneTree
## Paints the campaign world map backgrounds (320x180 pixel art).
## GDScript port of generate_world_maps.py (no Python needed).
##
##   godot --headless --path . -s tools/campaign/generate_world_maps.gd -- [theme ...] [--out=res://assets/campaign]
##
## Theme names: meadow cave haunted volcano frost clouds desert (or the full
## map_* name). With no theme the three newest maps are written (frost, clouds,
## desert); the four original maps are only rewritten when named explicitly.
## Node positions must match campaign/campaign_catalog.gd (*_MAP_NODES).

const W := 320
const H := 180
const OUTLINE := Color8(20, 20, 28)
const DEFAULT_THEMES := ["map_frost", "map_clouds", "map_desert"]

var img: Image
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var out_dir := "res://assets/campaign"
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		else:
			names.append(a if a.begins_with("map_") else "map_" + a)
	if names.is_empty():
		names = DEFAULT_THEMES
	var themes := _themes()
	for n in names:
		if not themes.has(n):
			printerr("unknown theme: ", n)
			continue
		var path := render(n, themes[n], out_dir)
		print(path)
	quit()


func c(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)


func _themes() -> Dictionary:
	return {
		"map_meadow": {
			"nodes": [Vector2(38, 138), Vector2(78, 112), Vector2(118, 134), Vector2(158, 100), Vector2(200, 122), Vector2(238, 92), Vector2(286, 66)],
			"ground": [c(96, 168, 82), c(88, 158, 76), c(104, 176, 88)], "ground_dark": c(70, 132, 66),
			"sky": c(140, 200, 236), "horizon": [c(78, 140, 92), c(70, 128, 84)], "horizon_line": c(60, 112, 72),
			"path": c(226, 196, 140), "path_dark": c(176, 142, 96), "path_light": c(240, 218, 170),
			"water": [c(64, 152, 214), c(40, 110, 170), c(130, 200, 240)],
			"river": [Vector2(250, 0), Vector2(232, 40), Vector2(262, 80), Vector2(248, 120), Vector2(276, 180)], "bridge": c(150, 104, 66),
			"props": "trees", "sparkles": [c(250, 246, 220), c(255, 214, 92), c(238, 132, 168), c(180, 160, 240)],
		},
		"map_cave": {
			"nodes": [Vector2(34, 70), Vector2(74, 98), Vector2(116, 74), Vector2(156, 110), Vector2(196, 84), Vector2(238, 118), Vector2(284, 92)],
			"ground": [c(74, 78, 96), c(68, 72, 90), c(80, 86, 104)], "ground_dark": c(56, 60, 76),
			"sky": c(30, 30, 42), "horizon": [c(46, 48, 62), c(40, 42, 56)], "horizon_line": c(24, 24, 34),
			"path": c(150, 140, 120), "path_dark": c(104, 96, 84), "path_light": c(176, 168, 150),
			"water": [c(48, 110, 160), c(30, 76, 120), c(110, 180, 220)],
			"lake": [70, 150, 34, 18], "bridge": c(110, 80, 60),
			"props": "crystals", "sparkles": [c(120, 220, 255), c(200, 160, 255), c(160, 255, 220)],
		},
		"map_haunted": {
			"nodes": [Vector2(36, 120), Vector2(78, 92), Vector2(118, 124), Vector2(160, 96), Vector2(202, 130), Vector2(242, 100), Vector2(286, 74)],
			"ground": [c(58, 72, 70), c(52, 64, 64), c(64, 80, 76)], "ground_dark": c(42, 52, 54),
			"sky": c(46, 40, 78), "horizon": [c(36, 44, 58), c(30, 38, 50)], "horizon_line": c(22, 26, 36),
			"path": c(150, 136, 122), "path_dark": c(104, 92, 84), "path_light": c(176, 164, 150),
			"water": [c(70, 90, 110), c(50, 64, 84), c(120, 150, 170)],
			"river": [Vector2(120, 180), Vector2(110, 160), Vector2(96, 150)], "bridge": c(90, 70, 60),
			"props": "graves", "sparkles": [c(170, 255, 200), c(200, 180, 255)], "moon": [262, 22],
		},
		"map_volcano": {
			"nodes": [Vector2(36, 96), Vector2(76, 128), Vector2(118, 100), Vector2(158, 132), Vector2(200, 104), Vector2(240, 134), Vector2(286, 104)],
			"ground": [c(72, 54, 52), c(64, 48, 48), c(80, 60, 56)], "ground_dark": c(50, 38, 40),
			"sky": c(120, 52, 44), "horizon": [c(60, 36, 36), c(52, 32, 34)], "horizon_line": c(34, 22, 26),
			"path": c(140, 120, 104), "path_dark": c(96, 80, 72), "path_light": c(168, 150, 132),
			"water": [c(255, 120, 40), c(200, 60, 30), c(255, 210, 90)],
			"river": [Vector2(176, 0), Vector2(186, 40), Vector2(172, 80), Vector2(184, 118), Vector2(176, 180)], "bridge": c(90, 90, 100),
			"props": "rocks", "sparkles": [c(255, 170, 60), c(255, 220, 120)], "volcano": [60, 30],
		},
		# Frost Mountain: snowfield, jagged pale peaks, a frozen lake, pines.
		"map_frost": {
			"nodes": [Vector2(34, 126), Vector2(76, 100), Vector2(118, 128), Vector2(160, 96), Vector2(202, 124), Vector2(244, 94), Vector2(286, 70)],
			"ground": [c(226, 236, 246), c(214, 228, 242), c(240, 247, 253)], "ground_dark": c(172, 198, 228),
			"sky": c(190, 220, 242), "sky_grad": [c(150, 190, 228), c(214, 234, 250)],
			"horizon": [c(150, 178, 210), c(128, 158, 196)], "horizon_line": c(88, 114, 156),
			"peaks": true, "snowcap": c(246, 250, 255),
			"path": c(204, 178, 142), "path_dark": c(132, 108, 92), "path_light": c(228, 210, 178),
			"water": [c(150, 210, 238), c(88, 152, 204), c(238, 250, 255)],
			"lake": [250, 158, 44, 15], "bridge": c(120, 92, 70),
			"props": "frost", "sparkles": [c(255, 255, 255), c(170, 220, 255), c(130, 190, 245)],
		},
		# Cloud Realm: sunset sky, cloud tops as ground, floating grass islands.
		"map_clouds": {
			"nodes": [Vector2(36, 90), Vector2(78, 118), Vector2(120, 88), Vector2(162, 116), Vector2(204, 86), Vector2(246, 112), Vector2(286, 80)],
			"ground": [c(248, 242, 252), c(238, 230, 248), c(255, 250, 255)], "ground_dark": c(204, 188, 232),
			"sky": c(210, 130, 170), "sky_grad": [c(96, 76, 160), c(190, 100, 170), c(246, 138, 130), c(255, 190, 110)],
			"horizon": [c(246, 196, 206), c(232, 176, 204)], "horizon_line": c(176, 128, 192),
			"base": 46, "amp": 1.6, "min_y": 56, "sun": [64, 24, 11], "rainbow": [228, 70],
			"path": c(252, 222, 140), "path_dark": c(228, 178, 112), "path_light": c(255, 242, 196),
			"water": [], "bridge": c(214, 156, 96),
			"props": "islands", "sparkles": [c(255, 236, 150), c(255, 190, 220), c(255, 255, 255), c(190, 170, 250)],
		},
		# Desert: dunes, pale hot sky and a big sun, oasis pond with palms.
		"map_desert": {
			"nodes": [Vector2(36, 110), Vector2(78, 132), Vector2(120, 104), Vector2(162, 130), Vector2(204, 100), Vector2(246, 126), Vector2(286, 96)],
			"ground": [c(238, 208, 128), c(230, 196, 112), c(246, 220, 142)], "ground_dark": c(208, 166, 88),
			"sky": c(252, 234, 192), "sky_grad": [c(255, 214, 150), c(255, 244, 214)],
			"horizon": [c(226, 182, 104), c(212, 166, 92)], "horizon_line": c(170, 126, 70),
			"base": 20, "amp": 1.5, "sun": [252, 20, 12], "ridges": true,
			"path": c(246, 234, 190), "path_dark": c(168, 122, 74), "path_light": c(255, 248, 220),
			"water": [c(70, 176, 182), c(34, 118, 136), c(170, 232, 226)],
			"lake": [64, 156, 26, 11], "lake_shore": c(104, 168, 80), "bridge": c(130, 92, 56),
			"palms": [Vector2(40, 150), Vector2(88, 146), Vector2(78, 168)],
			"props": "desert", "sparkles": [c(255, 250, 220), c(255, 196, 96), c(250, 160, 80)],
		},
	}


func catmull(points: Array, steps: int = 40) -> Array:
	var out: Array = []
	var pts: Array = [points[0]] + points + [points[-1]]
	for i in range(1, pts.size() - 2):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[i + 2]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			var x := 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
			var y := 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
			out.append(Vector2(x, y))
	out.append(points[-1])
	return out


func put(x: float, y: float, color: Color) -> void:
	var xi := int(x)
	var yi := int(y)
	if xi >= 0 and xi < W and yi >= 0 and yi < H:
		img.set_pixel(xi, yi, color)


func at(x: float, y: float) -> Color:
	return img.get_pixel(clampi(int(x), 0, W - 1), clampi(int(y), 0, H - 1))


func disc(cx: float, cy: float, r: float, color: Color) -> void:
	for y in range(int(cy - r - 1), int(cy + r + 2)):
		for x in range(int(cx - r - 1), int(cx + r + 2)):
			if (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy) <= r * r:
				put(x, y, color)


func darker(col: Color, amount: int) -> Color:
	return Color8(maxi(0, col.r8 - amount), maxi(0, col.g8 - amount), maxi(0, col.b8 - amount))


func horizon_top(theme: Dictionary, x: int) -> int:
	var base: float = theme.get("base", 18)
	var amp: float = theme.get("amp", 1.0)
	if theme.get("peaks", false):
		# Jagged peaks: triangle waves instead of rolling hills.
		var tri := absf(fposmod(x / 31.0, 1.0) * 2.0 - 1.0)
		var tri2 := absf(fposmod(x / 13.0 + 0.4, 1.0) * 2.0 - 1.0)
		return int(base + 4 + tri * 14.0 + tri2 * 3.0)
	return int(base + amp * 7 * sin(x / 23.0) + amp * 4 * sin(x / 9.0 + 1.3))


func sky_color(theme: Dictionary, y: int, top: int) -> Color:
	if not theme.has("sky_grad"):
		return theme["sky"]
	var stops: Array = theme["sky_grad"]
	var f := clampf(float(y) / maxf(1.0, top - 10.0), 0.0, 1.0) * (stops.size() - 1)
	var i := mini(int(f), stops.size() - 2)
	var col: Color = (stops[i] as Color).lerp(stops[i + 1], f - i)
	# Ordered dither between bands keeps the pixel-art look.
	return col


func paint_ground(theme: Dictionary) -> void:
	var g: Array = theme["ground"]
	for y in H:
		for x in W:
			var n := (x * 7 + y * 13 + (x * y) % 5) % 9
			img.set_pixel(x, y, g[0] if n < 6 else g[1] if n < 8 else g[2])
	var min_y: int = theme.get("min_y", 20)
	for _i in 26:
		var cx := rng.randi_range(0, W)
		var cy := rng.randi_range(min_y, H)
		var r := rng.randi_range(5, 14)
		for y in range(cy - r, cy + r):
			for x in range(cx - r * 2, cx + r * 2):
				if x >= 0 and x < W and y >= 0 and y < H and pow((x - cx) / 2.0, 2) + pow(y - cy, 2) < r * r and (x + y) % 2 == 0:
					img.set_pixel(x, y, theme["ground_dark"])
	if theme.get("ridges", false):
		# Dune ridges: a shaded line with a bright crest above it.
		for k in 6:
			var by := 50 + k * 22
			var ph := k * 1.7
			for x in W:
				var yy := by + int(5 * sin(x / 19.0 + ph) + 3 * sin(x / 7.0 + ph * 2))
				put(x, yy, theme["ground_dark"])
				put(x, yy + 1, theme["ground_dark"] if (x + k) % 2 == 0 else theme["ground"][1])
				put(x, yy - 1, theme["ground"][2])
	# Horizon band along the top: hills, cave ceiling, dark woods or ash.
	var hz: Array = theme["horizon"]
	for x in W:
		var top := horizon_top(theme, x)
		for y in range(0, top):
			img.set_pixel(x, y, sky_color(theme, y, top) if y < top - 10 else hz[0])
		for y in range(maxi(0, top - 10), top):
			img.set_pixel(x, y, hz[0] if (x + y) % 3 != 0 else hz[1])
		put(x, top, theme["horizon_line"])
		if theme.get("peaks", false):
			# Snow caps on the peaks.
			for y in range(maxi(0, top - 10), top - 4):
				if y >= top - 10 + int(absf(sin(x / 3.1)) * 2):
					img.set_pixel(x, y, theme["snowcap"] if (x + y) % 5 != 0 else hz[0])
	if theme["props"] == "crystals":
		# Stalactites hanging from the cave ceiling.
		for x in range(4, W, 11):
			var length := 6 + (x * 7) % 9
			var top := horizon_top(theme, x)
			for i in length:
				var hw := maxi(0, 2 - i / 3)
				for dx in range(-hw, hw + 1):
					put(x + dx, top + i, hz[1])
	if theme.has("moon"):
		var m: Array = theme["moon"]
		disc(m[0], m[1], 9, c(236, 232, 200))
		disc(m[0] + 3, m[1] - 2, 8, theme["sky"])
		for _i in 30:
			put(rng.randi_range(0, W - 1), rng.randi_range(0, 12), c(220, 220, 255))
	if theme.has("volcano"):
		var v: Array = theme["volcano"]
		for y in range(4, 26):
			var half := (y - 4) * 1.6 + 4
			for x in range(int(v[0] - half), int(v[0] + half)):
				put(x, y, c(52, 32, 34) if (x + y) % 4 != 0 else c(44, 28, 30))
		for x in range(v[0] - 4, v[0] + 4):
			put(x, 4, c(255, 140, 50))
			put(x, 5, c(255, 200, 90))
		for i in 8:
			disc(v[0] - 2 + i * 2, 0 - i, 3 + i * 0.5, c(90, 70, 70))
	if theme.has("rainbow"):
		_paint_rainbow(theme)
	if theme.has("sun"):
		_paint_sun(theme)


func in_sky(theme: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H and y < horizon_top(theme, x) - 10


func put_sky(theme: Dictionary, x: int, y: int, col: Color) -> void:
	if in_sky(theme, x, y):
		img.set_pixel(x, y, col)


func _paint_rainbow(theme: Dictionary) -> void:
	var rb: Array = theme["rainbow"]
	var bands := [c(240, 96, 110), c(255, 160, 80), c(255, 226, 110), c(130, 214, 140), c(110, 170, 240), c(170, 130, 230)]
	for y in 0:
		pass
	for y in H:
		for x in W:
			var d := Vector2(x + 0.5 - rb[0], (y + 0.5 - rb[1]) * 1.0).length()
			var k := int((d - 34.0) / 2.0)
			if d >= 34.0 and k >= 0 and k < bands.size() and in_sky(theme, x, y):
				img.set_pixel(x, y, bands[k])


func _paint_sun(theme: Dictionary) -> void:
	var s: Array = theme["sun"]
	var sx: int = s[0]
	var sy: int = s[1]
	var r: float = s[2]
	# Glow rings, then rays and the disc.
	var glow_a: Color = theme["sky"].lerp(c(255, 244, 200), 0.35)
	var glow_b: Color = theme["sky"].lerp(c(255, 244, 200), 0.6)
	for y in range(int(sy - r * 2.4), int(sy + r * 2.4)):
		for x in range(int(sx - r * 2.4), int(sx + r * 2.4)):
			var d := Vector2(x + 0.5 - sx, y + 0.5 - sy).length()
			if d < r * 2.0 and (x + y) % 2 == 0:
				put_sky(theme, x, y, glow_a if d > r * 1.5 else glow_b)
			if d >= r and d < r * 1.9:
				var ang := atan2(y + 0.5 - sy, x + 0.5 - sx)
				if int(floor(ang / (TAU / 16.0))) % 2 == 0 and d > r * 1.2:
					put_sky(theme, x, y, c(255, 232, 130))
			if d <= r + 1.0 and d > r:
				put_sky(theme, x, y, c(255, 190, 70))
			elif d <= r:
				put_sky(theme, x, y, c(255, 246, 190) if d < r * 0.6 else c(255, 224, 110))


func paint_water(theme: Dictionary) -> void:
	var wl: Array = theme["water"]
	if wl.is_empty():
		return
	var water: Color = wl[0]
	var dark: Color = wl[1]
	var light: Color = wl[2]
	if theme.has("river"):
		var river := catmull(theme["river"], 30)
		# Bank first, then the water, sampled densely so there are no gaps.
		var dense: Array = []
		for i in range(river.size() - 1):
			var a: Vector2 = river[i]
			var b: Vector2 = river[i + 1]
			var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
			for k in steps:
				dense.append(a + (b - a) * float(k) / steps)
		for p in dense:
			for dx in range(-6, 7):
				put(p.x + dx, p.y, dark)
		for p in dense:
			for dx in range(-4, 5):
				put(p.x + dx, p.y, water)
		for i in dense.size():
			if i % 9 == 0:
				var p: Vector2 = dense[i]
				for dx in [-2, -1, 0]:
					put(p.x + dx + (i / 9) % 3 - 1, p.y, light)
	if theme.has("lake"):
		var l: Array = theme["lake"]
		var cx: int = l[0]
		var cy: int = l[1]
		var rx: int = l[2]
		var ry: int = l[3]
		var shore = theme.get("lake_shore", null)
		for y in range(cy - ry - 3, cy + ry + 4):
			for x in range(cx - rx - 3, cx + rx + 4):
				var d := pow(float(x - cx) / rx, 2) + pow(float(y - cy) / ry, 2)
				if d <= 1.0:
					put(x, y, dark if d > 0.75 else water)
					if d < 0.5 and (x * 3 + y * 5) % 17 == 0:
						put(x, y, light)
				elif shore != null and d <= 1.45 and (x + y) % 3 != 0:
					put(x, y, shore)
		if theme["props"] == "frost":
			# Cracks and glints on the ice.
			for k in 7:
				var sx := cx - rx + 6 + k * (rx * 2 - 10) / 7
				var sy := cy - ry / 2 + (k * 5) % ry
				for i in 4:
					put(sx + i, sy + (i / 2), light)


func draw_path(theme: Dictionary) -> Array:
	var curve := catmull(theme["nodes"], 36)
	var water: Array = theme["water"]
	for p in curve:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy <= 9:
					var xx := int(p.x + dx)
					var yy := int(p.y + dy)
					if xx >= 0 and xx < W and yy >= 0 and yy < H:
						img.set_pixel(xx, yy, theme["bridge"] if at(xx, yy) in water else theme["path_dark"])
	for p in curve:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 4:
					var xx := int(p.x + dx)
					var yy := int(p.y + dy)
					if xx >= 0 and xx < W and yy >= 0 and yy < H:
						if at(xx, yy) == theme["bridge"]:
							img.set_pixel(xx, yy, theme["bridge"] if xx % 3 != 0 else OUTLINE)
						else:
							img.set_pixel(xx, yy, theme["path"])
	for i in curve.size():
		var p: Vector2 = curve[i]
		if i % 9 == 0 and at(p.x, p.y - 1) == theme["path"]:
			put(p.x, p.y - 1, theme["path_light"])
	return curve


# --- props -----------------------------------------------------------------

func tree(x: int, y: int) -> void:
	var leaf := [c(52, 128, 70), c(66, 150, 80), c(90, 176, 96)]
	for dx in range(-4, 5):
		put(x + dx, y + 2, c(64, 120, 62))
	for dy in range(-2, 2):
		put(x, y + dy, c(110, 74, 52))
	disc(x, y - 6, 5.2, OUTLINE)
	disc(x, y - 6, 4.4, leaf[0])
	disc(x - 1, y - 7, 3.2, leaf[1])
	disc(x - 2, y - 8, 1.5, leaf[2])


func crystal(x: int, y: int, color: Color) -> void:
	for i in 7:
		var half := maxi(0, 2 - absi(i - 3) / 2)
		for dx in range(-half, half + 1):
			put(x + dx, y - i, color if dx < 1 else darker(color, 50))
	put(x - 1, y - 5, c(240, 250, 255))
	for dx in range(-3, 4):
		put(x + dx, y + 1, c(40, 42, 54))


func stalagmite(x: int, y: int) -> void:
	for i in 9:
		var half := maxi(0, 3 - i / 3)
		for dx in range(-half, half + 1):
			put(x + dx, y - i, c(96, 100, 118) if dx < 0 else c(70, 74, 90))


func dead_tree(x: int, y: int) -> void:
	var col := c(40, 34, 40)
	for dy in range(-10, 2):
		put(x, y + dy, col)
	for i in 5:
		put(x - i, y - 6 - i / 2, col)
		put(x + i, y - 8 - i / 2, col)
	put(x - 5, y - 9, col)
	put(x + 5, y - 11, col)


func grave(x: int, y: int) -> void:
	var lt := c(120, 124, 140)
	var dk := c(92, 96, 112)
	var cr := c(60, 62, 74)
	for dy in range(-6, 1):
		for dx in range(-2, 3):
			put(x + dx, y + dy, lt if dx < 1 else dk)
	put(x - 1, y - 7, lt)
	put(x, y - 7, lt)
	put(x + 1, y - 7, dk)
	for p in [Vector2(0, -4), Vector2(-1, -4), Vector2(1, -4), Vector2(0, -5)]:
		put(x + p.x, y + p.y, cr)
	for dx in range(-3, 4):
		put(x + dx, y + 1, c(36, 44, 46))


func rock(x: int, y: int) -> void:
	disc(x, y - 2, 3.4, OUTLINE)
	disc(x, y - 2, 2.6, c(100, 84, 84))
	put(x - 1, y - 4, c(140, 120, 116))


func pine(x: int, y: int) -> void:
	var g1 := c(36, 96, 84)
	var g2 := c(56, 128, 104)
	var snow := c(248, 252, 255)
	for dx in range(-3, 4):
		put(x + dx, y + 2, c(168, 192, 222))
	for dy in range(-2, 2):
		put(x, y + dy, c(96, 68, 54))
	# Three stacked tiers, outlined, with a snow cap on each.
	for t in 3:
		var base := y - 1 - t * 5
		var hw := 6 - t * 1
		for row in 6:
			var half := int(hw * (row + 1) / 6.0 + 0.5)
			for dx in range(-half - 1, half + 2):
				var edge := absi(dx) > half
				if edge:
					put(x + dx, base - 5 + row, OUTLINE)
				else:
					var col := g2 if dx < 0 else g1
					if row <= 1 or (row == 2 and absi(dx) < 2):
						col = snow if dx < 1 else c(206, 222, 240)
					put(x + dx, base - 5 + row, col)
		for dx in range(-hw - 1, hw + 2):
			put(x + dx, base + 1, OUTLINE)
	put(x, y - 16, OUTLINE)
	put(x, y - 15, snow)


func snow_rock(x: int, y: int) -> void:
	disc(x, y - 2, 3.8, OUTLINE)
	disc(x, y - 2, 3.0, c(132, 144, 170))
	disc(x - 1, y - 3, 2.2, c(236, 244, 252))
	put(x - 1, y - 4, c(255, 255, 255))
	put(x + 2, y - 1, c(96, 106, 134))


func cactus(x: int, y: int) -> void:
	var lt := c(86, 160, 84)
	var dk := c(52, 118, 66)
	for dx in range(-3, 4):
		put(x + dx, y + 1, c(200, 156, 84))
	for dy in range(-12, 1):
		for dx in range(-2, 3):
			var edge := absi(dx) == 2 or dy == -12
			if dy == -12 and absi(dx) == 2:
				continue
			put(x + dx, y + dy, OUTLINE if edge else (lt if dx < 1 else dk))
	for k in 3:
		put(x - 1, y - 3 - k * 3, c(150, 210, 130))
	# Arms.
	for dy in range(-9, -4):
		put(x - 5, y + dy, OUTLINE)
		put(x - 4, y + dy, lt)
		put(x - 3, y + dy, dk)
	for dx in range(-5, -2):
		put(x + dx, y - 5, dk)
	put(x - 5, y - 10, OUTLINE)
	put(x - 4, y - 10, OUTLINE)
	put(x - 3, y - 10, OUTLINE)
	for dy in range(-8, -4):
		put(x + 4, y + dy, OUTLINE)
		put(x + 3, y + dy, dk)
	for dx in range(3, 5):
		put(x + dx, y - 4, dk)
	put(x + 3, y - 9, OUTLINE)
	put(x + 4, y - 9, OUTLINE)


func sand_rock(x: int, y: int) -> void:
	disc(x, y - 2, 3.6, OUTLINE)
	disc(x, y - 2, 2.8, c(176, 124, 84))
	disc(x - 1, y - 3, 1.8, c(214, 164, 108))
	put(x - 1, y - 4, c(240, 204, 150))


func palm(x: int, y: int) -> void:
	var trunk := c(132, 90, 56)
	var fr1 := c(70, 150, 64)
	var fr2 := c(110, 184, 80)
	for i in 12:
		var tx := x + int(sin(i / 5.0) * 2.0)
		put(tx, y - i, OUTLINE if i % 3 == 0 else trunk)
		put(tx + 1, y - i, trunk)
	var tx := x + int(sin(11 / 5.0) * 2.0)
	var ty := y - 12
	# Fronds as drooping arcs.
	for a in [-3.0, -2.2, -1.2, -0.3, 0.6, 1.6]:
		var dirx := cos(a)
		var diry := sin(a)
		for s in 7:
			var fx := tx + dirx * s * 1.1
			var fy := ty + diry * s * 0.5 + s * s * 0.08
			put(fx, fy, fr1 if s % 2 == 0 else fr2)
			put(fx, fy - 1, fr2)
	put(tx, ty + 1, c(120, 80, 50))
	put(tx + 1, ty + 1, c(120, 80, 50))


func floating_island(x: int, y: int, variant: int) -> void:
	var grass := c(98, 184, 88)
	var grass_hi := c(150, 214, 118)
	var dirt := c(140, 98, 76)
	var dirt_dk := c(98, 68, 60)
	var rw := 9 + variant % 3
	# Soft shadow of the island on the clouds below.
	for dx in range(-rw, rw + 1):
		put(x + dx, y + 11, c(206, 190, 232) if (x + dx) % 2 == 0 else c(218, 204, 240))
	# Dirt underside tapering to a point.
	for row in 9:
		var half := int(rw * (1.0 - row / 9.0))
		for dx in range(-half, half + 1):
			put(x + dx, y + 2 + row, dirt_dk if dx > 0 else dirt)
		put(x - half - 1, y + 2 + row, OUTLINE)
		put(x + half + 1, y + 2 + row, OUTLINE)
	put(x, y + 11, OUTLINE)
	# Grass cap.
	for dx in range(-rw - 1, rw + 2):
		put(x + dx, y - 1, OUTLINE)
		put(x + dx, y + 2, OUTLINE if absi(dx) > rw else dirt)
	for dy in range(0, 2):
		for dx in range(-rw, rw + 1):
			put(x + dx, y + dy, grass_hi if dy == 0 and dx < 1 else grass)
	# Tiny tree or flowers on top.
	if variant % 2 == 0:
		for dy in range(-4, 0):
			put(x + 1, y + dy, c(110, 74, 52))
		disc(x + 1, y - 7, 3.6, OUTLINE)
		disc(x + 1, y - 7, 2.8, c(66, 150, 80))
		put(x, y - 8, c(120, 190, 110))
	else:
		for dx in [-4, -1, 3]:
			put(x + dx, y - 2, c(255, 214, 92) if dx != -1 else c(238, 132, 168))
			put(x + dx, y - 3, c(250, 246, 220))


func place_prop(theme: Dictionary, x: int, y: int, placed: int) -> void:
	match theme["props"]:
		"trees":
			tree(x, y)
		"crystals":
			if placed % 3 == 0:
				crystal(x, y, theme["sparkles"][rng.randi_range(0, theme["sparkles"].size() - 1)])
			else:
				stalagmite(x, y)
		"graves":
			if placed % 2 == 0:
				dead_tree(x, y)
			else:
				grave(x, y)
		"frost":
			if placed % 3 == 2:
				snow_rock(x, y)
			else:
				pine(x, y)
		"islands":
			floating_island(x, y, placed)
		"desert":
			if placed % 3 == 2:
				sand_rock(x, y)
			else:
				cactus(x, y)
		_:
			rock(x, y)


func decorate(theme: Dictionary, curve: Array) -> void:
	var sparse: Array = []
	for i in range(0, curve.size(), 3):
		sparse.append(curve[i])
	var water: Array = theme["water"]
	var placed := 0
	var attempts := 0
	var count: int = theme.get("count", 34)
	if theme["props"] == "islands":
		count = 14
	var min_y: int = theme.get("min_y", 34)
	var near := func(x: int, y: int, d: float) -> bool:
		for p in sparse:
			if (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < d * d:
				return true
		return false
	# Oasis palms first, so the random props leave them alone.
	if theme.has("palms"):
		for p in theme["palms"]:
			palm(int(p.x), int(p.y))
	var palm_pts: Array = theme.get("palms", [])
	var lake_ok := func(x: int, y: int) -> bool:
		if at(x, y) in water:
			return false
		for dx in range(-8, 9, 4):
			if at(minf(W - 1, x + dx), y) in water:
				return false
		return true
	var prop_gap := 14.0 if theme["props"] != "islands" else 26.0
	var placed_pts: Array = []
	while placed < count and attempts < 4000:
		attempts += 1
		var x := rng.randi_range(6, W - 6)
		var y := rng.randi_range(min_y, H - 6)
		if near.call(x, y, 14) or not lake_ok.call(x, y):
			continue
		var too_close := false
		for q in placed_pts:
			if absf(q.x - x) < prop_gap and absf(q.y - y) < prop_gap * 0.7:
				too_close = true
				break
		if too_close:
			continue
		var skip := false
		for p in palm_pts:
			if absf(p.x - x) < 10 and absf(p.y - y) < 14:
				skip = true
		if skip:
			continue
		place_prop(theme, x, y, placed)
		placed_pts.append(Vector2(x, y))
		placed += 1
	var allowed: Array = theme["ground"] + [theme["ground_dark"]]
	for _i in 150:
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(30, H - 1)
		if not near.call(x, y, 6) and at(x, y) in allowed:
			img.set_pixel(x, y, theme["sparkles"][rng.randi_range(0, theme["sparkles"].size() - 1)])


func render(name: String, theme: Dictionary, out_dir: String) -> String:
	rng.seed = 7 + name.length()
	img = Image.create(W, H, false, Image.FORMAT_RGB8)
	paint_ground(theme)
	paint_water(theme)
	var curve := draw_path(theme)
	decorate(theme, curve)
	var path := out_dir.path_join(name + ".png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	img.save_png(path)
	return path
