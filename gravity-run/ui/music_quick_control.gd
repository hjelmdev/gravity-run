extends Control
class_name MusicQuickControl

const ActionIconScript := preload("res://ui/action_icon.gd")
const ChevronIconScript := preload("res://ui/chevron_icon.gd")

@export var right_offset := -156.0
@export var top_offset := 6.0

var _button: Button
var _expand_button: Button
var _speaker_icon: Control
var _panel: PanelContainer
var _slider: HSlider
var _value_label: Label
var _close_timer: Timer
var _touch_pinned := false
var _profile: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 8
	_build_ui()
	_layout()
	_close_timer = Timer.new()
	_close_timer.one_shot = true
	_close_timer.wait_time = 0.18
	_close_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_close_timer.timeout.connect(_on_close_timeout)
	add_child(_close_timer)
	_profile = get_node_or_null("/root/PlayerProfile")
	if is_instance_valid(_profile):
		_profile.connect("music_enabled_changed", _sync_enabled)
		_profile.connect("music_volume_changed", _sync_volume)
	get_viewport().size_changed.connect(_layout)
	if is_instance_valid(_profile):
		_sync_enabled(bool(_profile.get("music_enabled")))
		_sync_volume(float(_profile.get("music_volume")))

func _build_ui() -> void:
	_button = Button.new()
	_button.name = "MusicToggle"
	_button.text = ""
	_button.tooltip_text = tr("Mute music")
	_button.accessibility_name = tr("Mute music")
	_button.focus_mode = Control.FOCUS_ALL
	_button.custom_minimum_size = Vector2(44.0, 40.0)
	_button.pressed.connect(_toggle_music)
	add_child(_button)
	_speaker_icon = Control.new()
	_speaker_icon.name = "SpeakerIcon"
	_speaker_icon.set_script(ActionIconScript)
	_speaker_icon.set("icon_name", "music")
	_speaker_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speaker_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_speaker_icon)

	_expand_button = Button.new()
	_expand_button.name = "MusicVolumeExpand"
	_expand_button.text = ""
	_expand_button.tooltip_text = tr("Show music volume")
	_expand_button.accessibility_name = tr("Show music volume")
	_expand_button.focus_mode = Control.FOCUS_ALL
	_expand_button.custom_minimum_size = Vector2(30.0, 40.0)
	_expand_button.pressed.connect(_toggle_slider_panel)
	_expand_button.mouse_entered.connect(_on_expand_mouse_entered)
	_expand_button.mouse_exited.connect(_on_control_mouse_exited)
	_expand_button.focus_entered.connect(_on_expand_focus_entered)
	_expand_button.focus_exited.connect(_on_control_focus_exited)
	add_child(_expand_button)
	var chevron := Control.new()
	chevron.name = "ChevronIcon"
	chevron.set_script(ChevronIconScript)
	chevron.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expand_button.add_child(chevron)

	_panel = PanelContainer.new()
	_panel.name = "MusicVolumePopover"
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(230.0, 72.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_entered.connect(_on_volume_panel_mouse_entered)
	_panel.mouse_exited.connect(_on_control_mouse_exited)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text = tr("Music volume")
	title.accessibility_name = tr("Music volume")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_value_label = Label.new()
	_value_label.name = "MusicVolumeValue"
	_value_label.custom_minimum_size.x = 42.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_value_label)
	_slider = HSlider.new()
	_slider.name = "MusicVolumeSlider"
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 1.0
	_slider.focus_mode = Control.FOCUS_ALL
	_slider.custom_minimum_size = Vector2(202.0, 24.0)
	_slider.accessibility_name = tr("Music volume")
	_slider.tooltip_text = tr("Music volume")
	_slider.value_changed.connect(_on_volume_changed)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		if is_instance_valid(_profile):
			_profile.call("flush_settings")
	)
	_slider.focus_entered.connect(_on_volume_panel_mouse_entered)
	_slider.focus_exited.connect(_on_control_focus_exited)
	column.add_child(_slider)

func _layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not is_instance_valid(_button):
		return
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = right_offset + 4.0
	_button.offset_right = right_offset + 48.0
	_button.offset_top = top_offset
	_button.offset_bottom = top_offset + 40.0
	_expand_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_expand_button.offset_left = right_offset - 30.0
	_expand_button.offset_right = right_offset + 2.0
	_expand_button.offset_top = top_offset
	_expand_button.offset_bottom = top_offset + 40.0
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = right_offset - 226.0
	_panel.offset_right = right_offset + 4.0
	_panel.offset_top = top_offset + 44.0
	_panel.offset_bottom = top_offset + 120.0

func set_right_offset(value: float) -> void:
	right_offset = value
	if is_instance_valid(_button):
		_layout()

func set_toolbar_top_offset(value: float) -> void:
	top_offset = value
	if is_instance_valid(_button):
		_layout()

func _toggle_music() -> void:
	if not is_instance_valid(_profile):
		return
	_profile.call("set_music_enabled", not bool(_profile.get("music_enabled")))
	_profile.call("flush_settings")

func _toggle_slider_panel() -> void:
	_touch_pinned = not _touch_pinned
	_close_timer.stop()
	_panel.visible = _touch_pinned or not _panel.visible
	if not _panel.visible:
		_touch_pinned = false
	_expand_button.set_pressed_no_signal(_panel.visible)

func _on_volume_changed(value: float) -> void:
	if is_instance_valid(_profile):
		_profile.call("set_music_volume", value / 100.0)

func _sync_enabled(value: bool) -> void:
	if is_instance_valid(_speaker_icon):
		_speaker_icon.set("music_enabled", value)
		_speaker_icon.queue_redraw()
	if is_instance_valid(_button):
		_button.tooltip_text = tr("Mute music") if value else tr("Enable music")
		_button.accessibility_name = _button.tooltip_text

func _sync_volume(value: float) -> void:
	if is_instance_valid(_slider):
		_slider.set_value_no_signal(value * 100.0)
	if is_instance_valid(_value_label):
		_value_label.text = "%d%%" % roundi(value * 100.0)

func _on_expand_mouse_entered() -> void:
	_close_timer.stop()
	if not DisplayServer.is_touchscreen_available():
		_panel.visible = true

func _on_volume_panel_mouse_entered() -> void:
	_close_timer.stop()

func _on_control_mouse_exited() -> void:
	_schedule_close()

func _on_expand_focus_entered() -> void:
	_close_timer.stop()
	_panel.visible = true

func _on_control_focus_exited() -> void:
	_schedule_close()

func _schedule_close() -> void:
	if _touch_pinned or _has_control_focus():
		return
	_close_timer.start()

func _on_close_timeout() -> void:
	if _touch_pinned or _has_control_focus() or _pointer_over_controls():
		return
	_panel.visible = false
	_expand_button.set_pressed_no_signal(false)

func _has_control_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused == _button or focused == _expand_button or focused == _slider

func _pointer_over_controls() -> bool:
	var point := get_global_mouse_position()
	return _button.get_global_rect().has_point(point) or _expand_button.get_global_rect().has_point(point) or (_panel.visible and _panel.get_global_rect().has_point(point))
