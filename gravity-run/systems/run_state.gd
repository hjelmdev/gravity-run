extends Node

signal stats_changed(distance_m: float, coins: int)
signal run_started
signal run_finished(distance_m: float, coins: int)
signal achievement_metrics_changed(coins: int, gravity_flips: int, hazards_seen: Array)
signal loot_pending_changed(count: int)

var distance_m := 0.0
var coins := 0
var gravity_flips := 0
var hazards_seen: Dictionary = {}
var active := false
var loadout_snapshot: Resource
var loadout_signature := ""
var loot_pickup_indexes: Array[int] = []
var last_run_id := ""

func set_loadout_snapshot(snapshot: Resource) -> void:
	if snapshot == null or not snapshot.has_method("is_valid") or not bool(snapshot.call("is_valid")):
		loadout_snapshot = null
		loadout_signature = ""
		return
	loadout_snapshot = snapshot
	loadout_signature = str(snapshot.call("get_loadout_signature"))

func start_run() -> void:
	distance_m = 0.0
	coins = 0
	gravity_flips = 0
	hazards_seen.clear()
	loot_pickup_indexes.clear()
	last_run_id = ""
	active = true
	stats_changed.emit(distance_m, coins)
	_emit_achievement_metrics()
	run_started.emit()
	loot_pending_changed.emit(0)

func record_loot_pickup(pickup_index: int) -> void:
	if not active or pickup_index < 1 or loot_pickup_indexes.has(pickup_index):
		return
	loot_pickup_indexes.append(pickup_index)
	loot_pickup_indexes.sort()
	loot_pending_changed.emit(loot_pickup_indexes.size())

func add_distance(amount: float) -> void:
	if not active:
		return
	distance_m += amount
	stats_changed.emit(distance_m, coins)

func add_coins(amount: int) -> void:
	if not active or amount <= 0:
		return
	coins += amount
	stats_changed.emit(distance_m, coins)
	_emit_achievement_metrics()

func record_gravity_flip() -> void:
	if not active:
		return
	gravity_flips += 1
	_emit_achievement_metrics()

func record_hazard_seen(hazard_id: String) -> void:
	if not active or hazard_id.is_empty() or hazards_seen.has(hazard_id):
		return
	hazards_seen[hazard_id] = true
	_emit_achievement_metrics()

func get_hazards_seen() -> Array[String]:
	var result: Array[String] = []
	for hazard_id in hazards_seen.keys():
		result.append(str(hazard_id))
	result.sort()
	return result

func _emit_achievement_metrics() -> void:
	achievement_metrics_changed.emit(coins, gravity_flips, get_hazards_seen())

func finish_run() -> void:
	if not active:
		return
	active = false
	PlayerProfile.record_distance(distance_m)
	last_run_id = AccountProgress.record_completed_run(int(distance_m / 10.0), coins, gravity_flips, get_hazards_seen(), loot_pickup_indexes)
	run_finished.emit(distance_m, coins)
