extends Control
## Small badge for the campaign banner, in the pixel UI: a sunken slot with a
## warning sign (new hazard), a gravity star, a finish flag (stage) or a boss
## face. `accent` is kept for callers; the pixel icons carry their own colours.

var kind := "hazard"
var accent := Color("ff9f43")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(PixelUi.panel_box("inset", Vector2(4, 4)), rect)
	match kind:
		"star":
			PixelUi.draw_icon(self, "star", rect.grow(-8.0))
		"stage":
			PixelUi.draw_icon(self, "flag", rect.grow(-10.0))
		"boss":
			PixelUi.draw_icon(self, "boss", rect.grow(-10.0))
		_:
			var side := floorf(minf(size.x, size.y) - 12.0)
			draw_texture_rect(_sign_texture(), Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)

static var _signs: Dictionary = {}

func _sign_texture() -> Texture2D:
	var key := accent.to_html()
	if not _signs.has(key):
		var wrapped := CanvasTexture.new()
		wrapped.diffuse_texture = ImageTexture.create_from_image(RockWarningIcon.make_sign(accent))
		wrapped.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_signs[key] = wrapped
	return _signs[key]
