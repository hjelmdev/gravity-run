extends SceneTree
## Sound effects for the Cloud Realm and the Desert.
##
##   godot --headless --path . -s res://tools/audio/generate_sky_desert_audio.gd
##
## Writes thunder_crack.wav, cloud_star.wav, desert_star.wav, sand_burst.wav and
## thunderbird_screech.wav into assets/audio/sfx/. Everything is synthesised
## here (mono 22050 Hz 16-bit, peak-normalised like generate_volcano_audio.gd),
## so the files carry no third-party rights.

const RATE := 22050
const SFX_DIR := "res://assets/audio/sfx/"

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 2025
	_write_sfx("thunder_crack", _thunder_crack())
	_write_sfx("cloud_star", _cloud_star())
	_write_sfx("desert_star", _desert_star())
	_write_sfx("sand_burst", _sand_burst())
	_write_sfx("thunderbird_screech", _thunderbird_screech())
	quit()

# ---------------------------------------------------------------- helpers

func _midi_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * seconds))
	return out

func _save(path: String, data: PackedFloat32Array, peak: float) -> void:
	var top := 0.0001
	for v in data:
		top = maxf(top, absf(v))
	var gain := peak / top
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	var err := wav.save_to_wav(ProjectSettings.globalize_path(path))
	print("%s: %d samples (%.2f s) err=%d" % [path, data.size(), float(data.size()) / RATE, err])

func _write_sfx(sfx_name: String, data: PackedFloat32Array) -> void:
	_save(SFX_DIR + sfx_name + ".wav", data, 0.89)

## Short fade-out so no file ends on a click.
func _fade_end(out: PackedFloat32Array, samples: int) -> void:
	for i in out.size():
		out[i] *= minf(float(out.size() - i) / samples, 1.0)

# ---------------------------------------------------------------- sfx

func _thunder_crack() -> PackedFloat32Array:
	var out := _buffer(0.9)
	var prev := 0.0
	var prev2 := 0.0
	var low := 0.0
	var low2 := 0.0
	var phase := 0.0
	# Crackle clicks after the main crack.
	var clicks := [0.07, 0.115, 0.19, 0.24, 0.33]
	for i in out.size():
		var t := float(i) / RATE
		# Bright crack: differenced noise (high-pass) with a very fast decay.
		var v := _noise()
		var bright := (v - prev) * exp(-t * 38.0) * 1.6
		var mid := (v - 2.0 * prev + prev2) * exp(-t * 90.0) * 0.5
		prev2 = prev
		prev = v
		var click := 0.0
		for c in clicks:
			var dt: float = t - float(c)
			if dt >= 0.0 and dt < 0.01:
				click += _noise() * exp(-dt * 700.0) * 1.1
		# Low rumble swells in as the crack dies away.
		low += (_noise() - low) * 0.05
		low2 += (low - low2) * 0.4
		phase += TAU * (62.0 - 22.0 * t) / RATE
		var rumble_env := minf(t / 0.1, 1.0) * exp(-maxf(t - 0.1, 0.0) * 3.8)
		var rumble := (low2 * 5.0 * (0.65 + 0.35 * sin(TAU * 17.0 * t)) + tanh(sin(phase) * 2.0) * 0.5) * rumble_env * 1.9
		out[i] = bright + mid + click + rumble
	_fade_end(out, 500)
	return out

func _cloud_star() -> PackedFloat32Array:
	var out := _buffer(0.7)
	# Airy major arpeggio (C6 E6 G6 C7), soft pure sines with a slight shimmer.
	var notes := [[0.0, 1046.5, 1.0], [0.07, 1318.5, 0.85], [0.14, 1568.0, 0.75], [0.21, 2093.0, 0.6]]
	for voice in notes:
		var start := int(RATE * float(voice[0]))
		var f: float = voice[1]
		for i in range(out.size() - start):
			var t := float(i) / RATE
			var trem := 1.0 + 0.25 * sin(TAU * 9.0 * t + f)
			var tone := sin(TAU * f * t) * exp(-t * 6.0) + 0.22 * sin(TAU * f * 3.0 * t) * exp(-t * 12.0)
			tone += 0.3 * sin(TAU * f * 1.004 * t) * exp(-t * 7.0)
			out[start + i] += tone * trem * minf(t / 0.012, 1.0) * float(voice[2]) * 0.6
	# Breathy shimmer: high-passed noise, smoothed, gently swelling.
	var prev := 0.0
	var smooth := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var v := _noise()
		smooth += ((v - prev) - smooth) * 0.45
		prev = v
		var env := minf(t / 0.1, 1.0) * exp(-maxf(t - 0.1, 0.0) * 4.5)
		out[i] += smooth * env * 0.28 * (0.6 + 0.4 * sin(TAU * 14.0 * t))
	_fade_end(out, 700)
	return out

func _pluck(out: PackedFloat32Array, start: int, f: float, gain: float, decay: float) -> void:
	# Oud-like: fundamental plus a few partials, bright attack that dulls fast.
	for i in range(out.size() - start):
		var t := float(i) / RATE
		var tone := sin(TAU * f * t) * exp(-t * decay)
		tone += 0.55 * sin(TAU * f * 2.0 * t) * exp(-t * decay * 1.6)
		tone += 0.3 * sin(TAU * f * 3.01 * t) * exp(-t * decay * 2.4)
		tone += 0.15 * sin(TAU * f * 4.03 * t) * exp(-t * decay * 3.5)
		var snap := _noise() * exp(-t * 400.0) * 0.25
		out[start + i] += (tone + snap) * minf(t / 0.002, 1.0) * gain

func _desert_star() -> PackedFloat32Array:
	var out := _buffer(0.7)
	# E phrygian dominant (E F G# A B C D): quick run E4 F4 G#4 B4 C5 E5.
	var run := [64, 65, 68, 71, 72, 76]
	for n in run.size():
		var last: bool = n == run.size() - 1
		_pluck(out, int(RATE * 0.055 * n), _midi_freq(float(run[n])), 1.0 if last else 0.85, 4.5 if last else 6.5)
	# Low drone note to ground it (E3).
	for i in out.size():
		var t := float(i) / RATE
		out[i] += 0.35 * sin(TAU * _midi_freq(52.0) * t) * exp(-t * 4.0) * minf(t / 0.01, 1.0)
	# A little shaker: three quick high-passed noise bursts.
	var prev := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var v := _noise()
		var hp := v - prev
		prev = v
		var env := 0.0
		for s in [0.0, 0.11, 0.22]:
			var dt: float = t - float(s)
			if dt >= 0.0:
				env += exp(-dt * 45.0) * minf(dt / 0.004, 1.0)
		out[i] += hp * env * 0.16
	_fade_end(out, 600)
	return out

func _sand_burst() -> PackedFloat32Array:
	var out := _buffer(0.8)
	var a := 0.0
	var b := 0.0
	var c := 0.0
	var d := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var v := _noise()
		# Band-pass from two one-pole filters; the band drifts down over time.
		var hi_coef := 0.38 - 0.18 * minf(t / 0.8, 1.0)
		a += (v - a) * hi_coef
		b += (a - b) * 0.04
		var band := a - b
		c += (_noise() - c) * 0.3
		d += (c - d) * 0.03
		var hiss := c - d
		var env := minf(t / 0.2, 1.0) * exp(-maxf(t - 0.2, 0.0) * 4.2)
		# Grainy flutter so it reads as sand rather than wind.
		var grain := 0.75 + 0.25 * sin(TAU * 41.0 * t) * sin(TAU * 13.0 * t)
		# Soft thump at the start.
		phase += TAU * (70.0 + 50.0 * exp(-t * 30.0)) / RATE
		var thump := sin(phase) * exp(-t * 16.0) * 0.9
		out[i] = (band * 3.2 + hiss * 1.2) * env * grain + thump
	_fade_end(out, 500)
	return out

func _thunderbird_screech() -> PackedFloat32Array:
	var out := _buffer(1.0)
	var phase := 0.0
	var buzz_phase := 0.0
	var prev := 0.0
	for i in out.size():
		var t := float(i) / RATE
		# Glide: rises to about 2.5 kHz, hangs, then falls away.
		var glide := 1500.0 + 1000.0 * sin(PI * minf(t / 0.55, 1.0) * 0.5) - 700.0 * maxf(t - 0.55, 0.0) / 0.45
		var vib := 1.0 + 0.035 * sin(TAU * 8.5 * t) * minf(t * 6.0, 1.0)
		phase += TAU * glide * vib / RATE
		var env := minf(t / 0.03, 1.0) * (0.75 + 0.25 * exp(-t * 4.0)) * exp(-maxf(t - 0.5, 0.0) * 3.2)
		var tone := sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0) + 0.15 * sin(phase * 4.0)
		# Rasp: noise amplitude-modulated at a high rate.
		var rasp := _noise() * (0.5 + 0.5 * sin(TAU * 95.0 * t)) * 0.35
		# Electric buzz underneath (saturated 120 Hz).
		buzz_phase += TAU * 120.0 / RATE
		var buzz := tanh(sin(buzz_phase) * 4.0) * 0.3 * (0.7 + 0.3 * sin(TAU * 31.0 * t))
		# Crackle: sparse clicks.
		var crackle := 0.0
		if _rng.randf() < 0.012:
			crackle = _noise() * 1.2
		var v := _noise()
		var hiss := (v - prev) * 0.06
		prev = v
		out[i] = (tone * 0.55 + rasp) * env + buzz * minf(env * 1.3, 1.0) + (crackle + hiss) * env
	_fade_end(out, 600)
	return out
