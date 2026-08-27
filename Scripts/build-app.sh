#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="Numlex"
BUNDLE_ID="com.numlex.app"
VERSION="3.1.0"
BIN_PATH="$(swift build -c $CONFIG --show-bin-path)"
APP_DIR="$ROOT/.build/Numlex.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Building Numlex ($CONFIG)..."
swift build -c $CONFIG

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Icon (required — declared as CFBundleIconFile=AppIcon in Info.plist).
# Rimless fallback: built by Scripts/generate-app-icon.sh from
# Assets/AppIcon.iconset (see Assets/README.md for provenance: the authored
# Assets/AppIcon.icon has no stroke; ictool raster exports bake a platform
# specular rim, which the tracked iconset has had removed).
if [ ! -f "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" ]; then
  echo "Missing Sources/NumlexApp/Resources/AppIcon.icns"
  exit 1
fi
cp "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Native icon (Assets.car) via the official Xcode actool route, when a
# full Xcode is discoverable. Compiles the authored AppIcon.icon for
# macosx/26; the runtime then uses CFBundleIconName (layered, rimless —
# no ictool raster export involved). The rimless icns above stays as the
# verified legacy fallback (CLT-only builds have no car at all).
NATIVE_ICON=0
find_actool() {
  if [ -n "${DEVELOPER_DIR:-}" ] && [ -x "${DEVELOPER_DIR}/usr/bin/actool" ]; then
    echo "${DEVELOPER_DIR}/usr/bin/actool"; return 0
  fi
  local a
  if command -v xcrun >/dev/null 2>&1 && a="$(xcrun --find actool 2>/dev/null)" && [ -x "$a" ]; then
    echo "$a"; return 0
  fi
  local x
  for x in /Applications/Xcode.app /Volumes/*/Applications/Xcode.app; do
    [ -d "$x" ] || continue
    if [ -x "$x/Contents/Developer/usr/bin/actool" ]; then
      echo "$x/Contents/Developer/usr/bin/actool"; return 0
    fi
  done
  return 1
}
ACTOOL="$(find_actool || true)"
if [ -n "$ACTOOL" ] && [ -d "$ROOT/Assets/AppIcon.icon" ]; then
  CAR_STAGE="${RESOURCES_DIR}/.icon-stage.$$"
  mkdir -p "$CAR_STAGE"
  if "$ACTOOL" --compile "$CAR_STAGE" --platform macosx --minimum-deployment-target 26.0 \
       --app-icon AppIcon --output-partial-info-plist "$CAR_STAGE/partial.plist" \
       "$ROOT/Assets/AppIcon.icon" >/dev/null 2>&1 \
     && [ -s "$CAR_STAGE/Assets.car" ]; then
    cp "$CAR_STAGE/Assets.car" "$RESOURCES_DIR/Assets.car"
    # Merge the official partial plist keys (CFBundleIconName/CFBundleIconFile).
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
      || true
    NATIVE_ICON=1
  fi
  rm -rf "$CAR_STAGE"
  if [ "$NATIVE_ICON" = "1" ]; then
    echo "Native icon compiled via actool: Assets.car (CFBundleIconName=AppIcon)"
  else
    echo "actool available but compilation failed; legacy AppIcon.icns only"
  fi
else
  echo "No Xcode actool found; legacy AppIcon.icns only (CLT flow)"
fi

# Ad-hoc sign if codesign available
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "codesign ad-hoc failed (ignored)"
fi

echo "Done: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/Numlex"
