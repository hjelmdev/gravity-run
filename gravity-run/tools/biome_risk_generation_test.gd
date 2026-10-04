extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const Biomes := preload("res://biomes/biome_renderer.gd")
const Planner := preload("res://systems/shared_coin_planner.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const RunnerMotion := preload("res://systems/runner_motion.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const WorldSimulation := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")

const SEEDS := [100000014, 100000042, 100000123, 100000777, 100000888, 100001111, 100002222, 100004321]
var failures: Array[String] = []
var risk_planner := Planner.new()

func _initialize() -> void:
	var totals := {"classic": {}, "cave": {}, "haunted": {}}
	var risk_total := 0
	var risk_rows: Array[Dictionary] = []
	for seed_value in SEEDS:
		var built: Dictionary = Builder.new().build(seed_value, 100000, Generator.GENERATOR_VERSION_12)
		var manifest: Variant = built.get("manifest")
		_check(manifest != null, "seed %d builds Gen12 manifest: %s" % [seed_value, str(built.get("error", ""))])
		if manifest == null:
			continue
		var repeated: Variant = Builder.new().build(seed_value, 100000, Generator.GENERATOR_VERSION_12).get("manifest")
		_check(repeated != null and manifest.manifest_hash == repeated.manifest_hash, "seed %d manifest deterministic" % seed_value)
		for event in manifest.events:
			var biome := Biomes.biome_id_at(float(event.x) - float(manifest.start_x))
			var kind := str(event.get("kind", ""))
			totals[biome][kind] = int(totals[biome].get(kind, 0)) + 1
		var risk_coins: Array[Dictionary] = []
		for coin_value in manifest.collectibles:
			if str(coin_value.get("formation", "")) == "risk":
				risk_coins.append(coin_value)
		_check(_validate_risk_coins(manifest, risk_coins), "seed %d risk rows have supported, clear geometry and a real blocker lead" % seed_value)
		if not risk_coins.is_empty():
			var seen_rows: Dictionary = {}
			for coin in risk_coins:
				var risk_event_id := str(coin.get("risk_event_id", ""))
				if not seen_rows.has(risk_event_id):
					seen_rows[risk_event_id] = true
					risk_rows.append({"manifest": manifest, "coin": coin})
		risk_total += risk_coins.size()
		var streamed := _stream_coins(manifest)
		if streamed != manifest.collectibles:
			var divergence := 0
			while divergence < mini(streamed.size(), manifest.collectibles.size()) and streamed[divergence] == manifest.collectibles[divergence]:
				divergence += 1
			print("STREAM_DIFF seed=%d index=%d stream_size=%d full_size=%d stream=%s full=%s" % [seed_value, divergence, streamed.size(), manifest.collectibles.size(), str(streamed[divergence]) if divergence < streamed.size() else "EOF", str(manifest.collectibles[divergence]) if divergence < manifest.collectibles.size() else "EOF"])
		_check(streamed == manifest.collectibles, "seed %d streaming coin prefix equals full manifest" % seed_value)
	var cave_rock_saw := int(totals.cave.get("rock", 0)) + int(totals.cave.get("saw", 0))
	var classic_rock_saw := int(totals.classic.get("rock", 0)) + int(totals.classic.get("saw", 0))
	var haunted_ghost := int(totals.haunted.get("ghost", 0))
	var classic_ghost := int(totals.classic.get("ghost", 0))
	var risk_lane_coins := {"floor": 0, "ceiling": 0}
	for candidate in risk_rows:
		var candidate_coin: Dictionary = candidate.coin
		var candidate_manifest: Resource = candidate.manifest
		var candidate_lane := "ceiling" if float(candidate_coin.world_y) < (float(candidate_manifest.initial_floor_y) + float(candidate_manifest.initial_ceiling_y)) * 0.5 else "floor"
		risk_lane_coins[candidate_lane] = int(risk_lane_coins[candidate_lane]) + 3
	_check(int(risk_lane_coins.floor) > 0 and int(risk_lane_coins.ceiling) > 0, "bounded cohort generates optional risk rows on both ceiling and floor")
	for lane_ceiling in [false, true]:
		for speed in [250.0, 500.0, 750.0]:
			var route_proven := false
			for candidate in risk_rows:
				var coin: Dictionary = candidate.coin
				var manifest: Resource = candidate.manifest
				var coin_lane_ceiling := float(coin.world_y) < (float(manifest.initial_floor_y) + float(manifest.initial_ceiling_y)) * 0.5
				if coin_lane_ceiling != lane_ceiling or float(coin.world_x) > 18000.0:
					continue
				if _risk_route_survives(manifest, coin, speed, 2.0) and _safe_avoid_route_survives(manifest, coin, speed):
					route_proven = true
					print("RISK_ROUTE_PASS lane=%s speed=%.0f seed=%d event=%s" % ["ceiling" if lane_ceiling else "floor", speed, int(manifest.seed_value), str(coin.get("risk_event_id", ""))])
					break
			_check(route_proven, "%s risk pickup and opposite-lane avoid route survive full shared contact simulation at %.0f px/s" % ["ceiling" if lane_ceiling else "floor", speed])
	_check(cave_rock_saw > classic_rock_saw, "Cave cohort has more rock/saw encounters than Classic")
	_check(haunted_ghost > classic_ghost, "Haunted cohort has more ghost encounters than Classic")
	_check(risk_total >= 18, "short test cohort contains repeated optional risk formations (%d coins)" % risk_total)
	print("BIOME_RISK_GENERATION_TEST failures=%d seeds=%d totals=%s risk_coins=%d" % [failures.size(), SEEDS.size(), JSON.stringify(totals), risk_total])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _validate_risk_coins(manifest: Resource, risk_coins: Array[Dictionary]) -> bool:
	var groups: Dictionary = {}
	var surface := SurfaceIndex.new()
	surface.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
	for coin in risk_coins:
		var event_id := str(coin.get("risk_event_id", ""))
		var event: Dictionary = {}
		for candidate in manifest.events:
			if str(candidate.get("event_id", "")) == event_id:
				event = candidate
				break
		if event.is_empty() or str(event.get("kind", "")) not in ["block", "spikes"]:
			print("RISK_FAIL missing-event coin=%s eventid=%s" % [str(coin), event_id])
			return false
		groups[event_id] = groups.get(event_id, [])
		(groups[event_id] as Array).append(coin)
		var coin_x := float(coin.world_x)
		var coin_y := float(coin.world_y)
		var ceiling_lane := coin_y < (float(manifest.initial_floor_y) + float(manifest.initial_ceiling_y)) * 0.5
		var support: Dictionary = surface.surface_at(coin_x, ceiling_lane)
		var floor_surface: Dictionary = surface.surface_at(coin_x, false)
		var ceiling_surface: Dictionary = surface.surface_at(coin_x, true)
		if not bool(support.get("supported", false)) or not bool(floor_surface.get("supported", false)) or not bool(ceiling_surface.get("supported", false)) or float(floor_surface.y) - float(ceiling_surface.y) < 190.0:
			print("RISK_FAIL support coin=%s source=%s floor=%s ceiling=%s" % [str(coin), str(support), str(floor_surface), str(ceiling_surface)])
			return false
		if Planner._position_blocked(coin_x, coin_y, manifest.events):
			print("RISK_FAIL blocked coin=%s event=%s" % [str(coin), str(event)])
			return false
	for event_id in groups:
		var row: Array = groups[event_id]
		if row.size() != 3:
			print("RISK_FAIL row size=%d id=%s" % [row.size(), event_id])
			return false
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.world_x) < float(b.world_x))
		if risk_planner._risk_has_unmodeled_motion(float(row[0].world_x), manifest.events):
			print("RISK_FAIL unmodeled-moving-hazard event=%s row=%s" % [event_id, str(row)])
			return false
		if not risk_planner._risk_support_corridor_clear(float(row[0].world_x), surface):
			print("RISK_FAIL unsupported-transition-corridor event=%s row=%s" % [event_id, str(row)])
			return false
		var row_lane_ceiling := float(row[0].world_y) < (float(manifest.initial_floor_y) + float(manifest.initial_ceiling_y)) * 0.5
		for index in range(1, row.size()):
			if not is_equal_approx(float(row[index].world_x) - float(row[index - 1].world_x), 38.0):
				print("RISK_FAIL spacing row=%s" % str(row))
				return false
		for coin in row:
			var coin_x := float(coin.world_x)
			var row_surface: Dictionary = surface.surface_at(coin_x, row_lane_ceiling)
			var expected_y := float(row_surface.y) + 34.0 if row_lane_ceiling else float(row_surface.y) - 34.0
			if not bool(row_surface.get("supported", false)) or absf(float(coin.world_y) - expected_y) > 1.0:
				print("RISK_FAIL terrain-follow row=%s coin=%s surface=%s" % [str(row), str(coin), str(row_surface)])
				return false
		var event: Dictionary = {}
		for candidate in manifest.events:
			if str(candidate.get("event_id", "")) == str(event_id):
				event = candidate
				break
		var lead := float(event.get("x", 0.0)) - float(row.back().world_x)
		if lead < 1020.0 or lead > 1250.0:
			print("RISK_FAIL lead=%f event=%s row=%s" % [lead, str(event), str(row)])
			return false
	return true

func _stream_coins(manifest: Resource) -> Array[Dictionary]:
	var planner := Planner.new()
	planner.reset(int(manifest.seed_value), float(manifest.start_x), 2, 1.0)
	var coins: Array[Dictionary] = []
	for end_x in range(int(manifest.start_x) + 2000, int(manifest.finish_x) + 1, 2000):
		var lookahead_events: Array[Dictionary] = []
		for event in manifest.events:
			if float(event.x) <= float(end_x) + 1400.0:
				lookahead_events.append(event)
		coins.append_array(planner.extend(float(end_x), lookahead_events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y), 0))
	return coins

func _risk_route_survives(manifest: Resource, risk_coin: Dictionary, speed: float, cooldown_multiplier: float) -> bool:
	return _simulate_risk_path(manifest, risk_coin, speed, cooldown_multiplier, true)

func _safe_avoid_route_survives(manifest: Resource, risk_coin: Dictionary, speed: float) -> bool:
	return _simulate_risk_path(manifest, risk_coin, speed, 1.0, false)

func _simulate_risk_path(manifest: Resource, risk_coin: Dictionary, speed: float, cooldown_multiplier: float, collect_risk: bool) -> bool:
	var row: Array[Dictionary] = []
	for coin_value in manifest.collectibles:
		if str(coin_value.get("risk_event_id", "")) == str(risk_coin.get("risk_event_id", "")):
			row.append(coin_value)
	row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.world_x) < float(b.world_x))
	if row.size() != 3:
		return false
	var blocker: Dictionary = {}
	for candidate in manifest.events:
		if str(candidate.get("event_id", "")) == str(risk_coin.get("risk_event_id", "")):
			blocker = candidate
			break
	if blocker.is_empty() or str(blocker.get("kind", "")) not in ["block", "spikes"]:
		return false
	var coin_lane_ceiling := float(risk_coin.world_y) < (float(manifest.initial_floor_y) + float(manifest.initial_ceiling_y)) * 0.5
	if coin_lane_ceiling != bool(blocker.get("from_ceiling", false)):
		return false
	var safe_lane_ceiling := not coin_lane_ceiling
	var coin_direction := -1 if coin_lane_ceiling else 1
	var safe_direction := -coin_direction
	var surface := SurfaceIndex.new()
	surface.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
	var player_start_x := float(row.front().world_x) - 650.0
	var safe_surface: Dictionary = surface.surface_at(player_start_x, safe_lane_ceiling)
	if not bool(safe_surface.get("supported", false)):
		return false
	var state := {
		"world_x": player_start_x,
		"y": float(safe_surface.y) + (RunnerMotion.SIZE.y * 0.5 if safe_lane_ceiling else -RunnerMotion.SIZE.y * 0.5),
		"vertical_speed": 0.0,
		"gravity_direction": safe_direction,
		"grounded": true,
		"cooldown": 0.0,
	}
	if collect_risk and not RunnerMotion.try_flip(state, coin_direction, cooldown_multiplier):
		return false
	var target_ids: Dictionary = {}
	for coin_value in row:
		target_ids[str(coin_value.entity_id)] = true
	var contacted: Dictionary = {}
	var sim := WorldSimulation.new()
	if not str(sim.configure(manifest)).is_empty():
		return false
	var route_end_x := float(blocker.x) + float(blocker.get("width", 60.0)) * 0.5 + RunnerMotion.SIZE.x
	var start_tick := maxi(0, floori((player_start_x - float(manifest.start_x)) / speed * 60.0))
	var end_tick := ceili((route_end_x - float(manifest.start_x)) / speed * 60.0)
	for tick_value in range(1, end_tick + 1):
		if not sim.step_to(tick_value):
			return false
		if tick_value <= start_tick:
			continue
		var previous := state.duplicate(true)
		var next_x := minf(float(state.world_x) + speed / 60.0, route_end_x + 1.0)
		var floor_info: Dictionary = sim.surface_at(next_x, false)
		var ceiling_info: Dictionary = sim.surface_at(next_x, true)
		RunnerMotion.advance_vertical(state, 1.0 / 60.0, float(floor_info.y), float(ceiling_info.y), bool(floor_info.get("supported", false)), bool(ceiling_info.get("supported", false)))
		state["world_x"] = next_x
		for contact in sim.coin_contacts_swept(previous, state):
			var contact_id := str(contact.get("entity_id", ""))
			if target_ids.has(contact_id):
				contacted[contact_id] = true
		var swept_terminal := sim.first_static_terminal_contact(previous, state)
		if not swept_terminal.is_empty():
			return false
		var endpoint_contact := sim.player_contact(state)
		if not endpoint_contact.is_empty():
			return false
		if collect_risk and float(state.world_x) >= float(row.back().world_x) and int(state.get("gravity_direction", 0)) == coin_direction and bool(state.get("grounded", false)) and float(state.get("cooldown", 0.0)) <= 0.0:
			RunnerMotion.try_flip(state, safe_direction, cooldown_multiplier)
	if collect_risk:
		return contacted.size() == target_ids.size() and int(state.get("gravity_direction", 0)) == safe_direction and bool(state.get("grounded", false))
	return contacted.is_empty()

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
