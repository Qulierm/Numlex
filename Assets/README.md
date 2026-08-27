# Numlex app icon sources

Canonical authored source
-------------------------
`AppIcon.icon/` is the original Icon Composer package (icon.json + the two
glyph alpha masks). It contains NO border, stroke, or outline layer: the
background is a solid display-p3 `0.11615` fill with the blue N / green L
gradient glyph layers (group neutral shadow 0.5, translucency 0.5).

Why the iconset directories exist
---------------------------------
Raster exports of this `.icon` (Icon Composer / ictool, "macOS" or
"iOS Default" platform) bake in a platform specular finish: a bright
neutral bevel around the outer perimeter (top-center opaque RGB ~134 fading
over ~20 px into the dark fill). That rim is export machinery, not authored
artwork, so the flattened exports are NOT canonical.

- `AppIcon.flattened.iconset/` — flattened per-size exports, kept only as
  the deterministic INPUT for the rim strip (the per-size variants are
  hand-tuned and stay crisper than downscaling; the strip preserves them
  outside the outer correction band).
- `AppIcon.iconset/` — GENERATED rimless fallback rasters (all ten native
  slots). Regenerate with:
  `Scripts/strip-icon-rim.py` (rim correction) then
  `Scripts/generate-app-icon.sh` (iconutil ICNS build).

Build notes
-----------
- `Scripts/generate-app-icon.sh` packs `AppIcon.iconset` into
  `Sources/NumlexApp/Resources/AppIcon.icns` (legacy fallback, no resizing).
- `Scripts/build-app.sh` additionally tries the official Xcode `actool`
  route to compile `AppIcon.icon` into a native `Assets.car`
  (`CFBundleIconName`) when a full Xcode is available; the rimless ICNS
  (`CFBundleIconFile`) is the verified resource macOS actually presents when
  the native route would reintroduce the specular rim.
