extends SceneTree

var failures := 0

func _initialize() -> void:
	var payload_sql := FileAccess.get_file_as_string("res://supabase/migrations/202609270010_restore_skin_id_in_room_payload.sql")
	var phase_sql := FileAccess.get_file_as_string("res://supabase/migrations/202609270011_authoritative_match_phases.sql")
	var service_source := FileAccess.get_file_as_string("res://systems/multiplayer_service.gd")
	var provider_source := FileAccess.get_file_as_string("res://systems/supabase_lobby_provider.gd")
	var match_source := FileAccess.get_file_as_string("res://ui/multiplayer_match.gd")
	var transport_source := FileAccess.get_file_as_string("res://systems/webrtc_match_transport.gd")
	var lobby_ui_source := FileAccess.get_file_as_string("res://ui/multiplayer_lobby.gd")
	var navigation_source := FileAccess.get_file_as_string("res://systems/app_navigation.gd")
	_check(not payload_sql.is_empty(), "payload migration should be present")
	_check(payload_sql.contains("'skin_id', m.skin_id"), "lobby payload should preserve player skins")
	_check(payload_sql.contains("'countdown_start_at_unix'"), "lobby payload should expose the durable countdown")
	_check(phase_sql.contains("v_room.owner_user_id <> auth.uid()"), "only the room owner may advance the match phase")
	_check(phase_sql.contains("v_room.phase = 'COUNTDOWN' and p_next_phase = 'RUNNING'"), "countdown should advance into a running match")
	_check(phase_sql.contains("v_room.phase = 'RUNNING' and p_next_phase = 'FINISHED'"), "running should advance into a finished match")
	_check(phase_sql.contains("if v_phase = 'OPEN' then"), "return-to-lobby should safely allow idempotent retries")
	_check(phase_sql.contains("v_room.phase <> 'FINISHED'"), "only a finished match should return to the open lobby")
	_check(service_source.contains("func _lobby_context()") and service_source.contains("_room_generation += 1"), "lobby request replies should be scoped to a room generation")
	_check(service_source.contains("room_state_changed") and service_source.contains("poll_interval := 1.0"), "room hints should supplement countdown recovery polling")
	_check(provider_source.contains("_pending_calls.insert") and provider_source.contains("first_background") and provider_source.contains("retry_count >= 2"), "lobby mutations should be prioritized, queued, and recoverable")
	_check(match_source.contains("queue_reliable_peer_message(_owner_user_id") and match_source.contains("match_setup_ack") and match_source.contains("match_setup_retry") and match_source.contains("advance_match_phase(\"FINISHED\")"), "match setup should use reliable delivery, acknowledgement/retries and publish the terminal phase")
	_check(match_source.contains("The host can confirm with the button below") and not match_source.contains("if str(payload.get(\"room_id\", \"\")) == MultiplayerService.get_room_id():\n\t\t\t\t\tMultiplayerService.return_to_lobby()"), "a guest return action must ask the host rather than changing the whole room directly")
	_check(transport_source.contains("if new_room_id != _room_id or local_user_id != _local_user_id:") and not transport_source.contains("returning_to_lobby"), "same-room rematches should reuse established WebRTC channels")
	_check(service_source.contains("PlayerAccountProfile.nickname") and lobby_ui_source.contains("_on_player_account_profile_changed"), "multiplayer should prefill a saved account nickname")
	_check(match_source.contains("if bool(_authoritative_snapshot.get(\"finished\", false)):\n\t\treturn") and match_source.contains("tied_for_lead"), "results should use terminal host state and avoid arbitrary winners on exact ties")
	_check(navigation_source.contains("request_multiplayer_lobby") and match_source.contains("request_multiplayer_lobby()"), "rematches should return through the persistent menu navigation owner")
	if failures == 0:
		print("Multiplayer lobby contract tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
