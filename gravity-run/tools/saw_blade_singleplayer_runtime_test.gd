extends SceneTree

const SawModel := preload("res://systems/saw_blade_model.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge := root.get_node_or_null("ChallengeService")
	_check(challenge != null and bool(challenge.call("start_challenge_from_code", "GR9-100000014")), "normal challenge parser accepts the v9 demo seed")
	if challenge == null or not bool(challenge.get("active")):
		quit(1)
		return
	var game: Node = load("res://main.tscn").instantiate()
	game.set("demo_mode", true)
	root.add_child(game)
	await process_frame
	game.get("course_generator").ensure_horizon(45000.0, 500.0)
	var planned_saws: Array[Dictionary] = []
	for event in game.get("course_generator").get_planned_events():
		if str(event.get("kind", "")) == "saw":
			planned_saws.append(event)
	_check(not planned_saws.is_empty(), "v9 seed plans a shared saw encounter")
	var saw: Node2D
	for _frame in range(900):
		await physics_frame
		for obstacle in game.get("obstacles"):
			if is_instance_valid(obstacle) and obstacle.is_in_group("saw_blades"):
				saw = obstacle
				break
		if is_instance_valid(saw):
			break
	_check(is_instance_valid(saw), "real singleplayer main scene instantiates a saw from its planned encounter")
	if is_instance_valid(saw):
		for _activation_frame in range(240):
			if bool(saw.get("state").get("active", false)):
				break
			await physics_frame
		var scene_path := saw.scene_file_path
		_check(scene_path == "res://hazards/saw_blade.tscn", "singleplayer uses the shared SawBlade scene")
		var event: Dictionary = saw.get("event")
		_check(str(event.get("kind", "")) == "saw" and is_finite(float(event.get("x", NAN))) and float(event.get("spawn_lead", 0.0)) == SawModel.SPAWN_LEAD, "SP scene carries the versioned source event")
		var hitbox: Rect2 = saw.call("get_hitbox_rect")
		if bool(saw.get("state").get("active", false)):
			var player_rect := Rect2(hitbox.position + Vector2(13.0, 8.0), Vector2(34.0, 44.0))
			var contact_fraction := float(game.call("_earliest_lethal_contact_fraction", player_rect, player_rect))
			_check(is_finite(contact_fraction) and contact_fraction >= 0.0 and contact_fraction <= 1.0, "real SP collision resolver recognizes the shared saw hitbox as lethal")
			_check(int(game.call("_saw_endpoint_impact", player_rect, saw)) == HazardRules.PlayerImpact.LETHAL, "real SP endpoint collision recognizes the shared saw circle as lethal")
			var original_obstacles: Array = game.get("obstacles")
			game.set("obstacles", [saw])
			saw.set("_previous_state", saw.get("state").duplicate(true))
			var corner_rect := Rect2(hitbox.position + Vector2(57.0, 56.0), Vector2(34.0, 44.0))
			var corner_fraction := float(game.call("_earliest_lethal_contact_fraction", corner_rect, corner_rect))
			_check(is_inf(corner_fraction), "real SP collision resolver rejects a saw-circle corner miss")
			_check(hitbox.intersects(corner_rect) and not HazardRules.circle_intersects_rect(Vector2(float(saw.get("state").get("x")), float(saw.get("state").get("y"))), SawModel.RADIUS, corner_rect), "endpoint fixture overlaps the saw AABB corner but misses the saw circle")
			_check(int(game.call("_saw_endpoint_impact", corner_rect, saw)) == HazardRules.PlayerImpact.NONE, "real SP endpoint collision rejects the saw-circle corner miss")
			game.set("obstacles", original_obstacles)
		else:
			_check(not saw.visible, "a planned but not yet activated saw remains hidden")
	if failures == 0:
		print("SAW_SINGLEPLAYER_RUNTIME_PASS seed=100000014; scene=%s" % str(saw.scene_file_path if is_instance_valid(saw) else "missing"))
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
