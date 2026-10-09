extends Node2D
class_name PersonalBestGhost
## The ghost of your personal best on a course you have run before (the same
## campaign stage, or the same seed in a seed challenge or the daily stage).
## A run records the runner's position and facing every SAMPLE_TICKS physics
## ticks; when a run beats the stored best for its course identity, its
## recording replaces it. The next run on that course plays the best back as a
## see-through runner. Recordings are presentation only: the ghost never
## touches anything.

const SAMPLE_TICKS := 2
const SAVE_PATH := "user://gravity_run_ghosts.cfg"
const SECTION := "ghosts"
## Oldest recordings are dropped beyond this many courses.
const MAX_COURSES := 40
const GHOST_MODULATE := Color(0.7, 0.92, 1.0, 0.38)

## Playback: [x, y, facing] per sample.
var _playback := PackedFloat32Array()
## Recording of the current run.
var _recording := PackedFloat32Array()
var _identity := ""
var _sprite: AnimatedSprite2D
var _pixel_scale := 1.0
var _offset_y := 0.0
var _surface_gap := 0.0

func _ready() -> void:
	z_index = 4
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "GhostSprite"
	_sprite.modulate = GHOST_MODULATE
	add_child(_sprite)
	visible = false

## Starts a run on a course. An empty identity turns recording and playback off.
## `frames`, `pixel_scale` and `offset_y` are the runner's own art.
func begin(identity: String, frames: SpriteFrames, pixel_scale: float, offset_y: float, surface_gap: float) -> void:
	_identity = identity
	_recording = PackedFloat32Array()
	_playback = load_best(identity).get("samples", PackedFloat32Array()) if not identity.is_empty() else PackedFloat32Array()
	_pixel_scale = pixel_scale
	_offset_y = offset_y
	_surface_gap = surface_gap
	if frames != null:
		_sprite.sprite_frames = frames
		_sprite.play("run")
	visible = false

func has_playback() -> bool:
	return not _playback.is_empty()

## Call once per physics tick with the runner's position and facing (sprite
## scale.y over the pixel scale: +1 upright on the floor, -1 on the ceiling).
func record(tick: int, runner_position: Vector2, facing: float) -> void:
	if _identity.is_empty() or tick % SAMPLE_TICKS != 0:
		return
	_recording.append(runner_position.x)
	_recording.append(runner_position.y)
	_recording.append(facing)

## Places the ghost where the best run was at this tick (interpolated); hides
## it before the start and after the best run ended.
func show_at(tick: float) -> void:
	var count := _playback.size() / 3
	if count < 2:
		visible = false
		return
	var at := tick / float(SAMPLE_TICKS)
	var index := int(floor(at))
	if index < 0 or index + 1 >= count:
		visible = false
		return
	var t := at - float(index)
	var a := index * 3
	var b := a + 3
	position = Vector2(lerpf(_playback[a], _playback[b], t), lerpf(_playback[a + 1], _playback[b + 1], t))
	var facing := lerpf(_playback[a + 2], _playback[b + 2], t)
	var shown := facing if absf(facing) > 0.08 else (0.08 if facing >= 0.0 else -0.08)
	_sprite.scale = Vector2(_pixel_scale, _pixel_scale * shown)
	_sprite.offset.y = _offset_y
	_sprite.position.y = -signf(shown) * _surface_gap
	visible = true

## Keeps this run's recording when `score` beats the stored best. Returns true
## when it became the new best.
func finish(score: float) -> bool:
	if _identity.is_empty() or _recording.size() < 6:
		return false
	var best := load_best(_identity)
	if not best.is_empty() and score <= float(best.get("score", -INF)):
		return false
	save_best(_identity, score, _recording)
	return true

static func _open() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	return config

static func _key(identity: String) -> String:
	return identity.sha256_text().left(24)

static func load_best(identity: String) -> Dictionary:
	var stored: Variant = _open().get_value(SECTION, _key(identity), {})
	if not stored is Dictionary or not (stored as Dictionary).get("samples") is PackedFloat32Array:
		return {}
	return stored

static func save_best(identity: String, score: float, samples: PackedFloat32Array) -> void:
	var config := _open()
	config.set_value(SECTION, _key(identity), {"score": score, "samples": samples, "saved_at": Time.get_unix_time_from_system()})
	var keys := config.get_section_keys(SECTION) if config.has_section(SECTION) else PackedStringArray()
	if keys.size() > MAX_COURSES:
		var by_age := Array(keys)
		by_age.sort_custom(func(a: String, b: String) -> bool: return float((config.get_value(SECTION, a, {}) as Dictionary).get("saved_at", 0.0)) < float((config.get_value(SECTION, b, {}) as Dictionary).get("saved_at", 0.0)))
		for index in range(keys.size() - MAX_COURSES):
			config.erase_section_key(SECTION, by_age[index])
	config.save(SAVE_PATH)

static func clear_all() -> void:
	var config := _open()
	if config.has_section(SECTION):
		config.erase_section(SECTION)
	config.save(SAVE_PATH)
