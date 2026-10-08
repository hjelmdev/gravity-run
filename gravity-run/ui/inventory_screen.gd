extends Control

signal back_requested

const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")
const ItemDefinitionScript := preload("res://systems/item_definition.gd")
const SpriteFramesResource := preload("res://assets/character/run_frames.tres")
const ItemPresentationScript := preload("res://ui/item_presentation.gd")
const GameIconScript := preload("res://ui/game_icon.gd")
const SkinPalette := preload("res://player/skin_palette.gd")

var view_mode := "character"
var equipment_locked := false
var _panel: PanelContainer
var _body: Control
var _status_label: Label
var _wallet_label: Label
var _title_label: Label
var _view_switch_button: Button
var _state: Dictionary = {}
var _stale := false
var _error_message := ""
var _selected_instance_id := ""
var _selected_empty_slot := ""
var _selected_shop_item_id := ""
var _action_pending := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InventoryService.state_changed.connect(_on_state_changed)
	InventoryService.action_finished.connect(_on_action_finished)
	_state = InventoryService.inventory_state.duplicate(true)
	_stale = InventoryService.state_is_stale
	_error_message = InventoryService.last_error
	_build_shell()
	_render()
	if AuthService.is_authenticated:
		InventoryService.refresh()

func _build_shell() -> void:
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.035, 0.055, 0.09, 0.82)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.035
	_panel.anchor_bottom = 0.965
	var panel_width := minf(1400.0, get_viewport_rect().size.x - 32.0)
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_panel.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)
	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(72.0, 34.0)
	back.pressed.connect(_on_back)
	header.add_child(back)
	_title_label = Label.new()
	_title_label.text = tr("CHARACTER / INVENTORY") if view_mode == "character" else tr("SHOP")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 21)
	_title_label.add_theme_color_override("font_color", Color("edf3ff"))
	header.add_child(_title_label)
	_view_switch_button = Button.new()
	_view_switch_button.text = tr("Shop") if view_mode == "character" else tr("Character / Inventory")
	_view_switch_button.custom_minimum_size = Vector2(100.0, 34.0)
	_view_switch_button.pressed.connect(_toggle_view)
	header.add_child(_view_switch_button)
	_wallet_label = Label.new()
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet_label.custom_minimum_size.x = 100.0
	_wallet_label.add_theme_color_override("font_color", Color("f5d45e"))
	header.add_child(_wallet_label)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(_status_label)
	var separator := HSeparator.new()
	layout.add_child(separator)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	layout.add_child(_body)

func _render() -> void:
	if not is_instance_valid(_body):
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_wallet_label.text = tr("Coins: %d") % int(_state.get("wallet_coins", AccountProgress.wallet_coins)) if AuthService.is_authenticated else tr("Coins: —")
	_title_label.text = tr("CHARACTER / INVENTORY") if view_mode == "character" else tr("SHOP")
	_view_switch_button.text = tr("Shop") if view_mode == "character" else tr("Character / Inventory")
	if not AuthService.is_authenticated:
		if view_mode == "character":
			_status_label.text = tr("Sign in to save items and use the shop.")
			_build_guest_character()
		else:
			_status_label.text = tr("Sign in to save items and use the shop.")
			_add_empty_state(tr("Guest inventory is not saved."))
		return
	if _stale:
		_status_label.text = tr("Inventory is out of date; syncing. Changes are disabled.")
	elif _action_pending:
		_status_label.text = tr("Saving inventory change…")
	elif equipment_locked and view_mode == "character":
		_status_label.text = tr("Equipment changes are locked until the run ends.")
	elif not _error_message.is_empty():
		_status_label.text = tr("Could not sync inventory: %s") % _error_message
	else:
		_status_label.text = tr("Inventory is synced.") if not _state.is_empty() else tr("Loading inventory…")
	if _state.is_empty():
		_add_empty_state(tr("Loading inventory…") if _error_message.is_empty() else tr("Inventory could not be loaded."))
		return
	if view_mode == "shop":
		_build_shop()
	else:
		_build_character()

func _toggle_view() -> void:
	view_mode = "shop" if view_mode == "character" else "character"
	_render()

func _build_character() -> void:
	var narrow_layout := get_viewport_rect().size.x < 700.0
	var content: BoxContainer = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_body.add_child(content)
	var left := VBoxContainer.new()
	if not narrow_layout:
		left.custom_minimum_size.x = 185.0
	left.add_theme_constant_override("separation", 7)
	content.add_child(left)
	var character_card := _card()
	left.add_child(character_card)
	var character_column := VBoxContainer.new()
	character_column.add_theme_constant_override("separation", 4)
	character_card.add_child(character_column)
	var character_stage := Control.new()
	character_stage.custom_minimum_size = Vector2(155.0, 154.0)
	character_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_column.add_child(character_stage)
	var sprite := TextureRect.new()
	_apply_character_preview(sprite)
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.position = Vector2(52.0, 27.0)
	sprite.size = Vector2(58.0, 78.0)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_stage.add_child(sprite)
	var character_label := Label.new()
	character_label.text = tr(PlayerProfile.get_selected_character().display_name)
	character_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_label.position = Vector2(0.0, 124.0)
	character_label.size = Vector2(155.0, 22.0)
	character_stage.add_child(character_label)
	var equipment: Variant = _state.get("equipment", {})
	for slot in EquipmentStatsScript.SLOT_ORDER:
		var instance_id := str(equipment.get(slot, "")) if equipment is Dictionary else ""
		var owned := _find_owned_item(instance_id)
		var slot_control := _make_character_slot(str(slot), instance_id, owned)
		character_stage.add_child(slot_control)
	character_column.add_child(_make_character_picker())
	var stats_card := _card()
	left.add_child(stats_card)
	var stats_layout := VBoxContainer.new()
	stats_layout.add_theme_constant_override("separation", 3)
	stats_card.add_child(stats_layout)
	var stats_title := Label.new()
	stats_title.text = tr("Stats")
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_color_override("font_color", Color("42d6c5"))
	stats_layout.add_child(stats_title)
	var resolved := _resolve_equipment()
	for stat in EquipmentStatsScript.STAT_ORDER:
		var stat_row := HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 5)
		stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
		stats_layout.add_child(stat_row)
		var stat_label := Label.new()
		var value := int(resolved.get("totals", {}).get(stat, 10000))
		stat_label.text = tr("Run speed") if stat == "run_speed_percent" else tr("Flip cooldown")
		stat_label.text += ": %s" % _format_percent_bps(value)
		stats_label_add(stat_label, stat_row)
		var bonus := int(resolved.get("bonuses", {}).get(stat, 0))
		if bonus != 0:
			var bonus_label := Label.new()
			bonus_label.text = _format_modifier_bps(bonus)
			bonus_label.add_theme_color_override("font_color", Color("64d879"))
			bonus_label.add_theme_font_size_override("font_size", 10)
			stat_row.add_child(bonus_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	content.add_child(right)
	var bag_title := Label.new()
	bag_title.text = tr("Bag · 24 slots per page")
	bag_title.add_theme_color_override("font_color", Color("42d6c5"))
	right.add_child(bag_title)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.custom_minimum_size.y = 175.0 if narrow_layout else 225.0
	bag_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(bag_scroll)
	var grid := GridContainer.new()
	grid.columns = 4 if get_viewport_rect().size.x < 700.0 else 6
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(grid)
	var items: Variant = _state.get("items", [])
	var definitions := _catalog_by_id()
	var count := 0
	if items is Array:
		for raw_item in items:
			if not raw_item is Dictionary:
				continue
			var item_id := str(raw_item.get("item_id", ""))
			var definition: Dictionary = definitions.get(item_id, {})
			var instance_id := str(raw_item.get("instance_id", ""))
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(64.0, 44.0) if grid.columns == 4 else Vector2(70.0, 48.0)
			var equipped_state: Variant = _state.get("equipment", {})
			var item_equipped := equipped_state is Dictionary and str(equipped_state.get(str(definition.get("slot_type", "")), "")) == instance_id
			cell.tooltip_text = ItemPresentationScript.tooltip(definition, {"equipped": item_equipped})
			cell.accessibility_name = cell.tooltip_text
			cell.add_theme_color_override("font_color", _rarity_color(str(definition.get("rarity", "common"))))
			cell.pressed.connect(_select_item.bind(instance_id))
			var cell_layout := VBoxContainer.new()
			cell_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			cell_layout.offset_left = 3.0
			cell_layout.offset_right = -3.0
			cell_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell_layout.alignment = BoxContainer.ALIGNMENT_CENTER
			cell_layout.add_theme_constant_override("separation", 1)
			cell.add_child(cell_layout)
			var item_icon: Control = GameIconScript.new()
			item_icon.icon_key = str(definition.get("icon_key", "unknown"))
			item_icon.custom_minimum_size = Vector2(22, 20)
			item_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell_layout.add_child(item_icon)
			var item_label := Label.new()
			item_label.text = _display_item_name(definition)
			item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			item_label.add_theme_font_size_override("font_size", 9)
			item_label.add_theme_color_override("font_color", _rarity_color(str(definition.get("rarity", "common"))))
			item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell_layout.add_child(item_label)
			grid.add_child(cell)
			count += 1
	for _empty_index in range(24 - count):
		var empty_cell := Panel.new()
		empty_cell.custom_minimum_size = Vector2(64.0, 44.0) if grid.columns == 4 else Vector2(70.0, 48.0)
		empty_cell.add_theme_stylebox_override("panel", _empty_cell_style())
		grid.add_child(empty_cell)
	var detail := _build_selected_detail()
	right.add_child(detail)
	var equip_button := Button.new()
	equip_button.custom_minimum_size.y = 34.0
	equip_button.disabled = _selected_instance_id.is_empty() or _stale or _action_pending or equipment_locked
	if not equip_button.disabled:
		var selected := _find_owned_item(_selected_instance_id)
		var selected_slot := str(selected.get("definition", {}).get("slot_type", ""))
		var equipped: Variant = _state.get("equipment", {})
		var is_equipped := equipped is Dictionary and str(equipped.get(selected_slot, "")) == _selected_instance_id
		equip_button.text = tr("Unequip") if is_equipped else tr("Equip")
		if not equipment_locked:
			equip_button.pressed.connect(InventoryService.unequip.bind(selected_slot) if is_equipped else InventoryService.equip.bind(_selected_instance_id, selected_slot))
	elif equipment_locked:
		equip_button.text = tr("Equipment changes are locked until the run ends.")
	else:
		equip_button.text = tr("Select an item to equip")
	right.add_child(equip_button)

func _make_character_slot(slot: String, instance_id: String, owned: Dictionary) -> Control:
	var slot_column := VBoxContainer.new()
	slot_column.add_theme_constant_override("separation", 1)
	var slot_button := Button.new()
	slot_button.custom_minimum_size = Vector2(44.0, 42.0)
	slot_button.add_theme_font_size_override("font_size", 17)
	var definition: Dictionary = owned.get("definition", {})
	var equipped_name := _display_item_name(definition) if not definition.is_empty() else tr("Empty slot")
	slot_button.tooltip_text = ItemPresentationScript.tooltip(definition, {"equipped": true}) if not definition.is_empty() else "%s · %s · %s" % [_slot_name(slot), tr("Empty slot"), tr("No item is equipped in this slot.")]
	slot_button.accessibility_name = slot_button.tooltip_text
	slot_button.add_theme_color_override("font_color", _rarity_color(str(definition.get("rarity", "common"))) if not definition.is_empty() else Color("8292aa"))
	var slot_icon: Control = GameIconScript.new()
	slot_icon.icon_key = str(definition.get("icon_key", "helmet_copper_01" if slot == "helmet" else "boots_canvas_01"))
	slot_icon.custom_minimum_size = Vector2(30, 30)
	slot_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	slot_icon.position = Vector2(-15, -15)
	slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_button.add_child(slot_icon)
	slot_button.pressed.connect(_on_character_slot_pressed.bind(slot, instance_id))
	slot_column.add_child(slot_button)
	var slot_label := Label.new()
	slot_label.text = _slot_name(slot)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 10)
	slot_column.add_child(slot_label)
	if slot == "helmet":
		slot_column.position = Vector2(2.0, 5.0)
	else:
		slot_column.position = Vector2(108.0, 88.0)
	return slot_column

func _on_character_slot_pressed(slot: String, equipped_instance_id: String) -> void:
	if _stale or _action_pending or equipment_locked:
		return
	if _selected_instance_id.is_empty():
		if not equipped_instance_id.is_empty():
			_select_item(equipped_instance_id)
		else:
			_selected_empty_slot = slot
			_render()
		return
	var selected := _find_owned_item(_selected_instance_id)
	var definition: Dictionary = selected.get("definition", {})
	if definition.is_empty() or str(definition.get("slot_type", "")) != slot:
		_status_label.text = tr("Choose an item for the matching equipment slot.")
		return
	_action_pending = true
	_render()
	InventoryService.equip(_selected_instance_id, slot)

func _build_guest_character() -> void:
	var layout := VBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 8)
	_body.add_child(layout)
	var preview := TextureRect.new()
	_apply_character_preview(preview)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(60.0, 76.0)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(preview)
	layout.add_child(_make_character_picker())
	var stats := Label.new()
	var profile_stats: Resource = PlayerProfile.get_character_stats()
	var base_stats: Dictionary = profile_stats.call("get_base_stats") if profile_stats != null else {}
	stats.text = tr("Base stats") + "\n" + tr("Run speed") + ": %s\n" % _format_percent_bps(int(base_stats.get("run_speed_percent", 10000)))
	stats.text += tr("Flip cooldown") + ": %s" % _format_percent_bps(int(base_stats.get("flip_cooldown_percent", 10000)))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_color_override("font_color", Color("b8c7dc"))
	layout.add_child(stats)
	var prompt := Label.new()
	prompt.text = tr("Guest inventory is not saved.")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(prompt)

## Character switcher ("< Nova >") shared by the signed-in and guest views.
## Characters only change art for now; base stats are identical.
func _make_character_picker() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var previous := Button.new()
	previous.text = "<"
	previous.custom_minimum_size = Vector2(34.0, 30.0)
	previous.tooltip_text = tr("Previous character")
	previous.accessibility_name = previous.tooltip_text
	previous.disabled = equipment_locked
	previous.pressed.connect(_cycle_character.bind(-1))
	row.add_child(previous)
	var definition := PlayerProfile.get_selected_character()
	var name_label := Label.new()
	name_label.text = tr(definition.display_name)
	name_label.custom_minimum_size.x = 96.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(34.0, 30.0)
	next.tooltip_text = tr("Next character")
	next.accessibility_name = next.tooltip_text
	next.disabled = equipment_locked
	next.pressed.connect(_cycle_character.bind(1))
	row.add_child(next)
	var detail := Label.new()
	detail.text = tr(definition.trait_text) if not definition.trait_text.is_empty() else tr(definition.description)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 170.0
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", Color("b8c7dc"))
	column.add_child(detail)
	return column

func _cycle_character(direction: int) -> void:
	var count := CharacterCatalog.DEFINITIONS.size()
	var index := CharacterCatalog.index_of(PlayerProfile.selected_character_id)
	for _step in count:
		index = posmod(index + direction, count)
		var candidate: CharacterDefinition = CharacterCatalog.DEFINITIONS[index]
		if CharacterCatalog.is_unlocked(candidate):
			PlayerProfile.set_selected_character_id(candidate.id)
			break
	_render()

func _apply_character_preview(preview: TextureRect) -> void:
	var definition := PlayerProfile.get_selected_character()
	var frames: SpriteFrames = definition.sprite_frames if definition.sprite_frames != null else SpriteFramesResource
	preview.texture = frames.get_frame_texture(&"run", 0)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var skin_id := int(PlayerProfile.preferred_skin_id)
	preview.material = null if skin_id == 0 else SkinPalette.make_material(skin_id)

func _build_shop() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 150.0
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var grid := GridContainer.new()
	var viewport_width := get_viewport_rect().size.x
	grid.columns = 5 if viewport_width >= 1200.0 else (4 if viewport_width >= 900.0 else (3 if viewport_width >= 620.0 else 2))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var owned: Dictionary = {}
	var items: Variant = _state.get("items", [])
	if items is Array:
		for item in items:
			if item is Dictionary:
				owned[str(item.get("item_id", ""))] = true
	var catalog: Variant = _state.get("catalog", [])
	if not catalog is Array:
		return
	var first_shop_item := ""
	for definition in catalog:
		if not definition is Dictionary or not bool(definition.get("shop_enabled", false)):
			continue
		var item_id := str(definition.get("item_id", ""))
		if first_shop_item.is_empty():
			first_shop_item = item_id
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(95.0, 62.0)
		tile.tooltip_text = ItemPresentationScript.tooltip(definition, {"owned": owned.has(item_id)})
		tile.accessibility_name = tile.tooltip_text
		var item_color := Color("78869b") if owned.has(item_id) else _rarity_color(str(definition.get("rarity", "common")))
		var tile_content := VBoxContainer.new()
		tile_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile_content.offset_left = 4.0
		tile_content.offset_right = -4.0
		tile_content.alignment = BoxContainer.ALIGNMENT_CENTER
		tile_content.add_theme_constant_override("separation", 1)
		tile_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(tile_content)
		var glyph: Control = GameIconScript.new()
		glyph.icon_key = str(definition.get("icon_key", "unknown"))
		glyph.custom_minimum_size = Vector2(26, 26)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_content.add_child(glyph)
		var item_name := Label.new()
		item_name.text = _display_item_name(definition)
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_name.add_theme_font_size_override("font_size", 9)
		item_name.add_theme_color_override("font_color", item_color)
		tile_content.add_child(item_name)
		tile.pressed.connect(_select_shop_item.bind(item_id))
		grid.add_child(tile)
	if _selected_shop_item_id.is_empty() or not _catalog_by_id().has(_selected_shop_item_id):
		_selected_shop_item_id = first_shop_item
	var selected_definition: Dictionary = _catalog_by_id().get(_selected_shop_item_id, {})
	_body.add_child(_build_shop_detail(selected_definition, owned))
	var buy_button := Button.new()
	buy_button.custom_minimum_size.y = 34.0
	var price := int(selected_definition.get("shop_price", 0))
	if selected_definition.is_empty():
		buy_button.text = tr("Select an item to buy")
		buy_button.disabled = true
	elif owned.has(_selected_shop_item_id):
		buy_button.text = tr("Owned")
		buy_button.disabled = true
	elif _stale or _action_pending:
		buy_button.text = tr("Syncing…") if _stale else tr("Saving inventory change…")
		buy_button.disabled = true
	elif AccountProgress.wallet_coins < price:
		buy_button.text = tr("Not enough coins · %d") % price
		buy_button.disabled = true
	else:
		buy_button.text = tr("Buy · %d coins") % price
		buy_button.pressed.connect(_purchase.bind(_selected_shop_item_id))
	_body.add_child(buy_button)

func _build_shop_detail(definition: Dictionary, owned: Dictionary) -> Control:
	var card := _card()
	card.custom_minimum_size.y = 96.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var heading := Label.new()
	heading.text = _display_item_name(definition) if not definition.is_empty() else tr("Select an item to see its details.")
	heading.add_theme_color_override("font_color", _rarity_color(str(definition.get("rarity", "common"))))
	column.add_child(heading)
	var detail := Label.new()
	if definition.is_empty():
		detail.text = ""
	else:
		detail.text = "%s · %s · %d %s\n%s" % [_slot_name(str(definition.get("slot_type", ""))), _rarity_name(str(definition.get("rarity", "common"))), int(definition.get("shop_price", 0)), tr("coins"), _display_item_description(definition)]
		if owned.has(_selected_shop_item_id):
			detail.text += " · " + tr("Owned")
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 11)
	column.add_child(detail)
	if not definition.is_empty():
		_add_effect_labels(column, definition)
	return card

func _select_shop_item(item_id: String) -> void:
	_selected_shop_item_id = item_id
	_render()

func _build_selected_detail() -> Control:
	var card := _card()
	card.custom_minimum_size.y = 94.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var item := _find_owned_item(_selected_instance_id)
	var label := Label.new()
	label.text = _display_item_name(item.get("definition", {})) if not item.is_empty() else ("%s · %s" % [_slot_name(_selected_empty_slot), tr("Empty slot")] if not _selected_empty_slot.is_empty() else tr("Select an item to see its details."))
	label.add_theme_color_override("font_color", Color("edf3ff"))
	column.add_child(label)
	var description := Label.new()
	if not item.is_empty():
		var definition: Dictionary = item.get("definition", {})
		var equipment: Variant = _state.get("equipment", {})
		var slot := str(definition.get("slot_type", ""))
		var item_instance: Dictionary = item.get("instance", {})
		var is_equipped := equipment is Dictionary and str(equipment.get(slot, "")) == str(item_instance.get("instance_id", ""))
		var equipped_text := " · " + tr("Equipped") if is_equipped else ""
		description.text = "%s · %s%s\n%s" % [_slot_name(slot), _rarity_name(str(definition.get("rarity", "common"))), equipped_text, _display_item_description(definition)]
	else:
		description.text = tr("No item is equipped in this slot.") if not _selected_empty_slot.is_empty() else tr("Items change gameplay only when a supported stat bonus is listed.")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 11)
	column.add_child(description)
	if not item.is_empty():
		_add_effect_labels(column, item.get("definition", {}))
	return card

func _add_effect_labels(parent: Control, definition: Dictionary) -> void:
	var effects := ItemPresentationScript.effects(definition)
	if effects.is_empty():
		var neutral := Label.new()
		neutral.text = tr("No stat bonuses")
		neutral.add_theme_font_size_override("font_size", 10)
		neutral.add_theme_color_override("font_color", Color("b8c7dc"))
		parent.add_child(neutral)
		return
	for effect in effects:
		var effect_label := Label.new()
		effect_label.text = str(effect.text)
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.add_theme_font_size_override("font_size", 10)
		effect_label.add_theme_color_override("font_color", Color("64d879") if bool(effect.beneficial) else Color("ff7b72"))
		parent.add_child(effect_label)

func _select_item(instance_id: String) -> void:
	_selected_instance_id = instance_id
	_selected_empty_slot = ""
	_render()

func _purchase(item_id: String) -> void:
	if _stale or _action_pending or not AuthService.is_authenticated:
		return
	_action_pending = true
	_render()
	InventoryService.purchase(item_id)

func _on_state_changed(state: Dictionary, stale: bool, error_message: String) -> void:
	_state = state.duplicate(true)
	_stale = stale
	_error_message = error_message
	if not _selected_instance_id.is_empty() and _find_owned_item(_selected_instance_id).is_empty():
		_selected_instance_id = ""
	_render()

func _on_action_finished(_action: String, success: bool, message: String, _result: Dictionary) -> void:
	_action_pending = false
	_error_message = ""
	_render()
	_status_label.text = message

func _on_back() -> void:
	queue_free()
	back_requested.emit()

func _add_empty_state(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)

func _catalog_by_id() -> Dictionary:
	var result := {}
	var catalog: Variant = _state.get("catalog", [])
	if catalog is Array:
		for definition in catalog:
			if definition is Dictionary:
				result[str(definition.get("item_id", ""))] = definition
	return result

func _find_owned_item(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var items: Variant = _state.get("items", [])
	if not items is Array:
		return {}
	var definitions := _catalog_by_id()
	for item in items:
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return {"instance": item, "definition": definitions.get(str(item.get("item_id", "")), {})}
	return {}

func _resolve_equipment() -> Dictionary:
	var entries: Array[Dictionary] = []
	var equipped: Variant = _state.get("equipment", {})
	if equipped is Dictionary:
		for slot in equipped:
			var owned := _find_owned_item(str(equipped[slot]))
			if owned.is_empty():
				continue
			var raw: Dictionary = owned.get("definition", {})
			var definition = ItemDefinitionScript.new()
			definition.item_id = str(raw.get("item_id", ""))
			definition.slot_type = str(raw.get("slot_type", ""))
			definition.rarity = str(raw.get("rarity", "common"))
			definition.name_key = str(raw.get("name_key", ""))
			definition.description_key = str(raw.get("description_key", ""))
			definition.icon_key = str(raw.get("icon_key", "unknown"))
			var modifiers: Variant = raw.get("stat_modifiers", {})
			definition.stat_modifiers = modifiers if modifiers is Dictionary else {}
			entries.append({"slot_type": str(slot), "instance_id": str(equipped[slot]), "definition": definition})
	var character_stats: Resource = PlayerProfile.get_character_stats()
	var base_stats: Dictionary = character_stats.call("get_base_stats") if character_stats != null and character_stats.has_method("get_base_stats") else {}
	var result := EquipmentStatsScript.resolve(entries, base_stats)
	if not bool(result.get("valid", false)):
		push_warning("Could not resolve character equipment stats: %s" % ", ".join(result.get("errors", [])))
		return {"totals": base_stats, "bonuses": {}, "errors": result.get("errors", [])}
	return result

func _display_item_name(definition: Dictionary) -> String:
	if definition.is_empty():
		return tr("Nothing equipped")
	return ItemPresentationScript.item_name(definition)

func _display_item_description(definition: Dictionary) -> String:
	return ItemPresentationScript.item_description(definition)

func _slot_name(slot: String) -> String:
	return tr("Helmet") if slot == "helmet" else tr("Boots")

func _rarity_name(rarity: String) -> String:
	return tr(rarity.capitalize())

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon": return Color("64d879")
		"rare": return Color("67a8ff")
		"epic": return Color("c084fc")
		"legendary": return Color("ffb347")
		_: return Color("edf3ff")

func _format_percent_bps(value: int) -> String:
	var percent := snappedf(float(value) / 100.0, 0.1)
	var number := str(percent)
	if number.ends_with(".0"):
		number = number.substr(0, number.length() - 2)
	if TranslationServer.get_locale().begins_with("sv"):
		number = number.replace(".", ",")
	return number + "%"

func _format_modifier_bps(value: int) -> String:
	var result := _format_percent_bps(value)
	return "+" + result if value > 0 else result

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	return card

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("42d6c5")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b2b")
	style.border_color = Color("35455f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

func _empty_cell_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b2b", 0.5)
	style.border_color = Color("35455f", 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func stats_label_add(label: Label, parent: Control) -> void:
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)
