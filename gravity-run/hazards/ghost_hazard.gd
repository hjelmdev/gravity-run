extends Node2D
class_name GhostHazard

const Model := preload("res://systems/ghost_hazard_model.gd")
const TEXTURE: Texture2D = preload("res://hazards/ghost.svg")

signal phase_changed(event_id: String, phase: String)

var event: Dictionary = {}
var activation_tick := -1
var simulation_tick := 0
var phase := Model.DORMANT

func configure(value: Dictionary) -> void:
	event = value.duplicate(true)
	activation_tick = -1
	simulation_tick = 0
	phase = Model.DORMANT
	global_position = Model.center(event)
	name = "Ghost_%s" % str(event.get("event_id", "ghost"))
	add_to_group("ghost_hazards")
	_update_phase()

func set_activation_tick(value: int) -> void:
	if activation_tick >= 0:
		return
	activation_tick = maxi(value, 0)
	_update_phase()

func set_simulation_tick(value: int) -> void:
	var next_tick := maxi(value, 0)
	if next_tick < simulation_tick:
		return
	simulation_tick = next_tick
	_update_phase()

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
	if activation_tick < 0 and next_activation >= 0:
		activation_tick = next_activation
	simulation_tick = next_tick
	_update_phase()

func _update_phase() -> void:
	var next_phase := Model.phase_at(event, activation_tick, simulation_tick)
	if phase != next_phase:
		phase = next_phase
		phase_changed.emit(str(event.get("event_id", "")), phase)
		queue_redraw()
	visible = phase not in [Model.DORMANT, Model.EXPIRED]

func get_hitbox_rect() -> Rect2:
	return Model.hitbox(event, simulation_tick, activation_tick)

func is_destroying_now() -> bool:
	return phase == Model.EXPIRED

func _draw() -> void:
	if phase in [Model.DORMANT, Model.EXPIRED]:
		return
	var size := Vector2(float(event.get("width", 72.0)), float(event.get("height", 96.0)))
	var tint := Color("d6e3ff", 0.58)
	if phase == Model.DANGEROUS:
		tint = Color("f0f5ff", 0.98)
	elif phase == Model.FADING:
		tint = Color("bdc9e3", 0.28)
	draw_texture_rect(TEXTURE, Rect2(-size * 0.5, size), false, tint)
	if phase == Model.WARNING:
		var pulse := 0.65 + 0.25 * sin(float(simulation_tick % 24) * TAU / 24.0)
		var radius := maxf(size.x, size.y) * 0.58
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color("c7a9ff", pulse), 2.0, true)
