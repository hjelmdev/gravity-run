#!/usr/bin/env python3
"""Moves every frame of the pixel runners down so its lowest opaque pixel sits
on the bottom row. The generated run cycles lift both feet on the airborne
frames, which reads as running on top of the ground; grounding the frames
keeps a foot on the track every frame (the body bob stays).

    python3 tools/pixel_characters/ground_frames.py   # all assets/characters/*
"""
import glob
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

for path in sorted(glob.glob(os.path.join(ROOT, "assets", "characters", "*", "*.png"))):
    image = Image.open(path).convert("RGBA")
    box = image.getbbox()
    if box is None:
        continue
    shift = image.height - box[3]
    if shift <= 0:
        continue
    grounded = Image.new("RGBA", image.size, (0, 0, 0, 0))
    grounded.paste(image, (0, shift))
    grounded.save(path)
    print("%s: down %d px" % (os.path.relpath(path, ROOT), shift))
