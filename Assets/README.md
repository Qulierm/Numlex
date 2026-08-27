# Numlex app icon sources

Pipeline
--------
raw supplied exports → deterministic outer-rim correction → packaged
iconset → ICNS:

1. `AppIcon.exported.iconset/` — the RAW supplied silver monochrome N/L
   exports, tracked byte-exact (the same ten native slots, no resizing
   or filtering). No script ever modifies this set.
2. `Scripts/strip-icon-rim.py` — deterministic outer-rim correction.
   The export machinery bakes a neutral specular bevel around the
   alpha-silhouette perimeter of the rounded tile (up to ~RGB 182 at
   the top edge at 1024, fading into the tile over ~20 px). The
   correction touches exactly one set of pixels: the interior band
   within 20 px at 1024 (scaled linearly per native slot, minimum 1 px)
   of the silhouette. Each band pixel is refilled with the RGB of the
   raw pixel one band-width further inside along the local inward
   direction — i.e. the continuation of the LOCAL interior background
   (the tile background is a dark vertical gradient, ~49 top to ~19
   bottom at 1024), never a global flat gray. Alpha is never modified.
   There is deliberately no color classification: the silver N/L glyph
   is itself neutral gray, so geometry/perimeter locality alone
   guarantees the glyph and all central artwork stay bit-identical —
   the script asserts exactly that (outside-band pixels bit-identical,
   alpha identical everywhere) and is deterministic (two runs yield
   byte-identical PNGs).
3. `AppIcon.iconset/` — the GENERATED corrected (packaged) slots.
   Regenerate with `python3 Scripts/strip-icon-rim.py` (reads
   `AppIcon.exported.iconset`, writes here).
4. `Scripts/generate-app-icon.sh` — packs `AppIcon.iconset` into
   `Sources/NumlexApp/Resources/AppIcon.icns` (iconutil, NO resizing)
   and validates the result by unpacking it and checking all ten
   slots: exact dimensions everywhere; pixel-identical round-trip for
   every slot except the two legacy-representation slots (16, 32 px
   @1x), which iconutil re-encodes with palette quantization — those
   use a documented alpha-weighted pixel tolerance.

Slot mapping (raw export → iconset slot, same in both sets)

| source export                    | iconset slot            |
| -------------------------------- | ----------------------- |
| `16x16@1x`                       | `icon_16x16.png`        |
| `16x16@2x`                       | `icon_16x16@2x.png`     |
| `32x32@1x`                       | `icon_32x32.png`        |
| `32x32@2x`                       | `icon_32x32@2x.png`     |
| `128x128@1x`                     | `icon_128x128.png`      |
| `128x128@2x`                     | `icon_128x128@2x.png`   |
| `256x256@1x`                     | `icon_256x256.png`      |
| `256x256@2x`                     | `icon_256x256@2x.png`   |
| `512x512@1x`                     | `icon_512x512.png`      |
| `1024x1024@1x`                   | `icon_512x512@2x.png`   |

No layered source
-----------------
The supplied export directory contains PNGs only — no Icon Composer
(`.icon`) package or layered asset was supplied, and none is tracked.
The per-size exported PNGs ARE the source of truth; if a layered
package is ever added back, it must rasterize to the raw exported
pixels (the rim correction still applies to its raster exports).

Build
-----
- `Scripts/build-app.sh` copies the ICNS into the bundle and signs it.
  The ICNS is the single authoritative icon resource
  (`CFBundleIconFile=AppIcon`); no `Assets.car` is produced.
