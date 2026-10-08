extends Control
## Campaign world map. The painted 320x180 background (tools/campaign/
## generate_world_maps.py) is drawn x3 into a 960x540 map space that is
## letterboxed to the window; stage stones, stars, padlocks, the boss and the
## avatar are drawn on top from live progress. Cards and buttons are ordinary
## themed controls so they stay crisp at any size.
##
## Keys: left/right choose a stage, Enter/Space plays, Q/E or PageUp/PageDown
## change world, Esc goes back. Mouse and touch: tap a stone to walk there,
## then Play to start.

signal play_requested(level: CampaignLevel)
signal back_requested

const MAP_SIZE := Vector2(960.0, 540.0)
const MAP_PIXEL := 3.0
const SkinPalette := preload("res://player/skin_palette.gd")
const StarIconScript := preload("res://campaign/star_icon.gd")
const AVATAR_SPEED := 260.0
const INK := Color("edf3ff")
const MUTED := Color("b8c7dc")
const CARD := Color("121b2c", 0.93)
const OUTLINE := Color("14141c")

var _world_index := 0
var _selected := 0
var _map_rect := Rect2()
var _time := 0.0
var _canvas: Control
var _avatar: AnimatedSprite2D
var _avatar_map_pos := Vector2.ZERO
var _avatar_path: Array[Vector2] = []
var _world_title: Label
var _world_stats: Label
var _boss_card: PanelContainer
var _boss_label: Label
var _stage_title: Label
var _stage_intro: Label
var _stage_record: Label
var _stage_stars: HBoxContainer
var _play_button: Button
var _lock_label: Label
var _prev_world: Button
var _next_world: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var worlds := CampaignCatalog.worlds()
	_world_index = maxi(0, worlds.find(CampaignCatalog.get_world(Campaign.get_last_world_id())))
	if not Campaign.is_world_unlocked(worlds[_world_index]):
		_world_index = 0
	_build()
	_enter_world(_world_index)
	get_viewport().size_changed.connect(_layout)
	_layout()
	grab_focus()

func _world() -> CampaignWorld:
	return CampaignCatalog.worlds()[_world_index]

# --- construction -----------------------------------------------------------

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b111c")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_avatar = AnimatedSprite2D.new()
	_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.add_child(_avatar)
	_apply_avatar_character()

	var title_card := _card(Vector2(16.0, 14.0), Vector2(380.0, 0.0), Control.PRESET_TOP_LEFT)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_card.add_child(title_box)
	_world_title = _label("", 21, INK)
	_world_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(_world_title)
	_world_stats = _label("", 13, MUTED)
	_world_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_box.add_child(_world_stats)

	_boss_card = _card(Vector2(-16.0, 14.0), Vector2(220.0, 0.0), Control.PRESET_TOP_RIGHT)
	_boss_label = _label("", 14, INK)
	_boss_card.add_child(_boss_label)

	var stage_card := _card(Vector2(-16.0, -16.0), Vector2(380.0, 0.0), Control.PRESET_BOTTOM_RIGHT)
	stage_card.name = "StageCard"
	var stage_box := VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 4)
	stage_card.add_child(stage_box)
	_stage_title = _label("", 18, INK)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stage_box.add_child(_stage_title)
	_stage_intro = _label("", 13, MUTED)
	_stage_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stage_box.add_child(_stage_intro)
	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 6)
	stage_box.add_child(record_row)
	_stage_stars = HBoxContainer.new()
	_stage_stars.add_theme_constant_override("separation", 2)
	record_row.add_child(_stage_stars)
	_stage_record = _label("", 13, MUTED)
	_stage_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stage_record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_row.add_child(_stage_record)
	_play_button = Button.new()
	_play_button.text = tr("PLAY")
	_play_button.custom_minimum_size = Vector2(120.0, 42.0)
	_play_button.add_theme_font_size_override("font_size", 17)
	_play_button.focus_mode = Control.FOCUS_NONE
	_play_button.pressed.connect(_play_selected)
	record_row.add_child(_play_button)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	nav.offset_left = 16.0
	nav.offset_top = -58.0
	nav.offset_bottom = -16.0
	nav.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(nav)
	var back := _button(tr("Back"), nav)
	back.pressed.connect(back_requested.emit)
	_prev_world = _button("‹", nav)
	_prev_world.tooltip_text = tr("Previous world")
	_prev_world.pressed.connect(_change_world.bind(-1))
	_next_world = _button("›", nav)
	_next_world.tooltip_text = tr("Next world")
	_next_world.pressed.connect(_change_world.bind(1))

	_lock_label = _label("", 20, INK)
	_lock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lock_label.custom_minimum_size = Vector2(560.0, 0.0)
	_lock_label.offset_left = -280.0
	_lock_label.offset_right = 280.0
	_lock_label.offset_top = -40.0
	_lock_label.offset_bottom = 40.0
	add_child(_lock_label)

func _card(offset: Vector2, min_size: Vector2, preset: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	card.set_anchors_and_offsets_preset(preset)
	match preset:
		Control.PRESET_TOP_RIGHT:
			card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			card.offset_right = offset.x
			card.offset_left = offset.x - min_size.x
			card.offset_top = offset.y
		Control.PRESET_BOTTOM_RIGHT:
			card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			card.grow_vertical = Control.GROW_DIRECTION_BEGIN
			card.offset_right = offset.x
			card.offset_left = offset.x - min_size.x
			card.offset_bottom = offset.y
			card.offset_top = offset.y
		_:
			card.offset_left = offset.x
			card.offset_top = offset.y
	return card

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, parent: Container) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(52.0, 42.0)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _apply_avatar_character() -> void:
	var definition := PlayerProfile.get_selected_character()
	if definition == null or definition.sprite_frames == null:
		return
	_avatar.sprite_frames = definition.sprite_frames
	var skin := int(PlayerProfile.preferred_skin_id)
	_avatar.material = null if skin == 0 else SkinPalette.make_material(skin)
	_avatar.play(&"default")

# --- state ------------------------------------------------------------------

func _enter_world(index: int) -> void:
	var worlds := CampaignCatalog.worlds()
	_world_index = clampi(index, 0, worlds.size() - 1)
	var world := _world()
	# Start on the remembered stage, else on the furthest open stage.
	_selected = 0
	var remembered := Campaign.get_last_level_id(world)
	var found := false
	for i in range(world.levels.size()):
		if world.levels[i].level_id == remembered and Campaign.is_level_unlocked(world.levels[i]):
			_selected = i
			found = true
	if not found:
		for i in range(world.levels.size()):
			if Campaign.is_level_unlocked(world.levels[i]):
				_selected = i
	# Changing world always snaps; walking is only along one world's path.
	_avatar_path.clear()
	_avatar_map_pos = _node_pos(_selected)
	_refresh()
	# Coming back after clearing a stage: walk on to the newly opened one.
	if found and _selected + 1 < world.levels.size():
		var current: CampaignLevel = world.levels[_selected]
		var next: CampaignLevel = world.levels[_selected + 1]
		if Campaign.is_completed(current) and Campaign.is_level_unlocked(next) and not Campaign.is_completed(next):
			_select(_selected + 1)

func _node_pos(index: int) -> Vector2:
	var world := _world()
	if world.map_nodes.is_empty():
		return MAP_SIZE * 0.5
	return world.map_nodes[clampi(index, 0, world.map_nodes.size() - 1)] * MAP_PIXEL

func _selected_level() -> CampaignLevel:
	var world := _world()
	return world.levels[_selected] if _selected >= 0 and _selected < world.levels.size() else null

func _refresh() -> void:
	var world := _world()
	var unlocked := Campaign.is_world_unlocked(world)
	_world_title.text = tr("WORLD %d · %s") % [world.number, tr(world.title).to_upper()]
	if world.is_playable():
		_world_stats.text = tr("Gravity stars %d/%d  ·  Stages %d/%d") % [Campaign.get_world_star_count(world), world.total_stars(), Campaign.get_world_completed_count(world), world.levels.size()]
	else:
		_world_stats.text = tr("Coming soon")
	var boss := world.get_boss()
	_boss_card.visible = boss != null
	if boss != null:
		_boss_label.text = (tr("Boss: %s · beaten") if Campaign.is_completed(boss) else tr("Boss: %s")) % tr(boss.title)
	_prev_world.disabled = _world_index <= 0
	_next_world.disabled = _world_index >= CampaignCatalog.worlds().size() - 1
	var level := _selected_level()
	var stage_card := get_node("StageCard") as Control
	stage_card.visible = unlocked and level != null
	if not unlocked:
		var previous: CampaignWorld = CampaignCatalog.worlds()[_world_index - 1]
		_lock_label.text = tr("Beat the boss of %s to open this world") % tr(previous.title)
	elif not world.is_playable():
		_lock_label.text = tr("The stages of this world are on their way")
	else:
		_lock_label.text = ""
	_lock_label.visible = not _lock_label.text.is_empty()
	if level != null and unlocked:
		var open := Campaign.is_level_unlocked(level)
		_stage_title.text = "%s  %s" % [str(level.level_id), tr(level.title)]
		_stage_intro.text = tr(level.intro)
		for child in _stage_stars.get_children():
			child.queue_free()
		var mask := Campaign.get_star_mask(level)
		for i in range(level.stars.size()):
			var icon := StarIconScript.new() as Control
			icon.custom_minimum_size = Vector2(20.0, 20.0)
			icon.set("filled", (mask >> i) & 1 == 1)
			_stage_stars.add_child(icon)
		var best := Campaign.get_best_score(level)
		_stage_record.text = (tr("Best: %d") % best) if best > 0 else (tr("Not cleared yet") if open else tr("Locked"))
		_play_button.disabled = not open
	_canvas.queue_redraw()

func _change_world(direction: int) -> void:
	var target := clampi(_world_index + direction, 0, CampaignCatalog.worlds().size() - 1)
	if target == _world_index:
		return
	_enter_world(target)

func _select(index: int) -> void:
	var world := _world()
	if not Campaign.is_world_unlocked(world) or world.levels.is_empty():
		return
	index = clampi(index, 0, world.levels.size() - 1)
	if not Campaign.is_level_unlocked(world.levels[index]) or index == _selected:
		return
	# Walk along the stones between the old and the new stage.
	var step := 1 if index > _selected else -1
	var i := _selected
	while i != index:
		i += step
		_avatar_path.append(_node_pos(i))
	_selected = index
	Campaign.remember_selection(world.levels[index])
	_refresh()

func _play_selected() -> void:
	var level := _selected_level()
	if level == null or not Campaign.is_world_unlocked(_world()) or not Campaign.is_level_unlocked(level):
		return
	play_requested.emit(level)

# --- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Handle keys here while the map has focus, before focus navigation.
	if _handle_key(event):
		accept_event()
		return
	var press_position := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press_position = event.position
	elif event is InputEventScreenTouch and event.pressed:
		press_position = event.position
	if press_position == Vector2.INF:
		return
	var map_point := (press_position - _map_rect.position) / (_map_rect.size.x / MAP_SIZE.x)
	var world := _world()
	for i in range(world.levels.size()):
		if map_point.distance_to(_node_pos(i)) <= 30.0:
			# Tapping a stone only walks there; the Play button starts it.
			_select(i)
			accept_event()
			return

func _unhandled_key_input(event: InputEvent) -> void:
	if _handle_key(event):
		get_viewport().set_input_as_handled()

func _handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo:
		return false
	var key := (event as InputEventKey).keycode
	match key:
		KEY_LEFT, KEY_A:
			_select(_selected - 1)
		KEY_RIGHT, KEY_D:
			_select(_selected + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_play_selected()
		KEY_Q, KEY_PAGEUP:
			_change_world(-1)
		KEY_E, KEY_PAGEDOWN:
			_change_world(1)
		KEY_ESCAPE:
			back_requested.emit()
		_:
			return false
	return true

# --- drawing ----------------------------------------------------------------

func _layout() -> void:
	var view := get_viewport_rect().size
	var scale_factor := minf(view.x / MAP_SIZE.x, view.y / MAP_SIZE.y)
	var map_size := MAP_SIZE * scale_factor
	_map_rect = Rect2((view - map_size) * 0.5, map_size)
	_canvas.queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	if not _avatar_path.is_empty():
		var target: Vector2 = _avatar_path[0]
		var to_target := target - _avatar_map_pos
		var step := AVATAR_SPEED * delta
		if to_target.length() <= step:
			_avatar_map_pos = target
			_avatar_path.pop_front()
		else:
			_avatar_map_pos += to_target.normalized() * step
			_avatar.flip_h = to_target.x < 0.0
	var moving := not _avatar_path.is_empty()
	if moving and _avatar.animation != &"run":
		_avatar.play(&"run")
	elif not moving and _avatar.animation != &"default":
		_avatar.play(&"default")
		_avatar.flip_h = false
	var map_scale := _map_rect.size.x / MAP_SIZE.x
	_avatar.position = _map_rect.position + (_avatar_map_pos + Vector2(0.0, -46.0 + (0.0 if moving else roundf(sin(_time * 2.5) * 1.5)))) * map_scale
	_avatar.scale = Vector2.ONE * 2.0 * map_scale
	_avatar.visible = Campaign.is_world_unlocked(_world()) and _world().is_playable()
	_canvas.queue_redraw()

func _draw_map() -> void:
	var map_scale := _map_rect.size.x / MAP_SIZE.x
	_canvas.draw_set_transform(_map_rect.position, 0.0, Vector2.ONE * map_scale)
	var world := _world()
	if world.map_texture != null:
		_canvas.draw_texture_rect(world.map_texture, Rect2(Vector2.ZERO, MAP_SIZE), false)
	else:
		_canvas.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("24324a"))
	var unlocked := Campaign.is_world_unlocked(world)
	for i in range(world.map_nodes.size()):
		var level: CampaignLevel = world.levels[i] if i < world.levels.size() else null
		_draw_node(i, level, unlocked)
	if not unlocked or not world.is_playable():
		_canvas.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.02, 0.03, 0.06, 0.62))
	_canvas.draw_set_transform(Vector2.ZERO)

func _px(origin: Vector2, x: float, y: float, w: float, h: float, color: Color) -> void:
	_canvas.draw_rect(Rect2(origin + Vector2(x, y) * MAP_PIXEL, Vector2(w, h) * MAP_PIXEL), color)

func _pixel_disc(center: Vector2, radius: float, color: Color) -> void:
	# Center is in map space; radius in map pixels.
	var cx := center.x / MAP_PIXEL
	var cy := center.y / MAP_PIXEL
	for y in range(int(cy - radius - 1.0), int(cy + radius + 2.0)):
		var row_start := INF
		var row_end := -INF
		for x in range(int(cx - radius - 1.0), int(cx + radius + 2.0)):
			if pow(float(x) + 0.5 - cx, 2.0) + pow(float(y) + 0.5 - cy, 2.0) <= radius * radius:
				row_start = minf(row_start, float(x))
				row_end = maxf(row_end, float(x))
		if row_start <= row_end:
			_canvas.draw_rect(Rect2(Vector2(row_start, float(y)) * MAP_PIXEL, Vector2(row_end - row_start + 1.0, 1.0) * MAP_PIXEL), color)

func _draw_node(index: int, level: CampaignLevel, world_unlocked: bool) -> void:
	var center := _node_pos(index)
	var is_boss := level != null and level.is_boss()
	var radius := 9.0 if is_boss else 7.0
	var open := world_unlocked and level != null and Campaign.is_level_unlocked(level)
	var done := level != null and Campaign.is_completed(level)
	var top := Color("808492")
	if done:
		top = Color("42d6c5")
	elif open:
		top = Color("ffcd3c")
	if is_boss and open:
		top = Color("c44054") if not done else Color("42d6c5")
	if index == _selected and open:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		_pixel_disc(center + Vector2(0, 2), radius + 3.0 + pulse, Color(1.0, 0.95, 0.6, 0.35))
	_pixel_disc(center + Vector2(0, 6), radius + 1.0, OUTLINE)
	_pixel_disc(center + Vector2(0, 3), radius, Color("6e7484") if open else Color("5a5e6a"))
	_pixel_disc(center, radius, OUTLINE)
	_pixel_disc(center - Vector2(0, 3), radius - 1.0, top)
	_pixel_disc(center - Vector2(6, 9), 2.0, top.lightened(0.35))
	var font := ThemeDB.fallback_font
	if is_boss:
		if open and not done:
			_draw_mini_boss(center + Vector2(0, -30))
		elif not open:
			_draw_padlock(center + Vector2(15, -30))
	else:
		var label := str(level.level_id) if level != null else "%d-%d" % [_world().number, index + 1]
		_canvas.draw_string(font, center + Vector2(-20, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 13, OUTLINE if open else Color("3c404c"))
		if not open:
			_draw_padlock(center + Vector2(15, -30))
	if level != null and open and not is_boss:
		var mask := Campaign.get_star_mask(level)
		for k in range(level.stars.size()):
			_draw_pixel_star(center + Vector2(-24.0 + float(k) * 24.0, 36.0), (mask >> k) & 1 == 1)

func _draw_pixel_star(origin: Vector2, filled: bool) -> void:
	var shape := ["...#...", "..###..", "#######", ".#####.", ".##.##.", "#.....#"]
	var color := Color("ffcd3c") if filled else Color("40465a")
	var dark := Color("c88c1e") if filled else Color("40465a")
	var base := origin - Vector2(3.5, 3.0) * MAP_PIXEL
	for row in range(shape.size()):
		for column in range(7):
			if shape[row][column] == "#":
				_px(base, float(column), float(row), 1.0, 1.0, color if row < 3 else dark)

func _draw_padlock(origin: Vector2) -> void:
	var lock_color := Color("343440")
	_px(origin, -2, 0, 5, 4, lock_color)
	_px(origin, -2, -2, 1, 2, lock_color)
	_px(origin, 2, -2, 1, 2, lock_color)
	_px(origin, -1, -3, 3, 1, lock_color)
	_px(origin, 0, 1, 1, 1, Color("ffcd3c"))

func _draw_mini_boss(origin: Vector2) -> void:
	var boss := _world().get_boss()
	if boss != null and boss.boss_id == &"stalactite":
		_draw_mini_bat(origin)
		return
	# A tiny Rullaren on its stone: body, stack, eyes and a barrel.
	var body := Color("8c5a46")
	_px(origin, -6, -8, 13, 9, OUTLINE)
	_px(origin, -5, -7, 11, 7, body)
	_px(origin, 2, -12, 3, 4, OUTLINE)
	_px(origin, -4, -5, 2, 1, Color("ff5a46"))
	_px(origin, 1, -5, 2, 1, Color("ff5a46"))
	_px(origin, -6, 1, 13, 2, Color("5a6274"))
	_px(origin, -9, -3, 3, 3, Color("b8783f"))
	var puff := fmod(_time, 1.0)
	_canvas.draw_rect(Rect2(origin + Vector2(3.0 - puff * 6.0, -14.0 - puff * 14.0) * MAP_PIXEL, Vector2(2, 2) * MAP_PIXEL), Color(0.85, 0.87, 0.9, 1.0 - puff))

## A tiny Stalactite Giant hanging over its stone, wings flapping.
func _draw_mini_bat(origin: Vector2) -> void:
	var fur := Color("4a3566")
	var wing := Color("5b3f7a")
	var flap := 1 if fmod(_time, 0.6) < 0.3 else 0
	_px(origin, -3, -9, 7, 8, OUTLINE)
	_px(origin, -2, -8, 5, 6, fur)
	_px(origin, -3, -11, 2, 2, OUTLINE)
	_px(origin, 2, -11, 2, 2, OUTLINE)
	_px(origin, -1, -7, 1, 1, Color("ff4f6a"))
	_px(origin, 1, -7, 1, 1, Color("ff4f6a"))
	_px(origin, -8, -8 - flap, 5, 3, OUTLINE)
	_px(origin, -7, -7 - flap, 4, 1, wing)
	_px(origin, 4, -8 - flap, 5, 3, OUTLINE)
	_px(origin, 4, -7 - flap, 4, 1, wing)
