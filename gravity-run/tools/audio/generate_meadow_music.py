#!/usr/bin/env python3
"""Chiptune loop for the Meadow (campaign world 1) and the gravity-star chime.

    python3 tools/audio/generate_meadow_music.py

Writes assets/audio/music/meadow_summer.ogg (a seamless ~55 s loop at 140 BPM,
C major: pulse lead, pulse arpeggio, triangle bass, noise drums and a few
bird-like trills) and assets/audio/sfx/gravity_star.wav. Everything is
synthesised here, so the files carry no third-party rights. Needs numpy and
ffmpeg (libvorbis).
"""
import os
import subprocess
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RATE = 44100
## Footsteps of the pixel runners land on every eighth note (main.gd syncs the
## run cycle to the music), so this is also the running cadence.
BPM = 140.0
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
    vibrato = 1.0 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.18, 0, 1)
    phase = np.cumsum(f * vibrato) / RATE
    return np.where(phase % 1.0 < 0.25, 1.0, -1.0) * envelope(n, decay=0.18, sustain=0.5)


def echo_voice(f, t, n):
    return pulse(f, t, 0.5) * envelope(n, decay=0.1, sustain=0.35)


def arp_voice(f, t, n):
    return pulse(f, t, 0.125) * envelope(n, attack=0.002, decay=0.05, sustain=0.2, release=0.01)


def bass_voice(f, t, n):
    return triangle(f, t) * envelope(n, attack=0.003, decay=0.2, sustain=0.75, release=0.02)


CHORDS = {
    "C": ["C", "E", "G"], "G": ["G", "B", "D"], "Am": ["A", "C", "E"], "F": ["F", "A", "C"],
    "Em": ["E", "G", "B"], "Dm": ["D", "F", "A"],
}

# 32 bars: A, B, A (with echo harmony), C (airy bridge). Ends on G -> loops to C.
PROGRESSION = (
    ["C", "G", "Am", "F", "C", "G", "F", "G"]
    + ["F", "G", "Em", "Am", "F", "G", "C", "G"]
    + ["C", "G", "Am", "F", "C", "G", "F", "G"]
    + ["C", "Am", "F", "G", "C", "Am", "F", "G"]
)

MELODY_A = [
    ("E5", 2), ("G5", 2), ("A5", 1), ("G5", 1), ("E5", 2),
    ("D5", 2), ("G5", 2), ("B5", 1), ("A5", 1), ("G5", 2),
    ("C6", 2), ("B5", 1), ("A5", 1), ("E5", 2), ("A5", 2),
    ("G5", 3), ("F5", 1), ("E5", 2), ("D5", 2),
    ("E5", 2), ("G5", 2), ("C6", 2), ("G5", 2),
    ("B5", 2), ("A5", 1), ("G5", 1), ("D5", 2), ("G5", 2),
    ("A5", 2), ("C6", 2), ("A5", 1), ("G5", 1), ("F5", 2),
    ("E5", 2), ("D5", 2), ("C5", 2), ("D5", 2),
]
MELODY_B = [
    ("A5", 1), ("C6", 1), ("A5", 1), ("F5", 1), ("A5", 2), ("C6", 2),
    ("B5", 1), ("D6", 1), ("B5", 1), ("G5", 1), ("B5", 2), ("D6", 2),
    ("G5", 2), ("E5", 2), ("B5", 2), ("G5", 2),
    ("A5", 3), ("G5", 1), ("A5", 2), ("C6", 2),
    ("C6", 2), ("A5", 2), ("F5", 2), ("A5", 2),
    ("D6", 2), ("B5", 2), ("G5", 2), ("B5", 2),
    ("E6", 2), ("D6", 1), ("C6", 1), ("G5", 2), ("E5", 2),
    ("D5", 2), ("E5", 1), ("G5", 1), ("G5", 4),
]
MELODY_C = [
    ("E5", 6), (None, 2), ("C5", 6), (None, 2), ("A4", 6), (None, 2), ("B4", 4), ("D5", 4),
    ("E5", 4), ("G5", 4), ("A5", 6), (None, 2), ("F5", 4), ("A5", 4), ("G5", 6), ("B4", 2),
]


SCALE = ["C", "D", "E", "F", "G", "A", "B"]


def diatonic_shift(notes, steps):
    """Moves each note by scale steps in C major (a third below = -2)."""
    out = []
    for note, length in notes:
        if note is None:
            out.append((None, length))
            continue
        index = SCALE.index(note[:-1]) + 7 * int(note[-1]) + steps
        out.append(("%s%d" % (SCALE[index % 7], index // 7), length))
    return out


def build_music():
    bars = len(PROGRESSION)
    total = int(round(bars * 8 * EIGHTH * RATE))
    lead_notes = MELODY_A + MELODY_B + MELODY_A + MELODY_C
    mix = render_line(lead_notes, lead_voice, 0.16, total)
    # Third-below echo on the repeat of A, delayed by an eighth.
    echo = [(None, 64 + 64 + 1)] + diatonic_shift(MELODY_A, -2)
    mix += render_line(echo, echo_voice, 0.05, total)
    arp, bass = [], []
    for chord in PROGRESSION:
        tones = CHORDS[chord]
        pattern = [tones[0] + "5", tones[1] + "5", tones[2] + "5", tones[1] + "5"] * 4
        arp += [(note, 0.5) for note in pattern]
        root, fifth = tones[0] + "2", tones[2] + "2"
        bass += [(root, 1), (root, 1), (fifth, 1), (root, 1), (root, 1), (root, 1), (fifth, 1), (tones[1] + "2", 1)]
    mix += render_line(arp, arp_voice, 0.045, total)
    mix += render_line(bass, bass_voice, 0.22, total)
    rng = np.random.default_rng(11)
    beat = 2 * EIGHTH
    for b in range(bars * 4):
        t0 = int(b * beat * RATE)
        # Kick on 1 and 3, soft snare on 2 and 4, hats on every off-eighth.
        if b % 2 == 0:
            n = int(0.12 * RATE)
            t = np.arange(n) / RATE
            kick = np.sin(2 * np.pi * (55 + 90 * np.exp(-t * 30)) * t) * np.exp(-t * 22)
            mix[t0:t0 + n] += kick[: max(0, min(n, total - t0))] * 0.35
        else:
            n = int(0.09 * RATE)
            snare = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / RATE * 38)
            mix[t0:t0 + n] += snare[: max(0, min(n, total - t0))] * 0.07
        # Hats on every eighth (the footsteps), accented off-beats.
        for half in (0, 1):
            h0 = int((b * beat + half * EIGHTH) * RATE)
            n = int(0.03 * RATE)
            hat = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / RATE * 140)
            hat = np.diff(hat, prepend=0.0)
            mix[h0:h0 + n] += hat[: max(0, min(n, total - h0))] * (0.055 if half else 0.03)
    # A few bird trills in the airy bridge.
    for bar in (25, 27, 29):
        start = int((bar * 8 + 5) * EIGHTH * RATE)
        for k in range(6):
            n = int(0.035 * RATE)
            t = np.arange(n) / RATE
            f = 2600 + 500 * (k % 2) + 200 * np.sin(t * 90)
            chirp = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.sin(np.pi * t / t[-1])
            s = start + k * int(0.045 * RATE)
            mix[s:s + n] += chirp * 0.035
    mix = np.tanh(mix * 1.1)
    return mix / np.max(np.abs(mix)) * 0.86


def build_star_chime():
    # Rising major arpeggio with a sparkle tail: C6 E6 G6 C7.
    length = int(0.62 * RATE)
    out = np.zeros(length)
    for i, note in enumerate(["C6", "E6", "G6", "C7"]):
        start = int(i * 0.055 * RATE)
        n = length - start
        t = np.arange(n) / RATE
        f = freq(note)
        tone = (0.6 * pulse(f, t, 0.25) + 0.4 * np.sin(2 * np.pi * f * 2 * t)) * np.exp(-t * (7.0 - i))
        out[start:] += tone * 0.32
    t = np.arange(length) / RATE
    sparkle = np.sin(2 * np.pi * 4186.0 * t) * (np.sin(2 * np.pi * 18 * t) > 0.6) * np.exp(-t * 6) * 0.08
    out += sparkle
    return out / np.max(np.abs(out)) * 0.8


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def main():
    music_wav = os.path.join(ROOT, "assets", "audio", "music", "meadow_summer.wav.tmp")
    music_ogg = os.path.join(ROOT, "assets", "audio", "music", "meadow_summer.ogg")
    write_wav(music_wav, build_music())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "wav", "-i", music_wav, "-c:a", "libvorbis", "-q:a", "4", music_ogg], check=True)
    os.remove(music_wav)
    write_wav(os.path.join(ROOT, "assets", "audio", "sfx", "gravity_star.wav"), build_star_chime())
    print("wrote", music_ogg)


if __name__ == "__main__":
    main()
