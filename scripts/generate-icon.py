#!/usr/bin/env python3
"""Draws packaging/macos/LazyCode.icns from the shapes in assets/lazycode.svg.

The window draws the same shapes for its own icon (app/src/icon.rs). Needs Pillow.
"""
import math
import os

from PIL import Image

BACKGROUND = (26, 27, 38)
RADIUS = 52.0
# Points, half the stroke width and color, in the SVG's 256-unit space.
STROKES = [
    ([(84, 62), (84, 194), (176, 194)], 14.0, (122, 162, 247)),
    ([(136, 72), (184, 72), (136, 128), (184, 128)], 8.0, (187, 154, 247)),
]
SIZE = 1024
# macOS icons leave a margin: the artwork is 824 of the 1024 pixels.
ARTWORK = 824


def segment(p, a, b):
    ab, ap = (b[0] - a[0], b[1] - a[1]), (p[0] - a[0], p[1] - a[1])
    t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / (ab[0] ** 2 + ab[1] ** 2)))
    return math.hypot(ap[0] - ab[0] * t, ap[1] - ab[1] * t)


def draw(size):
    unit = 256.0 / size
    cover = lambda d: max(0.0, min(1.0, 0.5 - d / unit))
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            p = ((x + 0.5) * unit, (y + 0.5) * unit)
            q = (abs(p[0] - 128) - 128 + RADIUS, abs(p[1] - 128) - 128 + RADIUS)
            square = math.hypot(max(q[0], 0), max(q[1], 0)) + min(max(q[0], q[1]), 0) - RADIUS
            color = BACKGROUND
            for points, half, stroke in STROKES:
                d = min(segment(p, a, b) for a, b in zip(points, points[1:]))
                k = cover(d - half)
                color = tuple(c + (s - c) * k for c, s in zip(color, stroke))
            pixels[x, y] = (*(round(c) for c in color), round(cover(square) * 255))
    return image


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, "packaging", "macos", "LazyCode.icns")
    icon = Image.new("RGBA", (SIZE, SIZE))
    icon.paste(draw(ARTWORK), ((SIZE - ARTWORK) // 2,) * 2)
    icon.save(target, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print(f"wrote {target}")


if __name__ == "__main__":
    main()
