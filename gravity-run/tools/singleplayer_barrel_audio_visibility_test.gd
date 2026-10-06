extends Node

const MainScene := preload("res://main.tscn")
const BarrelScene := preload("res://hazards/barrel.tscn")
const AudibilityRules := preload("res://systems/sfx_audibility_rules.gd")
const PresentationScript := preload("res://systems/race_course_presentation.gd")

var _failures: Array[String] = []
var _started: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var original_enabled := bool(PlayerProfile.get("sfx_enabled"))
	var original_volume := float(PlayerProfile.get("sfx_volume"))
	PlayerProfile.set_sfx_enabled(true)
	PlayerProfile.set_sfx_volume(0.25)
	SfxController.event_started.connect(_on_event_started)
	var game := MainScene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var challenge_before := {"active": bool(ChallengeService.get("active")), "seed": int(ChallengeService.get("seed_value")), "generation": int(ChallengeService.get("generation_version")), "ruleset": ChallengeService.get("ruleset")}
	var seed_before := int(game.get("_active_seed"))
	var generation_before := int(game.get("_active_seed_version"))
	_check(bool(game.call("_start_singleplayer_audio_diagnostic_capture", 1.5)), "actual SP game seam starts its bounded audio capture for the active run")
	var audio_capture: Node = game.get("_sfx_audio_diagnostic_capture")
	_check(is_instance_valid(audio_capture) and audio_capture.get_parent() == game, "SP diagnostic node is owned by the active game and receives its runtime hooks")
	_check(not bool(game.get("render_diagnostics_enabled")) and (game.get("_render_diagnostic_frames") as Array).is_empty(), "audio-only SP capture leaves the older render-detail fixture inactive")
	_check(bool(ChallengeService.get("active")) == bool(challenge_before.active) and int(ChallengeService.get("seed_value")) == int(challenge_before.seed) and int(ChallengeService.get("generation_version")) == int(challenge_before.generation) and ChallengeService.get("ruleset") == challenge_before.ruleset, "SP audio-only capture preserves challenge state and ruleset")
	_check(int(game.get("_active_seed")) == seed_before and int(game.get("_active_seed_version")) == generation_before, "SP audio-only capture preserves the actual run seed and generator version")
	var camera := game.get_node("Camera2D")
	camera.call("configure", Vector2(960.0, 540.0), 180.0)
	camera.call("follow", Vector2(1180.0, 270.0), true)
	await get_tree().process_frame
	var camera_left := float(camera.get("left"))
	var camera_view_size: Vector2 = camera.get("view_size")
	var view_width := camera_view_size.x
	SfxController.begin_round("barrel-audibility-test")
	var presentation := PresentationScript.new()
	get_tree().root.add_child(presentation)
	presentation.call("set_audio_round_id", "mp-barrel-audibility-test")
	presentation.call("set_camera_left", camera_left)
	_check(AudibilityRules.is_world_x_audible(camera_left + 500.0, camera_left, view_width), "shared audible window includes visible world position")
	_check(AudibilityRules.is_world_x_audible(camera_left + view_width + 64.0, camera_left, view_width), "shared audible window retains the MP 64px edge margin")
	_check(not AudibilityRules.is_world_x_audible(camera_left + view_width + 65.0, camera_left, view_width), "shared audible window rejects just-outside positions")
	var visible_barrel := _add_barrel(game, camera_left + 500.0)
	visible_barrel.call("destroy")
	_check(_started.size() == 1 and _started[0].begins_with("barrel_destroy|"), "real SP barrel destruction signal plays once in camera range")
	var mp_visible_barrel := _add_barrel(game, camera_left + 500.0)
	presentation.call("_on_barrel_destruction_started", mp_visible_barrel)
	_check(_started.size() == 2, "MP presentation plays the same visible barrel event")
	var offscreen_barrel := _add_barrel(game, camera_left + view_width + 65.0)
	offscreen_barrel.call("destroy")
	_check(_started.size() == 2, "real SP barrel destruction outside camera range is silent")
	var mp_offscreen_barrel := _add_barrel(game, camera_left + view_width + 65.0)
	presentation.call("_on_barrel_destruction_started", mp_offscreen_barrel)
	_check(_started.size() == 2, "MP presentation is also silent for the same offscreen position")
	var edge_barrel := _add_barrel(game, camera_left + view_width + 64.0)
	edge_barrel.call("destroy")
	_check(_started.size() == 3, "SP preserves the same inclusive 64px audible margin as MP")
	var mp_edge_barrel := _add_barrel(game, camera_left + view_width + 64.0)
	presentation.call("_on_barrel_destruction_started", mp_edge_barrel)
	_check(_started.size() == 4, "MP preserves the shared inclusive 64px audible margin")
	var capture_wait_usec := Time.get_ticks_usec()
	while bool(audio_capture.call("is_capture_active")) and Time.get_ticks_usec() - capture_wait_usec < 3_000_000:
		await get_tree().process_frame
	var audio_report: Dictionary = audio_capture.call("report_for_test")
	_check(int(audio_report.get("run", {}).get("seed", -1)) == seed_before and int(audio_report.get("run", {}).get("generator_version", -1)) == generation_before, "SP audio-only report exports the active run seed and generator version")
	_check(not bool(audio_report.get("capture", {}).get("screenshots_enabled", true)) and int(audio_report.get("capture", {}).get("frame_readback_count", -1)) == 0, "SP audio capture report has no screenshot series")
	_check(not audio_report.get("audio_diagnostics", {}).get("events", []).is_empty(), "SP audio-only report includes bounded event requests")
	var download_button := audio_capture.get("_download_button") as Button
	var download_rect := download_button.get_global_rect() if is_instance_valid(download_button) else Rect2()
	_check(is_instance_valid(download_button) and download_rect.size.x > 0.0 and download_rect.size.y > 0.0 and download_rect.intersects(get_viewport().get_visible_rect()), "SP audio download control has a visible viewport hit area")
	if is_instance_valid(download_button):
		var runner: Node = game.get("_runner")
		var gravity_before_touch := int(runner.get("player_state").get("gravity_direction", 1)) if is_instance_valid(runner) else 1
		_push_touch(download_rect.get_center())
		var gravity_after_touch := int(runner.get("player_state").get("gravity_direction", 1)) if is_instance_valid(runner) else gravity_before_touch
		_check(gravity_after_touch == gravity_before_touch, "touch/release over the audio download control does not change gravity")
	audio_capture.call("_download_report")
	var saved_message := download_button.text if is_instance_valid(download_button) else ""
	var saved_prefix := "Diagnostics saved locally: "
	_check(saved_message.begins_with(saved_prefix), "SP audio diagnostics uses the normal JSON download/export helper")
	if saved_message.begins_with(saved_prefix):
		var report_path := saved_message.trim_prefix(saved_prefix)
		var exported: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		_check(exported is Dictionary and int(exported.get("run", {}).get("seed", -1)) == seed_before and int(exported.get("run", {}).get("generator_version", -1)) == generation_before, "actual SP downloaded JSON records the correct run seed/version")
		if exported is Dictionary:
			_check(int(exported.get("capture", {}).get("frame_readback_count", -1)) == 0 and not exported.has("images"), "actual SP audio JSON excludes screenshots")
		DirAccess.remove_absolute(report_path)
	var demo_game := MainScene.instantiate()
	demo_game.set("demo_mode", true)
	get_tree().root.add_child(demo_game)
	await get_tree().process_frame
	_check(not is_instance_valid(demo_game.get("_sfx_audio_diagnostic_capture")), "menu-style demo startup does not create an audio diagnostics capture")
	_check(not bool(demo_game.call("_start_singleplayer_audio_diagnostic_capture", 0.05)), "menu-style demo cannot start the gameplay audio capture seam")
	demo_game.queue_free()
	game.queue_free()
	presentation.queue_free()
	await get_tree().process_frame
	SfxController.stop_all()
	PlayerProfile.set_sfx_enabled(original_enabled)
	PlayerProfile.set_sfx_volume(original_volume)
	PlayerProfile.flush_settings()
	SfxController.event_started.disconnect(_on_event_started)
	for failure in _failures:
		push_error(failure)
	print("SINGLEPLAYER_BARREL_AUDIO_VISIBILITY_TEST failures=%d starts=%d" % [_failures.size(), _started.size()])
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if not _failures.is_empty() else 0)

func _add_barrel(game: Node, world_x: float) -> Node2D:
	var barrel := BarrelScene.instantiate() as Node2D
	barrel.call("configure", Vector2(52.0, 84.0), false)
	barrel.position = Vector2(world_x, 456.0)
	game.add_child(barrel)
	game.call("_connect_barrel_audio", barrel)
	return barrel

func _on_event_started(event_name: String, event_key: String) -> void:
	_started.append(event_name + "|" + event_key)

func _push_touch(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 9
	event.position = position
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventScreenTouch.new()
	event.index = 9
	event.position = position
	event.pressed = false
	get_viewport().push_input(event)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
