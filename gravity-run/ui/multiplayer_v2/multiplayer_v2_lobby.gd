extends Control

const ReadyIndicatorScript := preload("res://ui/ready_indicator.gd")
const RunnerFrames := preload("res://assets/character/run_frames.tres")
const SkinPalette := preload("res://player/skin_palette.gd")
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const RoomSettings := preload("res://systems/multiplayer_v2/v2_room_settings.gd")

signal back_requested
signal match_start_requested

var _status: Label
var _display_name: LineEdit
var _name_button: Button
var _room_code: LineEdit
var _room_code_button: Button
var _seed_edit: LineEdit
var _seed_button: Button
var _public_toggle: CheckButton
var _scroll: ScrollContainer
var _panel: PanelContainer
var _layout: VBoxContainer
var _title: Label
var _home_view: VBoxContainer
var _create_view: VBoxContainer
var _join_view: VBoxContainer
var _room_view: VBoxContainer
var _public_rooms: VBoxContainer
var _room_summary: Label
var _players: VBoxContainer
var _equipment_box: VBoxContainer
var _equipment_toggle: CheckButton
var _equipment_state_label: Label
var _equipment_request_pending := false
var _ready_button: Button
var _start_button: Button
var _diagnostics_button: Button
var _reconnect_button: Button
var _create_button: Button
var _join_button: Button
var _room: Dictionary = {}
var _active_view := "home"
var _mobile_text_entry := false
var _busy := false
var _skin_request_pending := false
var _preferred_skin_room_key := ""
var _lobby_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_text_entry = MobileTextEntry.is_mobile_web
	MobileTextEntry.entry_submitted.connect(_on_mobile_text_submitted)
	PlayerAccountProfile.profile_changed.connect(_on_profile_changed)
	_build_ui()
	_on_profile_changed(PlayerAccountProfile.nickname, PlayerAccountProfile.has_profile)
	MultiplayerV2Service.room_changed.connect(_on_room_changed)
	MultiplayerV2Service.public_rooms_loaded.connect(_on_rooms_loaded)
	MultiplayerV2Service.lobby_request_finished.connect(_on_request_finished)
	MultiplayerV2Service.signaling_state_changed.connect(_on_signaling_state)
	MultiplayerV2Service.transport_state_changed.connect(_on_transport_state)
	MultiplayerV2Service.start_failure_changed.connect(_on_start_failure_changed)
	MultiplayerV2Service.start_attempt_status_changed.connect(_on_start_attempt_status_changed)
	MultiplayerV2Service.round_prepare_requested.connect(_on_round_prepare_requested)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	if MultiplayerV2Service.has_room():
		_on_room_changed(MultiplayerV2Service.room_state)
	else:
		MultiplayerV2Service.list_public_rooms()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
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
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layout.add_child(_status)
	_diagnostics_button = _button(tr("Save diagnostics"))
	_diagnostics_button.pressed.connect(_download_diagnostics)
	_layout.add_child(_diagnostics_button)
	_display_name = LineEdit.new()
	_display_name.placeholder_text = tr("Display name")
	_display_name.max_length = 16
	_display_name.focus_entered.connect(_ensure_focused_input_visible)
	_display_name.focus_exited.connect(_restore_scroll_if_unfocused)
	_layout.add_child(_display_name)
	if _mobile_text_entry:
		_display_name.visible = false
		_name_button = _button(tr("Display name"))
		_name_button.pressed.connect(func() -> void: _open_mobile_text_entry("name"))
		_layout.add_child(_name_button)

	_home_view = _new_view()
	_layout.add_child(_home_view)
	var create_mode := _button(tr("Create room"))
	create_mode.pressed.connect(func() -> void: _show_view("create"))
	_home_view.add_child(create_mode)
	var join_mode := _button(tr("Join a room"))
	join_mode.pressed.connect(func() -> void:
		_show_view("join")
		MultiplayerV2Service.list_public_rooms()
	)
	_home_view.add_child(join_mode)
	var home_back := _button(tr("Back"))
	home_back.pressed.connect(back_requested.emit)
	_home_view.add_child(home_back)

	_create_view = _new_view()
	_layout.add_child(_create_view)
	var create_heading := _heading(tr("Create a room"))
	_create_view.add_child(create_heading)
	_public_toggle = CheckButton.new()
	_public_toggle.text = tr("Public — show in open rooms")
	_public_toggle.button_pressed = true
	_create_view.add_child(_public_toggle)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("Course seed (blank for random)")
	_seed_edit.tooltip_text = tr("Leave blank for a new course each round. Enter a seed to replay the same course.")
	_seed_edit.max_length = 10
	_create_view.add_child(_seed_edit)
	if _mobile_text_entry:
		_seed_edit.visible = false
		_seed_button = _button(tr("Course seed (blank for random)"))
		_seed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seed_button.pressed.connect(func() -> void: _open_mobile_text_entry("course_seed"))
		_create_view.add_child(_seed_button)
	_create_button = _button(tr("Create room"))
	_create_button.pressed.connect(_create_room)
	_create_view.add_child(_create_button)
	var create_back := _button(tr("Back"))
	create_back.pressed.connect(func() -> void: _show_view("home"))
	_create_view.add_child(create_back)

	_join_view = _new_view()
	_layout.add_child(_join_view)
	_join_view.add_child(_heading(tr("Join a room")))
	var code_row := HBoxContainer.new()
	_join_view.add_child(code_row)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = tr("Room code")
	_room_code.max_length = 8
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code.text_submitted.connect(func(_value: String) -> void: _join_room())
	_room_code.focus_entered.connect(_ensure_focused_input_visible)
	_room_code.focus_exited.connect(_restore_scroll_if_unfocused)
	code_row.add_child(_room_code)
	if _mobile_text_entry:
		_room_code.visible = false
		_room_code_button = _button(tr("Room code"))
		_room_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_room_code_button.pressed.connect(func() -> void: _open_mobile_text_entry("room_code"))
		code_row.add_child(_room_code_button)
	_join_button = _button(tr("Join"))
	_join_button.pressed.connect(_join_room)
	code_row.add_child(_join_button)
	var public_header := HBoxContainer.new()
	_join_view.add_child(public_header)
	var public_title := Label.new()
	public_title.text = tr("Open rooms")
	public_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_header.add_child(public_title)
	var refresh_button := _button(tr("Refresh"))
	refresh_button.pressed.connect(MultiplayerV2Service.list_public_rooms)
	public_header.add_child(refresh_button)
	var public_scroll := ScrollContainer.new()
	public_scroll.custom_minimum_size.y = 110.0
	public_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_join_view.add_child(public_scroll)
	_public_rooms = VBoxContainer.new()
	_public_rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_scroll.add_child(_public_rooms)
	var join_back := _button(tr("Back"))
	join_back.pressed.connect(func() -> void: _show_view("home"))
	_join_view.add_child(join_back)

	_room_view = _new_view()
	_layout.add_child(_room_view)
	_room_summary = _heading("")
	_room_view.add_child(_room_summary)
	var members_panel := PanelContainer.new()
	members_panel.add_theme_stylebox_override("panel", _inner_style())
	_room_view.add_child(members_panel)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 6)
	members_panel.add_child(_players)
	_equipment_box = VBoxContainer.new()
	_equipment_box.add_theme_constant_override("separation", 2)
	_room_view.add_child(_equipment_box)
	_equipment_toggle = CheckButton.new()
	_equipment_toggle.text = tr("Equipment items")
	_equipment_toggle.tooltip_text = tr("Host setting. On: every player's equipped effect items apply in the race. Off: everyone races without items.")
	_equipment_toggle.toggled.connect(_on_equipment_toggled)
	_equipment_box.add_child(_equipment_toggle)
	_equipment_state_label = Label.new()
	_equipment_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipment_state_label.add_theme_font_size_override("font_size", 13)
	_equipment_box.add_child(_equipment_state_label)
	_ready_button = _button(tr("Ready"))
	_ready_button.pressed.connect(_toggle_ready)
	_room_view.add_child(_ready_button)
	_start_button = _button(tr("Start race"))
	_start_button.pressed.connect(MultiplayerV2Service.request_start)
	_room_view.add_child(_start_button)
	var leave_button := _button(tr("Leave room"))
	leave_button.pressed.connect(MultiplayerV2Service.leave_room)
	_room_view.add_child(leave_button)
	_reconnect_button = _button(tr("Reconnect to host"))
	_reconnect_button.pressed.connect(MultiplayerV2Service.begin_peer_connection)
	_room_view.add_child(_reconnect_button)
	var build_label := Label.new()
	build_label.text = tr("Build %s") % str(ProjectSettings.get_setting("application/config/version", "unknown"))
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_label.add_theme_font_size_override("font_size", 10)
	build_label.add_theme_color_override("font_color", Color("8798af"))
	_layout.add_child(build_label)
	_show_view("home")

func _new_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 8)
	return view

func _heading(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _create_room() -> void:
	var seed_value := -1
	if not _seed_edit.text.strip_edges().is_empty():
		if not _seed_edit.text.is_valid_int() or _seed_edit.text.to_int() < 1 or _seed_edit.text.to_int() > 2_147_483_647:
			_status.text = tr("Course seed must be between 1 and 2147483647.")
			return
		seed_value = _seed_edit.text.to_int()
	MultiplayerV2Service.create_room(_name_value(), _public_toggle.button_pressed, seed_value)
	_status.text = tr("Creating room…")

func _join_room() -> void:
	if _room_code.text.strip_edges().is_empty():
		_status.text = tr("Enter a room code first.")
		return
	MultiplayerV2Service.join_room(_room_code.text, _name_value())
	_status.text = tr("Joining room…")

func _on_equipment_toggled(enabled: bool) -> void:
	_equipment_request_pending = MultiplayerV2Service.set_equipment_enabled(enabled)
	_refresh_equipment_setting(_room)

## Host: a switch. Everyone else: the same state as read-only text. Rooms from a
## server without the field hide the setting (it reads as off).
func _refresh_equipment_setting(room: Dictionary) -> void:
	if not is_instance_valid(_equipment_box):
		return
	# Hidden until the server sends the field (migration 202610080004), so the
	# lobby looks exactly as before on a server without the setting.
	_equipment_box.visible = room.has(RoomSettings.KEY_EQUIPMENT_ENABLED)
	var enabled := RoomSettings.equipment_enabled(room)
	var is_host := MultiplayerV2Service.is_room_owner()
	_equipment_toggle.visible = is_host
	_equipment_toggle.set_pressed_no_signal(enabled)
	_equipment_toggle.disabled = _equipment_request_pending or str(room.get("phase", "OPEN")) != "OPEN"
	if enabled:
		_equipment_state_label.text = tr("Equipment is ON: everyone's equipped items apply in the race.")
		_equipment_state_label.add_theme_color_override("font_color", Color("42d6c5"))
	else:
		_equipment_state_label.text = tr("Equipment is OFF: everyone races without items.")
		_equipment_state_label.add_theme_color_override("font_color", Color("b8c7dc"))

func _toggle_ready() -> void:
	var cycle := int(_room.get("lobby_cycle", 0))
	var content_revision := int(_room.get("content_revision", 0))
	for member_value in _room.get("members", []):
		if member_value is Dictionary and str(member_value.get("user_id", "")) == MultiplayerV2Service.identity_user_id:
			var loadout_hash := str(member_value.get("loadout_hash", ""))
			var current_loadout_hash := MultiplayerV2Service.local_loadout_hash()
			var ready_here := bool(member_value.get("is_ready", false)) and int(member_value.get("ready_cycle", 0)) == cycle and int(member_value.get("ready_content_revision", 0)) == content_revision and not loadout_hash.is_empty() and loadout_hash == current_loadout_hash and str(member_value.get("ready_loadout_hash", "")) == loadout_hash
			MultiplayerV2Service.set_ready(not ready_here)
			return

func _suggest_preferred_skin(room: Dictionary, current_skin: int) -> void:
	# Apply the hub's saved skin once when we first see ourselves in a room. A
	# later manual change in the lobby wins, and nothing is sent outside OPEN.
	var room_key := "%s:%s" % [str(room.get("room_id", "")), str(room.get("room_code", ""))]
	if room_key == _preferred_skin_room_key:
		return
	_preferred_skin_room_key = room_key
	var preferred := posmod(int(PlayerProfile.preferred_skin_id), SkinPalette.SKIN_COUNT)
	if preferred == current_skin or _skin_request_pending or str(room.get("phase", "OPEN")) != "OPEN":
		return
	_skin_request_pending = true
	MultiplayerV2Service.set_skin_id(preferred)

func _change_skin(direction: int) -> void:
	if _skin_request_pending:
		return
	for member_value in _room.get("members", []):
		if member_value is Dictionary and str(member_value.get("user_id", "")) == MultiplayerV2Service.identity_user_id:
			_skin_request_pending = true
			var next_skin := posmod(int(member_value.get("skin_id", 0)) + direction, SkinPalette.SKIN_COUNT)
			PlayerProfile.set_preferred_skin_id(next_skin)
			MultiplayerV2Service.set_skin_id(next_skin)
			_refresh_controls()
			return

func _on_room_changed(room: Dictionary) -> void:
	_room = room.duplicate(true)
	if _room.is_empty():
		_show_view("home")
		_clear_members()
		return
	_show_view("room")
	_room_summary.text = tr("Room %s · %d/%d players") % [str(room.get("room_code", "")), room.get("members", []).size(), int(room.get("max_players", 5))]
	_clear_members()
	var local_ready := false
	var local_manifest_ready := false
	var current_cycle := int(room.get("lobby_cycle", 0))
	var local_loadout_hash := MultiplayerV2Service.local_loadout_hash()
	var local_manifest_hash := str(room.get("manifest_hash", ""))
	var connected_peers := MultiplayerV2Service.connected_peer_ids()
	for member_value in room.get("members", []):
		if not member_value is Dictionary:
			continue
		var member: Dictionary = member_value
		var is_local := str(member.get("user_id", "")) == MultiplayerV2Service.identity_user_id
		var member_loadout_hash := str(member.get("loadout_hash", ""))
		var is_ready_this_cycle := bool(member.get("is_ready", false)) and int(member.get("ready_cycle", 0)) == current_cycle and int(member.get("ready_content_revision", 0)) == int(room.get("content_revision", 0)) and not member_loadout_hash.is_empty() and str(member.get("ready_loadout_hash", "")) == member_loadout_hash
		var has_returned := int(member.get("returned_for_cycle", 0)) >= current_cycle
		var ready_text := tr("Ready") if is_ready_this_cycle else tr("Not ready")
		if not has_returned:
			ready_text = tr("Has not returned to this lobby cycle")
		var is_online := bool(member.get("is_connected", true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size.y = 32.0
		var ready_indicator := Control.new()
		ready_indicator.set_script(ReadyIndicatorScript)
		ready_indicator.set("is_ready", is_ready_this_cycle and has_returned)
		ready_indicator.set("is_online", is_online)
		ready_indicator.custom_minimum_size = Vector2(22.0, 22.0)
		ready_indicator.tooltip_text = ready_text if is_online else tr("Offline")
		ready_indicator.accessibility_name = ready_indicator.tooltip_text
		row.add_child(ready_indicator)
		var name_label := Label.new()
		name_label.text = "%s%s" % [str(member.get("display_name", "Runner")), tr(" (you)") if is_local else ""]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if not is_local and is_online:
			var peer_id := int(member.get("player_slot", 1))
			var link_label := Label.new()
			var through_host := not MultiplayerV2Service.is_room_owner() and peer_id != 1
			var link_ready := 1 in connected_peers if through_host else peer_id in connected_peers
			link_label.text = tr("Connected through host") if through_host and link_ready else (tr("P2P connected") if link_ready else tr("Connecting…"))
			link_label.add_theme_font_size_override("font_size", 11)
			link_label.add_theme_color_override("font_color", Color("42d6c5") if link_ready else Color("b8c7dc"))
			row.add_child(link_label)
		var skin_id := posmod(int(member.get("skin_id", 0)), SkinPalette.SKIN_COUNT)
		if is_local:
			_suggest_preferred_skin(room, skin_id)
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
		row.add_child(miniature)
		if is_local:
			var next_skin := _button(">")
			next_skin.custom_minimum_size = Vector2(36, 34)
			next_skin.tooltip_text = tr("Next skin")
			next_skin.accessibility_name = next_skin.tooltip_text
			next_skin.disabled = _skin_request_pending or str(room.get("phase", "OPEN")) != "OPEN"
			next_skin.pressed.connect(_change_skin.bind(1))
			row.add_child(next_skin)
		_players.add_child(row)
		if is_local:
			local_ready = is_ready_this_cycle and has_returned and member_loadout_hash == local_loadout_hash
			local_manifest_ready = str(member.get("loaded_manifest_hash", "")) == local_manifest_hash and not local_manifest_hash.is_empty()
		elif MultiplayerV2Service.is_room_owner() and int(member.get("player_slot", 1)) > 1:
			var kick_button := _button(tr("Kick"))
			kick_button.custom_minimum_size = Vector2(54, 34)
			kick_button.tooltip_text = tr("Remove this player from the open lobby")
			kick_button.pressed.connect(MultiplayerV2Service.kick_member.bind(str(member.get("user_id", "")), int(member.get("player_slot", -1))))
			row.add_child(kick_button)
	_refresh_equipment_setting(room)
	_ready_button.text = tr("Not ready") if local_ready else tr("Ready")
	_ready_button.disabled = str(room.get("phase", "")) != "OPEN" or not local_manifest_ready or not MultiplayerV2Service.local_peer_mapping_valid() or not _local_member_returned(room)
	_start_button.visible = MultiplayerV2Service.is_room_owner()
	var blockers := MultiplayerV2Service.get_start_blockers()
	_start_button.disabled = not blockers.is_empty()
	_start_button.tooltip_text = _start_blocker_message(blockers)
	_reconnect_button.visible = not MultiplayerV2Service.is_room_owner() and not _has_host_connection()
	if not MultiplayerV2Service.local_peer_mapping_valid():
		_status.text = tr("The assigned player slot does not match this connection. Reconnect before readying.")
	elif str(room.get("phase", "")) == "FINISHED":
		_status.text = tr("Waiting for the host to open the next lobby cycle.")
	elif str(room.get("phase", "")) == "PREPARING_COURSE":
		_status.text = tr("The race is preparing. Waiting for every player to accept the same round.")
	elif str(room.get("phase", "")) == "RUNNING":
		_status.text = tr("The race is already in progress. Rejoin the room to continue.")
	elif str(room.get("manifest_hash", "")).is_empty():
		_status.text = tr("Preparing the shared course…")
	else:
		var waiting_for_return := _waiting_member_name(room, "returned_for_cycle", current_cycle)
		var waiting_for_ready := _waiting_member_name(room, "ready_cycle", current_cycle)
		if not waiting_for_return.is_empty():
			_status.text = tr("Waiting for %s to return from results.") % waiting_for_return
		elif not _has_host_connection() and not MultiplayerV2Service.is_room_owner():
			_status.text = tr("Waiting for a direct connection to the host…")
		elif not local_manifest_ready:
			_status.text = tr("Checking the shared course…")
		elif not local_ready:
			_status.text = tr("Mark yourself ready when you are ready.")
		elif not waiting_for_ready.is_empty():
			_status.text = tr("Waiting for %s to get ready.") % waiting_for_ready
		else:
			_status.text = tr("Room ready. Waiting for players.")
	if not MultiplayerV2Service.last_start_failure.is_empty():
		_status.text = tr("Last start attempt failed: %s") % MultiplayerV2Service.last_start_failure

func _local_member_returned(room: Dictionary) -> bool:
	for member_value in room.get("members", []):
		if member_value is Dictionary and str(member_value.get("user_id", "")) == MultiplayerV2Service.identity_user_id:
			return int(member_value.get("returned_for_cycle", 0)) >= int(room.get("lobby_cycle", 0))
	return false

func _waiting_member_name(room: Dictionary, field: String, required_value: int) -> String:
	for member_value in room.get("members", []):
		if not member_value is Dictionary:
			continue
		var member: Dictionary = member_value
		if str(member.get("user_id", "")) == MultiplayerV2Service.identity_user_id:
			continue
		var current_value := int(member.get(field, 0))
		if field == "ready_cycle":
			var loadout_hash := str(member.get("loadout_hash", ""))
			if current_value == required_value and int(member.get("ready_content_revision", 0)) == int(room.get("content_revision", 0)) and not loadout_hash.is_empty() and str(member.get("ready_loadout_hash", "")) == loadout_hash:
				continue
		elif current_value >= required_value:
			continue
		return str(member.get("display_name", "Runner"))
	return ""

func _clear_members() -> void:
	if not is_instance_valid(_players):
		return
	for child in _players.get_children():
		child.queue_free()

func _on_rooms_loaded(rooms: Array, message: String) -> void:
	for child in _public_rooms.get_children():
		child.queue_free()
	if not message.is_empty():
		_status.text = message
		return
	for room_value in rooms:
		if not room_value is Dictionary:
			continue
		var room: Dictionary = room_value
		var button := _button("%s  ·  %d/%d" % [str(room.get("host_name", "Host")), int(room.get("player_count", 0)), int(room.get("max_players", 5))])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			_room_code.text = str(room.get("room_code", ""))
			_join_room()
		)
		_public_rooms.add_child(button)
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = tr("No open rooms are available.")
		_public_rooms.add_child(empty)

func _on_request_finished(action: String, success: bool, message: String) -> void:
	if action == "set_skin":
		_skin_request_pending = false
	if action == "set_equipment":
		_equipment_request_pending = false
		_refresh_equipment_setting(_room)
	if not success:
		_status.text = message
	elif action == "connect":
		_status.text = message
	elif action in ["create_room", "join_room", "set_ready", "set_skin"]:
		_status.text = ""
	_refresh_controls()

func _on_start_failure_changed(message: String) -> void:
	if not message.is_empty():
		_status.text = tr("Last start attempt failed: %s") % message
	elif not _room.is_empty():
		_on_room_changed(_room)

func _on_start_attempt_status_changed(snapshot: Dictionary) -> void:
	if not MultiplayerV2Service.last_start_failure.is_empty():
		_status.text = tr("Last start attempt failed: %s") % MultiplayerV2Service.last_start_failure
		return
	if str(_room.get("phase", "")) == "PREPARING_COURSE":
		var stage := tr(str(snapshot.get("stage", "waiting")))
		var waiting := PackedStringArray()
		for peer_value in (snapshot.get("peers", {}) as Dictionary).values():
			if peer_value is Dictionary and str(peer_value.get("prepared", "")) == "waiting":
				waiting.append("slot %d" % int(peer_value.get("player_slot", -1)))
		var detail := tr("Waiting at: %s") % stage
		if not waiting.is_empty():
			detail += " · " + tr("Waiting for") + " " + ", ".join(waiting)
		_status.text = tr("The race is preparing. Waiting for every player to accept the same round.") + "\n" + detail

func _refresh_controls() -> void:
	var in_room := not _room.is_empty()
	if is_instance_valid(_create_button):
		_create_button.disabled = _busy or in_room
	if is_instance_valid(_join_button):
		_join_button.disabled = _busy or in_room
	if is_instance_valid(_ready_button):
		_ready_button.disabled = not in_room or str(_room.get("phase", "")) != "OPEN" or not MultiplayerV2Service.local_peer_mapping_valid() or not _local_member_returned(_room) or MultiplayerV2Service.current_manifest == null or str(MultiplayerV2Service.current_manifest.manifest_hash) != str(_room.get("manifest_hash", ""))
	if is_instance_valid(_start_button):
		_start_button.visible = in_room and MultiplayerV2Service.is_room_owner()
		_start_button.disabled = not in_room or not MultiplayerV2Service.get_start_blockers().is_empty()
	if is_instance_valid(_reconnect_button):
		_reconnect_button.visible = in_room and not MultiplayerV2Service.is_room_owner() and not _has_host_connection()

func _on_signaling_state(connected: bool, message: String) -> void:
	if connected:
		_status.text = tr("Connected to room signaling.")
	elif not message.is_empty():
		_status.text = message

func _on_transport_state(state: String, message: String) -> void:
	if state == "connected":
		_status.text = tr("Direct player connection ready.")
	elif state == "failed":
		_status.text = message
	_refresh_controls()
	if not _room.is_empty():
		_on_room_changed(_room)

func _has_host_connection() -> bool:
	if MultiplayerV2Service.is_room_owner():
		return true
	return 1 in MultiplayerV2Service.connected_peer_ids()

func _start_blocker_message(blockers: PackedStringArray) -> String:
	if blockers.is_empty():
		return tr("Start the race when everyone is ready.")
	for blocker in blockers:
		if str(blocker).begins_with("member_not_returned"):
			return tr("Every player must return from the previous result screen before the next race.")
		if str(blocker) == "local_peer_id_mismatch":
			return tr("The assigned player slot does not match this connection. Reconnect before starting.")
		if str(blocker).begins_with("transport_missing"):
			return tr("Waiting for all players to connect directly.")
		if str(blocker).begins_with("member_not_ready"):
			return tr("Every player must be ready before the host starts.")
		if str(blocker).begins_with("manifest"):
			return tr("Waiting for every player to load the course.")
	return tr("The room is still preparing the race.")

func _on_round_prepare_requested(_descriptor: Dictionary) -> void:
	match_start_requested.emit()

func _download_diagnostics() -> void:
	var report := MultiplayerV2Service.diagnostics.export_report()
	report["current_state"] = MultiplayerV2Service.current_diagnostic_state()
	_status.text = DiagnosticsExport.save_report(report, DiagnosticsExport.make_filename(report, "lobby"))

func _name_value() -> String:
	var value := _display_name.text.strip_edges()
	return value.substr(0, 16) if not value.is_empty() else "Runner"

func _show_view(view_name: String) -> void:
	_active_view = view_name
	_home_view.visible = view_name == "home"
	_create_view.visible = view_name == "create"
	_join_view.visible = view_name == "join"
	_room_view.visible = view_name == "room"
	var name_needed := view_name in ["create", "join"]
	_display_name.visible = name_needed and not _mobile_text_entry
	if is_instance_valid(_name_button):
		_name_button.visible = name_needed
	_room_code.visible = view_name == "join" and not _mobile_text_entry
	if is_instance_valid(_room_code_button):
		_room_code_button.visible = view_name == "join"
	_seed_edit.visible = view_name == "create" and not _mobile_text_entry
	if is_instance_valid(_seed_button):
		_seed_button.visible = view_name == "create"
		_seed_button.text = _seed_edit.text if not _seed_edit.text.is_empty() else tr("Course seed (blank for random)")

func _open_mobile_text_entry(field: String) -> void:
	match field:
		"name":
			MobileTextEntry.open(field, _display_name.text, tr("Display name"), "text", 16, "text", "off", "words")
		"room_code":
			MobileTextEntry.open(field, _room_code.text, tr("Room code"), "text", 8, "text", "off", "characters")
		"course_seed":
			MobileTextEntry.open(field, _seed_edit.text, tr("Course seed"), "text", 10, "numeric", "off", "characters")

func _on_mobile_text_submitted(field: String, value: String) -> void:
	if field == "name":
		_display_name.text = value.substr(0, 16)
		if is_instance_valid(_name_button):
			_name_button.text = _display_name.text
	elif field == "room_code":
		_room_code.text = value.substr(0, 8)
		if is_instance_valid(_room_code_button):
			_room_code_button.text = _room_code.text
	elif field == "course_seed":
		_seed_edit.text = value.substr(0, 10)
		if is_instance_valid(_seed_button):
			_seed_button.text = _seed_edit.text if not _seed_edit.text.is_empty() else tr("Course seed (blank for random)")

func _on_profile_changed(nickname: String, has_profile: bool) -> void:
	if has_profile and _display_name.text.is_empty():
		_display_name.text = nickname.left(16)
	if is_instance_valid(_name_button):
		_name_button.text = _display_name.text if not _display_name.text.is_empty() else tr("Display name")

func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 40.0
	_lobby_buttons.append(button)
	return button

func _on_viewport_size_changed() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport := get_viewport().get_visible_rect().size
	var width := minf(620.0, maxf(viewport.x - 32.0, 280.0))
	var height := minf(600.0, maxf(viewport.y - 28.0, 200.0))
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5
	var compact := viewport.y < 620.0
	_layout.add_theme_constant_override("separation", 6 if compact else 10)
	_title.add_theme_font_size_override("font_size", 20 if compact else 24)
	for button in _lobby_buttons:
		button.custom_minimum_size.y = 32.0 if compact else 40.0

func _ensure_focused_input_visible() -> void:
	call_deferred("_scroll_to_focused_input")

func _scroll_to_focused_input() -> void:
	if is_instance_valid(_scroll):
		if _display_name.has_focus():
			_scroll.ensure_control_visible(_display_name)
		elif _room_code.has_focus():
			_scroll.ensure_control_visible(_room_code)

func _restore_scroll_if_unfocused() -> void:
	call_deferred("_reset_scroll_if_unfocused")

func _reset_scroll_if_unfocused() -> void:
	if is_instance_valid(_scroll) and not _display_name.has_focus() and not _room_code.has_focus():
		_scroll.scroll_vertical = 0

func _exit_tree() -> void:
	if _mobile_text_entry:
		MobileTextEntry.cancel()

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
