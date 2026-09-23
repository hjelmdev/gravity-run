extends Node

signal stats_changed(distance_m: float, coins: int)
signal run_started
signal run_finished(distance_m: float, coins: int)

var distance_m := 0.0
var coins := 0
var active := false

func start_run() -> void:
	distance_m = 0.0
	coins = 0
	active = true
	stats_changed.emit(distance_m, coins)
	run_started.emit()

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

func finish_run() -> void:
	if not active:
		return
	active = false
	PlayerProfile.bank_coins(coins)
	PlayerProfile.record_distance(distance_m)
	run_finished.emit(distance_m, coins)
