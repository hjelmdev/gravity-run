extends Node
## Bounded actual-main presentation capture for the Gen19 one-shot flyby.

const MainScene := preload("res://main.tscn")
const SEED := 100000030
const SPEEDS := [250.0, 500.0, 750.0]
const MAX_TICKS := 900

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	var output_dir := ProjectSettings.globalize_path("res://.codex-gen19-review/runtime")
	DirAccess.make_dir_recursive_absolute(output_dir)
	Engine.time_scale = 1.0
	for speed in SPEEDS:
		challenge.call("clear_challenge")
		if not bool(challenge.call("start_singleplayer_seed_input", str(SEED))):
			_fail("could not select seed %d" % SEED)
			continue
		var game := MainScene.instantiate() as Node
		add_child(game)
		await get_tree().process_frame
		if not is_instance_valid(game.get("player")):
			_fail("main scene has no runner")
			game.queue_free()
			continue
		var player: Node = game.get("player")
		var effects: Node = player.get_node("PlayerEffects")
		effects.set("speed_multiplier", float(speed) / 500.0)
		var generator: Object = game.get("course_generator")
		generator.call("ensure_horizon", 10000.0, float(speed), float(game.get("screen_height")), 820.0)
		var target: Dictionary = {}
		var planned_events: Array = generator.call("get_planned_events")
		for planned in planned_events:
			if str(planned.get("kind", "")) == "ghost" and str(planned.get("id", "")) == "haunted_chaser":
				target = planned
				break
		if target.is_empty():
			print("GEN19_GHOST_RUNTIME_NO_EVENT active_seed=%d version=%d generator_version=%d event_count=%d first_events=%s" % [int(game.get("_active_seed")), int(game.get("_active_seed_version")), int(generator.get("_generator_version")), planned_events.size(), JSON.stringify(planned_events.slice(0, 8))])
			_fail("seed %d has no Gen19 flyby at %.0fpx/s" % [SEED, speed])
			game.queue_free()
			continue
		# Keep the real main adapter, camera, tick and collision path, but isolate
		# the one generated ghost so unrelated seed hazards cannot end the capture.
		for obstacle in game.get("obstacles").duplicate():
			if is_instance_valid(obstacle):
				obstacle.queue_free()
		game.get("obstacles").clear()
		for terrain in game.get("slopes").duplicate():
			if is_instance_valid(terrain):
				terrain.queue_free()
		game.get("slopes").clear()
		for gap in game.get("gaps").duplicate():
			if is_instance_valid(gap):
				gap.queue_free()
		game.get("gaps").clear()
		game.set("floor_level_y", 460.0)
		game.set("ceiling_level_y", 80.0)
		game.set("planned_floor_level_y", 460.0)
		game.set("planned_ceiling_level_y", 80.0)
		generator.set("_next_spawn_index", planned_events.size())
		# The normal main loop pre-spawns ghosts at their own trigger lead. Keep
		# only this source event in the generator so the capture follows one
		# flyby through its exit instead of an unrelated later ghost ending the run.
		var isolated_events: Array[Dictionary] = [target.duplicate(true)]
		generator.set("_events", isolated_events)
		generator.set("_next_spawn_index", isolated_events.size())
		generator.set("_configuration_failed", true)
		var ghost_key := str(game.call("_singleplayer_ghost_key", target))
		(game.get("_spawned_early_ghost_ids") as Dictionary)[ghost_key] = true
		var resolved_target: Dictionary = game.call("_resolve_singleplayer_ghost_event", target)
		print("GEN19_GHOST_RUNTIME_RESOLVE seed=%d version=%d source=%s resolved=%s" % [SEED, int(game.get("_active_seed_version")), JSON.stringify(target), JSON.stringify(resolved_target)])
		game.call("_spawn_course_event", target)
		var event_id := str(target.get("event_id", ""))
		var ghost := _find_ghost(game, event_id, float(target.get("course_distance", -1.0)))
		if not is_instance_valid(ghost) or int((ghost.get("event") as Dictionary).get("ghost_variant", 0)) != 3:
			var spawned_ghosts: Array = []
			for obstacle in game.get("obstacles"):
				if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards"):
					spawned_ghosts.append(obstacle.get("event"))
			print("GEN19_GHOST_RUNTIME_ADAPTER_FAILURE source=%s seed=%d active_version=%d ghost_nodes=%s" % [JSON.stringify(target), int(game.get("_active_seed")), int(game.get("_active_seed_version")), JSON.stringify(spawned_ghosts)])
			_fail("actual SP adapter did not create Gen19 variant 3 for source event")
			game.queue_free()
			continue
		event_id = str((ghost.get("event") as Dictionary).get("event_id", event_id))
		var records: Array[Dictionary] = []
		var phases: Dictionary = {}
		var flipped := false
		var activated_tick := -1
		var overtook := false
		var passed_in_view := false
		var exited_view := false
		var remained_alive := true
		var prior_runner_rect: Rect2 = player.call("get_player_rect")
		for step in range(MAX_TICKS):
			await get_tree().physics_frame
			if not is_instance_valid(game) or not is_instance_valid(player):
				remained_alive = false
				break
			var tick := int(game.get("_singleplayer_simulation_tick"))
			if not is_instance_valid(ghost):
				ghost = _find_ghost(game, event_id, float(target.get("course_distance", -1.0)))
			if is_instance_valid(ghost):
				var phase_now := str(ghost.get("phase"))
				if phase_now in ["warning", "dangerous"] and not bool(phases.get(phase_now, false)):
					phases[phase_now] = true
					var capture_path := output_dir.path_join("gen19-seed-%d-speed-%d-%s.png" % [SEED, int(speed), phase_now])
					_capture_phase_image.call_deferred(game, capture_path)
				var activation := int(ghost.get("activation_tick"))
				if step % 120 == 0:
					print("GEN19_GHOST_RUNTIME_PROGRESS seed=%d step=%d world_x=%.1f ghost=(%.1f,%.1f) phase=%s activation=%d game_over=%s" % [SEED, step, float(player.get("world_x")), ghost.global_position.x, ghost.global_position.y, phase_now, activation, str(bool(game.get("game_over")))])
				if activation >= 0 and activated_tick < 0:
					activated_tick = activation
					var snapshot: Dictionary = ghost.get("activation_state")
					print("GEN19_GHOST_RUNTIME_ACTIVATED seed=%d speed=%.0f event=%s tick=%d lane=%d origin_ceiling=%s player_world_x=%.1f ghost_x=%.1f" % [SEED, speed, event_id, activation, int(snapshot.get("lane", 0)), str(bool(target.get("from_ceiling", false))), float(player.get("world_x")), ghost.global_position.x])
				if not flipped and activated_tick >= 0 and tick >= activated_tick + 12 and bool(player.get("grounded")):
					player.call("_try_flip", -int(player.call("get_gravity_direction")), "gen19_runtime_capture")
					var target_gravity := 1 if int(ghost.get("activation_state").get("lane", 0)) == 1 else -1
					flipped = int(player.call("get_gravity_direction")) != target_gravity
				if tick % 6 == 0:
					var canvas := game.get_viewport().get_canvas_transform()
					var player_screen: Vector2 = canvas * player.global_position
					var ghost_screen: Vector2 = canvas * ghost.global_position
					var event: Dictionary = ghost.get("event")
					records.append({"tick": tick, "phase": str(ghost.get("phase")), "player_world_x": float(player.get("world_x")), "ghost_world_x": ghost.global_position.x, "player_screen": [player_screen.x, player_screen.y], "ghost_screen": [ghost_screen.x, ghost_screen.y], "ghost_lane": int(ghost.get("activation_state").get("lane", 0)), "from_ceiling": bool(event.get("from_ceiling", false))})
					if activated_tick >= 0 and str(ghost.get("phase")) in ["dangerous", "fading"] and float(ghost.global_position.x) > float(player.get("world_x")) + 34.0:
						overtook = true
					if overtook and ghost_screen.x >= 0.0 and ghost_screen.x <= game.get_viewport().get_visible_rect().size.x:
						passed_in_view = true
					if activated_tick >= 0 and str(ghost.get("phase")) in ["dangerous", "fading"] and ghost_screen.x > game.get_viewport().get_visible_rect().size.x + float(event.get("width", 72.0)) * 0.5:
						exited_view = true
					if str(ghost.get("phase")) in ["expired"]:
						break
					if exited_view:
						break
			if bool(game.get("game_over")):
				remained_alive = false
				var terminal_rect: Rect2 = player.call("get_player_rect")
				var terminal_fraction := float(game.call("_earliest_lethal_contact_fraction", prior_runner_rect, terminal_rect))
				var terminal_nodes: Array[String] = []
				for obstacle in game.get("obstacles"):
					if is_instance_valid(obstacle):
						var hitbox: Rect2 = obstacle.call("get_hitbox_rect") if obstacle.has_method("get_hitbox_rect") else Rect2()
						terminal_nodes.append("%s groups=%s pos=%s hitbox=%s" % [obstacle.name, str(obstacle.get_groups()), str(obstacle.global_position), str(hitbox)])
				print("GEN19_GHOST_RUNTIME_GAME_OVER seed=%d speed=%.0f step=%d tick=%d player=%s gravity=%d grounded=%s y=%.1f fraction=%f ghost_valid=%s ghost_phase=%s ghost_pose=%s nodes=%s" % [SEED, speed, step, int(game.get("_singleplayer_simulation_tick")), str(player.get("world_x")), int(player.call("get_gravity_direction")), str(bool(player.get("grounded"))), float(player.position.y), terminal_fraction, str(is_instance_valid(ghost)), str(ghost.get("phase")) if is_instance_valid(ghost) else "freed", str(ghost.global_position) if is_instance_valid(ghost) else "none", str(terminal_nodes)])
				break
			prior_runner_rect = player.call("get_player_rect")
		var trigger_x := float(target.get("course_distance", 0.0)) + 180.0 - float((ghost.get("event") as Dictionary).get("trigger_lead", 0.0)) if is_instance_valid(ghost) else NAN
		print("GEN19_GHOST_RUNTIME_RESULT seed=%d speed=%.0f event=%s trigger=%.1f activation=%d flipped=%s overtook=%s passed_in_view=%s exited_view=%s alive_through_pass=%s records=%s phases=%s" % [SEED, speed, event_id, trigger_x, activated_tick, str(flipped), str(overtook), str(passed_in_view), str(exited_view), str(remained_alive), JSON.stringify(records), JSON.stringify(phases)])
		if activated_tick < 0 or not flipped or not overtook or not passed_in_view or not exited_view or not bool(phases.get("warning", false)) or not bool(phases.get("dangerous", false)) or not remained_alive:
			_fail("runtime flyby did not show, permit alternate-lane passage, overtake and exit view at %.0fpx/s" % speed)
		game.queue_free()
		await get_tree().process_frame
	challenge.call("clear_challenge")
	Engine.time_scale = 1.0
	print("GEN19_GHOST_ACTUAL_RUNTIME failures=%d output=%s" % [failures, output_dir])
	get_tree().quit(1 if failures > 0 else 0)

func _record_phase(event_id: String, phase: String, phase_flags: Dictionary) -> void:
	phase_flags[phase] = true
	print("GEN19_GHOST_PHASE event=%s phase=%s" % [event_id, phase])

func _capture_phase_image(game: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(game):
		return
	var image := game.get_viewport().get_texture().get_image()
	var image_error := image.save_png(path)
	if image_error != OK:
		_fail("could not save capture %s" % path)

func _find_ghost(game: Node, event_id: String, course_distance: float) -> Node2D:
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards"):
			var event: Dictionary = obstacle.get("event")
			if str(event.get("event_id", "")) == event_id or absf(float(event.get("x", INF)) - 180.0 - course_distance) <= 0.5:
				return obstacle
	return null

func _fail(message: String) -> void:
	failures += 1
	push_error("GEN19_GHOST_ACTUAL_RUNTIME: " + message)
