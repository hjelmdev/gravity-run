extends SceneTree
const Rules := preload("res://systems/hazard_interaction_rules.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Builder := preload("res://systems/course_manifest_builder.gd")
var failures := 0

func _initialize() -> void:
	var polygon := PackedVector2Array([Vector2(100, 300), Vector2(148, 300), Vector2(148, 460), Vector2(100, 460)])
	for speed in [475.0, 500.0, 507.35, 525.0]:
		var start := Vector2(82, 438)
		var fraction := Rules.swept_rect_polygon_fraction(Rect2(start - Vector2(17, 22), Vector2(34, 44)), Vector2(speed / 60.0, 0), polygon)
		_check(absf(start.x + fraction * speed / 60.0 + 17.0 - 100.0) < 0.001, "block first contact at actual edge for variable speed")
	_check(Rules.swept_rect_polygon_fraction(Rect2(0, 0, 34, 44), Vector2(300, 0), polygon) < 0, "unrelated y path remains safe")
	var thin := PackedVector2Array([Vector2(100, 0), Vector2(101, 0), Vector2(101, 60), Vector2(100, 60)])
	_check(Rules.swept_rect_polygon_fraction(Rect2(0, 0, 34, 44), Vector2(200, 0), thin) >= 0, "sweep catches thin block even when final pose is beyond it")
	var built: Dictionary = Builder.new().build(1260459445, 45000, 4)
	var world := World.new()
	_check(world.configure(built.manifest).is_empty(), "world fixture initializes")
	# Replace events after valid configuration and supply matching entity ledger.
	world.manifest.events.assign([{"event_id": "fixture-block", "kind": "block", "x": 124.0, "y": 460.0, "width": 48.0, "height": 160.0}])
	world.entity_ledger.reset([{"entity_id": "fixture-block", "kind": "block", "health": 1, "incarnation": 1}])
	var previous := {"world_x": 82.0, "y": 438.0, "gravity_direction": 1}
	var proposed := {"world_x": 90.333333, "y": 438.0, "gravity_direction": 1}
	var contact := world.first_static_terminal_contact(previous, proposed)
	_check(not contact.is_empty() and absf(float(contact.get("world_x", 0)) - 83.0) < 0.001, "world returns the first terminal pose, not penetrated final pose")
	_check(float(proposed.world_x) == 90.333333, "contact query does not mutate authoritative candidate")
	var above := world.first_static_terminal_contact({"world_x": 124.0, "y": 275.0}, {"world_x": 124.0, "y": 290.0})
	_check(not above.is_empty() and absf(float(above.y) - 278.0) < 0.001, "vertical entry clamps to block top")
	var below := world.first_static_terminal_contact({"world_x": 124.0, "y": 485.0}, {"world_x": 124.0, "y": 470.0})
	_check(not below.is_empty() and absf(float(below.y) - 482.0) < 0.001, "flipped vertical entry clamps to block underside")
	world.manifest.events.assign([{"event_id": "spikes", "kind": "spikes", "start_x": 100.0, "y": 460.0, "count": 1}])
	var spike := world.first_static_terminal_contact(previous, proposed)
	_check(not spike.is_empty() and spike.reason == "spikes", "triangle contact participates in same first-contact query")
	if not failures:
		print("V2 terminal contact tests passed.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
