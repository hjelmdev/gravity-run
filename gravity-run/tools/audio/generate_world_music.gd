extends SceneTree
## Music loops for campaign worlds 2-4, each with its own character (they used
## to share the meadow's chiptune recipe and sounded alike). Synthesised here,
## so the files carry no third-party rights. Not part of the game.
##
##   godot --headless --path . -s res://tools/audio/generate_world_music.gd [-- cave|haunted|volcano]
##
## Writes mono 22050 Hz 16-bit loops of a whole number of bars to
## assets/audio/music/:
##   cave_depths.wav     128 BPM, A minor: low drone, plucked arpeggios with a
##                       long echo, water drips, soft kick and rim, a sparse
##                       sine lead
##   haunted_waltz.wav   120 BPM in 3/4, D harmonic minor: organ pad, music-box
##                       melody with echo, an "ooh" choir, waltz bass and stabs,
##                       a tolling bell
##   volcano_forge.wav   160 BPM, E phrygian: distorted bass chugs, power
##                       chords, taiko and snare, a lead riff in the second half
## The runner's feet follow each world's BPM (campaign/campaign_audio.gd).

const RATE := 22050
const OUT := "res://assets/audio/music/"

var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	var only := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	if only.is_empty() or only == "cave":
		_save(_cave(), "cave_depths.wav")
	if only.is_empty() or only == "haunted":
		_save(_haunted(), "haunted_waltz.wav")
	if only.is_empty() or only == "volcano":
		_save(_volcano(), "volcano_forge.wav")
	quit(0)

# --- Pieces ----------------------------------------------------------------

func _cave() -> PackedFloat32Array:
	_rng.seed = 2201
	var bpm := 128.0
	var beat := 60.0 / bpm
	var bars := 16
	var length := beat * 4.0 * float(bars)
	var drone := _buffer(length)
	var pluck := _buffer(length)
	var lead := _buffer(length)
	var drums := _buffer(length)
	# Am F Dm E, four bars each.
	var roots := [45, 41, 38, 40]
	var chords := [[0, 3, 7], [0, 4, 7], [0, 3, 7], [0, 4, 7]]
	for section in range(4):
		var start := float(section) * beat * 16.0
		var root: int = roots[section]
		_tone(drone, start, beat * 16.0, _f(root - 12), "sine", 0.22, 1.2, 1.2, 0.0)
		_tone(drone, start, beat * 16.0, _f(root + 7 - 12), "triangle", 0.07, 1.5, 1.5, 0.0)
		for bar in range(4):
			for step in range(8):
				var t := start + float(bar * 8 + step) * beat * 0.5
				var chord: Array = chords[section]
				var degree: int = chord[[0, 1, 2, 1, 0, 2, 1, 2][step]] + (12 if step >= 4 else 0)
				_tone(pluck, t, beat * 0.45, _f(root + 12 + degree), "pluck", 0.16, 0.003, 0.4, 0.0)
	_echo(pluck, beat * 0.75, 0.5, 0.55)
	# Sparse lead: a long note every other bar from the A minor pentatonic.
	var scale := [57, 60, 62, 64, 67, 69, 72]
	for bar in range(1, bars, 2):
		var note: int = scale[_rng.randi_range(0, scale.size() - 1)]
		_tone(lead, float(bar) * beat * 4.0 + beat, beat * 2.5, _f(note + 12), "sine", 0.1, 0.25, 0.8, 5.0)
	_echo(lead, beat * 1.5, 0.45, 0.5)
	# Kick on 1 and 3, a soft rim on 2 and 4, drips here and there.
	for b in range(bars * 4):
		var t := float(b) * beat
		if b % 2 == 0:
			_kick(drums, t, 0.35, 90.0, 45.0)
		else:
			_noise(drums, t, 0.05, 0.08, 0.35)
		if _rng.randf() < 0.3:
			_drip(drums, t + beat * 0.5 * float(_rng.randi_range(0, 1)), 0.12)
	_echo(drums, beat * 0.75, 0.35, 0.3)
	return _mix([drone, pluck, lead, drums], length)

func _haunted() -> PackedFloat32Array:
	_rng.seed = 3301
	var bpm := 120.0
	var beat := 60.0 / bpm
	var bar_len := beat * 3.0
	var bars := 24
	var length := bar_len * float(bars)
	var pad := _buffer(length)
	var box := _buffer(length)
	var choir := _buffer(length)
	var low := _buffer(length)
	# D harmonic minor, two-bar chords: Dm Gm A7 Dm Bb Gm A Dm (x1.5).
	var prog := [[50, [0, 3, 7]], [43, [0, 3, 7]], [45, [0, 4, 7, 10]], [50, [0, 3, 7]], [46, [0, 4, 7]], [43, [0, 3, 7]], [45, [0, 4, 7]], [50, [0, 3, 7]]]
	var melody_scale := [62, 64, 65, 67, 69, 70, 73, 74, 76, 77]
	var melody_index := 4
	for bar in range(bars):
		var chord: Array = prog[(bar / 2) % prog.size()]
		var root: int = chord[0]
		var tones: Array = chord[1]
		var t := float(bar) * bar_len
		if bar % 2 == 0:
			for tone in tones:
				_tone(pad, t, bar_len * 2.0, _f(root + 12 + int(tone)), "organ", 0.05, 0.4, 0.5, 0.0)
				_tone(choir, t, bar_len * 2.0, _f(root + 24 + int(tone)), "choir", 0.035, 0.6, 0.7, 5.5)
		# Waltz: bass on 1, music-box stabs on 2 and 3.
		_tone(low, t, beat * 0.9, _f(root - 12), "organ", 0.2, 0.01, 0.3, 0.0)
		for s in [1, 2]:
			for tone in tones.slice(0, 3):
				_tone(low, t + float(s) * beat, beat * 0.5, _f(root + 12 + int(tone)), "bell", 0.05, 0.002, 0.3, 0.0)
		# Melody: a stepwise walk over the scale, quarter and eighth notes.
		var pattern := [[0.0, 1.0], [1.0, 0.5], [1.5, 0.5], [2.0, 1.0]] if bar % 2 == 0 else [[0.0, 2.0], [2.0, 1.0]]
		for note in pattern:
			melody_index = clampi(melody_index + _rng.randi_range(-2, 2), 0, melody_scale.size() - 1)
			_tone(box, t + float(note[0]) * beat, float(note[1]) * beat, _f(int(melody_scale[melody_index]) + 12), "bell", 0.14, 0.002, 0.6, 0.0)
		# A low bell tolls every four bars.
		if bar % 4 == 0:
			_tone(low, t, bar_len * 2.0, _f(38), "bell", 0.12, 0.002, 2.0, 0.0)
	_echo(box, beat * 0.75, 0.45, 0.45)
	_echo(choir, beat * 1.5, 0.3, 0.3)
	return _mix([pad, box, choir, low], length)

func _volcano() -> PackedFloat32Array:
	_rng.seed = 4401
	var bpm := 160.0
	var beat := 60.0 / bpm
	var bars := 20
	var length := beat * 4.0 * float(bars)
	var bass := _buffer(length)
	var chords := _buffer(length)
	var drums := _buffer(length)
	var lead := _buffer(length)
	# E phrygian riff roots per bar pair: E E F E G F E D.
	var roots := [28, 28, 29, 28, 31, 29, 28, 26, 28, 28]
	var chug := [1, 1, 0, 1, 1, 0, 1, 1]
	for bar in range(bars):
		var root: int = roots[bar / 2]
		var t := float(bar) * beat * 4.0
		for step in range(8):
			if chug[step] == 1:
				_tone(bass, t + float(step) * beat * 0.5, beat * 0.42, _f(root), "dist", 0.3, 0.003, 0.05, 0.0)
		# Power chords on 1 and the "and" of 3.
		for at in [0.0, 2.5]:
			for interval in [12, 19, 24]:
				_tone(chords, t + at * beat, beat * 1.3, _f(root + interval), "dist", 0.07, 0.005, 0.2, 0.0)
		# Taiko on 1, the "and" of 2 and 3; snare on 2 and 4.
		for at in [0.0, 1.5, 2.0]:
			_kick(drums, t + at * beat, 0.6, 110.0, 38.0)
			_noise(drums, t + at * beat, 0.12, 0.18, 0.9)
		for at in [1.0, 3.0]:
			_noise(drums, t + at * beat, 0.16, 0.12, 0.25)
		# Lead riff in the second half.
		if bar >= bars / 2:
			var riff := [[0.0, 52], [0.5, 53], [1.0, 55], [2.0, 53], [2.5, 52], [3.0, 50]]
			for note in riff:
				_tone(lead, t + float(note[0]) * beat, beat * 0.45, _f(int(note[1]) + 12 + (root - 28)), "square", 0.08, 0.005, 0.1, 6.0)
	_echo(lead, beat * 0.75, 0.3, 0.3)
	_lowpass(chords, 0.35)
	return _mix([bass, chords, drums, lead], length)

# --- Instruments -------------------------------------------------------------

func _f(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)

func _buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	# Room for tails past the loop end; _mix folds them back to the start.
	buffer.resize(int((seconds + 4.0) * float(RATE)))
	return buffer

## One note. kinds: sine, triangle, square, saw, organ (stacked harmonics),
## pluck (triangle with a fast decay), bell (inharmonic partials, decaying),
## choir (soft saw through a low-pass, with vibrato), dist (saw driven into
## tanh). attack and release in seconds; vibrato in Hz (depth fixed).
func _tone(buffer: PackedFloat32Array, start: float, duration: float, freq: float, kind: String, amp: float, attack: float, release: float, vibrato: float) -> void:
	var first := int(start * float(RATE))
	var total := int((duration + release) * float(RATE))
	var phase := 0.0
	var low := 0.0
	for i in range(total):
		var idx := first + i
		if idx < 0 or idx >= buffer.size():
			continue
		var t := float(i) / float(RATE)
		var env := minf(t / maxf(attack, 0.0005), 1.0)
		if t > duration:
			env *= maxf(0.0, 1.0 - (t - duration) / maxf(release, 0.0005))
		var f := freq * (1.0 + (0.006 * sin(TAU * vibrato * t) if vibrato > 0.0 else 0.0))
		phase += f / float(RATE)
		var p := fmod(phase, 1.0)
		var s := 0.0
		match kind:
			"sine":
				s = sin(TAU * p)
			"triangle":
				s = 4.0 * absf(p - 0.5) - 1.0
			"square":
				s = 1.0 if p < 0.5 else -1.0
				s *= 0.6
			"saw":
				s = 2.0 * p - 1.0
			"organ":
				s = sin(TAU * p) + 0.5 * sin(TAU * p * 2.0) + 0.3 * sin(TAU * p * 3.0) + 0.15 * sin(TAU * p * 4.0)
				s *= 0.5
			"pluck":
				s = (4.0 * absf(p - 0.5) - 1.0) * exp(-t * 7.0)
			"bell":
				s = (sin(TAU * p) + 0.5 * sin(TAU * phase * 2.76) + 0.25 * sin(TAU * phase * 5.4)) * exp(-t * 3.5) * 0.6
			"choir":
				low += ((2.0 * p - 1.0) - low) * 0.08
				s = low * 1.6
			"dist":
				s = tanh(3.5 * (2.0 * p - 1.0) + 1.5 * sin(TAU * p * 0.5)) * 0.8
		buffer[idx] += s * env * amp

## A kick or taiko: a sine whose pitch falls from `high` to `low` Hz.
func _kick(buffer: PackedFloat32Array, start: float, amp: float, high: float, low: float) -> void:
	var first := int(start * float(RATE))
	var phase := 0.0
	for i in range(int(0.35 * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var f := low + (high - low) * exp(-t * 18.0)
		phase += f / float(RATE)
		buffer[idx] += sin(TAU * phase) * exp(-t * 9.0) * amp

## A noise burst (rim, snare, the skin of a taiko); `tone` 0..1 is how bright.
func _noise(buffer: PackedFloat32Array, start: float, duration: float, amp: float, tone: float) -> void:
	var first := int(start * float(RATE))
	var low := 0.0
	for i in range(int(duration * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var n := _rng.randf_range(-1.0, 1.0)
		low += (n - low) * (0.05 + 0.9 * tone)
		buffer[idx] += low * exp(-t / maxf(duration * 0.3, 0.001)) * amp

## A water drip: a short sine blip falling in pitch.
func _drip(buffer: PackedFloat32Array, start: float, amp: float) -> void:
	var first := int(start * float(RATE))
	var phase := 0.0
	var high := _rng.randf_range(1300.0, 2300.0)
	for i in range(int(0.09 * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		phase += (high * (1.0 - t * 4.0)) / float(RATE)
		buffer[idx] += sin(TAU * phase) * exp(-t * 40.0) * amp

## A feedback echo, applied in place.
func _echo(buffer: PackedFloat32Array, delay: float, feedback: float, mix: float) -> void:
	var offset := int(delay * float(RATE))
	for i in range(offset, buffer.size()):
		buffer[i] += buffer[i - offset] * feedback * mix

func _lowpass(buffer: PackedFloat32Array, amount: float) -> void:
	var low := 0.0
	for i in range(buffer.size()):
		low += (buffer[i] - low) * amount
		buffer[i] = low

## Sums the parts, folds everything past the loop end back to the start (so the
## loop is seamless) and normalises to a safe peak.
func _mix(parts: Array, length: float) -> PackedFloat32Array:
	var n := int(length * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for part in parts:
		var buffer: PackedFloat32Array = part
		for i in range(buffer.size()):
			out[i % n] += buffer[i]
	var peak := 0.0001
	for v in out:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	for i in range(n):
		out[i] *= gain
	return out

func _save(samples: PackedFloat32Array, name: String) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	stream.save_to_wav(OUT + name)
	print("wrote %s (%.1f s)" % [name, float(samples.size()) / float(RATE)])
