extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var profile = root.get_node_or_null("PlayerProfile")
	var music = root.get_node_or_null("MusicController")
	_check(profile != null and music != null, "music and profile autoloads should be available")
	if failures > 0:
		quit(1)
		return
	profile.set_music_enabled(true)
	_check(float(profile.music_volume) >= 0.0 and float(profile.music_volume) <= 1.0, "an explicitly saved music value should remain in range")
	_check(is_equal_approx(profile.normalize_music_volume("invalid"), 0.25), "a nonnumeric saved music setting should use 25 percent")
	_check(is_equal_approx(profile.normalize_music_volume(NAN), 0.25), "a nonfinite saved music setting should use 25 percent")
	_check(is_equal_approx(profile.normalize_music_volume(1.5), 1.0) and is_equal_approx(profile.normalize_music_volume(-0.2), 0.0), "valid saved music settings should be clamped to 0 through 1")
	_test_malformed_setting_fallback(profile)
	var bus_index := AudioServer.get_bus_index("Music")
	_check(bus_index > 0, "a dedicated Music bus should exist")
	var player := music.get_node_or_null("MusicPlayer") as AudioStreamPlayer
	_check(player != null and player.playing, "one shared music player should attempt autoplay as soon as audio is ready")
	_check(player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "the OGG music should use stream playback for web memory use and seamless pausing")
	var stream := player.stream as AudioStreamOggVorbis
	_check(stream != null and stream.loop and is_zero_approx(stream.loop_offset), "the selected OGG should loop from offset zero")
	music.enter_menu()
	var stable_menu_gain := player.volume_db
	music.enter_menu()
	_check(is_equal_approx(player.volume_db, stable_menu_gain), "re-entering an already active menu does not create another gain transition")
	var master_index := AudioServer.get_bus_index("Master")
	var master_before := AudioServer.get_bus_volume_db(master_index)
	var previous_gain := -1.0
	for setting in [0.0, 0.01, 0.05, 0.10, 0.25, 0.50, 1.0]:
		profile.set_music_volume(setting)
		var gain: float = music.music_gain_for_setting(setting)
		_check(gain >= previous_gain, "the quadratic music curve should remain monotonic")
		_check(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), linear_to_db(maxf(gain, 0.0001))), "Music bus should match the shared quadratic gain curve")
		_check(AudioServer.is_bus_mute(bus_index) == is_zero_approx(setting), "zero percent alone should mute the Music bus")
		previous_gain = gain
	_check(is_equal_approx(music.music_gain_for_setting(0.05), 0.000875), "5 percent should retain fine control below the default")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master_index), master_before), "music volume should not change Master")
	music.prepare_round()
	profile.set_music_volume(0.05)
	await create_timer(0.30).timeout
	_check(not player.playing, "round preparation fades from the actual current gain and stops the player")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), linear_to_db(music.music_gain_for_setting(0.05))), "a volume change during a round fade remains authoritative")
	music.enter_menu()
	_check(player.playing and is_equal_approx(player.volume_db, 0.0), "menu playback restarts at the shared unity context gain without a separate menu boost")
	profile.set_music_volume(0.25)
	var first_round := "music-test-round-1"
	music.start_round(first_round)
	await create_timer(0.12).timeout
	var position_before_volume_change := player.get_playback_position()
	profile.set_music_volume(0.0)
	await create_timer(0.12).timeout
	profile.set_music_volume(0.25)
	_check(player.playing and player.get_playback_position() > position_before_volume_change, "changing 0 percent back to 25 percent should preserve the current stream")
	music.start_round(first_round)
	await create_timer(0.04).timeout
	_check(player.get_playback_position() > position_before_volume_change, "the same round signal should not restart music")
	var retry_bus_gain := AudioServer.get_bus_volume_db(bus_index)
	music._menu_start_pending = true
	music._retry_blocked_autoplay_from_gesture()
	_check(player.playing and is_equal_approx(AudioServer.get_bus_volume_db(bus_index), retry_bus_gain), "a stalled autoplay fallback retries even when the engine reports playing, without changing the user's volume")
	music.set_stream_paused(true)
	_check(player.stream_paused, "singleplayer pause should pause the shared player")
	music.enter_menu()
	_check(not player.stream_paused and player.playing, "returning to menu should resume the existing stream")
	var saved_volume := float(profile.music_volume)
	profile.set_music_enabled(false)
	_check(not player.playing and AudioServer.is_bus_mute(bus_index), "disabling music immediately stops the player and mutes the Music bus")
	music.enter_menu()
	music.start_round("music-test-round-disabled")
	music._on_stream_finished()
	await create_timer(0.08).timeout
	_check(not player.playing, "menu entry, round start, trusted-input fallback and finished callback cannot restart disabled music")
	_check(is_equal_approx(float(profile.music_volume), saved_volume), "disabling music preserves the saved volume setting")
	profile.set_music_enabled(true)
	music.enter_menu()
	_check(player.playing and is_equal_approx(float(profile.music_volume), saved_volume), "reenabling music restores the saved level and follows menu autoplay")
	profile.set_music_volume(0.25)
	profile.set_music_enabled(true)
	profile.flush_settings()
	var saved := ConfigFile.new()
	_check(saved.load("user://gravity_run_profile.cfg") == OK and is_equal_approx(float(saved.get_value("settings", "music_volume", -1.0)), 0.25) and bool(saved.get_value("settings", "music_enabled", false)), "music volume and enabled state should persist to the local profile")
	profile.set_music_volume(0.25)
	profile.flush_settings()
	if failures == 0:
		print("Music controller tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _test_malformed_setting_fallback(profile: Node) -> void:
	for saved_value in [null, "not-a-number"]:
		var config := ConfigFile.new()
		config.set_value("profile", "best_distance_m", 321.0)
		config.set_value("settings", "language", "en")
		config.set_value("settings", "extra_setting", "keep-existing-value")
		if saved_value != null:
			config.set_value("settings", "music_volume", saved_value)
		_check(config.save("user://gravity_run_profile.cfg") == OK, "isolated malformed test profile should save")
		profile.call("_load_profile")
		_check(is_equal_approx(float(profile.get("music_volume")), 0.25), "empty or malformed saved music values should use the 25 percent default")
		_check(bool(profile.get("music_enabled")), "profiles created before the enabled setting default compatibly to music on")
		profile.call("flush_settings")
		var preserved := ConfigFile.new()
		_check(preserved.load("user://gravity_run_profile.cfg") == OK and str(preserved.get_value("settings", "extra_setting", "")) == "keep-existing-value", "saving settings should preserve unrelated existing ConfigFile values")
