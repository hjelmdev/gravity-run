extends Control
## The small down chevron of the toolbar, from the pixel UI icons.

func _draw() -> void:
	var pixel_ui := get_node_or_null("/root/PixelUi")
	if pixel_ui != null:
		pixel_ui.call("draw_icon", self, "chevron", Rect2(Vector2.ZERO, size).grow(-4.0))
