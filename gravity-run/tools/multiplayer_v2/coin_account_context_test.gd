extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := MultiplayerV2Service
	var auth := AuthService
	var prior_authenticated := bool(auth.is_authenticated)
	var prior_user_id := str(auth.user_id)
	var prior_room := service.room_state.duplicate(true)
	var prior_round := str(service._round_id)
	var prior_session := service.session.duplicate(true)
	var prior_status := str(service._coin_wallet_status)
	var prior_status_user := str(service._coin_wallet_status_user)
	var prior_confirmed := service._coin_confirmed_awards_by_round.duplicate(true)
	var prior_coin_round_metadata := service._coin_room_generation_by_round.duplicate(true)
	var prior_identity := str(service.identity_user_id)
	var context_a := ""
	service.room_state = {"room_id": "00000000-0000-0000-0000-0000000000a1", "lobby_generation": 1}
	service._round_id = "review-round-a"
	service._coin_room_generation_by_round[service._round_id] = {"room_id": str(service.room_state.room_id), "generation": 1}
	context_a = service._coin_link_context()
	service._coin_link_account_contexts[context_a] = {"account_user_id": "review-account-a"}
	auth.is_authenticated = true
	auth.user_id = "review-account-a"
	_check(service._coin_link_account_matches_current(context_a), "challenge callback is accepted for its initiating account")
	auth.user_id = "review-account-b"
	_check(not service._coin_link_account_matches_current(context_a), "a delayed callback cannot prepare after the signed-in account changes")
	service._coin_bound_account_by_round[service._round_id] = "review-account-a"
	service.identity_user_id = "review-network-a"
	service.session = {"local_peer_id": 1}
	service._note_local_coin_award({"action": "collect", "winner_peer_id": 1})
	_check(service._coin_wallet_status_user != "review-account-b", "a coin award never marks a different current account pending")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared coins were not linked to this account", "result status identifies that the current account differs from the frozen recipient")
	auth.user_id = "review-account-a"
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins pending", "a successful no-op settlement before journal persistence cannot mark coins saved")
	var settle_prefix := {"account_user_id": "review-account-a", "network_user_id": "review-network-a", "room_id": "00000000-0000-0000-0000-0000000000a1", "lobby_generation": 1}
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "other-round", "coins_earned": 9}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins pending", "a settlement from another runtime round cannot mark this result saved")
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "review-round-a", "coins_earned": 0}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins pending", "a zero-credit settlement row remains pending before its first award")
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "review-round-a", "coins_earned": 1}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(2) == "Shared account coins pending", "partial cumulative settlement remains pending")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins saved", "the exact round and recipient becomes saved once its cumulative award count is confirmed")
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "review-round-a", "coins_earned": 1}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins saved", "duplicate or lost-reply retry is monotonic and idempotent")
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "review-round-a", "network_user_id": "other-network", "coins_earned": 4}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(2) == "Shared account coins pending", "another network identity cannot satisfy this round’s confirmation count")
	service.room_state = {"room_id": "00000000-0000-0000-0000-0000000000a1", "lobby_generation": 2}
	service._coin_confirmed_awards_by_round.erase(service._coin_settlement_key("review-round-a", "review-network-a", "review-account-a"))
	service._record_coin_settlements({"settlements": [settle_prefix.merged({"runtime_round_id": "review-round-a", "coins_earned": 1}, true)]}, "review-account-a")
	_check(service.coin_wallet_status_for_local_awards(1) == "Shared account coins saved", "a guest result remains confirmed when the host advances the room generation before a late settlement response")
	service.room_state = {"room_id": "00000000-0000-0000-0000-0000000000b2", "lobby_generation": 1}
	service._round_id = "review-round-b"
	_check(service._coin_link_context() != context_a, "same lobby generation in a different room cannot reuse a delayed callback context")
	service._coin_link_account_contexts.erase(context_a)
	service._coin_bound_account_by_round.erase("review-round-a")
	service._round_id = prior_round
	service.room_state = prior_room
	service.session = prior_session
	service._coin_wallet_status = prior_status
	service._coin_wallet_status_user = prior_status_user
	service._coin_confirmed_awards_by_round = prior_confirmed
	service._coin_room_generation_by_round = prior_coin_round_metadata
	service.identity_user_id = prior_identity
	auth.is_authenticated = prior_authenticated
	auth.user_id = prior_user_id
	_check(failures == 0, "account binding context regression suite")
	print("Coin account context tests passed.")
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
