#!/usr/bin/env python3
"""Paints the campaign world map backgrounds (320x180 pixel art).

    python3 tools/campaign/generate_world_maps.py [out_dir]

One map per world: terrain, the path through the stage nodes, decoration and
water/lava. Stage stones, stars, padlocks, the avatar and the boss are drawn
by the game on top (ui/campaign/world_map.gd), so these images never need to
change when progress changes. Node positions must match
campaign/campaign_catalog.gd (*_MAP_NODES).
"""
import math
import os
import random
import sys
from PIL import Image

W, H = 320, 180
OUTLINE = (20, 20, 28)

THEMES = {
    "map_meadow": {
        "nodes": [(38, 138), (78, 112), (118, 134), (158, 100), (200, 122), (238, 92), (286, 66)],
        "ground": [(96, 168, 82), (88, 158, 76), (104, 176, 88)], "ground_dark": (70, 132, 66),
        "sky": (140, 200, 236), "horizon": [(78, 140, 92), (70, 128, 84)], "horizon_line": (60, 112, 72),
        "path": (226, 196, 140), "path_dark": (176, 142, 96), "path_light": (240, 218, 170),
        "water": [(64, 152, 214), (40, 110, 170), (130, 200, 240)],
        "river": [(250, 0), (232, 40), (262, 80), (248, 120), (276, 180)], "bridge": (150, 104, 66),
        "props": "trees", "sparkles": [(250, 246, 220), (255, 214, 92), (238, 132, 168), (180, 160, 240)],
    },
    "map_cave": {
        "nodes": [(34, 70), (74, 98), (116, 74), (156, 110), (196, 84), (238, 118), (284, 92)],
        "ground": [(74, 78, 96), (68, 72, 90), (80, 86, 104)], "ground_dark": (56, 60, 76),
        "sky": (30, 30, 42), "horizon": [(46, 48, 62), (40, 42, 56)], "horizon_line": (24, 24, 34),
        "path": (150, 140, 120), "path_dark": (104, 96, 84), "path_light": (176, 168, 150),
        "water": [(48, 110, 160), (30, 76, 120), (110, 180, 220)],
        "lake": (70, 150, 34, 18), "bridge": (110, 80, 60),
        "props": "crystals", "sparkles": [(120, 220, 255), (200, 160, 255), (160, 255, 220)],
    },
    "map_haunted": {
        "nodes": [(36, 120), (78, 92), (118, 124), (160, 96), (202, 130), (242, 100), (286, 74)],
        "ground": [(58, 72, 70), (52, 64, 64), (64, 80, 76)], "ground_dark": (42, 52, 54),
        "sky": (46, 40, 78), "horizon": [(36, 44, 58), (30, 38, 50)], "horizon_line": (22, 26, 36),
        "path": (150, 136, 122), "path_dark": (104, 92, 84), "path_light": (176, 164, 150),
        "water": [(70, 90, 110), (50, 64, 84), (120, 150, 170)],
        "river": [(120, 180), (110, 160), (96, 150)], "bridge": (90, 70, 60),
        "props": "graves", "sparkles": [(170, 255, 200), (200, 180, 255)], "moon": (262, 22),
    },
    "map_volcano": {
        "nodes": [(36, 96), (76, 128), (118, 100), (158, 132), (200, 104), (240, 134), (286, 104)],
        "ground": [(72, 54, 52), (64, 48, 48), (80, 60, 56)], "ground_dark": (50, 38, 40),
        "sky": (120, 52, 44), "horizon": [(60, 36, 36), (52, 32, 34)], "horizon_line": (34, 22, 26),
        "path": (140, 120, 104), "path_dark": (96, 80, 72), "path_light": (168, 150, 132),
        "water": [(255, 120, 40), (200, 60, 30), (255, 210, 90)],
        "river": [(176, 0), (186, 40), (172, 80), (184, 118), (176, 180)], "bridge": (90, 90, 100),
        "props": "rocks", "sparkles": [(255, 170, 60), (255, 220, 120)], "volcano": (60, 30),
    },
}


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


def put(px, x, y, color):
    if 0 <= x < W and 0 <= y < H:
        px[int(x), int(y)] = color


def disc(px, cx, cy, r, color):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                put(px, x, y, color)


def paint_ground(px, theme, rng):
    g = theme["ground"]
    for y in range(H):
        for x in range(W):
            n = (x * 7 + y * 13 + (x * y) % 5) % 9
            px[x, y] = g[0] if n < 6 else g[1] if n < 8 else g[2]
    for _ in range(26):
        cx, cy, r = rng.randint(0, W), rng.randint(20, H), rng.randint(5, 14)
        for y in range(cy - r, cy + r):
            for x in range(cx - r * 2, cx + r * 2):
                if 0 <= x < W and 0 <= y < H and ((x - cx) / 2) ** 2 + (y - cy) ** 2 < r * r and (x + y) % 2 == 0:
                    px[x, y] = theme["ground_dark"]
    # Horizon band along the top: hills, cave ceiling, dark woods or ash.
    for x in range(W):
        top = int(18 + 7 * math.sin(x / 23.0) + 4 * math.sin(x / 9.0 + 1.3))
        for y in range(0, top):
            px[x, y] = theme["sky"] if y < top - 10 else theme["horizon"][0]
        for y in range(max(0, top - 10), top):
            px[x, y] = theme["horizon"][0] if (x + y) % 3 else theme["horizon"][1]
        px[x, top] = theme["horizon_line"]
    if theme["props"] == "crystals":
        # Stalactites hanging from the cave ceiling.
        for x in range(4, W, 11):
            length = 6 + (x * 7) % 9
            top = int(18 + 7 * math.sin(x / 23.0) + 4 * math.sin(x / 9.0 + 1.3))
            for i in range(length):
                for dx in range(-max(0, 2 - i // 3), max(0, 2 - i // 3) + 1):
                    put(px, x + dx, top + i, theme["horizon"][1])
    if "moon" in theme:
        mx, my = theme["moon"]
        disc(px, mx, my, 9, (236, 232, 200))
        disc(px, mx + 3, my - 2, 8, theme["sky"])
        for _ in range(30):
            put(px, rng.randint(0, W - 1), rng.randint(0, 12), (220, 220, 255))
    if "volcano" in theme:
        vx, vy = theme["volcano"]
        for y in range(4, 26):
            half = (y - 4) * 1.6 + 4
            for x in range(int(vx - half), int(vx + half)):
                put(px, x, y, (52, 32, 34) if (x + y) % 4 else (44, 28, 30))
        for x in range(vx - 4, vx + 4):
            put(px, x, 4, (255, 140, 50))
            put(px, x, 5, (255, 200, 90))
        for i in range(8):
            disc(px, vx - 2 + i * 2, 0 - i, 3 + i * 0.5, (90, 70, 70))


def paint_water(px, theme):
    water, dark, light = theme["water"]
    if "river" in theme:
        river = catmull(theme["river"], 30)
        # Bank first, then the water, sampled densely so there are no gaps.
        dense = []
        for a, b in zip(river, river[1:]):
            steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
            for k in range(steps):
                dense.append((a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps))
        for (x, y) in dense:
            for dx in range(-6, 7):
                put(px, x + dx, y, dark)
        for (x, y) in dense:
            for dx in range(-4, 5):
                put(px, x + dx, y, water)
        for i, (x, y) in enumerate(dense):
            if i % 9 == 0:
                for dx in (-2, -1, 0):
                    put(px, x + dx + (i // 9) % 3 - 1, y, light)
    if "lake" in theme:
        cx, cy, rx, ry = theme["lake"]
        for y in range(cy - ry - 1, cy + ry + 2):
            for x in range(cx - rx - 1, cx + rx + 2):
                d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if d <= 1.0:
                    put(px, x, y, dark if d > 0.75 else water)
                    if d < 0.5 and (x * 3 + y * 5) % 17 == 0:
                        put(px, x, y, light)


def draw_path(px, theme):
    curve = catmull(theme["nodes"], 36)
    water = set(theme["water"])
    for (x, y) in curve:
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx * dx + dy * dy <= 9:
                    xx, yy = int(x + dx), int(y + dy)
                    if 0 <= xx < W and 0 <= yy < H:
                        px[xx, yy] = theme["bridge"] if px[xx, yy] in water else theme["path_dark"]
    for (x, y) in curve:
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 4:
                    xx, yy = int(x + dx), int(y + dy)
                    if 0 <= xx < W and 0 <= yy < H:
                        if px[xx, yy] == theme["bridge"]:
                            px[xx, yy] = theme["bridge"] if xx % 3 else OUTLINE
                        else:
                            px[xx, yy] = theme["path"]
    for i, (x, y) in enumerate(curve):
        if i % 9 == 0 and px[int(x), int(y) - 1] == theme["path"]:
            put(px, x, y - 1, theme["path_light"])
    return curve


def tree(px, x, y):
    leaf = [(52, 128, 70), (66, 150, 80), (90, 176, 96)]
    for dx in range(-4, 5):
        put(px, x + dx, y + 2, (64, 120, 62))
    for dy in range(-2, 2):
        put(px, x, y + dy, (110, 74, 52))
    disc(px, x, y - 6, 5.2, OUTLINE)
    disc(px, x, y - 6, 4.4, leaf[0])
    disc(px, x - 1, y - 7, 3.2, leaf[1])
    disc(px, x - 2, y - 8, 1.5, leaf[2])


def crystal(px, x, y, color):
    for i in range(7):
        half = max(0, 2 - abs(i - 3) // 2)
        for dx in range(-half, half + 1):
            put(px, x + dx, y - i, color if dx < 1 else tuple(max(0, c - 50) for c in color))
    put(px, x - 1, y - 5, (240, 250, 255))
    for dx in range(-3, 4):
        put(px, x + dx, y + 1, (40, 42, 54))


def stalagmite(px, x, y):
    for i in range(9):
        half = max(0, 3 - i // 3)
        for dx in range(-half, half + 1):
            put(px, x + dx, y - i, (96, 100, 118) if dx < 0 else (70, 74, 90))


def dead_tree(px, x, y):
    for dy in range(-10, 2):
        put(px, x, y + dy, (40, 34, 40))
    for i in range(5):
        put(px, x - i, y - 6 - i // 2, (40, 34, 40))
        put(px, x + i, y - 8 - i // 2, (40, 34, 40))
    put(px, x - 5, y - 9, (40, 34, 40))
    put(px, x + 5, y - 11, (40, 34, 40))


def grave(px, x, y):
    for dy in range(-6, 1):
        for dx in range(-2, 3):
            put(px, x + dx, y + dy, (120, 124, 140) if dx < 1 else (92, 96, 112))
    put(px, x - 1, y - 7, (120, 124, 140))
    put(px, x, y - 7, (120, 124, 140))
    put(px, x + 1, y - 7, (92, 96, 112))
    put(px, x, y - 4, (60, 62, 74))
    put(px, x - 1, y - 4, (60, 62, 74))
    put(px, x + 1, y - 4, (60, 62, 74))
    put(px, x, y - 5, (60, 62, 74))
    for dx in range(-3, 4):
        put(px, x + dx, y + 1, (36, 44, 46))


def rock(px, x, y):
    disc(px, x, y - 2, 3.4, OUTLINE)
    disc(px, x, y - 2, 2.6, (100, 84, 84))
    put(px, x - 1, y - 4, (140, 120, 116))


def decorate(px, theme, curve, rng):
    def near_path(x, y, d):
        return any((x - cx) ** 2 + (y - cy) ** 2 < d * d for cx, cy in curve[::3])
    water = set(theme["water"])
    placed = 0
    attempts = 0
    while placed < 34 and attempts < 4000:
        attempts += 1
        x, y = rng.randint(6, W - 6), rng.randint(34, H - 6)
        if near_path(x, y, 14) or px[x, y] in water or any(px[min(W - 1, x + dx), y] in water for dx in range(-8, 9, 4)):
            continue
        kind = theme["props"]
        if kind == "trees":
            tree(px, x, y)
        elif kind == "crystals":
            if placed % 3 == 0:
                crystal(px, x, y, rng.choice(theme["sparkles"]))
            else:
                stalagmite(px, x, y)
        elif kind == "graves":
            if placed % 2 == 0:
                dead_tree(px, x, y)
            else:
                grave(px, x, y)
        else:
            rock(px, x, y)
        placed += 1
    for _ in range(150):
        x, y = rng.randint(0, W - 1), rng.randint(30, H - 1)
        if not near_path(x, y, 6) and px[x, y] in theme["ground"] + [theme["ground_dark"]]:
            px[x, y] = rng.choice(theme["sparkles"])


def render(name, theme, out_dir):
    rng = random.Random(7 + len(name))
    img = Image.new("RGB", (W, H))
    px = img.load()
    paint_ground(px, theme, rng)
    paint_water(px, theme)
    curve = draw_path(px, theme)
    decorate(px, theme, curve, rng)
    path = os.path.join(out_dir, name + ".png")
    img.save(path)
    return path


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "assets", "campaign")
    os.makedirs(out, exist_ok=True)
    for name, theme in THEMES.items():
        print(render(name, theme, out))
