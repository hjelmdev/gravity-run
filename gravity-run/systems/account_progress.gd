extends Node

signal progress_changed(wallet_coins: int, total_distance_m: int, best_distance_m: int)
signal run_saved(success: bool, message: String)
signal achievements_loaded(data: Dictionary)
signal achievements_unlocked(entries: Array)
signal total_distance_leaderboard_received(rows: Array, error_message: String)
signal monthly_distance_leaderboard_received(rows: Array, error_message: String)

const ProgressProvider = preload("res://systems/supabase_progress_provider.gd")
const CACHE_PATH := "user://gravity_run_account_progress.cfg"
const PENDING_PATH := "user://gravity_run_pending_runs.cfg"
const RETRY_DELAY_SECONDS := 30.0

var wallet_coins := 0
var total_distance_m := 0
var best_distance_m := 0
var _user_id := ""
var _provider: Node
var _progress_loaded := false
var _pending_runs: Array[Dictionary] = []
var _active_run_id := ""
var _active_run_user_id := ""
var _retry_timer: Timer

func _ready() -> void:
	_provider = ProgressProvider.new()
	_provider.name = "SupabaseAccountProgressProvider"
	_provider.request_finished.connect(_on_request_finished)
	add_child(_provider)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = RETRY_DELAY_SECONDS
	_retry_timer.timeout.connect(_flush_pending_runs)
	add_child(_retry_timer)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	if AuthService.is_authenticated:
		_activate_user(AuthService.user_id)

func record_completed_run(distance_m: int, coins: int, gravity_flips: int = 0, hazards_seen: Array = []) -> void:
	if not AuthService.is_authenticated or AuthService.user_id.is_empty():
		return
	if distance_m < 0 or coins < 0:
		return
	var run := {
		"run_id": _create_run_id(),
		"distance_m": distance_m,
		"coins_earned": coins,
		"gravity_flips": maxi(gravity_flips, 0),
		"hazards_encountered": hazards_seen.duplicate(),
	}
	_pending_runs.append(run)
	_save_pending_runs()
	_flush_pending_runs()

func fetch_total_distance_leaderboard() -> void:
	_provider.fetch_total_distance_leaderboard()

func fetch_monthly_distance_leaderboard() -> void:
	_provider.fetch_monthly_distance_leaderboard()

## Inventory purchases are authoritative on the server; update the shared wallet
## cache from that response so every screen shows the same confirmed balance.
func apply_authoritative_wallet_balance(balance: int) -> void:
	if not AuthService.is_authenticated or AuthService.user_id != _user_id:
		return
	wallet_coins = maxi(balance, 0)
	_save_cached_progress()
	progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)

func _on_auth_state_changed(authenticated: bool, _email: String) -> void:
	if not authenticated:
		_activate_user("")
	elif AuthService.user_id != _user_id:
		_activate_user(AuthService.user_id)
	else:
		_flush_pending_runs()

func _activate_user(user_id: String) -> void:
	_user_id = user_id
	_progress_loaded = false
	_retry_timer.stop()
	_pending_runs.clear()
	wallet_coins = 0
	total_distance_m = 0
	best_distance_m = 0
	if _user_id.is_empty():
		progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)
		return
	_load_cached_progress()
	_load_pending_runs()
	_provider.load_progress(AuthService.get_access_token(), _user_id)
	_provider.load_achievements(AuthService.get_access_token(), _user_id)

func _load_cached_progress() -> void:
	var config := ConfigFile.new()
	if config.load(CACHE_PATH) != OK:
		return
	wallet_coins = int(config.get_value(_user_id, "wallet_coins", 0))
	total_distance_m = int(config.get_value(_user_id, "total_distance_m", 0))
	best_distance_m = int(config.get_value(_user_id, "best_distance_m", 0))
	progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)

func _save_cached_progress() -> void:
	if _user_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(CACHE_PATH)
	config.set_value(_user_id, "wallet_coins", wallet_coins)
	config.set_value(_user_id, "total_distance_m", total_distance_m)
	config.set_value(_user_id, "best_distance_m", best_distance_m)
	config.save(CACHE_PATH)

func _save_cached_progress_data(data: Dictionary, user_id: String) -> void:
	if user_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(CACHE_PATH)
	config.set_value(user_id, "wallet_coins", int(data.get("wallet_coins", 0)))
	config.set_value(user_id, "total_distance_m", int(data.get("total_distance_m", 0)))
	config.set_value(user_id, "best_distance_m", int(data.get("best_distance_m", 0)))
	config.save(CACHE_PATH)

func _load_pending_runs() -> void:
	var config := ConfigFile.new()
	if config.load(PENDING_PATH) != OK:
		return
	var stored: Variant = config.get_value("pending", _user_id, [])
	if stored is Array:
		for value in stored:
			if value is Dictionary and value.has("run_id"):
				_pending_runs.append(value)

func _save_pending_runs() -> void:
	if _user_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(PENDING_PATH)
	config.set_value("pending", _user_id, _pending_runs)
	config.save(PENDING_PATH)

func _flush_pending_runs() -> void:
	if not AuthService.is_authenticated or AuthService.user_id != _user_id or not _progress_loaded or not _active_run_id.is_empty() or _pending_runs.is_empty():
		return
	var run: Dictionary = _pending_runs[0]
	_active_run_id = str(run["run_id"])
	_active_run_user_id = _user_id
	_provider.record_run(
		_active_run_id,
		int(run["distance_m"]),
		int(run["coins_earned"]),
		int(run.get("gravity_flips", 0)),
		run.get("hazards_encountered", []),
		AuthService.get_access_token(),
		_user_id
	)

func _on_request_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	if action == "total_distance_leaderboard":
		total_distance_leaderboard_received.emit(data if success and data is Array else [], "" if success else message)
		return
	if action == "monthly_distance_leaderboard":
		monthly_distance_leaderboard_received.emit(data if success and data is Array else [], "" if success else message)
		return
	if action == "load_achievements":
		if context != _user_id or not AuthService.is_authenticated:
			return
		if success and data is Dictionary:
			achievements_loaded.emit(data)
		return
	if action == "load_progress":
		if context != _user_id or not AuthService.is_authenticated:
			if AuthService.is_authenticated and not _user_id.is_empty():
				_provider.load_progress(AuthService.get_access_token(), _user_id)
			return
		if not success and message == tr("An account progress request is already in progress."):
			return
		_progress_loaded = true
		if success and data is Dictionary:
			_apply_progress(data, context)
		else:
			progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)
		_flush_pending_runs()
		return
	if action != "record_run":
		return
	var run_context := context.split("|", false)
	if run_context.size() != 2 or run_context[0] != _active_run_user_id or run_context[1] != _active_run_id:
		return
	var completed_user_id := _active_run_user_id
	var completed_run_id := _active_run_id
	if success and data is Dictionary:
		var achievement_state: Variant = data.get("achievement_state", {})
		if completed_user_id == _user_id and AuthService.is_authenticated and achievement_state is Dictionary:
			achievements_loaded.emit(achievement_state)
		var newly_unlocked: Variant = data.get("new_achievements", [])
		if completed_user_id == _user_id and AuthService.is_authenticated and newly_unlocked is Array and not newly_unlocked.is_empty():
			achievements_unlocked.emit(newly_unlocked)
		if completed_user_id == _user_id and AuthService.is_authenticated:
			_apply_progress(data, completed_user_id)
		else:
			_save_cached_progress_data(data, completed_user_id)
		_remove_pending_run(completed_user_id, completed_run_id)
		_active_run_id = ""
		_active_run_user_id = ""
		_retry_timer.stop()
		if completed_user_id == _user_id and AuthService.is_authenticated:
			run_saved.emit(true, tr("Account saved · %d coins · %d m total distance") % [wallet_coins, total_distance_m])
		_flush_pending_runs()
	else:
		_active_run_id = ""
		_active_run_user_id = ""
		if completed_user_id == _user_id and AuthService.is_authenticated:
			run_saved.emit(false, tr("Account save pending. It will retry when the connection is available. %s") % message)
			_retry_timer.start(RETRY_DELAY_SECONDS)
		_flush_pending_runs()


func _apply_progress(data: Dictionary, user_id: String) -> void:
	if user_id != _user_id:
		_save_cached_progress_data(data, user_id)
		return
	wallet_coins = int(data.get("wallet_coins", 0))
	total_distance_m = int(data.get("total_distance_m", 0))
	best_distance_m = int(data.get("best_distance_m", 0))
	_save_cached_progress()
	progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)

func _remove_pending_run(user_id: String, run_id: String) -> void:
	var config := ConfigFile.new()
	config.load(PENDING_PATH)
	var stored: Variant = config.get_value("pending", user_id, [])
	var remaining: Array = stored if stored is Array else []
	for index in range(remaining.size() - 1, -1, -1):
		if remaining[index] is Dictionary and str(remaining[index].get("run_id", "")) == run_id:
			remaining.remove_at(index)
			break
	config.set_value("pending", user_id, remaining)
	config.save(PENDING_PATH)
	if user_id == _user_id:
		_pending_runs.clear()
		for value in remaining:
			if value is Dictionary:
				_pending_runs.append(value)

func _create_run_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
