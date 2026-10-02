extends Control
class_name MusicQuickControl

@export var right_offset := -156.0

var _button: Button
var _panel: PanelContainer
var _enabled: CheckButton
var _slider: HSlider
var _value_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_build_ui()
	_layout()
	PlayerProfile.music_enabled_changed.connect(_sync_enabled)
	PlayerProfile.music_volume_changed.connect(_sync_volume)
	_sync_enabled(PlayerProfile.music_enabled)
	_sync_volume(PlayerProfile.music_volume)

func _build_ui() -> void:
	_button = Button.new()
	_button.text = "♫"
	_button.tooltip_text = tr("Music settings")
	_button.accessibility_name = tr("Music settings")
	_button.custom_minimum_size = Vector2(40.0, 40.0)
	_button.pressed.connect(_toggle_panel)
	add_child(_button)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(224.0, 104.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_enabled = CheckButton.new()
	_enabled.text = tr("Music enabled")
	_enabled.toggled.connect(func(value: bool) -> void: PlayerProfile.set_music_enabled(value))
	column.add_child(_enabled)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text = tr("Music volume")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_value_label = Label.new()
	_value_label.custom_minimum_size.x = 42.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value_label)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 100
	_slider.step = 1
	_slider.custom_minimum_size = Vector2(184.0, 24.0)
	_slider.accessibility_name = tr("Music volume")
	_slider.value_changed.connect(func(value: float) -> void: PlayerProfile.set_music_volume(value / 100.0))
	_slider.drag_ended.connect(func(_changed: bool) -> void: PlayerProfile.flush_settings())
	column.add_child(_slider)

func _layout() -> void:
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = right_offset
	_button.offset_right = right_offset + 40.0
	_button.offset_top = 6.0
	_button.offset_bottom = 46.0
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = right_offset - 184.0
	_panel.offset_right = right_offset + 40.0
	_panel.offset_top = 50.0
	_panel.offset_bottom = 160.0

func set_right_offset(value: float) -> void:
	right_offset = value
	if is_instance_valid(_button):
		_layout()

func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_button.set_pressed_no_signal(_panel.visible)

func _sync_enabled(value: bool) -> void:
	if is_instance_valid(_enabled):
		_enabled.set_pressed_no_signal(value)
	if is_instance_valid(_button):
		_button.text = "♫" if value else "♪"
		_button.tooltip_text = tr("Music settings") + (" — " + tr("On") if value else " — " + tr("Off"))

func _sync_volume(value: float) -> void:
	if is_instance_valid(_slider):
		_slider.set_value_no_signal(value * 100.0)
	if is_instance_valid(_value_label):
		_value_label.text = "%d%%" % roundi(value * 100.0)
