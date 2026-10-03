extends Node

signal progress_changed(wallet_coins: int, total_distance_m: int, best_distance_m: int)
signal run_saved(success: bool, message: String)
signal run_loot_resolved(run_id: String, claims: Array)
signal achievements_loaded(data: Dictionary)
signal achievements_unlocked(entries: Array)
signal total_distance_leaderboard_received(rows: Array, error_message: String)
signal monthly_distance_leaderboard_received(rows: Array, error_message: String)
signal multiplayer_run_unlocks_received(runtime_round_id: String, player_slot: int, entries: Array)

const ProgressProvider = preload("res://systems/supabase_progress_provider.gd")
const CACHE_PATH := "user://gravity_run_account_progress.cfg"
const PENDING_PATH := "user://gravity_run_pending_runs.cfg"
const MP_PENDING_PATH := "user://gravity_run_pending_multiplayer_achievements.cfg"
const RETRY_DELAY_SECONDS := 30.0
const MP_PERMANENT_ERROR_MARKERS := [
	"invalid_multiplayer_run", "multiplayer_round_not_registered", "multiplayer_round_account_mismatch",
	"multiplayer_round_not_terminal", "multiplayer_receipt_conflict",
	"invalid_multiplayer_metrics", "invalid_hazard_catalog",
]

## Kept replaceable for isolated persistence tests; production uses the stable user:// path.
var _mp_pending_path := MP_PENDING_PATH

var wallet_coins := 0
var total_distance_m := 0
var best_distance_m := 0
var _user_id := ""
var _provider: Node
var _progress_loaded := false
var _pending_runs: Array[Dictionary] = []
var _pending_mp_runs: Array[Dictionary] = []
var _active_run_id := ""
var _active_run_user_id := ""
var _retry_timer: Timer
var _mp_inflight_context := ""
var _mp_inflight_action := ""

func _ready() -> void:
	_provider = ProgressProvider.new()
	_provider.name = "SupabaseAccountProgressProvider"
	_provider.request_finished.connect(_on_request_finished)
	add_child(_provider)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = RETRY_DELAY_SECONDS
	_retry_timer.timeout.connect(_on_retry_timeout)
	add_child(_retry_timer)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	if AuthService.is_authenticated:
		_activate_user(AuthService.user_id)

func _on_retry_timeout() -> void:
	_flush_pending_runs()
	_flush_pending_mp_runs()

func record_completed_run(distance_m: int, coins: int, gravity_flips: int = 0, hazards_seen: Array = [], loot_pickup_indexes: Array = []) -> String:
	if not AuthService.is_authenticated or AuthService.user_id.is_empty():
		return ""
	if distance_m < 0 or coins < 0:
		return ""
	var run_id := _create_run_id()
	var run := {
		"run_id": run_id,
		"distance_m": distance_m,
		"coins_earned": coins,
		"gravity_flips": maxi(gravity_flips, 0),
		"hazards_encountered": hazards_seen.duplicate(),
		"loot_pickup_indexes": loot_pickup_indexes.duplicate(),
	}
	_pending_runs.append(run)
	_save_pending_runs()
	_flush_pending_runs()
	return run_id

## Begins a durable receipt only after the coordinator reports an actual MP start.
## The server binds the slot and round to the signed account; the local user id is
## only a retry-queue partition and never an authorization input.
func begin_multiplayer_achievement_run(runtime_round_id: String, player_slot: int) -> Dictionary:
	if runtime_round_id.is_empty() or player_slot < 1 or player_slot > 5 or not AuthService.is_authenticated or AuthService.user_id.is_empty() or _jwt_is_anonymous(AuthService.get_access_token()):
		return {}
	var entry := {"runtime_round_id": runtime_round_id, "player_slot": player_slot, "account_user_id": AuthService.user_id, "started": false, "completed": false, "terminal_state": "", "distance_m": 0, "gravity_flips": 0, "hazards": []}
	for existing in _load_mp_queue_for_user(AuthService.user_id):
		if str(existing.get("runtime_round_id", "")) == runtime_round_id and int(existing.get("player_slot", -1)) == player_slot:
			return existing.duplicate(true)
	_pending_mp_runs.append(entry)
	_save_pending_mp_runs()
	_flush_pending_mp_runs()
	return entry.duplicate(true)

func complete_multiplayer_achievement_run(context: Dictionary, terminal_state: String, distance_m: int, gravity_flips: int, hazards: Array) -> void:
	var round_id := str(context.get("runtime_round_id", ""))
	var user_id := str(context.get("account_user_id", ""))
	var player_slot := int(context.get("player_slot", -1))
	if round_id.is_empty() or user_id.is_empty() or terminal_state not in ["dead", "finished"] or distance_m < 0 or gravity_flips < 0:
		return
	var queue := _load_mp_queue_for_user(user_id)
	for entry in queue:
		if str(entry.get("runtime_round_id", "")) == round_id and int(entry.get("player_slot", -1)) == player_slot:
			entry["completed"] = true
			entry["terminal_state"] = terminal_state
			entry["distance_m"] = mini(distance_m, 10000000)
			entry["gravity_flips"] = mini(gravity_flips, 100000)
			var clean_hazards: Array[String] = []
			for hazard in hazards:
				var hazard_id := str(hazard)
				if hazard_id.is_valid_identifier() and hazard_id not in clean_hazards:
					clean_hazards.append(hazard_id)
			entry["hazards"] = clean_hazards
			break
	_store_mp_queue_for_user(user_id, queue)
	_refresh_active_mp_queue()
	_flush_pending_mp_runs()

## Explicitly discards an unfinished receipt when its started round is aborted or
## membership ends without a terminal result. No server metrics are submitted.
func abandon_multiplayer_achievement_run(context: Dictionary) -> void:
	var round_id := str(context.get("runtime_round_id", ""))
	var user_id := str(context.get("account_user_id", ""))
	var player_slot := int(context.get("player_slot", -1))
	if round_id.is_empty() or user_id.is_empty():
		return
	var queue := _load_mp_queue_for_user(user_id)
	for index in range(queue.size() - 1, -1, -1):
		var entry: Dictionary = queue[index]
		if str(entry.get("runtime_round_id", "")) == round_id and int(entry.get("player_slot", -1)) == player_slot and not bool(entry.get("completed", false)):
			queue.remove_at(index)
	if _mp_inflight_context == "%s|%s|%d" % [user_id, round_id, player_slot]:
		_mp_inflight_context = ""
		_mp_inflight_action = ""
	_store_mp_queue_for_user(user_id, queue)
	_refresh_active_mp_queue()
	_flush_pending_mp_runs()

func _jwt_is_anonymous(token: String) -> bool:
	var parts := token.split(".", false)
	if parts.size() < 2:
		return true
	var encoded_payload := parts[1].replace("-", "+").replace("_", "/")
	while encoded_payload.length() % 4 != 0:
		encoded_payload += "="
	var payload := Marshalls.base64_to_utf8(encoded_payload)
	var parsed: Variant = JSON.parse_string(payload)
	return not parsed is Dictionary or bool(parsed.get("is_anonymous", false))

func _load_mp_queue_for_user(user_id: String) -> Array[Dictionary]:
	var config := ConfigFile.new()
	if config.load(_mp_pending_path) != OK:
		return []
	var raw: Variant = config.get_value("pending", user_id, [])
	var result: Array[Dictionary] = []
	if raw is Array:
		for row in raw:
			if row is Dictionary and str(row.get("account_user_id", "")) == user_id and not str(row.get("runtime_round_id", "")).is_empty():
				result.append(row.duplicate(true))
	return result

func _store_mp_queue_for_user(user_id: String, queue: Array[Dictionary]) -> void:
	if user_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_mp_pending_path)
	config.set_value("pending", user_id, queue)
	config.save(_mp_pending_path)
	if user_id == _user_id:
		_pending_mp_runs = queue.duplicate(true)

func _refresh_active_mp_queue() -> void:
	_pending_mp_runs = _load_mp_queue_for_user(_user_id) if not _user_id.is_empty() else []

func _save_pending_mp_runs() -> void:
	_store_mp_queue_for_user(_user_id, _pending_mp_runs)

func _flush_pending_mp_runs() -> void:
	if _mp_inflight_context != "" or not AuthService.is_authenticated or AuthService.user_id != _user_id or _pending_mp_runs.is_empty():
		return
	var entry: Dictionary = {}
	var now_unix := Time.get_unix_time_from_system()
	var earliest_retry_unix := 0
	for candidate in _pending_mp_runs:
		# A started round that never reached a terminal callback is not dispatchable.
		# Keep it for explicit abort cleanup but let later round receipts progress.
		if bool(candidate.get("started", false)) and not bool(candidate.get("completed", false)):
			continue
		var retry_after := int(candidate.get("retry_after_unix", 0))
		if retry_after > now_unix:
			if earliest_retry_unix == 0 or retry_after < earliest_retry_unix:
				earliest_retry_unix = retry_after
			continue
		entry = candidate
		break
	if entry.is_empty():
		if earliest_retry_unix > now_unix:
			_retry_timer.start(maxf(float(earliest_retry_unix - now_unix), 1.0))
		return
	var context := "%s|%s|%d" % [str(entry.get("account_user_id", "")), str(entry.get("runtime_round_id", "")), int(entry.get("player_slot", -1))]
	if not bool(entry.get("started", false)):
		_mp_inflight_context = context
		_mp_inflight_action = "mp_achievement_start"
		_provider.start_multiplayer_achievement_run(str(entry.runtime_round_id), int(entry.player_slot), AuthService.get_access_token(), context)
	elif bool(entry.get("completed", false)):
		_mp_inflight_context = context
		_mp_inflight_action = "mp_achievement_record"
		_provider.record_multiplayer_achievement_run(str(entry.runtime_round_id), int(entry.player_slot), str(entry.terminal_state), int(entry.distance_m), int(entry.gravity_flips), entry.get("hazards", []), AuthService.get_access_token(), context)

func apply_multiplayer_achievement_response(data: Dictionary, user_id: String) -> void:
	if user_id.is_empty() or user_id != _user_id or not AuthService.is_authenticated or AuthService.user_id != user_id:
		return
	var progress_data: Variant = data.get("progress", data)
	if progress_data is Dictionary and (progress_data.has("wallet_coins") or progress_data.has("total_distance_m") or progress_data.has("best_distance_m")):
		_apply_progress(progress_data, user_id)
	var newly_unlocked: Variant = data.get("new_achievements", [])
	if newly_unlocked is Array and not newly_unlocked.is_empty():
		achievements_unlocked.emit(newly_unlocked)
	var state: Variant = data.get("achievement_state", {})
	if state is Dictionary:
		achievements_loaded.emit(state)

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
		_flush_pending_mp_runs()

func _activate_user(user_id: String) -> void:
	# A pending HTTP completion remains scoped to its queue entry and may still
	# persist for the previous account. It must not hold the active account's
	# dispatcher hostage after an account switch.
	if not _mp_inflight_context.is_empty() and not _mp_inflight_context.begins_with(user_id + "|"):
		_mp_inflight_context = ""
		_mp_inflight_action = ""
	_user_id = user_id
	_progress_loaded = false
	_retry_timer.stop()
	_pending_runs.clear()
	wallet_coins = 0
	total_distance_m = 0
	best_distance_m = 0
	if _user_id.is_empty():
		_pending_mp_runs.clear()
		progress_changed.emit(wallet_coins, total_distance_m, best_distance_m)
		return
	_load_cached_progress()
	_load_pending_runs()
	_refresh_active_mp_queue()
	_provider.load_progress(AuthService.get_access_token(), _user_id)
	_provider.load_achievements(AuthService.get_access_token(), _user_id)
	_flush_pending_mp_runs()

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
	_flush_pending_mp_runs()
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
		run.get("loot_pickup_indexes", []),
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
	if action in ["mp_achievement_start", "mp_achievement_record"]:
		var split := context.split("|", false)
		if split.size() != 3:
			return
		var account_id := split[0]
		var round_id := split[1]
		var slot := int(split[2])
		var queue := _load_mp_queue_for_user(account_id)
		for index in range(queue.size()):
			var entry: Dictionary = queue[index]
			if str(entry.get("runtime_round_id", "")) != round_id or int(entry.get("player_slot", -1)) != slot:
				continue
			# The HTTP completion carries immutable account/round context. Accept a
			# late ACK even after switching accounts, but only while its own durable
			# row still expects this action. Duplicate/stale callbacks are harmless.
			if action == "mp_achievement_start" and bool(entry.get("started", false)):
				return
			if action == "mp_achievement_record" and not bool(entry.get("completed", false)):
				return
			if context == _mp_inflight_context:
				_mp_inflight_context = ""
				_mp_inflight_action = ""
			if success and data is Dictionary:
				if action == "mp_achievement_start":
					entry["started"] = true
					entry.erase("retry_after_unix")
					entry.erase("retry_attempts")
					queue[index] = entry
				else:
					if account_id == _user_id and AuthService.is_authenticated and AuthService.user_id == account_id:
						apply_multiplayer_achievement_response(data, account_id)
						var unlocks: Variant = data.get("new_achievements", [])
						if unlocks is Array and not unlocks.is_empty():
							multiplayer_run_unlocks_received.emit(round_id, slot, unlocks.duplicate(true))
					queue.remove_at(index)
					_store_mp_queue_for_user(account_id, queue)
					call_deferred("_flush_pending_mp_runs")
					return
			_store_mp_queue_for_user(account_id, queue)
			if success:
				call_deferred("_flush_pending_mp_runs")
			else:
				if _is_permanent_mp_error(message):
					queue.remove_at(index)
				else:
					# Persist per-row exponential backoff. Deferred rows are skipped by
					# the dispatcher so newer rounds can still get a turn.
					var attempts := int(entry.get("retry_attempts", 0)) + 1
					var delay_seconds := minf(30.0 * pow(2.0, float(attempts - 1)), 600.0)
					entry["retry_attempts"] = attempts
					entry["retry_after_unix"] = int(Time.get_unix_time_from_system() + int(ceili(delay_seconds)))
					queue[index] = entry
					if account_id == _user_id and AuthService.is_authenticated and AuthService.user_id == account_id and message.contains("(HTTP 401)"):
						AuthService.refresh_current_session()
					_retry_timer.start(delay_seconds)
				_store_mp_queue_for_user(account_id, queue)
			call_deferred("_flush_pending_mp_runs")
			return
	if action != "record_run":
		return
	var run_context := context.split("|", false)
	if run_context.size() != 2 or run_context[0] != _active_run_user_id or run_context[1] != _active_run_id:
		return
	var completed_user_id := _active_run_user_id
	var completed_run_id := _active_run_id
	if success and data is Dictionary:
		var newly_unlocked: Variant = data.get("new_achievements", [])
		if completed_user_id == _user_id and AuthService.is_authenticated and newly_unlocked is Array and not newly_unlocked.is_empty():
			achievements_unlocked.emit(newly_unlocked)
		var achievement_state: Variant = data.get("achievement_state", {})
		if completed_user_id == _user_id and AuthService.is_authenticated and achievement_state is Dictionary:
			achievements_loaded.emit(achievement_state)
		if completed_user_id == _user_id and AuthService.is_authenticated:
			_apply_progress(data, completed_user_id)
		else:
			_save_cached_progress_data(data, completed_user_id)
		_remove_pending_run(completed_user_id, completed_run_id)
		var loot_claims: Variant = data.get("loot_claims", [])
		if completed_user_id == _user_id and AuthService.is_authenticated and loot_claims is Array:
			run_loot_resolved.emit(completed_run_id, loot_claims)
			for claim in loot_claims:
				if claim is Dictionary and str(claim.get("claim_status", "")) == "awarded":
					InventoryService.refresh()
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

func _is_permanent_mp_error(message: String) -> bool:
	for marker in MP_PERMANENT_ERROR_MARKERS:
		if message.contains(marker):
			return true
	return false


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
