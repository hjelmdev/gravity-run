#!/usr/bin/env python3
"""Campaign sound effects: the goal jingle and Rullaren's barrel throw.

    python3 tools/audio/generate_campaign_audio.py

Writes assets/audio/sfx/campaign_goal.wav (a short cheerful chiptune fanfare
that ends on a held, sparkling C major chord) and rullaren_throw.wav (a low
dull "domph" with a short metallic clang on top). Everything is synthesised
here, so the files carry no third-party rights. Needs numpy.
"""
import os
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RATE = 44100


def pulse(f, t, duty):
    return np.where((t * f) % 1.0 < duty, 1.0, -1.0)


def put(out, at, sound):
    end = min(len(out), at + len(sound))
    if end > at:
        out[at:end] += sound[: end - at]


def note(f, length, gain, duty=0.5, decay=6.0, release=0.03):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    env = np.minimum(t / 0.004, 1.0) * np.exp(-t * decay) * np.clip((length - t) / release, 0.0, 1.0)
    return (pulse(f, t, duty) * 0.8 + np.sin(2 * np.pi * f * t) * 0.4) * env * gain


def build_goal():
    out = np.zeros(int(1.6 * RATE))
    step = 0.095
    # Quick climb C5 E5 G5 C6, a little turn, then the held chord.
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5]):
        put(out, int(i * step * RATE), note(f, 0.13, 0.30, 0.25, decay=5.0))
    start = int(6 * step * RATE)
    for f in [523.25, 659.25, 783.99, 1046.5, 1318.5]:
        put(out, start, note(f, 0.95, 0.17, 0.5, decay=2.6, release=0.2))
    # A bright bell sparkle on the top of the chord.
    for i, f in enumerate([2093.0, 2637.0, 3136.0, 4186.0]):
        n = int(0.5 * RATE)
        t = np.arange(n) / RATE
        put(out, start + int((0.04 + i * 0.07) * RATE), np.sin(2 * np.pi * f * t) * np.exp(-t * 9) * 0.1)
    out = np.tanh(out * 1.15)
    return out / np.max(np.abs(out)) * 0.85


def build_throw():
    length = int(0.55 * RATE)
    rng = np.random.default_rng(61)
    t = np.arange(length) / RATE
    # Low, dull thump: a fast downward sine sweep with a soft noise puff.
    phase = np.cumsum(46.0 + 110.0 * np.exp(-t * 30.0)) / RATE
    out = np.sin(2 * np.pi * phase) * np.exp(-t * 11.0) * 0.95
    puff = np.convolve(rng.uniform(-1, 1, length), np.ones(40) / 40, mode="same")
    out += puff * np.exp(-t * 26.0) * 0.5
    # Short metallic clang: inharmonic partials of a struck drum shell.
    clang = np.zeros(length)
    at = int(0.02 * RATE)
    m = length - at
    tc = np.arange(m) / RATE
    for hz, gain, decay in [(610.0, 1.0, 16.0), (1010.0, 0.7, 20.0), (1730.0, 0.5, 26.0), (2650.0, 0.3, 34.0)]:
        clang[at:] += np.sin(2 * np.pi * hz * tc) * np.exp(-tc * decay) * gain
    out += clang * 0.26
    out = np.tanh(out * 1.3) / np.tanh(1.3)
    return out / np.max(np.abs(out)) * 0.85


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def main():
    sfx = os.path.join(ROOT, "assets", "audio", "sfx")
    write_wav(os.path.join(sfx, "campaign_goal.wav"), build_goal())
    write_wav(os.path.join(sfx, "rullaren_throw.wav"), build_throw())
    print("wrote campaign_goal.wav and rullaren_throw.wav")


if __name__ == "__main__":
    main()
