extends SceneTree

const LobbyProviderScript := preload("res://systems/supabase_lobby_provider.gd")

var failures := 0

func _initialize() -> void:
	var payload_sql := FileAccess.get_file_as_string("res://supabase/migrations/202609270010_restore_skin_id_in_room_payload.sql")
	var phase_sql := FileAccess.get_file_as_string("res://supabase/migrations/202609270011_authoritative_match_phases.sql")
	var capacity_sql := FileAccess.get_file_as_string("res://supabase/migrations/202609280001_multiplayer_five_player_rooms.sql")
	var service_source := FileAccess.get_file_as_string("res://systems/multiplayer_service.gd")
	var provider_source := FileAccess.get_file_as_string("res://systems/supabase_lobby_provider.gd")
	var match_source := FileAccess.get_file_as_string("res://ui/multiplayer_match.gd")
	var transport_source := FileAccess.get_file_as_string("res://systems/webrtc_match_transport.gd")
	var lobby_ui_source := FileAccess.get_file_as_string("res://ui/multiplayer_lobby.gd")
	var lobby_provider_source := FileAccess.get_file_as_string("res://systems/supabase_lobby_provider.gd")
	var diagnostics_source := FileAccess.get_file_as_string("res://systems/multiplayer_diagnostics.gd")
	var lobby_provider := LobbyProviderScript.new()
	_check(lobby_provider._extract_error_code({"message": "ERROR: room_not_found"}, 400) == "room_not_found", "machine-readable room_not_found should be extracted from PostgREST error text")
	_check(lobby_provider._extract_error_code({"code": "not_room_member", "message": "membership required"}, 400) == "not_room_member", "structured SQL codes should be preserved independently of UI text")
	_check(lobby_provider._extract_error_code({"message": "unexpected failure"}, 400) == "http_400", "unknown HTTP errors should retain their status without being misclassified")
	lobby_provider.free()
	var navigation_source := FileAccess.get_file_as_string("res://systems/app_navigation.gd")
	_check(not payload_sql.is_empty(), "payload migration should be present")
	_check(payload_sql.contains("'skin_id', m.skin_id"), "lobby payload should preserve player skins")
	_check(payload_sql.contains("'countdown_start_at_unix'"), "lobby payload should expose the durable countdown")
	_check(phase_sql.contains("v_room.owner_user_id <> auth.uid()"), "only the room owner may advance the match phase")
	_check(phase_sql.contains("v_room.phase = 'COUNTDOWN' and p_next_phase = 'RUNNING'"), "countdown should advance into a running match")
	_check(phase_sql.contains("v_room.phase = 'RUNNING' and p_next_phase = 'FINISHED'"), "running should advance into a finished match")
	_check(phase_sql.contains("if v_phase = 'OPEN' then"), "return-to-lobby should safely allow idempotent retries")
	_check(phase_sql.contains("v_room.phase <> 'FINISHED'"), "only a finished match should return to the open lobby")
	_check(capacity_sql.contains("max_players between 2 and 5") and capacity_sql.contains("player_slot between 1 and 5") and capacity_sql.contains("set max_players = 5"), "the five-player migration should expand room and slot limits including existing open rooms")
	_check(service_source.contains("func _lobby_context()") and service_source.contains("_room_generation += 1"), "lobby request replies should be scoped to a room generation")
	_check(service_source.contains("room_state_changed") and service_source.contains("poll_interval := 1.0"), "room hints should supplement countdown recovery polling")
	_check(service_source.contains("phase == \"RUNNING\" else 2.0") and service_source.contains("else (15.0 if phase == \"RUNNING\" else 2.0)"), "OPEN/FINISHED lobbies should recover missed realtime hints without the old 15-second wait")
	_check(provider_source.contains("_pending_calls.insert") and provider_source.contains("first_background") and provider_source.contains("retry_count >= 2"), "lobby mutations should be prioritized, queued, and recoverable")
	_check(match_source.contains("queue_reliable_peer_message(_owner_user_id") and match_source.contains("match_setup_ack") and match_source.contains("match_setup_retry") and match_source.contains("advance_match_phase(\"FINISHED\")"), "match setup should use reliable delivery, acknowledgement/retries and publish the terminal phase")
	_check(match_source.contains("The host can confirm with the button below") and not match_source.contains("if str(payload.get(\"room_id\", \"\")) == MultiplayerService.get_room_id():\n\t\t\t\t\tMultiplayerService.return_to_lobby()"), "a guest return action must ask the host rather than changing the whole room directly")
	_check(transport_source.contains("if new_room_id != _room_id or local_user_id != _local_user_id:") and not transport_source.contains("returning_to_lobby"), "same-room rematches should reuse established WebRTC channels")
	_check(service_source.contains("PlayerAccountProfile.nickname") and lobby_ui_source.contains("_on_player_account_profile_changed"), "multiplayer should prefill a saved account nickname")
	_check(lobby_ui_source.contains("_adopt_cached_host_manifest(room, remote_hash)") and lobby_ui_source.contains("_send_manifest_to_connected_peers()"), "a rematch should reuse and resend the cached manifest over already-connected P2P channels")
	_check(lobby_ui_source.contains("_cached_manifest_rejection_reason") and lobby_ui_source.contains("manifest_cache_accepted"), "manifest cache reuse must validate hash and room metadata, and log why it was rejected")
	_check(lobby_ui_source.contains("manifest_request") and lobby_ui_source.contains("_request_host_manifest(\"retry\")") and lobby_ui_source.contains("manifest_application_ack_received"), "guests should retry an idempotent manifest request until application verification is acknowledged")
	_check(lobby_ui_source.contains("ready_blocked") and lobby_ui_source.contains("ready_available"), "the report trace should record why guest Ready is disabled and when it becomes usable")
	_check(match_source.contains("results_requested") and match_source.contains("results_visible_requested") and match_source.contains("results_frame_rendered"), "results timing must distinguish intent, visibility request, and a rendered engine frame")
	_check(match_source.contains("terminal_handler_timing") and match_source.contains("%s_trace_chunk") and match_source.contains("MultiplayerDiagnostics.record_post_match_event(\"%s_trace_chunk\""), "finish handling ACKs before trace serialization, and dumps raw trace in post-render batches")
	_check(diagnostics_source.contains("diagnostics_size_check_count") and diagnostics_source.contains("diagnostics_removed_%s") and diagnostics_source.contains("_is_protected_diagnostic_event"), "report reduction batches size checks, preserves core events and counts removed samples")
	_check(lobby_provider_source.contains("error_code: String, http_status: int, rpc_name: String") and lobby_provider_source.contains("func _extract_error_code") and lobby_provider_source.contains("_log_rpc_result(action, context, \"http_error\", response_code, error_code)"), "lobby provider exposes structured backend errors separately from display messages")
	_check(service_source.contains("error_code in [\"room_not_found\", \"room_expired\", \"not_room_member\"]") and service_source.contains("lobby_rpc_structured_error"), "service clears stale room state by machine-readable code and logs sanitized RPC context")
	_check(FileAccess.get_file_as_string("res://systems/multiplayer_diagnostics.gd").contains("diagnostics_size_reduction_iterations") and FileAccess.get_file_as_string("res://systems/multiplayer_diagnostics.gd").contains("record_post_match_event"), "post-match reports should expose bounded reduction progress and lobby handoff events")
	_check(lobby_ui_source.contains("_manifest_verified_peers[peer_user_id] = true") and lobby_ui_source.contains("_manifest_transfer_last_sent_msec"), "manifest retries should stop after guest verification and be rate-limited")
	_check(match_source.contains("if bool(_authoritative_snapshot.get(\"finished\", false)):\n\t\treturn") and match_source.contains("tied_for_lead"), "results should use terminal host state and avoid arbitrary winners on exact ties")
	_check(match_source.contains("interpolated_player_state(str(from.get(\"state\", \"running\")), str(to.get(\"state\", \"running\")), weight)"), "remote player death/finish state should not be delayed by position interpolation")
	_check(match_source.contains("host_simulation_finished") and match_source.contains("guest_received_finished_snapshot") and match_source.contains("match_peer_failed"), "terminal results should log the authoritative player states and any transport failure that preceded them")
	_check(navigation_source.contains("request_multiplayer_lobby") and match_source.contains("request_multiplayer_lobby()"), "rematches should return through the persistent menu navigation owner")
	if failures == 0:
		print("Multiplayer lobby contract tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
