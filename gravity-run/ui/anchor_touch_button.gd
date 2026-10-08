extends Control
## On-screen button for the gravity anchor. Only visible while the item is
## equipped; draws the same charge tile as the HUD effect row, just bigger.

signal pressed

const BUTTON_SIZE := 76.0
const MARGIN := 18.0

var entry: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -(BUTTON_SIZE + MARGIN)
	offset_top = -(BUTTON_SIZE + MARGIN)
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	tooltip_text = tr("Use gravity anchor")
	accessibility_name = tr("Use gravity anchor")
	visible = false

func set_entry(new_entry: Dictionary) -> void:
	entry = new_entry
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var touched: bool = event is InputEventScreenTouch and event.pressed
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if touched or clicked:
		pressed.emit()
		accept_event()

func _draw() -> void:
	if entry.is_empty():
		return
	EffectIcons.draw_slot(self, Rect2(Vector2.ZERO, size), entry)
