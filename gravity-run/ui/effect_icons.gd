extends RefCounted
class_name EffectIcons
## Small shapes for effect items, drawn in code. Shared by the HUD charge row
## and the inventory icons so both always look alike.

const INK := Color("edf3ff")
const ACCENT := Color("42d6c5")
const READY_COLOR := Color("42d6c5")
const CHARGING_COLOR := Color("f5d45e")
const SLOT_SIZE := 38.0
const SLOT_GAP := 8.0

## Maps an inventory icon key to its effect, or "" for plain items.
static func effect_for_icon_key(icon_key: String) -> String:
	match icon_key:
		"helmet_bubble_01":
			return "bubble_shield"
		"helmet_spikeplate_01":
			return "spike_plate"
		"backpack_magnet_01":
			return "coin_magnet"
		"boots_regret_01":
			return "regret_flip"
		"backpack_anchor_01":
			return "gravity_anchor"
	return ""

## Draws one effect glyph centered on `center`, fitting a square of `size`.
static func draw_glyph(canvas: CanvasItem, effect_id: String, center: Vector2, size: float, ink: Color = INK, accent: Color = ACCENT) -> void:
	var unit := size / 32.0
	match effect_id:
		"bubble_shield":
			canvas.draw_circle(center, 12.0 * unit, Color(accent, 0.18))
			canvas.draw_arc(center, 12.0 * unit, 0.0, TAU, 32, accent, maxf(1.5, 2.0 * unit), true)
			canvas.draw_arc(center, 8.0 * unit, PI * 1.1, PI * 1.55, 10, ink, maxf(1.2, 2.0 * unit), true)
			canvas.draw_circle(center + Vector2(5.0, -6.0) * unit, 1.6 * unit, ink)
		"spike_plate":
			canvas.draw_rect(Rect2(center + Vector2(-12.0, 3.0) * unit, Vector2(24.0, 7.0) * unit), accent)
			for index in range(3):
				var base_x := (-12.0 + float(index) * 8.0) * unit
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2(base_x, 3.0 * unit),
					center + Vector2(base_x + 4.0 * unit, -10.0 * unit),
					center + Vector2(base_x + 8.0 * unit, 3.0 * unit),
				]), ink)
		"coin_magnet":
			var arc_center := center + Vector2(0.0, -1.0) * unit
			canvas.draw_arc(arc_center, 8.0 * unit, PI, TAU, 18, ink, maxf(2.5, 4.5 * unit), true)
			canvas.draw_line(arc_center + Vector2(-8.0, 0.0) * unit, center + Vector2(-8.0, 8.0) * unit, ink, maxf(2.5, 4.5 * unit), true)
			canvas.draw_line(arc_center + Vector2(8.0, 0.0) * unit, center + Vector2(8.0, 8.0) * unit, ink, maxf(2.5, 4.5 * unit), true)
			canvas.draw_line(center + Vector2(-8.0, 6.0) * unit, center + Vector2(-8.0, 11.0) * unit, Color("ff647c"), maxf(2.5, 4.5 * unit), true)
			canvas.draw_line(center + Vector2(8.0, 6.0) * unit, center + Vector2(8.0, 11.0) * unit, accent, maxf(2.5, 4.5 * unit), true)
		"regret_flip":
			# A boot sole with a U-turn arrow over it: up, then back down.
			var turn_width := maxf(2.0, 3.0 * unit)
			canvas.draw_rect(Rect2(center + Vector2(-11.0, 7.0) * unit, Vector2(22.0, 4.0) * unit), accent)
			canvas.draw_line(center + Vector2(-6.0, 3.0) * unit, center + Vector2(-6.0, -6.0) * unit, ink, turn_width)
			canvas.draw_arc(center + Vector2(0.0, -6.0) * unit, 6.0 * unit, PI, TAU, 12, ink, turn_width, true)
			canvas.draw_line(center + Vector2(6.0, -6.0) * unit, center + Vector2(6.0, 1.0) * unit, ink, turn_width)
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(1.0, 0.0) * unit,
				center + Vector2(11.0, 0.0) * unit,
				center + Vector2(6.0, 6.5) * unit,
			]), ink)
		"gravity_anchor":
			# A ring, a shank and flukes, with a dashed middle line behind it.
			var anchor_width := maxf(2.0, 3.0 * unit)
			for dash in range(4):
				var dash_x := (-14.0 + float(dash) * 8.0) * unit
				canvas.draw_line(center + Vector2(dash_x, 0.0), center + Vector2(dash_x + 4.0 * unit, 0.0), accent, maxf(1.5, 2.0 * unit))
			canvas.draw_arc(center + Vector2(0.0, -9.0) * unit, 3.0 * unit, 0.0, TAU, 14, ink, anchor_width * 0.8, true)
			canvas.draw_line(center + Vector2(0.0, -6.0) * unit, center + Vector2(0.0, 9.0) * unit, ink, anchor_width)
			canvas.draw_line(center + Vector2(-5.0, -2.0) * unit, center + Vector2(5.0, -2.0) * unit, ink, anchor_width)
			canvas.draw_arc(center + Vector2(0.0, 3.0) * unit, 9.0 * unit, 0.1 * PI, 0.9 * PI, 14, ink, anchor_width, true)
		"ice_picks":
			# Two crossed picks.
			var pick_width := maxf(2.0, 3.0 * unit)
			canvas.draw_line(center + Vector2(-9.0, 9.0) * unit, center + Vector2(7.0, -7.0) * unit, ink, pick_width)
			canvas.draw_line(center + Vector2(9.0, 9.0) * unit, center + Vector2(-7.0, -7.0) * unit, ink, pick_width)
			canvas.draw_line(center + Vector2(3.0, -10.0) * unit, center + Vector2(11.0, -4.0) * unit, Color("8fb4ff"), pick_width)
			canvas.draw_line(center + Vector2(-3.0, -10.0) * unit, center + Vector2(-11.0, -4.0) * unit, Color("8fb4ff"), pick_width)
		"lantern":
			# A lantern with a warm flame.
			canvas.draw_arc(center + Vector2(0.0, -10.0) * unit, 3.0 * unit, PI, TAU, 10, ink, maxf(1.5, 2.0 * unit), true)
			canvas.draw_rect(Rect2(center + Vector2(-6.0, -7.0) * unit, Vector2(12.0, 16.0) * unit), ink, false, maxf(1.5, 2.0 * unit))
			canvas.draw_circle(center + Vector2(0.0, 1.0) * unit, 3.5 * unit, Color("ffd46a"))
		"heat_shield":
			# A shield with a flame on it.
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-9.0, -9.0) * unit, center + Vector2(9.0, -9.0) * unit, center + Vector2(8.0, 3.0) * unit, center + Vector2(0.0, 11.0) * unit, center + Vector2(-8.0, 3.0) * unit]), ink)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -6.0) * unit, center + Vector2(4.0, 2.0) * unit, center + Vector2(0.0, 6.0) * unit, center + Vector2(-4.0, 2.0) * unit]), Color("ff814f"))
		_:
			canvas.draw_rect(Rect2(center - Vector2(8.0, 8.0) * unit * unit, Vector2(16.0, 16.0) * unit), Color("8292aa"), false, 2.0)

## Draws a HUD slot for an entry of RunEffects.get_hud_entries(): a dark tile,
## a meter that fills from the bottom while the item recharges, the glyph, and a
## bright border once it is ready.
static func draw_slot(canvas: CanvasItem, rect: Rect2, entry: Dictionary) -> void:
	var charge := clampf(float(entry.get("charge", 1.0)), 0.0, 1.0)
	var ready := bool(entry.get("ready", true))
	var active := bool(entry.get("active", false))
	canvas.draw_rect(rect, Color("101827", 0.82))
	var fill_color := READY_COLOR if ready else CHARGING_COLOR
	var fill_height := rect.size.y * charge
	canvas.draw_rect(Rect2(rect.position.x, rect.end.y - fill_height, rect.size.x, fill_height), Color(fill_color, 0.38))
	var glyph_ink := INK if ready else Color(INK, 0.55)
	draw_glyph(canvas, str(entry.get("effect_id", "")), rect.get_center(), rect.size.x * 0.78, glyph_ink, fill_color)
	var border := Color("f4f7ff") if active else (READY_COLOR if ready else Color("718098"))
	canvas.draw_rect(rect, border, false, 3.0 if active else 2.0)
