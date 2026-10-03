extends Node

const CoinScene := preload("res://collectibles/coin.tscn")
const PresentationScript := preload("res://systems/race_course_presentation.gd")
var _starts: Array[String] = []
var _failures: Array[String] = []
var _reward_signals := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	SfxController.event_started.connect(_on_event_started)
	var original_enabled := PlayerProfile.sfx_enabled
	var original_volume := PlayerProfile.sfx_volume
	var music_bus := AudioServer.get_bus_index("Music")
	var music_before := AudioServer.get_bus_volume_db(music_bus) if music_bus >= 0 else 0.0
	PlayerProfile.set_sfx_enabled(true)
	PlayerProfile.set_sfx_volume(0.25)
	SfxController.begin_round("sfx-test-round-a")
	var coin := CoinScene.instantiate()
	get_tree().root.add_child(coin)
	coin.collected.connect(_on_coin_collected)
	coin.visual_collection_started.connect(Callable(SfxController, "play_event").bind("coin", "sfx-test-round-a|coin|coin-a"))
	coin.visual_collection_cancelled.connect(Callable(SfxController, "clear_event_key").bind("sfx-test-round-a|coin|coin-a"))
	_check(bool(coin.begin_visual_prediction("claim-a")), "real shared coin scene accepts pickup prediction")
	coin.confirm_visual_prediction("claim-a")
	_check(_starts.count("coin|sfx-test-round-a|coin|coin-a") == 1, "prediction plus confirmation starts one shared pickup sound")
	_check(_reward_signals == 0, "visual prediction and confirmation do not emit the gameplay reward")
	var presentation := PresentationScript.new()
	get_tree().root.add_child(presentation)
	presentation.set_audio_round_id("coin-visibility-round")
	var visibility_coin := CoinScene.instantiate()
	visibility_coin.position.x = 1800.0
	presentation.add_child(visibility_coin)
	presentation.event_nodes["visibility-coin"] = visibility_coin
	presentation.call("_connect_coin_audio", visibility_coin, "visibility-coin")
	presentation.set_camera_left(0.0)
	var starts_before_offscreen := _starts.count("coin|coin-visibility-round|coin|visibility-coin")
	_check(visibility_coin.begin_visual_prediction("offscreen-claim"), "offscreen presentation prediction starts visually")
	_check(_starts.count("coin|coin-visibility-round|coin|visibility-coin") == starts_before_offscreen, "offscreen remote pickup does not play coin audio")
	_check(visibility_coin.reject_visual_prediction("offscreen-claim"), "offscreen rejection restores the coin and resets dedup")
	presentation.set_camera_left(visibility_coin.position.x - 200.0)
	_check(visibility_coin.begin_visual_prediction("visible-claim"), "visible presentation prediction starts")
	_check(_starts.count("coin|coin-visibility-round|coin|visibility-coin") == starts_before_offscreen + 1, "visible coin plays exactly one pickup sound")
	visibility_coin.confirm_visual_prediction("visible-claim")
	SfxController.begin_round("sfx-test-round-b")
	_check(SfxController.play_event("coin", "sfx-test-round-b|coin|coin-a"), "same entity key can play in a distinct round")
	var before_pause := _starts.size()
	get_tree().paused = true
	_check(not SfxController.play_event("barrel_destroy", "sfx-test-round-b|barrel|1"), "paused gameplay does not queue a sound for resume")
	get_tree().paused = false
	_check(_starts.size() == before_pause, "unpausing does not replay a paused event")
	var starts_before_mute := _starts.size()
	PlayerProfile.set_sfx_enabled(false)
	_check(not SfxController.play_event("gravity_flip", "sfx-test-round-b|flip|1"), "mute blocks new SFX playback")
	_check(_starts.size() == starts_before_mute, "mute creates no delayed voice")
	for voice in SfxController._voices:
		_check(not voice.playing, "mute immediately stops active SFX voices")
	PlayerProfile.set_sfx_enabled(true)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_before), "SFX setting does not alter music bus gain")
	PlayerProfile.set_sfx_enabled(false)
	PlayerProfile.set_sfx_volume(0.41)
	PlayerProfile.flush_settings()
	var profile_copy = load("res://systems/player_profile.gd").new()
	get_tree().root.add_child(profile_copy)
	_check(not bool(profile_copy.sfx_enabled) and is_equal_approx(float(profile_copy.sfx_volume), 0.41), "SFX enabled and volume persist in the separate profile settings")
	profile_copy.queue_free()
	PlayerProfile.set_sfx_enabled(original_enabled)
	PlayerProfile.set_sfx_volume(original_volume)
	PlayerProfile.flush_settings()
	SfxController.stop_all()
	presentation.queue_free()
	coin.queue_free()
	for failure in _failures:
		push_error(failure)
	print("SFX_SHARED_POOL_TEST failures=%d starts=%d" % [_failures.size(), _starts.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _on_event_started(event_name: String, event_key: String) -> void:
	_starts.append(event_name + "|" + event_key)

func _on_coin_collected(_value: int) -> void:
	_reward_signals += 1

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
