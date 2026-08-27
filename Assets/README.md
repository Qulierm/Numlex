# Numlex app icon sources

Canonical icon
--------------
`AppIcon.iconset/` is the CANONICAL silver monochrome N/L icon: all ten
native slots, imported EXACT PER SIZE (no resizing, no filtering, no rim
stripping) from the supplied iOS Default exports
(`numlex-iOS-Default-16x16@1x.png` ... `numlex-iOS-Default-1024x1024@1x.png`).

Slot mapping:

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
The per-size PNGs ARE the source of truth; if a layered package is ever
added back, it must rasterize to these exact pixels.

Build
-----
- `Scripts/generate-app-icon.sh` packs `AppIcon.iconset` into
  `Sources/NumlexApp/Resources/AppIcon.icns` (iconutil, NO resizing) and
  validates the result by unpacking it and checking all ten slots:
  exact dimensions everywhere; pixel-identical round-trip for every
  slot except the two legacy-representation slots (16, 32 px @1x), which
  iconutil re-encodes with palette quantization — those use a documented
  alpha-weighted pixel tolerance.
- `Scripts/build-app.sh` copies that ICNS into the bundle and signs it.
  The ICNS is the single authoritative icon resource
  (`CFBundleIconFile=AppIcon`); no `Assets.car` is produced.
