#!/bin/bash
# Modern (Xcode 26 / Liquid Glass) app-icon compiler.
#
# Usage: Scripts/compile-modern-app-icon.sh [source-icn] [output-directory]
#   source-icn defaults to <repo>/Assets/AppIcon.icon (Icon Composer
#   package, tracked byte-exact — see Assets/README.md provenance).
#   output-directory defaults to <repo>/Assets/AppIcon.compiled.
#
# Pipeline (no flattening, no RGB processing, no downloads):
#   1. Xcode 26 `actool` compiles the .icon package DIRECTLY into
#      Assets.car (modern iconstack renditions) plus AppIcon.icns and
#      an actool partial Info.plist, targeting macOS 26.
#      (Verified on the macos-26 / Xcode 26.6 runner: `actool
#      Assets/AppIcon.icon --compile ... --app-icon AppIcon` succeeds.
#      The older Icon Composer 1.4 `ictool
#      --export-intermediate-representation` IR detour is NOT available
#      in Xcode 26's ictool build and is not needed.)
#   2. fail-closed validation: Assets.car + partial plist exist and are
#      nonempty, the partial plist carries CFBundleIconName=AppIcon,
#      `assetutil --info` parses the car, AppIcon entries are present,
#      source + artifact hashes are recorded in
#      <out>/icon-build-metadata.json.
#
# Requires: macOS, Xcode 26+ (CI: `macos-26` runner, Xcode_26.6.app).
# `ictool` (same build as actool) is used for version provenance only.
# Nothing is ever curl'd or downloaded.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${ROOT}/Assets/AppIcon.icon}"
OUT="${2:-${ROOT}/Assets/AppIcon.compiled}"

die() { echo "compile-modern-app-icon: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "requires macOS"
[ -d "$SRC" ] || die "Icon Composer package not found: $SRC"
[ -s "$SRC/icon.json" ] || die "missing icon.json in $SRC"

# --- Xcode 26+ (actool) required.
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
[ -n "$DEVELOPER_DIR" ] && [ -d "$DEVELOPER_DIR" ] \
    || die "no Xcode developer directory (set DEVELOPER_DIR or xcode-select)"
XVER="$(xcodebuild -version 2>/dev/null | awk '/Xcode/{print $2}')"
[ -n "$XVER" ] || die "xcodebuild not usable"
SDKVER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo unknown)"
echo "compile-modern-app-icon: Xcode ${XVER} (sdk ${SDKVER}), DEVELOPER_DIR=${DEVELOPER_DIR}"
case "${XVER%%.*}" in
    26|27|28|29|30|31|32|33|34|35) : ;;
    *) die "requires Xcode 26 or newer, found: ${XVER}" ;;
esac

xcrun --find actool >/dev/null 2>&1 || die "actool not found in selected Xcode"

# --- ictool (same Xcode build) for provenance. Never download anything.
ICTOOL="$(xcrun --find ictool 2>/dev/null || true)"
if [ -z "$ICTOOL" ] || [ ! -x "$ICTOOL" ]; then
    CANDIDATES="$(find "$DEVELOPER_DIR" \
        -path '*/Icon Composer.app/Contents/Executables/ictool' -type f 2>/dev/null || true)"
    [ -z "$CANDIDATES" ] && CANDIDATES="$(printf '%s\n' "$DEVELOPER_DIR/usr/bin/ictool" "$DEVELOPER_DIR/../../Icon Composer.app/Contents/Executables/ictool" 2>/dev/null | grep -m1 'ictool$' || true)"
    ICTOOL="$(printf '%s\n' "$CANDIDATES" | grep -m1 '^/.*ictool$' || true)"
fi
[ -n "$ICTOOL" ] && [ -x "$ICTOOL" ] \
    || die "ictool not found (xcrun or inside Xcode bundle) — needed for version provenance"
ICTOOL_VER_PLIST="$($ICTOOL --version 2>&1 || true)"
ICBUILD="$(printf '%s' "$ICTOOL_VER_PLIST" | tr -d '[:space:]' | sed -n 's/.*bundle-version..string.\([0-9][0-9]*\).*/\1/p' | head -1)"
echo "compile-modern-app-icon: ictool=$ICTOOL (build ${ICBUILD:-unknown})"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1) Compile the .icon package directly with actool.
mkdir -p "$OUT"
ACTOOL_ARGS=(
    "$SRC"
    --compile "$OUT"
    --platform macosx
    --minimum-deployment-target 26.0
    --target-device mac
    --app-icon AppIcon
    --output-partial-info-plist "$OUT/Assets.car-partial.plist"
    --output-format human-readable-text
)
# actool accepts .icon as an input on Xcode 26 (verified on macos-26 runner).
xcrun actool "${ACTOOL_ARGS[@]}" > "$WORK/actool.log" 2>&1 \
    || { tail -60 "$WORK/actool.log" >&2; die "actool compile failed"; }

[ -s "$OUT/Assets.car" ] || die "actool produced no/nonempty Assets.car"
[ -s "$OUT/Assets.car-partial.plist" ] || die "actool produced no/nonempty partial plist"
plutil -lint "$OUT/Assets.car-partial.plist" >/dev/null || die "partial plist not valid XML/plist"

# --- 2) Fail-closed artifact inspection.
ICONNAME="$(plutil -extract CFBundleIconName raw "$OUT/Assets.car-partial.plist" 2>/dev/null || true)"
[ "$ICONNAME" = "AppIcon" ] || {
    echo "compile-modern-app-icon: partial plist keys:" >&2
    plutil -p "$OUT/Assets.car-partial.plist" >&2 || cat "$OUT/Assets.car-partial.plist" >&2
    die "partial plist CFBundleIconName expected 'AppIcon', got: '${ICONNAME:-missing}'"
}

CARINFO="$WORK/car-info.txt"
xcrun --sdk macosx assetutil --info "$OUT/Assets.car" > "$CARINFO" 2>&1 \
    || { tail -40 "$CARINFO" >&2; die "assetutil cannot parse Assets.car"; }
grep -q "AppIcon" "$CARINFO" || die "Assets.car inventory has no AppIcon entries"
cp "$CARINFO" "$OUT/Assets.car.assetutil-info.txt"

# --- 3) Reproducibility metadata.
ICONJSON_SHA="$(shasum -a 256 "$SRC/icon.json" | cut -d' ' -f1)"
IMG_SHA="$(find "$SRC/Assets" -type f | sort | xargs shasum -a 256 | cut -d' ' -f1 | tr '\n' ' ')"
ICONHASH="$(shasum -a 256 "$OUT/Assets.car" | cut -d' ' -f1)"
ICNS_SHA=""
[ -f "$OUT/AppIcon.icns" ] && ICNS_SHA="$(shasum -a 256 "$OUT/AppIcon.icns" | cut -d' ' -f1)"
cat > "$OUT/icon-build-metadata.json" <<JSON
{
  "tool": "xcrun actool (Xcode 26) compiling .icon package directly",
  "platform": "macosx",
  "minimum-deployment-target": "26.0",
  "target-device": "mac",
  "app-icon": "AppIcon",
  "xcode": "$(xcodebuild -version 2>/dev/null | head -1)",
  "xcode-sdk": "${SDKVER}",
  "xcode-developer-dir": "${DEVELOPER_DIR}",
  "ictool": "${ICTOOL}",
  "ictool-build": "${ICBUILD:-unknown}",
  "source-icon-json-sha256": "${ICONJSON_SHA}",
  "source-asset-shas256": "${IMG_SHA}",
  "assets-car-sha256": "${ICONHASH}",
  "assets-car-bytes": "$(stat -f %z "$OUT/Assets.car" 2>/dev/null || stat -c %s "$OUT/Assets.car")",
  "derived-appicon-icns-sha256": "${ICNS_SHA}",
  "partial-plist-cfbundleiconname": "AppIcon",
  "source-package": "$(basename "$SRC")",
  "built-at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
cp "$WORK/actool.log" "$OUT/actool.log" 2>/dev/null || true
printf '%s\n' "Xcode ${XVER}" "sdk ${SDKVER}" "DEVELOPER_DIR ${DEVELOPER_DIR}" > "$OUT/xcode-version.txt"

echo "compile-modern-app-icon: OK — $OUT/Assets.car (sha256 $ICONHASH), CFBundleIconName=AppIcon"
echo "compile-modern-app-icon: AppIcon renditions present (see Assets.car.assetutil-info.txt)"
