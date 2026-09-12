#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="Numlex"
BUNDLE_ID="com.numlex.app"
# The packaged app embeds Sparkle.framework in Contents/Frameworks, so the
# executable needs its own @loader_path/../Frameworks rpath (SwiftPM's
# build-time rpath points into .build, which does not ship).
BUILD_FLAGS=(-c "$CONFIG" -Xlinker -rpath -Xlinker @loader_path/../Frameworks)
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
APP_DIR="$ROOT/.build/Numlex.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
# Single source of truth for the app version: the source Info.plist.
SRC_PLIST="$ROOT/Sources/NumlexApp/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC_PLIST")"
SU_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$SRC_PLIST")"
SU_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$SRC_PLIST")"
SU_VERIFY="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$SRC_PLIST")"
SU_PROFILE="$(/usr/libexec/PlistBuddy -c 'Print :SUEnableSystemProfiling' "$SRC_PLIST")"
if [ -f "$ROOT/Package.resolved" ]; then
  SPARKLE_VERSION="$(plutil -extract pins.0.state.version raw -o - "$ROOT/Package.resolved")"
else
  # A fresh clone may not have resolved yet; the manifest still pins exactly.
  SPARKLE_VERSION="$(sed -n 's/.*exact: "\([0-9.]*\)".*/\1/p' "$ROOT/Package.swift" | head -1)"
fi
[ -n "$SPARKLE_VERSION" ] || { echo "Cannot determine the pinned Sparkle version"; exit 1; }

echo "Building Numlex ($CONFIG)..."
swift build "${BUILD_FLAGS[@]}"

if [ ! -f "$BIN_PATH/Numlex" ]; then
  echo "Binary not found at $BIN_PATH/Numlex"
  exit 1
fi

echo "Packaging .app at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH/Numlex" "$MACOS_DIR/Numlex"
chmod +x "$MACOS_DIR/Numlex"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>SUFeedURL</key><string>$SU_FEED</string>
    <key>SUPublicEDKey</key><string>$SU_KEY</string>
    <key>SUVerifyUpdateBeforeExtraction</key><$SU_VERIFY/>
    <key>SUEnableSystemProfiling</key><$SU_PROFILE/>
</dict>
</plist>
PLIST

# Minimal assertions on the packaged metadata (fail loudly on drift).
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$BUNDLE_ID" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")" == "26.0" ]]

# Modern icons: ONE Xcode 26 Liquid Glass Assets.car carrying BOTH named
# iconstacks — AppIcon (primary, CFBundleIconName) and AppIconLight
# (alternate, selected at runtime through NSImage(named:)). Compiled by
# Scripts/compile-modern-app-icon.sh on the macos-26 Actions runner and
# committed to Assets/AppIcon.compiled/ (see Assets/README.md provenance).
CAR="$ROOT/Assets/AppIcon.compiled/Assets.car"
if [ ! -s "$CAR" ]; then
  echo "Missing modern icon: $CAR (run the 'Build Modern App Icon' GitHub Action first)"
  exit 1
fi
cp "$CAR" "$RESOURCES_DIR/Assets.car"

# Fail closed: the packaged catalog MUST carry both named iconstacks with
# full rendition ladders. A missing alternate would silently downgrade the
# Light choice to the ICNS fallback (the original sizing regression).
if command -v xcrun >/dev/null 2>&1; then
  CARINFO="$(mktemp)"
  if xcrun --sdk macosx assetutil --info "$RESOURCES_DIR/Assets.car" > "$CARINFO" 2>/dev/null; then
    python3 - "$CARINFO" <<'PYCAR'
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
start = text.find("[")
entries = json.loads(text[start:]) if start >= 0 else []
by_name = {}
for e in entries:
    if e.get("Name"):
        by_name.setdefault(e["Name"], []).append(e)
fail = []
for name in ("AppIcon", "AppIconLight"):
    stacks = [e for e in by_name.get(name, []) if e.get("AssetType") == "IconImageStack"]
    px = {e.get("PixelWidth") for e in by_name.get(name, [])
          if e.get("AssetType") == "Icon Image" and isinstance(e.get("PixelWidth"), int)}
    if not stacks:
        fail.append(f"{name}: no IconImageStack")
    if not {512, 1024} <= px:
        fail.append(f"{name}: missing modern renditions (present: {sorted(px)})")
    print(f"ok:   packaged {name}: {len(stacks)} stacks, renditions {sorted(px)}")
if fail:
    for f in fail:
        print("FAIL: " + f, file=sys.stderr)
    sys.exit(1)
PYCAR
  else
    echo "build-app: assetutil unavailable; skipping the dual-iconstack assertion"
  fi
  rm -f "$CARINFO"
else
  echo "build-app: xcrun unavailable; skipping the dual-iconstack assertion"
fi

# Legacy fallback (required on systems that ignore Assets.car): the
# user-supplied AppIcon.icns, installed byte-exact by
# Scripts/generate-app-icon.sh; declared as CFBundleIconFile=AppIcon.
if [ ! -f "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" ]; then
  echo "Missing Sources/NumlexApp/Resources/AppIcon.icns"
  exit 1
fi
cp "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# The NumlexCore SwiftPM resource bundle carries the offline timezone
# catalog. It is REQUIRED: a missing bundle (or a missing data file) fails the
# build instead of shipping an app whose timezone lookups silently fail.
CORE_BUNDLE="$(find "$ROOT/.build" -maxdepth 3 -name "Numlex_NumlexCore.bundle" -type d 2>/dev/null | head -1)"
if [ -z "$CORE_BUNDLE" ] || [ ! -d "$CORE_BUNDLE" ]; then
  echo "Missing NumlexCore resource bundle (.build/.../Numlex_NumlexCore.bundle)"
  exit 1
fi
for required in NumlexTimezones/iana-zones.tsv NumlexTimezones/cities.tsv NumlexTimezones/countries.tsv NumlexTimezones/airports.tsv NumlexTimezones/sources.json; do
  if [ ! -f "$CORE_BUNDLE/$required" ]; then
    echo "Missing timezone resource: $required"
    exit 1
  fi
done
rm -rf "$RESOURCES_DIR/Numlex_NumlexCore.bundle"
cp -R "$CORE_BUNDLE" "$RESOURCES_DIR/Numlex_NumlexCore.bundle"

# ---------------------------------------------------------------------------
# Alternate app icon (user-selectable Light) + the two Settings preview
# tiles. Byte-exact copies of the committed sources; the build FAILS CLOSED on
# a missing source or on any hash drift, so a packaged release can never ship
# a silently different icon. The Dark primary (Assets.car + AppIcon.icns) is
# never touched: selecting Dark resets to the bundle default instead.
# ---------------------------------------------------------------------------
LIGHT_ICON_SRC="$ROOT/Sources/NumlexApp/Resources/AppIconLight.icns"
LIGHT_ICON_SHA="d6d3c7108b437f4f0e51ad7a8989ad5b59a3e01e1a2e7044a2ac027c54c83e40"
DARK_PREVIEW_SRC="$ROOT/Sources/NumlexApp/Resources/AppIconDarkPreview.png"
DARK_PREVIEW_SHA="f2b66202656f9d04372010d251a54668d1a9d153648bb4940465c43e85902932"
LIGHT_PREVIEW_SRC="$ROOT/Sources/NumlexApp/Resources/AppIconLightPreview.png"
LIGHT_PREVIEW_SHA="4367adca2ded31ca07fe7cfcd7f1be4cab3b1e3a1fe927dc4d1a5855d505cf2e"
for pair in "$LIGHT_ICON_SRC|$LIGHT_ICON_SHA" \
            "$DARK_PREVIEW_SRC|$DARK_PREVIEW_SHA" \
            "$LIGHT_PREVIEW_SRC|$LIGHT_PREVIEW_SHA"; do
  src="${pair%%|*}"
  want="${pair##*|}"
  name="$(basename "$src")"
  if [ ! -f "$src" ]; then
    echo "Missing alternate icon resource: $src"
    exit 1
  fi
  got="$(shasum -a 256 "$src" | awk '{print $1}')"
  if [ "$got" != "$want" ]; then
    echo "Alternate icon resource hash drift: $name"
    echo "  expected $want"
    echo "  actual   $got"
    exit 1
  fi
  cp "$src" "$RESOURCES_DIR/$name"
  packed="$(shasum -a 256 "$RESOURCES_DIR/$name" | awk '{print $1}')"
  if [ "$packed" != "$want" ]; then
    echo "Packaged alternate icon resource mismatch: $name"
    exit 1
  fi
done


# ---------------------------------------------------------------------------
# Sparkle 2.9.6 embedding (secure in-app updates).
#
# The official SwiftPM artifact ships the prebuilt dynamic framework. It is
# copied with `ditto` so the Versions/B layout and every symlink survive, then
# signed from the INSIDE OUT (XPC services -> Updater.app -> Autoupdate ->
# framework -> app). Never `codesign --deep`: nested signing must be explicit.
#
# The app is not sandboxed; Sparkle's XPC services are kept (the supported
# configuration documented by Sparkle) so download/installation always work.
# ---------------------------------------------------------------------------
SPARKLE_XCFRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
SPARKLE_SRC="$SPARKLE_XCFRAMEWORK/Sparkle.framework"
if [ ! -d "$SPARKLE_SRC" ]; then
  SPARKLE_SRC="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path "*Sparkle.xcframework*" 2>/dev/null | head -1)"
fi
if [ ! -d "$SPARKLE_SRC" ]; then
  echo "Missing Sparkle.framework — run 'swift package resolve' first"
  exit 1
fi

FRAMEWORKS_DIR="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
ditto "$SPARKLE_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_FW="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_B="$SPARKLE_FW/Versions/B"

# Version assertion: the embedded framework must be exactly the pinned one.
EMBEDDED_SPARKLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SPARKLE_B/Resources/Info.plist")"
if [ "$EMBEDDED_SPARKLE_VERSION" != "$SPARKLE_VERSION" ]; then
  echo "Embedded Sparkle $EMBEDDED_SPARKLE_VERSION != pinned $SPARKLE_VERSION"
  exit 1
fi
for required in "$SPARKLE_B/Sparkle" "$SPARKLE_B/Autoupdate" "$SPARKLE_B/Updater.app" \
                "$SPARKLE_B/XPCServices/Downloader.xpc" "$SPARKLE_B/XPCServices/Installer.xpc"; do
  if [ ! -e "$required" ]; then
    echo "Missing Sparkle component: $required"
    exit 1
  fi
done
# Symlink layout must survive packaging (Sparkle loads through it).
if [ ! -L "$SPARKLE_FW/Versions/Current" ] || [ ! -L "$SPARKLE_FW/Sparkle" ]; then
  echo "Sparkle framework symlinks were not preserved"
  exit 1
fi

# Sign the bundle. Default is ad-hoc (-); NUMLEX_SIGN_IDENTITY is an OPTIONAL
# override for a specific identity. A stable identity is NOT required for
# in-app installs: Numlex relies on Sparkle's two independent trust routes —
# the MANDATORY EdDSA archive signature (SUPublicEDKey, verified before
# extraction thanks to SUVerifyUpdateBeforeExtraction) and, only as a
# fallback, Apple code-signing identity matching. When the EdDSA signature
# validates, the pre-validated path in Sparkle 2.9.6 requires only that the
# new bundle has a valid signature and that signing was not removed; ad-hoc
# signatures are explicitly supported (the identity-matching route simply
# cannot match cdhash-based ad-hoc requirements). See docs/UPDATES.md and
# Scripts/verify-sparkle-policy.sh. This is NOT Developer ID and NOT
# notarized. Signing failure is fatal (no silent ignore).
SIGN_ID="${NUMLEX_SIGN_IDENTITY:--}"
sign_nested() {
  codesign --force --sign "$SIGN_ID" "$1"
}
for xpc in "$SPARKLE_B/XPCServices/"*.xpc; do
  sign_nested "$xpc"
done
sign_nested "$SPARKLE_B/Updater.app"
sign_nested "$SPARKLE_B/Autoupdate"
sign_nested "$SPARKLE_FW"
codesign --force --sign "$SIGN_ID" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

# ---------------------------------------------------------------------------
# Updater packaging assertions (fail closed on any drift).
# ---------------------------------------------------------------------------
for key in SUFeedURL SUPublicEDKey SUVerifyUpdateBeforeExtraction SUEnableSystemProfiling; do
  SRC_VALUE="$(/usr/libexec/PlistBuddy -c "Print :$key" "$SRC_PLIST")"
  APP_VALUE="$(/usr/libexec/PlistBuddy -c "Print :$key" "$CONTENTS/Info.plist")"
  if [ "$SRC_VALUE" != "$APP_VALUE" ]; then
    echo "Info.plist drift for $key: source='$SRC_VALUE' app='$APP_VALUE'"
    exit 1
  fi
done
case "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$CONTENTS/Info.plist")" in
  https://*) ;;
  *) echo "SUFeedURL must be HTTPS"; exit 1 ;;
esac
if ! otool -L "$MACOS_DIR/Numlex" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
  echo "Packaged binary does not link @rpath/Sparkle.framework/Versions/B/Sparkle"
  exit 1
fi
if ! otool -l "$MACOS_DIR/Numlex" | grep -A2 LC_RPATH | grep -q '@loader_path/../Frameworks'; then
  echo "Packaged binary lacks the @loader_path/../Frameworks rpath"
  exit 1
fi
for signed in "$SPARKLE_B/XPCServices/Downloader.xpc" "$SPARKLE_B/XPCServices/Installer.xpc" \
              "$SPARKLE_B/Updater.app" "$SPARKLE_B/Autoupdate" "$SPARKLE_FW" "$APP_DIR"; do
  codesign --verify --strict "$signed" 2>/dev/null || {
    echo "codesign --verify --strict failed: $signed"
    exit 1
  }
done
echo "Sparkle $EMBEDDED_SPARKLE_VERSION embedded (signed: $SIGN_ID)"

echo "Done: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/Numlex"
