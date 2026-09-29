extends Control

signal back_requested
signal match_start_requested

var _status: Label
var _room_code: LineEdit
var _display_name: LineEdit
var _seed_edit: LineEdit
var _public_toggle: CheckButton
var _room_list: VBoxContainer
var _room_panel: PanelContainer
var _ready_button: Button
var _start_button: Button
var _members_label: RichTextLabel
var _room: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	MultiplayerV2Service.room_changed.connect(_on_room_changed)
	MultiplayerV2Service.public_rooms_loaded.connect(_on_rooms_loaded)
	MultiplayerV2Service.lobby_request_finished.connect(_on_request_finished)
	MultiplayerV2Service.signaling_state_changed.connect(_on_signaling_state)
	MultiplayerV2Service.round_prepare_requested.connect(_on_round_prepare_requested)
	if MultiplayerV2Service.has_room():
		_on_room_changed(MultiplayerV2Service.room_state)
	else:
		MultiplayerV2Service.list_public_rooms()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-300.0, -244.0)
	panel.size = Vector2(600.0, 488.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	scroll.add_child(layout)
	var title := Label.new()
	title.text = tr("Multiplayer V2 (test)")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	var description := Label.new()
	description.text = tr("Client-owned movement · Godot WebRTC RPC · V2 rooms only")
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(description)
	_display_name = LineEdit.new()
	_display_name.placeholder_text = tr("Display name")
	_display_name.text = str(PlayerAccountProfile.nickname) if not str(PlayerAccountProfile.nickname).is_empty() else "Runner"
	layout.add_child(_display_name)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("Course seed (blank for random)")
	_seed_edit.max_length = 10
	layout.add_child(_seed_edit)
	_public_toggle = CheckButton.new()
	_public_toggle.text = tr("List room publicly")
	_public_toggle.button_pressed = true
	layout.add_child(_public_toggle)
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	var create_button := Button.new()
	create_button.text = tr("Create V2 room")
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(_create_room)
	actions.add_child(create_button)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = tr("Room code")
	_room_code.max_length = 8
	actions.add_child(_room_code)
	var join_button := Button.new()
	join_button.text = tr("Join")
	join_button.pressed.connect(_join_room)
	actions.add_child(join_button)
	var list_header := HBoxContainer.new()
	var list_title := Label.new()
	list_title.text = tr("Public V2 rooms")
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(list_title)
	var refresh_button := Button.new()
	refresh_button.text = tr("Refresh")
	refresh_button.pressed.connect(MultiplayerV2Service.list_public_rooms)
	list_header.add_child(refresh_button)
	layout.add_child(list_header)
	_room_list = VBoxContainer.new()
	_room_list.add_theme_constant_override("separation", 3)
	layout.add_child(_room_list)
	_room_panel = PanelContainer.new()
	_room_panel.visible = false
	_room_panel.add_theme_stylebox_override("panel", _inner_panel_style())
	layout.add_child(_room_panel)
	var room_layout := VBoxContainer.new()
	_room_panel.add_child(room_layout)
	_members_label = RichTextLabel.new()
	_members_label.fit_content = true
	_members_label.scroll_active = false
	room_layout.add_child(_members_label)
	var room_actions := HBoxContainer.new()
	room_layout.add_child(room_actions)
	_ready_button = Button.new()
	_ready_button.text = tr("Ready")
	_ready_button.pressed.connect(_toggle_ready)
	room_actions.add_child(_ready_button)
	_start_button = Button.new()
	_start_button.text = tr("Start V2 round")
	_start_button.pressed.connect(MultiplayerV2Service.request_start)
	room_actions.add_child(_start_button)
	var leave_button := Button.new()
	leave_button.text = tr("Leave V2 room")
	leave_button.pressed.connect(MultiplayerV2Service.leave_room)
	room_actions.add_child(leave_button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 42.0
	layout.add_child(_status)
	var back_button := Button.new()
	back_button.text = tr("Back")
	back_button.pressed.connect(_back)
	layout.add_child(back_button)

func _create_room() -> void:
	var seed_value := -1
	if not _seed_edit.text.strip_edges().is_empty():
		if not _seed_edit.text.is_valid_int() or _seed_edit.text.to_int() < 1 or _seed_edit.text.to_int() > 2_147_483_647:
			_status.text = tr("Course seed must be between 1 and 2147483647.")
			return
		seed_value = _seed_edit.text.to_int()
	MultiplayerV2Service.create_room(_name_value(), _public_toggle.button_pressed, seed_value)
	_status.text = tr("Creating an isolated V2 room…")

func _join_room() -> void:
	if _room_code.text.strip_edges().is_empty():
		_status.text = tr("Enter a V2 room code first.")
		return
	MultiplayerV2Service.join_room(_room_code.text, _name_value())
	_status.text = tr("Joining the V2 room…")

func _toggle_ready() -> void:
	for member in _room.get("members", []):
		if str(member.get("user_id", "")) == MultiplayerV2Service.identity_user_id:
			MultiplayerV2Service.set_ready(not bool(member.get("is_ready", false)))
			return

func _on_room_changed(room: Dictionary) -> void:
	_room = room.duplicate(true)
	_room_panel.visible = not _room.is_empty()
	if _room.is_empty():
		return
	var lines := PackedStringArray(["[b]V2 room %s[/b] · %s · generation %d" % [str(room.get("room_code", "")), str(room.get("phase", "OPEN")), int(room.get("lobby_generation", 0))]])
	for member in room.get("members", []):
		var state := tr("ready") if bool(member.get("is_ready", false)) else tr("not ready")
		var link := tr("online") if bool(member.get("is_connected", false)) else tr("offline")
		lines.append("• %s — %s, %s" % [str(member.get("display_name", "Runner")), state, link])
	_members_label.clear()
	_members_label.append_text("\n".join(lines))
	_ready_button.disabled = str(room.get("phase", "")) != "OPEN"
	_start_button.visible = MultiplayerV2Service.is_room_owner()
	var blockers := MultiplayerV2Service.get_start_blockers()
	_start_button.disabled = not blockers.is_empty()
	_start_button.tooltip_text = ", ".join(blockers)
	if str(room.get("manifest_hash", "")).is_empty():
		_status.text = tr("Building and verifying the shared V2 course…")
	else:
		_status.text = tr("V2 room is isolated from Multiplayer V1.")

func _on_rooms_loaded(rooms: Array, message: String) -> void:
	for child in _room_list.get_children():
		child.queue_free()
	if not message.is_empty():
		_status.text = message
		return
	for room in rooms:
		if not room is Dictionary:
			continue
		var button := Button.new()
		button.text = "%s · %d/%d" % [str(room.get("host_name", "Host")), int(room.get("player_count", 0)), int(room.get("max_players", 5))]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _room_code.text = str(room.get("room_code", "")); _join_room())
		_room_list.add_child(button)
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = tr("No public V2 rooms are available.")
		_room_list.add_child(empty)

func _on_request_finished(action: String, success: bool, message: String) -> void:
	if not success:
		_status.text = message
	elif action == "connect":
		_status.text = message
	elif action in ["create_room", "join_room", "set_ready", "refresh_room"]:
		_status.text = tr("V2 room ready. Confirm your transport link and course before starting.")

func _on_signaling_state(connected: bool, message: String) -> void:
	if connected:
		_status.text = tr("V2 signaling connected. Negotiating the host peer link…")
	elif not message.is_empty():
		_status.text = message

func _on_round_prepare_requested(_descriptor: Dictionary) -> void:
	match_start_requested.emit()

func _name_value() -> String:
	var value := _display_name.text.strip_edges()
	return value.substr(0, 16) if not value.is_empty() else "Runner"

func _back() -> void:
	if MultiplayerV2Service.has_room():
		MultiplayerV2Service.leave_room()
	back_requested.emit()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _inner_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101a2a")
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
