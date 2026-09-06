# Numlex app icon sources

Pipeline
--------
user-supplied ICNS, installed byte-for-byte (no processing of any kind):

1. `Assets/AppIcon.icns` — the CANONICAL icon file, supplied by the user
   (from `/Users/nikita/Downloads/Numlex.icns`), tracked byte-exact:
   SHA-256 `b2bc96a9a52544611e997ec6176dd7a7ac981bc259f1b53104e4767e59a6a4b4`,
   656,587 bytes. Native reps 32/256/512 px. No script ever modifies it.
2. `Scripts/generate-app-icon.sh` — validates the canonical file with
   `iconutil -c iconset`, verifies usable 32/256/512 reps, then copies it
   BYTE-FOR-BYTE to `Sources/NumlexApp/Resources/AppIcon.icns` (hash +
   `cmp` proof). It never constructs from PNG slots, resizes, recolors,
   strips rims, injects profiles, repacks, or synthesizes representations.
3. `Assets/AppIconPreview.png` — exact 512 rep extracted from the canonical
   ICNS for README display only; extraction never affects packaged bytes.

Legacy reference (not active)
-----------------------------
`AppIcon.exported.iconset/` and `AppIcon.iconset/` are the previous
PNG-slot pipeline's inputs (ten native rasters). They are kept for
reference only; no active script reads them. Do not regenerate the ICNS
from them.

Build
-----
- `Scripts/build-app.sh` copies the ICNS into the bundle and signs it.
  The ICNS is the single authoritative icon resource
  (`CFBundleIconFile=AppIcon`); no `Assets.car` is produced.
