extends SceneTree
## Music loops for campaign worlds 2-4, each with its own character (they used
## to share the meadow's chiptune recipe and sounded alike). Synthesised here,
## so the files carry no third-party rights. Not part of the game.
##
##   godot --headless --path . -s res://tools/audio/generate_world_music.gd [-- cave|haunted|volcano|frost|clouds|desert]
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
##   frost_peaks.wav     136 BPM, F minor: glockenspiel with a long echo, airy
##                       pad, sleigh-bell shaker, soft kick
##   cloud_kingdom.wav   116 BPM, G major: vibrato flute, harp arpeggios, soft
##                       pad, brushed percussion
##   desert_dunes.wav    148 BPM, E phrygian dominant: darbuka maqsum, plucked
##                       oud lead, low drone, shaker
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
	if only.is_empty() or only == "frost":
		_save(_frost(), "frost_peaks.wav")
	if only.is_empty() or only == "clouds":
		_save(_clouds(), "cloud_kingdom.wav")
	if only.is_empty() or only == "desert":
		_save(_desert(), "desert_dunes.wav")
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

func _frost() -> PackedFloat32Array:
	_rng.seed = 5501
	var bpm := 136.0
	var beat := 60.0 / bpm
	var bars := 16
	var length := beat * 4.0 * float(bars)
	var pad := _buffer(length)
	var glock := _buffer(length)
	var low := _buffer(length)
	var perc := _buffer(length)
	# Two-bar chords: Fm Db Ab Eb Fm Db Ab C.
	var roots := [41, 37, 44, 39, 41, 37, 44, 36]
	var minor := [0, 3, 7]
	var major := [0, 4, 7]
	var qualities := [minor, major, major, major, minor, major, major, major]
	var high_scale := [77, 79, 80, 82, 84, 85]
	var arp := [0, 2, 1, 2, 0, 1, 2, 1]
	for c in range(8):
		var start := float(c) * beat * 8.0
		var root: int = roots[c]
		var tones: Array = qualities[c]
		for tone in tones:
			_pad(pad, start, beat * 7.0, _f(root + 12 + int(tone)), 0.07, 1.2, 1.6)
			_pad(pad, start, beat * 7.0, _f(root + 24 + int(tone)), 0.03, 1.6, 1.6)
		_tone(low, start, beat * 3.5, _f(root), "sine", 0.14, 0.05, 0.6, 0.0)
		_tone(low, start + beat * 4.0, beat * 3.5, _f(root), "sine", 0.1, 0.05, 0.6, 0.0)
	for bar in range(bars):
		var chord_i := bar / 2
		var root: int = roots[chord_i]
		var tones: Array = qualities[chord_i]
		for step in range(8):
			var t := float(bar) * beat * 4.0 + float(step) * beat * 0.5
			if step % 4 != 0 and _rng.randf() > 0.72:
				continue
			var note: int = root + 36 + int(tones[arp[step]])
			if step % 4 != 0 and _rng.randf() < 0.25:
				note = high_scale[_rng.randi_range(0, high_scale.size() - 1)]
			_glock(glock, t, _f(note), 0.1 if step % 2 == 0 else 0.07)
	_echo(glock, beat * 0.75, 0.6, 0.9)
	_echo(glock, beat * 2.0, 0.4, 0.4)
	for b in range(bars * 4):
		var t := float(b) * beat
		if b % 2 == 0:
			_kick(perc, t, 0.12, 80.0, 48.0)
		_shake(perc, t, 0.035, true)
		_shake(perc, t + beat * 0.5, 0.055, true)
	return _mix([pad, glock, low, perc], length)

func _clouds() -> PackedFloat32Array:
	_rng.seed = 6601
	var bpm := 116.0
	var beat := 60.0 / bpm
	var bars := 16
	var length := beat * 4.0 * float(bars)
	var pad := _buffer(length)
	var harp := _buffer(length)
	var flute := _buffer(length)
	var perc := _buffer(length)
	# Two-bar chords: G D Em C G D C D.
	var roots := [43, 38, 40, 36, 43, 38, 36, 38]
	var minor := [0, 3, 7]
	var major := [0, 4, 7]
	var qualities := [major, major, minor, major, major, major, major, major]
	var arp := [0, 1, 2, 3, 4, 3, 2, 1]
	for c in range(8):
		var start := float(c) * beat * 8.0
		var root: int = roots[c]
		var tones: Array = qualities[c]
		for tone in tones:
			_pad(pad, start, beat * 7.0, _f(root + 12 + int(tone)), 0.028, 1.4, 1.8)
		_pad(pad, start, beat * 7.0, _f(root), 0.04, 1.4, 1.8)
	for bar in range(bars):
		var root: int = roots[bar / 2]
		var tones: Array = qualities[bar / 2]
		var seq := [int(tones[0]), int(tones[1]), int(tones[2]), int(tones[0]) + 12, int(tones[1]) + 12]
		for step in range(8):
			var t := float(bar) * beat * 4.0 + float(step) * beat * 0.5
			_harp(harp, t, _f(root + 24 + int(seq[arp[step]])), 0.18 if step % 4 == 0 else 0.1)
	_echo(harp, beat * 0.75, 0.4, 0.4)
	# Flute: a pentatonic walk, one 8-beat phrase per chord pair.
	var scale := [67, 69, 71, 74, 76, 79, 81, 83]
	var rhythms := [
		[[0.0, 1.5], [1.5, 0.5], [2.0, 2.0], [4.0, 1.0], [5.0, 1.0], [6.0, 2.0]],
		[[0.0, 3.0], [3.0, 1.0], [4.0, 2.0], [6.0, 1.0], [7.0, 1.0]],
		[[1.0, 1.5], [2.5, 0.5], [3.0, 1.0], [4.0, 4.0]],
	]
	var index := 3
	for phrase in range(8):
		var rhythm: Array = rhythms[[0, 1, 2, 0, 1, 0, 2, 1][phrase]]
		for note in rhythm:
			index = clampi(index + _rng.randi_range(-2, 2), 0, scale.size() - 1)
			var t := float(phrase) * beat * 8.0 + float(note[0]) * beat
			_flute(flute, t, float(note[1]) * beat * 0.95, _f(int(scale[index])), 0.11)
	_echo(flute, beat * 1.5, 0.4, 0.4)
	# Very soft brushes on 2 and 4 and a faint thump on 1.
	for bar in range(bars):
		var t := float(bar) * beat * 4.0
		_kick(perc, t, 0.07, 70.0, 50.0)
		_brush(perc, t + beat, beat * 0.9, 0.05)
		_brush(perc, t + beat * 3.0, beat * 0.9, 0.05)
		_brush(perc, t + beat * 2.5, beat * 0.5, 0.02)
	return _mix([pad, harp, flute, perc], length)

func _desert() -> PackedFloat32Array:
	_rng.seed = 7701
	var bpm := 148.0
	var beat := 60.0 / bpm
	var bars := 20
	var length := beat * 4.0 * float(bars)
	var drone := _buffer(length)
	var oud := _buffer(length)
	var lead := _buffer(length)
	var drums := _buffer(length)
	# Drone: E and B, frequencies snapped to whole cycles so the loop is seamless.
	_drone(drone, length, _f(28), 0.22)
	_drone(drone, length, _f(35), 0.08)
	_drone(drone, length, _f(40), 0.05)
	# E phrygian dominant: E F G# A B C D (scale offsets from E4).
	var offsets := [0, 1, 4, 5, 7, 8, 10, 12, 13, 16, 17]
	var phrases := [
		[[0.0, 0.5, 7], [0.5, 0.5, 6], [1.0, 0.5, 7], [1.5, 0.5, 5], [2.0, 1.0, 4], [3.0, 0.5, 2], [3.5, 0.5, 1], [4.0, 2.0, 0], [6.0, 0.5, 1], [6.5, 0.5, 2], [7.0, 1.0, 0]],
		[[0.0, 1.0, 4], [1.0, 0.5, 5], [1.5, 0.5, 4], [2.0, 1.0, 2], [3.0, 1.0, 1], [4.0, 0.5, 2], [4.5, 0.5, 1], [5.0, 0.5, 0], [5.5, 0.5, 1], [6.0, 2.0, 0]],
		[[0.0, 0.5, 9], [0.5, 0.5, 8], [1.0, 1.0, 7], [2.0, 0.5, 6], [2.5, 0.5, 5], [3.0, 1.0, 4], [4.0, 0.5, 5], [4.5, 0.5, 4], [5.0, 0.5, 2], [5.5, 0.5, 1], [6.0, 2.0, 0]],
		[[0.0, 0.25, 4], [0.25, 0.25, 4], [0.5, 0.5, 5], [1.0, 0.5, 4], [1.5, 0.5, 2], [2.0, 1.0, 1], [3.0, 0.5, 2], [3.5, 0.5, 1], [4.0, 0.25, 0], [4.25, 0.25, 0], [4.5, 0.5, 1], [5.0, 0.5, 2], [5.5, 0.5, 4], [6.0, 1.0, 5], [7.0, 1.0, 0]],
	]
	var order := [0, 1, 0, 2, 3, 3, 0, 1, 2]
	for p in range(order.size()):
		var phrase: Array = phrases[order[p]]
		for note in phrase:
			var t := float(2 + p * 2) * beat * 4.0 + float(note[0]) * beat
			_oud(lead, t, float(note[1]) * beat, _f(64 + int(offsets[int(note[2])])), 0.2)
	_echo(lead, beat * 0.75, 0.3, 0.3)
	var bass_notes := [52, 59, 52, 53]
	for bar in range(bars):
		var t := float(bar) * beat * 4.0
		var sixteenth := beat * 0.25
		# Maqsum: dum tek . tek dum . tek .
		_darbuka(drums, t, "dum", 0.3)
		_darbuka(drums, t + sixteenth * 2.0, "tek", 0.2)
		_darbuka(drums, t + sixteenth * 6.0, "tek", 0.2)
		_darbuka(drums, t + sixteenth * 8.0, "dum", 0.27)
		_darbuka(drums, t + sixteenth * 12.0, "tek", 0.2)
		_darbuka(drums, t + sixteenth * 10.0, "tek", 0.1)
		_darbuka(drums, t + sixteenth * 14.0, "tek", 0.1)
		if bar % 4 == 3:
			for k in [13, 15]:
				_darbuka(drums, t + sixteenth * float(k), "tek", 0.2)
		# Low oud on the dums.
		_oud(oud, t, beat * 0.9, _f(52), 0.2)
		_oud(oud, t + beat * 2.0, beat * 0.9, _f(int(bass_notes[bar % 4])), 0.16)
		for s in range(16):
			_shake(drums, t + sixteenth * float(s), 0.05 if s % 4 == 0 else 0.026, false)
	return _mix([drone, oud, lead, drums], length)

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

## Airy pad: two slightly detuned sines plus a soft octave, slow swell, tremolo.
func _pad(buffer: PackedFloat32Array, start: float, duration: float, freq: float, amp: float, attack: float, release: float) -> void:
	var first := int(start * float(RATE))
	var total := int((duration + release) * float(RATE))
	var p1 := 0.0
	var p2 := 0.0
	for i in range(total):
		var idx := first + i
		if idx < 0 or idx >= buffer.size():
			continue
		var t := float(i) / float(RATE)
		var env := minf(t / maxf(attack, 0.0005), 1.0)
		if t > duration:
			env *= maxf(0.0, 1.0 - (t - duration) / maxf(release, 0.0005))
		p1 += freq * 0.998 / float(RATE)
		p2 += freq * 1.002 / float(RATE)
		var s := sin(TAU * p1) + sin(TAU * p2) + 0.25 * sin(TAU * p1 * 2.0)
		buffer[idx] += s * env * amp * (0.85 + 0.15 * sin(TAU * 0.3 * t)) * 0.5

## A glockenspiel bar: bright inharmonic partials with a fast ping.
func _glock(buffer: PackedFloat32Array, start: float, freq: float, amp: float) -> void:
	var first := int(start * float(RATE))
	for i in range(int(2.2 * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var s := sin(TAU * freq * t) * exp(-t * 3.0)
		s += 0.45 * sin(TAU * freq * 2.76 * t) * exp(-t * 6.0)
		if freq < 1000.0:
			s += 0.25 * sin(TAU * freq * 5.4 * t) * exp(-t * 11.0)
		buffer[idx] += s * minf(t / 0.001, 1.0) * amp

## Sleigh-bell like shaker: a short burst of bright (high-passed) noise; with
## `jingle` some ringing high sines are added.
func _shake(buffer: PackedFloat32Array, start: float, amp: float, jingle: bool) -> void:
	var first := int(start * float(RATE))
	var low := 0.0
	var total := int((0.09 if jingle else 0.05) * float(RATE))
	for i in range(total):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var n := _rng.randf_range(-1.0, 1.0)
		low += (n - low) * 0.3
		var s := (n - low) * exp(-t * (45.0 if jingle else 90.0))
		if jingle:
			s += 0.25 * (sin(TAU * 3100.0 * t) + sin(TAU * 4300.0 * t) + sin(TAU * 5200.0 * t)) * exp(-t * 55.0)
		buffer[idx] += s * amp

## A harp pluck: soft, rounded, medium decay.
func _harp(buffer: PackedFloat32Array, start: float, freq: float, amp: float) -> void:
	var first := int(start * float(RATE))
	for i in range(int(1.6 * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var s := sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) * exp(-t * 4.0) + 0.1 * sin(TAU * freq * 3.0 * t) * exp(-t * 8.0)
		buffer[idx] += s * exp(-t * 2.6) * minf(t / 0.002, 1.0) * amp

## A soft flute: sine with a little 2nd harmonic, breath noise and a vibrato
## that fades in after the attack.
func _flute(buffer: PackedFloat32Array, start: float, duration: float, freq: float, amp: float) -> void:
	var first := int(start * float(RATE))
	var release := 0.3
	var total := int((duration + release) * float(RATE))
	var phase := 0.0
	var breath := 0.0
	for i in range(total):
		var idx := first + i
		if idx < 0 or idx >= buffer.size():
			continue
		var t := float(i) / float(RATE)
		var env := minf(t / 0.09, 1.0)
		if t > duration:
			env *= maxf(0.0, 1.0 - (t - duration) / release)
		var vib := 0.007 * sin(TAU * 5.2 * t) * clampf((t - 0.15) / 0.4, 0.0, 1.0)
		phase += freq * (1.0 + vib) / float(RATE)
		breath += (_rng.randf_range(-1.0, 1.0) - breath) * 0.3
		var s := sin(TAU * phase) + 0.18 * sin(TAU * phase * 2.0) + 0.05 * sin(TAU * phase * 3.0)
		s += breath * (0.12 + 0.3 * exp(-t * 12.0))
		buffer[idx] += s * env * amp

## A brush swish: low-passed noise that swells and fades over `duration`.
func _brush(buffer: PackedFloat32Array, start: float, duration: float, amp: float) -> void:
	var first := int(start * float(RATE))
	var low := 0.0
	for i in range(int(duration * float(RATE))):
		var idx := first + i
		if idx >= buffer.size():
			break
		var s := sin(PI * float(i) / (duration * float(RATE)))
		low += (_rng.randf_range(-1.0, 1.0) - low) * 0.25
		buffer[idx] += low * s * s * amp

## A plucked oud: a doubled (course) saw through a low-pass that closes as the
## note decays.
func _oud(buffer: PackedFloat32Array, start: float, duration: float, freq: float, amp: float) -> void:
	var first := int(start * float(RATE))
	var release := 0.35
	var total := int((duration + release + 0.25) * float(RATE))
	var p1 := 0.0
	var p2 := 0.0
	var low := 0.0
	for i in range(total):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		p1 += freq / float(RATE)
		p2 += freq * 1.004 / float(RATE)
		var saw := (2.0 * fmod(p1, 1.0) - 1.0) + (2.0 * fmod(p2, 1.0) - 1.0)
		low += (saw - low) * (0.07 + 0.35 * exp(-t * 14.0))
		var env := minf(t / 0.003, 1.0) * exp(-t * 3.6)
		if t > duration:
			env *= maxf(0.0, 1.0 - (t - duration) / (release + 0.25))
		buffer[idx] += low * env * amp * 0.5

## A darbuka hit: "dum" is a low skin tone, "tek" a dry high rim click.
func _darbuka(buffer: PackedFloat32Array, start: float, kind: String, amp: float) -> void:
	var first := int(start * float(RATE))
	var phase := 0.0
	var low := 0.0
	var total := int((0.3 if kind == "dum" else 0.07) * float(RATE))
	for i in range(total):
		var idx := first + i
		if idx >= buffer.size():
			break
		var t := float(i) / float(RATE)
		var n := _rng.randf_range(-1.0, 1.0)
		if kind == "dum":
			phase += (95.0 + 110.0 * exp(-t * 30.0)) / float(RATE)
			buffer[idx] += (sin(TAU * phase) * exp(-t * 11.0) + n * exp(-t * 120.0) * 0.15) * amp
		else:
			low += (n - low) * 0.35
			phase += 1250.0 / float(RATE)
			buffer[idx] += ((n - low) * 0.7 + 0.5 * sin(TAU * phase)) * exp(-t * 60.0) * amp

## A sustained sine for the whole loop, its frequency snapped to a whole number
## of cycles per loop so it has no seam. Slow tremolo, also whole cycles.
func _drone(buffer: PackedFloat32Array, length: float, freq: float, amp: float) -> void:
	var n := int(length * float(RATE))
	var cycles := roundf(freq * length)
	var trem := roundf(0.25 * length)
	for i in range(n):
		var x := float(i) / float(n)
		buffer[i] += sin(TAU * cycles * x) * amp * (0.8 + 0.2 * sin(TAU * trem * x))

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
