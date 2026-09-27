extends Control

const ManifestBuilderScript := preload("res://systems/course_manifest_builder.gd")
const ManifestScript := preload("res://systems/multiplayer_course_manifest.gd")

signal back_requested
signal match_start_requested

var _status: Label
var _room_code: LineEdit
var _name_edit: LineEdit
var _players: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _create_button: Button
var _join_button: Button
var _prepared_hash := ""
var _prepared_manifest: Resource
var _course_loaded := false
var _manifest_transfer_parts: Dictionary = {}
var _countdown_remaining := 0.0
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	MultiplayerService.room_changed.connect(_on_room_changed)
	MultiplayerService.request_finished.connect(_on_request_finished)
	MultiplayerService.signaling_state_changed.connect(_on_signaling_state_changed)
	MultiplayerService.peer_connection_state_changed.connect(_on_peer_connection_state_changed)
	MultiplayerService.peer_data_received.connect(_on_peer_data_received)
	MultiplayerService.race_countdown_received.connect(_on_race_countdown_received)
	if MultiplayerService.has_room():
		_on_room_changed(MultiplayerService.room_state)

func _process(_delta: float) -> void:
	if _countdown_remaining > 0.0:
		_countdown_remaining = maxf(_countdown_remaining - _delta, 0.0)
		if _countdown_remaining <= 0.0:
			match_start_requested.emit()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var viewport := get_viewport_rect().size
	var panel_width := minf(620.0, viewport.x - 32.0)
	var panel_height := minf(600.0, viewport.y - 28.0)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	scroll.add_child(layout)
	var title := Label.new()
	title.text = tr("MULTIPLAYER LOBBY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	_status = Label.new()
	_status.text = tr("Create a private room or join with a code.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_status)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Display name")
	_name_edit.max_length = 16
	layout.add_child(_name_edit)
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	layout.add_child(create_row)
	_create_button = _button(tr("Create room"))
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button.pressed.connect(_create_room)
	create_row.add_child(_create_button)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = tr("Room code")
	_room_code.max_length = 8
	_room_code.text_submitted.connect(func(_value: String) -> void: _join_room())
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_room_code)
	_join_button = _button(tr("Join"))
	_join_button.pressed.connect(_join_room)
	create_row.add_child(_join_button)
	var separator := HSeparator.new()
	layout.add_child(separator)
	var code_label := Label.new()
	code_label.text = tr("Room code")
	layout.add_child(code_label)
	var members_box := PanelContainer.new()
	members_box.add_theme_stylebox_override("panel", _inner_style())
	layout.add_child(members_box)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 6)
	members_box.add_child(_players)
	_ready_button = _button(tr("Ready"))
	_ready_button.pressed.connect(_toggle_ready)
	_ready_button.disabled = true
	layout.add_child(_ready_button)
	_start_button = _button(tr("Start race"))
	_start_button.disabled = true
	_start_button.pressed.connect(_request_start)
	layout.add_child(_start_button)
	_leave_button = _button(tr("Leave room"))
	_leave_button.pressed.connect(MultiplayerService.leave_room)
	_leave_button.visible = false
	layout.add_child(_leave_button)
	var note := Label.new()
	note.text = tr("All players need the same verified course and a direct connection to the host before the race can start.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(note)
	var back := _button(tr("Back"))
	back.pressed.connect(back_requested.emit)
	layout.add_child(back)
	_update_room(MultiplayerService.room_state)

func _create_room() -> void:
	_set_busy(true)
	MultiplayerService.create_room(_name_edit.text)

func _join_room() -> void:
	if _room_code.text.strip_edges().length() != 8:
		_status.text = tr("Enter the 8-character room code.")
		return
	_set_busy(true)
	MultiplayerService.join_room(_room_code.text, _name_edit.text)

func _toggle_ready() -> void:
	var already_ready := false
	for member in MultiplayerService.get_members():
		if member is Dictionary and str(member.get("user_id", "")) == MultiplayerService.identity_user_id:
			already_ready = bool(member.get("is_ready", false))
			break
	MultiplayerService.set_ready(not already_ready)
	if not already_ready:
		MultiplayerService.begin_peer_connection()

func _request_start() -> void:
	if not MultiplayerService.can_start_race():
		_status.text = tr("Every player must be ready, have the same verified course, and be directly connected to the host.")
		return
	MultiplayerService.request_start()

func _on_room_changed(room: Dictionary) -> void:
	_update_room(room)
	if room.is_empty():
		_prepared_hash = ""
		_prepared_manifest = null
		_course_loaded = false
		_manifest_transfer_parts.clear()
		return
	var remote_hash := str(room.get("manifest_hash", ""))
	if remote_hash.is_empty() and MultiplayerService.is_room_owner():
		_build_and_publish_manifest(room)
	elif not remote_hash.is_empty() and remote_hash != _prepared_hash:
		_build_and_ack_manifest(room, remote_hash)

func _build_and_publish_manifest(room: Dictionary) -> void:
	var builder := ManifestBuilderScript.new()
	var result: Dictionary = builder.build(int(room.get("seed", 0)), int(room.get("course_length_px", 0)), int(room.get("generator_version", 0)))
	if result.get("manifest") == null:
		_status.text = tr("Could not prepare the shared course: %s") % str(result.get("error", "unknown error"))
		return
	var manifest: Resource = result.manifest
	_prepared_manifest = manifest
	_prepared_hash = str(manifest.get("manifest_hash"))
	_course_loaded = false
	MultiplayerService.course_manifest = manifest
	_status.text = tr("Preparing shared course…")
	MultiplayerService.publish_manifest(_prepared_hash, int(room.seed), int(room.course_length_px))

func _build_and_ack_manifest(room: Dictionary, expected_hash: String) -> void:
	var builder := ManifestBuilderScript.new()
	var result: Dictionary = builder.build(int(room.get("seed", 0)), int(room.get("course_length_px", 0)), int(room.get("generator_version", 0)))
	if result.get("manifest") == null:
		_status.text = tr("Could not verify the shared course: %s") % str(result.get("error", "unknown error"))
		return
	var manifest: Resource = result.manifest
	var actual_hash := str(manifest.get("manifest_hash"))
	if actual_hash != expected_hash:
		_prepared_hash = ""
		_status.text = tr("Course verification failed: this device generated a different course.")
		return
	_prepared_hash = expected_hash
	_prepared_manifest = manifest
	_course_loaded = false
	MultiplayerService.course_manifest = manifest
	_status.text = tr("Local course generated. Connecting to the host to receive and verify its manifest…")

func _on_request_finished(action: String, success: bool, message: String) -> void:
	_set_busy(false)
	if not success:
		_status.text = message
		return
	if action == "leave_room":
		_update_room({})
	elif action == "create_room" or action == "join_room":
		_status.text = tr("Room created. Share the code with friends.")
	elif action == "set_manifest":
		_status.text = tr("Shared course prepared. Each player must verify it and ready up.")
		if _prepared_hash == str(MultiplayerService.room_state.get("manifest_hash", "")):
			MultiplayerService.acknowledge_manifest(_prepared_hash)
	elif action == "ack_manifest":
		_course_loaded = true
		_status.text = tr("Shared course verified. Mark yourself ready when you are connected.")
		_update_room(MultiplayerService.room_state)
	elif action == "start_countdown":
		_status.text = tr("Race starts in 5 seconds!")

func _on_signaling_state_changed(state: String, message: String) -> void:
	if not message.is_empty():
		_status.text = message
	elif state == "connected":
		_status.text = tr("Private lobby signaling connected.")

func _on_peer_connection_state_changed(_peer_user_id: String, _state: String, message: String) -> void:
	if not message.is_empty():
		_status.text = message
	if _state == "connected" and MultiplayerService.is_room_owner():
		_send_manifest_to_peer(_peer_user_id)

func _send_manifest_to_peer(peer_user_id: String) -> void:
	if _prepared_manifest == null or str(_prepared_manifest.get("manifest_hash")) != str(MultiplayerService.room_state.get("manifest_hash", "")):
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
	if channel_name != "control":
		return
	if str(payload.get("kind", "")) == "course_manifest_chunk" and not MultiplayerService.is_room_owner():
		_receive_manifest_chunk(peer_user_id, payload)
	elif str(payload.get("kind", "")) == "race_start" and not MultiplayerService.is_room_owner():
		if str(payload.get("room_id", "")) == MultiplayerService.get_room_id():
			_on_race_countdown_received(float(payload.get("countdown_seconds", 5.0)))

func _on_race_countdown_received(countdown_seconds: float) -> void:
	if countdown_seconds > 0.0 and _countdown_remaining <= 0.0:
		_countdown_remaining = clampf(countdown_seconds, 0.5, 10.0)
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
		_manifest_transfer_parts = {"hash": hash_value, "total": total, "parts": {}}
	if str(_manifest_transfer_parts.get("hash", "")) != hash_value or int(_manifest_transfer_parts.get("total", 0)) != total:
		_manifest_transfer_parts.clear()
		return
	var parts: Dictionary = _manifest_transfer_parts.get("parts", {})
	parts[index] = piece
	_manifest_transfer_parts.parts = parts
	if parts.size() != total:
		return
	var encoded := ""
	for part_index in range(total):
		if not parts.has(part_index):
			return
		encoded += str(parts[part_index])
	_manifest_transfer_parts.clear()
	var json_text := Marshalls.base64_to_raw(encoded).get_string_from_utf8()
	if json_text.to_utf8_buffer().size() > 1048576:
		return
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return
	var manifest: Resource = ManifestScript.new()
	if not manifest.load_canonical_dictionary(parsed) or str(manifest.get("manifest_hash")) != hash_value or str(manifest.get("manifest_hash")) != _prepared_hash:
		_status.text = tr("The host's course manifest did not match this device; cannot ready up.")
		return
	_prepared_manifest = manifest
	_prepared_hash = hash_value
	_course_loaded = true
	MultiplayerService.course_manifest = manifest
	MultiplayerService.acknowledge_manifest(hash_value)
	_status.text = tr("Host course received and hash verified. Mark yourself ready.")

func _update_room(room: Dictionary) -> void:
	if not is_instance_valid(_players):
		return
	for child in _players.get_children():
		child.queue_free()
	var in_room := not room.is_empty()
	_create_button.disabled = _busy or in_room
	_join_button.disabled = _busy or in_room
	_room_code.editable = not in_room and not _busy
	_ready_button.disabled = not in_room
	_start_button.disabled = true
	_leave_button.visible = in_room
	if not in_room:
		_status.text = tr("Create a private room or join with a code.") if not _busy else _status.text
		return
	_room_code.text = str(room.get("room_code", ""))
	var members: Variant = room.get("members", [])
	var own_ready := false
	var everyone_ready := true
	if members is Array:
		for member in members:
			if not member is Dictionary:
				continue
			var own := str(member.get("user_id", "")) == MultiplayerService.identity_user_id
			var is_ready := bool(member.get("is_ready", false))
			own_ready = is_ready if own else own_ready
			everyone_ready = everyone_ready and is_ready and str(member.get("loaded_manifest_hash", "")) == str(room.get("manifest_hash", ""))
			var label := Label.new()
			label.text = "%s%s%s" % [str(member.get("display_name", "Runner")), tr(" (you)") if own else "", tr(" · ready") if is_ready else tr(" · waiting")]
			_players.add_child(label)
		_ready_button.text = tr("Not ready") if own_ready else tr("Ready")
	_ready_button.disabled = not in_room or not _course_loaded or str(room.get("manifest_hash", "")).is_empty() or _prepared_hash != str(room.get("manifest_hash", ""))
	_start_button.disabled = not MultiplayerService.can_start_race()
	if MultiplayerService.is_room_owner():
		_status.text = tr("Room code: %s · %d/4 players") % [str(room.get("room_code", "")), members.size() if members is Array else 0]
	else:
		_status.text = tr("Joined room %s · preparing shared course") % str(room.get("room_code", ""))
	if everyone_ready and members is Array and members.size() >= 2:
		_status.text += "\n" + tr("All players are ready. Match networking is still under construction.")

func _set_busy(value: bool) -> void:
	_busy = value
	if is_instance_valid(_create_button):
		_create_button.disabled = value or MultiplayerService.has_room()
		_join_button.disabled = value or MultiplayerService.has_room()

func _button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 40.0
	return button

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
