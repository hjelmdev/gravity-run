extends Control
class_name SharedRunHud

const MusicControlScript := preload("res://ui/music_quick_control.gd")
const IconScript := preload("res://ui/action_icon.gd")

var _coins := 0
var _distance_m := 0
var _show_distance := false
var _title: Label
var _player: Label
var _coin_icon: Control
var _coin_value: Label
var _distance: Label
var _music: Control
var _music_right_offset := -196.0
var _account_profile: Node
var _player_profile: Node

func _ready() -> void:
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout)
	_account_profile = get_node_or_null("/root/PlayerAccountProfile")
	_player_profile = get_node_or_null("/root/PlayerProfile")
	if is_instance_valid(_account_profile) and _account_profile.has_signal("profile_changed"):
		_account_profile.connect("profile_changed", _sync_player)
	if is_instance_valid(_player_profile) and _player_profile.has_signal("profile_changed"):
		_player_profile.connect("profile_changed", _sync_player)
	_sync_player()
	_layout()

func _build() -> void:
	_title = _label("GRAVITY RUN", 17, Color("f4f7ff"))
	_title.name = "RunTitle"
	_title.position = Vector2(20, 5)
	_title.size = Vector2(135, 24)
	add_child(_title)
	_player = _label("", 11, Color("42d6c5"))
	_player.name = "PlayerName"
	_player.position = Vector2(160, 5)
	_player.size = Vector2(138, 24)
	add_child(_player)
	_coin_icon = Control.new()
	_coin_icon.name = "CoinIcon"
	_coin_icon.set_script(IconScript)
	_coin_icon.set("icon_name", "coin")
	_coin_icon.position = Vector2(304, 5)
	_coin_icon.size = Vector2(20, 20)
	_coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_icon.tooltip_text = tr("My coins")
	_coin_icon.accessibility_name = tr("My coins")
	add_child(_coin_icon)
	_coin_value = _label("00", 11, Color("f5d45e"))
	_coin_value.name = "CoinCount"
	_coin_value.position = Vector2(328, 5)
	_coin_value.size = Vector2(52, 22)
	_coin_value.tooltip_text = tr("My coins")
	_coin_value.accessibility_name = tr("My coins")
	add_child(_coin_value)
	_distance = _label("", 15, Color("b8c7dc"))
	_distance.name = "Distance"
	_distance.anchor_left = 1.0
	_distance.anchor_right = 1.0
	_distance.offset_left = -445.0
	_distance.offset_right = -240.0
	_distance.offset_top = 5.0
	_distance.offset_bottom = 28.0
	_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_distance.visible = _show_distance
	add_child(_distance)
	_music = Control.new()
	_music.name = "MusicQuickControl"
	_music.set_script(MusicControlScript)
	_music.set("right_offset", _music_right_offset)
	add_child(_music)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func set_coins(value: int) -> void:
	_coins = maxi(value, 0)
	if is_instance_valid(_coin_value):
		_coin_value.text = "%02d" % _coins

func set_distance_m(value: float) -> void:
	_distance_m = maxi(roundi(value / 10.0), 0)
	if is_instance_valid(_distance):
		_distance.text = tr("DISTANCE  %06d m") % _distance_m

func set_show_distance(value: bool) -> void:
	_show_distance = value
	if is_instance_valid(_distance):
		_distance.visible = value

func set_music_right_offset(value: float) -> void:
	_music_right_offset = value
	if is_instance_valid(_music):
		_music.call("set_right_offset", value)

func _sync_player(_arg1: Variant = null, _arg2: Variant = null) -> void:
	if not is_instance_valid(_player):
		return
	var has_account_profile := is_instance_valid(_account_profile) and bool(_account_profile.get("has_profile"))
	var nickname := str(_account_profile.get("nickname")) if has_account_profile else str(_player_profile.get("leaderboard_name")) if is_instance_valid(_player_profile) else ""
	_player.text = tr("PLAYER: %s") % nickname if not nickname.is_empty() else ""

func _layout() -> void:
	if is_instance_valid(_music):
		_music.call("set_right_offset", _music_right_offset)
