extends Node
## The pixel-art UI (autoload PixelUi): frames, buttons, icons, the pixel font
## and a whole Theme, generated in code in the runners' style (1 art pixel =
## 2 screen pixels, a dark outline, flat colours with one highlight and one
## shade). Two styles the player can switch between in the options:
##   wood   wooden frames around dark walnut panels (default)
##   slate  dark slate with the game's teal trim
## The chosen style's Theme is merged into the project theme, so every Control
## that does not style itself picks it up; screens that build their own panels ask
## for a StyleBox here (panel_box) instead of making a StyleBoxFlat.

signal style_changed(style: String)

const ART := 2
const SETTINGS_PATH := "user://gravity_run_ui.cfg"
const FONT_PATH := "res://assets/fonts/pixelify_sans/PixelifySans.ttf"
const STYLES := ["wood", "slate"]

## Colours per style. text_on_frame is text on a primary (frame-coloured) button.
const PALETTES := {
	"wood": {
		"outline": Color8(34, 20, 14), "frame": Color8(166, 108, 60), "frame_light": Color8(204, 146, 88), "frame_dark": Color8(110, 68, 38),
		"fill": Color8(62, 42, 30), "fill_light": Color8(80, 56, 40), "fill_dark": Color8(44, 30, 22),
		"text": Color8(250, 238, 206), "muted": Color8(214, 190, 150), "accent": Color8(245, 196, 74), "good": Color8(132, 200, 96),
		"icon": Color8(250, 238, 206), "icon_accent": Color8(245, 196, 74), "text_on_frame": Color8(40, 24, 16),
		"hud_text": Color8(250, 238, 206), "shadow": Color(0, 0, 0, 0.45),
	},
	"slate": {
		"outline": Color8(10, 12, 20), "frame": Color8(66, 214, 197), "frame_light": Color8(140, 236, 224), "frame_dark": Color8(36, 130, 124),
		"fill": Color8(20, 28, 44), "fill_light": Color8(32, 44, 66), "fill_dark": Color8(14, 20, 32),
		"text": Color8(237, 243, 255), "muted": Color8(150, 166, 190), "accent": Color8(245, 212, 94), "good": Color8(66, 214, 197),
		"icon": Color8(237, 243, 255), "icon_accent": Color8(66, 214, 197), "text_on_frame": Color8(10, 12, 20),
		"hud_text": Color8(237, 243, 255), "shadow": Color(0, 0, 0, 0.45),
	},
}

## Icons as text: w = icon colour, a = accent, g = gold, r = red, k = outline
## colour, . = empty. Each gets a 1 px outline when drawn.
const ICONS := {
	"chevron": ["w.......w", "ww.....ww", ".ww...ww.", "..ww.ww..", "...www...", "....w...."],
	"chevron_right": ["ww....", ".ww...", "..ww..", "...ww.", "..ww..", ".ww...", "ww...."],
	"music": [".....w.....", "....ww..a..", "w..www...a.", "wwwwww.a.a.", "wwwwww.a.a.", "wwwwww.a.a.", "w..www...a.", "....ww..a..", ".....w....."],
	"music_off": [".....w.....", "....ww.....", "w..www.r.r.", "wwwwww..r..", "wwwwww.r.r.", "wwwwww.....", "w..www.....", "....ww.....", ".....w....."],
	"inventory": ["...www...", "..w...w..", ".wwwwwww.", ".wwaaaww.", ".wwaaaww.", ".wwwwwww.", ".wwwwwww.", ".wwwwwww."],
	"shop": ["awawawawa", "awawawawa", ".a.a.a.a.", ".w.....w.", ".w.www.w.", ".w.w.w.w.", ".wwwwwww."],
	"pause": ["ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww", "ww.ww"],
	"trophy": [".ggggggg.", "gg.ggg.gg", "gg.ggg.gg", ".ggggggg.", "..ggggg..", "...ggg...", "....g....", "...www...", "..wwwww.."],
	"flag": ["wkwkw", "kwkwk", "wkwkw", "w....", "w....", "w...."],
	"warning": ["....g....", "...ggg...", "...gkg...", "..ggkgg..", "..ggkgg..", ".ggggggg.", ".gggkggg.", "ggggggggg"],
	"star": ["....g....", "....g....", "...ggg...", "gggggwggg", ".gggwggg.", "..ggggg..", "..gg.gg..", ".gg...gg."],
	"check": ["......w", ".....ww", "w...ww.", "ww.ww..", ".www...", "..w...."],
	"close": ["w...w", "ww.ww", ".www.", "ww.ww", "w...w"],
	"boss": [".rrrrr.", "rwrrrwr", "rrrrrrr", "rrkkkrr", ".rrrrr."],
}

var style := "wood"
var _font: FontFile
var _cache: Dictionary = {}
var _themes: Dictionary = {}

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var saved := str(config.get_value("ui", "style", "wood"))
		if saved in STYLES:
			style = saved
	# Tools can force a style: -- ui-style=slate
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ui-style=") and arg.substr(9) in STYLES:
			style = arg.substr(9)
	apply()

## Switches the style, saves it and re-themes the whole game.
func set_style(value: String) -> void:
	if not value in STYLES or value == style:
		return
	style = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("ui", "style", style)
	config.save(SETTINGS_PATH)
	for key in _cache:
		var item: Variant = _cache[key]
		if item is StyleBoxTexture and (item as StyleBoxTexture).has_meta("pixel_kind"):
			(item as StyleBoxTexture).texture = _wrap(_frame_image(str((item as StyleBoxTexture).get_meta("pixel_kind"))), false)
	apply()
	style_changed.emit(style)

func apply() -> void:
	# The project theme is what every Control falls back to (also those under a
	# CanvasLayer, where a theme on the root window does not reach), so the
	# pixel theme is merged into it. The fallback font covers draw_string calls.
	ThemeDB.fallback_font = font()
	ThemeDB.fallback_font_size = 16
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.merge_with(theme())
		project.default_font = font()
		project.default_font_size = 16
	else:
		var tree := get_tree()
		if tree != null and tree.root != null:
			tree.root.theme = theme()

func color(key: String) -> Color:
	return (PALETTES[style] as Dictionary)[key]

## The pixel font, without smoothing (crisp at any size).
func font() -> Font:
	if _font == null:
		_font = FontFile.new()
		_font.load_dynamic_font(FONT_PATH)
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font

# --- Frames ------------------------------------------------------------------

## A 9-slice StyleBox for a frame kind:
##   panel    a raised panel (frame, bevel, fill with a lit top row)
##   inset    a sunken slot (for icons and fields)
##   button / button_hover / button_pressed / button_disabled
##   primary  a frame-coloured main button
##   hud      a small HUD plate
## Content margins leave room for the frame.
func panel_box(kind := "panel", padding := Vector2(10, 6)) -> StyleBoxTexture:
	# One box per kind and padding for all styles: a style switch redraws its
	# texture in place, so every panel that holds it changes at once.
	var key := "box|%s|%s" % [kind, str(padding)]
	if not _cache.has(key):
		var box := StyleBoxTexture.new()
		box.texture = _wrap(_frame_image(kind), false)
		box.set_meta("pixel_kind", kind)
		var m := float(5 * ART)
		box.texture_margin_left = m
		box.texture_margin_right = m
		box.texture_margin_top = m
		box.texture_margin_bottom = m
		box.content_margin_left = maxf(padding.x, m * 0.6)
		box.content_margin_right = maxf(padding.x, m * 0.6)
		box.content_margin_top = maxf(padding.y, m * 0.4)
		box.content_margin_bottom = maxf(padding.y, m * 0.4)
		_cache[key] = box
	return _cache[key]

## The frame picture (12 x 12 art pixels, scaled to screen pixels): notched
## corners, a 1 px outline, a 2 px frame with a light outer and dark inner
## line, and the fill with a lighter top row.
func _frame_image(kind: String) -> Image:
	var n := 12
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var inset := kind == "inset"
	var fill := color("fill")
	var frame := color("frame")
	var frame_light := color("frame_light")
	var frame_dark := color("frame_dark")
	match kind:
		"inset":
			fill = color("fill_dark")
		"button_hover":
			fill = color("fill_light")
			frame = color("frame_light")
		"button_pressed":
			fill = color("fill_dark")
		"button_disabled":
			fill = color("fill_dark")
			frame = color("frame_dark")
			frame_light = color("frame_dark")
		"primary":
			fill = color("frame")
			frame = color("frame_light")
			frame_light = color("frame_light").lightened(0.2)
			frame_dark = color("frame_dark")
		"hud":
			fill = color("fill")
	for y in range(n):
		for x in range(n):
			if (x == 0 or x == n - 1) and (y == 0 or y == n - 1):
				continue
			var edge := mini(mini(x, n - 1 - x), mini(y, n - 1 - y))
			var c := fill
			if edge == 0:
				c = color("outline")
			elif inset and edge == 1:
				c = frame_dark
			elif not inset and edge == 1:
				c = frame_light if (x < n / 2 and y < n / 2) or y == 1 else frame
			elif not inset and edge == 2:
				c = frame_dark
			elif y == 3 and kind != "button_pressed" and not inset:
				c = fill.lightened(0.12)
			image.set_pixel(x, y, c)
	image.resize(n * ART, n * ART, Image.INTERPOLATE_NEAREST)
	return image

# --- Icons -------------------------------------------------------------------

## An icon as a texture (nearest filtering), at ART times its art size.
func icon_texture(name: String) -> Texture2D:
	var key := "icon|%s|%s" % [style, name]
	if not _cache.has(key):
		_cache[key] = _wrap(icon_image(name), false)
	return _cache[key]

func icon_image(name: String) -> Image:
	var rows: Array = ICONS.get(name, ICONS["close"])
	var w := 0
	for row in rows:
		w = maxi(w, str(row).length())
	var image := Image.create(w + 2, rows.size() + 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			var ch: String = row[x]
			var c := Color(0, 0, 0, 0)
			match ch:
				"w": c = color("icon")
				"a": c = color("icon_accent")
				"g": c = Color8(245, 205, 82)
				"r": c = Color8(226, 76, 86)
				"k": c = color("outline")
			if c.a > 0.0:
				image.set_pixel(x + 1, y + 1, c)
	var edge: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < image.get_width() and q.y < image.get_height() and image.get_pixel(q.x, q.y).a > 0.5:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		image.set_pixel(p.x, p.y, color("outline"))
	image.resize(image.get_width() * ART, image.get_height() * ART, Image.INTERPOLATE_NEAREST)
	return image

## Draws an icon centred in a rectangle, as large as fits in whole steps.
func draw_icon(canvas: CanvasItem, name: String, rect: Rect2, modulate := Color.WHITE) -> void:
	var texture := icon_texture(name)
	var size := Vector2(texture.get_size())
	var scale := maxf(1.0, floorf(minf(rect.size.x / size.x, rect.size.y / size.y)))
	if rect.size.x < size.x or rect.size.y < size.y:
		scale = minf(rect.size.x / size.x, rect.size.y / size.y)
	var drawn := size * scale
	canvas.draw_texture_rect(texture, Rect2((rect.get_center() - drawn * 0.5).round(), drawn), false, modulate)

func _wrap(image: Image, repeat: bool) -> Texture2D:
	var wrapped := CanvasTexture.new()
	wrapped.diffuse_texture = ImageTexture.create_from_image(image)
	wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrapped.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if repeat else CanvasItem.TEXTURE_REPEAT_DISABLED
	return wrapped

# --- Theme -------------------------------------------------------------------

## The whole Theme for the current style (cached per style).
func theme() -> Theme:
	if _themes.has(style):
		return _themes[style]
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	var text := color("text")
	for kind in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", kind, panel_box("button"))
		t.set_stylebox("hover", kind, panel_box("button_hover"))
		t.set_stylebox("pressed", kind, panel_box("button_pressed"))
		t.set_stylebox("hover_pressed", kind, panel_box("button_pressed"))
		t.set_stylebox("disabled", kind, panel_box("button_disabled"))
		t.set_stylebox("focus", kind, _focus_box())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(state, kind, text)
		t.set_color("font_disabled_color", kind, Color(color("muted"), 0.7))
		t.set_color("icon_normal_color", kind, color("icon"))
		t.set_constant("outline_size", kind, 0)
	t.set_stylebox("normal", "LineEdit", panel_box("inset", Vector2(10, 6)))
	t.set_stylebox("focus", "LineEdit", _focus_box())
	t.set_stylebox("read_only", "LineEdit", panel_box("button_disabled", Vector2(10, 6)))
	t.set_color("font_color", "LineEdit", text)
	t.set_color("font_placeholder_color", "LineEdit", Color(color("muted"), 0.8))
	t.set_color("caret_color", "LineEdit", color("accent"))
	t.set_color("selection_color", "LineEdit", Color(color("frame"), 0.4))
	t.set_stylebox("panel", "PanelContainer", panel_box("panel", Vector2(14, 12)))
	t.set_stylebox("panel", "AcceptDialog", panel_box("panel", Vector2(16, 12)))
	t.set_stylebox("embedded_border", "Window", panel_box("panel", Vector2(8, 8)))
	t.set_stylebox("panel", "TooltipPanel", panel_box("panel", Vector2(8, 4)))
	t.set_color("font_color", "TooltipLabel", text)
	t.set_color("font_color", "Label", text)
	var track := panel_box("inset", Vector2(0, 3))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", panel_box("primary", Vector2(0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", panel_box("primary", Vector2(0, 3)))
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", panel_box("primary", Vector2(0, 3)))
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", kind, panel_box("inset", Vector2(3, 3)))
		t.set_stylebox("grabber", kind, panel_box("button", Vector2(3, 3)))
		t.set_stylebox("grabber_highlight", kind, panel_box("button_hover", Vector2(3, 3)))
		t.set_stylebox("grabber_pressed", kind, panel_box("button_pressed", Vector2(3, 3)))
	_themes[style] = t
	return t

## Keyboard focus: the frame drawn again in the accent colour around the control.
func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color("accent")
	box.set_border_width_all(2)
	box.expand_margin_left = 2.0
	box.expand_margin_right = 2.0
	box.expand_margin_top = 2.0
	box.expand_margin_bottom = 2.0
	box.anti_aliasing = false
	return box
