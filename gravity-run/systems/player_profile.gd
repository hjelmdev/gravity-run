extends Node

signal music_volume_changed(value: float)
signal music_enabled_changed(enabled: bool)

const DEFAULT_CHARACTER_STATS := preload("res://characters/runner_stats.tres")
const SAVE_PATH := "user://gravity_run_profile.cfg"

var best_distance_m := 0.0
var flip_control := "keyboard"
var leaderboard_name := ""
var language := ""
const DEFAULT_MUSIC_VOLUME := 0.25
var music_volume := DEFAULT_MUSIC_VOLUME
var music_enabled := true
var character_stats: Resource
var _saved_challenges: Array[Dictionary] = []
var _music_save_timer: Timer

func _ready() -> void:
	character_stats = DEFAULT_CHARACTER_STATS.duplicate(true)
	flip_control = "swipe" if DisplayServer.is_touchscreen_available() else "keyboard"
	_load_profile()
	_music_save_timer = Timer.new()
	_music_save_timer.one_shot = true
	_music_save_timer.wait_time = 0.45
	_music_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_save_timer.timeout.connect(_save_profile)
	add_child(_music_save_timer)
	if language.is_empty():
		language = "en" if OS.get_locale_language().to_lower() == "en" else "sv"
	TranslationServer.set_locale(language)

func get_character_stats() -> Resource:
	return character_stats

func set_character_stats(stats: Resource) -> bool:
	if stats == null or not stats.has_method("validate") or not str(stats.call("validate")).is_empty():
		return false
	character_stats = stats.duplicate(true)
	return true

func record_distance(distance_m: float) -> void:
	if distance_m <= best_distance_m:
		return
	best_distance_m = distance_m
	_save_profile()

func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	best_distance_m = float(config.get_value("profile", "best_distance_m", 0.0))
	leaderboard_name = str(config.get_value("profile", "leaderboard_name", ""))
	var saved_challenges: Variant = config.get_value("profile", "saved_challenges", [])
	_saved_challenges.clear()
	if saved_challenges is Array:
		for entry in saved_challenges:
			if entry is Dictionary and _is_valid_challenge_code(str(entry.get("challenge_code", ""))):
				_saved_challenges.append(entry.duplicate(true))
	language = str(config.get_value("settings", "language", ""))
	if language not in ["sv", "en"]:
		language = "en" if OS.get_locale_language().to_lower() == "en" else "sv"
	var default_control := "swipe" if DisplayServer.is_touchscreen_available() else "keyboard"
	flip_control = str(config.get_value("settings", "flip_control", default_control))
	if not _is_valid_flip_control(flip_control):
		var legacy_control := str(config.get_value("settings", "mobile_flip_control", default_control))
		flip_control = legacy_control if DisplayServer.is_touchscreen_available() and legacy_control in ["swipe", "tap"] else default_control
	var saved_music_volume: Variant = config.get_value("settings", "music_volume", DEFAULT_MUSIC_VOLUME)
	music_volume = normalize_music_volume(saved_music_volume)
	music_enabled = bool(config.get_value("settings", "music_enabled", true))

static func normalize_music_volume(value: Variant, default_value: float = DEFAULT_MUSIC_VOLUME) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return default_value
	return clampf(float(value), 0.0, 1.0)

func set_flip_control(mode: String) -> void:
	if not _is_valid_flip_control(mode):
		return
	flip_control = mode
	_save_profile()

func set_language(value: String) -> void:
	if value not in ["sv", "en"] or language == value:
		return
	language = value
	TranslationServer.set_locale(language)
	_save_profile()

func set_music_volume(value: float) -> void:
	if not is_finite(value):
		return
	var normalized := clampf(value, 0.0, 1.0)
	if is_equal_approx(music_volume, normalized):
		return
	music_volume = normalized
	music_volume_changed.emit(music_volume)
	if is_instance_valid(_music_save_timer):
		_music_save_timer.start()
	else:
		_save_profile()

func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled:
		return
	music_enabled = enabled
	music_enabled_changed.emit(music_enabled)
	_save_profile()

func flush_settings() -> void:
	if is_instance_valid(_music_save_timer):
		_music_save_timer.stop()
	_save_profile()

func _is_valid_flip_control(mode: String) -> bool:
	return mode in ["keyboard", "mouse", "swipe", "tap"]

func _save_profile() -> void:
	var config := ConfigFile.new()
	# Preserve settings and profile keys written by other systems or newer builds.
	config.load(SAVE_PATH)
	config.set_value("profile", "best_distance_m", best_distance_m)
	config.set_value("profile", "leaderboard_name", leaderboard_name)
	config.set_value("profile", "saved_challenges", _saved_challenges)
	config.set_value("settings", "flip_control", flip_control)
	config.set_value("settings", "language", language)
	config.set_value("settings", "music_volume", music_volume)
	config.set_value("settings", "music_enabled", music_enabled)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save Gravity Run profile (error %s)." % error)

func set_leaderboard_name(value: String) -> void:
	leaderboard_name = value.strip_edges().left(16)
	_save_profile()

func remember_seed_challenge(challenge_code: String, challenge_name: String, creator_name: String) -> void:
	var code := challenge_code.strip_edges().to_upper()
	if not _is_valid_challenge_code(code):
		return
	for index in range(_saved_challenges.size()):
		if str(_saved_challenges[index].get("challenge_code", "")) == code:
			_saved_challenges.remove_at(index)
			break
	_saved_challenges.push_front({
		"challenge_code": code,
		"challenge_name": challenge_name.strip_edges().left(40) if not challenge_name.strip_edges().is_empty() else code,
		"creator_name": creator_name.strip_edges().left(16),
		"added_at": int(Time.get_unix_time_from_system()),
	})
	while _saved_challenges.size() > 100:
		_saved_challenges.pop_back()
	_save_profile()

func get_saved_seed_challenges() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _saved_challenges:
		result.append(entry.duplicate(true))
	return result

func merge_saved_seed_challenges(entries: Array) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary:
			continue
		var code := str(entry.get("challenge_code", "")).strip_edges().to_upper()
		if not _is_valid_challenge_code(code) or seen.has(code):
			continue
		var normalized: Dictionary = entry.duplicate(true)
		normalized["challenge_code"] = code
		merged.append(normalized)
		seen[code] = true
	for local_entry in _saved_challenges:
		var local_code := str(local_entry.get("challenge_code", ""))
		if not seen.has(local_code):
			merged.append(local_entry.duplicate(true))
			seen[local_code] = true
	_saved_challenges = merged
	_save_profile()
	return get_saved_seed_challenges()

func forget_seed_challenge(challenge_code: String) -> void:
	var code := challenge_code.strip_edges().to_upper()
	for index in range(_saved_challenges.size() - 1, -1, -1):
		if str(_saved_challenges[index].get("challenge_code", "")) == code:
			_saved_challenges.remove_at(index)
	_save_profile()

func _is_valid_challenge_code(code: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^(GC-[A-F0-9]{12}|GR[3-7]-[0-9]{10})$")
	return pattern.search(code) != null
