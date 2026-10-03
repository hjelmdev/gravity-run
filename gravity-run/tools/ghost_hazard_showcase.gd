extends Node2D

const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const GhostWarningPulseScript := preload("res://systems/ghost_warning_pulse.gd")

var _layout_height := 540.0
var _warning_pulse: RefCounted = GhostWarningPulseScript.new()

func _ready() -> void:
	var view := get_viewport_rect().size
	_layout_height = minf(view.y, 540.0)
	var floor_y := _layout_height - 78.0
	var ceiling_y := 72.0
	_warning_pulse.call("observe_warning", "showcase_floor_warning", false)
	_warning_pulse.call("observe_warning", "showcase_ceiling_warning", true)
	_warning_pulse.call("advance", 0.32)
	var samples := [
		{"name": "VARNING", "tick": 0, "x_ratio": 0.2},
		{"name": "FARLIG", "tick": 120, "x_ratio": 0.5},
		{"name": "AVKLANGNING", "tick": 480, "x_ratio": 0.8},
	]
	for index in range(samples.size()):
		var sample: Dictionary = samples[index]
		var event := {
			"event_id": "showcase_%d" % index,
			"x": view.x * float(sample.x_ratio),
			"width": 94.0,
			"height": 120.0,
			"floor_y": floor_y,
			"ceiling_y": ceiling_y,
			"from_ceiling": index == 1,
			"warning_ticks": 120,
			"danger_ticks": 360,
			"fade_ticks": 45,
		}
		var ghost: Node2D = GhostScene.instantiate()
		add_child(ghost)
		ghost.call("configure", event)
		ghost.call("set_activation_tick", 0)
		ghost.call("set_simulation_tick", int(sample.tick))
		print("GHOST_SHOWCASE_PHASE id=%s phase=%s pos=%s visible=%s" % [str(sample.name), str(ghost.get("phase")), str(ghost.global_position), str(ghost.visible)])
		var caption := Label.new()
		caption.text = str(sample.name)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(view.x * float(sample.x_ratio) - 85.0, floor_y + 24.0)
		caption.size = Vector2(170.0, 28.0)
		caption.modulate = Color("e5e9f5")
		add_child(caption)
	queue_redraw()

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color("101421"), true)
	var floor_y := _layout_height - 78.0
	var ceiling_y := 72.0
	draw_rect(Rect2(0.0, 0.0, view.x, ceiling_y), Color("1b2235"), true)
	draw_rect(Rect2(0.0, floor_y, view.x, maxf(view.y - floor_y, 0.0)), Color("1b2235"), true)
	draw_line(Vector2(0.0, ceiling_y), Vector2(view.x, ceiling_y), Color("56617a"), 2.0)
	draw_line(Vector2(0.0, floor_y), Vector2(view.x, floor_y), Color("56617a"), 2.0)
	_warning_pulse.call("draw", self, Vector2(view.x * 0.5, _layout_height * 0.5))
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(16.0, 28.0), "SHARED GHOST HAZARD · SP + MP TICK MODEL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color("c9d2e7"))
