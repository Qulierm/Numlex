#!/usr/bin/env python3
"""Idempotently ensure PNG file(s) carry an explicit sRGB chunk.

Usage: inject-srgb-chunk.py <png> [<png> ...]
Inserts a standards-compliant sRGB chunk (rendering intent 0/perceptual)
right after IHDR when none is present. Existing sRGB chunks, pHYs (dpi),
gAMA/cHRM and all other chunks are preserved byte-exact (per PNG spec the
sRGB chunk overrides gAMA/cHRM on read). Needed because `sips -s dpiWidth`
rewrites PNGs expressing sRGB via gAMA/cHRM instead of an sRGB chunk.
Deterministic: same input bytes -> same output bytes.
"""
import struct
import sys
import zlib


def inject(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"not a PNG: {path}"
    pos = 8
    chunks = []
    while pos + 8 <= len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunks.append((typ, ln, pos))
        pos += 12 + ln
    if any(t == b"sRGB" for t, _, _ in chunks):
        print(f"keep (has sRGB): {path}")
        return
    assert chunks[0][0] == b"IHDR", f"first chunk is not IHDR: {path}"
    body = b"sRGB" + b"\x00"
    srgb = struct.pack(">I", 1) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    ihdr_end = chunks[0][2] + 12 + chunks[0][1]
    with open(path, "wb") as f:
        f.write(data[:ihdr_end] + srgb + data[ihdr_end:])
    print(f"injected sRGB: {path}")


for p in sys.argv[1:]:
    inject(p)
