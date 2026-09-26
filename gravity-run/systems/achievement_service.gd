extends Node

signal state_changed
signal run_unlocks_changed(entries: Array)

var definitions: Array[Dictionary] = []
var unlocked: Dictionary = {}
var metrics := {"total_distance_m": 0, "best_run_distance_m": 0, "total_coins_earned": 0, "total_gravity_flips": 0}
var hazard_stats: Dictionary = {}
var recent_run_unlocks: Array[Dictionary] = []
var _user_id := ""
var _catalog_loaded := false
var _presented_this_run: Dictionary = {}
var _toast_layer: CanvasLayer
var _toast_card: PanelContainer
var _toast_title: Label
var _toast_description: Label
var _toast_badge: Label
var _toast_heading: Label
var _toast_queue: Array[Dictionary] = []
var _toast_timer: Timer

func _ready() -> void:
	AccountProgress.achievements_loaded.connect(_on_achievements_loaded)
	AccountProgress.achievements_unlocked.connect(_on_achievements_unlocked)
	AccountProgress.progress_changed.connect(_on_progress_changed)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	_build_toast()
	if AuthService.is_authenticated:
		_user_id = AuthService.user_id

func get_definitions() -> Array:
	return definitions.duplicate(true)

func is_unlocked(achievement_id: String, tier: int) -> bool:
	return unlocked.has(_key(achievement_id, tier))

func get_progress(definition: Dictionary) -> Dictionary:
	var metric := str(definition.get("metric", ""))
	var current := _metric_value(metric, str(definition.get("scope_key", "")))
	var target := int(definition.get("target", 1))
	return {"current": current, "target": target, "ratio": clampf(float(current) / maxf(float(target), 1.0), 0.0, 1.0)}

func get_recent_run_unlocks() -> Array[Dictionary]:
	return recent_run_unlocks.duplicate(true)

func begin_run() -> void:
	recent_run_unlocks.clear()
	_presented_this_run.clear()
	_run_distance_m = 0
	_run_coins = 0
	_run_flips = 0
	_run_hazards.clear()

func update_run_distance(distance_pixels: float) -> void:
	_run_distance_m = int(distance_pixels / 10.0)
	_check_live_unlocks()

var _run_distance_m := 0
var _run_coins := 0
var _run_flips := 0
var _run_hazards: Dictionary = {}

func update_run_metrics(coins: int, gravity_flips: int, hazards_encountered: Array) -> void:
	_run_coins = coins
	_run_flips = gravity_flips
	for hazard_id in hazards_encountered:
		_run_hazards[str(hazard_id)] = true
	_check_live_unlocks()

func _check_live_unlocks() -> void:
	if not AuthService.is_authenticated or not _catalog_loaded:
		return
	for definition in definitions:
		var key := _key(str(definition.id), int(definition.tier))
		if unlocked.has(key) or _presented_this_run.has(key):
			continue
		if _metric_value(str(definition.metric), str(definition.get("scope_key", "")), true) >= int(definition.target):
			_presented_this_run[key] = true
			_toast_queue.append({"definition": definition, "provisional": true})
			if not _toast_card.visible:
				_show_next_toast()

func _metric_value(metric: String, scope_key: String, include_run: bool = false) -> int:
	var value := int(metrics.get(metric, 0))
	match metric:
		"total_distance_m":
			if include_run: value += _run_distance_m
		"best_run_distance_m":
			if include_run: value = maxi(value, _run_distance_m)
		"total_coins_earned":
			if include_run: value += _run_coins
		"total_gravity_flips":
			if include_run: value += _run_flips
		"distinct_hazards_seen":
			var ids := hazard_stats.keys()
			if include_run:
				for hazard_id in _run_hazards.keys():
					if hazard_id not in ids: ids.append(hazard_id)
			value = ids.size()
		"hazard_encounters":
			value = int(hazard_stats.get(scope_key, 0))
			if include_run and _run_hazards.has(scope_key): value += 1
	return value

func _on_auth_state_changed(authenticated: bool, _email: String) -> void:
	var next_user := AuthService.user_id if authenticated else ""
	if next_user == _user_id:
		return
	_user_id = next_user
	unlocked.clear()
	_catalog_loaded = false
	metrics = {"total_distance_m": 0, "best_run_distance_m": 0, "total_coins_earned": 0, "total_gravity_flips": 0}
	hazard_stats.clear()
	definitions.clear()
	recent_run_unlocks.clear()
	_toast_queue.clear()
	_hide_toast()
	state_changed.emit()

func _on_achievements_loaded(data: Dictionary) -> void:
	if not AuthService.is_authenticated:
		return
	_user_id = AuthService.user_id
	metrics["total_distance_m"] = int(data.get("total_distance_m", 0))
	metrics["best_run_distance_m"] = int(data.get("best_run_distance_m", 0))
	metrics["total_coins_earned"] = int(data.get("total_coins_earned", metrics.get("total_coins_earned", 0)))
	metrics["total_gravity_flips"] = int(data.get("total_gravity_flips", metrics.get("total_gravity_flips", 0)))
	var raw_hazard_stats: Variant = data.get("hazard_stats", hazard_stats)
	if raw_hazard_stats is Dictionary:
		hazard_stats = raw_hazard_stats.duplicate(true)
	var raw_catalog: Variant = data.get("catalog", null)
	if raw_catalog is Array:
		definitions.clear()
		for raw_definition in raw_catalog:
			if raw_definition is Dictionary:
				definitions.append({
					"id": str(raw_definition.get("achievement_id", "")),
					"tier": int(raw_definition.get("tier", 0)),
					"metric": str(raw_definition.get("metric", "")),
					"target": int(raw_definition.get("threshold", 1)),
					"scope_key": str(raw_definition.get("scope_key", "")),
					"title": str(raw_definition.get("title_key", "Achievement")),
					"description": str(raw_definition.get("description_key", "")),
					"visibility": str(raw_definition.get("visibility", "visible")),
				})
	var raw_unlocked: Variant = data.get("unlocked", null)
	if raw_unlocked is Array:
		unlocked.clear()
		for entry in raw_unlocked:
			if entry is Dictionary:
				unlocked[_key(str(entry.get("achievement_id", "")), int(entry.get("tier", 0)))] = entry
	if data.has("catalog"):
		_catalog_loaded = not definitions.is_empty()
	state_changed.emit()
	_check_live_unlocks()

func _on_progress_changed(_wallet: int, total_distance: int, best_distance: int) -> void:
	if not AuthService.is_authenticated:
		return
	metrics["total_distance_m"] = total_distance
	metrics["best_run_distance_m"] = best_distance
	state_changed.emit()

func _on_achievements_unlocked(entries: Array) -> void:
	if not AuthService.is_authenticated:
		return
	recent_run_unlocks.clear()
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue
		var key := _key(str(raw_entry.get("achievement_id", "")), int(raw_entry.get("tier", 0)))
		var definition := _find_definition(str(raw_entry.get("achievement_id", "")), int(raw_entry.get("tier", 0)))
		if definition.is_empty():
			continue
		unlocked[key] = raw_entry
		recent_run_unlocks.append(definition)
		if not _presented_this_run.has(key):
			_toast_queue.append({"definition": definition, "provisional": false})
	if not entries.is_empty():
		run_unlocks_changed.emit(recent_run_unlocks.duplicate(true))
		state_changed.emit()
		_show_next_toast()

func _find_definition(achievement_id: String, tier: int) -> Dictionary:
	for definition in definitions:
		if str(definition.id) == achievement_id and int(definition.tier) == tier:
			return definition
	return {}

func _key(achievement_id: String, tier: int) -> String:
	return "%s:%d" % [achievement_id, tier]

func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 20
	add_child(_toast_layer)
	_toast_card = PanelContainer.new()
	_toast_card.anchor_left = 1.0
	_toast_card.anchor_top = 1.0
	_toast_card.anchor_right = 1.0
	_toast_card.anchor_bottom = 1.0
	_toast_card.offset_left = -310.0
	_toast_card.offset_top = -102.0
	_toast_card.offset_right = -16.0
	_toast_card.offset_bottom = -16.0
	_toast_card.add_theme_stylebox_override("panel", _toast_style())
	_toast_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast_card.visible = false
	_toast_layer.add_child(_toast_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_toast_card.add_child(row)
	_toast_badge = Label.new()
	_toast_badge.text = "★"
	_toast_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_badge.custom_minimum_size = Vector2(52, 52)
	_toast_badge.add_theme_font_size_override("font_size", 26)
	_toast_badge.add_theme_color_override("font_color", Color("f5d45e"))
	row.add_child(_toast_badge)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)
	_toast_heading = Label.new()
	_toast_heading.text = tr("ACHIEVEMENT UNLOCKED")
	_toast_heading.add_theme_font_size_override("font_size", 11)
	_toast_heading.add_theme_color_override("font_color", Color("42d6c5"))
	text_column.add_child(_toast_heading)
	_toast_title = Label.new()
	_toast_title.add_theme_font_size_override("font_size", 15)
	_toast_title.add_theme_color_override("font_color", Color("edf3ff"))
	text_column.add_child(_toast_title)
	_toast_description = Label.new()
	_toast_description.add_theme_font_size_override("font_size", 11)
	_toast_description.add_theme_color_override("font_color", Color("b8c7dc"))
	_toast_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(_toast_description)
	_toast_card.gui_input.connect(_on_toast_input)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 4.2
	_toast_timer.timeout.connect(_show_next_toast)
	add_child(_toast_timer)

func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_hide_toast()
		return
	var queued: Dictionary = _toast_queue.pop_front()
	var definition: Dictionary = queued.get("definition", {})
	var provisional := bool(queued.get("provisional", false))
	_toast_heading.text = tr("MILESTONE REACHED") if provisional else tr("ACHIEVEMENT UNLOCKED")
	_toast_title.text = tr(str(definition.title))
	_toast_description.text = tr(str(definition.description))
	_toast_card.visible = true
	_toast_timer.start()

func _on_toast_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toast_timer.stop()
		_show_next_toast()

func _hide_toast() -> void:
	if is_instance_valid(_toast_card):
		_toast_card.visible = false
	if is_instance_valid(_toast_timer):
		_toast_timer.stop()

func _toast_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a", 0.98)
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
