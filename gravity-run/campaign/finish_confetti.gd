extends Node2D
## Confetti for a finished campaign stage. Lives in screen space (campaign_run
## moves it with the camera): a burst from the finish line, then a short rain.

const BURST_COUNT := 140
const RAIN_SECONDS := 1.4
const RAIN_PER_SECOND := 90.0
const LIFETIME := 2.6
const GRAVITY := 380.0
const COLORS: Array[Color] = [Color("f5d45e"), Color("42d6c5"), Color("ff6f91"), Color("8fd14f"), Color("6ea8ff"), Color("ffffff")]

var _pieces: Array[Dictionary] = []
var _rain_left := 0.0
var _rain_carry := 0.0
var _width := 960.0
var _height := 540.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 40
	_rng.seed = 20261008

## origin is the finish line in screen space; the burst fans out from it.
func burst(origin: Vector2, view_size: Vector2) -> void:
	_width = view_size.x
	_height = view_size.y
	_rain_left = RAIN_SECONDS
	for index in range(BURST_COUNT):
		var angle := _rng.randf_range(-PI * 0.95, -PI * 0.05)
		var speed := _rng.randf_range(240.0, 760.0)
		_add_piece(origin + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-40.0, 40.0)), Vector2(cos(angle), sin(angle)) * speed)

func _add_piece(at: Vector2, velocity: Vector2) -> void:
	_pieces.append({
		"pos": at,
		"vel": velocity,
		"age": 0.0,
		"life": _rng.randf_range(LIFETIME * 0.7, LIFETIME),
		"spin": _rng.randf_range(-9.0, 9.0),
		"rot": _rng.randf_range(0.0, TAU),
		"flutter": _rng.randf_range(4.0, 9.0),
		"size": Vector2(_rng.randf_range(8.0, 13.0), _rng.randf_range(5.0, 8.0)),
		"color": COLORS[_rng.randi() % COLORS.size()],
	})

func is_active() -> bool:
	return not _pieces.is_empty() or _rain_left > 0.0

func _process(delta: float) -> void:
	if not is_active():
		return
	if _rain_left > 0.0:
		_rain_left -= delta
		_rain_carry += RAIN_PER_SECOND * delta
		while _rain_carry >= 1.0:
			_rain_carry -= 1.0
			_add_piece(Vector2(_rng.randf_range(0.0, _width), -10.0), Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(20.0, 120.0)))
	var keep: Array[Dictionary] = []
	for piece in _pieces:
		piece["age"] = float(piece["age"]) + delta
		if float(piece["age"]) >= float(piece["life"]):
			continue
		var velocity: Vector2 = piece["vel"]
		velocity.y += GRAVITY * delta
		# Air drag: a burst slows quickly and then flutters down.
		velocity.x = move_toward(velocity.x, 0.0, 110.0 * delta)
		velocity.y = minf(velocity.y, 150.0)
		piece["vel"] = velocity
		piece["pos"] = Vector2(piece["pos"]) + velocity * delta
		piece["rot"] = float(piece["rot"]) + float(piece["spin"]) * delta
		keep.append(piece)
	_pieces = keep
	queue_redraw()

func _draw() -> void:
	for piece in _pieces:
		var age := float(piece["age"])
		var life := float(piece["life"])
		var color: Color = piece["color"]
		color.a = clampf((life - age) / 0.5, 0.0, 1.0)
		# Flipping paper: the width shrinks and grows as it tumbles.
		var flip := absf(sin(age * float(piece["flutter"]) + float(piece["rot"])))
		var half: Vector2 = Vector2(piece["size"]) * 0.5
		var rot := float(piece["rot"])
		var axis_x := Vector2(cos(rot), sin(rot)) * half.x
		var axis_y := Vector2(-sin(rot), cos(rot)) * half.y * maxf(flip, 0.25)
		var center: Vector2 = piece["pos"]
		draw_colored_polygon(PackedVector2Array([center - axis_x - axis_y, center + axis_x - axis_y, center + axis_x + axis_y, center - axis_x + axis_y]), color)
