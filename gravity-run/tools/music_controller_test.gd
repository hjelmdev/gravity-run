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
	var expect_reload := OS.get_cmdline_user_args().has("--expect-25")
	_check(is_equal_approx(float(profile.music_volume), 0.25 if expect_reload else 0.6), "new and reloaded isolated profiles should use the default or persisted 25 percent value")
	_check(is_equal_approx(profile.normalize_music_volume("invalid"), 0.6), "a nonnumeric saved music setting should use 60 percent")
	_check(is_equal_approx(profile.normalize_music_volume(NAN), 0.6), "a nonfinite saved music setting should use 60 percent")
	_check(is_equal_approx(profile.normalize_music_volume(1.5), 1.0) and is_equal_approx(profile.normalize_music_volume(-0.2), 0.0), "valid saved music settings should be clamped to 0 through 1")
	_test_malformed_setting_fallback(profile)
	var bus_index := AudioServer.get_bus_index("Music")
	_check(bus_index > 0, "a dedicated Music bus should exist")
	var player := music.get_node_or_null("MusicPlayer") as AudioStreamPlayer
	_check(player != null and player.playing, "one shared music player should be active in the menu")
	_check(player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "the OGG music should use stream playback for web memory use and seamless pausing")
	var stream := player.stream as AudioStreamOggVorbis
	_check(stream != null and stream.loop and is_zero_approx(stream.loop_offset), "the selected OGG should loop from offset zero")
	var master_index := AudioServer.get_bus_index("Master")
	var master_before := AudioServer.get_bus_volume_db(master_index)
	profile.set_music_volume(0.0)
	_check(AudioServer.is_bus_mute(bus_index), "zero percent should mute the Music bus")
	profile.set_music_volume(0.25)
	_check(not AudioServer.is_bus_mute(bus_index) and is_equal_approx(AudioServer.get_bus_volume_db(bus_index), linear_to_db(0.25)), "25 percent should immediately restore Music bus gain")
	profile.set_music_volume(0.6)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), linear_to_db(0.6)), "60 percent should apply only to the Music bus")
	profile.set_music_volume(1.0)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), 0.0), "100 percent should remain at unity gain")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master_index), master_before), "music volume should not change Master")
	var first_round := "music-test-round-1"
	music.start_round(first_round)
	await create_timer(0.12).timeout
	var position_before_volume_change := player.get_playback_position()
	profile.set_music_volume(0.0)
	await create_timer(0.12).timeout
	profile.set_music_volume(0.6)
	_check(player.playing and player.get_playback_position() > position_before_volume_change, "changing 0 percent back to 60 percent should preserve the current stream")
	music.start_round(first_round)
	await create_timer(0.04).timeout
	_check(player.get_playback_position() > position_before_volume_change, "the same round signal should not restart music")
	music.set_stream_paused(true)
	_check(player.stream_paused, "singleplayer pause should pause the shared player")
	music.enter_menu()
	_check(not player.stream_paused and player.playing, "returning to menu should resume the existing stream")
	profile.set_music_volume(0.25)
	profile.flush_settings()
	var saved := ConfigFile.new()
	_check(saved.load("user://gravity_run_profile.cfg") == OK and is_equal_approx(float(saved.get_value("settings", "music_volume", -1.0)), 0.25), "music volume should persist to the local profile")
	profile.set_music_volume(0.25 if not expect_reload else 0.6)
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
		_check(is_equal_approx(float(profile.get("music_volume")), 0.6), "empty or malformed saved music values should use the 60 percent default")
		profile.call("flush_settings")
		var preserved := ConfigFile.new()
		_check(preserved.load("user://gravity_run_profile.cfg") == OK and str(preserved.get_value("settings", "extra_setting", "")) == "keep-existing-value", "saving settings should preserve unrelated existing ConfigFile values")
