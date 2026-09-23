extends Node

const SAVE_PATH := "user://gravity_run_profile.cfg"

var wallet_coins := 0
var best_distance_m := 0.0

func _ready() -> void:
	_load_profile()

func bank_coins(amount: int) -> void:
	if amount <= 0:
		return
	wallet_coins += amount
	_save_profile()

func record_distance(distance_m: float) -> void:
	if distance_m <= best_distance_m:
		return
	best_distance_m = distance_m
	_save_profile()

func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	wallet_coins = int(config.get_value("profile", "wallet_coins", 0))
	best_distance_m = float(config.get_value("profile", "best_distance_m", 0.0))

func _save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "wallet_coins", wallet_coins)
	config.set_value("profile", "best_distance_m", best_distance_m)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save Gravity Run profile (error %s)." % error)
