extends Node2D

const ResultsView := preload("res://ui/race_results_view.gd")

const LocalRunnerScript := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const WorldSimulationScript := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const RemoteTrackScript := preload("res://systems/multiplayer_v2/v2_remote_track.gd")
const PlayerScene := preload("res://player/player.tscn")
const Motion := preload("res://systems/runner_motion.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const CoursePresentationScript := preload("res://systems/race_course_presentation.gd")
const RoundCoordinatorScript := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")

const FIXED_DELTA := 1.0 / 60.0
const CAMERA_PLAYER_X := 250.0
const MAX_CATCHUP_STEPS := 12

const CameraScript := preload("res://systems/runner_camera.gd")
var _render_camera: Camera2D
var _render_fraction := 0.0
var _previous_camera_left := 0.0
var _manifest: Resource
var _runner
var _world
var _round_id := ""
var _round_started := false
var _round_aborted := false
var _world_tick := 0
var _accumulator := 0.0
var _pending_flip_direction := 0
var _pending_interaction_id := ""
var _remote_tracks: Dictionary = {}
var _remote_terminal: Dictionary = {}
var _remote_terminal_poses: Dictionary = {}
var _remote_locomotion: Dictionary = {}
var _player_views: Dictionary = {}
var _course_root: Node2D
var _course_presentation: Node2D
var _camera_left := 0.0
var _spectator_peer_id := 0
var _last_spectator_event_peer_id := -1
var _result: Dictionary = {}
var _status_label: Label
var _result_panel: PanelContainer
var _result_text: RichTextLabel
var _results_view: ScrollContainer
var _return_lobby_button: Button
var _debug_panel: PanelContainer
var _debug_toggle: Button
var _export_confirmation: Label
var _frozen_roster: Array[Dictionary] = []
var _debug_open := false
var _lobby_navigation_pending := false
var _export_notice_generation := 0
var _touch_start := Vector2.ZERO
var _touch_index := -1

func _ready() -> void:
	set_process_unhandled_input(true)
	MultiplayerV2Service.room_changed.connect(_on_room_changed_for_abort)
	MultiplayerV2Service.lobby_returned.connect(_navigate_lobby)
	MultiplayerV2Service.lobby_request_finished.connect(_on_lobby_request_finished)
	_manifest = MultiplayerV2Service.current_manifest
	_round_id = str(MultiplayerV2Service.session.get("round_id", ""))
	if _manifest == null:
		_show_failure(tr("The V2 course manifest is missing."))
		return
	_runner = LocalRunnerScript.new()
	_world = WorldSimulationScript.new()
	var world_error := str(_world.configure(_manifest))
	if not world_error.is_empty():
		_show_failure(tr("The V2 course could not be initialized: %s") % world_error)
		return
	_render_camera = CameraScript.new()
	add_child(_render_camera)
	_course_root = Node2D.new()
	_course_root.name = "SharedCourseRoot"
	add_child(_course_root)
	_course_presentation = CoursePresentationScript.new()
	_course_presentation.name = "RaceCoursePresentation"
	_course_root.add_child(_course_presentation)
	var presentation_error := str(_course_presentation.call("load_manifest", _manifest))
	if not presentation_error.is_empty():
		_show_failure(tr("The shared race presentation failed: %s") % presentation_error)
		return
	var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
	var loadout_snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	var resolved_stats: Dictionary = loadout_snapshot.get_resolved_stats() if loadout_snapshot != null and loadout_snapshot.has_method("is_valid") and bool(loadout_snapshot.call("is_valid")) else {}
	_runner.configure(_round_id, local_peer, float(_manifest.start_x), float(_manifest.initial_floor_y), resolved_stats)
	MultiplayerV2Service.diagnostics.record_event("local_loadout_frozen", {"run_speed_percent": int(resolved_stats.get("run_speed_percent", 10000)), "flip_cooldown_percent": int(resolved_stats.get("flip_cooldown_percent", 10000))})
	MultiplayerV2Service.configure_world_simulation(_world)
	_build_overlay()
	_build_peer_slots()
	MultiplayerV2Service.player_sample_received.connect(_on_remote_sample)
	MultiplayerV2Service.terminal_report_received.connect(_on_terminal_report)
	MultiplayerV2Service.world_event_committed.connect(_on_world_commit)
	MultiplayerV2Service.world_interaction_resolved.connect(_on_interaction_resolved)
	MultiplayerV2Service.results_received.connect(_on_results_received)
	MultiplayerV2Service.round_failed.connect(_on_round_failed)
	MultiplayerV2Service.round_started.connect(_on_round_started)
	_round_id = str(MultiplayerV2Service.session.get("round_id", _round_id))
	_runner.round_id = _round_id
	MultiplayerV2Service.mark_local_prepared()
	_status_label.text = tr("Preparing all V2 players…")
	queue_redraw()

func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_status_label = Label.new()
	_status_label.position = Vector2(20.0, 18.0)
	_status_label.add_theme_font_size_override("font_size", 17)
	status_style(_status_label)
	overlay.add_child(_status_label)
	_debug_toggle = Button.new()
	_debug_toggle.text = tr("Menu")
	_debug_toggle.position = Vector2(20.0, 58.0)
	_debug_toggle.custom_minimum_size = Vector2(112.0, 42.0)
	_debug_toggle.pressed.connect(_toggle_debug_panel)
	overlay.add_child(_debug_toggle)
	_debug_panel = PanelContainer.new()
	_debug_panel.position = Vector2(20.0, 108.0)
	_debug_panel.custom_minimum_size = Vector2(300.0, 110.0)
	_debug_panel.visible = false
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color("18243a")
	debug_style.border_color = Color("42d6c5")
	debug_style.set_border_width_all(1)
	debug_style.set_corner_radius_all(8)
	debug_style.content_margin_left = 12
	debug_style.content_margin_right = 12
	debug_style.content_margin_top = 10
	debug_style.content_margin_bottom = 10
	_debug_panel.add_theme_stylebox_override("panel", debug_style)
	overlay.add_child(_debug_panel)
	var tools := VBoxContainer.new()
	_debug_panel.add_child(tools)
	var rate_row := HBoxContainer.new()
	tools.add_child(rate_row)
	var rate_label := Label.new()
	rate_label.text = tr("Position sample send rate")
	rate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_row.add_child(rate_label)
	var rate := OptionButton.new()
	rate.add_item("30 Hz", 30)
	rate.add_item("60 Hz", 60)
	rate.select(0 if MultiplayerV2Service.get_snapshot_rate() == 30 else 1)
	rate.item_selected.connect(func(index: int) -> void: MultiplayerV2Service.set_snapshot_rate(rate.get_item_id(index)))
	rate_row.add_child(rate)
	var export_button := Button.new()
	export_button.text = tr("Save V2 diagnostics")
	export_button.pressed.connect(_save_diagnostics)
	tools.add_child(export_button)
	_export_confirmation = Label.new()
	_export_confirmation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_confirmation.add_theme_font_size_override("font_size", 12)
	_export_confirmation.add_theme_color_override("font_color", Color("42d6c5"))
	_export_confirmation.visible = false
	tools.add_child(_export_confirmation)
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.anchor_left = 0.15
	_result_panel.anchor_right = 0.85
	_result_panel.anchor_top = 0.08
	_result_panel.anchor_bottom = 0.92
	_result_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_result_panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(_result_panel)
	var result_layout := VBoxContainer.new()
	_result_panel.add_child(result_layout)
	_result_text = RichTextLabel.new()
	_result_text.fit_content = true
	_result_text.scroll_active = false
	_result_text.custom_minimum_size.y = 30
	result_layout.add_child(_result_text)
	_results_view = ResultsView.new()
	result_layout.add_child(_results_view)
	_results_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := HBoxContainer.new()
	result_layout.add_child(actions)
	var rematch := Button.new()
	_return_lobby_button = rematch
	rematch.text = tr("Return to lobby")
	rematch.custom_minimum_size.y = 42
	rematch.pressed.connect(_return_to_lobby)
	actions.add_child(rematch)
	var back := Button.new()
	back.text = tr("Leave race")
	back.pressed.connect(_leave_v2)
	actions.add_child(back)
	# Keep diagnostic controls reachable when the result panel is open.
	overlay.move_child(_debug_panel, overlay.get_child_count() - 1)
	overlay.move_child(_debug_toggle, overlay.get_child_count() - 1)

func _build_peer_slots() -> void:
	for member in MultiplayerV2Service.get_active_round_roster():
		_frozen_roster.append(member.duplicate(true))
		var peer_id := int(member.get("player_slot", 1))
		var runner := PlayerScene.instantiate() as Node2D
		runner.name = "Runner_%d" % peer_id
		_course_root.add_child(runner)
		runner.call("set_input_enabled", false)
		runner.call("set_skin_id", int(member.get("skin_id", 0)))
		_player_views[peer_id] = runner
		if peer_id == int(MultiplayerV2Service.session.get("local_peer_id", 1)):
			continue
		var track = RemoteTrackScript.new()
		track.target_delay_ticks = 4.5
		_remote_tracks[peer_id] = track
		_remote_terminal[peer_id] = "running"
		_remote_locomotion[peer_id] = "running"

func _physics_process(delta: float) -> void:
	if _manifest == null or _runner == null:
		return
	if not _round_started:
		return
	_accumulator += minf(delta, FIXED_DELTA * float(MAX_CATCHUP_STEPS))
	var steps := 0
	while _accumulator >= FIXED_DELTA and steps < MAX_CATCHUP_STEPS:
		_accumulator -= FIXED_DELTA
		_step_local_round()
		steps += 1
	if _accumulator >= FIXED_DELTA:
		MultiplayerV2Service.diagnostics.record_event("local_physics_backlog", {"seconds": _accumulator})
		_accumulator = fmod(_accumulator, FIXED_DELTA)
	MultiplayerV2Service.diagnostics.observe_max("max_physics_delta_ms", delta * 1000.0)

func _process(delta: float) -> void:
	if _manifest == null or _runner == null or _course_presentation == null:
		return
	_render_fraction = Engine.get_physics_interpolation_fraction()
	for peer_id in _remote_tracks:
		if str(_remote_terminal.get(peer_id, "running")) == "running":
			_remote_tracks[peer_id].advance(delta)
	_previous_camera_left = _camera_left
	_update_spectator_camera()
	_render_camera.configure(get_viewport_rect().size, CAMERA_PLAYER_X)
	_render_camera.follow(Vector2(_camera_left + CAMERA_PLAYER_X, 0.0), true)
	_course_presentation.call("set_camera_left", _camera_left)
	_course_presentation.call("set_world_state", _world.render_state(_render_fraction))
	if _round_started:
		_update_hud()
	_sync_player_views()
	if _result.is_empty():
		MultiplayerV2Service.diagnostics.record_frame({"phase": "spectator" if _spectator_peer_id > 0 else "running", "tick": _runner.simulation_tick, "world_tick": _world.tick, "x": float(_runner.player_state.get("world_x", 0.0)), "y": float(_runner.player_state.get("y", 0.0)), "camera_left": _camera_left, "camera_delta_x": _camera_left - _previous_camera_left, "render_fraction": _render_fraction, "render_delta_ms": delta * 1000.0, "fps": Engine.get_frames_per_second(), "window_focused": DisplayServer.window_is_focused()})
	queue_redraw()

func _step_local_round() -> void:
	_world_tick += 1
	if not _world.step_to(_world_tick):
		return
	if _world_tick % 60 == 0:
		MultiplayerV2Service.report_world_hash(_world_tick, _world.entity_ledger.revision, _world.state_hash())
	if str(_runner.player_state.get("state", "")) == "pending_barrel":
		_runner.advance_pending_tick()
		return
	if str(_runner.player_state.get("state", "")) != "running":
		return
	var state: Dictionary = _runner.player_state
	var previous_state: Dictionary = state.duplicate(true)
	var candidate_x := minf(float(state.get("world_x", 0.0)) + Motion.distance_for_delta(FIXED_DELTA, _runner.run_speed_multiplier), float(_manifest.finish_x))
	var candidate := state.duplicate(true)
	candidate["world_x"] = candidate_x
	var contact: Dictionary = _world.player_contact(candidate)
	if str(contact.get("kind", "")) == "shared_interaction":
		_request_shared_barrel(contact)
		_runner.advance_pending_tick()
		return
	var blocked := str(contact.get("kind", "")) == "blocked"
	var target_x := float(state.get("world_x", 0.0)) if blocked else candidate_x
	var floor_info: Dictionary = _world.surface_at(target_x, false)
	var ceiling_info: Dictionary = _world.surface_at(target_x, true)
	var gravity_before := int(state.get("gravity_direction", 1))
	var sequence_before := int(_runner.input_sequence)
	var flip := _pending_flip_direction
	_pending_flip_direction = 0
	_runner.set_blocked(blocked)
	var sample: Dictionary = _runner.step(flip, float(floor_info.y), float(ceiling_info.y), bool(floor_info.supported), bool(ceiling_info.supported), false, target_x)
	if int(_runner.input_sequence) > sequence_before:
		var audit := {"round_id": _round_id, "owner_peer_id": int(MultiplayerV2Service.session.get("local_peer_id", 1)), "input_seq": _runner.input_sequence, "simulation_tick": _runner.simulation_tick, "kind": "gravity_flip", "requested_direction": flip, "accepted": int(_runner.player_state.get("gravity_direction", gravity_before)) != gravity_before, "gravity_direction": int(_runner.player_state.get("gravity_direction", gravity_before))}
		MultiplayerV2Service.report_input_audit(audit)
	var proposed_state: Dictionary = _runner.player_state.duplicate(true)
	var swept: Dictionary = _world.first_static_terminal_contact(previous_state, proposed_state)
	contact = _world.player_contact(_runner.player_state)
	if not swept.is_empty():
		contact = swept
		_runner.player_state.world_x = float(swept.world_x)
		_runner.player_state.y = float(swept.y)
	if str(contact.get("kind", "")) == "shared_interaction":
		_request_shared_barrel(contact)
		return
	if str(contact.get("kind", "")) == "terminal":
		MultiplayerV2Service.diagnostics.record_event("local_terminal_contact", {"tick": _runner.simulation_tick, "previous_pose": previous_state, "proposed_pose": proposed_state, "terminal_pose": _runner.player_state.duplicate(true), "contact": contact, "speed": Motion.speed_for_multiplier(_runner.run_speed_multiplier)})
		MultiplayerV2Service.diagnostics.preserve_terminal_frames()
		_runner.stop("dead")
		MultiplayerV2Service.submit_local_terminal("dead", str(contact.get("reason", "hazard")), _runner.simulation_tick, float(_runner.player_state.world_x), float(_runner.player_state.y), int(_runner.player_state.gravity_direction))
		return
	if float(_runner.player_state.get("y", 0.0)) < -64.0 or float(_runner.player_state.get("y", 0.0)) > float(_manifest.world_height) + 64.0:
		_runner.stop("dead")
		MultiplayerV2Service.submit_local_terminal("dead", "out_of_bounds", _runner.simulation_tick, float(_runner.player_state.world_x), float(_runner.player_state.y), int(_runner.player_state.gravity_direction))
		return
	if float(_runner.player_state.world_x) >= float(_manifest.finish_x):
		_runner.stop("finished")
		MultiplayerV2Service.submit_local_terminal("finished", "finish_line", _runner.simulation_tick, float(_runner.player_state.world_x), float(_runner.player_state.y), int(_runner.player_state.gravity_direction))
		return
	MultiplayerV2Service.send_sample(sample)

func _request_shared_barrel(contact: Dictionary) -> void:
	if not _pending_interaction_id.is_empty():
		return
	var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
	_pending_interaction_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_runner.set_pending_barrel(true)
	var request := {"round_id": _round_id, "owner_peer_id": local_peer, "request_id": _pending_interaction_id, "entity_id": str(contact.get("entity_id", "")), "incarnation": int(contact.get("incarnation", 1)), "action": "lethal_contact", "simulation_tick": _runner.simulation_tick, "input_seq": _runner.input_sequence, "known_world_revision": _world.entity_ledger.revision, "world_x": float(_runner.player_state.get("world_x", 0.0)), "y": float(_runner.player_state.get("y", 0.0)), "gravity_direction": int(_runner.player_state.get("gravity_direction", 1))}
	MultiplayerV2Service.submit_local_world_interaction(request)
	MultiplayerV2Service.diagnostics.record_event("barrel_contact_pending", request)

func _on_remote_sample(peer_id: int, sample: Dictionary) -> void:
	if peer_id == int(MultiplayerV2Service.session.get("local_peer_id", 1)) or not _remote_tracks.has(peer_id):
		return
	if str(sample.get("round_id", "")) != _round_id:
		return
	if bool(_remote_tracks[peer_id].add_sample(sample)):
		MultiplayerV2Service.diagnostics.increment_metric("track_insertions_owner_%d" % peer_id)
	else:
		MultiplayerV2Service.diagnostics.increment_metric("track_rejections_owner_%d" % peer_id)
	_remote_locomotion[peer_id] = str(sample.get("locomotion_state", "running"))

func _on_terminal_report(peer_id: int, report: Dictionary) -> void:
	var next_state := str(report.get("state", "dead"))
	if peer_id == int(MultiplayerV2Service.session.get("local_peer_id", 1)):
		_runner.stop(next_state)
	else:
		_remote_terminal[peer_id] = next_state
		_remote_locomotion[peer_id] = next_state
		_remote_terminal_poses[peer_id] = report.duplicate(true)
	MultiplayerV2Service.diagnostics.record_event("terminal_presented", {"peer_id": peer_id, "state": next_state, "tick": int(report.get("simulation_tick", -1))})
	_update_spectator_camera()

func _on_world_commit(commit: Dictionary) -> void:
	if str(commit.get("round_id", _round_id)) != _round_id and commit.has("round_id"):
		return
	var applied: bool = _world.apply_world_commit(commit)
	MultiplayerV2Service.diagnostics.record_event("world_commit_presented", {"commit_id": str(commit.get("commit_id", "")), "result": applied, "revision": int(commit.get("world_revision", 0))})
	var transition: Dictionary = commit.get("linked_player_transition", {})
	if not transition.is_empty() and int(transition.get("owner_peer_id", -1)) == int(MultiplayerV2Service.session.get("local_peer_id", 1)):
		_pending_interaction_id = ""
		_runner.stop("dead")
		if MultiplayerV2Service.is_room_owner():
			_runner.stop("dead")
	queue_redraw()

func _on_interaction_resolved(request_id: String, accepted: bool, reason: String, commit: Dictionary) -> void:
	if request_id != _pending_interaction_id:
		return
	_pending_interaction_id = ""
	if not accepted:
		if commit is Dictionary and not commit.is_empty():
			_world.apply_world_commit(commit)
		_runner.set_pending_barrel(false)
		_status_label.text = tr("The shared barrel was already consumed. Keep running.")
		MultiplayerV2Service.diagnostics.record_event("barrel_claim_lost", {"reason": reason, "revision": int(commit.get("world_revision", _world.entity_ledger.revision))})
	else:
		_status_label.text = tr("Barrel collision confirmed by host.")
	queue_redraw()

func _on_results_received(result: Dictionary) -> void:
	_result = result.duplicate(true)
	_result_panel.visible = true
	_status_label.visible = false
	_result_text.clear()
	_result_text.append_text("[center][b]%s[/b][/center]" % tr("Round complete"))
	_results_view.show_rows(result.get("placements", []))
	_status_label.text = tr("The host confirmed the result.")

func _frozen_member(peer_id: int) -> Dictionary:
	for member in _frozen_roster:
		if int(member.get("player_slot", -1)) == peer_id:
			return member
	return {}

func _on_round_failed(reason: String) -> void:
	_round_aborted = true
	_round_started = false
	_result_panel.visible = true
	_result_text.clear()
	_result_text.append_text("[center][b]V2 round aborted[/b][/center]\n\n%s" % reason)
	_on_room_changed_for_abort(MultiplayerV2Service.room_state)

func _on_room_changed_for_abort(room: Dictionary) -> void:
	if (not _round_aborted and _result.is_empty()) or str(room.get("phase", "")) != "OPEN":
		return
	_navigate_lobby()

func _on_round_started(round_id: String, _descriptor: Dictionary) -> void:
	if round_id != _round_id:
		return
	_round_started = true
	_world_tick = 0
	_status_label.text = tr("RUN")
	MultiplayerV2Service.diagnostics.record_event("first_local_simulation", {"round_id": round_id, "tick": _runner.simulation_tick})

func _update_spectator_camera() -> void:
	if str(_runner.player_state.get("state", "running")) == "running" or str(_runner.player_state.get("state", "")) == "pending_barrel":
		_spectator_peer_id = 0
		var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
		_camera_left = maxf(float(_runner.render_state(_render_fraction).get("world_x", 0.0)) - CAMERA_PLAYER_X, 0.0)
		return
	if _spectator_peer_id != 0 and str(_remote_terminal.get(_spectator_peer_id, "running")) == "running":
		var current := _remote_track_sample(_spectator_peer_id)
		if bool(current.get("valid", false)) and not bool(current.get("stale", true)):
			_camera_left = maxf(float(current.get("world_x", 0.0)) - CAMERA_PLAYER_X, 0.0)
			return
	var candidates: Array[Dictionary] = []
	for peer_id in _remote_tracks.keys():
		if str(_remote_terminal.get(peer_id, "running")) != "running":
			continue
		var render_state := _remote_track_sample(int(peer_id))
		if not bool(render_state.get("valid", false)):
			continue
		candidates.append({"peer_id": int(peer_id), "world_x": float(render_state.get("world_x", 0.0)), "stale": bool(render_state.get("stale", false))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.stale) != bool(b.stale): return not bool(a.stale)
		if float(a.world_x) != float(b.world_x): return float(a.world_x) > float(b.world_x)
		return int(a.peer_id) < int(b.peer_id)
	)
	_spectator_peer_id = int(candidates[0].peer_id) if not candidates.is_empty() else 0
	if _spectator_peer_id > 0:
		var selected := _remote_track_sample(_spectator_peer_id)
		_camera_left = maxf(float(selected.get("world_x", 0.0)) - CAMERA_PLAYER_X, 0.0)
	if _spectator_peer_id != _last_spectator_event_peer_id:
		MultiplayerV2Service.diagnostics.record_event("spectator_target", {"peer_id": _spectator_peer_id, "camera_left": _camera_left})
		_last_spectator_event_peer_id = _spectator_peer_id

func _remote_track_sample(peer_id: int) -> Dictionary:
	if not _remote_tracks.has(peer_id):
		return {}
	var result: Dictionary = _remote_tracks[peer_id].sample_at_render_time()
	var terminal := str(_remote_terminal.get(peer_id, "running")) != "running"
	MultiplayerV2Service.diagnostics.metrics["remote_track_%d" % peer_id] = {"valid": bool(result.get("valid", false)), "terminal": terminal, "stale": false if terminal else bool(result.get("stale", true)), "sequence": int(result.get("sample_seq", -1)), "render_tick": float(result.get("render_tick", -1.0)), "sample_age_ticks": 0.0 if terminal else float(result.get("render_tick", 0.0)) - float(result.get("simulation_tick", 0.0)), "world_x": float(result.get("world_x", 0.0))}
	return result

func _update_hud() -> void:
	if not _result.is_empty():
		_status_label.text = tr("The host confirmed the result.")
		return
	var state_name := str(_runner.player_state.get("state", "running"))
	if state_name == "pending_barrel":
		_status_label.text = tr("Waiting for shared barrel decision…")
	elif state_name in ["dead", "finished"]:
		_status_label.text = tr("Spectating peer %d") % _spectator_peer_id if _spectator_peer_id > 0 else tr("Waiting for host result…")
	else:
		_status_label.text = tr("V2 · tick %d · %s") % [_runner.simulation_tick, tr("Host") if MultiplayerV2Service.is_room_owner() else tr("Guest")]

func _draw() -> void:
	if _manifest == null:
		return
	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2(_camera_left, 0.0), view_size), Color("101827"))
	for index in range(18):
		var star_x := fposmod(float(index * 83) + _camera_left * 0.12, view_size.x)
		draw_circle(Vector2(_camera_left + star_x, 58.0 + float((index * 47) % 390)), 1.5, Color("26364b"))
	_draw_players()

func _draw_players() -> void:
	for member in _frozen_roster:
		var peer_id := int(member.get("player_slot", 1))
		var pose := _player_render_pose(member)
		var screen_position: Vector2 = pose.position
		var label_text := str(member.get("display_name", "Runner"))
		var font := ThemeDB.fallback_font
		var font_size := 10
		var text_width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var font_height := font.get_height(font_size)
		var baseline_y := screen_position.y - Motion.SIZE.y * 0.5 - 7.0 if int(pose.gravity) > 0 else screen_position.y + Motion.SIZE.y * 0.5 + font_height + 7.0
		draw_string(font, Vector2(screen_position.x - text_width * 0.5, baseline_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("edf3ff"))

func _player_render_pose(member: Dictionary) -> Dictionary:
	var peer_id := int(member.get("player_slot", 1))
	var world_x := float(_manifest.start_x)
	var y := float(_manifest.initial_floor_y) - Motion.SIZE.y * 0.5
	var gravity := 1
	var locomotion := "running"
	if peer_id == int(MultiplayerV2Service.session.get("local_peer_id", 1)):
		var local_render: Dictionary = _runner.render_state(_render_fraction)
		world_x = float(local_render.get("world_x", world_x))
		y = float(local_render.get("y", y))
		gravity = int(_runner.player_state.get("gravity_direction", 1))
		locomotion = str(_runner.player_state.get("state", "running"))
	else:
		var remote := _remote_track_sample(peer_id)
		if not remote.is_empty():
			world_x = float(remote.get("world_x", world_x))
			y = float(remote.get("y", y))
			gravity = int(remote.get("gravity_direction", gravity))
		locomotion = str(_remote_locomotion.get(peer_id, "running"))
		if str(_remote_terminal.get(peer_id, "running")) != "running":
			locomotion = str(_remote_terminal[peer_id])
			var terminal: Dictionary = _remote_terminal_poses.get(peer_id, {})
			world_x = float(terminal.get("world_x", world_x))
			y = float(terminal.get("y", y))
			gravity = int(terminal.get("gravity_direction", gravity))
	return {"position": Vector2(world_x, y), "gravity": gravity, "locomotion": locomotion}

func _sync_player_views() -> void:
	for member in _frozen_roster:
		var peer_id := int(member.get("player_slot", 1))
		var runner_value: Variant = _player_views.get(peer_id)
		if not is_instance_valid(runner_value) or not runner_value is Node2D:
			continue
		var pose := _player_render_pose(member)
		var runner: Node2D = runner_value
		var screen_position: Vector2 = pose.position
		runner.position = screen_position
		var screen_x := screen_position.x - _camera_left
		runner.visible = screen_x > -80.0 and screen_x < get_viewport_rect().size.x + 80.0
		var sprite := runner.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null:
			continue
		sprite.flip_v = int(pose.gravity) < 0
		if str(pose.locomotion) not in ["running", "pending_barrel"]:
			sprite.stop()
		elif not sprite.is_playing():
			sprite.play("run")

func _unhandled_input(event: InputEvent) -> void:
	if _debug_open:
		return
	if not _round_started or str(_runner.player_state.get("state", "")) not in ["running", "pending_barrel"]:
		return
	if event is InputEventScreenTouch:
		if PlayerProfile.flip_control not in ["swipe", "tap"]:
			return
		if event.pressed:
			if _touch_index == -1:
				if PlayerProfile.flip_control == "tap":
					_pending_flip_direction = -int(_runner.player_state.get("gravity_direction", 1))
				else:
					_touch_index = event.index
					_touch_start = event.position
		elif event.index == _touch_index:
			var swipe: Vector2 = event.position - _touch_start
			if absf(swipe.y) >= 48.0 and absf(swipe.y) > absf(swipe.x) * 1.2:
				_pending_flip_direction = -1 if swipe.y < 0.0 else 1
			_touch_index = -1
		return
	if event is InputEventKey and event.pressed and not event.echo and PlayerProfile.flip_control == "keyboard":
		if event.keycode in [KEY_UP, KEY_W]:
			_pending_flip_direction = -1
		elif event.keycode in [KEY_DOWN, KEY_S]:
			_pending_flip_direction = 1
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and PlayerProfile.flip_control == "mouse":
		_pending_flip_direction = -int(_runner.player_state.get("gravity_direction", 1))

func _return_to_lobby() -> void:
	if MultiplayerV2Service.is_room_owner():
		_return_lobby_button.disabled = true
		_return_lobby_button.text = tr("Opening lobby…")
		MultiplayerV2Service.return_to_lobby()
	else:
		_navigate_lobby()

func _navigate_lobby() -> void:
	if _lobby_navigation_pending:
		return
	_lobby_navigation_pending = true
	AppNavigation.request_multiplayer_v2_lobby()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _on_lobby_request_finished(action: String, success: bool, message: String) -> void:
	if action == "return_to_lobby" and not success:
		_return_lobby_button.disabled = false
		_return_lobby_button.text = tr("Return to lobby")
		_result_text.clear()
		_result_text.add_text(message)

func _save_diagnostics() -> void:
	var report := MultiplayerV2Service.diagnostics.export_report()
	report["current_state"] = MultiplayerV2Service.current_diagnostic_state()
	var saved_path := DiagnosticsExport.save_report(report, DiagnosticsExport.make_filename(report, "match"))
	_export_notice_generation += 1
	_export_confirmation.text = tr("Diagnostics saved: %s") % saved_path
	_export_confirmation.visible = true
	var generation := _export_notice_generation
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if generation == _export_notice_generation and is_instance_valid(_export_confirmation):
			_export_confirmation.visible = false
	)

func _toggle_debug_panel() -> void:
	_debug_open = not _debug_open
	_debug_panel.visible = _debug_open
	_debug_toggle.text = tr("Close menu") if _debug_open else tr("Menu")
	# A menu interaction cannot carry through as a gravity-flip input.
	_pending_flip_direction = 0

func _leave_v2() -> void:
	MultiplayerV2Service.leave_room()
	AppNavigation.request_game_hub()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _show_failure(message: String) -> void:
	if _round_started or MultiplayerV2Service._round_coordinator.state in [RoundCoordinatorScript.State.PREPARING, RoundCoordinatorScript.State.COMMITTING]:
		_round_aborted = true
		MultiplayerV2Service.report_local_prepare_failure(message, "match_scene_ready")
	var label := Label.new()
	label.text = message
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	_on_room_changed_for_abort(MultiplayerV2Service.room_state)

func status_style(label: Label) -> void:
	label.add_theme_color_override("font_color", Color("edf3ff"))
