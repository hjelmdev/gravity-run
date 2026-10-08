#!/usr/bin/env python3
"""Generates the animal/creature runners (32x32, shown at x2).

    python3 tools/pixel_characters/generate_critters.py [preview.png]

Every critter shares one chibi rig (big head, small body, short legs) so the
run cycles feel like one cast, plus species parts (ears, tail, beak...). Each
wears a magenta scarf: the skin shader recolours that band (hue 0.68-0.97),
so all four skins work for every character. Writes
assets/characters/<id>/run_00..07.png, still.png and frames.tres.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from generate_astronaut import Canvas, write_set, OUTLINE, GLINT, ACCENT, ACCENT_DARK  # noqa: E402

EYE = (20, 20, 28, 255)


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color[:3]) + (255,)


def run_pose(frame, running):
    if not running:
        return 0.3, -0.2, 0.0, 0
    phase = frame / 8 * math.tau
    swing = math.sin(phase)
    return 0.85 * swing, -0.85 * swing, swing, (-1 if frame % 4 in (1, 2) else 0)


def leg(c, hx, hy, angle, length, width, color, foot, foot_len=2, outline=False):
    fx = hx + math.sin(angle) * length
    fy = hy + math.cos(angle) * length
    if outline:
        c.limb(hx, hy, fx, fy, width + 2, OUTLINE)
        c.rect(fx - 2, fy - 1, fx + foot_len + 1, fy + 2, OUTLINE)
    c.limb(hx, hy, fx, fy, width, color)
    c.rect(fx - 1, fy, fx + foot_len, fy + 1, foot)


def ellipse(c, cx, cy, rx, ry, color, shade_color=None):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                col = color
                if shade_color and dx * 0.55 + dy * 0.8 > 0.55:
                    col = shade_color
                c.put(x, y, col)


def triangle(c, a, b, d, color):
    xs = [p[0] for p in (a, b, d)]
    ys = [p[1] for p in (a, b, d)]
    def side(p, q, r):
        return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
    for y in range(int(min(ys)), int(max(ys)) + 1):
        for x in range(int(min(xs)), int(max(xs)) + 1):
            p = (x + 0.5, y + 0.5)
            d1, d2, d3 = side(p, a, b), side(p, b, d), side(p, d, a)
            if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
                c.put(x, y, color)


def scarf(c, b, flap):
    c.rect(12, 15 + b, 20, 16 + b, ACCENT)
    c.rect(18, 15 + b, 20, 16 + b, ACCENT_DARK)
    # Trailing end flutters behind the runner.
    tail_y = 15 + b + (1 if flap > 0 else 0)
    c.rect(8, tail_y, 11, tail_y + 1, ACCENT)
    c.put(7, tail_y + (1 if flap > 0 else 0), ACCENT_DARK)


def eye(c, x, y, big=False):
    if big:
        c.rect(x, y, x + 2, y + 2, EYE)
        c.put(x + 1, y, GLINT)
    else:
        c.rect(x, y, x + 1, y + 1, EYE)
        c.put(x + 1, y, GLINT)


def draw_critter(spec, frame, running=True):
    c = Canvas(32)
    front, back, swing, b = run_pose(frame, running)
    body, body_shade = spec["body"], shade(spec["body"], 0.78)
    head, head_shade = spec.get("head", spec["body"]), shade(spec.get("head", spec["body"]), 0.8)
    limbs = spec.get("limbs", body_shade)
    feet = spec.get("feet", shade(limbs, 0.7))
    hip_y = 23 + b

    if "tail" in spec:
        spec["tail"](c, b, swing)
    # Back leg and arm.
    leg(c, 14, hip_y, back, spec.get("leg_len", 5), 3, shade(limbs, 0.82), shade(feet, 0.85))
    arm_x = 14 + math.sin(-swing * 0.9) * 3
    c.limb(15, 17 + b, arm_x, 20 + b, 2, shade(limbs, 0.8))
    # Body with belly.
    ellipse(c, 16, 20 + b, 5.2, 4.8, body, body_shade)
    if "belly" in spec:
        ellipse(c, 17.6, 20.5 + b, 2.8, 3.4, spec["belly"])
    if "behind_head" in spec:
        spec["behind_head"](c, b)
    # Head.
    if spec.get("square_head"):
        c.rect(11, 4 + b, 22, 14 + b, head)
        c.rect(19, 4 + b, 22, 14 + b, head_shade)
        c.rect(11, 13 + b, 22, 14 + b, head_shade)
    else:
        ellipse(c, 16.5, 9.5 + b, spec.get("head_rx", 6.6), spec.get("head_ry", 6.0), head, head_shade)
    if "face" in spec:
        spec["face"](c, b)
    scarf(c, b, swing)
    # Front leg and arm, outlined.
    leg(c, 17, hip_y, front, spec.get("leg_len", 5), 3, limbs, feet, outline=True)
    # Front arm: a short stub swinging with the stride; only the paw gets an
    # outline so it does not paint dark lines across the belly.
    # When it swings back it is hidden behind the body.
    if swing > -0.25:
        ax = 19 + math.sin(swing * 0.9) * 3.5
        ay = 19.5 + b - abs(math.sin(swing * 0.9)) * 1.0
        c.limb(18, 17 + b, ax, ay, 2, limbs)
        c.put(ax + 1, ay, OUTLINE)
        c.put(ax, ay + 1, OUTLINE)
    return c.image()


# ---------------------------------------------------------------- species ---

FOX = (232, 116, 40, 255)
CREAM = (250, 236, 214, 255)
DARK_BROWN = (70, 44, 36, 255)


def fox_tail(c, b, swing):
    wag = int(round(swing))
    ellipse(c, 7.5, 19 + b + wag, 4.0, 2.6, FOX, shade(FOX, 0.8))
    ellipse(c, 4.5, 18.5 + b + wag, 1.8, 1.6, CREAM)


def fox_ears(c, b):
    triangle(c, (11, 7 + b), (14.5, 5.5 + b), (11.5, 0 + b), FOX)
    triangle(c, (16, 5 + b), (19.5, 5.5 + b), (17, 0 + b), shade(FOX, 0.85))
    triangle(c, (12.2, 5.6 + b), (13.8, 5 + b), (12.4, 2.4 + b), DARK_BROWN)


def fox_face(c, b):
    ellipse(c, 20.5, 12 + b, 3.2, 2.2, CREAM)
    c.rect(23, 11 + b, 23, 11 + b, EYE)
    eye(c, 19, 8 + b)


FROG = (98, 186, 72, 255)
FROG_BELLY = (214, 236, 150, 255)


def frog_eyes(c, b):
    for ex in (13.5, 19.5):
        ellipse(c, ex, 4.5 + b, 2.6, 2.4, FROG, shade(FROG, 0.82))
    c.rect(19, 3 + b, 21, 5 + b, (250, 250, 240, 255))
    c.rect(20, 4 + b, 21, 5 + b, EYE)
    c.rect(13, 3 + b, 14, 5 + b, (250, 250, 240, 255))
    c.put(14, 4 + b, EYE)


def frog_face(c, b):
    c.rect(18, 12 + b, 22, 12 + b, shade(FROG, 0.55))
    c.put(17, 11 + b, shade(FROG, 0.55))
    ellipse(c, 21, 10.5 + b, 1.2, 0.9, (238, 140, 150, 255))


PENGUIN = (44, 52, 74, 255)
PENGUIN_WHITE = (244, 246, 250, 255)
BEAK = (250, 170, 40, 255)


def penguin_face(c, b):
    ellipse(c, 19, 10.5 + b, 3.6, 3.8, PENGUIN_WHITE)
    eye(c, 19, 8 + b)
    triangle(c, (22, 9.5 + b), (22, 12 + b), (25.5, 11 + b), BEAK)


PANDA = (246, 246, 244, 255)
PANDA_BLACK = (40, 40, 48, 255)


def panda_ears(c, b):
    ellipse(c, 12, 4 + b, 2.3, 2.3, PANDA_BLACK)
    ellipse(c, 19.5, 3.6 + b, 2.3, 2.3, PANDA_BLACK)


def panda_face(c, b):
    ellipse(c, 19.5, 9.5 + b, 2.2, 1.9, PANDA_BLACK)
    c.put(20, 9 + b, GLINT)
    c.rect(22, 11 + b, 23, 12 + b, PANDA_BLACK)
    c.put(21, 13 + b, shade(PANDA, 0.6))


AXOLOTL = (246, 150, 196, 255)
AXOLOTL_GILL = (210, 70, 130, 255)


def axolotl_gills(c, b):
    for i, (dx, dy) in enumerate(((-1, -3), (-2, 0), (-1, 3))):
        c.limb(11, 9 + b, 11 + dx * 3, 9 + b + dy, 2, AXOLOTL_GILL)
        c.put(11 + dx * 3, 9 + b + dy, shade(AXOLOTL_GILL, 0.8))


def axolotl_tail(c, b, swing):
    wag = int(round(swing))
    triangle(c, (12, 18 + b), (12, 23 + b), (3, 19 + b + wag), AXOLOTL)
    triangle(c, (12, 18 + b), (12, 19 + b), (4, 18 + b + wag), (250, 200, 225, 255))


def axolotl_face(c, b):
    eye(c, 19, 8 + b)
    c.rect(19, 12 + b, 22, 12 + b, shade(AXOLOTL, 0.6))
    c.put(14, 11 + b, (255, 196, 214, 255))
    c.put(15, 11 + b, (255, 196, 214, 255))


ROBOT = (150, 178, 196, 255)
ROBOT_DARK = (86, 104, 122, 255)
LED = (255, 210, 70, 255)


def robot_antenna(c, b):
    c.rect(15, 1 + b, 15, 3 + b, ROBOT_DARK)
    c.rect(14, 0 + b, 16, 0 + b, LED)


def robot_face(c, b):
    c.rect(16, 7 + b, 22, 11 + b, (30, 40, 52, 255))
    c.rect(17, 8 + b, 18, 9 + b, LED)
    c.rect(20, 8 + b, 21, 9 + b, LED)
    c.rect(12, 6 + b, 13, 7 + b, ROBOT_DARK)


CAT = (150, 150, 162, 255)
CAT_STRIPE = (100, 100, 114, 255)


def cat_ears(c, b):
    triangle(c, (11, 7 + b), (14, 5.5 + b), (11, 1.5 + b), CAT)
    triangle(c, (16.5, 5 + b), (20, 5.5 + b), (18.5, 0.5 + b), shade(CAT, 0.85))
    triangle(c, (12, 5.5 + b), (13.4, 5 + b), (12, 3 + b), (240, 170, 180, 255))


def cat_tail(c, b, swing):
    tip = 4 + int(round(swing * 2))
    c.limb(11, 21 + b, 6, 18 + b, 2, CAT)
    c.limb(6, 18 + b, 5, tip + 9 + b, 2, CAT)
    c.put(5, tip + 9 + b, CAT_STRIPE)


def cat_face(c, b):
    eye(c, 19, 8 + b)
    c.put(22, 11 + b, (240, 150, 170, 255))
    c.rect(13, 5 + b, 13, 6 + b, CAT_STRIPE)
    c.rect(15, 4 + b, 15, 5 + b, CAT_STRIPE)
    c.rect(21, 12 + b, 24, 12 + b, (210, 210, 220, 255))


CRITTERS = {
    "fox": {"body": FOX, "belly": CREAM, "limbs": shade(FOX, 0.85), "feet": DARK_BROWN,
            "tail": fox_tail, "behind_head": fox_ears, "face": fox_face},
    "frog": {"body": FROG, "belly": FROG_BELLY, "feet": shade(FROG, 0.6), "leg_len": 5.5,
             "behind_head": frog_eyes, "face": frog_face, "head_rx": 7.2, "head_ry": 5.4},
    "penguin": {"body": PENGUIN, "belly": PENGUIN_WHITE, "limbs": PENGUIN, "feet": BEAK, "leg_len": 3.5,
                "face": penguin_face},
    "panda": {"body": PANDA_BLACK, "head": PANDA, "belly": (90, 90, 100, 255), "limbs": PANDA_BLACK,
              "feet": (24, 24, 30, 255), "behind_head": panda_ears, "face": panda_face},
    "axolotl": {"body": AXOLOTL, "belly": (252, 200, 222, 255), "feet": shade(AXOLOTL, 0.7),
                "tail": axolotl_tail, "behind_head": axolotl_gills, "face": axolotl_face, "head_rx": 7.0},
    "robot": {"body": ROBOT, "belly": ROBOT_DARK, "limbs": ROBOT_DARK, "feet": (52, 60, 74, 255),
              "square_head": True, "behind_head": robot_antenna, "face": robot_face},
    "cat": {"body": CAT, "belly": (220, 220, 228, 255), "feet": (230, 230, 236, 255),
            "tail": cat_tail, "behind_head": cat_ears, "face": cat_face},
}


def main():
    for critter_id, spec in CRITTERS.items():
        write_set(critter_id, lambda frame, running=True, spec=spec: draw_critter(spec, frame, running))
    if len(sys.argv) > 1:
        from PIL import Image
        cell = 200
        sheet = Image.new("RGBA", (cell * 9, cell * len(CRITTERS)), (30, 40, 62, 255))
        for row, (critter_id, spec) in enumerate(CRITTERS.items()):
            frames = [draw_critter(spec, i) for i in range(8)] + [draw_critter(spec, 0, running=False)]
            for col, image in enumerate(frames):
                big = image.resize((192, 192), Image.NEAREST)
                sheet.paste(big, (col * cell + 4, row * cell + 4), big)
        sheet.save(sys.argv[1])


if __name__ == "__main__":
    main()
