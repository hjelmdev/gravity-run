extends Node2D
## Local-only visual fixture for the versioned shared saw variants.

const SawScene := preload("res://hazards/saw_blade.tscn")
const SawModel := preload("res://systems/saw_blade_model.gd")

var _saws: Array[Node2D] = []
var _fit_portrait := false

func _ready() -> void:
	var viewport_size := get_viewport_rect().size
	_fit_portrait = viewport_size.x < viewport_size.y
	if _fit_portrait:
		var camera := Camera2D.new()
		camera.position = Vector2(640.0, 360.0)
		var fit_zoom := viewport_size.x / 1280.0
		camera.zoom = Vector2.ONE * fit_zoom
		camera.enabled = true
		add_child(camera)
	_add_saw("floor_embedded", 280.0, 440.0, 180.0, false, 12)
	_add_saw("ceiling_embedded", 640.0, 440.0, 180.0, false, 12)
	_add_saw("ceiling_gap_drop", 1000.0, 440.0, 180.0, true, 38)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var size := Vector2(1280.0, 720.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("101923"))
	draw_rect(Rect2(0.0, 0.0, 900.0, 180.0), Color("36424d"))
	draw_rect(Rect2(980.0, 0.0, size.x - 980.0, 180.0), Color("36424d"))
	draw_rect(Rect2(0.0, 180.0, size.x, 12.0), Color("36424d"))
	draw_rect(Rect2(0.0, 440.0, size.x, size.y - 440.0), Color("36424d"))
	draw_line(Vector2(0.0, 180.0), Vector2(900.0, 180.0), Color("8b9aa6"), 3.0)
	draw_line(Vector2(980.0, 180.0), Vector2(size.x, 180.0), Color("8b9aa6"), 3.0)
	draw_line(Vector2(0.0, 440.0), Vector2(size.x, 440.0), Color("8b9aa6"), 3.0)
	for index in range(3):
		var x := 108.0 + float(index) * 360.0
		draw_string(ThemeDB.fallback_font, Vector2(x, 78.0), ["FLOOR EMBEDDED", "CEILING EMBEDDED", "GAP DROP / FALLING"][index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color("e6edf3"))
	draw_string(ThemeDB.fallback_font, Vector2(914.0, 172.0), "ROOF GAP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("e9a34d"))

func _add_saw(variant: String, spawn_x: float, floor_y: float, ceiling_y: float, has_gap: bool, target_tick: int) -> void:
	var event_x := spawn_x - 1100.0
	var event := {
		"event_id": "saw-showcase-%s" % variant,
		"saw_variant": variant,
		"saw_radius": 34.0,
		"from_ceiling": variant != "floor_embedded",
		"x": event_x,
		"spawn_x": spawn_x,
		"floor_y": floor_y,
		"ceiling_y": ceiling_y,
	}
	var support := {"floor_y": floor_y, "ceiling_y": ceiling_y, "gap_start": -INF, "gap_end": -INF}
	if has_gap:
		event["roof_gap_x"] = event_x + SawModel.V10_DROP_ROOF_GAP_OFFSET
		event["roof_gap_width"] = SawModel.V10_DROP_ROOF_GAP_WIDTH
		support.gap_start = float(event.roof_gap_x)
		support.gap_end = float(event.roof_gap_x) + float(event.roof_gap_width)
	var saw := SawScene.instantiate() as Node2D
	add_child(saw)
	saw.call("configure", event, Callable(self, "_surface_at").bind(support), 0.0, 0)
	saw.call("set_activation_tick", 12)
	for tick in range(1, target_tick + 1):
		saw.call("set_simulation_tick", tick)
	_saws.append(saw)

func _surface_at(x: float, ceiling: bool, support: Dictionary) -> Dictionary:
	if ceiling and x >= float(support.gap_start) and x <= float(support.gap_end):
		return {"y": float(support.ceiling_y), "supported": false}
	return {"y": float(support.ceiling_y) if ceiling else float(support.floor_y), "supported": true}
