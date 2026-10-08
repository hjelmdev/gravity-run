#!/usr/bin/env python3
"""Generates the "Nova" astronaut runner as pixel art in two canvas sizes.

    python3 tools/pixel_characters/generate_astronaut.py

Writes assets/characters/nova_32/ (32x32 canvas, shown at x2) and
assets/characters/nova_16/ (16x16 canvas, shown at x4): an 8-frame run cycle,
a still pose and a SpriteFrames resource. The suit accent is magenta so the
existing hue-shift skin shader recolours it like the original runner.
"""
import math
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Outline and boots stay just outside the shader's hue band (0.68-0.97) so
# only the magenta accents change colour with the skin.
OUTLINE = (20, 20, 28, 255)
SUIT = (233, 239, 248, 255)
SUIT_SHADE = (166, 179, 201, 255)
SUIT_DARK = (112, 122, 150, 255)
VISOR = (64, 208, 224, 255)
VISOR_DARK = (24, 106, 138, 255)
GLINT = (255, 255, 255, 255)
ACCENT = (214, 66, 196, 255)        # hue ~0.84: recoloured by skin_palette.gdshader
ACCENT_DARK = (140, 38, 140, 255)
BOOT = (52, 56, 74, 255)
PACK = (128, 136, 168, 255)


class Canvas:
    def __init__(self, size):
        self.size = size
        self.px = {}

    def put(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[(x, y)] = color

    def rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, color)

    def disc(self, cx, cy, r, color, shade=None):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                if dx * dx + dy * dy <= r * r:
                    c = color
                    if shade and dx * 0.6 + dy * 0.8 > r * 0.45:
                        c = shade
                    self.put(x, y, c)

    def limb(self, x0, y0, x1, y1, width, color, end_color=None, end_len=0):
        length = max(abs(x1 - x0), abs(y1 - y0), 1)
        steps = int(length * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            c = end_color if end_color and t >= 1.0 - end_len / max(length, 1) else color
            for oy in range(width):
                for ox in range(width):
                    self.put(x - (width - 1) / 2 + ox, y - (width - 1) / 2 + oy, c)

    def image(self):
        img = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            img.putpixel((x, y), c)
        # 1px outline around the silhouette (4-neighbourhood).
        out = img.copy()
        for y in range(self.size):
            for x in range(self.size):
                if img.getpixel((x, y))[3]:
                    continue
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < self.size and 0 <= ny < self.size and img.getpixel((nx, ny))[3]:
                        out.putpixel((x, y), OUTLINE)
                        break
        return out


def pose(frame, frames=8, running=True):
    """Leg/arm swing angles and body bob for a run-cycle frame."""
    if not running:
        return {"front": 0.35, "back": -0.25, "arm": -0.4, "bob": 0, "knee_f": 0.5, "knee_b": 0.2}
    phase = frame / frames * math.tau
    swing = math.sin(phase)
    return {
        "front": 0.95 * swing,
        "back": -0.95 * swing,
        "arm": -0.9 * swing,
        "bob": -1 if frame % 4 in (1, 2) else 0,
        "knee_f": 0.9 if swing < 0 else 0.25,
        "knee_b": 0.9 if swing > 0 else 0.25,
    }


def leg(c, hip_x, hip_y, angle, knee, seg, width, color, boot):
    kx = hip_x + math.sin(angle) * seg
    ky = hip_y + math.cos(angle) * seg
    fx = kx + math.sin(angle - knee) * seg
    fy = ky + math.cos(angle - knee) * seg
    c.limb(hip_x, hip_y, kx, ky, width, color)
    c.limb(kx, ky, fx, fy, width, color, boot, end_len=max(1, seg * 0.5))
    c.put(fx + 1, fy, boot)


def outlined_limb(c, x0, y0, x1, y1, width, color, end_color=None, end_len=0):
    """Front limbs get their own outline so they read against the body."""
    c.limb(x0, y0, x1, y1, width + 2, OUTLINE)
    c.limb(x0, y0, x1, y1, width, color, end_color, end_len)


def leg_points(hip_x, hip_y, angle, knee, seg):
    kx = hip_x + math.sin(angle) * seg
    ky = hip_y + math.cos(angle) * seg
    fx = kx + math.sin(angle - knee) * seg
    fy = ky + math.cos(angle - knee) * seg
    return kx, ky, fx, fy


def draw_32(frame, running=True):
    c = Canvas(32)
    p = pose(frame, running=running)
    b = p["bob"]
    hip_y = 21 + b
    # Back leg and arm (shaded, behind the body).
    kx, ky, fx, fy = leg_points(14, hip_y, p["back"], p["knee_b"], 3.6)
    c.limb(14, hip_y, kx, ky, 3, SUIT_SHADE)
    c.limb(kx, ky, fx, fy, 3, SUIT_SHADE)
    c.rect(fx - 1, fy, fx + 2, fy + 1, BOOT)
    ax, ay = 15 + math.sin(-p["arm"]) * 4, 16 + b + math.cos(-p["arm"]) * 4
    c.limb(15, 16 + b, ax, ay, 2, SUIT_DARK)
    c.rect(ax - 0.5, ay - 0.5, ax + 0.5, ay + 0.5, BOOT)
    # Backpack.
    c.rect(9, 13 + b, 11, 20 + b, PACK)
    c.rect(9, 13 + b, 9, 20 + b, SUIT_DARK)
    c.put(10, 14 + b, ACCENT)
    # Torso with belt.
    c.rect(12, 14 + b, 19, 21 + b, SUIT)
    c.rect(18, 14 + b, 19, 21 + b, SUIT_SHADE)
    c.rect(12, 19 + b, 19, 19 + b, SUIT_DARK)
    c.put(16, 19 + b, ACCENT)
    # Helmet, collar ring and visor.
    c.disc(16.5, 8.5 + b, 6.0, SUIT, SUIT_SHADE)
    c.rect(12, 13 + b, 20, 13 + b, ACCENT)
    c.rect(18, 13 + b, 20, 13 + b, ACCENT_DARK)
    c.rect(17, 6 + b, 22, 10 + b, VISOR)
    c.rect(17, 10 + b, 22, 10 + b, VISOR_DARK)
    c.rect(22, 7 + b, 22, 10 + b, VISOR_DARK)
    c.put(18, 7 + b, GLINT)
    c.put(19, 7 + b, GLINT)
    c.put(13, 5 + b, GLINT)
    c.put(12, 6 + b, GLINT)
    # Antenna.
    c.put(13, 2 + b, SUIT_DARK)
    c.put(12, 1 + b, ACCENT)
    # Front leg and arm, outlined so the silhouette stays readable.
    kx, ky, fx, fy = leg_points(17, hip_y, p["front"], p["knee_f"], 3.6)
    c.limb(17, hip_y, kx, ky, 5, OUTLINE)
    c.limb(kx, ky, fx, fy, 5, OUTLINE)
    c.limb(17, hip_y, kx, ky, 3, SUIT)
    c.limb(kx, ky, fx, fy, 3, SUIT)
    c.rect(fx - 1, fy, fx + 2, fy + 1, BOOT)
    # Front arm as a coloured sleeve: it reads against the white torso without
    # a heavy outline, and recolours with the skin.
    ax, ay = 17 + math.sin(p["arm"]) * 4, 16 + b + math.cos(p["arm"]) * 4
    c.limb(17, 15 + b, ax, ay, 2, ACCENT)
    c.put(17, 15 + b, ACCENT_DARK)
    c.rect(ax - 0.5, ay - 0.5, ax + 0.5, ay + 0.5, BOOT)
    return c.image()


# 16x16 frames are hand-placed: at this size procedural limbs turn to mush.
#   . empty  W suit  S shade  D dark suit  V visor  v visor dark  G glint
#   A accent  P pack  B boot
_HEAD_16 = [
    "....A...........",
    ".....WWWW.......",
    "....WWWWWW......",
    "...WGWWVVVV.....",
    "...WWWWVGVv.....",
    "...WWWWVVVv.....",
    "....SWWWSS......",
    "...PAAAAAA......",
]
_BODY_16 = {
    "still": [
        "..PPWWWWS.......",
        "..PPWWWWS.......",
        "....DDDDD.......",
        "....WS.WS.......",
        "....WS.WS.......",
        "....BB.BBB......",
    ],
    0: [
        "..PPWWWWSW......",
        "..PPWWWWS.B.....",
        "....DDDDD.......",
        "...SW..WW.......",
        "..SS....WS......",
        ".BB......BBB....",
    ],
    1: [
        "..PPWWWWS.......",
        "..PPWWWWWB......",
        "....DDDDD.......",
        "....SWWW........",
        "....S.WS........",
        "...BB.BBB.......",
    ],
    2: [
        "..PPWWWWS.......",
        ".BSWWWWWS.......",
        "....DDDDD.......",
        "....WWWS........",
        "...WS..S........",
        "..BBB..BB.......",
    ],
    3: [
        "..PPWWWWS.......",
        "..PSWWWWS.......",
        "....DDDDD.......",
        "....SWWS........",
        "....SWS.........",
        "....BBBB........",
    ],
}
_PALETTE_16 = {"W": SUIT, "S": SUIT_SHADE, "D": SUIT_DARK, "V": VISOR, "v": VISOR_DARK,
               "G": GLINT, "A": ACCENT, "P": PACK, "B": BOOT}


def draw_16(frame, running=True):
    body = _BODY_16["still"] if not running else _BODY_16[frame % 4]
    bob = 1 if running and frame % 4 in (1, 3) else 0
    c = Canvas(16)
    rows = _HEAD_16 + body
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in _PALETTE_16:
                c.put(x + 1, y + 1 - bob + (0 if running else 0), _PALETTE_16[ch])
    return c.image()


SPRITE_FRAMES = """[gd_resource type="SpriteFrames" load_steps={steps} format=3]

{ext}
[resource]
animations = [{{
"frames": [{{
"duration": 1.0,
"texture": ExtResource("still")
}}],
"loop": true,
"name": &"default",
"speed": 5.0
}}, {{
"frames": [{run}],
"loop": true,
"name": &"run",
"speed": 14.0
}}]
"""


def write_set(name, drawer):
    folder = os.path.join(ROOT, "assets", "characters", name)
    os.makedirs(folder, exist_ok=True)
    ext = []
    run = []
    for i in range(8):
        drawer(i).save(os.path.join(folder, "run_%02d.png" % i))
        ext.append('[ext_resource type="Texture2D" path="res://assets/characters/%s/run_%02d.png" id="run%d"]' % (name, i, i))
        run.append('{\n"duration": 1.0,\n"texture": ExtResource("run%d")\n}' % i)
    drawer(0, running=False).save(os.path.join(folder, "still.png"))
    ext.append('[ext_resource type="Texture2D" path="res://assets/characters/%s/still.png" id="still"]' % name)
    with open(os.path.join(folder, "frames.tres"), "w") as handle:
        handle.write(SPRITE_FRAMES.format(steps=len(ext) + 1, ext="\n".join(ext) + "\n", run=", ".join(run)))
    return folder


if __name__ == "__main__":
    print(write_set("nova_32", draw_32))
    print(write_set("nova_16", draw_16))
