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

# Icon (required — declared as CFBundleIconFile=AppIcon in Info.plist)
if [ ! -f "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" ]; then
  echo "Missing Sources/NumlexApp/Resources/AppIcon.icns"
  exit 1
fi
cp "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Ad-hoc sign if codesign available
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "codesign ad-hoc failed (ignored)"
fi

echo "Done: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/Numlex"
