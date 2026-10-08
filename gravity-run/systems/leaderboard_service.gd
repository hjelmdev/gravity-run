extends Node

signal top_runs_received(runs: Array, error_message: String)
signal submission_finished(success: bool, error_message: String)

const SupabaseProvider = preload("res://systems/supabase_leaderboard_provider.gd")

var _provider: Node

func _ready() -> void:
	_provider = SupabaseProvider.new()
	_provider.name = "SupabaseLeaderboardProvider"
	_provider.top_runs_received.connect(func(runs: Array, message: String) -> void:
		top_runs_received.emit(runs, message))
	_provider.submission_finished.connect(func(success: bool, message: String) -> void:
		submission_finished.emit(success, message))
	add_child(_provider)

func fetch_top_runs() -> void:
	_provider.fetch_top_runs()

func submit_run(player_name: String, distance_m: int, coins: int, modified: bool = false) -> void:
	_provider.submit_run(player_name, distance_m, coins, modified)
