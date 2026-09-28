extends Control

const ManifestBuilderScript := preload("res://systems/course_manifest_builder.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")
const ReadyIndicatorScript := preload("res://ui/ready_indicator.gd")
const RunnerFrames := preload("res://assets/character/run_frames.tres")
const SkinPalette := preload("res://player/skin_palette.gd")

signal back_requested
signal match_start_requested

var _status: Label
var _room_code: LineEdit
var _name_edit: LineEdit
var _name_button: Button
var _room_code_button: Button
var _mobile_text_entry := false
var _scroll: ScrollContainer
var _panel: PanelContainer
var _layout: VBoxContainer
var _title: Label
var _players: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _create_button: Button
var _join_button: Button
var _home_view: VBoxContainer
var _create_view: VBoxContainer
var _join_view: VBoxContainer
var _room_view: VBoxContainer
var _public_rooms: VBoxContainer
var _public_toggle: CheckButton
var _room_summary: Label
var _active_view := "home"
var _public_list_busy := false
var _lobby_buttons: Array[Button] = []
var _prepared_hash := ""
var _prepared_manifest: Resource
var _course_loaded := false
var _manifest_transfer_parts: Dictionary = {}
var _manifest_publish_in_progress := false
var _countdown_remaining := 0.0
var _countdown_active := false
var _match_transition_requested := false
var _busy := false
var _skin_request_pending := false
var _manifest_build_started_msec := 0
var _manifest_transfer_started_msec: Dictionary = {}
var _manifest_transfer_last_sent_msec: Dictionary = {}
var _manifest_verified_peers: Dictionary = {}
var _diagnostics_status: Label
var _diagnostics_opt_in_button: Button
var _diagnostics_opt_out_button: Button
var _diagnostics_session_button: Button
var _latest_report_status: Label
var _latest_report_copy_button: Button
var _latest_report_save_button: Button
var _diagnostics_session_id_edit: LineEdit
var _fetch_diagnostics_button: Button
var _list_diagnostics_sessions_button: Button
var _download_fetched_diagnostics_button: Button
var _diagnostics_layout_option: OptionButton
var _diagnostics_instances_option: OptionButton

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_text_entry = MobileTextEntry.is_mobile_web
	MobileTextEntry.entry_submitted.connect(_on_mobile_text_submitted)
	PlayerAccountProfile.profile_changed.connect(_on_player_account_profile_changed)
	_build_ui()
	_on_player_account_profile_changed(PlayerAccountProfile.nickname, PlayerAccountProfile.has_profile)
	MultiplayerService.room_changed.connect(_on_room_changed)
	MultiplayerService.request_finished.connect(_on_request_finished)
	MultiplayerService.signaling_state_changed.connect(_on_signaling_state_changed)
	MultiplayerService.peer_connection_state_changed.connect(_on_peer_connection_state_changed)
	MultiplayerService.peer_data_received.connect(_on_peer_data_received)
	MultiplayerService.race_countdown_received.connect(_on_race_countdown_received)
	MultiplayerService.public_rooms_loaded.connect(_on_public_rooms_loaded)
	if MultiplayerService.has_room():
		_on_room_changed(MultiplayerService.room_state)

func _process(_delta: float) -> void:
	if not _countdown_active:
		return
	_countdown_remaining = maxf(float(MultiplayerService.race_start_at_unix) - Time.get_unix_time_from_system(), 0.0)
	_status.text = tr("Race starts in %d…") % ceili(_countdown_remaining)
	if _countdown_remaining <= 0.0 and not _match_transition_requested:
		_match_transition_requested = true
		match_start_requested.emit()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	var viewport := get_viewport_rect().size
	var panel_width := minf(620.0, maxf(viewport.x - 32.0, 280.0))
	var panel_height := minf(600.0, maxf(viewport.y - 28.0, 200.0))
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.offset_top = -panel_height * 0.5
	_panel.offset_bottom = panel_height * 0.5
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_layout = VBoxContainer.new()
	_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 10)
	_scroll.add_child(_layout)
	_title = Label.new()
	_title.text = tr("MULTIPLAYER LOBBY")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_layout.add_child(_title)
	_status = Label.new()
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layout.add_child(_status)
	_latest_report_status = Label.new()
	_latest_report_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_latest_report_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layout.add_child(_latest_report_status)
	var report_actions := HBoxContainer.new()
	_layout.add_child(report_actions)
	_latest_report_copy_button = _button(tr("Copy last multiplayer report"))
	_latest_report_copy_button.pressed.connect(_copy_latest_multiplayer_report)
	report_actions.add_child(_latest_report_copy_button)
	_latest_report_save_button = _button(tr("Save last report"))
	_latest_report_save_button.pressed.connect(_save_latest_multiplayer_report)
	report_actions.add_child(_latest_report_save_button)
	_diagnostics_session_id_edit = LineEdit.new()
	_diagnostics_session_id_edit.placeholder_text = tr("Shared debug ID")
	_layout.add_child(_diagnostics_session_id_edit)
	_fetch_diagnostics_button = _button(tr("Fetch all reports for debug ID"))
	_fetch_diagnostics_button.pressed.connect(func() -> void: MultiplayerDiagnostics.fetch_shared_session(_diagnostics_session_id_edit.text.strip_edges()))
	_layout.add_child(_fetch_diagnostics_button)
	_list_diagnostics_sessions_button = _button(tr("List recent diagnostic sessions"))
	_list_diagnostics_sessions_button.pressed.connect(_list_diagnostic_sessions)
	_layout.add_child(_list_diagnostics_sessions_button)
	_download_fetched_diagnostics_button = _button(tr("Save fetched reports JSON"))
	_download_fetched_diagnostics_button.pressed.connect(_save_fetched_diagnostics)
	_layout.add_child(_download_fetched_diagnostics_button)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Display name")
	_name_edit.max_length = 16
	_name_edit.focus_entered.connect(_ensure_focused_input_visible)
	_name_edit.focus_exited.connect(_restore_scroll_if_unfocused)
	_layout.add_child(_name_edit)
	if _mobile_text_entry:
		_name_edit.visible = false
		_name_button = _button(tr("Display name"))
		_name_button.pressed.connect(func() -> void: _open_mobile_text_entry("name", _name_edit.text))
		_layout.add_child(_name_button)

	_home_view = VBoxContainer.new()
	_home_view.add_theme_constant_override("separation", 8)
	_layout.add_child(_home_view)
	var create_mode := _button(tr("Create room"))
	create_mode.pressed.connect(func() -> void: _show_view("create"))
	_home_view.add_child(create_mode)
	var join_mode := _button(tr("Join a room"))
	join_mode.pressed.connect(func() -> void:
		_show_view("join")
		_load_public_rooms()
	)
	_home_view.add_child(join_mode)
	var home_back := _button(tr("Back"))
	home_back.pressed.connect(back_requested.emit)
	_home_view.add_child(home_back)

	_create_view = VBoxContainer.new()
	_create_view.add_theme_constant_override("separation", 8)
	_layout.add_child(_create_view)
	var create_heading := Label.new()
	create_heading.text = tr("Create a room")
	create_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_create_view.add_child(create_heading)
	_public_toggle = CheckButton.new()
	_public_toggle.text = tr("Public — show in open rooms")
	_create_view.add_child(_public_toggle)
	_create_button = _button(tr("Create room"))
	_create_button.pressed.connect(_create_room)
	_create_view.add_child(_create_button)
	var create_back := _button(tr("Back"))
	create_back.pressed.connect(func() -> void: _show_view("home"))
	_create_view.add_child(create_back)

	_join_view = VBoxContainer.new()
	_join_view.add_theme_constant_override("separation", 8)
	_layout.add_child(_join_view)
	var join_heading := Label.new()
	join_heading.text = tr("Join a room")
	join_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_view.add_child(join_heading)
	var code_label := Label.new()
	code_label.text = tr("Private room code")
	_join_view.add_child(code_label)
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	_join_view.add_child(create_row)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = tr("Room code")
	_room_code.max_length = 8
	_room_code.focus_entered.connect(_ensure_focused_input_visible)
	_room_code.focus_exited.connect(_restore_scroll_if_unfocused)
	_room_code.text_submitted.connect(func(_value: String) -> void: _join_room())
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_room_code)
	if _mobile_text_entry:
		_room_code.visible = false
		_room_code_button = _button(tr("Room code"))
		_room_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_room_code_button.pressed.connect(func() -> void: _open_mobile_text_entry("room_code", _room_code.text))
		create_row.add_child(_room_code_button)
	_join_button = _button(tr("Join"))
	_join_button.pressed.connect(_join_room)
	create_row.add_child(_join_button)
	var public_header := HBoxContainer.new()
	_join_view.add_child(public_header)
	var public_title := Label.new()
	public_title.text = tr("Open rooms")
	public_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_header.add_child(public_title)
	var refresh_public := _button(tr("Refresh"))
	refresh_public.pressed.connect(_load_public_rooms)
	public_header.add_child(refresh_public)
	var public_scroll := ScrollContainer.new()
	public_scroll.custom_minimum_size.y = 110
	public_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_join_view.add_child(public_scroll)
	_public_rooms = VBoxContainer.new()
	_public_rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_scroll.add_child(_public_rooms)
	var join_back := _button(tr("Back"))
	join_back.pressed.connect(func() -> void: _show_view("home"))
	_join_view.add_child(join_back)

	_room_view = VBoxContainer.new()
	_room_view.add_theme_constant_override("separation", 8)
	_layout.add_child(_room_view)
	_room_summary = Label.new()
	_room_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_view.add_child(_room_summary)
	var members_box := PanelContainer.new()
	members_box.add_theme_stylebox_override("panel", _inner_style())
	_room_view.add_child(members_box)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 6)
	members_box.add_child(_players)
	_ready_button = _button(tr("Ready"))
	_ready_button.pressed.connect(_toggle_ready)
	_ready_button.disabled = true
	_room_view.add_child(_ready_button)
	_start_button = _button(tr("Start race"))
	_start_button.disabled = true
	_start_button.pressed.connect(_request_start)
	_room_view.add_child(_start_button)
	_leave_button = _button(tr("Leave room"))
	_leave_button.pressed.connect(MultiplayerService.leave_room)
	_leave_button.visible = false
	_room_view.add_child(_leave_button)
	_diagnostics_opt_in_button = _button(tr("Enable diagnostic upload for this account"))
	_diagnostics_opt_in_button.pressed.connect(func() -> void: MultiplayerDiagnostics.opt_in(true))
	_room_view.add_child(_diagnostics_opt_in_button)
	_diagnostics_opt_out_button = _button(tr("Disable diagnostic upload"))
	_diagnostics_opt_out_button.pressed.connect(func() -> void: MultiplayerDiagnostics.opt_in(false))
	_room_view.add_child(_diagnostics_opt_out_button)
	_diagnostics_session_button = _button(tr("Create shared debug ID"))
	_diagnostics_session_button.pressed.connect(func() -> void: MultiplayerDiagnostics.start_shared_session(""))
	_room_view.add_child(_diagnostics_session_button)
	_diagnostics_status = Label.new()
	_diagnostics_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostics_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diagnostics_status.text = MultiplayerDiagnostics.get_status()
	_room_view.add_child(_diagnostics_status)
	_diagnostics_layout_option = OptionButton.new()
	_diagnostics_layout_option.add_item(tr("Test layout: unknown"), 0)
	_diagnostics_layout_option.add_item(tr("Split view + separate host"), 1)
	_diagnostics_layout_option.add_item(tr("Three separate windows"), 2)
	_diagnostics_layout_option.add_item(tr("Separate devices"), 3)
	_diagnostics_layout_option.add_item(tr("Other setup"), 4)
	_diagnostics_layout_option.item_selected.connect(_on_diagnostic_layout_selected)
	_room_view.add_child(_diagnostics_layout_option)
	_diagnostics_instances_option = OptionButton.new()
	_diagnostics_instances_option.add_item(tr("Instances on this device: unknown"), 0)
	for count in range(1, 6):
		_diagnostics_instances_option.add_item(tr("Instances on this device: %d") % count, count)
	_diagnostics_instances_option.item_selected.connect(_on_diagnostic_instances_selected)
	_room_view.add_child(_diagnostics_instances_option)
	_update_diagnostic_option_selections()
	MultiplayerDiagnostics.report_changed.connect(_on_diagnostics_status_changed)
	_update_latest_report_actions()
	for view in [_home_view, _create_view, _join_view, _room_view]:
		view.visible = false
	_show_view("home")
	_update_room(MultiplayerService.room_state)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _create_room() -> void:
	_set_busy(true)
	_release_lobby_input_focus()
	MultiplayerService.create_room(_name_edit.text, _public_toggle.button_pressed)

func _join_room() -> void:
	if _room_code.text.strip_edges().length() != 8:
		_status.text = tr("Enter the 8-character room code.")
		return
	_set_busy(true)
	_release_lobby_input_focus()
	MultiplayerService.join_room(_room_code.text, _name_edit.text)

func _join_public_room(room_code: String) -> void:
	_room_code.text = room_code
	_join_room()

func _load_public_rooms() -> void:
	if _public_list_busy:
		return
	_public_list_busy = true
	for child in _public_rooms.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = tr("Loading open rooms…")
	_public_rooms.add_child(loading)
	MultiplayerService.load_public_rooms()

func _on_public_rooms_loaded(rooms: Array, message: String) -> void:
	_public_list_busy = false
	for child in _public_rooms.get_children():
		child.queue_free()
	if not message.is_empty():
		_status.text = message
		return
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = tr("No open public rooms right now.")
		_public_rooms.add_child(empty)
		return
	for room in rooms:
		if not room is Dictionary:
			continue
		var room_code := str(room.get("room_code", ""))
		if room_code.length() != 8:
			continue
		var row := HBoxContainer.new()
		var summary := Label.new()
		summary.text = "%s · %d/%d" % [str(room.get("host_name", "Host")), int(room.get("player_count", 0)), int(room.get("max_players", 5))]
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(summary)
		var join := Button.new()
		join.text = tr("Join")
		join.custom_minimum_size.y = 36.0
		join.pressed.connect(_join_public_room.bind(room_code))
		row.add_child(join)
		_public_rooms.add_child(row)

func _toggle_ready() -> void:
	var already_ready := false
	for member in MultiplayerService.get_members():
		if member is Dictionary and str(member.get("user_id", "")) == MultiplayerService.identity_user_id:
			already_ready = bool(member.get("is_ready", false))
			break
	MultiplayerService.set_ready(not already_ready)
	if not already_ready:
		MultiplayerService.begin_peer_connection()

func _change_skin(direction: int) -> void:
	if _skin_request_pending or not MultiplayerService.has_room():
		return
	var current_skin := 0
	for member in MultiplayerService.get_members():
		if member is Dictionary and str(member.get("user_id", "")) == MultiplayerService.identity_user_id:
			current_skin = posmod(int(member.get("skin_id", 0)), SkinPalette.SKIN_COUNT)
			break
	_skin_request_pending = true
	_update_room(MultiplayerService.room_state)
	MultiplayerService.set_skin_id(posmod(current_skin + direction, SkinPalette.SKIN_COUNT))

func _request_start() -> void:
	if not MultiplayerService.can_start_race():
		_status.text = tr("Every player must be ready, have the same verified course, and be directly connected to the host.")
		return
	MultiplayerService.request_start()

func _on_room_changed(room: Dictionary) -> void:
	_update_room(room)
	if room.is_empty():
		_countdown_active = false
		_countdown_remaining = 0.0
		_match_transition_requested = false
		_prepared_hash = ""
		_prepared_manifest = null
		_course_loaded = false
		_manifest_publish_in_progress = false
		_manifest_transfer_parts.clear()
		_manifest_transfer_last_sent_msec.clear()
		_manifest_verified_peers.clear()
		return
	if str(room.get("phase", "OPEN")) == "COUNTDOWN":
		# Room state is the durable fallback if the one-shot WebRTC start packet
		# was lost while a peer was reconnecting or returning from a prior race.
		var countdown_started_at := float(room.get("countdown_start_at_unix", 0.0))
		var start_at := countdown_started_at + 5.0
		if countdown_started_at <= 0.0:
			start_at = Time.get_unix_time_from_system() + 5.0
		elif start_at <= Time.get_unix_time_from_system():
			start_at = Time.get_unix_time_from_system() + 0.25
		_on_race_countdown_received(start_at)
		return
	var remote_hash := str(room.get("manifest_hash", ""))
	if not remote_hash.is_empty() and remote_hash != _prepared_hash:
		_manifest_transfer_last_sent_msec.clear()
		_manifest_verified_peers.clear()
	if MultiplayerService.is_room_owner():
		# A rematch returns to a newly-instanced lobby while the autoload and its
		# WebRTC channels survive. Reuse the exact host manifest and explicitly
		# resend it: no new "connected" event is guaranteed in that case.
		if _prepared_manifest == null and not remote_hash.is_empty():
			_adopt_cached_host_manifest(room, remote_hash)
		if remote_hash.is_empty():
			if _prepared_manifest == null and not _manifest_publish_in_progress:
				_build_and_publish_manifest(room)
		elif _prepared_manifest == null or remote_hash != str(_prepared_manifest.get("manifest_hash")):
			# The room owner is the source of truth. If a poll returns a stale or
			# inconsistent hash, republish the already prepared manifest instead
			# of trying to verify it by independently generating the course again.
			if not _manifest_publish_in_progress:
				if _prepared_manifest == null:
					_build_and_publish_manifest(room)
				else:
					_publish_prepared_manifest(room)
		if not remote_hash.is_empty() and _prepared_manifest != null and remote_hash == _prepared_hash:
			_send_manifest_to_connected_peers()
		return
	if not remote_hash.is_empty() and remote_hash != _prepared_hash:
		_expect_host_manifest(room, remote_hash)

func _adopt_cached_host_manifest(room: Dictionary, expected_hash: String) -> void:
	var cached: Resource = MultiplayerService.course_manifest
	if cached == null or not cached.has_method("validate") or str(cached.get("manifest_hash")) != expected_hash:
		return
	if not str(cached.call("validate")).is_empty():
		return
	if int(cached.get("seed_value")) != int(room.get("seed", -1)) \
		or int(cached.get("course_length_px")) != int(room.get("course_length_px", -1)) \
		or int(cached.get("generator_version")) != int(room.get("generator_version", -1)):
		return
	_prepared_manifest = cached
	_prepared_hash = expected_hash
	_course_loaded = true
	MultiplayerService.acknowledge_manifest(expected_hash)

func _send_manifest_to_connected_peers() -> void:
	for peer_id in MultiplayerService.get_connected_peer_ids():
		_send_manifest_to_peer(peer_id)

func _build_and_publish_manifest(room: Dictionary) -> void:
	_manifest_build_started_msec = Time.get_ticks_msec()
	print("[MP_DIAG] ", JSON.stringify({"event": "manifest_build_start", "room_id": MultiplayerService.get_room_id(), "at_ms": _manifest_build_started_msec}))
	var builder := ManifestBuilderScript.new()
	var result: Dictionary = builder.build(int(room.get("seed", 0)), int(room.get("course_length_px", 0)), int(room.get("generator_version", 0)))
	if result.get("manifest") == null:
		_status.text = tr("Could not prepare the shared course: %s") % str(result.get("error", "unknown error"))
		return
	var manifest: Resource = result.manifest
	var manifest_bytes: PackedByteArray = manifest.to_canonical_json().to_utf8_buffer()
	print("[MP_DIAG] ", JSON.stringify({"event": "manifest_build_done", "room_id": MultiplayerService.get_room_id(), "elapsed_ms": Time.get_ticks_msec() - _manifest_build_started_msec, "bytes": manifest_bytes.size(), "hash": str(manifest.get("manifest_hash"))}))
	_prepared_manifest = manifest
	_prepared_hash = str(manifest.get("manifest_hash"))
	_course_loaded = false
	MultiplayerService.course_manifest = manifest
	_status.text = tr("Preparing shared course…")
	_publish_prepared_manifest(room)

func _publish_prepared_manifest(room: Dictionary) -> void:
	if _prepared_manifest == null or _manifest_publish_in_progress:
		return
	_prepared_hash = str(_prepared_manifest.get("manifest_hash"))
	_course_loaded = false
	_manifest_publish_in_progress = true
	MultiplayerService.publish_manifest(_prepared_hash, int(room.seed), int(room.course_length_px))


func _expect_host_manifest(room: Dictionary, expected_hash: String) -> void:
	# Guests validate the host's canonical manifest instead of requiring the
	# local generator to reproduce every float/random decision bit-for-bit.
	_prepared_hash = expected_hash
	_course_loaded = false
	_prepared_manifest = null
	_manifest_transfer_parts.clear()
	MultiplayerService.course_manifest = null
	_status.text = tr("Waiting for the host to send the shared course…")

func _on_request_finished(action: String, success: bool, message: String) -> void:
	if action in ["set_manifest", "ack_manifest"]:
		print("[MP_DIAG] ", JSON.stringify({"event": "manifest_rpc", "action": action, "success": success, "room_id": MultiplayerService.get_room_id(), "at_ms": Time.get_ticks_msec(), "message": message}))
	if action == "set_skin":
		_skin_request_pending = false
		if not success:
			_status.text = message
		_update_room(MultiplayerService.room_state)
		return
	_set_busy(false)
	if action == "list_public_rooms":
		_public_list_busy = false
	if not success:
		if action == "set_manifest":
			_manifest_publish_in_progress = false
		_status.text = message
		if action == "leave_room":
			_update_room(MultiplayerService.room_state)
		return
	if action == "leave_room":
		_update_room({})
	elif action == "create_room" or action == "join_room":
		_status.text = tr("Room created. Share the code with friends.")
	elif action == "set_manifest":
		_manifest_publish_in_progress = false
		_status.text = tr("Shared course prepared. Each player must verify it and ready up.")
		if _prepared_hash == str(MultiplayerService.room_state.get("manifest_hash", "")):
			MultiplayerService.acknowledge_manifest(_prepared_hash)
	elif action == "ack_manifest":
		_course_loaded = true
		_status.text = tr("Shared course verified. Mark yourself ready when you are connected.")
		_update_room(MultiplayerService.room_state)
	elif action == "start_countdown":
		_update_room(MultiplayerService.room_state)

func _on_signaling_state_changed(state: String, message: String) -> void:
	print("[MP_DIAG] ", JSON.stringify({"event": "signaling", "state": state, "room_id": MultiplayerService.get_room_id(), "at_ms": Time.get_ticks_msec(), "message": message}))
	if not message.is_empty():
		_status.text = message
	elif state == "connected":
		_status.text = tr("Private lobby signaling connected.")

func _on_peer_connection_state_changed(_peer_user_id: String, _state: String, message: String) -> void:
	if not message.is_empty():
		_status.text = message
	_update_room(MultiplayerService.room_state)
	if _state == "connected" and MultiplayerService.is_room_owner():
		_manifest_verified_peers.erase(_peer_user_id)
		_manifest_transfer_last_sent_msec.erase(_peer_user_id)
		_send_manifest_to_peer(_peer_user_id)

func _send_manifest_to_peer(peer_user_id: String) -> void:
	if _prepared_manifest == null or str(_prepared_manifest.get("manifest_hash")) != str(MultiplayerService.room_state.get("manifest_hash", "")):
		return
	if bool(_manifest_verified_peers.get(peer_user_id, false)):
		return
	var now_msec := Time.get_ticks_msec()
	if int(_manifest_transfer_last_sent_msec.get(peer_user_id, 0)) > 0 and now_msec - int(_manifest_transfer_last_sent_msec[peer_user_id]) < 1500:
		return
	var bytes: PackedByteArray = _prepared_manifest.to_canonical_json().to_utf8_buffer()
	if bytes.size() > 1048576:
		_status.text = tr("The shared course manifest is too large to send.")
		return
	var encoded := Marshalls.raw_to_base64(bytes)
	const CHUNK_CHARS := 8000
	var total := ceili(float(encoded.length()) / CHUNK_CHARS)
	if total <= 0 or total > 256:
		_status.text = tr("The shared course manifest exceeded the transfer limit.")
		return
	var transfer_id := str(_prepared_manifest.get("manifest_hash"))
	_manifest_transfer_started_msec[peer_user_id] = now_msec
	_manifest_transfer_last_sent_msec[peer_user_id] = now_msec
	print("[MP_DIAG] ", JSON.stringify({"event": "manifest_send_start", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "chunks": total, "bytes": bytes.size(), "at_ms": _manifest_transfer_started_msec[peer_user_id]}))
	for index in range(total):
		var piece := encoded.substr(index * CHUNK_CHARS, CHUNK_CHARS)
		var queued := MultiplayerService.queue_reliable_peer_message(peer_user_id, {
			"kind": "course_manifest_chunk",
			"transfer_id": transfer_id,
			"manifest_hash": transfer_id,
			"index": index,
			"total": total,
			"data": piece,
		})
		if not queued:
			_status.text = tr("Could not queue the shared course for transfer.")
			return
	_status.text = tr("Sending the shared course manifest to %s…") % peer_user_id

func _on_peer_data_received(peer_user_id: String, channel_name: String, payload: Dictionary) -> void:
	if channel_name == "control" and str(payload.get("kind", "")) == "diagnostic_session":
		if MultiplayerDiagnostics.accept_shared_session(payload, peer_user_id):
			_on_diagnostics_status_changed("Shared diagnostic ID: %s" % str(payload.get("session_id", "")))
		return
	if channel_name != "control":
		return
	if str(payload.get("kind", "")) == "course_manifest_chunk" and not MultiplayerService.is_room_owner():
		_receive_manifest_chunk(peer_user_id, payload)
	elif str(payload.get("kind", "")) == "manifest_verified" and MultiplayerService.is_room_owner():
		var expected_hash := str(MultiplayerService.room_state.get("manifest_hash", ""))
		if str(payload.get("manifest_hash", "")) == expected_hash:
			_manifest_verified_peers[peer_user_id] = true
			var sent_at := int(_manifest_transfer_started_msec.get(peer_user_id, 0))
			print("[MP_DIAG] ", JSON.stringify({"event": "manifest_peer_verified", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "elapsed_ms": maxi(0, Time.get_ticks_msec() - sent_at), "bytes": _prepared_manifest.to_canonical_json().to_utf8_buffer().size() if _prepared_manifest != null else 0}))
	elif str(payload.get("kind", "")) == "race_start" and not MultiplayerService.is_room_owner():
		if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
			var start_at := float(payload.get("start_at_unix", 0.0))
			if start_at <= 0.0:
				start_at = Time.get_unix_time_from_system() + float(payload.get("countdown_seconds", 5.0))
			_on_race_countdown_received(start_at)

func _on_race_countdown_received(start_at_unix: float) -> void:
	if _match_transition_requested:
		return
	if start_at_unix > 0.0:
		MultiplayerService.race_start_at_unix = start_at_unix
		_countdown_active = true
		_countdown_remaining = maxf(start_at_unix - Time.get_unix_time_from_system(), 0.0)
		_status.text = tr("Race starts in %d…") % ceili(_countdown_remaining)

func _receive_manifest_chunk(peer_user_id: String, chunk: Dictionary) -> void:
	var hash_value := str(chunk.get("manifest_hash", ""))
	var index := int(chunk.get("index", -1))
	var total := int(chunk.get("total", 0))
	var piece := str(chunk.get("data", ""))
	if peer_user_id != str(MultiplayerService.room_state.get("owner_user_id", "")) or hash_value != str(MultiplayerService.room_state.get("manifest_hash", "")):
		return
	if total <= 0 or total > 256 or index < 0 or index >= total or piece.is_empty() or piece.length() > 8000:
		return
	if _manifest_transfer_parts.is_empty():
		_manifest_transfer_parts = {"hash": hash_value, "total": total, "parts": {}, "started_at_msec": Time.get_ticks_msec()}
	if str(_manifest_transfer_parts.get("hash", "")) != hash_value or int(_manifest_transfer_parts.get("total", 0)) != total:
		_manifest_transfer_parts.clear()
		return
	var parts: Dictionary = _manifest_transfer_parts.get("parts", {})
	parts[index] = piece
	_manifest_transfer_parts.parts = parts
	if parts.size() != total:
		return
	var encoded := ""
	var transfer_started_msec := int(_manifest_transfer_parts.get("started_at_msec", Time.get_ticks_msec()))
	for part_index in range(total):
		if not parts.has(part_index):
			return
		encoded += str(parts[part_index])
	_manifest_transfer_parts.clear()
	var payload_bytes := Marshalls.base64_to_raw(encoded)
	if payload_bytes.size() > 1048576:
		return
	var json_text := payload_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return
	var manifest: Resource = ManifestScript.new()
	if not manifest.load_canonical_dictionary(parsed, hash_value, payload_bytes) or str(manifest.get("manifest_hash")) != _prepared_hash:
		_status.text = tr("The host's course manifest failed its integrity check; cannot ready up.")
		return
	var room := MultiplayerService.room_state
	if int(manifest.get("seed_value")) != int(room.get("seed", -1)) \
		or int(manifest.get("course_length_px")) != int(room.get("course_length_px", -1)) \
		or int(manifest.get("generator_version")) != int(room.get("generator_version", -1)):
		_status.text = tr("The host's course manifest does not match this room; cannot ready up.")
		return
	_prepared_manifest = manifest
	_prepared_hash = hash_value
	_course_loaded = true
	MultiplayerService.course_manifest = manifest
	print("[MP_DIAG] ", JSON.stringify({"event": "manifest_receive_validated", "room_id": MultiplayerService.get_room_id(), "peer_id": peer_user_id, "bytes": payload_bytes.size(), "transfer_validation_ms": Time.get_ticks_msec() - transfer_started_msec, "at_ms": Time.get_ticks_msec()}))
	MultiplayerService.queue_reliable_peer_message(peer_user_id, {"kind": "manifest_verified", "manifest_hash": hash_value})
	MultiplayerService.acknowledge_manifest(hash_value)
	_status.text = tr("Host course received and hash verified. Mark yourself ready.")

func _update_room(room: Dictionary) -> void:
	if not is_instance_valid(_players):
		return
	for child in _players.get_children():
		child.queue_free()
	var in_room := not room.is_empty()
	if in_room:
		_show_view("room")
	elif _active_view == "room":
		_show_view("home")
	_create_button.disabled = _busy or in_room
	_join_button.disabled = _busy or in_room
	_room_code.editable = not in_room and not _busy
	if is_instance_valid(_room_code_button):
		_room_code_button.disabled = in_room or _busy
	_ready_button.disabled = not in_room
	_start_button.disabled = true
	_leave_button.visible = in_room
	_diagnostics_opt_in_button.visible = in_room
	_diagnostics_opt_out_button.visible = in_room
	_diagnostics_session_button.visible = in_room and MultiplayerService.is_room_owner()
	if not in_room:
		if not _busy:
			_status.text = ""
		return
	_room_code.text = str(room.get("room_code", ""))
	_update_mobile_text_labels()
	var members: Variant = room.get("members", [])
	_room_summary.text = tr("Room %s · %d/%d players") % [str(room.get("room_code", "")), members.size() if members is Array else 0, int(room.get("max_players", 5))]
	var own_ready := false
	var everyone_ready := true
	var present_count := 0
	if members is Array:
		for member in members:
			if not member is Dictionary:
				continue
			var own := str(member.get("user_id", "")) == MultiplayerService.identity_user_id
			var present := bool(member.get("is_connected", true))
			var is_ready := bool(member.get("is_ready", false))
			if present:
				present_count += 1
				everyone_ready = everyone_ready and is_ready and str(member.get("loaded_manifest_hash", "")) == str(room.get("manifest_hash", ""))
			own_ready = is_ready if own else own_ready
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.custom_minimum_size.y = 26.0
			var ready_indicator := Control.new()
			ready_indicator.set_script(ReadyIndicatorScript)
			ready_indicator.set("is_ready", is_ready)
			ready_indicator.set("is_online", present)
			ready_indicator.custom_minimum_size = Vector2(22.0, 22.0)
			ready_indicator.tooltip_text = tr("Ready") if is_ready else (tr("Offline") if not present else tr("Not ready"))
			ready_indicator.accessibility_name = ready_indicator.tooltip_text
			ready_indicator.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(ready_indicator)
			var name_label := Label.new()
			name_label.text = "%s%s" % [str(member.get("display_name", "Runner")), tr(" (you)") if own else ""]
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			if not own and present:
				var link_label := Label.new()
				link_label.text = tr("P2P connected") if MultiplayerService.get_peer_link_state(str(member.get("user_id", ""))) == "connected" else tr("Connecting…")
				link_label.add_theme_font_size_override("font_size", 11)
				link_label.add_theme_color_override("font_color", Color("42d6c5") if link_label.text == tr("P2P connected") else Color("b8c7dc"))
				row.add_child(link_label)
			var skin_id := posmod(int(member.get("skin_id", 0)), SkinPalette.SKIN_COUNT)
			if own:
				var previous_skin := _button("<")
				previous_skin.custom_minimum_size = Vector2(36, 34)
				previous_skin.tooltip_text = tr("Previous skin")
				previous_skin.accessibility_name = previous_skin.tooltip_text
				previous_skin.disabled = _skin_request_pending or str(room.get("phase", "OPEN")) != "OPEN"
				previous_skin.pressed.connect(_change_skin.bind(-1))
				row.add_child(previous_skin)
			var miniature := TextureRect.new()
			miniature.custom_minimum_size = Vector2(32, 32)
			miniature.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			miniature.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			miniature.texture = RunnerFrames.get_frame_texture("run", 0)
			miniature.material = SkinPalette.make_material(skin_id)
			miniature.tooltip_text = tr("Runner appearance")
			row.add_child(miniature)
			if own:
				var next_skin := _button(">")
				next_skin.custom_minimum_size = Vector2(36, 34)
				next_skin.tooltip_text = tr("Next skin")
				next_skin.accessibility_name = next_skin.tooltip_text
				next_skin.disabled = _skin_request_pending or str(room.get("phase", "OPEN")) != "OPEN"
				next_skin.pressed.connect(_change_skin.bind(1))
				row.add_child(next_skin)
			if not present:
				var offline_label := Label.new()
				offline_label.text = tr("Offline")
				offline_label.add_theme_color_override("font_color", Color("8292aa"))
				row.add_child(offline_label)
			_players.add_child(row)
		_ready_button.text = tr("Not ready") if own_ready else tr("Ready")
	_ready_button.disabled = not in_room or str(room.get("phase", "OPEN")) != "OPEN" or not _course_loaded or str(room.get("manifest_hash", "")).is_empty() or _prepared_hash != str(room.get("manifest_hash", ""))
	_start_button.disabled = not MultiplayerService.can_start_race()
	if _countdown_active or str(room.get("phase", "OPEN")) == "COUNTDOWN":
		_ready_button.disabled = true
		_start_button.disabled = true
		_status.text = tr("Race starting…")
		return
	var room_manifest_hash := str(room.get("manifest_hash", ""))
	if room_manifest_hash.is_empty():
		_status.text = tr("Preparing the shared course…")
	elif not _course_loaded or _prepared_hash != room_manifest_hash:
		_status.text = tr("Connecting to the host to verify the course…")
	elif MultiplayerService.is_room_owner():
		_status.text = tr("Share the room code with friends.")
	else:
		_status.text = tr("Waiting for the host to start.")
	if everyone_ready and present_count > 0:
		if MultiplayerService.is_room_owner() and not room_manifest_hash.is_empty() and _course_loaded and not MultiplayerService.can_start_race():
			_status.text = tr("Everyone is ready — waiting for a direct connection.")
		else:
			_status.text = tr("Everyone is ready.")

func _on_diagnostics_status_changed(message: String) -> void:
	if is_instance_valid(_diagnostics_status):
		_diagnostics_status.text = message
	if is_instance_valid(_latest_report_status):
		_latest_report_status.text = message

func _on_diagnostic_layout_selected(index: int) -> void:
	var layouts := ["unknown", "split_host", "three_windows", "separate_devices", "other"]
	var current_instances := MultiplayerDiagnostics.get_instances_on_device()
	MultiplayerDiagnostics.set_test_context(str(layouts[index]), current_instances)

func _on_diagnostic_instances_selected(index: int) -> void:
	var count_id := _diagnostics_instances_option.get_item_id(index)
	var layout_id := _diagnostics_layout_option.get_selected_id()
	var layouts := ["unknown", "split_host", "three_windows", "separate_devices", "other"]
	MultiplayerDiagnostics.set_test_context(str(layouts[layout_id]), count_id if count_id > 0 else null)

func _update_diagnostic_option_selections() -> void:
	if not is_instance_valid(_diagnostics_layout_option):
		return
	var layouts := ["unknown", "split_host", "three_windows", "separate_devices", "other"]
	var layout_index := layouts.find(MultiplayerDiagnostics.get_test_layout())
	_diagnostics_layout_option.select(maxi(layout_index, 0))
	var instances := MultiplayerDiagnostics.get_instances_on_device()
	var instance_index := 0 if instances == null else int(instances)
	_diagnostics_instances_option.select(clampi(instance_index, 0, 5))
	if is_instance_valid(_latest_report_status):
		_latest_report_status.text = message
	_update_latest_report_actions()

func _update_latest_report_actions() -> void:
	if not is_instance_valid(_latest_report_status):
		return
	var latest := MultiplayerDiagnostics.get_latest_report()
	var available := not latest.is_empty()
	_latest_report_status.visible = available
	_latest_report_copy_button.visible = available
	_latest_report_save_button.visible = available
	_diagnostics_session_id_edit.visible = available
	_fetch_diagnostics_button.visible = available
	_list_diagnostics_sessions_button.visible = available
	_download_fetched_diagnostics_button.visible = available and not MultiplayerDiagnostics.get_fetched_session_text().is_empty()
	if available:
		var session_id := str(latest.get("diagnostic_session_id", ""))
		if _diagnostics_session_id_edit.text.is_empty():
			_diagnostics_session_id_edit.text = session_id
		_latest_report_status.text = tr("Latest report · debug ID: %s · %s") % [session_id if not session_id.is_empty() else tr("local only"), MultiplayerDiagnostics.get_status()]

func _copy_latest_multiplayer_report() -> void:
	DisplayServer.clipboard_set(MultiplayerDiagnostics.get_export_text(true))
	_latest_report_status.text = tr("Compact report copied. Debug ID: %s") % str(MultiplayerDiagnostics.get_latest_report().get("diagnostic_session_id", tr("local only")))

func _save_latest_multiplayer_report() -> void:
	var saved_path := MultiplayerDiagnostics.save_latest_report()
	if OS.has_feature("web"):
		var base64 := Marshalls.raw_to_base64(MultiplayerDiagnostics.get_export_text(false).to_utf8_buffer())
		JavaScriptBridge.eval("(()=>{const a=document.createElement('a');a.href='data:application/json;base64,%s';a.download='gravity-run-multiplayer-report.json';a.click()})()" % base64, true)
		_latest_report_status.text = tr("Download requested. Debug ID: %s") % str(MultiplayerDiagnostics.get_latest_report().get("diagnostic_session_id", ""))
	else:
		_latest_report_status.text = tr("Full report saved: %s") % saved_path

func _save_fetched_diagnostics() -> void:
	var json_text := MultiplayerDiagnostics.get_fetched_session_text()
	if json_text.is_empty():
		return
	if OS.has_feature("web"):
		var base64 := Marshalls.raw_to_base64(json_text.to_utf8_buffer())
		JavaScriptBridge.eval("(()=>{const a=document.createElement('a');a.href='data:application/json;base64,%s';a.download='gravity-run-diagnostic-session.json';a.click()})()" % base64, true)
		_latest_report_status.text = tr("Fetched reports download requested.")
	else:
		var saved_path := MultiplayerDiagnostics.save_fetched_session()
		_latest_report_status.text = tr("All fetched client reports saved: %s") % saved_path

func _list_diagnostic_sessions() -> void:
	_latest_report_status.text = tr("Loading recent diagnostic sessions…")
	MultiplayerDiagnostics.request_sessions()

func _show_view(view_name: String) -> void:
	_active_view = view_name
	if is_instance_valid(_home_view):
		_home_view.visible = view_name == "home"
		_create_view.visible = view_name == "create"
		_join_view.visible = view_name == "join"
		_room_view.visible = view_name == "room"
	var needs_name := view_name in ["create", "join"]
	if is_instance_valid(_name_edit):
		_name_edit.visible = needs_name and not _mobile_text_entry
	if is_instance_valid(_name_button):
		_name_button.visible = needs_name
	if is_instance_valid(_room_code):
		_room_code.visible = view_name == "join" and not _mobile_text_entry
	if is_instance_valid(_room_code_button):
		_room_code_button.visible = view_name == "join"
	if is_instance_valid(_public_toggle):
		_public_toggle.disabled = _busy

func _set_busy(value: bool) -> void:
	_busy = value
	if is_instance_valid(_create_button):
		_create_button.disabled = value or MultiplayerService.has_room()
		_join_button.disabled = value or MultiplayerService.has_room()
		if is_instance_valid(_room_code_button):
			_room_code_button.disabled = value or MultiplayerService.has_room()

func _open_mobile_text_entry(field: String, value: String) -> void:
	var label := tr("Display name") if field == "name" else tr("Room code")
	MobileTextEntry.open(field, value, label, "text", 16 if field == "name" else 8, "text", "off", "words" if field == "name" else "characters")

func _on_mobile_text_submitted(field: String, value: String) -> void:
	match field:
		"name":
			_name_edit.text = value.substr(0, 16)
		"room_code":
			_room_code.text = value.substr(0, 8)
	_update_mobile_text_labels()

func _on_player_account_profile_changed(nickname: String, has_profile: bool) -> void:
	if not has_profile or not is_instance_valid(_name_edit) or not _name_edit.text.strip_edges().is_empty():
		return
	_name_edit.text = nickname.left(16)
	_update_mobile_text_labels()

func _update_mobile_text_labels() -> void:
	if is_instance_valid(_name_button):
		_name_button.text = _name_edit.text if not _name_edit.text.is_empty() else tr("Display name")
	if is_instance_valid(_room_code_button):
		_room_code_button.text = _room_code.text if not _room_code.text.is_empty() else tr("Room code")

func _exit_tree() -> void:
	if _mobile_text_entry:
		MobileTextEntry.cancel()

func _button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 40.0
	_lobby_buttons.append(button)
	return button

func _on_viewport_size_changed() -> void:
	var viewport := get_viewport().get_visible_rect().size
	if is_instance_valid(_panel):
		var panel_width := minf(620.0, maxf(viewport.x - 32.0, 280.0))
		var panel_height := minf(600.0, maxf(viewport.y - 28.0, 200.0))
		_panel.offset_left = -panel_width * 0.5
		_panel.offset_right = panel_width * 0.5
		_panel.offset_top = -panel_height * 0.5
		_panel.offset_bottom = panel_height * 0.5
		var compact := viewport.y < 620.0
		_layout.add_theme_constant_override("separation", 6 if compact else 10)
		_title.add_theme_font_size_override("font_size", 20 if compact else 24)
		for button in _lobby_buttons:
			button.custom_minimum_size.y = 32.0 if compact else 40.0
	_ensure_focused_input_visible()

func _ensure_focused_input_visible() -> void:
	call_deferred("_scroll_to_focused_input")

func _scroll_to_focused_input() -> void:
	if not is_instance_valid(_scroll):
		return
	if is_instance_valid(_name_edit) and _name_edit.has_focus():
		_scroll.ensure_control_visible(_name_edit)
	elif is_instance_valid(_room_code) and _room_code.has_focus():
		_scroll.ensure_control_visible(_room_code)

func _restore_scroll_if_unfocused() -> void:
	call_deferred("_reset_scroll_if_unfocused")

func _reset_scroll_if_unfocused() -> void:
	if is_instance_valid(_scroll) \
		and (not is_instance_valid(_name_edit) or not _name_edit.has_focus()) \
		and (not is_instance_valid(_room_code) or not _room_code.has_focus()):
		_scroll.scroll_vertical = 0

func _release_lobby_input_focus() -> void:
	if is_instance_valid(_name_edit):
		_name_edit.release_focus()
	if is_instance_valid(_room_code):
		_room_code.release_focus()
	_reset_scroll_if_unfocused()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _inner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b2c")
	style.border_color = Color("364861")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
