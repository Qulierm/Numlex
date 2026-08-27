#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="Numlex"
BUNDLE_ID="com.numlex.app"
BIN_PATH="$(swift build -c $CONFIG --show-bin-path)"
APP_DIR="$ROOT/.build/Numlex.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
# Single source of truth for the app version: the source Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Sources/NumlexApp/Resources/Info.plist")"

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

# Minimal assertions on the packaged metadata (fail loudly on drift).
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$BUNDLE_ID" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")" == "26.0" ]]

# Icon (required — declared as CFBundleIconFile=AppIcon in Info.plist).
# THE icon: the silver AppIcon.icns built by Scripts/generate-app-icon.sh
# from Assets/AppIcon.iconset (see Assets/README.md for provenance). No
# Assets.car is ever produced — the ICNS is the single authoritative
# resource macOS presents.
if [ ! -f "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" ]; then
  echo "Missing Sources/NumlexApp/Resources/AppIcon.icns"
  exit 1
fi
cp "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"


# Sign the bundle. Default is ad-hoc (-); set NUMLEX_SIGN_IDENTITY for a
# specific identity. This is NOT Developer ID and NOT notarized — do not
# rely on Apple Development identities for public distribution.
# Signing failure is fatal (no silent ignore).
codesign --force --sign "${NUMLEX_SIGN_IDENTITY:--}" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "Done: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/Numlex"
