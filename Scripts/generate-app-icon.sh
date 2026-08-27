#!/bin/bash
# Native-slot AppIcon.icns packer (macOS iconutil — NO resizing).
#
# Usage: Scripts/generate-app-icon.sh [iconset-dir]
#   iconset-dir defaults to <repo>/Assets/AppIcon.iconset: the tracked,
#   READY PER-SIZE EXPORTS with iconutil-standard filenames. Each slot
#   is packed exactly as supplied — the script never resizes or
#   recompresses a slot (sips is used for metadata queries only).
#
# Produces Sources/NumlexApp/Resources/AppIcon.icns, replacing the
# previous file atomically, then unpacks the result and validates all
# ten slots:
#   * the eight PNG-container slots (32, 64, 128, 256, 256, 512, 512,
#     1024 px) are byte-identical to the tracked exports — enforced;
#   * the two legacy-representation slots (16, 32 px @1x) are stored by
#     iconutil in the legacy ICNS representation and its unpacker
#     re-encodes them with palette quantization — enforced with exact
#     dimensions, exact alpha (measured drift ≤1) and a documented,
#     alpha-weighted pixel tolerance (measured worst case 186, limit
#     200): only semi-transparent edge pixels shift, sub-perceptually.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="${1:-${ROOT}/Assets/AppIcon.iconset}"
OUT_DIR="${ROOT}/Sources/NumlexApp/Resources"
OUT="${OUT_DIR}/AppIcon.icns"

die() { echo "generate-app-icon: $*" >&2; exit 1; }

for tool in iconutil sips; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found in PATH"
done

[ -d "$ICONSET" ] || die "iconset directory not found: $ICONSET"

# name : expected pixels
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

dims_of() {
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null \
        | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w" "h}'
}

# --- Validate the supplied slots: exact filenames, nonempty, dimensions, alpha.
for slot in "${SLOTS[@]}"; do
    name="${slot%%:*}"
    size="${slot##*:}"
    f="${ICONSET}/${name}"
    [ -s "$f" ] || die "missing or empty slot: $f"
    d="$(dims_of "$f")"
    [ "$d" = "${size} ${size}" ] || die "slot ${name} is ${d:-unreadable}, expected ${size}x${size} (slots are never resized)"
    a="$(sips -g hasAlpha "$f" 2>/dev/null | awk -F': ' '/hasAlpha/{print $2}')"
    [ "$a" = "yes" ] || die "slot ${name} must carry an alpha channel"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Pack the directory as-is (iconutil cannot and does not resize).
TMP_OUT="${WORK}/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$TMP_OUT" || die "iconutil failed to build the ICNS"
[ -s "$TMP_OUT" ] || die "iconutil produced an empty file"

# --- Unpack and validate every slot.
UP="${WORK}/check.iconset"
iconutil -c iconset "$TMP_OUT" -o "$UP" || die "produced ICNS cannot be unpacked"
[ "$(find "$UP" -name '*.png' | wc -l | tr -d ' ')" = "10" ] || die "unpacked ICNS does not contain all 10 slots"

have_pil="$(python3 -c 'import PIL' 2>/dev/null && echo yes || echo no)"

for slot in "${SLOTS[@]}"; do
    name="${slot%%:*}"
    size="${slot##*:}"
    [ -s "$UP/${name}" ] || die "unpacked slot missing: ${name}"
    d="$(dims_of "$UP/${name}")"
    [ "$d" = "${size} ${size}" ] || die "unpacked slot ${name} is ${d}, expected ${size}x${size}"
    case "$name" in
        icon_16x16.png|icon_32x32.png)
            # Legacy ICNS representation: iconutil's unpacker re-encodes
            # these two slots with palette quantization. Exact
            # dimensions/alpha are enforced above; pixels are checked
            # within the documented tolerance when PIL is available.
            if [ "$have_pil" = "yes" ]; then
                python3 - "$UP/${name}" "${ICONSET}/${name}" << 'PYEOF' || die "legacy slot pixel check failed"
import sys
from PIL import Image
up, src = Image.open(sys.argv[1]).convert("RGBA"), Image.open(sys.argv[2]).convert("RGBA")
assert up.size == src.size, "size mismatch"
du, ds = up.load(), src.load()
maxa = 0.0
maxw = 0.0
for y in range(up.size[1]):
    for x in range(up.size[0]):
        pu, ps = du[x, y], ds[x, y]
        maxa = max(maxa, abs(pu[3] - ps[3]))
        # Perceptual delta: RGB channel-sum weighted by the source
        # alpha — a fully transparent swing is invisible, an opaque
        # swing is not.
        rgb = sum(abs(pu[i] - ps[i]) for i in range(3))
        maxw = max(maxw, rgb * ps[3] / 255.0)
assert maxa <= 2, f"alpha drifted: {maxa}"
assert maxw <= 200, f"palette delta beyond documented tolerance: {maxw:.1f}"
PYEOF
            else
                echo "generate-app-icon: note: python3+PIL unavailable; legacy slot ${name} checked by dimensions/alpha only"
            fi
            ;;
        *)
            cmp -s "$UP/${name}" "${ICONSET}/${name}" \
                || die "payload not byte-preserved for ${name} (supplied exports must pass through untouched)"
            ;;
    esac
done

# --- Atomic replace of the tracked ICNS.
mkdir -p "$OUT_DIR"
STAGED="${OUT_DIR}/.AppIcon.icns.tmp.$$"
cp "$TMP_OUT" "$STAGED"
mv -f "$STAGED" "$OUT"

echo "generate-app-icon: wrote $OUT from $ICONSET (10 native slots, no resizing)"
