# Numlex app icon sources

Pipeline
--------
raw supplied exports → iconutil ICNS (no rim correction, no resizing):

1. `AppIcon.exported.iconset/` — the RAW supplied silver monochrome N/L
   exports, tracked byte-exact (the same ten native slots, no resizing
   or filtering). No script ever modifies this set. These match the
   original supplied files in `/Downloads/Numlex` byte-exact
   (e.g. `icon_512x512@2x.png` SHA256 `3653ba85bb4b…` equals
   `numlex-iOS-Default-1024x1024@1x.png`).
2. `AppIcon.iconset/` — the PACKAGED slots, kept BYTE-EXACT copies of
   the raw exports (`cmp` clean on all ten slots). The user explicitly
   chose the original raw exports; no RGB correction of any kind is
   applied (the former `Scripts/strip-icon-rim.py` outer-rim correction
   has been removed from the pipeline because, while alpha-identical,
   it altered edge RGB on ~69k pixels at 1024 and produced visible
   banding/white lateral artifacts in Finder).
3. `Scripts/generate-app-icon.sh` — packs `AppIcon.iconset` into
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
The per-size exported PNGs ARE the source of truth; they ship as-is.

Build
-----
- `Scripts/build-app.sh` copies the ICNS into the bundle and signs it.
  The ICNS is the single authoritative icon resource
  (`CFBundleIconFile=AppIcon`); no `Assets.car` is produced.
