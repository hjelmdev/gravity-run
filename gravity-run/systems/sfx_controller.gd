extends Node
## Small shared pool for short, interchangeable gameplay sound effects.

signal event_started(event_name: String, event_key: String)

const SFX_BUS := "SFX"
const VOICE_LIMIT := 8
const DIAGNOSTIC_EVENT_LIMIT := 128
const DIAGNOSTIC_GAP_LIMIT := 64
const DIAGNOSTIC_COIN_LIMIT := 48
const DIAGNOSTIC_GAP_THRESHOLD_USEC := 50_000
const STREAMS: Dictionary = {
	"coin": preload("res://assets/audio/sfx/coin.wav"),
	"gravity_flip": preload("res://assets/audio/sfx/gravity_flip.wav"),
	"barrel_destroy": preload("res://assets/audio/sfx/barrel_destroy.wav"),
	"rock_impact": preload("res://assets/audio/sfx/rock_impact.wav"),
	"ghost_warning": preload("res://assets/audio/sfx/ghost_warning.wav"),
	"death": preload("res://assets/audio/sfx/death.mp3"),
	"gravity_star": preload("res://assets/audio/sfx/gravity_star.wav"),
	# Cave (tools/audio/generate_cave_audio.py). Scripted features play the
	# first two by name; crystal_chime replaces gravity_star on cave stages.
	"icicle_crack": preload("res://assets/audio/sfx/icicle_crack.wav"),
	"cave_in_rumble": preload("res://assets/audio/sfx/cave_in_rumble.wav"),
	"crystal_chime": preload("res://assets/audio/sfx/crystal_chime.wav"),
	# Cave boss (giant bat): lock-on screech and the big icicle breaking.
	"cave_bat_screech": preload("res://assets/audio/sfx/cave_bat_screech.wav"),
	"cave_icicle_shatter": preload("res://assets/audio/sfx/cave_icicle_shatter.wav"),
	# Haunted Woods (tools/audio/generate_haunted_audio.py). Scripted features
	# play these by name; haunted_star replaces gravity_star on haunted stages.
	"ghost_whistle": preload("res://assets/audio/sfx/ghost_whistle.wav"),
	"hand_scrape": preload("res://assets/audio/sfx/hand_scrape.wav"),
	"lantern_chime": preload("res://assets/audio/sfx/lantern_chime.wav"),
	"haunted_star": preload("res://assets/audio/sfx/haunted_star.wav"),
	"ghost_king_laugh": preload("res://assets/audio/sfx/ghost_king_laugh.wav"),
}

var _voices: Array[AudioStreamPlayer] = []
var _voice_started_msec: Dictionary = {}
var _played_keys: Dictionary = {}
var _round_id := ""
var _death_keys: Dictionary = {}
var _web_unlocked := false
var _diagnostic_capture_active := false
var _diagnostic_capture_started_usec := -1
var _diagnostic_audio_events: Array[Dictionary] = []
var _diagnostic_frame_gaps: Array[Dictionary] = []
var _diagnostic_coin_contacts: Array[Dictionary] = []
var _diagnostic_last_callback_usec: Dictionary = {}
var _diagnostic_audio_server_at_start: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_web_unlocked = not OS.has_feature("web")
	for index in range(VOICE_LIMIT):
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxVoice%02d" % index
		voice.bus = SFX_BUS
		voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(voice)
		_voices.append(voice)
		voice.finished.connect(_on_voice_finished.bind(index))
	PlayerProfile.sfx_volume_changed.connect(_apply_settings)
	PlayerProfile.sfx_enabled_changed.connect(_apply_settings)
	_apply_settings()

func _input(event: InputEvent) -> void:
	if _web_unlocked:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
		# This only enables future SFX after a real engine input gesture. Missed
		# events are discarded; nothing is queued behind the browser audio lock.
		_web_unlocked = true

func begin_round(round_id: String) -> void:
	if round_id == _round_id:
		return
	stop_all()
	_played_keys.clear()
	_death_keys.clear()
	_round_id = round_id

## Death is a terminal event, never replayed by repeated reports or after unmute.
func play_death(round_id: String, player_key: String) -> bool:
	if round_id.is_empty() or round_id != _round_id or player_key.is_empty():
		return false
	var key := "%s|death|%s" % [round_id, player_key]
	if _death_keys.has(key):
		return false
	_death_keys[key] = true
	return play_event("death", key)

func play_event(event_name: String, event_key: String, audible: bool = true) -> bool:
	var request_usec := Time.get_ticks_usec() if _diagnostic_capture_active else -1
	var rejection_reason := ""
	if not audible: rejection_reason = "outside_audible_range"
	elif get_tree().paused: rejection_reason = "tree_paused"
	elif event_key.is_empty(): rejection_reason = "empty_event_key"
	elif not STREAMS.has(event_name): rejection_reason = "unknown_event"
	elif not bool(PlayerProfile.get("sfx_enabled")) or float(PlayerProfile.get("sfx_volume")) <= 0.0: rejection_reason = "disabled_or_zero_volume"
	elif OS.has_feature("web") and not _web_unlocked: rejection_reason = "web_audio_not_unlocked"
	elif _played_keys.has(event_key): rejection_reason = "duplicate_key"
	if not rejection_reason.is_empty():
		_record_audio_request(request_usec, event_name, event_key, false, rejection_reason, -1)
		return false
	_played_keys[event_key] = true
	while _played_keys.size() > 768:
		_played_keys.erase(_played_keys.keys()[0])
	var voice_index := -1
	for index in range(_voices.size()):
		if not _voices[index].playing:
			voice_index = index
			break
	if voice_index < 0:
		# Reuse the oldest active voice; the pool never grows during play.
		voice_index = 0
		for index in range(1, _voices.size()):
			if int(_voice_started_msec.get(index, 0)) < int(_voice_started_msec.get(voice_index, 0)):
				voice_index = index
	var voice := _voices[voice_index]
	voice.stop()
	voice.stream = STREAMS[event_name]
	# Recorded effects use their original level and the user's shared SFX gain.
	voice.volume_db = 0.0
	voice.play()
	_voice_started_msec[voice_index] = Time.get_ticks_msec()
	_record_audio_request(request_usec, event_name, event_key, true, "", voice_index)
	event_started.emit(event_name, event_key)
	return true

func begin_diagnostic_capture() -> void:
	_diagnostic_capture_active = true
	_diagnostic_capture_started_usec = Time.get_ticks_usec()
	_diagnostic_audio_events.clear()
	_diagnostic_frame_gaps.clear()
	_diagnostic_coin_contacts.clear()
	_diagnostic_last_callback_usec.clear()
	_diagnostic_audio_server_at_start = _audio_server_snapshot()

func finish_diagnostic_capture() -> Dictionary:
	if not _diagnostic_capture_active:
		return {"enabled": false}
	var ended_usec := Time.get_ticks_usec()
	var result := {
		"enabled": true,
		"started_monotonic_usec": _diagnostic_capture_started_usec,
		"ended_monotonic_usec": ended_usec,
		"duration_usec": maxi(ended_usec - _diagnostic_capture_started_usec, 0),
		"audio_server_at_start": _diagnostic_audio_server_at_start.duplicate(true),
		"audio_server_at_end": _audio_server_snapshot(),
		"events": _diagnostic_audio_events.duplicate(true),
		"long_callback_gaps": _diagnostic_frame_gaps.duplicate(true),
		"coin_sweeps": _diagnostic_coin_contacts.duplicate(true),
		"limits": {"events": DIAGNOSTIC_EVENT_LIMIT, "gaps": DIAGNOSTIC_GAP_LIMIT, "coin_sweeps": DIAGNOSTIC_COIN_LIMIT}
	}
	_diagnostic_capture_active = false
	_diagnostic_last_callback_usec.clear()
	return result

func diagnostic_capture_active() -> bool:
	return _diagnostic_capture_active

func record_callback_timing(callback_name: String, delta_seconds: float, simulation_tick: int = -1) -> void:
	if not _diagnostic_capture_active:
		return
	var now_usec := Time.get_ticks_usec()
	var previous_usec := int(_diagnostic_last_callback_usec.get(callback_name, now_usec))
	_diagnostic_last_callback_usec[callback_name] = now_usec
	var gap_usec := now_usec - previous_usec
	if gap_usec < DIAGNOSTIC_GAP_THRESHOLD_USEC or _diagnostic_frame_gaps.size() >= DIAGNOSTIC_GAP_LIMIT:
		return
	_diagnostic_frame_gaps.append({"at_monotonic_usec": now_usec, "callback": callback_name, "interval_usec": gap_usec, "engine_delta_usec": int(maxf(delta_seconds, 0.0) * 1_000_000.0), "simulation_tick": simulation_tick})

func record_coin_sweep(source: String, details: Dictionary) -> void:
	if not _diagnostic_capture_active or _diagnostic_coin_contacts.size() >= DIAGNOSTIC_COIN_LIMIT:
		return
	var row := details.duplicate(true)
	row["at_monotonic_usec"] = Time.get_ticks_usec()
	row["source"] = source
	_diagnostic_coin_contacts.append(row)

func _record_audio_request(request_usec: int, event_name: String, event_key: String, accepted: bool, reason: String, voice_index: int) -> void:
	if request_usec < 0 or not _diagnostic_capture_active or _diagnostic_audio_events.size() >= DIAGNOSTIC_EVENT_LIMIT:
		return
	_diagnostic_audio_events.append({
		"request_monotonic_usec": request_usec,
		"event_type": event_name,
		"event_key": event_key,
		"accepted": accepted,
		"rejection_reason": reason,
		"voice_index": voice_index,
		"player_playback_type": int(_voices[voice_index].playback_type) if voice_index >= 0 and voice_index < _voices.size() else -1,
		"audio_context_state": "not_exposed_by_godot_web_driver" if OS.has_feature("web") else "not_applicable",
		"audio_server_since_mix_usec": int(AudioServer.get_time_since_last_mix() * 1_000_000.0),
		"audio_server_until_mix_usec": int(AudioServer.get_time_to_next_mix() * 1_000_000.0)
	})

func _audio_server_snapshot() -> Dictionary:
	var voice_playback_types: Array[int] = []
	for voice in _voices:
		voice_playback_types.append(int(voice.playback_type) if is_instance_valid(voice) else -1)
	var music_player: Variant = MusicController.get("_player")
	var music_playback_type := -1
	var music_playing := false
	if is_instance_valid(music_player):
		music_playback_type = int(music_player.playback_type)
		music_playing = bool(music_player.playing)
	var snapshot := {
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"time_since_last_mix_usec": int(AudioServer.get_time_since_last_mix() * 1_000_000.0),
		"time_to_next_mix_usec": int(AudioServer.get_time_to_next_mix() * 1_000_000.0),
		"effective_output_latency_usec": int(AudioServer.get_output_latency() * 1_000_000.0),
		"sfx_player_playback_types": voice_playback_types,
		"music_player_playback_type": music_playback_type,
		"music_player_playing": music_playing,
		"web_default_playback_type_setting": str(ProjectSettings.get_setting("audio/general/default_playback_type.web", "engine_default"))
	}
	if OS.has_feature("web"):
		# Godot 4.7.2 keeps AudioContext state in AudioDriverWeb's internal
		# static AudioContext; it exposes effective driver latency via AudioServer,
		# but not the JS AudioContext object or AudioContext.outputTimestamp.
		var bridge_probe: Variant = JavaScriptBridge.eval("(()=>{const p=window.__gravityRunAudioContextProbe;return typeof p==='function'?JSON.stringify(p()):JSON.stringify({context_state:'not_exposed_by_godot_driver',output_timestamp_available:false,custom_probe_available:false})})()", true)
		var parsed: Variant = JSON.parse_string(str(bridge_probe))
		snapshot["web_audio_probe"] = parsed if parsed is Dictionary else {"context_state": "probe_unavailable", "output_timestamp_available": false}
	else:
		snapshot["web_audio_probe"] = {"context_state": "not_applicable", "output_timestamp_available": false}
	return snapshot

func clear_event_key(event_key: String) -> void:
	_played_keys.erase(event_key)

func stop_all() -> void:
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
	_voice_started_msec.clear()

func _apply_settings(_value: Variant = null) -> void:
	var bus := AudioServer.get_bus_index(SFX_BUS)
	if bus < 0:
		return
	var volume := clampf(float(PlayerProfile.get("sfx_volume")), 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume * volume, 0.0001)))
	var enabled := bool(PlayerProfile.get("sfx_enabled")) and volume > 0.0
	AudioServer.set_bus_mute(bus, not enabled)
	if not enabled:
		stop_all()

func _on_voice_finished(index: int) -> void:
	_voice_started_msec.erase(index)
