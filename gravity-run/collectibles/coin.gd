extends Node2D

signal collected(value: int)
signal visual_collection_started
signal visual_collection_cancelled

const COIN_SIZE := Vector2(24.0, 24.0)
const COIN_VALUE := 1
const BURST_DURATION := 0.22

var is_being_collected := false
var burst_elapsed := 0.0
var coin_face_scale_y := 1.0
var coin_alpha := 1.0
var sparks: Array[Dictionary] = []
var _visual_prediction_request_id := ""
var _visual_prediction_pending := false
var _prediction_origin := Vector2.ZERO
## Idle turn: the pixel coin frame on screen (PixelCoin), redrawn when it changes.
var _frame := -1
var _spin_phase := 0.0

func _ready() -> void:
	_spin_phase = fposmod(global_position.x * 0.013, float(PixelCoin.FRAMES))
	set_process(true)

func get_hitbox_rect() -> Rect2:
	return Rect2(global_position - COIN_SIZE * 0.5, COIN_SIZE)

func is_collected() -> bool:
	return is_being_collected

func collect() -> void:
	if not animate_collection():
		return
	collected.emit(COIN_VALUE)

func animate_collection() -> bool:
	if is_being_collected:
		return false
	is_being_collected = true
	visual_collection_started.emit()
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + randf_range(-0.3, 0.3)
		sparks.append({
			"position": Vector2.ZERO,
			"velocity": Vector2.from_angle(angle) * randf_range(55.0, 105.0),
			"life": BURST_DURATION,
			"size": randf_range(3.0, 5.0)
		})
	set_process(true)
	return true

func begin_visual_prediction(request_id: String) -> bool:
	if request_id.is_empty() or _visual_prediction_pending or is_being_collected:
		return false
	_prediction_origin = position
	_visual_prediction_request_id = request_id
	_visual_prediction_pending = true
	return animate_collection()

func confirm_visual_prediction(request_id: String = "") -> bool:
	if not _visual_prediction_pending:
		return false
	if not request_id.is_empty() and request_id != _visual_prediction_request_id:
		return false
	_visual_prediction_pending = false
	_visual_prediction_request_id = ""
	if burst_elapsed >= BURST_DURATION and sparks.is_empty():
		queue_free()
	else:
		set_process(true)
	return true

func reject_visual_prediction(request_id: String) -> bool:
	if not _visual_prediction_pending or request_id != _visual_prediction_request_id:
		return false
	_visual_prediction_pending = false
	_visual_prediction_request_id = ""
	visual_collection_cancelled.emit()
	is_being_collected = false
	burst_elapsed = 0.0
	coin_face_scale_y = 1.0
	coin_alpha = 1.0
	sparks.clear()
	position = _prediction_origin
	visible = true
	set_process(true)
	queue_redraw()
	return true

func _process(delta: float) -> void:
	if not is_being_collected:
		var frame := PixelCoin.frame_at(Time.get_ticks_msec() / 1000.0, _spin_phase)
		if frame != _frame:
			_frame = frame
			queue_redraw()
		return
	burst_elapsed += delta
	coin_face_scale_y = absf(cos(burst_elapsed * 16.0))
	coin_alpha = clampf(1.0 - burst_elapsed / 0.16, 0.0, 1.0)
	for i in range(sparks.size()):
		var spark: Dictionary = sparks[i]
		spark["position"] = Vector2(spark["position"]) + Vector2(spark["velocity"]) * delta
		spark["velocity"] = Vector2(spark["velocity"]) + Vector2(0.0, 55.0) * delta
		spark["life"] = float(spark["life"]) - delta
		sparks[i] = spark
	sparks = sparks.filter(func(spark: Dictionary) -> bool: return float(spark["life"]) > 0.0)
	position.y -= 95.0 * delta
	queue_redraw()
	if burst_elapsed >= BURST_DURATION and sparks.is_empty():
		if _visual_prediction_pending:
			visible = false
			set_process(false)
		else:
			queue_free()

func _draw() -> void:
	# Sparks: small square pixels that fly out and fade.
	for spark in sparks:
		var life_ratio := clampf(float(spark["life"]) / BURST_DURATION, 0.0, 1.0)
		var size := roundf(float(spark["size"]) * life_ratio * 0.5) * 2.0
		if size < 2.0:
			continue
		var center := (Vector2(spark["position"]) / 2.0).round() * 2.0
		var spark_color := Color("ffeaa0") if int(spark["size"] * 10.0) % 2 == 0 else Color("f5d45e")
		spark_color.a = life_ratio
		draw_rect(Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), spark_color)
	# The coin: the turning pixel frame; when collected it flips flat and fades.
	var frame := _frame if _frame >= 0 else 0
	var texture := PixelCoin.frame_texture(frame)
	var side := float(PixelCoin.ART) * 2.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, maxf(coin_face_scale_y, 0.06)))
	draw_texture_rect(texture, Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side)), false, Color(1.0, 1.0, 1.0, coin_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
