extends CanvasLayer
## Mid-screen campaign callout (new hazard, gravity star, stage intro, boss).
## Same card family as the achievement toast, but centred and coloured per
## kind. It pops in solid, holds briefly and then fades out in one smooth
## curve so the track behind it shows through more and more.

const BannerIconScript := preload("res://campaign/banner_icon.gd")
const POP_IN := 0.12
const HOLD := 0.55
const TOTAL := 2.4
## A newer banner may replace this one once it has been readable this long.
const REPLACEABLE_AFTER := 0.9
const KIND_COLORS := {
	"hazard": Color("ff9f43"),
	"star": Color("f5d45e"),
	"stage": Color("42d6c5"),
	"boss": Color("ff647c"),
}

var _root: Control
var _card: PanelContainer
var _style: StyleBoxFlat
var _icon: Control
var _heading: Label
var _title: Label
var _description: Label
var _content: Control
var _time := -1.0
var _queue: Array[Dictionary] = []

func _ready() -> void:
	layer = 19
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color("18243a", 0.97)
	_style.set_border_width_all(2)
	_style.border_width_top = 5
	_style.set_corner_radius_all(12)
	_style.content_margin_left = 14
	_style.content_margin_right = 18
	_style.content_margin_top = 10
	_style.content_margin_bottom = 10
	_style.shadow_color = Color(0, 0, 0, 0.35)
	_style.shadow_size = 8
	_card.add_theme_stylebox_override("panel", _style)
	_root.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_content = row
	_icon = BannerIconScript.new() as Control
	_icon.custom_minimum_size = Vector2(46, 46)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_heading = _label(11)
	column.add_child(_heading)
	_title = _label(20)
	_title.add_theme_color_override("font_color", Color("edf3ff"))
	column.add_child(_title)
	_description = _label(12)
	_description.add_theme_color_override("font_color", Color("b8c7dc"))
	column.add_child(_description)
	_card.visible = false
	set_process(false)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## kind: "hazard", "star", "stage" or "boss". Text is already translated.
func show_banner(kind: String, heading: String, title: String, description: String = "") -> void:
	var entry := {"kind": kind, "heading": heading, "title": title, "description": description}
	# A newer banner replaces one that has been readable for a moment; at most
	# one waits, so bursts never lag behind play.
	if _time >= 0.0 and _time < REPLACEABLE_AFTER:
		_queue = [entry]
		return
	_queue.clear()
	_present(entry)

func clear() -> void:
	_queue.clear()
	_time = -1.0
	if is_instance_valid(_card):
		_card.visible = false
	set_process(false)

func _present(entry: Dictionary) -> void:
	var accent: Color = KIND_COLORS.get(str(entry.kind), KIND_COLORS.hazard)
	_style.border_color = accent
	_icon.set("kind", str(entry.kind))
	_icon.set("accent", accent)
	_icon.queue_redraw()
	_heading.text = str(entry.heading).to_upper()
	_heading.add_theme_color_override("font_color", accent)
	_title.text = str(entry.title)
	_description.text = str(entry.description)
	_description.visible = not _description.text.is_empty()
	_card.visible = true
	_card.reset_size()
	_time = 0.0
	set_process(true)
	_layout()

func _layout() -> void:
	var view := _root.get_viewport_rect().size
	var card_size := _card.get_combined_minimum_size()
	_card.size = card_size
	_card.position = (view - card_size) * 0.5
	_card.pivot_offset = card_size * 0.5

func _process(delta: float) -> void:
	_time += delta
	if _time >= TOTAL:
		if not _queue.is_empty():
			_present(_queue.pop_front())
			return
		clear()
		return
	if _time >= REPLACEABLE_AFTER and not _queue.is_empty():
		_present(_queue.pop_front())
		return
	var pop := clampf(_time / POP_IN, 0.0, 1.0)
	var scale_value := lerpf(0.82, 1.0, 1.0 - pow(1.0 - pop, 3.0))
	_card.scale = Vector2.ONE * scale_value
	# One continuous ease-out from solid to gone; the card background leaves a
	# little ahead of the text so the words stay readable longest.
	var fade := clampf((_time - HOLD) / (TOTAL - HOLD), 0.0, 1.0)
	var eased := fade * fade * (3.0 - 2.0 * fade)
	var panel_alpha := pow(1.0 - eased, 1.4) * pop
	var text_alpha := (1.0 - eased) * pop
	_card.self_modulate = Color(1, 1, 1, panel_alpha)
	_content.modulate = Color(1, 1, 1, text_alpha)
