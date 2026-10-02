extends RefCounted
class_name MultiplayerV2HudLayout

static func for_viewport(size: Vector2) -> Dictionary:
	var margin := clampf(minf(size.x, size.y) * 0.035, 14.0, 36.0)
	var button_width := clampf(size.x * 0.24, 96.0, 136.0)
	var status_width := minf(440.0, maxf(size.x - 2.0 * margin - button_width - 64.0, 0.0))
	var panel_width := minf(360.0, maxf(size.x - 2.0 * margin, 120.0))
	var panel_height := minf(220.0, maxf(size.y - 2.0 * margin - 56.0, 110.0))
	var button := Rect2(size.x - margin - button_width, margin, button_width, 42.0)
	var music_control_x := button.position.x - 48.0
	var status_right := music_control_x - 30.0 - 12.0
	status_width = minf(status_width, maxf(status_right - margin, 0.0))
	return {"margin": margin, "button": button, "music_button": Rect2(music_control_x, margin, 64.0, 42.0), "coin_count": Rect2(margin, margin + 70.0, minf(112.0, size.x - margin * 2.0), 30.0), "status": Rect2(margin, margin + 34.0, status_width, 30.0), "panel": Rect2(size.x - margin - panel_width, margin + 50.0, panel_width, panel_height)}
