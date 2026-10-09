extends Node
## Proposals for a pixel-art UI (HUD, popups, banners, menus) drawn over real
## game frames. Not part of the game; it renders mockups to compare styles:
##   godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/pixel_ui/ui_mockups.tscn -- out_dir
## Every element is generated in code in the runners' style (1 art pixel =
## 2 screen pixels, dark outline, flat colours) in two styles:
##   slate  dark slate panels with the game's teal trim (close to today's UI)
##   wood   wooden frames around parchment, warmer, matches the meadow

const MainScene := preload("res://main.tscn")
const FONTS := {
	"pixelify": "res://assets/fonts/pixelify_sans/PixelifySans.ttf",
	"silkscreen": "res://assets/fonts/silkscreen/Silkscreen-Regular.ttf",
}
var _font: Font
var _font_name := "default"
const TICK := 1.0 / 60.0
const S := 2.0

const STYLES := {
	"slate": {
		"outline": Color8(10, 12, 20), "frame": Color8(66, 214, 197), "frame_dark": Color8(36, 130, 124),
		"fill": Color8(20, 28, 44), "fill_light": Color8(32, 44, 66), "text": Color8(237, 243, 255),
		"muted": Color8(150, 166, 190), "accent": Color8(245, 212, 94), "icon": Color8(237, 243, 255), "icon_accent": Color8(66, 214, 197),
	},
	"wood": {
		"outline": Color8(34, 20, 14), "frame": Color8(166, 108, 60), "frame_dark": Color8(110, 68, 38),
		"fill": Color8(240, 222, 182), "fill_light": Color8(250, 238, 206), "text": Color8(60, 36, 24),
		"muted": Color8(120, 88, 60), "accent": Color8(200, 90, 50), "icon": Color8(96, 58, 34), "icon_accent": Color8(200, 90, 50),
	},
}

## Icons as text: w = icon colour, a = accent, g = gold, k = dark, . = empty.
const ICONS := {
	"chevron": ["w.......w", "ww.....ww", ".ww...ww.", "..ww.ww..", "...www...", "....w...."],
	"sound": [".....w.....", "....ww..a..", "w..www...a.", "wwwwww.a.a.", "wwwwww.a.a.", "wwwwww.a.a.", "w..www...a.", "....ww..a..", ".....w....."],
	"bag": ["...www...", "..w...w..", ".wwwwwww.", ".wwaaaww.", ".wwaaaww.", ".wwwwwww.", ".wwwwwww.", ".wwwwwww."],
	"shop": ["awawawawa", "awawawawa", ".a.a.a.a.", ".w.....w.", ".w.www.w.", ".w.w.w.w.", ".wwwwwww."],
	"pause": ["ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww"],
	"trophy": [".ggggggg.", "gg.ggg.gg", "gg.ggg.gg", ".ggggggg.", "..ggggg..", "...ggg...", "....g....", "...www...", "..wwwww.."],
	"flag": ["wkwkw", "kwkwk", "wkwkw", "w....", "w....", "w...."],
	"warning": ["....g....", "...ggg...", "...gkg...", "..ggkgg..", "..ggkgg..", ".ggggggg.", ".gggkggg.", "ggggggggg"],
	"coin": ["..ggg..", ".gwggg.", "gwgkggg", "ggkgkgg", "gggkggg", ".ggggg.", "..ggg.."],
	"star": ["....g....", "....g....", "...ggg...", "gggggwggg", ".gggwggg.", "..ggggg..", "..gg.gg..", ".gg...gg."],
}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if not args.is_empty() else "user://ui_mockups"
	# Optional: only these styles, and a font per run ("default", "pixelify", "silkscreen").
	var only_style := args[1] if args.size() > 1 else ""
	_font_name = args[2] if args.size() > 2 else "default"
	_font = _load_font(_font_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	Campaign.persist = false
	Campaign.start_level(CampaignCatalog.get_level(&"1-5"))
	var game := MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.set_physics_process(false)
	var effects: Object = game.get("_run_effects")
	for _i in range(600):
		effects.set("_invulnerable_left", 10)
		game.call("_physics_process", TICK)
	# Hide the current UI (every UI layer of the scene and the campaign banner).
	for child in game.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var banner: Variant = game.get("_campaign_banner")
	if banner is CanvasItem and is_instance_valid(banner):
		(banner as CanvasItem).visible = false
	for style in STYLES:
		if not only_style.is_empty() and style != only_style:
			continue
		for scene in ["hud", "menu"]:
			var layer := CanvasLayer.new()
			layer.layer = 50
			add_child(layer)
			var root := Control.new()
			root.size = Vector2(960, 540)
			root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			layer.add_child(root)
			if scene == "hud":
				_hud(root, STYLES[style])
			else:
				_menu(root, STYLES[style])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join("ui_%s_%s_%s.png" % [style, _font_name, scene])
			get_viewport().get_texture().get_image().save_png(path)
			print("CAPTURED ", path)
			layer.queue_free()
			await get_tree().process_frame
	get_tree().quit(0)

# --- Mockups ---------------------------------------------------------------

func _hud(root: Control, st: Dictionary) -> void:
	# Top left: coins and the stage name in a small panel.
	_panel(root, Rect2(12, 10, 150, 36), st)
	_icon(root, "coin", Vector2(22, 17), st, 3.0)
	_label(root, "23", Vector2(50, 15), 18, st.text)
	_label(root, "1-5", Vector2(96, 17), 13, st.muted)
	# Top centre: the stage progress bar with star slots and the flag.
	_panel(root, Rect2(250, 10, 400, 36), st)
	_label(root, "Fallande stenar", Vector2(264, 13), 12, st.text)
	var bar := Rect2(264, 30, 340, 8)
	_rect(root, bar.grow(2), st.outline)
	_rect(root, bar, st.fill_light)
	_rect(root, Rect2(bar.position, Vector2(bar.size.x * 0.42, bar.size.y)), st.frame)
	for f in [0.33, 0.62, 0.86]:
		_rect(root, Rect2(bar.position + Vector2(bar.size.x * f - 1, -2), Vector2(2, 12)), st.outline)
	_icon(root, "star", Vector2(608, 14), st, 2.0)
	_icon(root, "flag", Vector2(632, 18), st, 2.0)
	# Top right: icon buttons.
	var x := 960.0 - 12.0
	for icon in ["pause", "shop", "bag", "sound", "chevron"]:
		x -= 40.0
		_panel(root, Rect2(x, 10, 36, 36), st)
		_icon_centered(root, icon, Rect2(x, 10, 36, 36), st, 2.0)
		x -= 4.0
	# Stage banner ("Nytt hinder") mid screen.
	_panel(root, Rect2(300, 190, 360, 70), st)
	_panel(root, Rect2(312, 202, 46, 46), st, true)
	_icon_centered(root, "warning", Rect2(312, 202, 46, 46), st, 3.0)
	_label(root, "NYTT HINDER", Vector2(372, 200), 11, st.accent)
	_label(root, "Fallande stenar", Vector2(372, 214), 20, st.text)
	_label(root, "Se varningen och lämna golvet", Vector2(372, 240), 12, st.muted)
	# Achievement popup, bottom right.
	_panel(root, Rect2(608, 446, 336, 78), st)
	_panel(root, Rect2(620, 458, 54, 54), st, true)
	_icon_centered(root, "trophy", Rect2(620, 458, 54, 54), st, 4.0)
	_label(root, "PRESTATION UPPLÅST", Vector2(686, 458), 11, st.accent)
	_label(root, "Stjärnsamlare", Vector2(686, 472), 20, st.text)
	_label(root, "Samla 10 gravitationsstjärnor", Vector2(686, 498), 12, st.muted)

func _menu(root: Control, st: Dictionary) -> void:
	_rect(root, Rect2(0, 0, 960, 540), Color(0, 0, 0, 0.45))
	_panel(root, Rect2(330, 110, 300, 320), st)
	_label(root, "PAUS", Vector2(330, 126), 26, st.text, 300)
	var y := 180.0
	for text in ["Fortsätt", "Försök igen", "Karta", "Inställningar"]:
		var primary: bool = text == "Fortsätt"
		_panel(root, Rect2(360, y, 240, 44), st, not primary, primary)
		_label(root, text, Vector2(360, y + 10), 18, st.outline if primary else st.text, 240)
		y += 56.0
	_icon(root, "star", Vector2(400, 398), st, 2.0)
	_icon(root, "star", Vector2(430, 398), st, 2.0)
	_label(root, "2 / 3 stjärnor", Vector2(462, 398), 13, st.muted)

# --- Kit ---------------------------------------------------------------------

## A framed panel: outline, a 2-art-pixel frame with a darker inner line, the
## fill with a lighter top row, and notched corners. `inset` draws a sunken
## slot (for icons); `primary` fills with the frame colour (a main button).
func _panel(root: Control, rect: Rect2, st: Dictionary, inset := false, primary := false) -> void:
	var w := int(rect.size.x / S)
	var h := int(rect.size.y / S)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var fill: Color = st.frame if primary else (st.fill.darkened(0.15) if inset else st.fill)
	for y in range(h):
		for x in range(w):
			var edge := mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			var corner := (x == 0 or x == w - 1) and (y == 0 or y == h - 1)
			if corner:
				continue
			var color: Color = fill
			if edge == 0:
				color = st.outline
			elif edge == 1 and not inset:
				color = st.frame if not primary else st.frame.lightened(0.25)
			elif edge == 2 and not inset:
				color = st.frame_dark
			elif edge == 1 and inset:
				color = st.frame_dark
			elif y == 3 and not inset:
				color = (st.fill_light if not primary else st.frame.lightened(0.2))
			image.set_pixel(x, y, color)
	_texture(root, image, rect.position)

func _icon(root: Control, name: String, at: Vector2, st: Dictionary, scale: float) -> void:
	_texture(root, _icon_image(name, st), at, scale)

func _icon_centered(root: Control, name: String, box: Rect2, st: Dictionary, scale: float) -> void:
	var image := _icon_image(name, st)
	var size := Vector2(image.get_size()) * scale
	_texture(root, image, (box.get_center() - size * 0.5).round(), scale)

func _icon_image(name: String, st: Dictionary) -> Image:
	var rows: Array = ICONS[name]
	var w := 0
	for row in rows:
		w = maxi(w, str(row).length())
	var image := Image.create(w + 2, rows.size() + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			var c: String = row[x]
			var color := Color(0, 0, 0, 0)
			match c:
				"w": color = st.icon
				"a": color = st.icon_accent
				"g": color = Color8(245, 205, 82)
				"k": color = st.outline
			if color.a > 0.0:
				image.set_pixel(x + 1, y + 1, color)
	# Outline around the icon.
	var edge: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + n
				if q.x >= 0 and q.y >= 0 and q.x < image.get_width() and q.y < image.get_height() and image.get_pixel(q.x, q.y).a > 0.5:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		image.set_pixel(p.x, p.y, st.outline)
	return image

func _texture(root: Control, image: Image, at: Vector2, scale := S) -> void:
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.position = at
	rect.size = Vector2(image.get_size()) * scale
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(rect)

func _rect(root: Control, rect: Rect2, color: Color) -> void:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	root.add_child(r)

func _label(root: Control, text: String, at: Vector2, size: int, color: Color, width := 0.0) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	if width > 0.0:
		label.size = Vector2(width, size + 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		label.add_theme_font_override("font", _font)
		size = _pixel_size(size)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	root.add_child(label)

## A pixel font loaded without smoothing, or null for the theme's font.
func _load_font(name: String) -> Font:
	if not FONTS.has(name):
		return null
	var font := FontFile.new()
	font.load_dynamic_font(FONTS[name])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font

## Pixel fonts stay crisp only at multiples of their pixel size.
func _pixel_size(size: int) -> int:
	if _font_name == "silkscreen":
		return 16 if size <= 20 else 24
	return 16 if size <= 14 else (24 if size <= 22 else 32)
