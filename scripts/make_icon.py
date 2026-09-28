#!/usr/bin/env python3
"""Draw the Psst app icon: a map pin whose head holds a whisper (three dots).

Writes the light, dark, and tinted 1024 px variants into the asset catalog.
Requires Pillow: python3 -m pip install pillow
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "PsstMap" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SS = 4  # supersampling factor
SIZE = 1024 * SS

INK = (16, 24, 43)
PAPER = (246, 243, 236)
SIGNAL = (211, 34, 27)


def pin_polygon(cx, cy, r, tip_y, steps=720):
    """Teardrop: a circle joined to a point below it by two tangent lines."""
    d = tip_y - cy
    theta = math.acos(r / d)  # angle between the downward axis and each tangent point
    points = []
    # Walk the circle from the right tangent point, over the top, to the left tangent point.
    start = math.pi / 2 - theta
    end = -(3 * math.pi / 2 - theta)
    for i in range(steps + 1):
        a = start + (end - start) * i / steps
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    points.append((cx, tip_y))
    return points


def draw(background, pin, dots, accent):
    image = Image.new("RGBA", (SIZE, SIZE), background)
    draw = ImageDraw.Draw(image)
    s = SS
    cx, cy, r, tip = 512 * s, 452 * s, 262 * s, 880 * s
    draw.polygon(pin_polygon(cx, cy, r, tip), fill=pin)
    dot_r = 40 * s
    gap = 118 * s
    for i, x in enumerate((cx - gap, cx, cx + gap)):
        color = accent if i == 2 else dots
        draw.ellipse((x - dot_r, cy - dot_r, x + dot_r, cy + dot_r), fill=color)
    return image.resize((1024, 1024), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    draw(INK + (255,), PAPER, INK, SIGNAL).convert("RGB").save(OUT / "icon-light.png")
    draw((0, 0, 0, 0), PAPER, INK, SIGNAL).save(OUT / "icon-dark.png")
    tinted = draw((0, 0, 0, 0), (255, 255, 255), (0, 0, 0), (0, 0, 0)).convert("LA")
    tinted.save(OUT / "icon-tinted.png")
    print(f"Wrote icons to {OUT}")


if __name__ == "__main__":
    main()
