extends Node2D
class_name GhostHazard

const Model := preload("res://systems/ghost_hazard_model.gd")
const TEXTURE: Texture2D = preload("res://hazards/ghost.svg")
const SKINS: Array[Texture2D] = [
	TEXTURE,
	preload("res://hazards/ghost_wisp.svg"),
	preload("res://hazards/ghost_grim.svg"),
]

signal phase_changed(event_id: String, phase: String)

var event: Dictionary = {}
var activation_tick := -1
var activation_state: Dictionary = {}
var simulation_tick := 0
var phase := Model.DORMANT
var _presentation_tick := 0.0
var _presentation_phase := Model.DORMANT
var _visual_time := 0.0
var skin_variant := 0

func _process(delta: float) -> void:
	if visible:
		_visual_time = fmod(_visual_time + delta, 60.0)
		queue_redraw()

## Cosmetic motion only: the node and tick-authoritative hitbox stay anchored.
func visual_offset() -> Vector2:
	return Vector2(sin(_visual_time * TAU / 4.0) * 3.0, sin(_visual_time * TAU / 2.8) * 5.0)

func configure(value: Dictionary) -> void:
	# The shared renderer samples this node explicitly in SP and MP. Disable
	# engine transform interpolation here so the same pose is never interpolated twice.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	event = value.duplicate(true)
	activation_tick = -1
	activation_state.clear()
	simulation_tick = 0
	phase = Model.DORMANT
	_presentation_tick = 0.0
	_presentation_phase = Model.DORMANT
	_visual_time = 0.0
	skin_variant = clampi(int(event.get("skin_variant", 0)), 0, SKINS.size() - 1)
	global_position = Model.center(event)
	name = "Ghost_%s" % str(event.get("event_id", "ghost"))
	add_to_group("ghost_hazards")
	_update_phase()

func set_activation_tick(value: int) -> void:
	if activation_tick >= 0:
		return
	activation_tick = maxi(value, 0)
	_update_phase()

func set_activation_snapshot(value: Dictionary) -> void:
	if activation_tick >= 0 or int(event.get("ghost_variant", 0)) not in [2, 3]:
		return
	var lane := int(value.get("lane", 0))
	var world_x := float(value.get("world_x", NAN))
	var speed := float(value.get("speed", NAN))
	var target_peer_id := int(value.get("target_peer_id", 0))
	var tick := int(value.get("activation_tick", -1))
	if lane not in [1, 2] or not is_finite(world_x) or world_x < 0.0 or not is_finite(speed) or speed < 200.0 or speed > 800.0 or target_peer_id <= 0 or tick < 0:
		return
	activation_state = {"lane": lane, "world_x": world_x, "speed": speed, "target_peer_id": target_peer_id}
	activation_tick = tick
	_update_phase()

func set_simulation_tick(value: int) -> void:
	var next_tick := maxi(value, 0)
	if next_tick < simulation_tick:
		return
	simulation_tick = next_tick
	global_position = Model.center_for_activation(event, activation_tick, simulation_tick, activation_state)
	_update_phase()

## Moves only the rendered node. The authoritative simulation tick and hitbox
## remain integer-tick based for collision, replay and ledger decisions.
func set_presentation_tick(value: float) -> void:
	if not is_finite(value):
		return
	var variant := int(event.get("ghost_variant", 0))
	if variant not in [1, 2, 3]:
		_presentation_tick = float(simulation_tick)
		_presentation_phase = phase
		global_position = Model.center_for_activation(event, activation_tick, _presentation_tick, activation_state)
		visible = phase not in [Model.DORMANT, Model.EXPIRED]
		return
	_presentation_tick = maxf(value, 0.0)
	_presentation_phase = Model.presentation_phase_at(event, activation_tick, _presentation_tick)
	global_position = Model.center_for_activation(event, activation_tick, _presentation_tick, activation_state)
	visible = _presentation_phase not in [Model.DORMANT, Model.EXPIRED]

func apply_world_state(value: Dictionary) -> void:
	var incoming: Variant = value.get("state", value)
	if not incoming is Dictionary:
		return
	var next_activation := int(incoming.get("activation_tick", activation_tick))
	var next_tick := int(incoming.get("tick", simulation_tick))
	if activation_tick >= 0 and next_activation != activation_tick:
		return
	if next_tick < simulation_tick:
		return
	var next_activation_state := activation_state.duplicate(true)
	if int(event.get("ghost_variant", 0)) in [2, 3]:
		if next_activation >= 0:
			var lane_value: Variant = incoming.get("lane", null)
			var world_x_value: Variant = incoming.get("world_x", null)
			var speed_value: Variant = incoming.get("speed", null)
			var peer_value: Variant = incoming.get("target_peer_id", null)
			if not lane_value is int or int(lane_value) not in [1, 2] or not (world_x_value is int or world_x_value is float) or not is_finite(float(world_x_value)) or float(world_x_value) < 0.0 or not (speed_value is int or speed_value is float) or not is_finite(float(speed_value)) or float(speed_value) < 200.0 or float(speed_value) > 800.0 or not peer_value is int or int(peer_value) <= 0:
				return
			var candidate := {"lane": int(lane_value), "world_x": float(world_x_value), "speed": float(speed_value), "target_peer_id": int(peer_value)}
			if activation_tick >= 0 and (candidate.lane != int(activation_state.get("lane", 0)) or not is_equal_approx(candidate.world_x, float(activation_state.get("world_x", -1.0))) or not is_equal_approx(candidate.speed, float(activation_state.get("speed", 0.0))) or candidate.target_peer_id != int(activation_state.get("target_peer_id", 0))):
				return
			next_activation_state = candidate
	if activation_tick < 0 and next_activation >= 0:
		activation_tick = next_activation
	activation_state = next_activation_state
	simulation_tick = next_tick
	global_position = Model.center_for_activation(event, activation_tick, simulation_tick, activation_state)
	_update_phase()
	if incoming.has("render_tick") and (incoming.render_tick is int or incoming.render_tick is float):
		set_presentation_tick(float(incoming.render_tick))
	else:
		set_presentation_tick(float(simulation_tick))

func _update_phase() -> void:
	var next_phase := Model.phase_at(event, activation_tick, simulation_tick)
	if phase != next_phase:
		phase = next_phase
		phase_changed.emit(str(event.get("event_id", "")), phase)
		queue_redraw()
	visible = phase not in [Model.DORMANT, Model.EXPIRED]
	_presentation_tick = float(simulation_tick)
	_presentation_phase = phase
	global_position = Model.center_for_activation(event, activation_tick, simulation_tick, activation_state)

func get_hitbox_rect() -> Rect2:
	return Model.hitbox(event, simulation_tick, activation_tick, activation_state)

func swept_contact_fraction(start_rect: Rect2, finish_rect: Rect2, start_tick: int, end_tick: int, body_size: Vector2) -> float:
	return Model.swept_contact_fraction(event, activation_tick, start_tick, end_tick, start_rect.get_center(), finish_rect.get_center(), body_size, activation_state)

func is_destroying_now() -> bool:
	return phase == Model.EXPIRED

func _draw() -> void:
	var draw_phase := _presentation_phase if int(event.get("ghost_variant", 0)) in [1, 2, 3] else phase
	if draw_phase in [Model.DORMANT, Model.EXPIRED]:
		return
	var size := Vector2(float(event.get("width", 72.0)), float(event.get("height", 96.0)))
	var tint := Color("d6e3ff", 0.58)
	if draw_phase == Model.DANGEROUS:
		tint = Color("f0f5ff", 0.98)
	elif draw_phase == Model.FADING:
		tint = Color("bdc9e3", 0.28)
	draw_set_transform(visual_offset(), sin(_visual_time * TAU / 4.0) * 0.025)
	draw_texture_rect(SKINS[skin_variant], Rect2(-size * 0.5, size), false, tint)
	draw_set_transform(Vector2.ZERO)
	if draw_phase == Model.WARNING:
		var pulse := 0.65 + 0.25 * sin(fposmod(_presentation_tick, 24.0) * TAU / 24.0)
		var radius := maxf(size.x, size.y) * 0.58
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color("c7a9ff", pulse), 2.0, true)
