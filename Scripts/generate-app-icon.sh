#!/bin/bash
# Supplied-ICNS validator/copier — the ONLY sanctioned icon pipeline step.
#
# Usage: Scripts/generate-app-icon.sh [source-icns]
#   source-icns defaults to <repo>/Assets/AppIcon.icns: the user-supplied
#   canonical icon file (tracked byte-exact). An explicit alternate source
#   must be an .icns file; it is validated the same way before install.
#
# Behavior (deliberately narrow):
#   1. validates the source with `iconutil -c iconset` (must unpack);
#   2. verifies usable native reps exist for at least 32, 256 and 512 px;
#   3. atomically copies the file BYTE-FOR-BYTE to
#      Sources/NumlexApp/Resources/AppIcon.icns.
#
# The script NEVER constructs from Assets/AppIcon.iconset, resizes,
# recolors, strips rims, injects profiles, repacks, or synthesizes
# missing representations. Byte preservation IS the invariant
# (source SHA-256 must equal installed SHA-256).
#
# Provenance (see Assets/README.md):
#   * Assets/AppIcon.icns: canonical user-supplied file, tracked
#     byte-exact (SHA-256 b2bc96a9a52544611e997ec6176dd7a7ac981bc259f1b53104e4767e59a6a4b4),
#     native reps 32/256/512 px.
#   * Assets/AppIcon.iconset + AppIcon.exported.iconset: LEGACY reference
#     only (previous PNG-slot pipeline); not read by this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${ROOT}/Assets/AppIcon.icns}"
OUT_DIR="${ROOT}/Sources/NumlexApp/Resources"
OUT="${OUT_DIR}/AppIcon.icns"

die() { echo "generate-app-icon: $*" >&2; exit 1; }

command -v iconutil >/dev/null 2>&1 || die "required tool 'iconutil' not found in PATH"

[[ "$SRC" == *.icns ]] || die "accepted input is an ICNS file, got: $SRC"
[ -s "$SRC" ] || die "source ICNS missing or empty: $SRC"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1) iconutil must unpack the source.
iconutil -c iconset "$SRC" -o "$WORK/check.iconset" || die "source ICNS cannot be unpacked by iconutil: $SRC"

# --- 2) required usable reps: at least 32, 256, 512 px.
dims_of() {
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null \
        | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w" "h}'
}
have32=0; have256=0; have512=0
for f in "$WORK"/check.iconset/*.png; do
    [ -f "$f" ] || continue
    case "$(dims_of "$f")" in
        "32 32") have32=1 ;;
        "256 256") have256=1 ;;
        "512 512") have512=1 ;;
    esac
done
(( have32 )) || die "source ICNS lacks a usable 32px rep"
(( have256 )) || die "source ICNS lacks a usable 256px rep"
(( have512 )) || die "source ICNS lacks a usable 512px rep"

# --- 3) atomic byte-for-byte install.
mkdir -p "$OUT_DIR"
STAGED="${OUT_DIR}/.AppIcon.icns.tmp.$$"
cp "$SRC" "$STAGED"
mv -f "$STAGED" "$OUT"

# --- 4) byte-preservation proof.
[ "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" = "$(shasum -a 256 "$OUT" | cut -d' ' -f1)" ] \
    || die "installed ICNS hash differs from source (byte preservation violated)"
cmp -s "$SRC" "$OUT" || die "installed ICNS not byte-identical to source"

echo "generate-app-icon: installed $OUT byte-exact from $SRC (reps 32/256/512 verified)"
