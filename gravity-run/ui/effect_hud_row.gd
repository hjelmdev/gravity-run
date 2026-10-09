extends Control
class_name EffectHudRow
## Row of effect item meters (bubble helmet, spike plate, ...) for scenes that
## own their HUD layout, such as the multiplayer race. Draws the same slots as
## the singleplayer HUD through EffectIcons.

var _entries: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(EffectIcons.SLOT_SIZE, EffectIcons.SLOT_SIZE)

## Entries come from RunEffects.get_hud_entries(). An empty list hides the row.
func set_entries(entries: Array[Dictionary]) -> void:
	if entries.is_empty() and _entries.is_empty():
		return
	_entries = entries
	queue_redraw()

func entry_count() -> int:
	return _entries.size()

func _draw() -> void:
	var x := 0.0
	for entry in _entries:
		EffectIcons.draw_slot(self, Rect2(x, 0.0, EffectIcons.SLOT_SIZE, EffectIcons.SLOT_SIZE), entry)
		x += EffectIcons.SLOT_SIZE + EffectIcons.SLOT_GAP
