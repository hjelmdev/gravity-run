extends Control
## A toolbar icon (shop, inventory, music on/off, coin) drawn from the pixel UI
## (PixelUi icons), centred and as large as fits in whole pixel steps.

@export var icon_name := "inventory"
@export var music_enabled := true

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pixel_ui := get_node_or_null("/root/PixelUi")
	if pixel_ui != null:
		pixel_ui.style_changed.connect(func(_style: String) -> void: queue_redraw())

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if icon_name == "coin":
		var coin := PixelCoin.frame_texture(0)
		var side := minf(size.x, size.y)
		draw_texture_rect(coin, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)
		return
	var pixel_ui := get_node_or_null("/root/PixelUi")
	if pixel_ui == null:
		return
	var name := icon_name
	if icon_name == "music":
		name = "music" if music_enabled else "music_off"
	pixel_ui.call("draw_icon", self, name, rect.grow(-2.0))
