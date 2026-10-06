extends Node

const MainScene := preload("res://main.tscn")
const MatchScene := preload("res://ui/multiplayer_v2/multiplayer_v2_match.tscn")
const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const Biome := preload("res://biomes/biome_renderer.gd")
const CameraScript := preload("res://systems/runner_camera.gd")

class RemoteFixture extends RefCounted:
	var pose: Dictionary = {}
	func set_shared_presentation_tick(_tick: float) -> void: pass
	func advance_presentation(_delta: float) -> Dictionary: return pose
	func consume_transition() -> String: return ""
	func sample_at_render_time() -> Dictionary: return pose.duplicate(true)

const SEEDS := [100000001, 100000000, 100000005, 100000029]
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	var service: Node = get_tree().root.get_node("MultiplayerV2Service")
	var old_manifest: Resource = service.current_manifest
	var old_session: Dictionary = service.session.duplicate(true)
	var old_challenge := {"seed": int(challenge.get("seed_value")), "version": int(challenge.get("generation_version")), "active": bool(challenge.get("active"))}
	var builder := Builder.new()
	var verified_biomes: Array[String] = []
	for index in range(SEEDS.size()):
		var seed_value := int(SEEDS[index])
		print("GEN16_LIFECYCLE_BEGIN code=GR16-%d index=%d" % [seed_value, index])
		var expected_biome: String = ["classic", "cave", "haunted", "lava"][Biome.start_biome_slot_for_seed(seed_value, 16)]
		verified_biomes.append(expected_biome)
		var code := "GR16-%d" % seed_value
		_check(bool(challenge.call("start_singleplayer_seed_input", code)), "SP accepts supported start-biome seed %s" % code)
		var game := MainScene.instantiate() as Node2D
		get_tree().root.add_child(game)
		await get_tree().process_frame
		print("GEN16_LIFECYCLE_SP_READY code=GR16-%d" % seed_value)
		game.set_physics_process(false)
		game.set_process(false)
		var generator: Object = game.get("course_generator")
		_check(int(game.get("_active_seed")) == seed_value and int(game.get("_active_seed_version")) == 16, "actual main.tscn starts %s without replacing its seed" % code)
		_check(is_equal_approx(float(generator.get("_biome_start_offset")), float(Biome.start_biome_slot_for_seed(seed_value, 16)) * Biome.THEME_LENGTH), "actual SP generator applies the deterministic %s start phase" % expected_biome)
		generator.call("ensure_horizon", 7200.0, 500.0, Generator.REFERENCE_TRACK_HEIGHT, Generator.EVENT_SPAWN_LEAD_DISTANCE)
		var retry_tick := int(game.get("_singleplayer_simulation_tick"))
		game.call("retry_run")
		await get_tree().process_frame
		game.set_physics_process(false)
		game.set_process(false)
		_check(int(game.get("_active_seed")) == seed_value and int(game.get("_active_seed_version")) == 16, "SP retry preserves %s and its selected starting biome" % code)
		_check(int(game.get("_singleplayer_simulation_tick")) <= retry_tick and float(game.get("course_distance")) <= 8.34, "SP retry resets the real course position before resuming")
		game.queue_free()
		await get_tree().process_frame
		challenge.call("clear_challenge")

		var built: Dictionary = builder.build(seed_value, 45000, 16)
		print("GEN16_LIFECYCLE_MP_MANIFEST code=GR16-%d" % seed_value)
		var manifest: Resource = built.get("manifest")
		_check(manifest != null, "MP manifest builds for %s" % code)
		if manifest == null:
			continue
		service.current_manifest = manifest
		var round_id := "gen16-biome-lifecycle-%d" % seed_value
		service.session = {"round_id": round_id, "local_peer_id": 1, "role": "host"}
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 540) if index != 1 else Vector2i(540, 960)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_tree().root.add_child(viewport)
		var match_node := MatchScene.instantiate() as Node2D
		viewport.add_child(match_node)
		await get_tree().process_frame
		print("GEN16_LIFECYCLE_MP_READY code=GR16-%d" % seed_value)
		match_node.set_process(false)
		match_node.set_physics_process(false)
		var presentation: Node = match_node.get("_course_presentation")
		_check(presentation != null and presentation.get("manifest") == manifest, "actual MP match scene loads %s during PREPARING" % code)
		if presentation != null:
			var offset := Biome.start_biome_offset_for_seed(seed_value, 16)
			_check(is_equal_approx(offset, float(Biome.start_biome_slot_for_seed(seed_value, 16)) * Biome.THEME_LENGTH), "MP presentation uses the same %s biome phase as SP" % expected_biome)
			var surface_index: Object = presentation.get("_surface_index")
			var floor_start: Dictionary = surface_index.call("surface_at", float(manifest.start_x), false)
			var ceiling_start: Dictionary = surface_index.call("surface_at", float(manifest.start_x), true)
			_check(bool(floor_start.get("supported", false)) and bool(ceiling_start.get("supported", false)), "MP %s starts on the same supported surface pair" % expected_biome)
			var boundary_distance := Biome.THEME_LENGTH
			var boundary_world_x := float(manifest.start_x) + boundary_distance
			var camera_left := maxf(boundary_world_x - float(viewport.size.x) * 0.5, 0.0)
			presentation.call("set_render_profile_enabled", true)
			presentation.call("begin_start_profile", Time.get_ticks_usec())
			presentation.call("set_camera_left", camera_left)
			presentation.queue_redraw()
			await get_tree().process_frame
			var before_id := Biome.biome_id_for_seed(seed_value, boundary_distance - 1.0, 16)
			var after_id := Biome.biome_id_for_seed(seed_value, boundary_distance + 1.0, 16)
			var boundary_floor_left: Dictionary = surface_index.call("surface_at", boundary_world_x - 120.0, false)
			var boundary_floor_right: Dictionary = surface_index.call("surface_at", boundary_world_x + 120.0, false)
			var draw_profile: Dictionary = presentation.call("take_start_draw_profile")
			_check(before_id != after_id and before_id == expected_biome, "MP biome sampling changes from the selected %s phase at the real 4,800 px theme boundary" % expected_biome)
			_check(bool(boundary_floor_left.get("supported", false)) and bool(boundary_floor_right.get("supported", false)), "MP resolved support remains available on both sides of the theme boundary")
			_check(not draw_profile.is_empty() and is_equal_approx(float(presentation.get("_camera_left")), camera_left), "MP presentation actually draws at the centered theme boundary (viewport %s)" % str(viewport.size))
		_check(not bool(match_node.get("_round_started")), "MP scene is still in PREPARING before the shared START signal")
		service.round_started.emit(round_id, {"seed": seed_value, "generator_version": 16})
		await get_tree().process_frame
		_check(bool(match_node.get("_round_started")), "actual multiplayer match transitions to RUNNING for %s" % code)
		if index == 0:
			var runner: Object = match_node.get("_runner")
			var local_state: Dictionary = runner.get("player_state").duplicate(true)
			local_state["state"] = "dead"
			runner.set("player_state", local_state)
			var remote := RemoteFixture.new()
			remote.pose = {"valid": true, "stale": false, "world_x": float(manifest.start_x) + 700.0, "y": 270.0, "grounded": false, "gravity_direction": 1, "simulation_tick": 16.0}
			match_node.get("_remote_tracks")[2] = remote
			match_node.get("_remote_terminal")[2] = "running"
			match_node.call("_update_spectator_camera")
			_check(int(match_node.get("_spectator_peer_id")) == 2, "actual MP match retains live presentation while spectating")
		match_node.queue_free()
		await get_tree().process_frame
		viewport.queue_free()
		await get_tree().process_frame
	service.current_manifest = old_manifest
	service.session = old_session
	challenge.set("seed_value", int(old_challenge.seed))
	challenge.set("generation_version", int(old_challenge.version))
	challenge.set("active", bool(old_challenge.active))
	print("GEN16_FREE_BIOME_LIFECYCLE failures=%d seeds=%s biomes=%s actual=main.tscn+multiplayer_v2_match.tscn stages=PREPARING,START,RUNNING,spectating,retry viewports=960x540,540x960" % [failures, str(SEEDS), str(verified_biomes)])
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
