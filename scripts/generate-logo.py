#!/usr/bin/env python3
"""Draws assets/logo.svg from the ASCII logo in lua/lazycode/welcome.lua.

The art is drawn as shapes, so it looks the same with any font.
"""
import os
import re

CELL_W, CELL_H = 10, 20
BLOCK, SHADOW = "#7aa2f7", "#3d59a1"
LEFT, MID, RIGHT = 3.5, 5, 6.5
TOP, CENTER, BOTTOM = 7, 10, 13

# Double-line box characters as polylines inside one cell.
LINES = {
    "═": [[(0, TOP), (CELL_W, TOP)], [(0, BOTTOM), (CELL_W, BOTTOM)]],
    "║": [[(LEFT, 0), (LEFT, CELL_H)], [(RIGHT, 0), (RIGHT, CELL_H)]],
    "╔": [[(CELL_W, TOP), (LEFT, TOP), (LEFT, CELL_H)], [(CELL_W, BOTTOM), (RIGHT, BOTTOM), (RIGHT, CELL_H)]],
    "╗": [[(0, TOP), (RIGHT, TOP), (RIGHT, CELL_H)], [(0, BOTTOM), (LEFT, BOTTOM), (LEFT, CELL_H)]],
    "╚": [[(LEFT, 0), (LEFT, BOTTOM), (CELL_W, BOTTOM)], [(RIGHT, 0), (RIGHT, TOP), (CELL_W, TOP)]],
    "╝": [[(RIGHT, 0), (RIGHT, BOTTOM), (0, BOTTOM)], [(LEFT, 0), (LEFT, TOP), (0, TOP)]],
}


def read_logo(root):
    source = open(os.path.join(root, "lua", "lazycode", "welcome.lua"), encoding="utf8").read()
    block = re.search(r"local LOGO = \{(.*?)\n\}", source, re.S).group(1)
    return re.findall(r'"([^"]+)"', block)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    logo = read_logo(root)
    width = max(len(line) for line in logo) * CELL_W
    height = len(logo) * CELL_H
    rects, paths = [], []
    for row, line in enumerate(logo):
        run = None
        for col, char in enumerate(line + " "):
            if char == "█":
                run = col if run is None else run
                continue
            if run is not None:
                rects.append(f'<rect x="{run * CELL_W}" y="{row * CELL_H}" width="{(col - run) * CELL_W}" height="{CELL_H}"/>')
                run = None
            for points in LINES.get(char, []):
                moved = [f"{x + col * CELL_W:g} {y + row * CELL_H:g}" for x, y in points]
                paths.append("M" + "L".join(moved))
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        'role="img" aria-label="LazyCode">\n'
        f'<path d="{"".join(paths)}" fill="none" stroke="{SHADOW}" stroke-width="2"/>\n'
        f'<g fill="{BLOCK}" shape-rendering="crispEdges">{"".join(rects)}</g>\n'
        "</svg>\n"
    )
    with open(os.path.join(root, "assets", "logo.svg"), "w", encoding="utf8") as out:
        out.write(svg)


if __name__ == "__main__":
    main()
