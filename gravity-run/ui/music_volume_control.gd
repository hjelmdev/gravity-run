extends VBoxContainer

var _music_value_label: Label
var _music_slider: HSlider
var _music_enabled_button: CheckButton
var _sfx_value_label: Label
var _sfx_slider: HSlider
var _sfx_enabled_button: CheckButton

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	add_child(music_row)
	var music_title := Label.new()
	music_title.text = tr("Music volume")
	music_title.accessibility_name = tr("Music volume")
	music_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_child(music_title)
	_music_value_label = Label.new()
	_music_value_label.custom_minimum_size.x = 44.0
	_music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_row.add_child(_music_value_label)
	_music_slider = _make_slider("Music volume")
	_music_slider.value_changed.connect(_on_music_value_changed)
	music_row.add_child(_music_slider)
	_music_enabled_button = CheckButton.new()
	_music_enabled_button.text = tr("Music enabled")
	_music_enabled_button.toggled.connect(_on_music_enabled_toggled)
	music_row.add_child(_music_enabled_button)

	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 10)
	add_child(sfx_row)
	var sfx_title := Label.new()
	sfx_title.text = tr("Sound effects volume")
	sfx_title.accessibility_name = tr("Sound effects volume")
	sfx_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_child(sfx_title)
	_sfx_value_label = Label.new()
	_sfx_value_label.custom_minimum_size.x = 44.0
	_sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_row.add_child(_sfx_value_label)
	_sfx_slider = _make_slider("Sound effects volume")
	_sfx_slider.value_changed.connect(_on_sfx_value_changed)
	sfx_row.add_child(_sfx_slider)
	_sfx_enabled_button = CheckButton.new()
	_sfx_enabled_button.text = tr("Sound effects enabled")
	_sfx_enabled_button.toggled.connect(_on_sfx_enabled_toggled)
	sfx_row.add_child(_sfx_enabled_button)

	_sync_music_volume(PlayerProfile.music_volume)
	_sync_music_enabled(PlayerProfile.music_enabled)
	_sync_sfx_volume(PlayerProfile.sfx_volume)
	_sync_sfx_enabled(PlayerProfile.sfx_enabled)
	PlayerProfile.music_volume_changed.connect(_sync_music_volume)
	PlayerProfile.music_enabled_changed.connect(_sync_music_enabled)
	PlayerProfile.sfx_volume_changed.connect(_sync_sfx_volume)
	PlayerProfile.sfx_enabled_changed.connect(_sync_sfx_enabled)

func _exit_tree() -> void:
	if PlayerProfile != null:
		if PlayerProfile.music_volume_changed.is_connected(_sync_music_volume): PlayerProfile.music_volume_changed.disconnect(_sync_music_volume)
		if PlayerProfile.music_enabled_changed.is_connected(_sync_music_enabled): PlayerProfile.music_enabled_changed.disconnect(_sync_music_enabled)
		if PlayerProfile.sfx_volume_changed.is_connected(_sync_sfx_volume): PlayerProfile.sfx_volume_changed.disconnect(_sync_sfx_volume)
		if PlayerProfile.sfx_enabled_changed.is_connected(_sync_sfx_enabled): PlayerProfile.sfx_enabled_changed.disconnect(_sync_sfx_enabled)
		PlayerProfile.flush_settings()

func _make_slider(accessible_name: String) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 108.0
	slider.accessibility_name = tr(accessible_name)
	slider.tooltip_text = tr(accessible_name)
	slider.drag_ended.connect(func(_changed: bool) -> void: PlayerProfile.flush_settings())
	slider.focus_exited.connect(func() -> void: PlayerProfile.flush_settings())
	return slider

func _on_music_value_changed(value: float) -> void:
	PlayerProfile.set_music_volume(value / 100.0)

func _on_sfx_value_changed(value: float) -> void:
	PlayerProfile.set_sfx_volume(value / 100.0)

func _on_music_enabled_toggled(enabled: bool) -> void:
	PlayerProfile.set_music_enabled(enabled)

func _on_sfx_enabled_toggled(enabled: bool) -> void:
	PlayerProfile.set_sfx_enabled(enabled)

func _sync_music_volume(value: float) -> void:
	_sync_slider(_music_slider, _music_value_label, value)

func _sync_sfx_volume(value: float) -> void:
	_sync_slider(_sfx_slider, _sfx_value_label, value)

func _sync_slider(slider: HSlider, label: Label, value: float) -> void:
	if is_instance_valid(slider): slider.set_value_no_signal(value * 100.0)
	if is_instance_valid(label):
		label.text = "%d%%" % roundi(value * 100.0)
		label.accessibility_name = "%s %s" % [tr(slider.accessibility_name), label.text]

func _sync_music_enabled(enabled: bool) -> void:
	if is_instance_valid(_music_enabled_button): _music_enabled_button.set_pressed_no_signal(enabled)

func _sync_sfx_enabled(enabled: bool) -> void:
	if is_instance_valid(_sfx_enabled_button): _sfx_enabled_button.set_pressed_no_signal(enabled)
