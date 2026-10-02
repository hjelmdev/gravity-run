extends Node2D

const ResultsView := preload("res://ui/race_results_view.gd")

const LocalRunnerScript := preload("res://systems/multiplayer_v2/v2_local_runner.gd")
const WorldSimulationScript := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const RemoteTrackScript := preload("res://systems/multiplayer_v2/v2_remote_track.gd")
const PlayerScene := preload("res://player/player.tscn")
const Motion := preload("res://systems/runner_motion.gd")
const FallingRockModel := preload("res://systems/falling_rock_model.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const CoursePresentationScript := preload("res://systems/race_course_presentation.gd")
const RoundCoordinatorScript := preload("res://systems/multiplayer_v2/v2_round_coordinator.gd")
const HudLayout := preload("res://ui/multiplayer_v2/v2_hud_layout.gd")
const SharedRunHudScene := preload("res://ui/shared_run_hud.tscn")
const ConfirmedCoinPresentationScript := preload("res://systems/confirmed_coin_presentation.gd")

const FIXED_DELTA := 1.0 / 60.0
const CAMERA_PLAYER_X := 250.0
const MAX_CATCHUP_STEPS := 12
const START_TRACE_SECONDS := 4.0
const PRESENTATION_DELAY_TICKS := 1.0
const LOCAL_POSE_HISTORY := 256
const COUNTDOWN_START_FLASH_USEC := 350_000
const FLOW_TRACE_MAX_FRAMES := 512
const FLOW_TRACE_MAX_WINDOWS := 64
const FLOW_TRACE_MAX_USEFUL_WINDOWS := 8
const FLOW_TRACE_MIN_USEFUL_FRAMES := 48
const FLOW_TRACE_MAX_TOTAL_FRAMES := 4096

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
var _pending_coin_claims: Dictionary = {}
var _remote_tracks: Dictionary = {}
var _remote_presentation_cache: Dictionary = {}
var _presentation_work_counts: Dictionary = {"track_sample_calls": 0, "projection_steps": 0, "surface_queries": 0, "contact_queries": 0, "track_pose_computations": 0}
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
var _coin_commit_presentation = ConfirmedCoinPresentationScript.new()
var _return_lobby_button: Button
var _debug_panel: PanelContainer
var _debug_toggle: Button
var _shared_run_hud: Control
var _export_confirmation: Label
var _frozen_roster: Array[Dictionary] = []
var _debug_open := false
var _lobby_navigation_pending := false
var _export_notice_generation := 0
var _touch_start := Vector2.ZERO
var _touch_index := -1
var _local_start_deadline_usec := -1
var _first_physics_step_usec := -1
var _local_pose_history: Array[Dictionary] = []
var _local_presentation_pose: Dictionary = {}
var _countdown_label: Label
var _countdown_flash_until_usec := -1
var _trace_frame_elapsed := 0.0
var _last_remote_watch_usec := -1
var _last_remote_watch_poses: Dictionary = {}
var _last_cadence_window_usec := -1
var _last_process_usec := -1
var _diagnostics_export_in_progress := false
var _godot_frame_intervals_ms: Array[float] = []
var _phase_profile: Dictionary = {}
var _last_barrel_probe: Dictionary = {}
var _barrel_trace_entity_id := ""
var _barrel_trace_started_usec := -1
var _barrel_trace_frames: Array[Dictionary] = []
var _last_render_world_state: Dictionary = {}
var _last_world_render_fraction := 0.0
var _last_presentation_tick := 0.0
var _profiling_enabled := false
var _render_anchor_experiment_enabled := false
var _hud_root: Control
var _viewport_size := Vector2.ZERO
var _flow_trace_windows := 0
var _flow_trace_useful_windows := 0
var _flow_trace_total_frames := 0
var _flow_trace_moving_target_sampled := false
var _flow_trace_frame_index := 0
var _render_callback_index := 0
var _render_callback_begin_usec := -1
var _presentation_anchor_usec := -1
var _presentation_ready_usec := -1
var _flow_trace_active := false
var _flow_trace_started_usec := -1
var _flow_trace_frames: Array[Dictionary] = []
var _flow_trace_static_target: Node2D
var _flow_trace_static_id := ""
var _flow_trace_moving_target: Node2D
var _flow_trace_moving_id := ""
var _flow_trace_view_metrics: Dictionary = {}
var _flow_trace_browser_start_index := 0
var _flow_trace_camera_instance_id := 0
var _flow_trace_viewport_size := Vector2.ZERO
var _start_profile_recorded: Dictionary = {}

func _ready() -> void:
	set_process_unhandled_input(true)
	_configure_profiling()
	_install_browser_frame_diagnostics()
	MultiplayerV2Service.room_changed.connect(_on_room_changed_for_abort)
	MultiplayerV2Service.lobby_returned.connect(_navigate_lobby)
	MultiplayerV2Service.membership_removed.connect(_on_membership_removed)
	MultiplayerV2Service.lobby_request_finished.connect(_on_lobby_request_finished)
	_manifest = MultiplayerV2Service.current_manifest
	_round_id = str(MultiplayerV2Service.session.get("round_id", ""))
	if _manifest == null:
		_show_failure(tr("The course manifest is missing."))
		return
	_runner = LocalRunnerScript.new()
	_world = WorldSimulationScript.new()
	var world_error := str(_world.configure(_manifest))
	if not world_error.is_empty():
		_show_failure(tr("The course could not be initialized: %s") % world_error)
		return
	_render_camera = CameraScript.new()
	add_child(_render_camera)
	_course_root = Node2D.new()
	_course_root.name = "SharedCourseRoot"
	add_child(_course_root)
	_course_presentation = CoursePresentationScript.new()
	_course_presentation.name = "RaceCoursePresentation"
	_course_root.add_child(_course_presentation)
	_course_presentation.call("set_render_profile_enabled", _profiling_enabled)
	var presentation_error := str(_course_presentation.call("load_manifest", _manifest))
	if not presentation_error.is_empty():
		_show_failure(tr("The shared race presentation failed: %s") % presentation_error)
		return
	var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
	var loadout_snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	var resolved_stats: Dictionary = loadout_snapshot.get_resolved_stats() if loadout_snapshot != null and loadout_snapshot.has_method("is_valid") and bool(loadout_snapshot.call("is_valid")) else {}
	_runner.configure(_round_id, local_peer, float(_manifest.start_x), float(_manifest.initial_floor_y), resolved_stats)
	_record_local_pose(0)
	MultiplayerV2Service.diagnostics.record_event("local_loadout_frozen", {"run_speed_percent": int(resolved_stats.get("run_speed_percent", 10000)), "flip_cooldown_percent": int(resolved_stats.get("flip_cooldown_percent", 10000))})
	MultiplayerV2Service.configure_world_simulation(_world)
	_build_overlay()
	_build_peer_slots()
	MultiplayerV2Service.player_sample_received.connect(_on_remote_sample)
	MultiplayerV2Service.terminal_report_received.connect(_on_terminal_report)
	MultiplayerV2Service.world_event_committed.connect(_on_world_commit)
	if not MultiplayerV2Service.coin_contact_presented.is_connected(_on_verified_coin_contact):
		MultiplayerV2Service.coin_contact_presented.connect(_on_verified_coin_contact)
	if not MultiplayerV2Service.coin_contact_presentation_cancelled.is_connected(_on_coin_contact_cancelled):
		MultiplayerV2Service.coin_contact_presentation_cancelled.connect(_on_coin_contact_cancelled)
	MultiplayerV2Service.world_interaction_resolved.connect(_on_interaction_resolved)
	MultiplayerV2Service.results_received.connect(_on_results_received)
	MultiplayerV2Service.round_failed.connect(_on_round_failed)
	MultiplayerV2Service.round_started.connect(_on_round_started)
	_round_id = str(MultiplayerV2Service.session.get("round_id", _round_id))
	_runner.round_id = _round_id
	MultiplayerV2Service.mark_local_prepared()
	_status_label.text = tr("Preparing all players…")
	queue_redraw()

func _configure_profiling() -> void:
	if OS.has_feature("web"):
		_profiling_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('v2_profile') === '1'"))
		_render_anchor_experiment_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('v2_render_anchor') === '1'"))
	else:
		_profiling_enabled = OS.get_cmdline_user_args().has("--v2-profile")
		_render_anchor_experiment_enabled = OS.get_cmdline_user_args().has("--v2-render-anchor")

func _exit_tree() -> void:
	_close_barrel_frame_trace("match_scene_exit")
	_close_flow_trace("match_scene_exit")
	if MultiplayerV2Service.coin_contact_presented.is_connected(_on_verified_coin_contact):
		MultiplayerV2Service.coin_contact_presented.disconnect(_on_verified_coin_contact)
	if MultiplayerV2Service.coin_contact_presentation_cancelled.is_connected(_on_coin_contact_cancelled):
		MultiplayerV2Service.coin_contact_presentation_cancelled.disconnect(_on_coin_contact_cancelled)

func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.resized.connect(_layout_hud)
	overlay.add_child(_hud_root)
	_shared_run_hud = SharedRunHudScene.instantiate() as Control
	_shared_run_hud.name = "SharedRunHud"
	_hud_root.add_child(_shared_run_hud)
	_shared_run_hud.call("set_show_distance", false)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 17)
	status_style(_status_label)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_status_label)
	_debug_toggle = Button.new()
	_debug_toggle.text = tr("Menu")
	_debug_toggle.custom_minimum_size = Vector2(104.0, 42.0)
	_debug_toggle.pressed.connect(_toggle_debug_panel)
	_hud_root.add_child(_debug_toggle)
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 64)
	_countdown_label.add_theme_color_override("font_color", Color("ffd166"))
	_countdown_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.07, 0.12, 0.9))
	_countdown_label.add_theme_constant_override("shadow_offset_x", 3)
	_countdown_label.add_theme_constant_override("shadow_offset_y", 4)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	_hud_root.add_child(_countdown_label)
	_debug_panel = PanelContainer.new()
	_debug_panel.custom_minimum_size = Vector2(280.0, 110.0)
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
	_hud_root.add_child(_debug_panel)
	var tools := VBoxContainer.new()
	_debug_panel.add_child(tools)
	var export_button := Button.new()
	export_button.text = tr("Save diagnostics")
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
	# The small menu control remains reachable above a result panel.
	_hud_root.z_index = 1
	_layout_hud()
	get_viewport().size_changed.connect(_layout_hud)
	call_deferred("_layout_hud")

func _layout_hud() -> void:
	if not is_instance_valid(_hud_root) or not is_instance_valid(_debug_toggle) or not is_instance_valid(_status_label) or not is_instance_valid(_debug_panel) or not is_instance_valid(_countdown_label) or not is_instance_valid(_shared_run_hud):
		return
	var size := _hud_root.size
	if size.x <= 0.0 or size.y <= 0.0:
		size = get_viewport_rect().size
	if size == _viewport_size and _viewport_size != Vector2.ZERO:
		return
	_viewport_size = size
	var layout := HudLayout.for_viewport(size)
	var button_rect: Rect2 = layout.get("button", Rect2())
	var music_rect: Rect2 = layout.get("music_button", Rect2())
	var status_rect: Rect2 = layout.get("status", Rect2())
	var panel_rect: Rect2 = layout.get("panel", Rect2())
	_debug_toggle.position = button_rect.position
	_debug_toggle.size = button_rect.size
	_shared_run_hud.call("set_music_right_offset", music_rect.position.x - size.x)
	_shared_run_hud.call("set_music_toolbar_top", music_rect.position.y, music_rect.size.y)
	_status_label.position = status_rect.position
	_status_label.size = status_rect.size
	_debug_panel.position = panel_rect.position
	_debug_panel.size = panel_rect.size
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -minf(size.x * 0.4, 240.0)
	_countdown_label.offset_right = minf(size.x * 0.4, 240.0)
	_countdown_label.offset_top = -56.0
	_countdown_label.offset_bottom = 56.0

func _update_start_countdown() -> void:
	if not is_instance_valid(_countdown_label):
		return
	var now_usec := Time.get_ticks_usec()
	if _round_started:
		if _countdown_flash_until_usec >= now_usec:
			_countdown_label.text = tr("START!")
			_countdown_label.visible = true
		else:
			_countdown_label.visible = false
		return
	var coordinator = MultiplayerV2Service._round_coordinator
	if coordinator.state != RoundCoordinatorScript.State.COMMITTING:
		_countdown_label.visible = false
		return
	var local_deadline: int = coordinator.clock.host_time_to_local_usec(coordinator.host_start_usec)
	var phase := RoundCoordinatorScript.countdown_label(local_deadline, now_usec)
	_countdown_label.text = tr(phase)
	_countdown_label.visible = not phase.is_empty()

func _record_local_pose(tick: int) -> void:
	if _runner == null:
		return
	var state: Dictionary = _runner.player_state
	var entry := {"tick": tick, "world_x": float(state.get("world_x", 0.0)), "y": float(state.get("y", 0.0)), "vertical_speed": float(state.get("vertical_speed", 0.0)), "velocity_x": Motion.speed_for_multiplier(_runner.run_speed_multiplier) if str(state.get("state", "running")) == "running" and not bool(state.get("blocked", false)) else 0.0, "gravity_direction": int(state.get("gravity_direction", 1)), "grounded": bool(state.get("grounded", false)), "blocked": bool(state.get("blocked", false)), "locomotion_state": str(state.get("state", "running"))}
	if not _local_pose_history.is_empty() and int(_local_pose_history.back().get("tick", -1)) == tick:
		_local_pose_history[_local_pose_history.size() - 1] = entry
	else:
		_local_pose_history.append(entry)
	while _local_pose_history.size() > LOCAL_POSE_HISTORY:
		_local_pose_history.pop_front()
	if _profiling_enabled and _local_start_deadline_usec >= 0 and Time.get_ticks_usec() - _local_start_deadline_usec <= int(START_TRACE_SECONDS * 1_000_000.0):
		_append_timeline_metric("local_poses", entry.duplicate(true))

func _sample_local_pose(target_tick: float) -> Dictionary:
	if _local_pose_history.is_empty():
		return _runner.render_state(_render_fraction)
	var before: Dictionary = _local_pose_history.front()
	var after: Dictionary = {}
	for pose in _local_pose_history:
		if float(pose.get("tick", 0.0)) <= target_tick:
			before = pose
		elif after.is_empty():
			after = pose
			break
	if not after.is_empty():
		var span := maxf(float(after.tick) - float(before.tick), 0.001)
		var weight := clampf((target_tick - float(before.tick)) / span, 0.0, 1.0)
		var result := before.duplicate(true)
		for key in ["world_x", "y", "vertical_speed", "velocity_x"]:
			result[key] = lerpf(float(before.get(key, 0.0)), float(after.get(key, 0.0)), weight)
		result["presentation_tick"] = target_tick
		return result
	var result := before.duplicate(true)
	var ahead_ticks := maxf(target_tick - float(before.get("tick", 0.0)), 0.0)
	if ahead_ticks > 0.0 and str(before.get("locomotion_state", "running")) == "running":
		var ahead_seconds := ahead_ticks / 60.0
		result["world_x"] = float(before.world_x) + float(before.velocity_x) * ahead_seconds
		var vertical_sample := before.duplicate(true)
		vertical_sample["velocity_y"] = float(before.get("vertical_speed", 0.0))
		var projected := _project_remote_vertical(vertical_sample, float(before.tick) + ahead_ticks)
		result["y"] = float(projected.get("y", before.y))
		result["vertical_speed"] = float(projected.get("velocity_y", before.vertical_speed))
		result["grounded"] = bool(projected.get("grounded", before.get("grounded", false)))
	result["presentation_tick"] = target_tick
	return result

func _build_peer_slots() -> void:
	var local_runner_view: Node2D
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
			local_runner_view = runner
			continue
		var track = RemoteTrackScript.new()
		track.target_delay_ticks = 0.0
		track.vertical_projector = Callable(self, "_project_remote_vertical")
		track.seed({"round_id": _round_id, "owner_peer_id": peer_id, "world_x": float(_manifest.start_x), "y": float(_manifest.initial_floor_y) - Motion.SIZE.y * 0.5, "velocity_x": Motion.BASE_RUN_SPEED, "velocity_y": 0.0, "gravity_direction": 1, "locomotion_state": "running"})
		_remote_tracks[peer_id] = track
		_remote_terminal[peer_id] = "running"
		_remote_locomotion[peer_id] = "running"
	if is_instance_valid(local_runner_view):
		_course_root.move_child(local_runner_view, _course_root.get_child_count() - 1)

func _physics_process(delta: float) -> void:
	if _manifest == null or _runner == null:
		return
	if not _round_started:
		return
	_advance_local_to_shared_clock(delta)

func _advance_local_to_shared_clock(delta: float, target_usec: int = -1) -> void:
	if not _round_started or _manifest == null or _runner == null:
		return
	if str(MultiplayerV2Service.session.get("role", "")) == "guest" and bool(MultiplayerV2Service._reconnect_sync_pending.get(1, false)):
		return
	if str(MultiplayerV2Service.session.get("role", "")) == "guest" and MultiplayerV2Service.consume_rock_warning_missed_recovery():
		var missed_pose: Dictionary = _runner.player_state
		MultiplayerV2Service.submit_local_terminal("dead", "falling_rock_warning_missed_delivery", _world_tick, float(missed_pose.get("world_x", 0.0)), float(missed_pose.get("y", 0.0)), int(missed_pose.get("gravity_direction", 1)), 0.0)
		_runner.stop("dead")
		MultiplayerV2Service.diagnostics.record_event("falling_rock_warning_recovery_terminal", {"round_id": _round_id, "tick": _world_tick, "policy": "connection_fairness_elimination_after_resync"})
		return
	var clock = MultiplayerV2Service._round_coordinator.clock
	var sample_usec := Time.get_ticks_usec() if target_usec < 0 else target_usec
	var target_tick := int(floor(clock.tick_at_monotonic_usec(sample_usec)))
	var owed_steps := maxi(target_tick - _world_tick, 0)
	var steps := 0
	while steps < mini(owed_steps, MAX_CATCHUP_STEPS):
		if _first_physics_step_usec < 0:
			_first_physics_step_usec = Time.get_ticks_usec()
			var late_usec := maxi(_first_physics_step_usec - _local_start_deadline_usec, 0) if _local_start_deadline_usec >= 0 else 0
			MultiplayerV2Service.diagnostics.record_event("first_local_physics_step", {"deadline_lateness_ms": float(late_usec) / 1000.0, "tick": _world_tick + 1, "round_elapsed_tick": target_tick})
		_step_local_round()
		_record_local_pose(_world_tick)
		if _profiling_enabled and _local_start_deadline_usec >= 0 and Time.get_ticks_usec() - _local_start_deadline_usec <= int(START_TRACE_SECONDS * 1_000_000.0):
			_append_timeline_metric("local_steps", {"tick": _world_tick, "world_x": float(_runner.player_state.get("world_x", 0.0)), "local_usec": Time.get_ticks_usec()})
		steps += 1
	if owed_steps > MAX_CATCHUP_STEPS:
		MultiplayerV2Service.diagnostics.record_event("local_physics_backlog", {"owed_steps": owed_steps, "executed_steps": steps})
	MultiplayerV2Service.diagnostics.observe_max("max_physics_delta_ms", delta * 1000.0)

func _process(delta: float) -> void:
	if _manifest == null or _runner == null or _course_presentation == null:
		return
	var callback_begin_usec := Time.get_ticks_usec()
	_render_callback_index += 1
	_render_callback_begin_usec = callback_begin_usec
	_remote_presentation_cache.clear()
	# Godot's render callback can run between 60 Hz physics callbacks. Advance
	# fixed-tick simulation to the shared clock before sampling any player pose,
	# so the local runner and camera do not hit a short projection ceiling.
	if _round_started:
		var catchup_started_usec := Time.get_ticks_usec() if _profiling_enabled else 0
		_advance_local_to_shared_clock(0.0, callback_begin_usec if _render_anchor_experiment_enabled else -1)
		if _profiling_enabled:
			_profile_phase("fixed_step_catchup", catchup_started_usec)
	_presentation_anchor_usec = callback_begin_usec if _round_started and _render_anchor_experiment_enabled else Time.get_ticks_usec()
	_render_fraction = Engine.get_physics_interpolation_fraction()
	var shared_tick := 0.0
	var presentation_tick := 0.0
	var player_presentation_started_usec := Time.get_ticks_usec() if _profiling_enabled else 0
	if _round_started:
		shared_tick = MultiplayerV2Service._round_coordinator.clock.tick_at_monotonic_usec(_presentation_anchor_usec)
		# One fixed simulation tick of shared history gives 30/60 Hz remote
		# samples time to bracket the display tick. Local pose and camera use the
		# same delayed tick, while simulation and terminal decisions stay current.
		presentation_tick = maxf(shared_tick - PRESENTATION_DELAY_TICKS, 0.0)
		_local_presentation_pose = _sample_local_pose(presentation_tick)
		for peer_id in _remote_tracks:
			if str(_remote_terminal.get(peer_id, "running")) == "running":
				_remote_tracks[peer_id].set_shared_presentation_tick(presentation_tick)
			var sampled: Dictionary = _remote_tracks[peer_id].advance_presentation(delta)
			var transition := str(_remote_tracks[peer_id].consume_transition())
			if not transition.is_empty():
				MultiplayerV2Service.diagnostics.record_event("remote_track_transition", {"peer_id": int(peer_id), "round_id": _round_id, "transition": transition, "presentation_tick": presentation_tick, "shared_clock_tick": shared_tick, "sample_tick": float(sampled.get("simulation_tick", -1.0)), "world_x": float(sampled.get("world_x", 0.0)), "correction_magnitude": float(sampled.get("correction_magnitude", 0.0)), "correction_elapsed_seconds": float(sampled.get("correction_elapsed_seconds", 0.0))})
	else:
		_local_presentation_pose = _runner.render_state(_render_fraction)
	if _profiling_enabled:
		_profile_phase("player_remote_presentation", player_presentation_started_usec)
	_last_presentation_tick = presentation_tick
	_update_start_countdown()
	_previous_camera_left = _camera_left
	_update_spectator_camera()
	_render_camera.configure(get_viewport_rect().size, CAMERA_PLAYER_X)
	_render_camera.follow(Vector2(_camera_left + CAMERA_PLAYER_X, 0.0), true)
	_course_presentation.call("set_camera_left", _camera_left)
	var world_render_fraction := _render_fraction
	if _round_started:
		world_render_fraction = WorldSimulationScript.presentation_fraction(presentation_tick, _world.tick)
	_last_world_render_fraction = world_render_fraction
	var dynamic_nodes_started_usec := Time.get_ticks_usec() if _profiling_enabled else 0
	_last_render_world_state = _world.render_state(world_render_fraction)
	_course_presentation.call("set_world_state", _last_render_world_state)
	if _profiling_enabled:
		_profile_phase("dynamic_entity_presentation", dynamic_nodes_started_usec)
	if _profiling_enabled:
		var barrel_trace_started_usec := Time.get_ticks_usec()
		_capture_barrel_frame_trace()
		_profile_phase("barrel_trace_sampling", barrel_trace_started_usec)
	if _local_start_deadline_usec >= 0 and Time.get_ticks_usec() - _local_start_deadline_usec <= int(START_TRACE_SECONDS * 1_000_000.0):
		var remote_presented := {}
		for peer_id in _remote_tracks:
			var remote_pose := _remote_track_sample(int(peer_id))
			remote_presented[str(peer_id)] = {"requested_presentation_tick": presentation_tick, "actual_sample_tick": float(remote_pose.get("simulation_tick", -1.0)), "sample_age_ticks": float(remote_pose.get("sample_age_ticks", -1.0)), "world_x": float(remote_pose.get("world_x", 0.0)), "screen_x": float(remote_pose.get("world_x", 0.0)) - _camera_left, "y": float(remote_pose.get("y", 0.0)), "stale": bool(remote_pose.get("stale", true)), "render_mode": str(remote_pose.get("render_mode", "unknown")), "correction_magnitude": float(remote_pose.get("correction_magnitude", 0.0)), "correction_elapsed_seconds": float(remote_pose.get("correction_elapsed_seconds", 0.0))}
		var local_pose: Dictionary = _local_presentation_pose if not _local_presentation_pose.is_empty() else _runner.render_state(_render_fraction)
		_append_timeline_metric("presented_frames", {"presentation_tick": presentation_tick, "shared_clock_tick": shared_tick, "presentation_delay_ticks": PRESENTATION_DELAY_TICKS, "local_simulation_tick": _runner.simulation_tick, "local_actual_sample_tick": float(_local_presentation_pose.get("tick", _runner.simulation_tick)), "local_previous_pose": _runner.previous_render_state.duplicate(true), "local_current_pose": _runner.current_render_state.duplicate(true), "local_render_x": float(local_pose.get("world_x", 0.0)), "local_render_y": float(local_pose.get("y", 0.0)), "local_screen_x": float(local_pose.get("world_x", 0.0)) - _camera_left, "remote": remote_presented, "camera_left": _camera_left, "camera_delta_x": _camera_left - _previous_camera_left, "frame_delta_seconds": delta, "local_usec": _presentation_anchor_usec, "render_callback_index": _render_callback_index, "render_callback_begin_usec": _render_callback_begin_usec, "presentation_anchor_usec": _presentation_anchor_usec, "presentation_ready_usec": _presentation_ready_usec})
	if _round_started:
		_update_hud()
	_sync_player_views()
	_presentation_ready_usec = Time.get_ticks_usec()
	if _profiling_enabled and _round_started:
		var flow_trace_started_usec := Time.get_ticks_usec()
		_capture_common_course_flow_frame(delta)
		_profile_phase("common_course_flow_trace", flow_trace_started_usec)
	if _result.is_empty():
		_record_presentation_diagnostic(delta)
	if _local_start_deadline_usec >= 0 and Time.get_ticks_usec() - _local_start_deadline_usec > int(START_TRACE_SECONDS * 1_000_000.0):
		MultiplayerV2Service.diagnostics.freeze_round_trace("start_window_complete")
	queue_redraw()
	if _profiling_enabled:
		_capture_first_course_draw_profile()

func _step_local_round() -> void:
	if _profiling_enabled:
		var tick_started_usec := Time.get_ticks_usec()
		_step_local_round_impl()
		_profile_phase("world_tick_and_collision", tick_started_usec)
	else:
		_step_local_round_impl()

func _step_local_round_impl() -> void:
	_world_tick += 1
	var start_step_profile := _profiling_enabled and not _start_profile_recorded.has("first_world_step")
	var world_step_started_usec := Time.get_ticks_usec() if start_step_profile else 0
	var world_step_advanced := bool(_world.step_to(_world_tick))
	if start_step_profile:
		_record_start_stage("first_world_step", Time.get_ticks_usec(), {"duration_usec": Time.get_ticks_usec() - world_step_started_usec, "simulation_tick": _world_tick, "advanced": world_step_advanced})
	if not world_step_advanced:
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
		MultiplayerV2Service.send_sample(sample)
		_submit_coin_claims(previous_state, proposed_state, float(swept.get("fraction", 2.0)))
		_request_shared_barrel(contact)
		return
	if str(contact.get("kind", "")) == "terminal":
		# Only the accepted contact pose may enter host history. The proposal can
		# continue past the lethal collision and must never validate later pickups.
		sample["world_x"] = float(swept.get("world_x", _runner.player_state.world_x))
		sample["y"] = float(swept.get("y", _runner.player_state.y))
		MultiplayerV2Service.send_sample(sample)
		_submit_coin_claims(previous_state, proposed_state, float(swept.get("fraction", 2.0)))
		MultiplayerV2Service.diagnostics.record_event("local_terminal_contact", {"tick": _runner.simulation_tick, "previous_pose": previous_state, "proposed_pose": proposed_state, "terminal_pose": _runner.player_state.duplicate(true), "contact": contact, "speed": Motion.speed_for_multiplier(_runner.run_speed_multiplier)})
		MultiplayerV2Service.diagnostics.preserve_terminal_frames()
		_runner.stop("dead")
		MultiplayerV2Service.submit_local_terminal("dead", str(contact.get("reason", "hazard")), _runner.simulation_tick, float(_runner.player_state.world_x), float(_runner.player_state.y), int(_runner.player_state.gravity_direction), float(swept.get("fraction", 1.0)))
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
	_submit_coin_claims(previous_state, proposed_state, 2.0)
	MultiplayerV2Service.observe_local_world_progress(previous_state, proposed_state)

func _submit_coin_claims(previous_state: Dictionary, proposed_state: Dictionary, terminal_fraction: float) -> void:
	for contact in _world.coin_contacts_swept(previous_state, proposed_state):
		if float(contact.get("fraction", 2.0)) >= terminal_fraction:
			continue
		var entity_id := str(contact.get("entity_id", ""))
		if entity_id.is_empty() or _pending_coin_claims.has(entity_id):
			continue
		var request_id := Crypto.new().generate_random_bytes(16).hex_encode()
		var incarnation := int(contact.get("incarnation", 1))
		var contact_usec := Time.get_ticks_usec()
		var predicted: bool = bool(_course_presentation.predict_coin_collection(entity_id, incarnation, _round_id, request_id))
		var contact_tick := float(_runner.simulation_tick - 1) + float(contact.get("fraction", 0.0))
		_pending_coin_claims[entity_id] = {"request_id": request_id, "incarnation": incarnation, "round_id": _round_id, "contact_usec": contact_usec, "contact_tick": contact_tick, "predicted": predicted}
		if predicted:
			MultiplayerV2Service.diagnostics.record_event("coin_visual_prediction", {"round_id": _round_id, "entity_id": entity_id, "incarnation": incarnation, "contact_to_visual_usec": maxi(Time.get_ticks_usec() - contact_usec, 0), "contact_tick": contact_tick})
		MultiplayerV2Service.submit_local_world_interaction({"round_id": _round_id, "owner_peer_id": int(MultiplayerV2Service.session.get("local_peer_id", 1)), "request_id": request_id, "entity_id": entity_id, "incarnation": int(contact.get("incarnation", 1)), "action": "collect", "simulation_tick": _runner.simulation_tick, "input_seq": _runner.input_sequence, "known_world_revision": _world.entity_ledger.revision})

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
	var sample_started_usec := Time.get_ticks_usec() if _profiling_enabled else 0
	if peer_id == int(MultiplayerV2Service.session.get("local_peer_id", 1)) or not _remote_tracks.has(peer_id):
		if _profiling_enabled: _profile_phase("remote_sample_ingest", sample_started_usec)
		return
	if str(sample.get("round_id", "")) != _round_id:
		if _profiling_enabled: _profile_phase("remote_sample_ingest", sample_started_usec)
		return
	if bool(_remote_tracks[peer_id].add_sample(sample)):
		MultiplayerV2Service.diagnostics.increment_metric("track_insertions_owner_%d" % peer_id)
	else:
		MultiplayerV2Service.diagnostics.increment_metric("track_rejections_owner_%d" % peer_id)
	_remote_locomotion[peer_id] = str(sample.get("locomotion_state", "running"))
	if _profiling_enabled and _local_start_deadline_usec >= 0 and Time.get_ticks_usec() - _local_start_deadline_usec <= int(START_TRACE_SECONDS * 1_000_000.0):
		var local_peer_id := int(MultiplayerV2Service.session.get("local_peer_id", -1))
		var role := str(MultiplayerV2Service.session.get("role", ""))
		_append_timeline_metric("remote_samples", {"owner_peer_id": peer_id, "transport_sender_peer_id": 1 if role == "guest" else peer_id, "delivery_path": "host_relay" if role == "guest" and peer_id != 1 else "direct", "local_peer_id": local_peer_id, "sample_tick": int(sample.get("simulation_tick", -1)), "local_simulation_tick": _world_tick, "world_x": float(sample.get("world_x", 0.0)), "received_usec": Time.get_ticks_usec()})
	if _profiling_enabled:
		_profile_phase("remote_sample_ingest", sample_started_usec)

func _append_timeline_metric(key: String, value: Dictionary) -> void:
	var sample := value.duplicate(true)
	sample["round_id"] = _round_id
	sample["local_peer_id"] = int(MultiplayerV2Service.session.get("local_peer_id", -1))
	sample["start_deadline_usec"] = _local_start_deadline_usec
	sample["trace_schema_version"] = 1
	MultiplayerV2Service.diagnostics.record_round_trace(key, sample)

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
	if str(commit.get("action", "")) == "activate_rock":
		var activation_tick := int(commit.get("rock_activation_tick", commit.get("effective_tick", -1)))
		if activation_tick >= 0 and _world != null and _world.tick > activation_tick:
			var rock_event := _rock_event_for_entity(str(commit.get("entity_id", "")))
			var route_safe := not rock_event.is_empty() and _late_rock_route_remains_safe(rock_event, activation_tick)
			MultiplayerV2Service.diagnostics.record_event("falling_rock_warning_delivery_late", {"round_id": _round_id, "event_id": str(commit.get("entity_id", "")), "activation_tick": activation_tick, "local_world_tick": _world.tick, "phase": FallingRockModel.phase_at(rock_event, activation_tick, _world.tick) if not rock_event.is_empty() else "unknown", "reaction_margin_ms": 200, "route_remains_safe": route_safe})
			if not route_safe:
				MultiplayerV2Service.request_rock_warning_recovery(str(commit.get("entity_id", "")), activation_tick)
				return
	var commit_result := str(_world.apply_world_commit(commit))
	var applied := commit_result == "applied"
	if str(commit.get("action", "")) == "collect":
		var entity_id := str(commit.get("entity_id", ""))
		var pending_claim: Dictionary = _pending_coin_claims.get(entity_id, {})
		_pending_coin_claims.erase(entity_id)
		_coin_commit_presentation.present(commit, commit_result, _course_presentation)
		if not pending_claim.is_empty():
			var confirmation_usec := maxi(Time.get_ticks_usec() - int(pending_claim.get("contact_usec", Time.get_ticks_usec())), 0)
			MultiplayerV2Service.diagnostics.record_event("coin_visual_confirmation", {"round_id": _round_id, "entity_id": entity_id, "incarnation": int(pending_claim.get("incarnation", -1)), "contact_to_confirm_usec": confirmation_usec, "commit_result": commit_result})
	MultiplayerV2Service.diagnostics.record_event("world_commit_presented", {"commit_id": str(commit.get("commit_id", "")), "result": applied, "revision": int(commit.get("world_revision", 0))})
	var transition: Dictionary = commit.get("linked_player_transition", {})
	if not transition.is_empty() and int(transition.get("owner_peer_id", -1)) == int(MultiplayerV2Service.session.get("local_peer_id", 1)):
		_pending_interaction_id = ""
		_runner.stop("dead")
		if MultiplayerV2Service.is_room_owner():
			_runner.stop("dead")
	queue_redraw()

func _on_verified_coin_contact(presentation: Dictionary) -> void:
	if _world == null or _course_presentation == null or str(presentation.get("round_id", "")) != _round_id:
		return
	var entity_id := str(presentation.get("entity_id", ""))
	var incarnation := int(presentation.get("incarnation", -1))
	if entity_id.is_empty() or incarnation < 1 or not _world.entity_ledger.is_active(entity_id, incarnation):
		return
	var entity_state: Dictionary = _world.entity_ledger.entities.get(entity_id, {})
	if str(entity_state.get("kind", "")) != "coin":
		return
	var started_usec := Time.get_ticks_usec()
	var presented: bool = bool(_coin_commit_presentation.present_contact(presentation, _course_presentation))
	if presented:
		var pending: Dictionary = _pending_coin_claims.get(entity_id, {})
		var contact_to_effect_usec := maxi(started_usec - int(pending.get("contact_usec", started_usec)), 0) if str(pending.get("round_id", "")) == _round_id else -1
		MultiplayerV2Service.diagnostics.record_event("coin_contact_effect_presented", {"round_id": _round_id, "entity_id": entity_id, "incarnation": incarnation, "peer_id": int(presentation.get("peer_id", -1)), "contact_tick": float(presentation.get("contact_tick", -1.0)), "local_contact_to_effect_usec": contact_to_effect_usec})
	queue_redraw()

func _on_coin_contact_cancelled(presentation: Dictionary) -> void:
	if _world == null or _course_presentation == null or str(presentation.get("round_id", "")) != _round_id:
		return
	var entity_id := str(presentation.get("entity_id", ""))
	var incarnation := int(presentation.get("incarnation", -1))
	if entity_id.is_empty() or incarnation < 1 or not _world.entity_ledger.is_active(entity_id, incarnation):
		return
	var restored: bool = bool(_coin_commit_presentation.cancel_contact(presentation, _course_presentation))
	if restored:
		MultiplayerV2Service.diagnostics.record_event("coin_contact_effect_restored", {"round_id": _round_id, "entity_id": entity_id, "incarnation": incarnation, "reason": str(presentation.get("reason", ""))})
		queue_redraw()

func _rock_event_for_entity(entity_id: String) -> Dictionary:
	if _manifest == null:
		return {}
	for event in _manifest.events:
		if str(event.get("event_id", "")) == entity_id and str(event.get("kind", "")) == "rock":
			return event
	return {}

func _late_rock_route_remains_safe(event: Dictionary, activation_tick: int) -> bool:
	if _runner == null or _world == null:
		return false
	var state: Dictionary = _runner.player_state.duplicate(true)
	var previous := Vector2(float(state.get("world_x", 0.0)), float(state.get("y", 0.0)))
	var tick := int(_world.tick)
	var reaction_ready_tick := tick + ceili(0.20 / FIXED_DELTA)
	for _step in range(240):
		var next_x := float(state.get("world_x", previous.x)) + 750.0 * FIXED_DELTA
		var floor_surface: Dictionary = _world.surface_at(next_x, false)
		var ceiling_surface: Dictionary = _world.surface_at(next_x, true)
		if tick >= reaction_ready_tick and int(state.get("gravity_direction", 1)) > 0 and bool(state.get("grounded", false)) and float(state.get("cooldown", 0.0)) <= 0.0:
			Motion.try_flip(state, -1, 2.0)
		Motion.advance_vertical(state, FIXED_DELTA, float(floor_surface.get("y", _manifest.initial_floor_y)), float(ceiling_surface.get("y", _manifest.initial_ceiling_y)), bool(floor_surface.get("supported", false)), bool(ceiling_surface.get("supported", false)))
		state["world_x"] = next_x
		var current := Vector2(next_x, float(state.get("y", previous.y)))
		if FallingRockModel.swept_contact_fraction(event, activation_tick, tick, tick + 1, previous, current, Motion.SIZE) >= 0.0:
			return false
		previous = current
		tick += 1
		if next_x > float(event.get("x", 0.0)) + float(event.get("width", FallingRockModel.WIDTH)) * 0.5 + Motion.SIZE.x:
			return true
	return false

func _on_interaction_resolved(request_id: String, accepted: bool, reason: String, commit: Dictionary) -> void:
	for entity_id in _pending_coin_claims:
		var pending_claim: Dictionary = _pending_coin_claims[entity_id]
		if str(pending_claim.get("request_id", "")) == request_id:
			_pending_coin_claims.erase(entity_id)
			if not commit.is_empty():
				var commit_result := str(_world.apply_world_commit(commit))
				_coin_commit_presentation.present(commit, commit_result, _course_presentation)
			elif not accepted and bool(pending_claim.get("predicted", false)):
				var incarnation := int(pending_claim.get("incarnation", -1))
				var still_active: bool = bool(_world.entity_ledger.is_active(str(entity_id), incarnation))
				var should_restore := still_active and reason not in ["coin_claim_lost", "already_collected"]
				_course_presentation.resolve_coin_visual_prediction(str(entity_id), incarnation, str(pending_claim.get("round_id", "")), request_id, should_restore)
				MultiplayerV2Service.diagnostics.record_event("coin_visual_prediction_resolved", {"round_id": str(pending_claim.get("round_id", "")), "entity_id": str(entity_id), "reason": reason, "ledger_still_active": still_active, "restored_active_coin": should_restore, "contact_to_resolution_usec": maxi(Time.get_ticks_usec() - int(pending_claim.get("contact_usec", Time.get_ticks_usec())), 0)})
			if not accepted and reason not in ["coin_claim_lost", "already_collected"]:
				MultiplayerV2Service.diagnostics.record_event("coin_claim_retryable", {"entity_id": str(entity_id), "reason": reason})
			return
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
	MusicController.enter_menu()
	_result = result.duplicate(true)
	_close_flow_trace("results_received")
	MultiplayerV2Service.diagnostics.freeze_round_trace("results_received")
	_result_panel.visible = true
	_status_label.visible = false
	_result_text.clear()
	_result_text.append_text("[center][b]%s[/b][/center]" % tr("Round complete"))
	_results_view.show_rows(result.get("placements", []))
	_update_coin_count_indicator()

func _frozen_member(peer_id: int) -> Dictionary:
	for member in _frozen_roster:
		if int(member.get("player_slot", -1)) == peer_id:
			return member
	return {}

static func spectator_display_name(peer_id: int, roster: Array, fallback: String = "Player") -> String:
	for member in roster:
		if not member is Dictionary or int(member.get("player_slot", -1)) != peer_id:
			continue
		var display_name := str(member.get("display_name", "")).strip_edges()
		return display_name if not display_name.is_empty() else fallback
	return fallback

func _on_round_failed(reason: String) -> void:
	MusicController.enter_menu()
	_round_aborted = true
	_round_started = false
	_close_flow_trace("round_aborted")
	_countdown_label.visible = false
	MultiplayerV2Service.diagnostics.freeze_round_trace("round_aborted")
	_result_panel.visible = true
	_result_text.clear()
	_result_text.append_text("[center][b]%s[/b][/center]\n\n%s" % [tr("Round aborted"), reason])
	_on_room_changed_for_abort(MultiplayerV2Service.room_state)

func _on_room_changed_for_abort(room: Dictionary) -> void:
	# Room phase changes are global state. Each local results page stays open
	# until this client explicitly records its own return.
	if _round_aborted and _result.is_empty():
		_status_label.text = tr("The round was aborted. Return to the lobby when you are ready.")

func _on_membership_removed(reason: String) -> void:
	MusicController.enter_menu()
	_round_started = false
	_result_panel.visible = true
	_result_text.clear()
	_result_text.append_text(reason)
	_return_lobby_button.text = tr("Back to menu")
	_status_label.visible = true
	_status_label.text = reason
	queue_redraw()

func _on_round_started(round_id: String, _descriptor: Dictionary) -> void:
	if round_id != _round_id:
		return
	var callback_started_usec := Time.get_ticks_usec()
	_round_started = true
	_pending_coin_claims.clear()
	MusicController.start_round(round_id)
	_world_tick = 0
	_local_start_deadline_usec = int(MultiplayerV2Service._round_coordinator.clock.started_at_usec)
	_first_physics_step_usec = -1
	_last_cadence_window_usec = Time.get_ticks_usec()
	_last_process_usec = -1
	_godot_frame_intervals_ms.clear()
	_phase_profile.clear()
	for key in _presentation_work_counts:
		_presentation_work_counts[key] = 0
	_last_barrel_probe.clear()
	_close_barrel_frame_trace("round_restarted")
	_close_flow_trace("round_restarted")
	_flow_trace_windows = 0
	_flow_trace_useful_windows = 0
	_flow_trace_total_frames = 0
	_flow_trace_moving_target_sampled = false
	_flow_trace_frame_index = 0
	_flow_trace_active = false
	_start_profile_recorded.clear()
	if _profiling_enabled and _course_presentation.has_method("begin_start_profile"):
		_course_presentation.call("begin_start_profile", _local_start_deadline_usec)
	_countdown_flash_until_usec = _local_start_deadline_usec + COUNTDOWN_START_FLASH_USEC
	_status_label.text = tr("RUN")
	MultiplayerV2Service.diagnostics.record_event("round_timeline_started", {"round_id": round_id, "deadline_local_usec": _local_start_deadline_usec, "clock_uncertainty_usec": float(MultiplayerV2Service._round_coordinator.clock.offset_uncertainty_usec), "initial_tick": _world_tick})
	MultiplayerV2Service.diagnostics.begin_round_trace(round_id, int(MultiplayerV2Service.session.get("local_peer_id", -1)), str(MultiplayerV2Service.session.get("role", "")), _local_start_deadline_usec, float(MultiplayerV2Service._round_coordinator.clock.offset_uncertainty_usec))
	MultiplayerV2Service.diagnostics.record_event("presentation_timing_config", {"shared_presentation_delay_ticks": PRESENTATION_DELAY_TICKS, "moving_barrels_use_shared_presentation_time": true, "browser_raf_available": OS.has_feature("web"), "profiling_enabled": _profiling_enabled, "render_anchor_experiment_enabled": _render_anchor_experiment_enabled})
	_update_start_countdown()
	if _profiling_enabled:
		_record_start_stage("round_started_callback", callback_started_usec, {"callback_duration_usec": Time.get_ticks_usec() - callback_started_usec, "callback_lateness_usec": maxi(callback_started_usec - _local_start_deadline_usec, 0)})

func _update_spectator_camera() -> void:
	if str(_runner.player_state.get("state", "running")) == "running" or str(_runner.player_state.get("state", "")) == "pending_barrel":
		_spectator_peer_id = 0
		var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
		var local_pose: Dictionary = _local_presentation_pose if not _local_presentation_pose.is_empty() else _runner.render_state(_render_fraction)
		_camera_left = maxf(float(local_pose.get("world_x", 0.0)) - CAMERA_PLAYER_X, 0.0)
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
	if _profiling_enabled:
		_presentation_work_counts["track_sample_calls"] = int(_presentation_work_counts.track_sample_calls) + 1
	if _remote_presentation_cache.has(peer_id):
		return _remote_presentation_cache[peer_id]
	if _profiling_enabled:
		_presentation_work_counts["track_pose_computations"] = int(_presentation_work_counts.track_pose_computations) + 1
	var result: Dictionary = _remote_tracks[peer_id].sample_at_render_time()
	var terminal := str(_remote_terminal.get(peer_id, "running")) != "running"
	var gravity := int(result.get("gravity_direction", 1))
	if bool(result.get("grounded", false)) and not terminal and _world != null:
		if _profiling_enabled:
			_presentation_work_counts["surface_queries"] = int(_presentation_work_counts.surface_queries) + 1
		var support: Dictionary = _world.surface_at(float(result.get("world_x", 0.0)), gravity < 0)
		if bool(support.get("supported", false)):
			result["y"] = float(support.get("y", result.get("y", 0.0))) - float(gravity) * Motion.SIZE.y * 0.5
	result["sample_age_ticks"] = 0.0 if terminal else maxf(float(result.get("render_tick", 0.0)) - float(result.get("simulation_tick", 0.0)), 0.0)
	MultiplayerV2Service.diagnostics.metrics["remote_track_%d" % peer_id] = {"valid": bool(result.get("valid", false)), "terminal": terminal, "stale": false if terminal else bool(result.get("stale", true)), "sequence": int(result.get("sample_seq", -1)), "render_tick": float(result.get("render_tick", -1.0)), "sample_age_ticks": float(result.get("sample_age_ticks", -1.0)), "world_x": float(result.get("world_x", 0.0)), "render_mode": str(result.get("render_mode", "unknown")), "correction_magnitude": float(result.get("correction_magnitude", 0.0)), "correction_elapsed_seconds": float(result.get("correction_elapsed_seconds", 0.0))}
	_remote_presentation_cache[peer_id] = result
	return result

func _project_remote_vertical(sample: Dictionary, target_tick: float) -> Dictionary:
	var projected := sample.duplicate(true)
	if _world == null or str(sample.get("locomotion_state", "running")) != "running" or bool(sample.get("blocked", false)):
		return projected
	var start_tick := float(sample.get("simulation_tick", target_tick))
	var remaining := clampf(target_tick - start_tick, 0.0, 6.0)
	var state := {"y": float(sample.get("y", 0.0)), "vertical_speed": float(sample.get("velocity_y", 0.0)), "gravity_direction": int(sample.get("gravity_direction", 1)), "grounded": bool(sample.get("grounded", false)), "cooldown": float(sample.get("cooldown", 0.0))}
	var world_x := float(sample.get("world_x", 0.0))
	var velocity_x := maxf(float(sample.get("velocity_x", Motion.BASE_RUN_SPEED)), 0.0)
	while remaining > 0.0001:
		if _profiling_enabled:
			_presentation_work_counts["projection_steps"] = int(_presentation_work_counts.projection_steps) + 1
		var step_ticks := minf(remaining, 1.0)
		var delta := step_ticks / 60.0
		var previous_state := state.duplicate(true)
		var previous_x := world_x
		world_x += velocity_x * delta
		var floor_surface: Dictionary = _world.surface_at(world_x, false)
		var ceiling_surface: Dictionary = _world.surface_at(world_x, true)
		if _profiling_enabled:
			_presentation_work_counts["surface_queries"] = int(_presentation_work_counts.surface_queries) + 2
		Motion.advance_vertical(state, delta, float(floor_surface.get("y", _manifest.initial_floor_y)), float(ceiling_surface.get("y", _manifest.initial_ceiling_y)), bool(floor_surface.get("supported", false)), bool(ceiling_surface.get("supported", false)))
		var candidate := {"world_x": world_x, "y": float(state.y), "gravity_direction": int(state.gravity_direction), "state": "running", "blocked": false}
		var contact: Dictionary = _world.player_contact(candidate)
		if _profiling_enabled:
			_presentation_work_counts["contact_queries"] = int(_presentation_work_counts.contact_queries) + 1
		if not contact.is_empty():
			state = previous_state
			world_x = previous_x
			break
		remaining -= step_ticks
	projected["world_x"] = world_x
	projected["y"] = float(state.y)
	projected["velocity_y"] = float(state.vertical_speed)
	projected["grounded"] = bool(state.grounded)
	return projected

func _record_presentation_diagnostic(delta: float) -> void:
	var diagnostic_started_usec := Time.get_ticks_usec() if _profiling_enabled else 0
	var now_usec := Time.get_ticks_usec()
	if not _round_started:
		_last_process_usec = -1
		return
	if _last_process_usec >= 0:
		_godot_frame_intervals_ms.append(float(now_usec - _last_process_usec) / 1000.0)
	_last_process_usec = now_usec
	if not _profiling_enabled and (_last_cadence_window_usec < 0 or now_usec - _last_cadence_window_usec < 1_000_000):
		return
	if _profiling_enabled and _last_remote_watch_usec >= 0 and now_usec - _last_remote_watch_usec < 100_000:
		if _last_cadence_window_usec < 0 or now_usec - _last_cadence_window_usec < 1_000_000:
			if _profiling_enabled: _profile_phase("diagnostic_sampling", diagnostic_started_usec)
			return
	var peers := {}
	if _profiling_enabled:
		_last_remote_watch_usec = now_usec
		for peer_id in _remote_tracks:
			var pose := _remote_track_sample(int(peer_id))
			peers[str(peer_id)] = {"simulation_tick": float(pose.get("simulation_tick", -1.0)), "render_tick": float(pose.get("render_tick", -1.0)), "world_x": float(pose.get("world_x", 0.0)), "y": float(pose.get("y", 0.0)), "velocity_y": float(pose.get("velocity_y", 0.0)), "gravity_direction": int(pose.get("gravity_direction", 1)), "grounded": bool(pose.get("grounded", false)), "blocked": bool(pose.get("blocked", false)), "locomotion_state": str(pose.get("locomotion_state", "unknown")), "render_mode": str(pose.get("render_mode", "unknown")), "sample_age_ticks": float(pose.get("sample_age_ticks", -1.0))}
		for peer_key in peers:
			var current: Dictionary = peers[peer_key]
			var previous: Dictionary = _last_remote_watch_poses.get(peer_key, {})
			if not previous.is_empty() and (absf(float(current.y) - float(previous.y)) >= 24.0 or int(current.gravity_direction) != int(previous.gravity_direction) or bool(current.grounded) != bool(previous.grounded) or bool(current.blocked) != bool(previous.blocked) or str(current.locomotion_state) != str(previous.locomotion_state)):
				MultiplayerV2Service.diagnostics.record_event("remote_presentation_change", {"peer_id": int(peer_key), "presentation_tick": float(current.render_tick), "previous": previous, "current": current})
		_last_remote_watch_poses = peers.duplicate(true) if _profiling_enabled else _last_remote_watch_poses
	if _profiling_enabled:
		MultiplayerV2Service.diagnostics.record_frame({"phase": "spectator" if _spectator_peer_id > 0 else "running", "tick": _runner.simulation_tick, "world_tick": _world.tick, "x": float(_runner.player_state.get("world_x", 0.0)), "y": float(_runner.player_state.get("y", 0.0)), "camera_left": _camera_left, "camera_delta_x": _camera_left - _previous_camera_left, "render_fraction": _render_fraction, "render_delta_ms": delta * 1000.0, "fps": Engine.get_frames_per_second(), "window_focused": DisplayServer.window_is_focused(), "presentation_tick": float(MultiplayerV2Service._round_coordinator.clock.tick_at_monotonic_usec(now_usec)) if _round_started else -1.0, "remote": peers})
	if _last_cadence_window_usec < 0:
		_last_cadence_window_usec = now_usec
	if now_usec - _last_cadence_window_usec >= 1_000_000:
		var window := _summarize_intervals(_godot_frame_intervals_ms)
		window["engine_fps"] = Engine.get_frames_per_second()
		window["elapsed_round_tick"] = _world_tick
		window["presentation_tick"] = float(MultiplayerV2Service._round_coordinator.clock.tick_at_monotonic_usec(now_usec)) - PRESENTATION_DELAY_TICKS if _round_started else -1.0
		window["profiling_enabled"] = _profiling_enabled
		if _profiling_enabled:
			window["obstacle_transform"] = _diagnostic_obstacle_transform()
			window["barrel_transform"] = _diagnostic_barrel_transform()
			window["presentation_work_counts"] = _presentation_work_counts.duplicate(true)
		var browser_window := _take_browser_frame_window()
		if not browser_window.is_empty():
			window["browser_raf"] = _summarize_intervals(_intervals_from_json(browser_window.get("intervals", [])))
			for key in ["device_pixel_ratio", "canvas_css_width", "canvas_css_height"]:
				if browser_window.has(key):
					window[key] = browser_window[key]
		if _profiling_enabled: _profile_phase("diagnostic_sampling", diagnostic_started_usec)
		if _profiling_enabled:
			window["phase_profile"] = _take_phase_profile()
		if _profiling_enabled and _course_presentation.has_method("take_render_profile"):
			window["course_render_profile"] = _course_presentation.call("take_render_profile")
		MultiplayerV2Service.diagnostics.record_event("render_cadence_window", window)
		_godot_frame_intervals_ms.clear()
		for key in _presentation_work_counts:
			_presentation_work_counts[key] = 0
		_last_cadence_window_usec = now_usec
	else:
		if _profiling_enabled: _profile_phase("diagnostic_sampling", diagnostic_started_usec)

func _summarize_intervals(intervals: Array[float]) -> Dictionary:
	if intervals.is_empty():
		return {"sample_count": 0, "p50_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "over_8_3_ms": 0, "over_16_7_ms": 0, "over_33_3_ms": 0}
	var ordered := intervals.duplicate()
	ordered.sort()
	var over_16_7 := 0
	var over_8_3 := 0
	var over_33_3 := 0
	for interval in intervals:
		if interval > 8.3:
			over_8_3 += 1
		if interval > 16.7:
			over_16_7 += 1
		if interval > 33.3:
			over_33_3 += 1
	return {"sample_count": intervals.size(), "p50_ms": ordered[int(round(float(ordered.size() - 1) * 0.50))], "p95_ms": ordered[int(round(float(ordered.size() - 1) * 0.95))], "max_ms": ordered.back(), "over_8_3_ms": over_8_3, "over_16_7_ms": over_16_7, "over_33_3_ms": over_33_3}

func _intervals_from_json(raw: Variant) -> Array[float]:
	var result: Array[float] = []
	if raw is Array:
		for value in raw:
			var interval := float(value)
			if is_finite(interval) and interval >= 0.0:
				result.append(interval)
	return result

func _install_browser_frame_diagnostics() -> void:
	if not OS.has_feature("web"):
		return
	var script := "(function(){if(window.__gravityRunRafDiag)return;var d={intervals:[],samples:[],last:null,frameIndex:0,take:function(){var canvas=document.getElementById('canvas');var r=canvas?canvas.getBoundingClientRect():{width:0,height:0};var out={intervals:d.intervals,device_pixel_ratio:window.devicePixelRatio||1,canvas_css_width:r.width,canvas_css_height:r.height};d.intervals=[];return JSON.stringify(out);},beginTrace:function(){var canvas=document.getElementById('canvas');var r=canvas?canvas.getBoundingClientRect():{width:0,height:0};return JSON.stringify({frame_index:d.frameIndex,browser_now_ms:performance.now(),device_pixel_ratio:window.devicePixelRatio||1,canvas_css_width:r.width,canvas_css_height:r.height});},takeTrace:function(from){var canvas=document.getElementById('canvas');var r=canvas?canvas.getBoundingClientRect():{width:0,height:0};var retained=d.samples.length?d.samples[0].frame_index:d.frameIndex;var out={samples:d.samples.filter(function(s){return s.frame_index>=from;}),dropped_samples:Math.max(0,retained-from),browser_now_ms:performance.now(),device_pixel_ratio:window.devicePixelRatio||1,canvas_css_width:r.width,canvas_css_height:r.height};return JSON.stringify(out);}};window.__gravityRunRafDiag=d;function pulse(t){if(d.last!==null){d.intervals.push(t-d.last);if(d.intervals.length>512)d.intervals.shift();}d.last=t;d.samples.push({frame_index:d.frameIndex,performance_ms:t});d.frameIndex++;if(d.samples.length>2048)d.samples.shift();window.requestAnimationFrame(pulse);}window.requestAnimationFrame(pulse);})()"
	JavaScriptBridge.eval(script)

func _take_browser_frame_window() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var encoded := str(JavaScriptBridge.eval("window.__gravityRunRafDiag ? window.__gravityRunRafDiag.take() : ''"))
	if encoded.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(encoded)
	return parsed if parsed is Dictionary else {}

func _capture_common_course_flow_frame(delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if not _flow_trace_active:
		if _flow_trace_windows >= FLOW_TRACE_MAX_WINDOWS or _flow_trace_useful_windows >= FLOW_TRACE_MAX_USEFUL_WINDOWS or _flow_trace_total_frames >= FLOW_TRACE_MAX_TOTAL_FRAMES:
			return
		var visible_static := _find_visible_course_target(false)
		var visible_moving := _find_visible_course_target(true)
		# Always preserve the opening after start; later windows are reserved for
		# actual visible course entities so the budget reaches obstacle flow.
		if _flow_trace_windows > 0 and visible_static.is_empty() and visible_moving.is_empty():
			return
		if _flow_trace_useful_windows >= FLOW_TRACE_MAX_USEFUL_WINDOWS - 1 and not _flow_trace_moving_target_sampled and visible_moving.is_empty():
			return
		_begin_flow_trace_window(now_usec, visible_static, visible_moving)
	var static_valid := is_instance_valid(_flow_trace_static_target)
	var moving_valid := is_instance_valid(_flow_trace_moving_target)
	if _render_camera == null or _render_camera.get_instance_id() != _flow_trace_camera_instance_id:
		_close_flow_trace("camera_changed")
		return
	if get_viewport().get_visible_rect().size != _flow_trace_viewport_size:
		_close_flow_trace("viewport_changed")
		return
	if not static_valid and not _flow_trace_static_id.is_empty():
		_close_flow_trace("static_target_removed")
		return
	if not moving_valid and not _flow_trace_moving_id.is_empty():
		_close_flow_trace("moving_target_removed")
		return
	if static_valid and not _node_is_visible_in_canvas(_flow_trace_static_target):
		_close_flow_trace("static_target_visibility_lost")
		return
	if moving_valid and not _node_is_visible_in_canvas(_flow_trace_moving_target):
		_close_flow_trace("moving_target_visibility_lost")
		return
	if not static_valid:
		var newly_visible := _find_visible_course_target(false)
		if not newly_visible.is_empty():
			_set_flow_static_target(newly_visible)
	if not moving_valid:
		var newly_moving := _find_visible_course_target(true)
		if not newly_moving.is_empty():
			_set_flow_moving_target(newly_moving)
			_flow_trace_moving_target_sampled = true
	var now_frame_usec := Time.get_ticks_usec()
	var viewport := get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	var local_state: Dictionary = _runner.player_state
	var local_pose: Dictionary = _local_presentation_pose if not _local_presentation_pose.is_empty() else _runner.render_state(_render_fraction)
	var row := {"at_usec": now_frame_usec, "frame_index": _flow_trace_frame_index, "render_delta_seconds": delta, "render_callback_index": _render_callback_index, "render_callback_begin_usec": _render_callback_begin_usec, "presentation_anchor_usec": _presentation_anchor_usec, "presentation_ready_usec": _presentation_ready_usec, "presentation_anchor_age_at_capture_usec": now_frame_usec - _presentation_anchor_usec, "simulation_tick": _world_tick, "presentation_tick": _last_presentation_tick, "local_pose_tick": float(_local_presentation_pose.get("tick", _runner.simulation_tick)), "world_render_fraction": _last_world_render_fraction, "physics_interpolation_fraction": _render_fraction, "phase": "spectator" if _spectator_peer_id > 0 else ("finished" if not _result.is_empty() else "running"), "local_player": {"state": str(local_state.get("state", "running")), "blocked": bool(local_state.get("blocked", false)), "simulated_speed_px_s": float(local_pose.get("velocity_x", 0.0)), "world_position": _vector_dict(Vector2(float(local_pose.get("world_x", 0.0)), float(local_pose.get("y", 0.0))))}, "camera": _camera_trace_state(canvas_transform), "static_target": _flow_target_trace(_flow_trace_static_target, _flow_trace_static_id, false), "moving_target": _flow_target_trace(_flow_trace_moving_target, _flow_trace_moving_id, true)}
	_flow_trace_frames.append(row)
	_flow_trace_frame_index += 1
	_flow_trace_total_frames += 1
	if _flow_trace_frames.size() >= FLOW_TRACE_MAX_FRAMES:
		_close_flow_trace("sample_window_complete")

func _begin_flow_trace_window(now_usec: int, static_target: Dictionary, moving_target: Dictionary) -> void:
	_flow_trace_active = true
	_flow_trace_started_usec = now_usec
	_flow_trace_frames.clear()
	_flow_trace_static_target = null
	_flow_trace_static_id = ""
	_flow_trace_moving_target = null
	_flow_trace_moving_id = ""
	if not static_target.is_empty():
		_set_flow_static_target(static_target)
	if not moving_target.is_empty():
		_set_flow_moving_target(moving_target)
		_flow_trace_moving_target_sampled = true
	var viewport := get_viewport()
	_flow_trace_view_metrics = {"viewport_size": _vector_dict(viewport.get_visible_rect().size), "window_size": _vector_dict(DisplayServer.window_get_size()), "device_pixel_ratio": 1.0, "canvas_css_size": _vector_dict(viewport.get_visible_rect().size), "raf_clock": "browser performance.now timestamps are mapped to Godot monotonic usec using a before/after bridge bracket at window close"}
	_flow_trace_camera_instance_id = _render_camera.get_instance_id() if is_instance_valid(_render_camera) else 0
	_flow_trace_viewport_size = viewport.get_visible_rect().size
	if OS.has_feature("web"):
		var encoded := str(JavaScriptBridge.eval("window.__gravityRunRafDiag ? window.__gravityRunRafDiag.beginTrace() : ''"))
		var metrics: Variant = JSON.parse_string(encoded) if not encoded.is_empty() else {}
		if metrics is Dictionary:
			_flow_trace_browser_start_index = int(metrics.get("frame_index", 0))
			for key in ["device_pixel_ratio", "canvas_css_width", "canvas_css_height"]:
				if metrics.has(key): _flow_trace_view_metrics[key] = metrics[key]
	_flow_trace_windows += 1

func _set_flow_static_target(target: Dictionary) -> void:
	_flow_trace_static_target = target.get("node") as Node2D
	_flow_trace_static_id = str(target.get("id", ""))

func _set_flow_moving_target(target: Dictionary) -> void:
	_flow_trace_moving_target = target.get("node") as Node2D
	_flow_trace_moving_id = str(target.get("id", ""))

func _find_visible_course_target(moving: bool) -> Dictionary:
	if _course_presentation == null:
		return {}
	var local_x := float(_local_presentation_pose.get("world_x", _runner.player_state.get("world_x", 0.0)))
	var selected: Dictionary = {}
	var selected_distance := INF
	for node_value in _course_presentation.event_nodes.values():
		if not is_instance_valid(node_value) or not node_value is Node2D:
			continue
		var node := node_value as Node2D
		if not node.has_meta("presentation_target") or not bool(node.get_meta("presentation_target_obstacle", false)) or bool(node.get_meta("presentation_target_moving", false)) != moving:
			continue
		if not _node_is_visible_in_canvas(node):
			continue
		var event_id := str(node.get_meta("presentation_target_id", ""))
		var kind := str(node.get_meta("presentation_target_kind", ""))
		if event_id.is_empty():
			continue
		var distance := absf(node.global_position.x - local_x)
		if distance < selected_distance:
			selected = {"id": event_id, "kind": kind, "node": node}
			selected_distance = distance
	return selected

func _node_is_visible_in_canvas(node: Node2D) -> bool:
	if not is_instance_valid(node) or not node.is_visible_in_tree():
		return false
	var canvas_position := node.get_global_transform_with_canvas().origin
	var rect := get_viewport().get_visible_rect()
	return canvas_position.x >= rect.position.x - 64.0 and canvas_position.x <= rect.end.x + 64.0 and canvas_position.y >= rect.position.y - 96.0 and canvas_position.y <= rect.end.y + 96.0

func _camera_trace_state(canvas_transform: Transform2D) -> Dictionary:
	return {"target_position": _vector_dict(Vector2(_camera_left + CAMERA_PLAYER_X, 0.0)), "applied_position": _vector_dict(_render_camera.global_position), "zoom": _vector_dict(_render_camera.zoom), "viewport_canvas_transform": _transform_dict(canvas_transform), "viewport_canvas_size": _vector_dict(get_viewport().get_visible_rect().size), "canvas_metrics": _flow_trace_view_metrics.duplicate(false)}

func _flow_target_trace(node: Node2D, stable_id: String, moving: bool) -> Dictionary:
	if not is_instance_valid(node):
		return {"id": stable_id, "valid": false}
	var result := {"id": stable_id, "kind": str(node.get_meta("presentation_target_kind", "unknown")), "visible": _node_is_visible_in_canvas(node), "global_position": _vector_dict(node.global_position), "canvas_position": _vector_dict(node.get_global_transform_with_canvas().origin), "rotation": node.global_rotation, "moving": moving}
	if moving and str(node.get_meta("presentation_target_kind", "")) == "barrel" and _world != null:
		var probe: Dictionary = _world.barrel_presentation_probe(stable_id, _last_presentation_tick, _last_world_render_fraction)
		result["previous"] = probe.get("previous", {})
		result["current"] = probe.get("current", {})
		result["displayed"] = probe.get("displayed", {})
		for barrel in _world.barrels:
			if str(barrel.get("entity_id", "")) == stable_id:
				result["lifecycle"] = {"spawned": bool(barrel.get("spawned", false)), "falling": bool(barrel.get("falling", false)), "destroyed": bool(barrel.get("destroyed", false)), "simulation_tick": _world.tick}
				break
	return result

func _close_flow_trace(reason: String) -> void:
	if not _flow_trace_active:
		return
	var ended_usec := Time.get_ticks_usec()
	var browser_trace := _take_browser_trace_window() if OS.has_feature("web") else {}
	var browser_samples: Array = browser_trace.get("samples", []) if browser_trace is Dictionary else []
	var bridge_before := int(browser_trace.get("bridge_before_usec", ended_usec)) if browser_trace is Dictionary else ended_usec
	var bridge_after := int(browser_trace.get("bridge_after_usec", ended_usec)) if browser_trace is Dictionary else ended_usec
	var browser_now_usec := float(browser_trace.get("browser_now_ms", 0.0)) * 1000.0 if browser_trace is Dictionary else 0.0
	var clock_offset_usec := float(bridge_before + bridge_after) * 0.5 - browser_now_usec if browser_trace is Dictionary else 0.0
	for sample in browser_samples:
		if sample is Dictionary:
			sample["godot_monotonic_usec_estimate"] = int(float(sample.get("performance_ms", 0.0)) * 1000.0 + clock_offset_usec)
	var trace_close_reason := reason
	if browser_trace is Dictionary:
		for pair in [["device_pixel_ratio", "device_pixel_ratio"], ["canvas_css_width", "canvas_css_width"], ["canvas_css_height", "canvas_css_height"]]:
			var metric_name: String = pair[0]
			var trace_name: String = pair[1]
			var ending_value: float = float(browser_trace.get(metric_name, _flow_trace_view_metrics.get(trace_name, 0.0)))
			if not is_equal_approx(ending_value, float(_flow_trace_view_metrics.get(trace_name, ending_value))):
				trace_close_reason = "canvas_scale_changed"
	var qualifies_as_useful_window := _flow_trace_frames.size() >= FLOW_TRACE_MIN_USEFUL_FRAMES
	if qualifies_as_useful_window:
		_flow_trace_useful_windows += 1
	MultiplayerV2Service.diagnostics.record_event("common_course_flow_trace", {"window_index": _flow_trace_windows, "useful_window_index": _flow_trace_useful_windows if qualifies_as_useful_window else -1, "useful_window": qualifies_as_useful_window, "useful_window_min_frames": FLOW_TRACE_MIN_USEFUL_FRAMES, "total_trace_frames": _flow_trace_total_frames, "started_at_usec": _flow_trace_started_usec, "ended_at_usec": ended_usec, "duration_usec": maxi(ended_usec - _flow_trace_started_usec, 0), "close_reason": trace_close_reason, "static_target_id": _flow_trace_static_id, "moving_target_id": _flow_trace_moving_id, "sample_count": _flow_trace_frames.size(), "dropped_samples": 0, "frame_index_start": _flow_trace_frame_index - _flow_trace_frames.size(), "frame_index_end": _flow_trace_frame_index - 1, "view_metrics": _flow_trace_view_metrics, "browser_raf": {"start_frame_index": _flow_trace_browser_start_index, "sample_count": browser_samples.size(), "dropped_samples": int(browser_trace.get("dropped_samples", 0)) if browser_trace is Dictionary else 0, "clock_mapping_offset_usec": clock_offset_usec, "bridge_uncertainty_usec": maxi(bridge_after - bridge_before, 0), "samples": browser_samples}, "frames": _flow_trace_frames})
	_flow_trace_active = false
	_flow_trace_started_usec = -1
	_flow_trace_frames.clear()
	_flow_trace_static_target = null
	_flow_trace_static_id = ""
	_flow_trace_moving_target = null
	_flow_trace_moving_id = ""
	_flow_trace_view_metrics.clear()
	_flow_trace_camera_instance_id = 0
	_flow_trace_viewport_size = Vector2.ZERO

func _take_browser_trace_window() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var before_usec := Time.get_ticks_usec()
	var encoded := str(JavaScriptBridge.eval("window.__gravityRunRafDiag ? window.__gravityRunRafDiag.takeTrace(%d) : ''" % _flow_trace_browser_start_index))
	var after_usec := Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(encoded) if not encoded.is_empty() else {}
	if parsed is Dictionary:
		parsed["bridge_before_usec"] = before_usec
		parsed["bridge_after_usec"] = after_usec
		return parsed
	return {}

static func _vector_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

static func _transform_dict(value: Transform2D) -> Dictionary:
	return {"x": _vector_dict(value.x), "y": _vector_dict(value.y), "origin": _vector_dict(value.origin)}

func _record_start_stage(name: String, at_usec: int, details: Dictionary = {}) -> void:
	if _start_profile_recorded.has(name):
		return
	_start_profile_recorded[name] = at_usec
	var entry := {"stage": name, "at_usec": at_usec, "relative_to_deadline_usec": at_usec - _local_start_deadline_usec, "simulation_tick": _world_tick}
	entry.merge(details, true)
	MultiplayerV2Service.diagnostics.record_event("start_stage_profile", entry)

func _capture_first_course_draw_profile() -> void:
	if _course_presentation == null or not _course_presentation.has_method("take_start_draw_profile"):
		return
	var sample: Dictionary = _course_presentation.call("take_start_draw_profile")
	if not sample.is_empty() and not _start_profile_recorded.has("first_course_draw"):
		_record_start_stage("first_course_draw", int(sample.get("at_usec", Time.get_ticks_usec())), sample)

func _diagnostic_obstacle_transform() -> Dictionary:
	if _manifest == null or _course_presentation == null:
		return {}
	var local_pose: Dictionary = _local_presentation_pose if not _local_presentation_pose.is_empty() else _runner.player_state
	var local_x := float(local_pose.get("world_x", 0.0))
	var selected: Dictionary = {}
	var selected_x := INF
	for event in _manifest.events:
		if not event is Dictionary or str(event.get("kind", "")) not in ["block", "spikes"]:
			continue
		var event_x := float(event.get("start_x", event.get("x", 0.0)))
		if event_x >= local_x - 200.0 and event_x < selected_x:
			selected = event
			selected_x = event_x
	if selected.is_empty():
		return {"obstacle_id": "none", "local_world_x": local_x}
	var event_id := str(selected.get("event_id", ""))
	var node_key := event_id + "_0" if str(selected.get("kind", "")) == "spikes" else event_id
	var node_value: Variant = _course_presentation.event_nodes.get(node_key)
	var world_position := Vector2(selected_x, float(selected.get("y", _manifest.initial_floor_y)))
	var canvas_position := get_viewport().get_canvas_transform() * world_position
	if is_instance_valid(node_value) and node_value is Node2D:
		world_position = (node_value as Node2D).global_position
		canvas_position = (node_value as Node2D).get_global_transform_with_canvas().origin
	return {"obstacle_id": event_id, "kind": str(selected.get("kind", "")), "world_x": world_position.x, "world_y": world_position.y, "canvas_x": canvas_position.x, "canvas_y": canvas_position.y, "camera_left": _camera_left, "local_world_x": local_x, "node_valid": is_instance_valid(node_value)}

func _diagnostic_barrel_transform() -> Dictionary:
	var previous_id := str(_last_barrel_probe.get("entity_id", ""))
	if _world == null or _course_presentation == null:
		return {"entity_id": "", "previous_probe_entity_id": previous_id, "target_changed": not previous_id.is_empty(), "stage": "unavailable"}
	var selected := _find_visible_barrel()
	if selected.is_empty():
		_last_barrel_probe = {"entity_id": ""}
		return {"entity_id": "", "previous_probe_entity_id": previous_id, "target_changed": not previous_id.is_empty(), "stage": "no_visible_spawned_barrel", "simulation_tick": int(_world.tick)}
	var entity_id := str(selected.entity_id)
	var probe: Dictionary = _world.barrel_presentation_probe(entity_id, _last_presentation_tick, _last_world_render_fraction)
	var node: Node2D = selected.node
	var canvas_position: Vector2 = node.get_global_transform_with_canvas().origin
	probe["world_x"] = node.global_position.x
	probe["world_y"] = node.global_position.y
	probe["canvas_x"] = canvas_position.x
	probe["canvas_y"] = canvas_position.y
	probe["screen_x"] = canvas_position.x
	probe["screen_y"] = canvas_position.y
	probe["camera_left"] = _camera_left
	probe["node_visible"] = node.visible
	probe["target_changed"] = not previous_id.is_empty() and previous_id != entity_id
	probe["previous_probe_entity_id"] = previous_id
	if previous_id == entity_id:
		probe["same_entity_delta"] = {"elapsed_ms": float(Time.get_ticks_usec() - int(_last_barrel_probe.get("at_usec", Time.get_ticks_usec()))) / 1000.0, "world_dx": node.global_position.x - float(_last_barrel_probe.get("world_x", node.global_position.x)), "world_dy": node.global_position.y - float(_last_barrel_probe.get("world_y", node.global_position.y))}
	_last_barrel_probe = {"entity_id": entity_id, "world_x": node.global_position.x, "world_y": node.global_position.y, "at_usec": Time.get_ticks_usec()}
	return probe

func _find_visible_barrel() -> Dictionary:
	var viewport_width := get_viewport_rect().size.x
	var selected: Dictionary = {}
	var selected_distance := INF
	for barrel in _world.barrels:
		if not bool(barrel.get("spawned", false)) or bool(barrel.get("destroyed", false)):
			continue
		var entity_id := str(barrel.get("entity_id", ""))
		var node_value: Variant = _course_presentation.event_nodes.get(entity_id)
		if not is_instance_valid(node_value) or not node_value is Node2D or not (node_value as Node2D).visible:
			continue
		var canvas_position: Vector2 = (node_value as Node2D).get_global_transform_with_canvas().origin
		if canvas_position.x < 0.0 or canvas_position.x > viewport_width:
			continue
		var distance := absf(canvas_position.x - CAMERA_PLAYER_X)
		if distance < selected_distance:
			selected = {"entity_id": entity_id, "node": node_value}
			selected_distance = distance
	return selected

func _capture_barrel_frame_trace() -> void:
	var selected := _find_visible_barrel()
	if selected.is_empty():
		_close_barrel_frame_trace(_barrel_trace_loss_reason())
		return
	var entity_id := str(selected.entity_id)
	if not _barrel_trace_entity_id.is_empty() and _barrel_trace_entity_id != entity_id:
		_close_barrel_frame_trace("visible_target_changed")
	if _barrel_trace_entity_id.is_empty():
		_barrel_trace_entity_id = entity_id
		_barrel_trace_started_usec = Time.get_ticks_usec()
	var node: Node2D = selected.node
	var canvas_position: Vector2 = node.get_global_transform_with_canvas().origin
	var barrel_state: Dictionary = _world.barrel_presentation_probe(entity_id, _last_presentation_tick, _last_world_render_fraction)
	_barrel_trace_frames.append({"at_usec": Time.get_ticks_usec(), "simulation_tick": _world.tick, "presentation_tick": _last_presentation_tick, "presentation_fraction": _last_world_render_fraction, "entity_id": entity_id, "previous": barrel_state.get("previous", {}), "current": barrel_state.get("current", {}), "displayed": barrel_state.get("displayed", {}), "world_x": node.global_position.x, "world_y": node.global_position.y, "canvas_x": canvas_position.x, "canvas_y": canvas_position.y, "rotation": node.rotation})
	if _barrel_trace_frames.size() >= 120:
		_close_barrel_frame_trace("sample_window_complete")

func _close_barrel_frame_trace(reason: String) -> void:
	if not _barrel_trace_entity_id.is_empty() and not _barrel_trace_frames.is_empty():
		MultiplayerV2Service.diagnostics.record_event("barrel_render_trace", {"entity_id": _barrel_trace_entity_id, "sample_count": _barrel_trace_frames.size(), "duration_ms": float(Time.get_ticks_usec() - _barrel_trace_started_usec) / 1000.0 if _barrel_trace_started_usec >= 0 else 0.0, "close_reason": reason, "samples": _barrel_trace_frames})
	_barrel_trace_entity_id = ""
	_barrel_trace_started_usec = -1
	_barrel_trace_frames.clear()

func _barrel_trace_loss_reason() -> String:
	if _barrel_trace_entity_id.is_empty() or _world == null:
		return "target_not_visible"
	for barrel in _world.barrels:
		if str(barrel.get("entity_id", "")) == _barrel_trace_entity_id:
			return "entity_destroyed" if bool(barrel.get("destroyed", false)) else "target_not_visible"
	return "entity_removed"

func _profile_phase(name: String, started_usec: int) -> void:
	if not _profiling_enabled:
		return
	var elapsed_usec := maxi(Time.get_ticks_usec() - started_usec, 0)
	var sample: Dictionary = _phase_profile.get(name, {"total_usec": 0, "max_usec": 0, "sample_count": 0})
	sample["total_usec"] = int(sample.total_usec) + elapsed_usec
	sample["max_usec"] = maxi(int(sample.max_usec), elapsed_usec)
	sample["sample_count"] = int(sample.sample_count) + 1
	_phase_profile[name] = sample

func _take_phase_profile() -> Dictionary:
	var profile := _phase_profile.duplicate(true)
	for phase in profile:
		var sample: Dictionary = profile[phase]
		var count := maxi(int(sample.get("sample_count", 0)), 1)
		sample["average_usec"] = float(sample.get("total_usec", 0)) / float(count)
	_phase_profile.clear()
	return profile

func _update_hud() -> void:
	_update_coin_count_indicator()
	if not _result.is_empty():
		_status_label.text = ""
		return
	var state_name := str(_runner.player_state.get("state", "running"))
	if state_name == "pending_barrel":
		_status_label.text = tr("Waiting for shared barrel decision…")
	elif state_name in ["dead", "finished"]:
		if _spectator_peer_id > 0:
			var display_name := spectator_display_name(_spectator_peer_id, _frozen_roster, tr("Player"))
			_status_label.text = tr("Watching %s") % display_name
		else:
			_status_label.text = tr("Waiting for host result…")
	else:
		_status_label.text = ""

func _update_coin_count_indicator() -> void:
	if is_instance_valid(_shared_run_hud):
		_shared_run_hud.call("set_coins", _local_shared_coin_count())

func _local_shared_coin_count() -> int:
	if _world == null:
		return 0
	var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
	var total := 0
	for entity_id in _world.entity_ledger.entities:
		var entity: Dictionary = _world.entity_ledger.entities[entity_id]
		if str(entity.get("kind", "")) == "coin" and str(entity.get("state", "")) == "collected" and int(entity.get("winner_peer_id", 0)) == local_peer:
			total += int(entity.get("award_value", 0))
	return total

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
	var draw_order := _frozen_roster.duplicate(true)
	var local_peer := int(MultiplayerV2Service.session.get("local_peer_id", 1))
	draw_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_local := int(a.get("player_slot", -1)) == local_peer
		var b_local := int(b.get("player_slot", -1)) == local_peer
		if a_local != b_local:
			return not a_local
		return int(a.get("player_slot", -1)) < int(b.get("player_slot", -1))
	)
	for member in draw_order:
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
		var local_render: Dictionary = _local_presentation_pose if not _local_presentation_pose.is_empty() else _runner.render_state(_render_fraction)
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
	var started_usec := Time.get_ticks_usec() if _profiling_enabled and _round_started else 0
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
	if _profiling_enabled and _round_started and not _start_profile_recorded.has("first_figure_presentation"):
		_record_start_stage("first_figure_presentation", Time.get_ticks_usec(), {"duration_usec": Time.get_ticks_usec() - started_usec, "player_count": _player_views.size()})

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
	if not MultiplayerV2Service.has_room():
		_leave_v2()
		return
	_return_lobby_button.disabled = true
	_return_lobby_button.text = tr("Returning…")
	MultiplayerV2Service.return_to_lobby()

func _navigate_lobby() -> void:
	if _lobby_navigation_pending:
		return
	_lobby_navigation_pending = true
	AppNavigation.request_multiplayer_lobby()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _on_lobby_request_finished(action: String, success: bool, message: String) -> void:
	if action in ["return_to_lobby", "return_member"] and not success:
		_return_lobby_button.disabled = false
		_return_lobby_button.text = tr("Return to lobby")
		_result_text.clear()
		_result_text.add_text(message)

func _save_diagnostics() -> void:
	if _diagnostics_export_in_progress:
		return
	_diagnostics_export_in_progress = true
	var report := MultiplayerV2Service.diagnostics.export_report()
	report["current_state"] = MultiplayerV2Service.current_diagnostic_state()
	report["course_presentation_snapshot"] = _course_presentation_diagnostic_snapshot()
	if not _result.is_empty():
		report["frozen_result"] = _result.duplicate(true)
		report["frozen_roster"] = _frozen_roster.duplicate(true)
		report["frozen_terminal_poses"] = _remote_terminal_poses.duplicate(true)
	var saved_path := DiagnosticsExport.save_report(report, DiagnosticsExport.make_filename(report, "match"))
	_diagnostics_export_in_progress = false
	_export_notice_generation += 1
	_export_confirmation.text = tr("Diagnostics saved: %s") % saved_path
	_export_confirmation.visible = true
	var generation := _export_notice_generation
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if generation == _export_notice_generation and is_instance_valid(_export_confirmation):
			_export_confirmation.visible = false
	)

func _course_presentation_diagnostic_snapshot() -> Dictionary:
	var snapshot := {"mode": "multiplayer_v2", "round_id": _round_id, "generator_version": int(_manifest.get("generator_version")) if _manifest != null else -1, "world_tick": _world.tick if _world != null else -1, "camera_left": _camera_left, "viewport": [get_viewport_rect().size.x, get_viewport_rect().size.y], "world_distance": float(_runner.player_state.get("world_x", 0.0)) - float(_manifest.get("start_x")) if _runner != null and _manifest != null else 0.0, "generated_coins": 0, "generated_hazards": {}, "presented_event_nodes": 0, "visible_event_nodes": 0, "coin_nodes": 0, "active_coins": 0, "collected_coins": 0, "visible_coins": 0, "in_view_coins": 0, "rocks": []}
	if _manifest != null:
		snapshot["generated_coins"] = _manifest.collectibles.size()
		for event in _manifest.events:
			var kind := str(event.get("kind", "unknown"))
			var counts: Dictionary = snapshot["generated_hazards"]
			counts[kind] = int(counts.get(kind, 0)) + 1
			if kind == "rock" and snapshot["rocks"].size() < 12:
				snapshot["rocks"].append({"event_id": str(event.get("event_id", "")), "x": float(event.get("x", 0.0)), "trigger_lead": float(event.get("trigger_lead", 0.0)), "warning_ticks": int(event.get("warning_ticks", 0)), "warning_seconds": float(event.get("warning_ticks", 0)) / 60.0, "fall_ticks": int(event.get("fall_ticks", 0)), "fall_seconds": float(event.get("fall_ticks", 0)) / 60.0})
	var ledger_entities: Dictionary = _world.entity_ledger.entities if _world != null else {}
	var nodes: Dictionary = _course_presentation.event_nodes if is_instance_valid(_course_presentation) else {}
	snapshot["presented_event_nodes"] = nodes.size()
	var view_right := _camera_left + get_viewport_rect().size.x
	for entity_id in nodes:
		var node_value: Variant = nodes[entity_id]
		if not is_instance_valid(node_value) or not node_value is Node2D:
			continue
		var node: Node2D = node_value
		var entity_state: Dictionary = ledger_entities.get(str(entity_id), {})
		if node.visible: snapshot["visible_event_nodes"] = int(snapshot["visible_event_nodes"]) + 1
		if not str(entity_id).begins_with("coin_"):
			continue
		snapshot["coin_nodes"] = int(snapshot["coin_nodes"]) + 1
		if str(entity_state.get("state", "active")) == "active": snapshot["active_coins"] = int(snapshot["active_coins"]) + 1
		if str(entity_state.get("state", "active")) == "collected": snapshot["collected_coins"] = int(snapshot["collected_coins"]) + 1
		if node.visible: snapshot["visible_coins"] = int(snapshot["visible_coins"]) + 1
		if node.position.x >= _camera_left and node.position.x <= view_right: snapshot["in_view_coins"] = int(snapshot["in_view_coins"]) + 1
	return snapshot

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
	MusicController.enter_menu()
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
