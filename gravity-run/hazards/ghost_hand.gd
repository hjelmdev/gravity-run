extends "res://hazards/hazard.gd"
class_name GhostHand
## Haunted-woods hazard (scripted feature "ghost_hand"): a ghost hand that
## reaches up out of one lane. A purple glow in the lane warns first, then the
## hand rises, stays up for a short while and sinks back. The runner on the other
## surface is safe. The hand is a pure function of how far the runner is from it
## (not of wall time), so a given run is the same every time:
##   d = runner x - hand x
##   d < GLOW_START          dormant
##   GLOW_START .. EMERGE    glow in the lane (0.6 s of warning at base speed)
##   EMERGE .. FULL          the hand rises (lethal as soon as it is above ground)
##   FULL .. SINK_START      the hand is up
##   SINK_START .. GONE      the hand sinks back

signal emerged(hand: GhostHand)

const GLOW_START := -360.0
const EMERGE := -60.0
const FULL := -10.0
const SINK_START := 100.0
const GONE := 180.0
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")

var event: Dictionary = {}
var phase := "dormant"
## Hitbox at the start of the current physics step, for the swept test.
var step_start_rect := Rect2()
var _reach := 0.0
var _glow := 0.0
var _clock := 0.0

func _ready() -> void:
	super._ready()
	set_process(true)

## world_x is the hand's x, surface_y the lane's surface there.
func configure_hand(value: Dictionary, world_x: float, surface_y: float) -> void:
	event = value.duplicate(true)
	size = Vector2(float(event.get("width", 60.0)), float(event.get("height", 120.0)))
	from_ceiling = bool(event.get("from_ceiling", false))
	position = Vector2(world_x, surface_y)
	add_to_group("ghost_hands")
	_apply_distance(-INF)
	step_start_rect = get_hitbox_rect()

func get_phase() -> String:
	return phase

## How far out of the lane the hand is, 0..1.
func get_reach() -> float:
	return _reach

func advance_motion(_delta: float, _movement: float, player_position: Vector2, _floor_y_at: Callable, _surface_angle_at: Callable, _surface_supported_at: Callable = Callable()) -> void:
	step_start_rect = get_hitbox_rect()
	_apply_distance(player_position.x - position.x)

func _apply_distance(d: float) -> void:
	var before := phase
	_glow = 0.0
	if d < GLOW_START or d > GONE:
		phase = "dormant" if d < GLOW_START else "gone"
		_reach = 0.0
	elif d < EMERGE:
		phase = "glow"
		_reach = 0.0
		_glow = clampf((d - GLOW_START) / 120.0, 0.0, 1.0)
	elif d < FULL:
		phase = "rising"
		_reach = (d - EMERGE) / (FULL - EMERGE)
	elif d < SINK_START:
		phase = "up"
		_reach = 1.0
	else:
		phase = "sinking"
		_reach = 1.0 - (d - SINK_START) / (GONE - SINK_START)
	if before != "rising" and before != "up" and (phase == "rising" or phase == "up"):
		emerged.emit(self)

func get_hitbox_rect() -> Rect2:
	var height := size.y * _reach
	if height < 1.0:
		return Rect2()
	var top := position.y if from_ceiling else position.y - height
	return Rect2(Vector2(position.x - size.x * 0.5, top), Vector2(size.x, height))

## Fraction 0..1 of the step in which the runner first touches the hand (which
## grew or sank during the step), -1 for no contact. Uses the union of the hand's
## rectangle at the start and the end of the step, so a hand rising into a
## standing runner is caught.
func swept_contact_fraction(start_rect: Rect2, finish_rect: Rect2) -> float:
	var now := get_hitbox_rect()
	var target := now
	if step_start_rect.size != Vector2.ZERO:
		target = step_start_rect if now.size == Vector2.ZERO else step_start_rect.merge(now)
	if target.size == Vector2.ZERO:
		return -1.0
	var polygon := PackedVector2Array([target.position, Vector2(target.end.x, target.position.y), target.end, Vector2(target.position.x, target.end.y)])
	return HazardRules.swept_rect_polygon_fraction(start_rect, finish_rect.position - start_rect.position, polygon)

func _process(delta: float) -> void:
	if is_destroying:
		super._process(delta)
		return
	_clock += delta
	queue_redraw()

func _draw() -> void:
	var dir := 1.0 if from_ceiling else -1.0
	# The glow sits in the lane the hand will come out of.
	if phase == "glow" or phase == "rising" or phase == "up":
		var strength := _glow if phase == "glow" else 1.0
		var pulse := 0.6 + 0.4 * sin(_clock * 14.0)
		for ring in range(3):
			var radius := 26.0 + float(ring) * 14.0
			draw_circle(Vector2(0.0, 0.0), radius, Color(0.62, 0.35, 1.0, 0.3 * strength * pulse))
		draw_rect(Rect2(Vector2(-size.x * 0.9, -4.0 if not from_ceiling else 0.0), Vector2(size.x * 1.8, 4.0)), Color(0.78, 0.55, 1.0, 0.8 * strength * pulse))
	if _reach <= 0.01:
		return
	var height := size.y * _reach
	var flip := 1.0 if int(_clock * 6.0) % 2 == 0 else -1.0
	_draw_hand(height, dir, flip)

## Two frames: fingers spread (flip = 1) and curled in (flip = -1).
func _draw_hand(height: float, dir: float, frame: float) -> void:
	var skin := Color(0.78, 0.9, 0.86, 0.92)
	var shade := Color(0.5, 0.62, 0.66, 0.92)
	var w := size.x
	# Wrist and palm.
	var arm_top := dir * height * 0.55
	draw_rect(Rect2(Vector2(-w * 0.16, minf(0.0, arm_top)), Vector2(w * 0.32, absf(arm_top))), shade)
	var palm_center := Vector2(0.0, dir * height * 0.62)
	draw_rect(Rect2(palm_center + Vector2(-w * 0.36, -height * 0.1), Vector2(w * 0.72, height * 0.2)), skin)
	# Four fingers and a thumb; spread or curled by frame.
	var spread := 0.16 if frame > 0.0 else 0.07
	var length := height * (0.34 if frame > 0.0 else 0.26)
	for index in range(4):
		var lean := (float(index) - 1.5) * spread * w
		var base := palm_center + Vector2((float(index) - 1.5) * w * 0.2, dir * height * 0.1)
		var tip := base + Vector2(lean, dir * length)
		draw_line(base, tip, skin, 5.0)
		draw_circle(tip, 3.0, Color(0.92, 1.0, 0.98, 0.95))
	var thumb_base := palm_center + Vector2(-w * 0.34, 0.0)
	draw_line(thumb_base, thumb_base + Vector2(-w * (0.2 if frame > 0.0 else 0.08), dir * height * 0.14), skin, 5.0)
	# Wispy fade where the arm leaves the lane.
	draw_rect(Rect2(Vector2(-w * 0.2, -3.0 if not from_ceiling else 0.0), Vector2(w * 0.4, 3.0)), Color(0.62, 0.35, 1.0, 0.7))

func _begin_destruction() -> void:
	pass
