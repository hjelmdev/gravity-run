extends Node
## Small shared pool for short, interchangeable gameplay sound effects.

signal event_started(event_name: String, event_key: String)

const SFX_BUS := "SFX"
const VOICE_LIMIT := 8
## The low voiced ouff needs more level than the bright pickup/flip sounds.
const EVENT_GAIN_DB: Dictionary = {"death": 8.0}
const STREAMS: Dictionary = {
	"coin": preload("res://assets/audio/sfx/coin.wav"),
	"gravity_flip": preload("res://assets/audio/sfx/gravity_flip.wav"),
	"barrel_destroy": preload("res://assets/audio/sfx/barrel_destroy.wav"),
	"rock_impact": preload("res://assets/audio/sfx/rock_impact.wav"),
	"ghost_warning": preload("res://assets/audio/sfx/ghost_warning.wav"),
	"death": preload("res://assets/audio/sfx/death.wav"),
}

var _voices: Array[AudioStreamPlayer] = []
var _voice_started_msec: Dictionary = {}
var _played_keys: Dictionary = {}
var _round_id := ""
var _death_keys: Dictionary = {}
var _web_unlocked := false

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
	if not audible or get_tree().paused or event_key.is_empty() or not STREAMS.has(event_name):
		return false
	if not bool(PlayerProfile.get("sfx_enabled")) or float(PlayerProfile.get("sfx_volume")) <= 0.0 or (OS.has_feature("web") and not _web_unlocked):
		return false
	if _played_keys.has(event_key):
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
	# Reset for every event: a reused death voice must not boost later pickups.
	voice.volume_db = float(EVENT_GAIN_DB.get(event_name, 0.0))
	voice.play()
	_voice_started_msec[voice_index] = Time.get_ticks_msec()
	event_started.emit(event_name, event_key)
	return true

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
