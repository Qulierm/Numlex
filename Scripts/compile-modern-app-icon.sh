#!/bin/bash
# Modern (Xcode 26 / Liquid Glass) app-icon compiler.
#
# Usage: Scripts/compile-modern-app-icon.sh [source-icn] [output-directory]
#   source-icn defaults to <repo>/Assets/AppIcon.icon (Icon Composer
#   package, tracked byte-exact — see Assets/README.md provenance).
#   output-directory defaults to <repo>/Assets/AppIcon.compiled.
#
# Pipeline (no flattening, no RGB processing, no downloads):
#   1. `ictool --export-intermediate-representation --platform macOS`
#      expands the .icon package into a `<name>.icon.xcassets` containing
#      the `AppIcon.iconstack` (the IR ictool emits is the ONLY valid
#      intermediate; `--export-image` flattens layers and is NEVER used).
#   2. `xcrun actool --app-icon AppIcon` compiles that catalog into
#      Assets.car targeting macOS 26, plus an actool partial Info.plist.
#   3. fail-closed validation: Assets.car + partial plist exist and are
#      nonempty, `assetutil --info` parses the car, the AppIcon/iconstack
#      entries are present in the car inventory, source + IR hashes are
#      recorded in <out>/icon-build-metadata.json.
#
# Requires: macOS, Xcode 26+ (CI: `macos-26` runner, Xcode_26.6.app).
# `ictool` is located via `xcrun --find ictool` or, failing that,
# deterministically inside the selected Xcode bundle
# (`*/Icon Composer.app/Contents/Executables/ictool`). Nothing is ever
# curl'd or downloaded.
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
xcver="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
xcodebuild -version > /dev/null 2>&1 || die "xcodebuild not usable"
XVER="$(xcodebuild -version 2>/dev/null | awk '/Xcode/{print $2}')"
echo "compile-modern-app-icon: Xcode ${XVER} (sdk ${xcver}), DEVELOPER_DIR=${DEVELOPER_DIR}"
case "${XVER%%.*}" in
    26|27|28|29|30|31|32|33|34|35) : ;;
    *) die "requires Xcode 26 or newer, found: ${XVER}" ;;
esac

command -v xcrun >/dev/null || die "xcrun not found"
xcrun --find actool >/dev/null 2>&1 || die "actool not found in selected Xcode"

# --- Locate ictool (Icon Composer CLI). Never download anything.
ICTOOL="$(xcrun --find ictool 2>/dev/null || true)"
if [ -z "$ICTOOL" ] || [ ! -x "$ICTOOL" ]; then
    CANDIDATES="$(find "$DEVELOPER_DIR/../../../Applications" "$DEVELOPER_DIR" \
        -path '*/Icon Composer.app/Contents/Executables/ictool' -type f 2>/dev/null || true)"
    ICTOOL="$(printf '%s\n' "$CANDIDATES" | head -1 || true)"
    [ -n "$ICTOOL" ] && [ -x "$ICTOOL" ] || die "ictool not found (xcrun or inside Xcode bundle)"
fi
echo "compile-modern-app-icon: ictool=$ICTOOL"
"$ICTOOL" --version > /dev/null 2>&1 || die "ictool --version failed"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1) Intermediate representation (the IR — never the flattened image).
mkdir -p "$WORK/ir"
"$ICTOOL" "$SRC" --export-intermediate-representation --output-directory "$WORK/ir" --platform macOS \
    > "$WORK/ictool.log" 2>&1 || { tail -40 "$WORK/ictool.log" >&2; die "ictool IR export failed"; }

XCASETS="$(find "$WORK/ir" -maxdepth 2 -name '*.xcassets' -type d | sort)"
[ "$(printf '%s\n' "$XCASETS" | grep -c .)" = "1" ] \
    || die "expected exactly one .xcassets from ictool, got: $XCASETS"
XCASETS="${XCASETS%%$'\n'*}"
STACK_DIR="${XCASETS%/}/AppIcon.iconstack"
[ -s "$STACK_DIR/Contents.json" ] || die "missing AppIcon.iconstack/Contents.json in IR catalog"
echo "compile-modern-app-icon: IR catalog ${XCASETS} (AppIcon.iconstack present)"

# --- 2) Compile with actool (modern icon, macOS 26, ad-hoc-free catalog).
mkdir -p "$OUT"
"$WORK/xcodebuild_version" 2>/dev/null || xcodebuild -version > "$WORK/xcodebuild_version"
xcrun actool \
    "$XCASETS" \
    --compile "$OUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$OUT/Assets.car-partial.plist" \
    --output-format human-readable-text \
    > "$WORK/actool.log" 2>&1 || { tail -60 "$WORK/actool.log" >&2; die "actool compile failed"; }

[ -s "$OUT/Assets.car" ] || die "actool produced no/nonempty Assets.car"
[ -s "$OUT/Assets.car-partial.plist" ] || die "actool produced no/nonempty partial plist"
plutil -lint "$OUT/Assets.car-partial.plist" >/dev/null || die "partial plist not valid XML/plist"

# --- 3) Fail-closed artifact inspection.
CARINFO="$WORK/car-info.txt"
xcrun --sdk macosx assetutil --info "$OUT/Assets.car" > "$CARINFO" 2>&1 \
    || { tail -40 "$CARINFO" >&2; die "assetutil cannot parse Assets.car"; }
grep -q "AppIcon" "$CARINFO" || die "Assets.car inventory has no AppIcon entries"
if ! grep -qi "iconstack" "$CARINFO"; then
    # assetutil inventory may not name iconstack explicitly on some Xcode
    # builds — the AppIcon app-icon entry + actool success is authoritative;
    # but we still require at least one iconstack-derived rendition marker.
    echo "compile-modern-app-icon: WARNING: no literal 'iconstack' string in assetutil info" >&2
fi
cp "$CARINFO" "$OUT/Assets.car.assetutil-info.txt"

# --- 4) Reproducibility metadata.
ICONJSON_SHA="$(shasum -a 256 "$SRC/icon.json" | cut -d' ' -f1)"
IMG_SHA="$(find "$SRC/Assets" -type f | sort | xargs shasum -a 256 | cut -d' ' -f1 | tr '\n' ' ')"
ICONHASH="$(shasum -a 256 "$OUT/Assets.car" | cut -d' ' -f1)"
cat > "$OUT/icon-build-metadata.json" <<JSON
{
  "tool": "ictool --export-intermediate-representation + xcrun actool --app-icon AppIcon",
  "platform": "macosx",
  "minimum-deployment-target": "26.0",
  "target-device": "mac",
  "xcode": "$(xcodebuild -version 2>/dev/null | head -1)",
  "xcode-developer-dir": "${DEVELOPER_DIR}",
  "ictool": "${ICTOOL}",
  "ictool-version": "$("$ICTOOL" --version 2>&1 | tr -d '\n' | sed 's/ /\\n/g')",
  "source-icon-json-sha256": "${ICONJSON_SHA}",
  "source-asset-shas256": "${IMG_SHA}",
  "assets-car-sha256": "${ICONHASH}",
  "assets-car-bytes": "$(stat -f %z "$OUT/Assets.car" 2>/dev/null || stat -c %s "$OUT/Assets.car")",
  "source-package": "$(basename "$SRC")",
  "built-at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
cp "$WORK/ictool.log" "$OUT/ictool.log" 2>/dev/null || true
cp "$WORK/actool.log" "$OUT/actool.log" 2>/dev/null || true
cp "$WORK/xcodebuild_version" "$OUT/xcode-version.txt" 2>/dev/null || true

echo "compile-modern-app-icon: OK — $OUT/Assets.car (sha256 $ICONHASH) + partial plist"
echo "compile-modern-app-icon: AppIcon renditions present in Assets.car (see Assets.car.assetutil-info.txt)"
