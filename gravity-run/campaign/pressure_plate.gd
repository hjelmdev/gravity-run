extends Node2D
## Rullaren's weak point: a glowing plate on the floor or ceiling. Running over
## it on that side sends a bolt back to the machine.

var on_ceiling := false
var surface_y := 460.0
var width := 150.0
var state := "armed"
var _time := 0.0
var _state_time := 0.0

func _ready() -> void:
	z_index = 1

func set_state(new_state: String) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_state_time += delta
	queue_redraw()

func _draw() -> void:
	var side := -1.0 if not on_ceiling else 1.0
	var plate_height := 10.0 if state != "hit" else 5.0
	var top := surface_y if on_ceiling else surface_y - plate_height
	var body := Rect2(Vector2(-width * 0.5, top), Vector2(width, plate_height))
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var glow := Color("42d6c5")
	match state:
		"hit":
			glow = Color("f5d45e")
		"missed":
			glow = Color("6c7488")
	if state == "armed":
		# A beam of light shows from far away which side the plate is on.
		var beam := glow
		beam.a = 0.10 + 0.08 * pulse
		var beam_top := surface_y + side * 150.0
		draw_rect(Rect2(Vector2(-width * 0.5 + 10.0, minf(beam_top, surface_y)), Vector2(width - 20.0, 150.0)), beam)
		for i in range(3):
			var chevron_y := surface_y + side * (40.0 + float(i) * 34.0 + fmod(_time * 60.0, 34.0))
			var c := glow
			c.a = 0.55
			draw_polyline(PackedVector2Array([Vector2(-16, chevron_y + side * 10.0), Vector2(0, chevron_y), Vector2(16, chevron_y + side * 10.0)]), c, 4.0)
	draw_rect(body.grow(3.0), Color("14141c"))
	draw_rect(body, Color("3a4458"))
	var light := glow
	light.a = 0.75 + 0.25 * pulse if state == "armed" else 1.0
	draw_rect(Rect2(body.position + Vector2(8.0, 3.0 if not on_ceiling else 2.0), Vector2(width - 16.0, maxf(plate_height - 6.0, 2.0))), light)
	if state == "hit" and _state_time < 0.8:
		var ring := Color("f5d45e")
		ring.a = 1.0 - _state_time / 0.8
		draw_arc(Vector2(0.0, surface_y), 20.0 + _state_time * 140.0, PI if not on_ceiling else 0.0, TAU if not on_ceiling else PI, 24, ring, 4.0)
