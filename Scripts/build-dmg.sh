#!/bin/bash
# Package .build/Numlex.app into a clean, compressed, read-only DMG.
#
# Output: dist/Numlex-<VERSION>-macOS-<arch>.dmg
#   - volume name "Numlex <VERSION>"
#   - staging contains ONLY Numlex.app plus an Applications symlink
#   - UDZO compressed, read-only HFS+, generated from a private temp dir
#   - NO styled artwork: no .background, no .DS_Store, no .VolumeIcon.icns,
#     no Finder window/icon scripting of any kind (the plain image is the
#     only default; there is no style flag or "-plain" filename suffix)
#
# By default the release app is (re)built via Scripts/build-app.sh.
# Set NUMLEX_USE_BUILT_APP=1 to explicitly consume the already-built
# .build/Numlex.app without rebuilding (no stale-ambiguity: the app
# must exist; the version is always derived from its packaged plist).
#
# Optional safe output override: NUMLEX_DMG_OUTPUT must be an absolute
# path ending in .dmg; its parent directory is created if needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/Numlex.app"
DIST_DIR="$ROOT/dist"
ARCH="$(uname -m)"

if [[ "${NUMLEX_USE_BUILT_APP:-0}" == "1" ]]; then
  if [[ ! -d "$APP_DIR" ]]; then
    echo "NUMLEX_USE_BUILT_APP=1 but $APP_DIR does not exist" >&2
    exit 1
  fi
  echo "Consuming existing $APP_DIR (NUMLEX_USE_BUILT_APP=1)"
else
  bash "$ROOT/Scripts/build-app.sh" release
fi

# Version is the single source of truth from the packaged app plist.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"

STAGE="$(mktemp -d /tmp/numlex-dmg-stage.XXXXXX)"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

echo "Staging DMG content at $STAGE..."
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/Numlex.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST_DIR"
DMG_NAME="Numlex-${VERSION}-macOS-${ARCH}.dmg"
OUTPUT="${NUMLEX_DMG_OUTPUT:-$DIST_DIR/$DMG_NAME}"
case "$OUTPUT" in
  /*.dmg) : ;;
  *)
    echo "NUMLEX_DMG_OUTPUT must be an absolute path ending in .dmg (got: $OUTPUT)" >&2
    exit 1
    ;;
esac
mkdir -p "$(dirname "$OUTPUT")"

echo "Creating read-only UDZO $OUTPUT..."
hdiutil create \
  -volname "Numlex $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$OUTPUT"

echo "Done: $OUTPUT"
ls -lh "$OUTPUT"
