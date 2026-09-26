extends Node

signal top_runs_received(runs: Array, error_message: String)
signal submission_finished(success: bool, error_message: String)

func fetch_top_runs() -> void:
	push_error("LeaderboardProvider.fetch_top_runs must be implemented by a provider.")

func submit_run(_player_name: String, _distance_m: int, _coins: int) -> void:
	push_error("LeaderboardProvider.submit_run must be implemented by a provider.")
