#!/usr/bin/env python3
"""Chiptune loop for the Cave (campaign world 2) and the cave sound effects.

    python3 tools/audio/generate_cave_audio.py

Writes assets/audio/music/cave_echoes.ogg (a seamless ~38 s loop at 150 BPM in
A minor: pulse lead with a circular echo, soft arpeggio, triangle bass and
dripping percussion) and five effects in assets/audio/sfx/: icicle_crack.wav,
cave_in_rumble.wav, crystal_chime.wav, cave_bat_screech.wav and
cave_icicle_shatter.wav. Everything is synthesised here, so
the files carry no third-party rights. Needs numpy and ffmpeg (libvorbis).
Modelled on generate_meadow_music.py.
"""
import os
import subprocess
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RATE = 44100
## main.gd syncs the runner's feet to this tempo (one footstep per eighth note).
BPM = 150.0
EIGHTH = 60.0 / BPM / 2.0
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NOTES[pitch]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def pulse(f, t, duty):
    return np.where((t * f) % 1.0 < duty, 1.0, -1.0)


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


def lead_voice(f, t, n):
    vibrato = 1.0 + 0.003 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.2, 0, 1)
    phase = np.cumsum(f * vibrato) / RATE
    return np.where(phase % 1.0 < 0.25, 1.0, -1.0) * envelope(n, decay=0.22, sustain=0.45, release=0.06)


def arp_voice(f, t, n):
    return pulse(f, t, 0.125) * envelope(n, attack=0.002, decay=0.06, sustain=0.15, release=0.01)


def bass_voice(f, t, n):
    return triangle(f, t) * envelope(n, attack=0.003, decay=0.2, sustain=0.7, release=0.03)


CHORDS = {
    "Am": ["A", "C", "E"], "F": ["F", "A", "C"], "C": ["C", "E", "G"], "G": ["G", "B", "D"],
    "Dm": ["D", "F", "A"], "E": ["E", "G#", "B"],
}
# 24 bars: A, B, A. The harmonic-minor E chord pulls back to Am at the loop.
PROGRESSION = (
    ["Am", "F", "C", "G", "Am", "F", "E", "Am"]
    + ["Dm", "Am", "Dm", "Am", "F", "C", "E", "E"]
    + ["Am", "F", "C", "G", "Am", "F", "E", "Am"]
)
A_MINOR = ["A", "B", "C", "D", "E", "F", "G"]
RHYTHMS = [[2, 2, 2, 2], [3, 1, 2, 2], [2, 1, 1, 2, 2], [1, 1, 2, 2, 2], [4, 2, 2], [2, 2, 1, 1, 2]]


def build_melody():
    """Stepwise, chord-anchored melody in a fixed order so the file is stable."""
    rng = np.random.default_rng(23)
    notes = []
    degree = 14  # A5-ish index into the scale ladder
    section_a = None
    for index, chord in enumerate(PROGRESSION):
        if index >= 16:
            if index == 16:
                notes.extend(section_a)
            continue
        tones = CHORDS[chord]
        bar = []
        for length in RHYTHMS[int(rng.integers(len(RHYTHMS)))]:
            if not bar:
                # Land the bar's first note on a chord tone near the last note.
                best = min(range(10, 20), key=lambda d: (abs(d - degree) + (0 if A_MINOR[d % 7] in [t[0] for t in tones] else 3)))
                degree = best
            else:
                degree = int(np.clip(degree + int(rng.choice([-2, -1, -1, 1, 1, 2])), 10, 19))
            pitch = A_MINOR[degree % 7]
            if chord == "E" and pitch == "G":
                pitch = "G#"
            bar.append((pitch + str(degree // 7 + 3 + 1), length))
        if index == 7 or index == 15:
            bar = [(bar[0][0], 4), (None, 4)]  # breathe at the end of a phrase
        notes.extend(bar)
        if index < 8:
            section_a = (section_a or []) + bar
    return notes


def add_echo(line):
    """Circular echo: the tail of the loop wraps to the start, so it is seamless."""
    delay = int(round(3 * EIGHTH * RATE))
    out = line.copy()
    for k, gain in enumerate([0.55, 0.32, 0.18, 0.1], start=1):
        out += np.roll(line, delay * k) * gain
    return out


def drip(freq_hz, length=0.16, gain=0.2):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    sweep = freq_hz * (1.0 + 0.9 * np.exp(-t * 40))
    return np.sin(2 * np.pi * np.cumsum(sweep) / RATE) * np.exp(-t * 26) * gain


def build_music():
    bars = len(PROGRESSION)
    total = int(round(bars * 8 * EIGHTH * RATE))
    mix = add_echo(render_line(build_melody(), lead_voice, 0.15, total))
    arp, bass = [], []
    for chord in PROGRESSION:
        tones = CHORDS[chord]
        pattern = [tones[0] + "4", tones[1] + "4", tones[2] + "4", tones[1] + "4"] * 4
        arp += [(note, 0.5) for note in pattern]
        root, fifth = tones[0] + "2", tones[2] + "2"
        bass += [(root, 1), (None, 1), (root, 1), (fifth, 1), (root, 1), (None, 1), (fifth, 1), (tones[1] + "2", 1)]
    mix += add_echo(render_line(arp, arp_voice, 0.04, total)) * 0.6
    mix += render_line(bass, bass_voice, 0.22, total)
    rng = np.random.default_rng(5)
    beat = 2 * EIGHTH
    pings = [freq("E6"), freq("A6"), freq("C7"), freq("G6")]
    for b in range(bars * 4):
        t0 = int(b * beat * RATE)

        def put(at, sound):
            end = min(total, at + len(sound))
            if end > at:
                mix[at:end] += sound[: end - at]

        if b % 2 == 0:
            n = int(0.14 * RATE)
            t = np.arange(n) / RATE
            put(t0, np.sin(2 * np.pi * (50 + 80 * np.exp(-t * 28)) * t) * np.exp(-t * 20) * 0.34)
        else:
            n = int(0.07 * RATE)
            put(t0, rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / RATE * 45) * 0.05)
        # Water drops on a skipping pattern: the echo-y heart of the groove.
        for half in (0, 1):
            slot = (b * 2 + half) % 8
            if slot in (1, 4, 7):
                put(int((b * beat + half * EIGHTH) * RATE), drip(pings[(b + slot) % 4], gain=0.16))
            elif half == 1:
                n = int(0.02 * RATE)
                tick = np.diff(rng.uniform(-1, 1, n), prepend=0.0) * np.exp(-np.arange(n) / RATE * 220)
                put(int((b * beat + EIGHTH) * RATE), tick * 0.05)
    mix = np.tanh(mix * 1.1)
    return mix / np.max(np.abs(mix)) * 0.86


def build_icicle_crack():
    # Sharp glassy snap, a few fast tinkling splinters and a short low tick.
    length = int(0.5 * RATE)
    rng = np.random.default_rng(31)
    out = np.zeros(length)
    n = int(0.03 * RATE)
    out[:n] += np.diff(rng.uniform(-1, 1, n), prepend=0.0) * np.exp(-np.arange(n) / RATE * 160) * 0.8
    for i, hz in enumerate([3100, 4200, 2600, 5200]):
        start = int((0.012 + i * 0.045) * RATE)
        m = length - start
        t = np.arange(m) / RATE
        out[start:] += np.sin(2 * np.pi * hz * t * (1 + 0.03 * np.exp(-t * 60))) * np.exp(-t * (28 + i * 6)) * 0.28
    t = np.arange(length) / RATE
    out += np.sin(2 * np.pi * 180 * t) * np.exp(-t * 55) * 0.35
    return out / np.max(np.abs(out)) * 0.8


def build_cave_in_rumble():
    # Low rock rumble: brown noise swell, sub wobble and a few grinding knocks.
    seconds = 1.8
    length = int(seconds * RATE)
    rng = np.random.default_rng(47)
    noise = np.cumsum(rng.uniform(-1, 1, length))
    noise -= np.convolve(noise, np.ones(2000) / 2000, mode="same")
    noise /= np.max(np.abs(noise))
    t = np.arange(length) / RATE
    env = np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.5, 0) * 1.7) * np.clip((seconds - t) / 0.2, 0, 1)
    out = noise * env * 0.75
    out += np.sin(2 * np.pi * (46 + 6 * np.sin(2 * np.pi * 7 * t)) * t) * env * 0.4
    for k in range(9):
        at = int(rng.uniform(0.1, 1.3) * RATE)
        m = int(0.09 * RATE)
        thud = np.sin(2 * np.pi * rng.uniform(70, 130) * np.arange(m) / RATE) * np.exp(-np.arange(m) / RATE * 38) * 0.5
        out[at:at + m] += thud[: length - at]
    return np.tanh(out * 1.2) / np.tanh(1.2) * 0.85


def build_crystal_chime():
    # Bright glassy bell: A5 with inharmonic partials plus a rising A minor sparkle.
    length = int(0.9 * RATE)
    out = np.zeros(length)
    for i, (note, delay) in enumerate([("A5", 0.0), ("E6", 0.07), ("A6", 0.14), ("C7", 0.21)]):
        start = int(delay * RATE)
        m = length - start
        t = np.arange(m) / RATE
        f = freq(note)
        tone = (np.sin(2 * np.pi * f * t) + 0.45 * np.sin(2 * np.pi * f * 2.76 * t) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t)) * np.exp(-t * (5.5 + i))
        out[start:] += tone * 0.3
    return out / np.max(np.abs(out)) * 0.8


def build_bat_screech():
    # Short rising shriek: two detuned FM-ish sweeps with a fast tremolo.
    length = int(0.45 * RATE)
    t = np.arange(length) / RATE
    sweep = 2200 + 1900 * (t / t[-1]) ** 0.7 + 180 * np.sin(2 * np.pi * 38 * t)
    phase = np.cumsum(sweep) / RATE
    out = np.sin(2 * np.pi * phase) + 0.6 * np.sin(2 * np.pi * phase * 1.51) + 0.3 * np.sign(np.sin(2 * np.pi * phase * 0.5))
    env = np.clip(t / 0.02, 0, 1) * np.exp(-np.maximum(t - 0.18, 0) * 9) * (0.75 + 0.25 * np.sin(2 * np.pi * 26 * t))
    out = out * env
    return out / np.max(np.abs(out)) * 0.7


def build_icicle_shatter():
    # Big icicle: heavy crack, a spray of glass shards and a low crash thud.
    length = int(1.0 * RATE)
    rng = np.random.default_rng(83)
    out = np.zeros(length)
    n = int(0.05 * RATE)
    out[:n] += np.diff(rng.uniform(-1, 1, n), prepend=0.0) * np.exp(-np.arange(n) / RATE * 90) * 0.9
    for i in range(22):
        start = int((0.01 + i * 0.022 + rng.uniform(0, 0.015)) * RATE)
        m = int(0.18 * RATE)
        if start + m > length:
            break
        t = np.arange(m) / RATE
        hz = rng.uniform(2200, 6200)
        out[start:start + m] += np.sin(2 * np.pi * hz * t) * np.exp(-t * rng.uniform(25, 60)) * (0.22 * (1 - i / 30))
    t = np.arange(length) / RATE
    out += np.sin(2 * np.pi * (95 - 40 * np.minimum(t, 0.3)) * t) * np.exp(-t * 14) * 0.7
    noise = rng.uniform(-1, 1, length) * np.exp(-t * 11) * 0.25
    out += noise
    return np.tanh(out * 1.1) / np.tanh(1.1) * 0.85


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def main():
    music_wav = os.path.join(ROOT, "assets", "audio", "music", "cave_echoes.wav.tmp")
    music_ogg = os.path.join(ROOT, "assets", "audio", "music", "cave_echoes.ogg")
    write_wav(music_wav, build_music())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "wav", "-i", music_wav, "-c:a", "libvorbis", "-q:a", "4", music_ogg], check=True)
    os.remove(music_wav)
    sfx = os.path.join(ROOT, "assets", "audio", "sfx")
    write_wav(os.path.join(sfx, "icicle_crack.wav"), build_icicle_crack())
    write_wav(os.path.join(sfx, "cave_in_rumble.wav"), build_cave_in_rumble())
    write_wav(os.path.join(sfx, "crystal_chime.wav"), build_crystal_chime())
    write_wav(os.path.join(sfx, "cave_bat_screech.wav"), build_bat_screech())
    write_wav(os.path.join(sfx, "cave_icicle_shatter.wav"), build_icicle_shatter())
    print("wrote", music_ogg)


if __name__ == "__main__":
    main()
