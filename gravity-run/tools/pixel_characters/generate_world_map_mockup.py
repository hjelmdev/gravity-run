#!/usr/bin/env python3
"""Pixel-art mockup of the campaign world map ("Ängen").

    python3 tools/pixel_characters/generate_world_map_mockup.py out.png

The map is painted at 320x180 and scaled x3 to 960x540 (same pixel density as
the 32x32 runners at x2 would read on a map), then UI cards are drawn on top
in a clean font like the in-game theme. Concept art only.
"""
import math
import os
import random
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
W, H, SCALE = 320, 180, 3

GRASS = [(96, 168, 82), (88, 158, 76), (104, 176, 88)]
GRASS_DARK = (70, 132, 66)
FLOWERS = [(250, 246, 220), (255, 214, 92), (238, 132, 168), (180, 160, 240)]
PATH = (226, 196, 140)
PATH_DARK = (176, 142, 96)
PATH_LIGHT = (240, 218, 170)
WATER = (64, 152, 214)
WATER_LIGHT = (130, 200, 240)
WATER_DARK = (40, 110, 170)
OUTLINE = (20, 20, 28)
TRUNK = (110, 74, 52)
LEAF = [(52, 128, 70), (66, 150, 80), (90, 176, 96)]
STONE = (170, 176, 190)
STONE_LIGHT = (214, 220, 230)
STONE_DARK = (110, 116, 132)
TEAL = (66, 214, 197)
GOLD = (255, 205, 60)
GOLD_DARK = (200, 140, 30)
RED = (196, 64, 84)


def catmull(points, steps=40):
    out = []
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(points[-1])
    return out


def disc(px, cx, cy, r, color):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r and 0 <= x < W and 0 <= y < H:
                px[x, y] = color


def paint():
    rng = random.Random(7)
    img = Image.new("RGB", (W, H))
    px = img.load()
    # Grass with a soft dither and darker patches.
    for y in range(H):
        for x in range(W):
            n = (x * 7 + y * 13 + (x * y) % 5) % 9
            px[x, y] = GRASS[0] if n < 6 else GRASS[1] if n < 8 else GRASS[2]
    for _ in range(26):
        cx, cy, r = rng.randint(0, W), rng.randint(20, H), rng.randint(5, 14)
        for y in range(cy - r, cy + r):
            for x in range(cx - r * 2, cx + r * 2):
                if 0 <= x < W and 0 <= y < H and ((x - cx) / 2) ** 2 + (y - cy) ** 2 < r * r and (x + y) % 2 == 0:
                    px[x, y] = GRASS_DARK
    # Distant hills along the top.
    for x in range(W):
        top = int(18 + 7 * math.sin(x / 23.0) + 4 * math.sin(x / 9.0 + 1.3))
        for y in range(0, top):
            px[x, y] = (140, 200, 236) if y < top - 10 else (118, 178, 120)
        for y in range(max(0, top - 10), top):
            px[x, y] = (78, 140, 92) if (x + y) % 3 else (70, 128, 84)
        px[x, top] = (60, 112, 72)
    # River from top to bottom-right.
    river = catmull([(250, 0), (232, 40), (262, 80), (248, 120), (276, 180)], 30)
    for (x, y) in river:
        for dx in range(-6, 7):
            xx = int(x + dx)
            if 0 <= xx < W and 0 <= int(y) < H:
                px[xx, int(y)] = WATER_DARK if abs(dx) >= 5 else WATER
    for i, (x, y) in enumerate(river):
        if i % 7 == 0 and 0 <= int(y) < H:
            for dx in (-2, -1, 0):
                if 0 <= int(x) + dx < W:
                    px[int(x) + dx, int(y)] = WATER_LIGHT
    return img, rng


NODES = [(38, 138), (78, 112), (118, 134), (158, 100), (200, 122), (238, 92), (286, 66)]
STATE = ["done", "done", "done", "current", "locked", "locked", "boss"]
STARS = [3, 2, 1, 0, 0, 0, 0]


def draw_path(img):
    px = img.load()
    curve = catmull(NODES, 36)
    for (x, y) in curve:
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx * dx + dy * dy <= 9:
                    xx, yy = int(x + dx), int(y + dy)
                    if 0 <= xx < W and 0 <= yy < H:
                        px[xx, yy] = PATH_DARK
    for (x, y) in curve:
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 4:
                    xx, yy = int(x + dx), int(y + dy)
                    if 0 <= xx < W and 0 <= yy < H:
                        px[xx, yy] = PATH
    for i, (x, y) in enumerate(curve):
        if i % 9 == 0:
            px[int(x), int(y) - 1] = PATH_LIGHT
    # Locked part of the path is faded with grass dots.
    start = 3 * 36
    for (x, y) in curve[start + 6:]:
        if (int(x) + int(y)) % 3 == 0:
            px[int(x), int(y)] = GRASS[0]
    # Plank bridge over the river.
    for (x, y) in curve:
        if 236 <= x <= 262 and abs(y - 96) < 30:
            for dy in range(-3, 4):
                xx, yy = int(x), int(y + dy)
                if 0 <= yy < H and px[xx, yy] in (WATER, WATER_DARK, WATER_LIGHT):
                    px[xx, yy] = (150, 104, 66) if xx % 3 else (112, 76, 50)


def tree(px, x, y, rng):
    for dx in range(-4, 5):
        if 0 <= x + dx < W and 0 <= y + 2 < H:
            px[x + dx, y + 2] = (64, 120, 62)
    for dy in range(-2, 2):
        px[x, y + dy] = TRUNK
    disc(px, x, y - 6, 5.2, OUTLINE)
    disc(px, x, y - 6, 4.4, LEAF[0])
    disc(px, x - 1, y - 7, 3.2, LEAF[1])
    disc(px, x - 2, y - 8, 1.5, LEAF[2])


def decorate(img, rng):
    px = img.load()
    curve = catmull(NODES, 36)
    def near_path(x, y, d=10):
        return any((x - cx) ** 2 + (y - cy) ** 2 < d * d for cx, cy in curve[::3])
    placed = 0
    while placed < 34:
        x, y = rng.randint(6, W - 6), rng.randint(34, H - 6)
        if near_path(x, y, 14) or 222 < x < 284:
            continue
        tree(px, x, y, rng)
        placed += 1
    for _ in range(160):
        x, y = rng.randint(0, W - 1), rng.randint(30, H - 1)
        if not near_path(x, y, 6) and px[x, y] in GRASS + [GRASS_DARK]:
            px[x, y] = rng.choice(FLOWERS)


def node(px, x, y, state):
    r = 7 if state != "boss" else 9
    disc(px, x, y + 2, r + 1, OUTLINE)
    disc(px, x, y + 1, r, STONE_DARK if state != "locked" else (90, 94, 106))
    disc(px, x, y, r, OUTLINE)
    top = {"done": TEAL, "current": GOLD, "locked": (128, 132, 146), "boss": RED}[state]
    disc(px, x, y - 1, r - 1, top)
    disc(px, x - 2, y - 3, 2, tuple(min(255, c + 40) for c in top))


def star(px, x, y, filled):
    shape = ["...#...", "..###..", "#######", ".#####.", ".##.##.", "#.....#"]
    for dy, row in enumerate(shape):
        for dx, ch in enumerate(row):
            if ch == "#":
                px[x + dx - 3, y + dy] = (GOLD if dy < 3 else GOLD_DARK) if filled else (64, 70, 84)


def padlock(px, x, y):
    for dx in range(-2, 3):
        for dy in range(0, 4):
            px[x + dx, y + dy] = (52, 52, 64)
    for dx in (-2, 2):
        px[x + dx, y - 1] = (52, 52, 64)
        px[x + dx, y - 2] = (52, 52, 64)
    for dx in (-1, 0, 1):
        px[x + dx, y - 3] = (52, 52, 64)
    px[x, y + 1] = GOLD


def boss_machine(img, x, y):
    px = img.load()
    # Rullaren: a barrel-throwing machine on the boss node.
    for dy in range(-22, -6):
        for dx in range(-9, 10):
            px[x + dx, y + dy] = (120, 84, 70) if abs(dx) < 9 and dy > -21 else OUTLINE
    for dx in range(-9, 10):
        px[x + dx, y - 15] = (90, 60, 50)
    for dy in range(-30, -21):
        for dx in (-5, -4, -3):
            px[x + dx, y + dy] = (90, 94, 106)
    for i, (sx, sy) in enumerate([(-4, -34), (-1, -38), (-5, -41)]):
        disc(px, x + sx, y + sy, 2.2 - i * 0.4, (200, 204, 214))
    # Barrel at the hatch and glowing eyes.
    disc(px, x + 7, y - 9, 3.6, OUTLINE)
    disc(px, x + 7, y - 9, 2.8, (184, 120, 64))
    px[x + 7, y - 10] = (226, 170, 100)
    for ex in (-4, 2):
        px[x + ex, y - 18] = (255, 90, 70)
        px[x + ex + 1, y - 18] = (255, 90, 70)


def render(out_path):
    img, rng = paint()
    draw_path(img)
    decorate(img, rng)
    px = img.load()
    for i, ((x, y), st) in enumerate(zip(NODES, STATE)):
        node(px, x, y, st)
        if st == "locked":
            padlock(px, x + 5, y - 10)
        if st in ("done", "current", "locked"):
            for k in range(3):
                star(px, x - 8 + k * 8, y + 9, k < STARS[i])
    boss_machine(img, *NODES[6])
    big = img.resize((W * SCALE, H * SCALE), Image.NEAREST).convert("RGBA")
    # Avatar: the fox runner at its in-game size (32 px x2) standing on 1-4.
    fox = Image.open(os.path.join(ROOT, "assets/characters/fox/still.png")).resize((64, 64), Image.NEAREST)
    ax, ay = NODES[3]
    big.alpha_composite(fox, (ax * SCALE - 30, ay * SCALE - 62))
    # Node numbers in a pixel-ish bold font.
    d = ImageDraw.Draw(big)
    bold = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    regular = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    for i, ((x, y), st) in enumerate(zip(NODES, STATE)):
        if st == "boss":
            continue
        d.text((x * SCALE, y * SCALE - 3), "1-%d" % (i + 1), font=ImageFont.truetype(bold, 13),
               fill=(20, 20, 28) if st != "locked" else (60, 64, 76), anchor="mm")
    # UI cards (theme colours).
    card, ink, muted, line = (18, 27, 44, 235), (237, 243, 255), (184, 199, 220), (66, 214, 197)
    d.rounded_rectangle([18, 14, 380, 76], 12, fill=card, outline=line, width=2)
    d.text((36, 22), "VÄRLD 1 · ÄNGEN", font=ImageFont.truetype(bold, 22), fill=ink)
    d.text((36, 52), "Gravitationsstjärnor 6/18   ·   Hemligheter 1/6", font=ImageFont.truetype(regular, 13), fill=muted)
    d.rounded_rectangle([566, 420, 942, 524], 12, fill=card, outline=line, width=2)
    d.text((584, 430), "1-4  Fallande stenar", font=ImageFont.truetype(bold, 18), fill=ink)
    d.text((584, 458), "Nytt hinder: fallande sten", font=ImageFont.truetype(regular, 13), fill=muted)
    d.text((584, 478), "Bästa: –   ·   ☆☆☆", font=ImageFont.truetype(regular, 13), fill=muted)
    d.rounded_rectangle([806, 470, 930, 512], 10, fill=line)
    d.text((868, 491), "SPELA", font=ImageFont.truetype(bold, 16), fill=(18, 27, 44), anchor="mm")
    d.rounded_rectangle([744, 14, 942, 52], 10, fill=card, outline=(196, 64, 84), width=2)
    d.text((843, 33), "Boss: Rullaren", font=ImageFont.truetype(bold, 14), fill=ink, anchor="mm")
    d.text((26, 512), "◀  Världar  ▶", font=ImageFont.truetype(bold, 13), fill=ink)
    big.convert("RGB").save(out_path)


if __name__ == "__main__":
    render(sys.argv[1] if len(sys.argv) > 1 else "world_map_mockup.png")
