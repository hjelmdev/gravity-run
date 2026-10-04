extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sfx := root.get_node("SfxController")
	var profile := root.get_node("PlayerProfile")
	var old_volume: float = profile.sfx_volume
	var old_enabled: bool = profile.sfx_enabled
	profile.sfx_volume = 0.25
	profile.sfx_enabled = true
	sfx._apply_settings()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var bus := AudioServer.get_bus_index("SFX")
	AudioServer.add_bus_effect(bus, capture)
	var game: Node = load("res://main.tscn").instantiate()
	game.demo_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	var warmup := Time.get_ticks_msec()
	while Time.get_ticks_msec() - warmup < 500:
		await process_frame
	game.demo_mode = false
	game.run_state.active = false # No wallet/profile writes in this fixture.
	game._singleplayer_audio_round_id = "end-audio-probe"
	sfx.begin_round("end-audio-probe")
	capture.clear_buffer()
	game._end_run()
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 100:
		await process_frame
	var voices: Array = sfx._voices
	var live_death := false
	for voice in voices:
		if voice.playing:
			live_death = voice.get_playback_position() > 0.03 and not voice.stream_paused
			_check(is_equal_approx(voice.volume_db, 8.0), "death has its own gain")
			print("DEATH_VOICE playing=",voice.playing," position=",voice.get_playback_position()," paused=",voice.stream_paused)
	_check(game.run_end_panel.visible and not paused, "real SP result opens without pausing audio")
	_check(live_death, "death playback advances after result opens")
	_check(not sfx.play_death("end-audio-probe", "local"), "terminal event remains deduplicated")
	while Time.get_ticks_msec() - began < 500:
		await process_frame
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame in frames:
		energy += frame.length_squared()
	print("SFX_CAPTURE frames=",frames.size()," rms=",sqrt(energy / max(frames.size(),1))," mixrate=",AudioServer.get_mix_rate())
	if "--verify-audio-output" in OS.get_cmdline_user_args():
		_check(energy > 0.000001, "real mixed death signal reaches SFX bus")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus)-1)
	sfx.play_event("coin", "gain-reset")
	_check(is_zero_approx(sfx._voices[0].volume_db), "reused voice resets gain for coin")
	sfx.stop_all()
	game.queue_free()
	await process_frame
	await process_frame
	profile.sfx_volume = old_volume
	profile.sfx_enabled = old_enabled
	sfx._apply_settings()
	print("DEATH_RESULT_AUDIO_TEST failures=", failures)
	quit(1 if failures else 0)



func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
