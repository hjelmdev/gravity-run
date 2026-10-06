"""Offline generator for short interchangeable Gravity Run SFX WAV drafts."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
TAU = math.tau


def soften(samples, level=0.18):
    peak = max(abs(x) for x in samples) or 1
    return [x * level / peak for x in samples]


def save(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(x * 32767)) for x in samples))


def edge(t, duration):
    return min(1, t / 0.004) * min(1, max(0, duration - t) / 0.012)


def barrel_destroy():
    duration = 0.34
    rng = random.Random(29)
    samples = []
    low_noise = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        low_noise = 0.88 * low_noise + 0.12 * rng.uniform(-1, 1)
        thud = math.sin(TAU * (115 * t - 80 * t * t)) * math.exp(-t * 18)
        crack = rng.uniform(-1, 1) * math.exp(-t * 32)
        samples.append((0.75 * thud + 0.6 * low_noise * math.exp(-t * 8) + 0.45 * crack) * edge(t, duration))
    return soften(samples, 0.15)


def ghost_warning():
	# A soft two-tone chime; no sustained tone or high-energy pulse.
	duration = 0.36
	data = []
	for i in range(round(duration * RATE)):
		t = i / RATE
		attack = min(1.0, t / 0.015)
		envelope = attack * math.exp(-t * 8.0) * edge(t, duration)
		blend = math.sin(TAU * 660.0 * t) + 0.45 * math.sin(TAU * 990.0 * max(0.0, t - 0.09)) * min(1.0, max(0.0, (t - 0.09) / 0.01))
		data.append(blend * envelope)
	return soften(data, 0.12)


def coin():
    duration = 0.24
    data = []
    for i in range(round(duration * RATE)):
        t = i / RATE
        first = math.sin(TAU * 1175 * t) * math.exp(-t * 35)
        second_t = max(0, t - 0.055)
        second = (math.sin(TAU * 1760 * second_t) + 0.2 * math.sin(TAU * 3520 * second_t))
        second *= math.exp(-second_t * 24) * min(1, second_t / 0.003)
        data.append((first + second) * edge(t, duration))
    return soften(data)


def flip():
    duration = 0.28
    data = []
    # Keep the original gain reference while omitting the rejected air layer.
    # This preserves the accepted tone's phase, envelope and level exactly.
    original_mix = []
    rng = random.Random(42)
    air = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        phase = TAU * (240 * t + 1100 * t * t)
        air = 0.65 * air + 0.35 * rng.uniform(-1, 1)
        envelope = math.sin(math.pi * t / duration) ** 2
        original_mix.append((0.7 * math.sin(phase) + 0.3 * air) * envelope)
        data.append(0.7 * math.sin(phase) * envelope)
    reference_peak = max(abs(x) for x in original_mix) or 1
    return [x * 0.18 / reference_peak for x in data]


def impact():
    duration = 0.52
    data = []
    rng = random.Random(7)
    noise = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        noise = 0.92 * noise + 0.08 * rng.uniform(-1, 1)
        body = math.sin(TAU * (90 * t - 42 * t * t)) * math.exp(-t * 16)
        grit = noise * math.exp(-t * 12)
        data.append((0.65 * body + 1.8 * grit) * edge(t, duration))
    return soften(data)


def main():
    clips = [("coin.wav", coin()), ("gravity_flip.wav", flip()), ("rock_impact.wav", impact()), ("barrel_destroy.wav", barrel_destroy()), ("ghost_warning.wav", ghost_warning())]
    for name, samples in clips:
        save(name, samples)
        with wave.open(str(OUT / name), "rb") as check:
            print(f"{name}: {check.getnframes() / RATE:.2f}s, PCM16 mono {RATE}Hz")


if __name__ == "__main__":
    main()
