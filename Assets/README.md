# App icons and project media

## Current icon pipeline

Numlex packages a committed modern icon catalog and keeps ICNS resources as
fallbacks. `Assets/AppIcon.compiled/Assets.car` contains both named iconstacks:
`AppIcon` (primary) and `AppIconLight` (alternate). Each includes the 32/64/128/
256/512/1024 rendition ladder in Aqua, DarkAqua and tintable appearances. The
committed catalog is protected byte-for-byte:

- SHA-256: `be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d`
- 3,407,048 bytes; Xcode 26.6 / macOS 26 Actions run
  [34610169645](https://github.com/Qulierm/Numlex/actions/runs/34610169645)
- Committed `icon-build-metadata.json`, `Assets.car.assetutil-info.txt`,
  `Assets.car-partial.plist` and `xcode-version.txt` record its inputs, compiler
  run and output checks. CI also emits `actool.log` for diagnostics; that
  generated log is not a committed input or a fresh-checkout prerequisite.

The modern catalog is compiled from both Icon Composer packages in one
`xcrun actool` invocation by `Scripts/compile-modern-app-icon.sh`. The manual
[Build Modern App Icon workflow](../.github/workflows/build-modern-app-icon.yml)
runs on `macos-26`; the compiler verifies both stacks and rendition ladders
before an artifact can be committed. Local app builds copy the already-committed
`Assets.car`; they do not generate it.

### Sources, fallbacks and previews

- `Assets/AppIcon.icon/` is the user-supplied Dark Icon Composer project. Its
  `icon.json` SHA-256 is
  `347f6a378e7267d944cffd66b93c768f410431cb6f228f6bd9fc2e240b7ff726`; the
  source image SHA-256 is
  `b293279246cb9e37396b89878c5d631e6ff8c35a6e7fd95a2622b483d5c0080d`.
- `Assets/AppIconLight.icon/` is the reconstructed Light Composer project, not
  a user-supplied or flattened ICNS. It shares the Dark source mask and geometry;
  its `system-light` fill and calibrated gradient are checked by
  `Scripts/validate-icon-sources.sh`.
- `Assets/AppIcon.icns` is the user-supplied legacy fallback, installed
  byte-for-byte by `Scripts/generate-app-icon.sh` after `iconutil` and native
  rendition checks. SHA-256:
  `b2bc96a9a52544611e997ec6176dd7a7ac981bc259f1b53104e4767e59a6a4b4`
  (656,587 bytes). `Sources/NumlexApp/Resources/AppIconLight.icns` is retained
  for development fallback use when the compiled catalog is unavailable.
- `Assets/AppIconPreview.png` is the extracted 512 px Dark preview used by the
  README. `Sources/NumlexApp/Resources/AppIconLightPreview.png` is the Light
  preview. Previews do not supply packaged icon bytes.

`Scripts/validate-icon-sources.sh` checks the Composer source/preview contract.
The modern-icon workflow uses the Xcode 26 `macos-26` runner; when its bundled
`ictool` cannot export a preview, the workflow reports that skip and still
compiles and validates the catalog. Preserve all source packages, previews,
metadata and validators; do not hand-edit protected hashes.

`Scripts/build-app.sh` copies `Assets.car` and the ICNS fallback before signing.
The modern `Assets.car` supplies the app icon when present; ICNS remains the
fallback. Neither file is rebuilt during ordinary app assembly.

## Project media

These project visuals are separate from icon-generation inputs. Preserve their
original bytes and paths:

- `Assets/NumlexScreenshot.png` — README hero screenshot.
- `Assets/Demos/base.gif`, `household.gif`, `kilometres.gif` and `linked.gif` —
  the four README feature demonstrations.
- `Assets/DMG/numlex-tagline.png` — a separately pinned typography reference
  for “Think freely. We'll do the math.”; it is not an icon input.

The screenshot and demonstrations are linked directly from the root README.
Do not crop, recompress, recolor or regenerate them as part of icon work.
