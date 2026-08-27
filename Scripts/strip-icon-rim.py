#!/usr/bin/env python3
"""Generate the rimless Numlex app-icon fallback rasters.

Why this exists
---------------
The canonical authored source is Assets/AppIcon.icon (Icon Composer
package). Its icon.json defines a solid display-p3 0.11615 background with
the blue N / green L gradient glyph layers (neutral shadow 0.5, translucency
0.5) and contains NO border or stroke. Icon Composer / ictool raster exports
("macOS" or "iOS Default") nonetheless bake in a platform specular finish:
a bright neutral bevel around the outer perimeter (top-center opaque RGB
~134 fading over ~20 px at 1024 into the dark fill). That rim is export
machinery, not authored artwork.

What this script does
---------------------
For each of the ten hand-tuned flattened exports in
Assets/AppIcon.flattened.iconset (kept as the deterministic strip INPUT so
small sizes stay crisper than downscaling), it removes ONLY the outer
neutral/specular perimeter:

  1. Fill reference: sampled from the raster itself (first neutral pixel on
     the center column with luminance <= 30, i.e. inside the true dark fill,
     past the rim gradient tail) — no color management needed because the
     authored fill is a neutral gray, identical in P3 and sRGB.
  2. Band width: measured per size from the raster (rows at top center that
     are neutral and brighter than the fill by >10), plus a 1 px margin.
     Measured values: 1,1,2,2,5,5,10,10,20 px for 16,32,64,128,256,256,512,
     512,1024 (exactly 20 px per 1024).
  3. Correction: pixels within `band` px of the silhouette perimeter (a
     four-sided frame: each column's top/bottom band and each row's
     left/right band) whose color is neutral (max-min <= 20) and brighter
     than the fill by >4 are set to the fill color. Alpha is never
     modified. The N/L glyphs and their bevels are deep inside the
     silhouette (tens of px at 1024) and are untouched by construction.

Output
------
Assets/AppIcon.iconset/ — the ten rimless native slots (tracked GENERATED
fallback; NOT the canonical source). The output is deterministic: the same
inputs always produce byte-identical PNGs.

PNG canonicalization
--------------------
iconutil passes a slot's PNG bytes through untouched only when the file
matches its canonical chunk layout (IHDR + iCCP + cICP + eXIf + IDAT...).PIL writes a different metadata set, which makes iconutil
re-encode the slot. After the pixel strip, the script therefore splices
the metadata chunks (iCCP/cICP/eXIf, byte-copied from the corresponding
flattened input) into the output, keeping PIL's pixel IDAT data. The
result round-trips byte-identically through iconutil.

Requires: python3 + Pillow. Fails clearly if anything is off.
"""
import os
import struct
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("strip-icon-rim: requires python3 + Pillow (pip install pillow)")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN_DIR = os.path.join(ROOT, "Assets", "AppIcon.flattened.iconset")
OUT_DIR = os.path.join(ROOT, "Assets", "AppIcon.iconset")

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

NEUTRAL_SPREAD = 20   # max(r,g,b) - min(r,g,b) for "neutral"
FILL_BRIGHT_DELTA = 4  # "brighter than fill" threshold
FILL_LUM_MAX = 30      # lum <= this on the center column means true fill


def lum(rgb):
    return (rgb[0] + rgb[1] + rgb[2]) / 3.0


def sample_fill(px, w, h):
    """First neutral pixel with luminance <= FILL_LUM_MAX (the true fill)."""
    x = w // 2
    for y in range(h):
        r, g, b, a = px[x, y]
        if a > 200 and max(r, g, b) - min(r, g, b) <= NEUTRAL_SPREAD and lum((r, g, b)) <= FILL_LUM_MAX:
            return (r, g, b)
    raise SystemExit("strip-icon-rim: could not sample dark fill on center column")


def measure_band(px, w):
    """Neutral-bright rows at top center (the baked specular rim)."""
    x = w // 2
    n = 0
    for y in range(w // 2):
        r, g, b, a = px[x, y]
        if a > 200 and max(r, g, b) - min(r, g, b) <= NEUTRAL_SPREAD and lum((r, g, b)) > 40:
            n += 1
        else:
            break
    return n


def perimeter_frame(w, h, alpha, band):
    """True for pixels within `band` px of the silhouette perimeter.

    Four-sided frame: for every column, the `band` rows below its first
    opaque pixel and above its last opaque pixel; for every row, the same
    horizontally. Handles full-bleed silhouettes whose only transparent
    pixels are the rounded corners.
    """
    col_first = [-1] * w
    col_last = [-1] * w
    row_first = [-1] * h
    row_last = [-1] * h
    for x in range(w):
        for y in range(h):
            if alpha[y * w + x] > 0:
                if col_first[x] < 0:
                    col_first[x] = y
                col_last[x] = y
    for y in range(h):
        for x in range(w):
            if alpha[y * w + x] > 0:
                if row_first[y] < 0:
                    row_first[y] = x
                row_last[y] = x
    frame = [[False] * w for _ in range(h)]
    for x in range(w):
        if col_first[x] < 0:
            continue
        for y in range(col_first[x], min(h, col_first[x] + band + 1)):
            frame[y][x] = True
        for y in range(max(0, col_last[x] - band), col_last[x] + 1):
            frame[y][x] = True
    for y in range(h):
        if row_first[y] < 0:
            continue
        for x in range(row_first[y], min(w, row_first[y] + band + 1)):
            frame[y][x] = True
        for x in range(max(0, row_last[y] - band), row_last[y] + 1):
            frame[y][x] = True
    return frame


def strip_slot(name):
    src = Image.open(os.path.join(IN_DIR, name)).convert("RGBA")
    w, h = src.size
    px = src.load()
    fill = sample_fill(px, w, h)
    fill_l = lum(fill)
    band = measure_band(px, w) + 1
    alpha = [px[x, y][3] for y in range(h) for x in range(w)]
    frame = perimeter_frame(w, h, alpha, band)

    changed = 0
    for y in range(h):
        for x in range(w):
            if not frame[y][x]:
                continue
            r, g, b, a = px[x, y]
            if max(r, g, b) - min(r, g, b) <= NEUTRAL_SPREAD and lum((r, g, b)) > fill_l + FILL_BRIGHT_DELTA:
                px[x, y] = (fill[0], fill[1], fill[2], a)
                changed += 1

    # Post-checks: alpha untouched, rim gone at top center.
    out = src.load()
    for y in range(h):
        for x in range(w):
            if out[x, y][3] != alpha[y * w + x]:
                raise SystemExit(f"strip-icon-rim: {name}: alpha was modified")
    x = w // 2
    seen_glyph = False
    for y in range(w // 2):
        r, g, b, a = out[x, y]
        neutral = max(r, g, b) - min(r, g, b) <= NEUTRAL_SPREAD
        if not neutral and a > 200:
            seen_glyph = True
        if seen_glyph:
            break
        if a > 200 and neutral and lum((r, g, b)) > fill_l + FILL_BRIGHT_DELTA:
            raise SystemExit(f"strip-icon-rim: {name}: neutral bright rim remains at top center (row {y})")

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, name)
    src.save(out_path, format="PNG")
    canonicalize_png(out_path, os.path.join(IN_DIR, name))
    return fill, band, changed


def _read_png(path):
    with open(path, "rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"strip-icon-rim: not a PNG: {path}")
        chunks = []
        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            ln, typ = struct.unpack(">I4s", hdr)
            data = f.read(ln)
            chunks.append((typ, data, f.read(4)))
    return sig, chunks


def canonicalize_png(out_path, ref_path):
    """Give `out_path` the canonical chunk layout iconutil passes through
    untouched: IHDR + iCCP + cICP + eXIf + IDAT + IEND, with the metadata
    chunks byte-copied from `ref_path` (the flattened input). PIL's pixel
    IDAT data is preserved; all other chunks are dropped."""
    _, in_chunks = _read_png(out_path)
    _, ref_chunks = _read_png(ref_path)
    idat = b"".join(data for typ, data, _ in in_chunks if typ == b"IDAT")
    if not idat:
        raise SystemExit(f"strip-icon-rim: {out_path}: no IDAT data")
    ref_meta = {typ: data for typ, data, _ in ref_chunks if typ in (b"iCCP", b"cICP", b"eXIf")}
    for required in (b"iCCP", b"cICP", b"eXIf"):
        if required not in ref_meta:
            raise SystemExit(f"strip-icon-rim: {ref_path}: missing {required.decode()} chunk")
    ihdr = next(data for typ, data, _ in in_chunks if typ == b"IHDR")
    _rebuild_canonical(out_path, ref_meta, idat, ihdr)


def _rebuild_canonical(out_path, ref_meta, idat, ihdr):
    import zlib
    sig = b"\x89PNG\r\n\x1a\n"

    def put(f, typ, data):
        f.write(struct.pack(">I4s", len(data), typ) + data + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    # iconutil's canonical layout splits the IDAT stream into 16 KB chunks.
    parts = [idat[i:i + 16384] for i in range(0, len(idat), 16384)]
    with open(out_path, "wb") as f:
        f.write(sig)
        put(f, b"IHDR", ihdr)
        for t in (b"iCCP", b"cICP", b"eXIf"):
            put(f, t, ref_meta[t])
        for part in parts:
            put(f, b"IDAT", part)
        put(f, b"IEND", b"")


def main():
    for slot in SLOTS:
        if not os.path.isfile(os.path.join(IN_DIR, slot)):
            sys.exit(f"strip-icon-rim: missing input {IN_DIR}/{slot}")
    for slot in SLOTS:
        fill, band, changed = strip_slot(slot)
        print(f"strip-icon-rim: {slot}: fill={fill} band={band}px changed={changed} px")
    print(f"strip-icon-rim: wrote {len(SLOTS)} rimless slots to {OUT_DIR}")


if __name__ == "__main__":
    main()
