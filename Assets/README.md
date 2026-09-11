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
4. `Assets/AppIcon.compiled/` — the compiled modern icons committed from a
   verified Actions run: ONE `Assets.car` carrying BOTH named iconstacks —
   `AppIcon` (primary, `CFBundleIconName=AppIcon`) and `AppIconLight`
   (alternate, selected at runtime with
   `NSImage(named: NSImage.Name("AppIconLight"))`) — each with the full
   rendition ladder 32/64/128/256/512/1024 in Aqua + DarkAqua +
   tintable. `Assets.car-partial.plist` (actool emits
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

Alternate (Light) Composer source — RECONSTRUCTED, not user-supplied
-------------------------------------------------------------------
`AppIconLight.icon/` is a genuine Icon Composer package built for this
project (it is NOT a byte-exact copy of a user-supplied file, and it is
NOT a flattened/resized ICNS):
- the foreground MASK is the dark package's `Assets/Image 32.png` copied
  byte-exactly (SHA-256 `b2932792…c0080d`), with the same scale 1.9,
  translation [0,0], layer/image names, neutral shadow 0.5, translucency
  0.5 and gradient orientation — so Light and Dark share the exact safe
  area and logo bounds;
- the background is the official `system-light` fill;
- the layer gradient was reverse-derived deterministically from the
  supplied Light preview (`Sources/NumlexApp/Resources/AppIconLightPreview.png`,
  SHA-256 `4367adca…cf2e`) by least squares over three affine basis
  renders of the same pipeline, then refined by coordinate descent:
  top `srgb:0.25114,0.25114,0.25114`, bottom `srgb:0.0,0.0,0.0`.
  Calibration (Icon Composer 1.4 `ictool`, macOS Default 512×512 scale 1):
  alpha geometry EXACT (0 differing alpha pixels), mean per-pixel
  max-channel RGB error 1.085/255, 2 pixels above 32/255; the residual is
  the official renderer's edge sampling.
- `Scripts/validate-icon-sources.sh` enforces this contract locally
  (Dark render byte-identical to its preview; Light alpha exact plus the
  bounded RGB tolerance; both packages sharing mask/scale/effects).
  The Xcode-bundled `ictool` on CI has no `--export-image` CLI, so the CI
  run reports the skip loudly and compiles instead.

Canonical modern-icon build path: `Scripts/compile-modern-app-icon.sh`
(`xcrun actool` compiles BOTH .icon packages in ONE invocation —
`--compile --platform macosx --minimum-deployment-target 26.0
--target-device mac --app-icon AppIcon --alternate-app-icon AppIconLight`;
Xcode 26's ictool has no IR-export flag and no IR detour is needed) run on
the GitHub Actions `macos-26` runner
(`.github/workflows/build-modern-app-icon.yml`, which may be dispatched on
a focused `ci/light-modern-app-icon` branch). The compiler fails closed
unless `assetutil --info` shows a real `IconImageStack` entry AND the
modern rendition ladder for BOTH names, and it records both source hashes.

Current committed catalog (see `Assets/AppIcon.compiled/icon-build-metadata.json`):
Actions run `34610169645`
(<https://github.com/Qulierm/Numlex/actions/runs/34610169645>), Xcode 26.6
(sdk 26.5), `Assets.car` SHA-256
`be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d`,
3,407,048 bytes, iconstacks `AppIcon` + `AppIconLight`, renditions
32/64/128/256/512/1024 each. `Assets/AppIcon.icns` and
`Sources/NumlexApp/Resources/AppIconLight.icns` remain the explicit
legacy/development fallbacks — the modern Assets.car takes precedence
when present (and the Light runtime path normalizes an ICNS fallback to
the bundle default's 128 pt logical size in memory, never rewriting the
resource).

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
