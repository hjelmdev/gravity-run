extends SceneTree

const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const Coordinator := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service: Node = Service.new()
	service.name = "TimeoutDiagnosticsService"
	root.add_child(service)
	await process_frame
	service.identity_user_id = "timeout-test-host"
	service.session = {"role": "host", "local_peer_id": 1, "build_id": ProjectSettings.get_setting("application/config/version", "unknown")}
	service.room_state = {"room_id": "test-room", "room_session_id": "test-session", "owner_user_id": "timeout-test-host", "phase": "PREPARING_COURSE", "lobby_generation": 4, "manifest_hash": "manifest-hash", "members": [{"player_slot": 1}, {"player_slot": 2}]}
	service._start_attempt_id = "bounded-timeout-test"
	service._start_attempt_started_usec = Time.get_ticks_usec() - 15_100_000
	service._start_attempt_peer_status = {"2": {"player_slot": 2, "scene": "ready", "account_binding": "bound", "clock": "synced", "prepared": "waiting", "registration": "waiting", "start_commit": "waiting"}}
	service.diagnostics.begin_session({"role": "host", "build_id": service.session.build_id})
	service._round_id = "opaque-runtime-round"
	service._round_coordinator.state = Coordinator.State.PREPARING
	service._round_coordinator.is_host = true
	service._round_coordinator.round_id = service._round_id
	service._round_coordinator.round_descriptor = {"attempt_id": service._start_attempt_id, "round_id": service._round_id}
	service._round_coordinator.prepare_started_usec = Time.get_ticks_usec() - Coordinator.PREPARE_TIMEOUT_USEC
	service._round_coordinator.process(Time.get_ticks_usec())
	_check(str(service.last_start_failure).contains("prepare_timeout"), "actual coordinator timeout reaches the service failure callback")
	service.room_state["phase"] = "OPEN"
	service._complete_lobby_return()
	var report: Dictionary = service.diagnostics.export_report()
	report["current_state"] = service.current_diagnostic_state()
	var filename := "start-timeout-diagnostics-test.json"
	var saved_message := DiagnosticsExport.save_report(report, filename)
	_check(saved_message.contains("Diagnostics saved locally"), "timeout report saves without blocking or requiring a completed round")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://%s" % filename))
	_check(parsed is Dictionary, "saved timeout diagnostics file can be read back")
	if parsed is Dictionary:
		var attempts: Array = parsed.get("start_attempts", [])
		_check(attempts.size() == 1 and str(attempts[0].get("stage", "")) == "timeout_or_abort", "the failed attempt and its final barrier survive lobby reset/export")
		_check(str(JSON.stringify(parsed)).find("token") < 0 and str(JSON.stringify(parsed)).find("nonce") < 0, "downloadable report contains no access token or nonce")
	_check(service.has_room() and str(service.room_state.get("phase", "")) == "OPEN", "saving diagnostics leaves the same lobby session usable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://%s" % filename))
	if failures == 0:
		print("Start-timeout diagnostics passed: real coordinator timeout, lobby-return snapshot and local JSON export verified.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
