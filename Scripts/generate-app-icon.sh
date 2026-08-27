#!/bin/bash
# Deterministic AppIcon.icns generator (macOS-native sips + iconutil).
#
# Usage: Scripts/generate-app-icon.sh [source-png]
#   source-png defaults to <repo>/Assets/AppIcon.png (the canonical,
#   user-provided 1024x1024 source; the bytes are used exactly as-is).
#
# Produces Sources/NumlexApp/Resources/AppIcon.icns with the full
# standard 10-slot iconset (16..1024 px), replacing the previous file
# atomically. Fails clearly when the source is missing, not exactly
# 1024x1024, or the required tools are unavailable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-${ROOT}/Assets/AppIcon.png}"
OUT_DIR="${ROOT}/Sources/NumlexApp/Resources"
OUT="${OUT_DIR}/AppIcon.icns"

die() { echo "generate-app-icon: $*" >&2; exit 1; }

for tool in sips iconutil; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found in PATH"
done

[ -f "$SOURCE" ] || die "icon source not found: $SOURCE"

# Exact dimension check (no crop, no padding — the source is used as-is).
dims="$(sips -g pixelWidth -g pixelHeight "$SOURCE" 2>/dev/null \
    | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w" "h}')"
[ "$dims" = "1024 1024" ] || die "source is not exactly 1024x1024 (got: '${dims:-unreadable}') — refusing to crop or pad"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="${WORK}/AppIcon.iconset"
mkdir -p "$ICONSET"

# Standard macOS iconset: name < pixel size, one file per slot.
SLOTS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)
for slot in "${SLOTS[@]}"; do
    name="${slot%%:*}"
    size="${slot##*:}"
    sips -z "$size" "$size" "$SOURCE" --out "${ICONSET}/${name}" >/dev/null \
        || die "sips failed for ${name}"
done

# Build the ICNS next to the destination (same filesystem), then move it
# over the tracked file in one atomic rename.
TMP_OUT="${WORK}/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$TMP_OUT" || die "iconutil failed to build the ICNS"
[ -s "$TMP_OUT" ] || die "iconutil produced an empty file"

mkdir -p "$OUT_DIR"
# Stage on the destination filesystem, then atomic rename.
STAGED="${OUT_DIR}/.AppIcon.icns.tmp.$$"
cp "$TMP_OUT" "$STAGED"
mv -f "$STAGED" "$OUT"

# Sanity: the final file must unpack back to all ten slots.
CHECK="${WORK}/check.iconset"
mkdir -p "$CHECK"
iconutil -c iconset "$OUT" -o "$CHECK" || die "produced ICNS cannot be unpacked"
count="$(find "$CHECK" -name '*.png' | wc -l | tr -d ' ')"
[ "$count" = "10" ] || die "unpacked ICNS has $count slots, expected 10"

echo "generate-app-icon: wrote $OUT from $SOURCE"
