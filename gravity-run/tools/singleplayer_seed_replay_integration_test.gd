extends Node

const MainScene := preload("res://main.tscn")
const HubScene := preload("res://ui/game_hub.tscn")
const Generator := preload("res://systems/course_generator.gd")
const ManifestBuilder := preload("res://systems/course_manifest_builder.gd")

var failures := 0
var start_count := 0
var scene_started := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge = get_tree().root.get_node("ChallengeService")
	challenge.call("clear_challenge")
	var hub := HubScene.instantiate() as Control
	get_tree().root.add_child(hub)
	await get_tree().process_frame
	hub.start_run_requested.connect(_on_start_requested)
	var seed_edit := hub.get("_seed_edit") as LineEdit
	seed_edit.text = "not a seed"
	hub.call("_start_run")
	_check(start_count == 0, "invalid ordinary input cannot start a run")
	seed_edit.text = "GR13-100000003"
	hub.call("_start_run")
	print("seed_hub_start_count=%d version=%d active=%s" % [start_count, int(challenge.get("generation_version")), str(challenge.get("active"))])
	_check(start_count == 1 and int(challenge.get("generation_version")) == 13 and not bool(challenge.get("active")), "hub uses the old GR parser for an ordinary frozen Gen13 replay")
	challenge.set("active", true)
	challenge.set("seed_value", 777777)
	challenge.set("generation_version", 12)
	seed_edit.text = "GR14-100000003"
	hub.call("_update_account_summary")
	_check(not seed_edit.visible and not seed_edit.editable and not (hub.get("_seed_label") as Label).visible, "active challenge hides and disables ordinary seed entry")
	hub.call("_start_run")
	_check(start_count == 2 and int(challenge.get("seed_value")) == 777777 and int(challenge.get("generation_version")) == 12 and bool(challenge.get("active")), "starting an active challenge cannot silently replace its seed or generator")
	challenge.call("clear_challenge")
	seed_edit.text = "100000014"
	hub.call("_start_run")
	_check(start_count == 3 and int(challenge.get("seed_value")) == 100000014 and int(challenge.get("generation_version")) == 14 and not bool(challenge.get("active")), "numeric ordinary input selects the current generator without challenge mode")
	seed_edit.text = ""
	challenge.call("clear_challenge")
	hub.call("_start_run")
	_check(start_count == 4 and scene_started, "blank seed input continues through the ordinary random-run path")
	hub.queue_free()
	await get_tree().process_frame
	_check(bool(challenge.call("start_singleplayer_seed_input", "GR14-100000014")), "current Gen14 seed code is accepted for ordinary play")
	var game := MainScene.instantiate() as Node
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_physics_process(false)
	_check(int(game.get("_active_seed")) == 100000014 and int(game.get("_active_seed_version")) == 14, "actual main scene starts the exact selected Gen14 seed")
	_check(not bool(challenge.get("active")), "ordinary selected run is not promoted into a saved challenge")
	var generator = game.get("course_generator")
	generator.call("ensure_horizon", 45000.0, 500.0)
	var lava_source: Dictionary = {}
	var matching_manifest_event: Dictionary = {}
	var shared_build: Dictionary = ManifestBuilder.new().build(100000014, 45000, 14)
	if shared_build.get("manifest") != null:
		for planned in generator.call("get_planned_events"):
			if str(planned.get("kind", "")) not in ["lava_crack", "volcano"]:
				continue
			for shared_event in shared_build.manifest.get("events"):
				if str(shared_event.get("kind", "")) == str(planned.get("kind", "")) and is_equal_approx(float(shared_event.get("x", -1.0)), 180.0 + float(planned.get("course_distance", 0.0))):
					lava_source = planned
					matching_manifest_event = shared_event
					break
			if not lava_source.is_empty():
				break
	_check(not lava_source.is_empty(), "ordinary selected seed has a lava event accepted in both SP and MP resolved support")
	if not lava_source.is_empty():
		_check(not matching_manifest_event.is_empty(), "SP generator event has matching geometry in the shared MP manifest")
		game.call("_spawn_course_event", lava_source)
		var found_lava := false
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("lava_hazards"):
				found_lava = true
		_check(found_lava, "generated SP event resolves through the ordinary spawn route into the shared lava scene")
		if found_lava and not matching_manifest_event.is_empty():
			for obstacle in game.get("obstacles"):
				if is_instance_valid(obstacle) and obstacle.is_in_group("lava_hazards") and str(obstacle.get("event").get("kind", "")) == str(lava_source.get("kind", "")):
					_check(is_equal_approx(float(obstacle.global_position.x), float(matching_manifest_event.get("x", -1.0))), "SP's shared lava scene is positioned at the exact MP manifest coordinate")
	var original_audio_round := str(game.get("_singleplayer_audio_round_id"))
	game.call("retry_run")
	await get_tree().process_frame
	game.set_physics_process(false)
	_check(int(game.get("_active_seed")) == 100000014 and int(game.get("_active_seed_version")) == 14, "replay keeps the exact current seed and generator")
	_check(str(game.get("_singleplayer_audio_round_id")) != original_audio_round, "replay starts with a fresh run/audio identity")
	_check(int(game.get("_singleplayer_simulation_tick")) == 0 and float(game.get("course_distance")) == 0.0, "replay resets shared simulation tick and course position")
	_check((game.get("obstacles") as Array).is_empty() and (game.get("coins") as Array).is_empty(), "replay clears old hazards and collectibles before respawning")
	game.call("new_random_run")
	await get_tree().process_frame
	game.set_physics_process(false)
	_check(int(game.get("_active_seed_version")) == Generator.GENERATOR_VERSION and not bool(challenge.get("active")), "new random course switches to current generator without challenge mode")
	_check(int(game.get("_active_seed")) != 100000014, "new random course selects a fresh seed")
	game.queue_free()
	if failures == 0:
		print("SINGLEPLAYER_SEED_REPLAY_INTEGRATION_TEST passed: hub input, actual generated lava spawn, exact replay reset, fresh random course.")
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)

func _on_start_requested() -> void:
	start_count += 1
	scene_started = true
