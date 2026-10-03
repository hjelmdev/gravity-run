extends VBoxContainer
class_name MultiplayerAchievementResultSection

const GameIcon := preload("res://ui/game_icon.gd")

var _round_id := ""
var _player_slot := -1
var _result_visible := false
var _unlock_entries: Dictionary = {}

func _ready() -> void:
	visible = false
	AccountProgress.multiplayer_run_unlocks_received.connect(_on_unlocks_received)

func _exit_tree() -> void:
	if AccountProgress.multiplayer_run_unlocks_received.is_connected(_on_unlocks_received):
		AccountProgress.multiplayer_run_unlocks_received.disconnect(_on_unlocks_received)

func begin_round(round_id: String, player_slot: int) -> void:
	_round_id = round_id
	_player_slot = player_slot
	_result_visible = false
	_unlock_entries.clear()
	_clear_rows()
	visible = false

func show_terminal_result(round_id: String, player_slot: int) -> void:
	if round_id != _round_id or player_slot != _player_slot:
		return
	_result_visible = true
	_refresh()

func unlock_count() -> int:
	return _unlock_entries.size()

func _on_unlocks_received(round_id: String, player_slot: int, entries: Array) -> void:
	if round_id != _round_id or player_slot != _player_slot:
		return
	for entry in entries:
		if not entry is Dictionary:
			continue
		var key := "%s:%d" % [str(entry.get("achievement_id", "")), int(entry.get("tier", -1))]
		if key.begins_with(":") or _unlock_entries.has(key):
			continue
		_unlock_entries[key] = entry.duplicate(true)
	if _result_visible:
		_refresh()

func _refresh() -> void:
	_clear_rows()
	visible = _result_visible and not _unlock_entries.is_empty()
	if not visible:
		return
	add_theme_constant_override("separation", 6)
	var heading := Label.new()
	heading.text = tr("Achievements unlocked")
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("42d6c5"))
	add_child(heading)
	for key in _unlock_entries:
		var entry: Dictionary = _unlock_entries[key]
		var definition := _find_definition(str(entry.get("achievement_id", "")), int(entry.get("tier", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var icon := Control.new()
		icon.set_script(GameIcon)
		icon.set("icon_family", "achievement_status")
		icon.set("unlocked", true)
		icon.custom_minimum_size = Vector2(24.0, 24.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var title := Label.new()
		title.text = tr(str(definition.get("title", entry.get("achievement_id", "Achievement"))))
		row.add_child(title)

func _find_definition(achievement_id: String, tier: int) -> Dictionary:
	for definition in AchievementService.get_definitions():
		if str(definition.get("id", "")) == achievement_id and int(definition.get("tier", -1)) == tier:
			return definition
	return {}

func _clear_rows() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
