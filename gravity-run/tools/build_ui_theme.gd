extends SceneTree
## Regenerates res://ui/theme/gravity_theme.tres, the project-wide UI theme.
## Run: godot --headless --path . -s res://tools/build_ui_theme.gd
## Screens built in code keep their own overrides; the theme gives every
## un-styled Button, LineEdit, slider, scrollbar, tooltip and dialog the same
## navy + teal look as the existing menu panels instead of Godot's grey default.

const INK := Color("edf3ff")
const MUTED := Color("b8c7dc")
const ACCENT := Color("42d6c5")
const ACCENT_DARK := Color(0.09, 0.33, 0.36, 0.98)
const SURFACE := Color(0.07, 0.105, 0.17, 0.92)
const RAISED := Color(0.11, 0.16, 0.25, 0.96)
const RAISED_HOVER := Color(0.14, 0.21, 0.32, 0.98)
const LINE := Color(0.25, 0.37, 0.50, 1.0)
const DISABLED := Color(0.09, 0.12, 0.18, 0.75)

func _box(bg: Color, border: Color, border_width := 2, radius := 10, h := 10.0, v := 4.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	style.anti_aliasing = true
	return style

func _initialize() -> void:
	var theme := Theme.new()
	# Buttons
	theme.set_stylebox("normal", "Button", _box(RAISED, LINE))
	theme.set_stylebox("hover", "Button", _box(RAISED_HOVER, ACCENT))
	theme.set_stylebox("pressed", "Button", _box(ACCENT_DARK, ACCENT))
	theme.set_stylebox("hover_pressed", "Button", _box(ACCENT_DARK, ACCENT))
	theme.set_stylebox("disabled", "Button", _box(DISABLED, Color(LINE, 0.45)))
	var focus := _box(Color(0, 0, 0, 0), Color(ACCENT, 0.95), 2, 11)
	focus.expand_margin_left = 2.0
	focus.expand_margin_right = 2.0
	focus.expand_margin_top = 2.0
	focus.expand_margin_bottom = 2.0
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	theme.set_color("icon_normal_color", "Button", INK)
	theme.set_color("icon_hover_color", "Button", Color.WHITE)
	theme.set_color("icon_pressed_color", "Button", Color.WHITE)
	theme.set_constant("outline_size", "Button", 0)
	# Text inputs
	theme.set_stylebox("normal", "LineEdit", _box(Color(0.04, 0.07, 0.12, 0.95), LINE, 2, 8, 10, 6))
	theme.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), ACCENT, 2, 8, 10, 6))
	theme.set_stylebox("read_only", "LineEdit", _box(DISABLED, Color(LINE, 0.5), 2, 8, 10, 6))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	# Panels and popups
	# Plain Panel/PanelContainer keep Godot defaults: several HUD widgets rely on
	# them being unobtrusive, and menu panels already set their own style.
	theme.set_stylebox("panel", "AcceptDialog", _box(SURFACE, ACCENT, 2, 14, 16, 12))
	theme.set_stylebox("embedded_border", "Window", _box(SURFACE, ACCENT, 2, 14, 8, 8))
	theme.set_stylebox("panel", "TooltipPanel", _box(Color(0.03, 0.05, 0.09, 0.96), ACCENT, 1, 6, 8, 4))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_color("font_color", "Label", INK)
	# Sliders and progress
	var track := _box(Color(0.04, 0.07, 0.12, 1.0), LINE, 1, 4, 0, 3)
	var fill := _box(ACCENT_DARK, ACCENT, 1, 4, 0, 3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, ACCENT, 1, 4, 0, 3))
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	# Thin, rounded scrollbars
	var scroll := _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 4, 3, 3)
	var grab := _box(Color(MUTED, 0.35), Color(0, 0, 0, 0), 0, 4, 3, 3)
	var grab_hover := _box(Color(ACCENT, 0.7), Color(0, 0, 0, 0), 0, 4, 3, 3)
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, scroll)
		theme.set_stylebox("grabber", kind, grab)
		theme.set_stylebox("grabber_highlight", kind, grab_hover)
		theme.set_stylebox("grabber_pressed", kind, grab_hover)
	# Check buttons / boxes keep Godot icons, just with readable text.
	for kind in ["CheckBox", "CheckButton", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", kind, INK)
		theme.set_color("font_hover_color", kind, Color.WHITE)
		theme.set_color("font_pressed_color", kind, Color.WHITE)
	theme.set_stylebox("normal", "OptionButton", _box(RAISED, LINE))
	theme.set_stylebox("hover", "OptionButton", _box(RAISED_HOVER, ACCENT))
	theme.set_stylebox("pressed", "OptionButton", _box(ACCENT_DARK, ACCENT))
	theme.set_stylebox("focus", "OptionButton", focus)
	var error := ResourceSaver.save(theme, "res://ui/theme/gravity_theme.tres")
	print("THEME_SAVED error=%d" % error)
	quit(error)
