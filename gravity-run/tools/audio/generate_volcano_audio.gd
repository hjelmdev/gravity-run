extends SceneTree
## Music loop for the Volcano (campaign world 4) and its sound effects.
##
##   godot --headless --path . -s res://tools/audio/generate_volcano_audio.gd
##
## Writes assets/audio/music/volcano_forge.wav (a seamless 24-bar loop at 156 BPM
## in E minor: heavy kick and toms, snare, gritty gallop bass, detuned saw drone
## and a pulse lead) and four effects in assets/audio/sfx/: lava_bubble.wav,
## ember_impact.wav, magma_roar.wav and ember_star.wav. Everything is synthesised
## here, so the files carry no third-party rights. All files are mono 22050 Hz
## 16-bit to keep the web build small. Needs no Python, numpy or ffmpeg; the
## style follows generate_haunted_audio.py.
## main.gd syncs the runner's feet to this tempo (one footstep per eighth note).

const RATE := 22050
const BPM := 156.0
const BARS := 24
const STEPS_PER_BAR := 16
## The old music loop goes here, not over the current volcano_forge.wav, which
## tools/audio/generate_world_music.gd writes now (this file still makes the
## volcano sound effects).
const MUSIC_PATH := "res://assets/audio/music/volcano_forge_v1.wav"
const SFX_DIR := "res://assets/audio/sfx/"

## Chord tones in semitones above E (octave arbitrary).
const CHORDS := {
	"Em": [0, 3, 7], "C": [-4, 0, 3], "D": [-2, 2, 5], "F": [-7, -3, 0],
	"B": [-5, -1, 2], "Am": [-7, -4, 0],
}
## Semitones above E for the chord root (bass).
const ROOTS := {"Em": 0, "C": -4, "D": -2, "F": -11, "B": -5, "Am": -7}
const PROGRESSION := [
	"Em", "Em", "C", "D", "Em", "Em", "F", "B",
	"C", "D", "Em", "Em", "C", "D", "F", "B",
	"Em", "Em", "C", "D", "Em", "Em", "F", "B",
]
## E natural minor as semitones above E.
const SCALE := [0, 2, 3, 5, 7, 8, 10]
const RHYTHMS := [[4, 4, 4, 4], [6, 2, 4, 4], [4, 2, 2, 4, 4], [2, 2, 4, 4, 4], [8, 4, 4], [4, 4, 2, 2, 4], [2, 2, 2, 2, 8]]

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 156
	_write_music()
	_write_sfx("lava_bubble", _lava_bubble())
	_write_sfx("ember_impact", _ember_impact())
	_write_sfx("magma_roar", _magma_roar())
	_write_sfx("ember_star", _ember_star())
	quit()

# ---------------------------------------------------------------- helpers

func _midi_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

## E2 = MIDI 40; offset in semitones above E2.
func _e2(offset: float) -> float:
	return _midi_freq(40.0 + offset)

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)

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

func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * seconds))
	return out

# ---------------------------------------------------------------- music

## Mixes one event into a looping buffer; the tail wraps round to the start so
## the loop is seamless.
func _add(buf: PackedFloat32Array, start: int, samples: PackedFloat32Array, gain: float) -> void:
	var total := buf.size()
	for i in samples.size():
		buf[(start + i) % total] += samples[i] * gain

func _kick() -> PackedFloat32Array:
	var out := _buffer(0.32)
	var n := out.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (44.0 + 120.0 * exp(-t * 28.0)) / RATE
		var click := _noise() * exp(-t * 400.0) * 0.5
		out[i] = (sin(phase) * exp(-t * 9.0) + click) * minf(float(n - i) / 80.0, 1.0)
	return out

func _tom(base_hz: float) -> PackedFloat32Array:
	var out := _buffer(0.38)
	var n := out.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (base_hz + base_hz * 0.9 * exp(-t * 18.0)) / RATE
		out[i] = (sin(phase) + _noise() * exp(-t * 120.0) * 0.3) * exp(-t * 7.0) * minf(float(n - i) / 80.0, 1.0)
	return out

func _snare() -> PackedFloat32Array:
	var out := _buffer(0.26)
	var n := out.size()
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low += (_noise() - low) * 0.55
		var body := sin(TAU * 185.0 * t) * exp(-t * 26.0)
		out[i] = (low * exp(-t * 15.0) * 0.9 + body * 0.6) * minf(float(n - i) / 80.0, 1.0)
	return out

func _hat(open: bool) -> PackedFloat32Array:
	var out := _buffer(0.14 if open else 0.045)
	var prev := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var v := _noise()
		out[i] = (v - prev) * exp(-t * (24.0 if open else 85.0))
		prev = v
	return out

func _bass_note(f: float, length: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var n := out.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * f / RATE
		# Saturated sine for grit plus a clean sub an octave down.
		var tone := tanh(sin(phase) * 3.2) * 0.6 + sin(phase * 0.5) * 0.5
		out[i] = tone * (minf(t / 0.004, 1.0) * (0.35 + 0.65 * exp(-t * 7.0))) * minf(float(n - i) / 100.0, 1.0)
	return out

func _lead_note(f: float, length: float, vibrato: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var n := out.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += f * (1.0 + vibrato * sin(TAU * 5.5 * t) * minf(t * 3.0, 1.0)) / RATE
		var pulse := 1.0 if fposmod(phase, 1.0) < 0.28 else -1.0
		var env := minf(t / 0.006, 1.0) * (0.5 + 0.5 * exp(-t * 5.0)) * minf(float(n - i) / 200.0, 1.0)
		out[i] = pulse * env
	return out

func _pad_chord(freqs: Array, length: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var n := out.size()
	for f in freqs:
		var p1 := 0.0
		var p2 := 0.0
		var inc1: float = f / RATE
		var inc2: float = f * 1.006 / RATE
		for i in n:
			p1 += inc1
			p2 += inc2
			var saw := (fposmod(p1, 1.0) + fposmod(p2, 1.0)) - 1.0
			var t := float(i) / RATE
			var env := minf(t / 0.35, 1.0) * minf((length - t) / 0.3, 1.0)
			out[i] += saw * env * 0.12
	# Cheap low-pass to keep the drone dark.
	var state := 0.0
	for i in n:
		state += (out[i] - state) * 0.16
		out[i] = state
	return out

## Stepwise, chord-anchored melody for bars 0..15; bars 16..23 repeat 0..7.
## Returns [[bar, step, semitones above E, length in steps], ...].
func _build_melody() -> Array:
	var notes := []
	var degree := 9
	var chord_tones := {}
	for chord_name in CHORDS:
		var pitch_classes := {}
		for tone in CHORDS[chord_name]:
			pitch_classes[posmod(tone, 12)] = true
		chord_tones[chord_name] = pitch_classes
	for bar in 16:
		var chord: String = PROGRESSION[bar]
		var step := 0
		var rhythm: Array = RHYTHMS[_rng.randi() % RHYTHMS.size()]
		var first := true
		for length in rhythm:
			if first:
				var best := degree
				var best_cost := 999
				for d in range(7, 15):
					var pc := posmod(SCALE[d % 7], 12)
					var cost := absi(d - degree) + (0 if chord_tones[chord].has(pc) else 3)
					if cost < best_cost:
						best_cost = cost
						best = d
				degree = best
				first = false
			else:
				degree = clampi(degree + [-2, -1, -1, 1, 1, 2][_rng.randi() % 6], 7, 14)
			# End a phrase with a rest.
			if (bar == 7 or bar == 15) and step >= 8:
				break
			var semis: int = SCALE[degree % 7] + 12 * (degree / 7)
			if chord == "B" and posmod(semis, 12) == 2:
				semis += 1  # D -> D# leading tone over the B chord
			notes.append([bar, step, semis, length])
			step += length
	var repeat := []
	for note in notes:
		if note[0] < 8:
			repeat.append([note[0] + 16, note[1], note[2], note[3]])
	notes.append_array(repeat)
	return notes

func _write_music() -> void:
	var step_len := float(RATE) * 60.0 / BPM / 4.0
	var total := int(round(step_len * BARS * STEPS_PER_BAR))
	var buf := PackedFloat32Array()
	buf.resize(total)
	var kick := _kick()
	var snare := _snare()
	var hat_closed := _hat(false)
	var hat_open := _hat(true)
	var tom_hi := _tom(150.0)
	var tom_lo := _tom(100.0)
	var bass_cache := {}
	# Gallop bass: [step, length in steps, semitones above the chord root].
	var bass_pattern := [[0, 2, 0], [2, 1, 0], [3, 1, 0], [4, 2, 0], [6, 2, 0], [8, 2, 0], [10, 1, 7], [11, 1, 0], [12, 2, 0], [14, 2, 3]]
	var melody := _build_melody()
	var lead_cache := {}
	for bar in BARS:
		var chord: String = PROGRESSION[bar]
		var base_step := bar * STEPS_PER_BAR
		var phrase_end := bar % 8 == 7
		for step in STEPS_PER_BAR:
			var at := int(round((base_step + step) * step_len))
			if bar == 0:
				# Sparse first bar: kick on the half-bar and a quiet hat.
				if step == 0 or step == 8:
					_add(buf, at, kick, 0.8)
			else:
				var fill_zone := phrase_end and step >= 12
				if not fill_zone and (step % 4 == 0 or (step == 10 and bar % 2 == 1) or (step == 6 and bar % 4 == 3)):
					_add(buf, at, kick, 0.95)
				if not fill_zone and (step == 4 or step == 12):
					_add(buf, at, snare, 0.62)
			if step % 2 == 0:
				_add(buf, at, hat_open if step == 14 and bar % 2 == 0 else hat_closed, 0.22 if step % 4 == 0 else 0.14)
			elif bar >= 8 and bar % 2 == 1:
				_add(buf, at, hat_closed, 0.08)
		# Fill: descending toms on the last beat of each phrase.
		if phrase_end:
			for fill in [[12, tom_hi], [13, tom_hi], [14, tom_lo], [15, tom_lo]]:
				_add(buf, int(round((base_step + fill[0]) * step_len)), fill[1], 0.8)
			_add(buf, int(round((base_step + 12) * step_len)), kick, 0.7)
		# Bass.
		var root_offset: float = ROOTS[chord]
		for entry in bass_pattern:
			var key := "%d_%d" % [int(root_offset) + int(entry[2]), entry[1]]
			if not bass_cache.has(key):
				bass_cache[key] = _bass_note(_e2(root_offset + entry[2]), entry[1] * step_len / RATE * 0.95)
			_add(buf, int(round((base_step + entry[0]) * step_len)), bass_cache[key], 0.42)
		# Drone pad: one chord per bar, two octaves above the bass.
		var freqs := []
		for tone in CHORDS[chord]:
			freqs.append(_e2(24.0 + float(tone)))
		_add(buf, int(round(base_step * step_len)), _pad_chord(freqs, STEPS_PER_BAR * step_len / RATE), 0.5)
	# Lead from bar 4 on, cached by pitch and length.
	for note in melody:
		if note[0] < 4:
			continue
		var key := "%d_%d" % [note[2], note[3]]
		if not lead_cache.has(key):
			lead_cache[key] = _lead_note(_e2(36.0 + float(note[2])), note[3] * step_len / RATE * 0.92, 0.006)
		_add(buf, int(round((note[0] * STEPS_PER_BAR + note[1]) * step_len)), lead_cache[key], 0.12)
	# Gentle saturation, then normalise.
	for i in total:
		buf[i] = tanh(buf[i] * 1.15)
	_save(MUSIC_PATH, buf, 0.89)
	print("bars=%d bpm=%.0f length=%.3f s" % [BARS, BPM, float(total) / RATE])

# ---------------------------------------------------------------- sfx

func _lava_bubble() -> PackedFloat32Array:
	var out := _buffer(0.55)
	# Two bubbles: the pitch swoops up as the bubble rises, then it pops.
	for bubble in [[0.0, 150.0, 330.0, 1.0], [0.21, 210.0, 470.0, 0.6]]:
		var start := int(RATE * float(bubble[0]))
		var phase := 0.0
		for i in int(RATE * 0.26):
			var t := float(i) / RATE
			var rise := minf(t / 0.12, 1.0)
			phase += TAU * (float(bubble[1]) + (float(bubble[2]) - float(bubble[1])) * rise * rise) / RATE
			var env := minf(t / 0.008, 1.0) * exp(-t * 16.0)
			if start + i < out.size():
				out[start + i] += (sin(phase) + 0.3 * sin(phase * 2.0)) * env * float(bubble[3])
	# Thick gurgle underneath.
	var low := 0.0
	for i in out.size():
		var t := float(i) / RATE
		low += (_noise() - low) * 0.06
		out[i] += low * 2.2 * exp(-t * 6.0) * (0.6 + 0.4 * sin(TAU * 23.0 * t))
		out[i] *= minf(float(out.size() - i) / 300.0, 1.0)
	return out

func _ember_impact() -> PackedFloat32Array:
	var out := _buffer(0.7)
	var phase := 0.0
	var low := 0.0
	var prev := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (42.0 + 90.0 * exp(-t * 22.0)) / RATE
		var thud := sin(phase) * exp(-t * 9.0)
		low += (_noise() - low) * 0.12
		var burst := low * exp(-t * 22.0) * 1.1
		# Crackle: sparse clicks that thin out over time.
		var crackle := 0.0
		if _rng.randf() < 0.006 * exp(-t * 3.0):
			crackle = _noise() * 1.4
		var v := _noise()
		var hiss := (v - prev) * exp(-t * 10.0) * 0.12
		prev = v
		out[i] = (thud + burst + crackle + hiss) * minf(float(out.size() - i) / 400.0, 1.0)
	return out

func _magma_roar() -> PackedFloat32Array:
	var out := _buffer(1.2)
	var low := 0.0
	var low2 := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var env := minf(t / 0.28, 1.0) * (0.7 + 0.3 * exp(-pow(t - 0.45, 2.0) * 12.0)) * minf((1.2 - t) / 0.4, 1.0)
		low += (_noise() - low) * 0.05
		low2 += (low - low2) * 0.5
		phase += TAU * (48.0 + 9.0 * sin(TAU * 1.5 * t) - 6.0 * t) / RATE
		var growl := 0.55 + 0.45 * sin(TAU * 19.0 * t)
		var rumble := tanh(sin(phase) * 2.4) * 0.7
		out[i] = (low2 * 5.0 * growl + rumble + _noise() * 0.06 * env) * env
	return out

func _ember_star() -> PackedFloat32Array:
	var out := _buffer(0.85)
	# A warm rising arpeggio (E5, B5, E6) of soft bell tones over a low glow.
	for voice in [[0.0, 659.25, 1.0], [0.08, 987.77, 0.8], [0.16, 1318.5, 0.7]]:
		var start := int(RATE * float(voice[0]))
		var f: float = voice[1]
		for i in range(out.size() - start):
			var t := float(i) / RATE
			var tone := sin(TAU * f * t) * exp(-t * 5.0) + 0.35 * sin(TAU * f * 2.0 * t) * exp(-t * 8.0) + 0.18 * sin(TAU * f * 2.76 * t) * exp(-t * 14.0)
			out[start + i] += tone * minf(t / 0.004, 1.0) * float(voice[2])
	for i in out.size():
		var t := float(i) / RATE
		out[i] += 0.5 * sin(TAU * 329.63 * t) * exp(-t * 4.0) * minf(t / 0.02, 1.0)
		out[i] *= minf(float(out.size() - i) / 600.0, 1.0)
	return out
