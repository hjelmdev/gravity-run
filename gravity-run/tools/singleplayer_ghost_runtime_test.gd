extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")

var failures := 0
var _sfx_events := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed := -1
	var expected_manifest: Resource
	for candidate in range(100000000, 100000160):
		var built: Dictionary = Builder.new().build(candidate, 45000, Generator.GENERATOR_VERSION)
		var manifest: Resource = built.get("manifest")
		if manifest == null:
			continue
		for event in manifest.events:
			if str(event.get("kind", "")) == "ghost":
				seed = candidate
				expected_manifest = manifest
				break
		if seed > 0:
			break
	_check(seed > 0, "bounded gen11 user-valid seed range contains an authored ghost")
	if seed < 0:
		quit(1)
		return
	var challenge: Node = root.get_node("ChallengeService")
	_check(bool(challenge.call("start_challenge_from_code", "GR11-%d" % seed)), "normal challenge parser accepts selected gen11 seed")
	var game: Node = load("res://main.tscn").instantiate()
	game.set("demo_mode", true)
	var sfx: Node = root.get_node("SfxController")
	var music: Node = root.get_node("MusicController")
	var profile: Node = root.get_node("PlayerProfile")
	sfx.event_started.connect(_on_sfx_event_started)
	root.add_child(game)
	await process_frame
	_check(int(game.get("_active_seed_version")) == Generator.GENERATOR_VERSION and int(game.get("_active_seed")) == seed, "actual SP main scene starts the selected gen11 course")
	var sfx_round_before := str(sfx.get("_round_id"))
	var music_round_before := str(music.get("_last_round_id"))
	var music_enabled_before := bool(profile.get("music_enabled"))
	var demo_coin: Node2D = load("res://collectibles/coin.tscn").instantiate()
	root.add_child(demo_coin)
	game.call("_connect_coin_audio", demo_coin, "demo_coin")
	demo_coin.call("animate_collection")
	game.call("_on_singleplayer_gravity_flipped")
	var demo_barrel := Node2D.new()
	root.add_child(demo_barrel)
	game.call("_on_barrel_destruction_started", demo_barrel)
	game.call("_on_rock_impact_started", "demo_rock")
	game.call("_on_singleplayer_ghost_phase_changed", "demo_ghost", "warning", {"event_id": "demo_ghost", "from_ceiling": false, "x": 10.0})
	await process_frame
	_check(_sfx_events == 0 and str(sfx.get("_round_id")) == sfx_round_before, "main-menu demo creates no gameplay SFX and does not reset the sound round")
	_check(bool(profile.get("music_enabled")) == music_enabled_before and str(music.get("_last_round_id")) == music_round_before, "demo sound guard leaves the live music setting and music round untouched")
	demo_coin.queue_free()
	demo_barrel.queue_free()
	var course_generator: Object = game.get("course_generator")
	course_generator.call("ensure_horizon", 45000.0, 500.0, 540.0, 1200.0)
	var ghost_source: Dictionary = {}
	var saw_source: Dictionary = {}
	for event in course_generator.call("get_planned_events"):
		if str(event.get("kind", "")) == "ghost" and ghost_source.is_empty():
			ghost_source = event
		elif str(event.get("kind", "")) == "saw" and saw_source.is_empty():
			saw_source = event
	_check(not ghost_source.is_empty(), "actual SP generator exposes a ghost source event")
	_check(not saw_source.is_empty(), "actual SP generator exposes a saw source event")
	if not ghost_source.is_empty():
		var resolved_ghost: Dictionary = game.call("_resolve_singleplayer_ghost_event", ghost_source)
		var expected_ghost: Dictionary = _find_event(expected_manifest, "ghost", float(ghost_source.get("course_distance", -1.0)))
		_check(not resolved_ghost.is_empty(), "SP ghost resolver accepts the active generator-version parameter")
		_check(not expected_ghost.is_empty() and is_equal_approx(float(resolved_ghost.get("floor_y", -1.0)), float(expected_ghost.get("floor_y", -2.0))) and is_equal_approx(float(resolved_ghost.get("ceiling_y", -1.0)), float(expected_ghost.get("ceiling_y", -2.0))), "SP ghost uses resolved future floor/ceiling support matching the shared manifest")
		if not expected_ghost.is_empty() and (not is_equal_approx(float(resolved_ghost.get("floor_y", -1.0)), float(expected_ghost.get("floor_y", -2.0))) or not is_equal_approx(float(resolved_ghost.get("ceiling_y", -1.0)), float(expected_ghost.get("ceiling_y", -2.0)))):
			print("GHOST_SUPPORT_DIFFERENCE screen_h=%.1f source=%s resolved=%s manifest=%s" % [float(game.get("screen_height")), JSON.stringify(ghost_source), JSON.stringify(resolved_ghost), JSON.stringify(expected_ghost)])
		game.call("_spawn_course_event", ghost_source)
		var spawned_ghost := _find_group(game.get("obstacles"), "ghost_hazards")
		_check(is_instance_valid(spawned_ghost), "normal SP event spawning instantiates the shared ghost scene")
		if is_instance_valid(spawned_ghost):
			_check(is_equal_approx(float(spawned_ghost.get("event").get("floor_y", -1.0)), float(resolved_ghost.get("floor_y", -2.0))), "spawned SP ghost keeps the resolved support pose")
			game.call("_update_ghost_hazards", float(resolved_ghost.get("x", 0.0)) - float(resolved_ghost.get("trigger_lead", 2500.0)))
			_check(bool(game.get("_ghost_warning_pulse").call("is_active")), "SP event activation raises the same centered warning pulse before danger")
	if not saw_source.is_empty():
		var resolved_saw: Dictionary = game.call("_resolve_singleplayer_saw_event", saw_source)
		_check(not resolved_saw.is_empty(), "SP saw resolver accepts the active generator-version parameter")
	game.call("_spawn_shared_coins")
	var planned_until := float(game.get("_shared_coin_planned_until"))
	_check(planned_until > 0.0, "actual SP coin streaming invokes the current-version manifest event resolver")
	print("SINGLEPLAYER_GHOST_RUNTIME_TEST seed=%d ghost_x=%.1f saw_resolved=%s coin_plan_until=%.1f failures=%d" % [seed, float(ghost_source.get("course_distance", -1.0)) + 180.0, str(not saw_source.is_empty() and not game.call("_resolve_singleplayer_saw_event", saw_source).is_empty()), planned_until, failures])
	quit(1 if failures > 0 else 0)

func _find_event(manifest: Resource, kind: String, source_distance: float) -> Dictionary:
	for event in manifest.events:
		if str(event.get("kind", "")) == kind and absf(float(event.get("x", -10000000.0)) - 180.0 - source_distance) < 0.5:
			return event
	return {}

func _find_group(nodes: Array, group: String) -> Node:
	for node in nodes:
		if is_instance_valid(node) and node.is_in_group(group):
			return node
	return null

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)

func _on_sfx_event_started(_event_name: String, _event_key: String) -> void:
	_sfx_events += 1
