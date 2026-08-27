#!/usr/bin/env python3
"""Deterministic outer-rim correction for the SILVER Numlex icon exports.

The supplied iOS Default PNG exports (Assets/AppIcon.exported.iconset,
byte-exact copies of the user-supplied rasters) carry a platform
specular rim baked into the export: a NEUTRAL light-gray bevel around
the alpha-silhouette perimeter of the rounded tile (up to ~RGB 182 at
the top edge at 1024, fading into the local interior background over
~20 px). The rim reads as a stray gray outline around the icon; the
intended artwork (silver N/L glyph on a dark gradient tile) does not
contain it.

This script produces Assets/AppIcon.iconset (the PACKAGED corrected
slots) from the raw exports. Rules, in order of priority:

1. GEOMETRY-LOCAL ONLY. The correction touches exactly one set of
   pixels: the interior band within `band` px (Manhattan distance to
   the alpha silhouette, 4-connected BFS; out-of-canvas counts as
   outside) of the tile perimeter. Nothing else is ever written.
   There is deliberately NO color classification (the silver N/L
   glyph is itself neutral-gray): locality alone guarantees the
   glyph and all central artwork stay bit-identical, which is
   asserted.
2. ALPHA IS NEVER MODIFIED. Only the RGB of band pixels changes.
3. FILL FROM THE LOCAL INTERIOR, not a global flat gray. Each band
   pixel p takes the RGB of the raw pixel B px further inside along
   the local inward direction (max-distance 4-neighbor walk), i.e.
   the continuation of the local background gradient (the tile
   background itself is a dark vertical gradient, ~49 top to ~19
   bottom at 1024). No halo, no seam: every filled pixel is a real
   interior sample.
4. DETERMINISTIC. Integer BFS, fixed tie-break direction order, no
   randomness; running twice yields byte-identical PNGs (verified by
   the caller's hash check).

Band width: ~20 px at 1024, scaled linearly per native slot
(B = max(1, round(20 * S / 1024))), so small slots keep a 1 px
perimeter correction and stay crisp.

Usage:
  Scripts/strip-icon-rim.py [raw-iconset-dir] [out-iconset-dir]
    raw defaults to <repo>/Assets/AppIcon.exported.iconset
    out defaults to <repo>/Assets/AppIcon.iconset

Requires python3 + Pillow (same host dependency as
Scripts/generate-app-icon.sh).
"""

import os
import sys
from collections import deque

try:
    from PIL import Image
except ImportError:
    sys.exit("strip-icon-rim: Pillow is required (pip install pillow)")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    ROOT, "Assets", "AppIcon.exported.iconset")
OUT_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    ROOT, "Assets", "AppIcon.iconset")

# The ten native slots (iconutil-standard filenames).
SLOTS = [
    "icon_16x16.png",
    "icon_16x16@2x.png",
    "icon_32x32.png",
    "icon_32x32@2x.png",
    "icon_128x128.png",
    "icon_128x128@2x.png",
    "icon_256x256.png",
    "icon_256x256@2x.png",
    "icon_512x512.png",
    "icon_512x512@2x.png",
]

# Rim fade depth reference: 20 px at 1024.
RIM_REF_PX = 20
RIM_REF_SIZE = 1024

# Fixed tie-break order for the max-dist 4-neighbor walk (determinism).
DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))  # up, right, down, left


def band_for(size: int) -> int:
    return max(1, round(RIM_REF_PX * size / RIM_REF_SIZE))


def silhouette(alpha_rows):
    """1 where the tile is opaque (alpha >= 128)."""
    w = len(alpha_rows[0])
    h = len(alpha_rows)
    inside = [bytearray(w) for _ in range(h)]
    for y in range(h):
        arow = alpha_rows[y]
        irow = inside[y]
        for x in range(w):
            irow[x] = 1 if arow[x] >= 128 else 0
    return inside


def boundary_dist(inside):
    """Manhattan distance to the alpha silhouette for every interior
    pixel (4-connected BFS; out-of-canvas neighbors count as outside,
    so canvas-edge tile pixels are boundary pixels too)."""
    w = len(inside[0])
    h = len(inside)
    dist = [[-1] * w for _ in range(h)]

    def outside(nx, ny):
        return nx < 0 or nx >= w or ny < 0 or ny >= h or not inside[ny][nx]

    q = deque()
    for y in range(h):
        irow = inside[y]
        drow = dist[y]
        for x in range(w):
            if irow[x] and any(
                    outside(x + dx, y + dy)
                    for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                    if dx or dy):
                drow[x] = 0
                q.append((x, y))
    while q:
        x, y = q.popleft()
        d = dist[y][x] + 1
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and inside[ny][nx] \
                    and dist[ny][nx] == -1:
                dist[ny][nx] = d
                q.append((nx, ny))
    return dist


def correct(raw):
    """Return (corrected, band_pixel_count) for one slot's RGBA pixel
    matrix (rows of (r, g, b, a) tuples)."""
    w = len(raw[0])
    h = len(raw)
    alpha_rows = [[px[3] for px in row] for row in raw]
    inside = silhouette(alpha_rows)
    dist = boundary_dist(inside)
    band = band_for(w)

    # Pre-resolve each band pixel's interior sample ONCE (the sample
    # depends only on the raw geometry, never on previously filled
    # pixels — the fill always copies from the RAW export).
    out = [row[:] for row in raw]
    count = 0
    for y in range(h):
        irow = inside[y]
        orow = out[y]
        for x in range(w):
            if not irow[x]:
                continue
            d = dist[y][x]
            if d < 0 or d >= band:
                continue
            # Walk (band - d) steps toward the interior: each step to
            # the MAX-distance 4-neighbor (first maximum in the fixed
            # DIRS order). A strict greater distance always wins, so a
            # true inward neighbor beats a sideways one; the equal
            # fallback lets a boundary-ramp pixel (surrounded by other
            # dist-0 antialiased pixels) slide sideways to where an
            # inward neighbor exists. A step cap bounds degenerate
            # cases, which leave the pixel raw.
            sx, sy = x, y
            stalled = False
            steps = 0
            cap = 4 * band
            for _ in range(band - d):
                best = None
                bd = -1
                for dx, dy in DIRS:
                    nx, ny = sx + dx, sy + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        nd = dist[ny][nx]
                        if nd > bd:
                            bd = nd
                            best = (nx, ny)
                if best is None or bd < dist[sy][sx]:
                    # No neighbor at all, or every neighbor is strictly
                    # closer to the boundary (a local distance maximum
                    # — cannot happen at d < band on this convex tile).
                    stalled = True
                    break
                sx, sy = best
                steps += 1
                if steps > cap:
                    stalled = True
                    break
            if stalled:
                continue
            sr, sg, sb, _ = raw[sy][sx]
            # RGB from the local interior sample; the pixel's OWN raw
            # alpha is preserved exactly (alpha is never modified).
            orow[x] = (sr, sg, sb, raw[y][x][3])
            count += 1
    return out, count


def main():
    if not os.path.isdir(RAW_DIR):
        sys.exit(f"strip-icon-rim: raw iconset not found: {RAW_DIR}")
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in SLOTS:
        src = os.path.join(RAW_DIR, name)
        if not os.path.isfile(src):
            sys.exit(f"strip-icon-rim: missing raw slot: {src}")
        im = Image.open(src).convert("RGBA")
        w, h = im.size
        if w != h:
            sys.exit(f"strip-icon-rim: {name} is not square: {im.size}")
        # Row-major RGBA as immutable 4-tuples (fast, exact).
        buf = im.tobytes()
        flat = [tuple(buf[i:i + 4]) for i in range(0, w * h * 4, 4)]
        raw = [flat[y * w:(y + 1) * w] for y in range(h)]

        out, n = correct(raw)

        # --- Assertions (fail loudly, never write partial output).
        # 1) alpha is bit-identical everywhere.
        for y in range(h):
            for x in range(w):
                if out[y][x][3] != raw[y][x][3]:
                    sys.exit(f"strip-icon-rim: {name}: alpha changed at "
                             f"({x},{y})")
        # 2) everything outside the band is bit-identical (RGBA).
        alpha_rows = [[px[3] for px in row] for row in raw]
        inside = silhouette(alpha_rows)
        dist = boundary_dist(inside)
        band = band_for(w)
        for y in range(h):
            for x in range(w):
                if (not inside[y][x]) or dist[y][x] >= band:
                    if out[y][x] != raw[y][x]:
                        sys.exit(f"strip-icon-rim: {name}: pixel outside "
                                 f"the band changed at ({x},{y})")
        # 3) the band actually did something at the perimeter (the raw
        #    exports all carry the rim).
        if n == 0:
            sys.exit(f"strip-icon-rim: {name}: no band pixels corrected")

        im2 = Image.new("RGBA", (w, h))
        im2.putdata([p for row in out for p in row])
        im2.save(os.path.join(OUT_DIR, name))
        print(f"strip-icon-rim: {name} ({w}x{h}, band {band} px, "
              f"{n} perimeter pixels refilled from the local interior)")
    print("strip-icon-rim: done — packaged corrected iconset written to "
          f"{OUT_DIR}")


if __name__ == "__main__":
    main()
