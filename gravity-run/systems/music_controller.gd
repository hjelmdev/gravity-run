extends Node

const MUSIC_STREAM: AudioStream = preload("res://assets/audio/music/arcade_rush_96k.ogg")
const MUSIC_BUS := "Music"
const MENU_GAIN := 0.65

var _player: AudioStreamPlayer
var _context_tween: Tween
var _last_round_id := ""
var _web_input_seen := false
var _menu_start_pending := false

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.stream = MUSIC_STREAM
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_player.bus = MUSIC_BUS
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.finished.connect(_on_stream_finished)
	add_child(_player)
	PlayerProfile.music_volume_changed.connect(_on_user_volume_changed)
	_apply_user_volume()
	enter_menu()

func enter_menu() -> void:
	_cancel_context_fade()
	_player.stream_paused = false
	if not _player.playing:
		if OS.has_feature("web") and not _web_input_seen:
			_menu_start_pending = true
			return
		_player.play()
	_menu_start_pending = false
	_set_context_gain(MENU_GAIN, 0.30)

func prepare_round() -> void:
	_cancel_context_fade()
	if _player.playing:
		_player.volume_db = linear_to_db(MENU_GAIN)
		_context_tween = create_tween()
		_context_tween.tween_property(_player, "volume_db", -50.0, 0.25)
		_context_tween.tween_callback(_player.stop)

func start_round(round_id: String) -> void:
	if round_id.is_empty() or round_id == _last_round_id:
		return
	_last_round_id = round_id
	_cancel_context_fade()
	_player.stop()
	_player.volume_db = -50.0
	_player.play(0.0)
	_player.stream_paused = false
	_set_context_gain(1.0, 0.10)

func set_stream_paused(paused: bool) -> void:
	if _player != null and _player.playing:
		_player.stream_paused = paused

func _set_context_gain(gain: float, duration: float) -> void:
	if not _player.playing:
		return
	var target_linear := clampf(gain, 0.0, 1.0)
	var target_db := linear_to_db(maxf(target_linear, 0.0001))
	if target_linear <= 0.0001:
		_player.volume_db = -80.0
		return
	if duration <= 0.0:
		_player.volume_db = target_db
	else:
		_context_tween = create_tween()
		_context_tween.tween_property(_player, "volume_db", target_db, duration)

func _apply_user_volume() -> void:
	if not is_instance_valid(_player):
		return
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_index < 0:
		push_warning("Music bus is missing; music volume cannot be applied.")
		return
	var volume := clampf(float(PlayerProfile.music_volume), 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.0001)))

func _on_user_volume_changed(_value: float) -> void:
	_apply_user_volume()

func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") or _web_input_seen:
		return
	var pressed := false
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		pressed = event.pressed
	if not pressed:
		return
	_web_input_seen = true
	if _menu_start_pending and not _player.playing:
		_player.play(0.0)
		_menu_start_pending = false
		_set_context_gain(MENU_GAIN, 0.10)

func _cancel_context_fade() -> void:
	if _context_tween != null and _context_tween.is_running():
		_context_tween.kill()
	_context_tween = null

func _on_stream_finished() -> void:
	# Keep playback resilient if a reimport changes the stream's loop flag.
	_player.play(0.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cancel_context_fade()
