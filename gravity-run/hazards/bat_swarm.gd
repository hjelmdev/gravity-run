extends "res://hazards/hazard.gd"
class_name BatSwarm
## Campaign cave hazard (scripted feature "bat_swarm"): a flapping swarm that
## roosts in one lane, rustles when the runner gets close and then sweeps toward
## the runner along that lane. The hitbox is the swarm's rectangle, so the
## runner on the other surface is safe. Everything is driven by the distance the
## runner covers, not by wall time, so a given run is the same every time.
##   roost   hangs still, dimly visible ahead
##   warning shadow on the lane, a "!" sign, the swarm rustles (squeak cue)
##   flying  slides toward the runner at FLY_FACTOR x the runner's own movement

signal warning_started(swarm: BatSwarm)

const TRIGGER_DISTANCE := 520.0
const WARNING_DISTANCE := 180.0
const FLY_FACTOR := 0.6
const BAT_COUNT := 11
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var phase := "roost"
var trigger_distance := TRIGGER_DISTANCE
var event: Dictionary = {}
## Hitbox at the start of the current physics step (for the swept test).
var step_start_rect := Rect2()
var _warning_start_x := INF
var _flap := 0.0
var _bats: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	set_process(true)

## world_x is the roost's centre; surface_y the lane's surface there.
func configure_swarm(value: Dictionary, world_x: float, surface_y: float) -> void:
	event = value.duplicate(true)
	size = Vector2(float(event.get("width", 300.0)), float(event.get("height", 84.0)))
	from_ceiling = bool(event.get("from_ceiling", false))
	trigger_distance = float(event.get("trigger_distance", TRIGGER_DISTANCE))
	position = Vector2(world_x, surface_y)
	_build_bats()
	add_to_group("bat_swarms")
	step_start_rect = get_hitbox_rect()

func _build_bats() -> void:
	_bats.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(event.get("course_distance", 0.0)) * 10.0) + 7
	for index in range(BAT_COUNT):
		_bats.append({
			"x": rng.randf_range(-0.42, 0.42) * size.x,
			"y": rng.randf_range(0.18, 0.82) * size.y,
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.8, 1.3),
			"scale": rng.randf_range(0.9, 1.3),
		})

func get_phase() -> String:
	return phase

func advance_motion(_delta: float, movement: float, player_position: Vector2, _floor_y_at: Callable, _surface_angle_at: Callable, _surface_supported_at: Callable = Callable()) -> void:
	step_start_rect = get_hitbox_rect()
	var runner_x := player_position.x
	match phase:
		"roost":
			if runner_x >= position.x - trigger_distance:
				phase = "warning"
				_warning_start_x = runner_x
				warning_started.emit(self)
		"warning":
			if runner_x - _warning_start_x >= WARNING_DISTANCE:
				phase = "flying"
		"flying":
			position.x -= maxf(movement, 0.0) * FLY_FACTOR

## Fraction 0..1 of the step in which a runner moving from start_rect to
## finish_rect first touches the swarm, which itself moved during the step.
## -1 when there is no contact.
func swept_contact_fraction(start_rect: Rect2, finish_rect: Rect2) -> float:
	var target := get_hitbox_rect()
	var swarm_move := target.position - step_start_rect.position
	var relative := (finish_rect.position - start_rect.position) - swarm_move
	var polygon := PackedVector2Array([step_start_rect.position, Vector2(step_start_rect.end.x, step_start_rect.position.y), step_start_rect.end, Vector2(step_start_rect.position.x, step_start_rect.end.y)])
	return HazardRules.swept_rect_polygon_fraction(start_rect, relative, polygon)

func _process(delta: float) -> void:
	if is_destroying:
		super._process(delta)
		return
	_flap += delta
	queue_redraw()

func _draw() -> void:
	var lane_sign := 1.0 if from_ceiling else -1.0
	var top := 0.0 if from_ceiling else -size.y
	if phase == "warning" or phase == "flying":
		_draw_shadow(top)
	var rustle := 2.5 if phase == "warning" else 0.0
	var speed := 1.0 if phase == "roost" else (1.8 if phase == "warning" else 2.6)
	var alpha := 0.55 if phase == "roost" else 1.0
	for bat in _bats:
		var flap := sin(_flap * 16.0 * speed * float(bat.speed) + float(bat.phase))
		var wobble := Vector2(sin(_flap * 5.0 * float(bat.speed) + float(bat.phase)) * 6.0, cos(_flap * 4.0 + float(bat.phase)) * 5.0)
		if phase == "roost":
			wobble = Vector2.ZERO
			flap = 0.35
		var center := Vector2(float(bat.x), top + float(bat.y)) + wobble
		center.x += rustle * sin(_flap * 40.0 + float(bat.phase))
		_draw_bat(center, float(bat.scale), flap, alpha, lane_sign)
	if phase == "warning":
		var sign_center := Vector2(0.0, top + size.y * 0.5 + (size.y * 0.5 + 40.0) * (1.0 if from_ceiling else -1.0))
		var pulse := 0.65 + 0.35 * sin(_flap * 18.0)
		_draw_warning_sign(sign_center, 44.0, pulse)

## A triangular "!" sign in the swarm's purple.
func _draw_warning_sign(center: Vector2, sign_size: float, opacity: float) -> void:
	var half := sign_size * 0.5
	var triangle := PackedVector2Array([center + Vector2(0.0, -half), center + Vector2(half * 0.88, half * 0.55), center + Vector2(-half * 0.88, half * 0.55)])
	draw_colored_polygon(triangle, Color(0.09, 0.07, 0.16, 0.96 * opacity))
	var outline := triangle.duplicate()
	outline.append(triangle[0])
	draw_polyline(outline, Color(0.78, 0.55, 1.0, opacity), 3.0, true)
	draw_rect(Rect2(center + Vector2(-2.0, -half * 0.5), Vector2(4.0, half * 0.62)), Color(1.0, 0.88, 0.5, opacity))
	draw_rect(Rect2(center + Vector2(-2.0, half * 0.24), Vector2(4.0, 4.0)), Color(1.0, 0.88, 0.5, opacity))

func _draw_shadow(top: float) -> void:
	# A dark band along the lane toward the runner: where the swarm will sweep.
	var length := 520.0
	var band := Rect2(Vector2(-size.x * 0.5 - length, top), Vector2(length + size.x, size.y))
	var alpha := 0.22 if phase == "warning" else 0.10
	if phase == "warning":
		alpha *= 0.6 + 0.4 * sin(_flap * 18.0)
	draw_rect(band, Color(0.05, 0.02, 0.12, alpha))

## One pixel-art style bat: a body block, two flapping wing triangles, eyes.
func _draw_bat(center: Vector2, bat_scale: float, flap: float, alpha: float, lane_sign: float) -> void:
	var body := Color(0.16, 0.1, 0.24, alpha)
	var wing := Color(0.27, 0.17, 0.38, alpha)
	var u := 3.0 * bat_scale
	var lift := flap * 5.0 * bat_scale
	draw_rect(Rect2(center + Vector2(-u, -u * 0.8), Vector2(u * 2.0, u * 1.8)), body)
	draw_rect(Rect2(center + Vector2(-u, -u * 1.6), Vector2(u * 0.8, u * 0.9)), body)
	draw_rect(Rect2(center + Vector2(u * 0.2, -u * 1.6), Vector2(u * 0.8, u * 0.9)), body)
	for side in [-1.0, 1.0]:
		var root := center + Vector2(side * u, -u * 0.2)
		var tip := center + Vector2(side * u * 4.4, -lift * lane_sign - u * 0.6)
		var low := center + Vector2(side * u * 2.6, u * 1.6 + lift * 0.3)
		draw_colored_polygon(PackedVector2Array([root, tip, low]), wing)
	draw_rect(Rect2(center + Vector2(-u * 0.7, -u * 0.5), Vector2(u * 0.5, u * 0.5)), Color(1.0, 0.35, 0.4, alpha))
	draw_rect(Rect2(center + Vector2(u * 0.2, -u * 0.5), Vector2(u * 0.5, u * 0.5)), Color(1.0, 0.35, 0.4, alpha))

func _begin_destruction() -> void:
	pass
