extends HBoxContainer

var _value_label: Label
var _slider: HSlider

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = tr("Music volume")
	title.accessibility_name = tr("Music volume")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title)
	_value_label = Label.new()
	_value_label.custom_minimum_size.x = 44.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size.x = 108.0
	_slider.accessibility_name = tr("Music volume")
	_slider.tooltip_text = tr("Music volume")
	_slider.value_changed.connect(_on_value_changed)
	_slider.drag_ended.connect(func(_changed: bool) -> void: PlayerProfile.flush_settings())
	_slider.focus_exited.connect(func() -> void: PlayerProfile.flush_settings())
	add_child(_slider)
	_sync_value(float(PlayerProfile.music_volume) * 100.0)
	PlayerProfile.music_volume_changed.connect(func(value: float) -> void: _sync_value(value * 100.0))

func _exit_tree() -> void:
	if PlayerProfile != null:
		PlayerProfile.flush_settings()

func _on_value_changed(value: float) -> void:
	_sync_value(value)
	PlayerProfile.set_music_volume(value / 100.0)

func _sync_value(value: float) -> void:
	if is_instance_valid(_slider):
		_slider.set_value_no_signal(value)
	if is_instance_valid(_value_label):
		_value_label.text = "%d%%" % roundi(value)
		_value_label.accessibility_name = "%s %s" % [tr("Music volume"), _value_label.text]
