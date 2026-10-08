extends Node
## Effect items against the real singleplayer scene (main.tscn), stepped at 60 Hz
## by calling main._physics_process directly like the campaign runtime test:
##  - bubble helmet survives the first lethal hit, then dies on a second one
##    before it recharges; the pop leaves the runner invulnerable for a moment;
##  - spike plate ignores spikes right after a flip, not later;
##  - coin magnet collects coins off the runner's line, not beyond its radius;
##  - regret boots reverse a flip during the first part of the flight, once, and
##    not after the window or without the boots;
##  - gravity anchor holds the middle of the course for 60 ticks, recharges
##    before it can be used again and is absent without the item;
##  - runs without equipment, campaign runs and unknown server slots/effects
##    behave as before.

const MainScene := preload("res://main.tscn")
const CoinScene := preload("res://collectibles/coin.tscn")
const BiomeRendererScript := preload("res://biomes/biome_renderer.gd")
const RunEffectsScript := preload("res://systems/run_effects.gd")
const TICK := 1.0 / 60.0

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _run() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	var original_state: Dictionary = InventoryService.inventory_state.duplicate(true)
	_check_run_effects_timers()
	await _check_unequipped_run()
	await _check_bubble_helmet()
	await _check_spike_plate()
	await _check_coin_magnet()
	_check_regret_and_anchor_timers()
	await _check_regret_boots()
	await _check_gravity_anchor()
	await _check_campaign_ignores_effects()
	_check_unknown_server_data_is_ignored()
	InventoryService.inventory_state = original_state
	BiomeRendererScript.set_locked_biome(&"")
	print("RUN_EFFECTS_RUNTIME_TEST failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _catalog_entry(item_id: String, slot: String, effect_id: String, level: int = 1) -> Dictionary:
	return {
		"item_id": item_id, "slot_type": slot, "rarity": "rare",
		"name_key": "item.%s.name" % item_id, "description_key": "item.%s.description" % item_id,
		"icon_key": item_id, "stat_modifiers": {}, "effect_id": effect_id, "effect_level": level,
		"catalog_version": 3,
	}

func _equip(entries: Array[Dictionary]) -> void:
	var items: Array = []
	var equipment := {}
	for entry in entries:
		var instance_id := "owned-%s" % entry.item_id
		items.append({"instance_id": instance_id, "item_id": entry.item_id})
		equipment[entry.slot_type] = instance_id
	InventoryService.inventory_state = {"catalog": entries, "items": items, "equipment": equipment, "wallet_coins": 0}

func _bubble() -> Dictionary:
	return _catalog_entry("helmet_bubble_01", "helmet", "bubble_shield")

func _plate() -> Dictionary:
	return _catalog_entry("helmet_spikeplate_01", "helmet", "spike_plate")

func _magnet() -> Dictionary:
	return _catalog_entry("backpack_magnet_01", "backpack", "coin_magnet")

func _regret() -> Dictionary:
	return _catalog_entry("boots_regret_01", "boots", "regret_flip")

func _anchor() -> Dictionary:
	return _catalog_entry("backpack_anchor_01", "backpack", "gravity_anchor")

func _make_game() -> Node:
	var game := MainScene.instantiate() as Node
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	return game

func _free_game(game: Node) -> void:
	game.queue_free()
	await get_tree().process_frame
	Campaign.clear_active()

## Removes generated hazards and coins so only fixtures can hurt or reward the runner.
func _purge_generated(game: Node) -> void:
	var kept_obstacles: Array[Node2D] = []
	for obstacle in game.get("obstacles"):
		if is_instance_valid(obstacle) and obstacle.has_meta("fixture"):
			kept_obstacles.append(obstacle)
		elif is_instance_valid(obstacle):
			obstacle.queue_free()
	game.set("obstacles", kept_obstacles)
	var kept_coins: Array[Node2D] = []
	for coin in game.get("coins"):
		if is_instance_valid(coin) and coin.has_meta("fixture"):
			kept_coins.append(coin)
		elif is_instance_valid(coin):
			coin.queue_free()
	game.set("coins", kept_coins)

func _step(game: Node, ticks: int) -> int:
	var done := 0
	for _i in range(ticks):
		if bool(game.get("game_over")):
			break
		_purge_generated(game)
		game.call("_physics_process", TICK)
		done += 1
		if done % 30 == 0:
			game.call("_process", TICK)
	return done

func _add_spike(game: Node, x: float, from_ceiling: bool = false) -> void:
	game.call("_spawn_spike_group", 1, from_ceiling, x)
	var obstacles: Array = game.get("obstacles")
	obstacles[obstacles.size() - 1].set_meta("fixture", true)

func _add_coin(game: Node, at: Vector2) -> Node2D:
	var coin := CoinScene.instantiate() as Node2D
	coin.connect("collected", Callable(game.get_node("RunState"), "add_coins"))
	coin.position = at
	coin.set_meta("fixture", true)
	game.add_child(coin)
	game.get("coins").append(coin)
	return coin

func _player(game: Node) -> Node:
	return game.get_node("Player")

func _effects(game: Node) -> RefCounted:
	return game.get("_run_effects")

func _check_run_effects_timers() -> void:
	var effects: RefCounted = RunEffectsScript.new()
	_check(not effects.has_any() and not effects.on_lethal_contact(), "RunEffects without a loadout absorbs nothing")
	var snapshot := RunLoadoutSnapshot.create([
		{"slot_type": "helmet", "instance_id": "h", "definition": ItemDefinition.from_catalog_entry(_bubble())},
	], 3, CharacterStats.new().get_base_stats())
	effects.configure(snapshot)
	_check(effects.bubble_ready() and effects.on_lethal_contact(), "the bubble absorbs a first lethal contact")
	_check(not effects.bubble_ready() and effects.is_invulnerable(), "the used bubble is empty and the runner invulnerable")
	for _i in range(RunEffectsScript.BUBBLE_INVULNERABLE_TICKS):
		_check_silent(effects.on_lethal_contact())
		effects.tick()
	_check(not effects.is_invulnerable() and not effects.on_lethal_contact(), "invulnerability ends and the empty bubble no longer helps")
	for _i in range(RunEffectsScript.BUBBLE_RECHARGE_TICKS[0]):
		effects.tick()
	_check(effects.bubble_ready(), "the bubble is ready again after 20 s (1200 ticks)")
	var entry: Dictionary = effects.get_hud_entries()[0]
	_check(is_equal_approx(float(entry.charge), 1.0) and bool(entry.ready), "a ready bubble shows a full meter")
	effects.on_lethal_contact()
	for _i in range(RunEffectsScript.BUBBLE_RECHARGE_TICKS[0] / 2):
		effects.tick()
	entry = effects.get_hud_entries()[0]
	_check(absf(float(entry.charge) - 0.5) < 0.01 and not bool(entry.ready), "the meter fills while recharging")
	_check(RunEffectsScript.BUBBLE_RECHARGE_TICKS[1] < RunEffectsScript.BUBBLE_RECHARGE_TICKS[0] and RunEffectsScript.BUBBLE_RECHARGE_TICKS[2] < RunEffectsScript.BUBBLE_RECHARGE_TICKS[1], "higher levels recharge faster")

func _check_silent(_value: bool) -> void:
	pass

func _check_unequipped_run() -> void:
	InventoryService.inventory_state = {}
	var game: Node = await _make_game()
	_check(not _effects(game).has_any(), "no equipment means no effects")
	_check(not bool(game.get_node("RunState").get("modified")), "an unequipped run is not modified")
	_check((game.get("hud").get("effect_entries") as Array).is_empty(), "no HUD effect row without effect items")
	_add_spike(game, float(_player(game).get("world_x")) + 120.0)
	_step(game, 120)
	_check(bool(game.get("game_over")), "without equipment a spike ends the run")
	await _free_game(game)

func _check_bubble_helmet() -> void:
	_equip([_bubble()])
	var game: Node = await _make_game()
	_check(bool(game.get_node("RunState").get("modified")), "a run with a bubble helmet is flagged modified")
	_check((game.get("hud").get("effect_entries") as Array).size() == 1, "the HUD shows one effect meter")
	var start_x := float(_player(game).get("world_x"))
	_add_spike(game, start_x + 120.0)
	_step(game, 100)
	_check(not bool(game.get("game_over")), "the bubble helmet survives the first lethal hit")
	_check(not _effects(game).bubble_ready(), "the bubble is spent after the hit")
	_check(float(_player(game).get("world_x")) > start_x + 200.0, "the runner got clear of the hazard that hit it")
	var entries: Array = game.get("hud").get("effect_entries")
	_check(entries.size() == 1 and not bool(entries[0].ready) and float(entries[0].charge) < 0.2, "the HUD meter shows the recharge starting")
	_add_spike(game, float(_player(game).get("world_x")) + 120.0)
	_step(game, 100)
	_check(bool(game.get("game_over")), "a second hit before the recharge ends the run")
	await _free_game(game)
	# A hazard that is still touching when the bubble pops must not kill on the next tick.
	var game_two: Node = await _make_game()
	_add_spike(game_two, float(_player(game_two).get("world_x")))
	var survived := _step(game_two, 30)
	_check(survived == 30 and not bool(game_two.get("game_over")), "the runner is not killed on the tick after the pop, even inside the hazard")
	await _free_game(game_two)

func _check_spike_plate() -> void:
	_equip([_plate()])
	var game: Node = await _make_game()
	var player := _player(game)
	_add_spike(game, float(player.get("world_x")))
	player.call("_try_flip", -1)
	_step(game, 25)
	_check(not bool(game.get("game_over")), "the spike plate ignores spikes right after a flip")
	_step(game, 60)
	_check(not bool(game.get("game_over")) and int(player.call("get_gravity_direction")) == -1, "the runner reached the ceiling unhurt")
	_check(not _effects(game).is_spike_immune(), "the spike immunity has ended after about a second")
	_add_spike(game, float(player.get("world_x")) + 150.0, true)
	_step(game, 90)
	_check(bool(game.get("game_over")), "later spikes are lethal again")
	await _free_game(game)
	# Control: without the plate the same flip-over-spike dies.
	InventoryService.inventory_state = {}
	var control: Node = await _make_game()
	_add_spike(control, float(_player(control).get("world_x")))
	_player(control).call("_try_flip", -1)
	_step(control, 25)
	_check(bool(control.get("game_over")), "without the plate the same spike kills")
	await _free_game(control)

func _check_coin_magnet() -> void:
	_equip([_magnet()])
	var game: Node = await _make_game()
	var player := _player(game)
	var run_state: Node = game.get_node("RunState")
	var origin: Vector2 = player.position
	_add_coin(game, origin + Vector2(50.0, -70.0))
	var far_coin := _add_coin(game, origin + Vector2(120.0, -230.0))
	_step(game, 40)
	_check(int(run_state.get("coins")) == 1, "the magnet collects a coin off the runner's line")
	_check(is_instance_valid(far_coin) and not bool(far_coin.call("is_collected")), "a coin beyond the magnet radius is left alone")
	_check(float(RunEffectsScript.MAGNET_RADIUS[2]) > float(RunEffectsScript.MAGNET_RADIUS[0]), "the magnet radius grows with level")
	await _free_game(game)
	InventoryService.inventory_state = {}
	var control: Node = await _make_game()
	var control_origin: Vector2 = _player(control).position
	_add_coin(control, control_origin + Vector2(50.0, -70.0))
	_step(control, 40)
	_check(int(control.get_node("RunState").get("coins")) == 0, "without the magnet the same coin is missed")
	await _free_game(control)

func _check_campaign_ignores_effects() -> void:
	_equip([_bubble(), _magnet()])
	Campaign.start_level(CampaignCatalog.get_level(&"1-1"))
	var game: Node = await _make_game()
	_check(not _effects(game).has_any() and not bool(game.get_node("RunState").get("modified")), "campaign stages run without effect items")
	await _free_game(game)

func _check_unknown_server_data_is_ignored() -> void:
	var boots := _catalog_entry("boots_runner_01", "boots", "")
	boots["stat_modifiers"] = {"run_speed_percent": 250}
	var future_helmet := _catalog_entry("helmet_laser_01", "helmet", "laser_beam")
	var cape := _catalog_entry("cape_future_01", "cape", "")
	InventoryService.inventory_state = {
		"catalog": [boots, future_helmet, cape],
		"items": [
			{"instance_id": "i-boots", "item_id": "boots_runner_01"},
			{"instance_id": "i-helmet", "item_id": "helmet_laser_01"},
			{"instance_id": "i-cape", "item_id": "cape_future_01"},
		],
		"equipment": {"boots": "i-boots", "helmet": "i-helmet", "cape": "i-cape"},
	}
	var snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	_check(snapshot.is_valid(), "unknown slots and effects from the server do not invalidate the loadout")
	_check(not snapshot.has_effects(), "an unknown effect is dropped")
	_check(int(snapshot.get_resolved_stats().get("run_speed_percent", 0)) > 10000, "known items in the same loadout still apply")


func _effects_for(entries: Array[Dictionary], level: int = 1) -> RefCounted:
	var loadout: Array = []
	for entry in entries:
		loadout.append({"slot_type": entry.slot_type, "instance_id": "i-%s" % entry.item_id, "definition": ItemDefinition.from_catalog_entry(entry)})
	var effects: RefCounted = RunEffectsScript.new()
	effects.configure(RunLoadoutSnapshot.create(loadout, 3, CharacterStats.new().get_base_stats()))
	return effects

func _check_regret_and_anchor_timers() -> void:
	var regret := _effects_for([_regret()])
	_check(regret.has_any() and not regret.can_reverse_flip(), "regret boots cannot reverse before a flip")
	regret.on_flip()
	_check(regret.can_reverse_flip(), "a flip opens the reverse window")
	for _i in range(RunEffectsScript.REGRET_WINDOW_TICKS[0] - 1):
		regret.tick()
	_check(regret.can_reverse_flip(), "the window is still open on its last tick")
	regret.tick()
	_check(not regret.can_reverse_flip() and not regret.consume_reverse_flip(), "the window closes after its tick count")
	regret.on_flip()
	_check(regret.consume_reverse_flip() and not regret.consume_reverse_flip(), "one reverse per flip")
	regret.on_flip()
	regret.on_land()
	_check(not regret.can_reverse_flip(), "landing closes the window")
	_check(RunEffectsScript.REGRET_WINDOW_TICKS[1] > RunEffectsScript.REGRET_WINDOW_TICKS[0] and RunEffectsScript.REGRET_WINDOW_TICKS[2] > RunEffectsScript.REGRET_WINDOW_TICKS[1], "higher levels widen the window")
	var anchor := _effects_for([_anchor()])
	_check(anchor.anchor_ready() and anchor.has_anchor() and anchor.has_any(), "the anchor starts ready")
	_check(anchor.activate_anchor() and anchor.is_anchor_gliding() and not anchor.activate_anchor(), "the anchor cannot be fired twice")
	_check(not anchor.is_invulnerable() and not anchor.on_lethal_contact(), "gliding gives no protection from hazards")
	for _i in range(RunEffectsScript.ANCHOR_GLIDE_TICKS - 1):
		anchor.tick()
	_check(anchor.is_anchor_gliding(), "the glide lasts 60 ticks")
	anchor.tick()
	_check(not anchor.is_anchor_gliding() and not anchor.anchor_ready() and not anchor.activate_anchor(), "the glide ends and the anchor is recharging")
	var entry: Dictionary = anchor.get_hud_entries()[0]
	_check(entry.effect_id == "gravity_anchor" and not bool(entry.ready) and float(entry.charge) < 0.01, "the HUD meter starts empty after the glide")
	for _i in range(RunEffectsScript.ANCHOR_RECHARGE_TICKS[0] - 1):
		anchor.tick()
	_check(not anchor.anchor_ready(), "the anchor is still charging one tick before 15 s")
	anchor.tick()
	_check(anchor.anchor_ready() and anchor.activate_anchor(), "the anchor is ready after 15 s (900 ticks)")
	_check(RunEffectsScript.ANCHOR_RECHARGE_TICKS[0] == 900 and RunEffectsScript.ANCHOR_RECHARGE_TICKS[1] == 720 and RunEffectsScript.ANCHOR_RECHARGE_TICKS[2] == 540, "recharge is 15 s, 12 s, 9 s by level")

func _check_regret_boots() -> void:
	_equip([_regret()])
	var game: Node = await _make_game()
	var player := _player(game)
	_check(bool(game.get_node("RunState").get("modified")), "a run with regret boots is flagged modified")
	_check((game.get("hud").get("effect_entries") as Array).size() == 1, "the HUD shows the regret boots")
	_step(game, 5)
	player.call("_try_flip", -1)
	_step(game, 5)
	_check(int(player.call("get_gravity_direction")) == -1 and not bool(player.get("grounded")), "the first flip sends the runner up")
	player.call("_try_flip", 1)
	_check(int(player.call("get_gravity_direction")) == 1 and float(player.get("vertical_speed")) > 0.0, "a second press inside the window reverses the flip")
	_step(game, 3)
	player.call("_try_flip", -1)
	_check(int(player.call("get_gravity_direction")) == 1, "only one reverse per flip")
	var landed := 3 + _step_until_grounded(game)
	_check(bool(player.get("grounded")) and int(player.call("get_gravity_direction")) == 1 and landed < 60, "the runner lands back on the surface it left (%d ticks)" % landed)
	_check(not bool(game.get("game_over")), "the reversed flight is survivable")
	# A full flight outlasts the widest window.
	_step(game, 30)
	player.call("_try_flip", -1)
	var flight_ticks := _step_until_grounded(game)
	print("INFO full flip flight takes %d ticks" % flight_ticks)
	_check(flight_ticks > RunEffectsScript.REGRET_WINDOW_TICKS[2] and int(player.call("get_gravity_direction")) == -1, "a full flight is longer than the widest window")
	# A new flip gives a new reverse; a press after the window is ignored.
	_step(game, 30)
	player.call("_try_flip", 1)
	_step(game, RunEffectsScript.REGRET_WINDOW_TICKS[0] + 2)
	_check(not bool(player.get("grounded")), "the runner is still in the air after the window")
	player.call("_try_flip", -1)
	_check(int(player.call("get_gravity_direction")) == 1, "a press after the window is ignored")
	_step_until_grounded(game)
	_step(game, 30)
	player.call("_try_flip", -1)
	_step(game, RunEffectsScript.REGRET_WINDOW_TICKS[0] - 1)
	player.call("_try_flip", 1)
	_check(int(player.call("get_gravity_direction")) == 1, "a press on the last tick of the window still reverses")
	await _free_game(game)
	InventoryService.inventory_state = {}
	var control: Node = await _make_game()
	var control_player := _player(control)
	_check(not _effects(control).has_any(), "no regret effect without the boots")
	_step(control, 5)
	control_player.call("_try_flip", -1)
	_step(control, 5)
	control_player.call("_try_flip", 1)
	_check(int(control_player.call("get_gravity_direction")) == -1, "without the boots the second press is ignored as before")
	await _free_game(control)

func _step_until_grounded(game: Node) -> int:
	var ticks := 0
	while not bool(_player(game).get("grounded")) and ticks < 200:
		ticks += _step(game, 1)
		if bool(game.get("game_over")):
			break
	return ticks

func _check_gravity_anchor() -> void:
	_equip([_anchor()])
	var game: Node = await _make_game()
	var player := _player(game)
	_check(bool(game.get_node("RunState").get("modified")), "a run with the gravity anchor is flagged modified")
	_check((game.get("hud").get("effect_entries") as Array).size() == 1, "the HUD shows the anchor")
	_check(game.get_node("HUDLayer/GravityAnchorButton").visible, "the touch button is shown with the anchor")
	_step(game, 5)
	var middle := (float(game.get("floor_level_y")) + float(game.get("ceiling_level_y"))) * 0.5
	_check(bool(player.call("try_use_anchor")), "the anchor fires when ready")
	var held := 0
	for tick_index in range(RunEffectsScript.ANCHOR_GLIDE_TICKS):
		_step(game, 1)
		if absf(player.position.y - middle) < 1.0:
			held += 1
	_check(held >= RunEffectsScript.ANCHOR_GLIDE_TICKS - 8 and not bool(game.get("game_over")), "the runner holds the middle for the glide (%d of 60 ticks)" % held)
	_check(not bool(player.call("try_use_anchor")), "recharge blocks reuse")
	_step(game, 10)
	_check(absf(player.position.y - middle) > 20.0 and int(player.call("get_gravity_direction")) == 1 and float(player.get("vertical_speed")) > 0.0, "normal gravity resumes in the old direction")
	var entries: Array = game.get("hud").get("effect_entries")
	_check(entries.size() == 1 and not bool(entries[0].ready) and float(entries[0].charge) < 0.1, "the HUD meter shows the recharge")
	await _free_game(game)
	# Hazards still hit while gliding: a spike on the floor kills a runner that
	# was holding the middle and then drops back onto it.
	var hit_game: Node = await _make_game()
	var hit_player := _player(hit_game)
	_step(hit_game, 5)
	hit_player.call("try_use_anchor")
	hit_game.call("_spawn_spike_group", 10, false, float(hit_player.get("world_x")) + 420.0)
	var hit_obstacles: Array = hit_game.get("obstacles")
	hit_obstacles[hit_obstacles.size() - 1].set_meta("fixture", true)
	_step(hit_game, 50)
	_check(not bool(hit_game.get("game_over")), "the glide passes over a floor spike")
	_step(hit_game, 80)
	_check(bool(hit_game.get("game_over")), "after the glide the runner falls onto the spike and dies")
	await _free_game(hit_game)
	InventoryService.inventory_state = {}
	var control: Node = await _make_game()
	_check(not bool(_player(control).call("try_use_anchor")), "without the item the anchor does nothing")
	_check(not control.get_node("HUDLayer/GravityAnchorButton").visible, "no touch button without the anchor")
	_check((control.get("hud").get("effect_entries") as Array).is_empty(), "no anchor in the HUD without the item")
	await _free_game(control)
