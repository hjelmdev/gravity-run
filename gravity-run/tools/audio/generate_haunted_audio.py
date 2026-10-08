#!/usr/bin/env python3
"""Chiptune loop for the Haunted Woods (campaign world 3) and its sound effects.

    python3 tools/audio/generate_haunted_audio.py

Writes assets/audio/music/haunted_hollow.ogg (a seamless ~44 s loop at 132 BPM
in D minor: harpsichord-like plucked lead with a circular echo, wheezy organ
pad with tremolo, harpsichord arpeggio, triangle bass and a soft heartbeat) and
five effects in assets/audio/sfx/: ghost_whistle.wav, hand_scrape.wav,
lantern_chime.wav, haunted_star.wav and ghost_king_laugh.wav. Everything is
synthesised here, so the files carry no third-party rights. Needs numpy and
ffmpeg (libvorbis). Modelled on generate_cave_audio.py.
"""
import os
import subprocess
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RATE = 44100
## main.gd syncs the runner's feet to this tempo (one footstep per eighth note).
BPM = 132.0
EIGHTH = 60.0 / BPM / 2.0
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NOTES[pitch]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def triangle(f, t):
    return 4.0 * np.abs((t * f) % 1.0 - 0.5) - 1.0


def envelope(n, attack=0.005, decay=0.12, sustain=0.55, release=0.04):
    t = np.arange(n) / RATE
    length = n / RATE
    env = np.where(t < attack, t / attack, sustain + (1.0 - sustain) * np.exp(-(t - attack) / decay))
    tail = np.clip((length - t) / release, 0.0, 1.0)
    return env * tail


def render_line(notes, voice, gain, total):
    out = np.zeros(total)
    cursor = 0.0
    for note, eighths in notes:
        start = int(round(cursor * EIGHTH * RATE))
        n = int(round(eighths * EIGHTH * RATE))
        cursor += eighths
        if note is None or start >= total:
            continue
        n = min(n, total - start)
        t = np.arange(n) / RATE
        out[start:start + n] += voice(freq(note), t, n) * gain
    return out


def harpsichord_voice(f, t, n):
    # Thin pulse with a quick pluck decay and a bright click at the start.
    pulse = np.where((t * f) % 1.0 < 0.3, 1.0, -1.0) + 0.5 * np.where((t * f * 2.0) % 1.0 < 0.5, 1.0, -1.0)
    return pulse * envelope(n, attack=0.001, decay=0.09, sustain=0.06, release=0.02)


def organ_voice(f, t, n):
    # Drawbar-style organ: a few harmonics, slow tremolo, soft attack and release.
    tone = sum(np.sin(2 * np.pi * f * h * t) * a for h, a in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2), (6, 0.12)])
    tremolo = 0.82 + 0.18 * np.sin(2 * np.pi * 5.5 * t)
    return tone * tremolo * envelope(n, attack=0.04, decay=1.0, sustain=0.9, release=0.08) * 0.4


def bass_voice(f, t, n):
    return triangle(f, t) * envelope(n, attack=0.003, decay=0.2, sustain=0.7, release=0.03)


CHORDS = {
    "Dm": ["D", "F", "A"], "A#": ["A#", "D", "F"], "Gm": ["G", "A#", "D"], "A": ["A", "C#", "E"],
    "F": ["F", "A", "C"], "C": ["C", "E", "G"],
}
# 24 bars: A, B, A. The major A chord (C# leading tone) pulls back to Dm.
PROGRESSION = (
    ["Dm", "A#", "Gm", "A", "Dm", "A#", "A", "Dm"]
    + ["Gm", "Dm", "A#", "F", "Gm", "Dm", "A", "A"]
    + ["Dm", "A#", "Gm", "A", "Dm", "A#", "A", "Dm"]
)
D_MINOR = ["D", "E", "F", "G", "A", "A#", "C"]
RHYTHMS = [[2, 2, 2, 2], [3, 1, 2, 2], [2, 1, 1, 2, 2], [1, 1, 2, 2, 2], [4, 2, 2], [2, 2, 1, 1, 2], [1, 1, 1, 1, 2, 2]]


def build_melody():
    """Stepwise, chord-anchored melody in a fixed order so the file is stable."""
    rng = np.random.default_rng(66)
    notes = []
    degree = 14
    section_a = None
    for index, chord in enumerate(PROGRESSION):
        if index >= 16:
            if index == 16:
                notes.extend(section_a)
            continue
        tones = [t[0] for t in CHORDS[chord]]
        bar = []
        for length in RHYTHMS[int(rng.integers(len(RHYTHMS)))]:
            if not bar:
                best = min(range(10, 20), key=lambda d: (abs(d - degree) + (0 if D_MINOR[d % 7] in tones else 3)))
                degree = best
            else:
                degree = int(np.clip(degree + int(rng.choice([-2, -1, -1, 1, 1, 2])), 10, 19))
            pitch = D_MINOR[degree % 7]
            if chord == "A" and pitch == "C":
                pitch = "C#"
            bar.append((pitch + str(degree // 7 + 3 + 1), length))
        if index == 7 or index == 15:
            bar = [(bar[0][0], 4), (None, 4)]  # breathe at the end of a phrase
        notes.extend(bar)
        if index < 8:
            section_a = (section_a or []) + bar
    return notes


def add_echo(line, taps=(0.5, 0.3, 0.17, 0.09), delay_eighths=3):
    """Circular echo: the tail of the loop wraps to the start, so it is seamless."""
    delay = int(round(delay_eighths * EIGHTH * RATE))
    out = line.copy()
    for k, gain in enumerate(taps, start=1):
        out += np.roll(line, delay * k) * gain
    return out


def build_music():
    bars = len(PROGRESSION)
    total = int(round(bars * 8 * EIGHTH * RATE))
    mix = add_echo(render_line(build_melody(), harpsichord_voice, 0.13, total))
    pad, arp, bass = [], [], []
    for chord in PROGRESSION:
        tones = CHORDS[chord]
        pad_notes = [tones[0] + "3", tones[1] + "3", tones[2] + "3"]
        pad.append(pad_notes)
        pattern = [tones[0] + "4", tones[2] + "4", tones[1] + "5", tones[2] + "4"] * 4
        arp += [(note, 0.5) for note in pattern]
        root, fifth = tones[0] + "2", tones[2] + "2"
        bass += [(root, 2), (root, 1), (fifth, 1), (root, 2), (tones[1] + "2", 1), (fifth, 1)]
    for index, notes in enumerate(pad):
        for note in notes:
            mix += render_line([(None, index * 8), (note, 8)], organ_voice, 0.05, total)
    mix += add_echo(render_line(arp, harpsichord_voice, 0.035, total), (0.4, 0.2, 0.1)) * 0.7
    mix += render_line(bass, bass_voice, 0.22, total)
    rng = np.random.default_rng(13)
    beat = 2 * EIGHTH

    def put(at, sound):
        end = min(total, at + len(sound))
        if end > at:
            mix[at:end] += sound[: end - at]

    bells = [freq("A5"), freq("D6"), freq("F6"), freq("E6")]
    for b in range(bars * 4):
        t0 = int(b * beat * RATE)
        if b % 2 == 0:
            # Heartbeat-like soft thump.
            n = int(0.16 * RATE)
            t = np.arange(n) / RATE
            put(t0, np.sin(2 * np.pi * (46 + 70 * np.exp(-t * 26)) * t) * np.exp(-t * 17) * 0.32)
            put(t0 + int(0.2 * RATE), np.sin(2 * np.pi * (44 + 50 * np.exp(-t * 26)) * t) * np.exp(-t * 20) * 0.18)
        else:
            n = int(0.09 * RATE)
            put(t0, np.diff(rng.uniform(-1, 1, n), prepend=0.0) * np.exp(-np.arange(n) / RATE * 38) * 0.05)
        # A hollow little bell on an off-beat skip.
        if b % 8 in (3, 6):
            m = int(0.4 * RATE)
            t = np.arange(m) / RATE
            f = bells[(b // 2) % 4]
            put(int((b * beat + EIGHTH) * RATE), (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t)) * np.exp(-t * 9) * 0.07)
    mix = np.tanh(mix * 1.1)
    return mix / np.max(np.abs(mix)) * 0.86


def add_echo_tail(out, taps):
    """Linear echo for one-shots: (delay seconds, gain) taps."""
    length = len(out)
    result = out.copy()
    for delay, gain in taps:
        d = int(delay * RATE)
        if d < length:
            result[d:] += out[: length - d] * gain
    return result


def build_ghost_whistle():
    # Eerie slide: a pure tone swooping up then falling, wide slow vibrato, breath noise.
    seconds = 1.1
    length = int(seconds * RATE)
    t = np.arange(length) / RATE
    rng = np.random.default_rng(3)
    rise = 520 + 640 * np.clip(t / 0.45, 0, 1) ** 0.8 - 520 * np.clip((t - 0.55) / 0.55, 0, 1) ** 1.3
    sweep = rise * (1.0 + 0.025 * np.sin(2 * np.pi * 6.0 * t) * np.clip(t / 0.3, 0, 1))
    phase = np.cumsum(sweep) / RATE
    tone = np.sin(2 * np.pi * phase) + 0.18 * np.sin(2 * np.pi * phase * 2.0)
    breath = np.convolve(rng.uniform(-1, 1, length), np.ones(6) / 6, mode="same") * 0.12
    env = np.clip(t / 0.12, 0, 1) * np.exp(-np.maximum(t - 0.4, 0) * 2.6) * np.clip((seconds - t) / 0.2, 0, 1)
    out = (tone + breath) * env
    out = add_echo_tail(out, [(0.18, 0.4), (0.36, 0.2)])
    return out / np.max(np.abs(out)) * 0.7


def build_hand_scrape():
    # A hand clawing up through dirt: gritty filtered noise in three scrapes, crumbs and a dull thud.
    seconds = 0.85
    length = int(seconds * RATE)
    t = np.arange(length) / RATE
    rng = np.random.default_rng(29)
    raw = rng.uniform(-1, 1, length)
    grit = raw - np.convolve(raw, np.ones(14) / 14, mode="same")  # high-passed noise
    env = np.zeros(length)
    for start, dur in [(0.02, 0.2), (0.25, 0.22), (0.5, 0.28)]:
        local = np.clip((t - start) / dur, 0, 1)
        env += np.where((t >= start) & (t < start + dur), np.sin(np.pi * local) ** 1.2, 0.0)
    scratch = grit * env * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t))
    out = scratch * 0.7
    low = np.convolve(rng.uniform(-1, 1, length), np.ones(60) / 60, mode="same") * 4.0
    out += low * env * 0.35
    for i in range(14):
        at = int(rng.uniform(0.05, 0.75) * RATE)
        m = int(0.025 * RATE)
        out[at:at + m] += np.sin(2 * np.pi * rng.uniform(300, 900) * np.arange(m) / RATE) * np.exp(-np.arange(m) / RATE * 160) * 0.18
    out[: int(0.12 * RATE)] += np.sin(2 * np.pi * 70 * t[: int(0.12 * RATE)]) * np.exp(-t[: int(0.12 * RATE)] * 30) * 0.5
    out *= np.clip((seconds - t) / 0.08, 0, 1)
    return np.tanh(out * 1.2) / np.tanh(1.2) * 0.8


def bell(f, length_s, decay=4.5):
    t = np.arange(int(length_s * RATE)) / RATE
    partials = [(1.0, 1.0), (2.0, 0.55), (2.76, 0.4), (4.07, 0.25), (5.4, 0.12)]
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * (0.6 + 0.4 * r)) for r, a in partials)


def build_lantern_chime():
    # Warm metallic lantern clang: a struck low bell plus a high ting and a faint shimmer.
    length = int(1.1 * RATE)
    out = np.zeros(length)
    main = bell(freq("D5"), 1.1, 3.2)
    out[: len(main)] += main * 0.5
    ting = bell(freq("A6"), 0.6, 7.0)
    start = int(0.015 * RATE)
    out[start:start + len(ting)] += ting * 0.22
    t = np.arange(length) / RATE
    out += np.sin(2 * np.pi * (freq("D5") * 2.0 * (1 + 0.004 * np.sin(2 * np.pi * 7 * t))) * t) * np.exp(-t * 3.0) * 0.12
    out *= np.clip(t / 0.002, 0, 1)
    return out / np.max(np.abs(out)) * 0.8


def build_haunted_star():
    # Rising D minor arpeggio of glassy bells, each followed by a wobbling, fading ghost echo.
    length = int(1.5 * RATE)
    dry = np.zeros(length)
    for note, delay in [("D5", 0.0), ("F5", 0.07), ("A5", 0.14), ("D6", 0.21)]:
        start = int(delay * RATE)
        t = np.arange(length - start) / RATE
        f = freq(note)
        tone = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t)) * np.exp(-t * 6.0)
        dry[start:] += tone * 0.3
    t = np.arange(length) / RATE
    wet = np.zeros(length)
    for k, (delay, gain) in enumerate([(0.2, 0.5), (0.4, 0.3), (0.6, 0.18), (0.8, 0.1)]):
        d = int(delay * RATE)
        # The echo is slightly detuned and warbles, like a distant voice.
        shifted = np.interp(np.arange(length) * (1.0 - 0.012 * (k + 1)), np.arange(length), dry)
        warble = 0.7 + 0.3 * np.sin(2 * np.pi * (5.0 + k) * t)
        wet[d:] += (shifted * warble)[: length - d] * gain
    out = dry + wet
    return out / np.max(np.abs(out)) * 0.8


def build_ghost_king_laugh():
    # "Hu-ha-ha-ha": four falling vowel bursts built from formant-weighted harmonics,
    # a wide vibrato and a hollow echo.
    seconds = 1.3
    length = int(seconds * RATE)
    out = np.zeros(length)
    for i, (start, dur, f0, vowel) in enumerate([(0.0, 0.2, 150.0, (500.0, 1100.0)), (0.27, 0.17, 135.0, (750.0, 1250.0)),
                                                   (0.5, 0.17, 125.0, (750.0, 1250.0)), (0.73, 0.28, 112.0, (700.0, 1150.0))]):
        n = int(dur * RATE)
        t = np.arange(n) / RATE
        glide = f0 * (1.12 - 0.22 * t / dur) * (1.0 + 0.025 * np.sin(2 * np.pi * 7.5 * t))
        phase = np.cumsum(glide) / RATE
        voice = np.zeros(n)
        for h in range(1, 40):
            hz = h * f0
            weight = np.exp(-((hz - vowel[0]) / 170.0) ** 2) + 0.6 * np.exp(-((hz - vowel[1]) / 230.0) ** 2) + 0.05 / h
            voice += weight * np.sin(2 * np.pi * phase * h)
        env = np.clip(t / 0.015, 0, 1) * np.exp(-t * 6.0) * np.clip((dur - t) / 0.03, 0, 1)
        # A whisper of breath at each onset, as in "h".
        breath = np.random.default_rng(i).uniform(-1, 1, n) * np.exp(-t * 60) * 0.25
        begin = int(start * RATE)
        out[begin:begin + n] += (voice * 0.28 + breath) * env
    out = add_echo_tail(out, [(0.14, 0.35), (0.3, 0.2), (0.46, 0.1)])
    return np.tanh(out * 1.4) / np.max(np.abs(np.tanh(out * 1.4))) * 0.75


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def main():
    music_wav = os.path.join(ROOT, "assets", "audio", "music", "haunted_hollow.wav.tmp")
    music_ogg = os.path.join(ROOT, "assets", "audio", "music", "haunted_hollow.ogg")
    write_wav(music_wav, build_music())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "wav", "-i", music_wav, "-c:a", "libvorbis", "-q:a", "4", music_ogg], check=True)
    os.remove(music_wav)
    sfx = os.path.join(ROOT, "assets", "audio", "sfx")
    write_wav(os.path.join(sfx, "ghost_whistle.wav"), build_ghost_whistle())
    write_wav(os.path.join(sfx, "hand_scrape.wav"), build_hand_scrape())
    write_wav(os.path.join(sfx, "lantern_chime.wav"), build_lantern_chime())
    write_wav(os.path.join(sfx, "haunted_star.wav"), build_haunted_star())
    write_wav(os.path.join(sfx, "ghost_king_laugh.wav"), build_ghost_king_laugh())
    print("wrote", music_ogg)


if __name__ == "__main__":
    main()
