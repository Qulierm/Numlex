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
4. `Assets/AppIcon.compiled/` — the compiled modern icon committed from a
   verified Actions run: `Assets.car` (iconstack renditions, Aqua +
   DarkAqua), `Assets.car-partial.plist` (actool emits
   `CFBundleIconFile=AppIcon` + `CFBundleIconName=AppIcon`),
   `Assets.car.assetutil-info.txt`, `icon-build-metadata.json` (run URL,
   Xcode/ictool versions, source + artifact hashes), `actool.log`,
   `xcode-version.txt`. To rebuild: GitHub Actions → "Build Modern App
   Icon" → Run workflow (or `gh workflow run build-modern-app-icon.yml`
   on main), download the `numlex-modern-app-icon` artifact (7-day
   retention), verify the SHA-256 in `icon-build-metadata.json`, and
   commit the artifact into this directory. This artifact is NOT a
   release; it only reaches users in the next app release.

Build wiring
-----------
- `Scripts/build-app.sh` copies `Assets/AppIcon.compiled/Assets.car` into
  the bundle (`CFBundleIconName=AppIcon` — modern rendition takes
  precedence on macOS 26) and keeps the user-supplied `AppIcon.icns`
  (`CFBundleIconFile=AppIcon`) as the legacy fallback. Both are copied
  before the ad-hoc signature; no `Assets.car` is ever generated at
  local build time.

Modern Icon Composer source (Xcode 26 / Liquid Glass)
-----------------------------------------------------
`AppIcon.icon/` — user-supplied Icon Composer project (from
`/Users/nikita/Downloads/numlex.icon`, package renamed to `AppIcon.icon`
so the asset name is `AppIcon`), tracked byte-exact:
- `icon.json` SHA-256 `347f6a378e7267d944cffd66b93c768f410431cb6f228f6bd9fc2e240b7ff726`
- `Assets/Image 32.png` SHA-256 `b293279246cb9e37396b89878c5d631e6ff8c35a6e7fd95a2622b483d5c0080d`
Contents: system-dark fill, one glass/translucent layer (gradient white,
scale 1.9, neutral shadow). No script modifies the package.

Canonical modern-icon build path: `Scripts/compile-modern-app-icon.sh`
(`xcrun actool` compiles the .icon package directly — `--compile --platform
macosx --minimum-deployment-target 26.0 --target-device mac --app-icon
AppIcon`; Xcode 26's ictool has no IR-export flag and no IR detour is
needed) run on the GitHub Actions `macos-26` runner
(`.github/workflows/build-modern-app-icon.yml`); the compiled
`Assets/AppIcon.compiled/Assets.car` is committed to the repo after
digest-verified inspection (current: built by Actions run
34029287600, Xcode 26.6, SHA-256 `3ff69341…c2996` — see
`Assets/AppIcon.compiled/icon-build-metadata.json`). `Assets/AppIcon.icns` remains the explicit
legacy fallback (installed by `Scripts/generate-app-icon.sh`) — the
modern Assets.car takes precedence when present.

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
