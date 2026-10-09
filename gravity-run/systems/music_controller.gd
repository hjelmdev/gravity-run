extends Node

const MUSIC_STREAM: AudioStream = preload("res://assets/audio/music/arcade_rush_96k.ogg")
const MUSIC_BUS := "Music"
const MAX_USER_GAIN := 0.35

var _player: AudioStreamPlayer
var _context_tween: Tween
var _last_round_id := ""
var _menu_start_pending := false
var _autoplay_probe_position := -1.0
var _autoplay_last_retry_msec := -10000
var _pause_position := 0.0
var _pause_position_valid := false

const AUTOPLAY_STALL_RETRY_MSEC := 1200

static func music_gain_for_setting(value: float) -> float:
	var normalized := clampf(value, 0.0, 1.0)
	return MAX_USER_GAIN * normalized * normalized

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
	PlayerProfile.music_enabled_changed.connect(_on_music_enabled_changed)
	_apply_user_volume()
	if PlayerProfile.music_enabled:
		_start_playback_if_needed()
		enter_menu()

func _process(_delta: float) -> void:
	if not _menu_start_pending or not PlayerProfile.music_enabled or not is_instance_valid(_player) or not _player.playing:
		return
	var position := _player.get_playback_position()
	if _autoplay_probe_position < 0.0:
		_autoplay_probe_position = position
		return
	var stream_length := _player.stream.get_length() if _player.stream != null else 0.0
	var advanced := position >= _autoplay_probe_position + 0.04
	var looped := stream_length > 0.0 and position + 0.25 < _autoplay_probe_position
	if advanced or looped:
		# A moving playback cursor confirms that the autoplay attempt is running.
		# A blocked browser leaves the request pending for a real user gesture.
		_menu_start_pending = false
		_autoplay_probe_position = position

## Audible position (seconds) of a track, compensated for mix latency, or -1
## when that track is not the one playing. Used to keep the run cycle on beat.
func get_audible_position(track: AudioStream) -> float:
	if not is_instance_valid(_player) or track == null or _player.stream != track or not _player.playing or _player.stream_paused:
		return -1.0
	return maxf(_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency(), 0.0)

## Menus always use the default track.
func use_menu_track() -> void:
	if _use_track(null) and PlayerProfile.music_enabled:
		_start_playback_if_needed()

func _use_track(track: AudioStream) -> bool:
	var target := track if track != null else MUSIC_STREAM
	if not is_instance_valid(_player) or _player.stream == target:
		return false
	if target is AudioStreamOggVorbis:
		(target as AudioStreamOggVorbis).loop = true
	_player.stop()
	_player.stream = target
	_pause_position_valid = false
	return true

func enter_menu() -> void:
	if not PlayerProfile.music_enabled:
		_stop_for_disabled_setting()
		return
	_cancel_context_fade()
	_player.stream_paused = false
	if not _player.playing:
		_start_playback_if_needed()
	_set_context_gain(1.0, 0.0)

func prepare_round() -> void:
	if not PlayerProfile.music_enabled:
		_stop_for_disabled_setting()
		return
	_cancel_context_fade()
	if _player.playing:
		_context_tween = create_tween()
		_context_tween.tween_property(_player, "volume_db", -50.0, 0.25)
		_context_tween.tween_callback(_player.stop)

## Rounds may bring their own track (campaign worlds); null means the
## default music. Changing track restarts playback from the top.
func start_round(round_id: String, track: AudioStream = null) -> void:
	if not PlayerProfile.music_enabled or round_id.is_empty() or round_id == _last_round_id:
		return
	_last_round_id = round_id
	_cancel_context_fade()
	_use_track(track)
	_player.stream_paused = false
	if not _player.playing:
		_player.volume_db = -50.0
		_apply_user_volume()
		_player.play(0.0)
		_menu_start_pending = OS.has_feature("web")
		_autoplay_probe_position = _player.get_playback_position() if _menu_start_pending else -1.0
		_set_context_gain(1.0, 0.10)

## Endless runs change music with the biome: a short fade out, the new track
## from the top, a fade back in. null is the default round music.
func switch_track(track: AudioStream, fade_seconds := 0.8) -> void:
	var target := track if track != null else MUSIC_STREAM
	if not PlayerProfile.music_enabled or not is_instance_valid(_player) or _player.stream == target:
		return
	_cancel_context_fade()
	_context_tween = create_tween()
	_context_tween.tween_property(_player, "volume_db", -50.0, fade_seconds * 0.5)
	_context_tween.tween_callback(func() -> void:
		_use_track(track)
		_player.stream_paused = false
		_player.play(0.0))
	_context_tween.tween_property(_player, "volume_db", 0.0, fade_seconds * 0.5)

func set_stream_paused(paused: bool) -> void:
	if not is_instance_valid(_player):
		return
	if paused:
		if PlayerProfile.music_enabled and _player.playing:
			_pause_position = maxf(_player.get_playback_position(), 0.0)
			_pause_position_valid = true
		else:
			_pause_position_valid = false
		_player.stream_paused = true
		return
	_player.stream_paused = false
	if not PlayerProfile.music_enabled:
		_pause_position_valid = false
		return
	if not _player.playing and _pause_position_valid:
		# Some web audio backends stop the stream when their context is suspended.
		# Resume from the saved cursor without issuing a new round/start identity.
		_player.play(_pause_position)
		_apply_user_volume()
		if OS.has_feature("web"):
			_menu_start_pending = _player.playing
			_autoplay_probe_position = _player.get_playback_position() if _menu_start_pending else -1.0
	_pause_position_valid = false

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
	var volume := music_gain_for_setting(float(PlayerProfile.music_volume))
	AudioServer.set_bus_mute(bus_index, not PlayerProfile.music_enabled or volume <= 0.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.0001)))

func _on_user_volume_changed(_value: float) -> void:
	_apply_user_volume()

func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") or not PlayerProfile.music_enabled:
		return
	var pressed := false
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		pressed = event.pressed
	if not pressed:
		return
	# A browser can report AudioStreamPlayer.playing while its AudioContext is
	# suspended. Retry a stalled autoplay request from the trusted gesture itself.
	_retry_blocked_autoplay_from_gesture()

func _retry_blocked_autoplay_from_gesture() -> void:
	if not _menu_start_pending or not PlayerProfile.music_enabled or Time.get_ticks_msec() - _autoplay_last_retry_msec < AUTOPLAY_STALL_RETRY_MSEC:
		return
	_autoplay_last_retry_msec = Time.get_ticks_msec()
	_start_playback_if_needed(true)

func _start_playback_if_needed(retry_blocked_autoplay: bool = false) -> void:
	if not PlayerProfile.music_enabled or (_player.playing and not retry_blocked_autoplay):
		return
	if _player.playing:
		_player.stop()
	_player.volume_db = 0.0
	_apply_user_volume()
	_player.stream_paused = false
	_player.play(0.0)
	_menu_start_pending = OS.has_feature("web") and _player.playing
	_autoplay_probe_position = _player.get_playback_position() if _menu_start_pending else -1.0

func _cancel_context_fade() -> void:
	if _context_tween != null and _context_tween.is_running():
		_context_tween.kill()
	_context_tween = null

func _on_stream_finished() -> void:
	# Keep playback resilient if a reimport changes the stream's loop flag.
	_start_playback_if_needed()

func _on_music_enabled_changed(enabled: bool) -> void:
	if not enabled:
		_stop_for_disabled_setting()
		_apply_user_volume()
		return
	_apply_user_volume()
	_menu_start_pending = true
	if not _player.playing and get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://ui/main_menu.tscn":
		_start_playback_if_needed()
		_set_context_gain(1.0, 0.0)

func _stop_for_disabled_setting() -> void:
	_cancel_context_fade()
	_menu_start_pending = false
	_pause_position_valid = false
	if is_instance_valid(_player):
		_player.stream_paused = false
		_player.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cancel_context_fade()
