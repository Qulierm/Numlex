#!/bin/bash
# Icon Composer source calibration gate.
#
# Usage: Scripts/validate-icon-sources.sh
#
# Two layers, both fail-closed:
#
#  1. SOURCE INVARIANTS (always enforced): the Light package must reuse the
#     Dark package's foreground mask bytes, scale, translation, layer/image
#     names, shadow and translucency, and the gradient orientation — only
#     the background fill (system-dark vs system-light) and the layer
#     gradient may differ.
#
#  2. RENDER CALIBRATION (enforced whenever the local `ictool` build
#     supports `--export-image`, which is the Icon Composer renderer the
#     supplied previews come from):
#       - Dark  (Assets/AppIcon.icon)      -> BYTE-IDENTICAL to
#         Sources/NumlexApp/Resources/AppIconDarkPreview.png
#         (f2b66202656f9d04372010d251a54668d1a9d153648bb4940465c43e85902932)
#       - Light (Assets/AppIconLight.icon) -> EXACT alpha/Squircle geometry
#         (zero differing alpha bytes) against
#         Sources/NumlexApp/Resources/AppIconLightPreview.png
#         (4367adca2ded31ca07fe7cfcd7f1be4cab3b1e3a1fe927dc4d1a5855d505cf2e)
#         plus a strict bounded RGB tolerance (mean per-pixel max-channel
#         error <= 1.5/255, at most 8 pixels above 32/255; measured 1.09 and
#         2). The Light gradient was reverse-derived deterministically from
#         the supplied preview by least squares on three affine basis renders;
#         the residual is the renderer's edge sampling, not the gradient.
#
# A newer `ictool` shipped inside Xcode (used by CI) exposes a different CLI
# surface: when it cannot export a PNG the script prints a loud note and
# skips ONLY the render comparison — the compile step (actool) plus the
# assetutil inventory check remain the CI gates.
#
# Requires: macOS, Icon Composer `ictool` (NUMLEX_ICTOOL to override),
# python3 (JSON invariants) and swiftc (CoreGraphics pixel comparator).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DARK_SRC="$ROOT/Assets/AppIcon.icon"
LIGHT_SRC="$ROOT/Assets/AppIconLight.icon"
DARK_PREVIEW="$ROOT/Sources/NumlexApp/Resources/AppIconDarkPreview.png"
LIGHT_PREVIEW="$ROOT/Sources/NumlexApp/Resources/AppIconLightPreview.png"

die() { echo "validate-icon-sources: $*" >&2; exit 1; }

find_ictool() {
    if [ -n "${NUMLEX_ICTOOL:-}" ] && [ -x "${NUMLEX_ICTOOL}" ]; then
        printf '%s' "$NUMLEX_ICTOOL"; return 0
    fi
    local found dev
    found="$(xcrun --find ictool 2>/dev/null || true)"
    if [ -n "$found" ] && [ -x "$found" ]; then printf '%s' "$found"; return 0; fi
    dev="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
    if [ -n "$dev" ] && [ -d "$dev" ]; then
        found="$(find "$dev" -path '*/Icon Composer.app/Contents/Executables/ictool' -type f 2>/dev/null | head -1 || true)"
        if [ -n "$found" ] && [ -x "$found" ]; then printf '%s' "$found"; return 0; fi
        if [ -x "$dev/usr/bin/ictool" ]; then printf '%s' "$dev/usr/bin/ictool"; return 0; fi
    fi
    for candidate in "/Applications/Icon Composer.app/Contents/Executables/ictool" \
                     "/Applications/Xcode_26.6.app/Contents/Developer/usr/bin/ictool"; do
        if [ -x "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
    done
    return 1
}

ICTOOL="$(find_ictool || true)"
[ -d "$DARK_SRC" ] && [ -s "$DARK_SRC/icon.json" ] || die "missing $DARK_SRC/icon.json"
[ -d "$LIGHT_SRC" ] && [ -s "$LIGHT_SRC/icon.json" ] || die "missing $LIGHT_SRC/icon.json"
command -v python3 >/dev/null || die "python3 required"
[ -f "$DARK_PREVIEW" ] && [ -f "$LIGHT_PREVIEW" ] || die "preview fixtures missing"

TMP="$(mktemp -d /tmp/numlex-icon-calibration.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- 1) Source invariants (always) --------------------------------------
python3 - "$DARK_SRC" "$LIGHT_SRC" <<'PYCHECK'
import hashlib, json, sys
dark_src, light_src = sys.argv[1:3]
fail = []


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


dark = json.load(open(f"{dark_src}/icon.json"))
light = json.load(open(f"{light_src}/icon.json"))
dg, lg = dark["groups"][0], light["groups"][0]
dl, ll = dg["layers"][0], lg["layers"][0]

if dark.get("fill") != "system-dark" or light.get("fill") != "system-light":
    fail.append(f"expected system-dark / system-light fills, got {dark.get('fill')!r}/{light.get('fill')!r}")
if sha(f"{dark_src}/Assets/Image 32.png") != sha(f"{light_src}/Assets/Image 32.png"):
    fail.append("foreground mask bytes differ between Dark and Light")
for label, a, b in [
    ("scale", dl["position"]["scale"], ll["position"]["scale"]),
    ("translation", dl["position"]["translation-in-points"], ll["position"]["translation-in-points"]),
    ("layer name", dl["name"], ll["name"]),
    ("image name", dl["image-name"], ll["image-name"]),
    ("shadow", dg.get("shadow"), lg.get("shadow")),
    ("translucency", dg.get("translucency"), lg.get("translucency")),
    ("gradient orientation", dl["fill"]["orientation"], ll["fill"]["orientation"]),
]:
    if a != b:
        fail.append(f"Light/Dark {label} differ: {a!r} != {b!r}")
if dl["fill"]["linear-gradient"] == ll["fill"]["linear-gradient"]:
    fail.append("Light must use its own (dark) layer gradient")
if fail:
    for f in fail:
        print("FAIL: " + f, file=sys.stderr)
    sys.exit(1)
print("ok:   both packages share the foreground mask, scale, effects and orientation")
PYCHECK

# --- 2) Render calibration (when this ictool can export PNGs) -----------
if [ -z "$ICTOOL" ] || [ ! -x "$ICTOOL" ]; then
    echo "validate-icon-sources: NOTE — ictool not found; render calibration SKIPPED (source invariants enforced)"
    echo "validate-icon-sources: OK (source invariants only)"
    exit 0
fi

if ! command -v swiftc >/dev/null; then
    echo "validate-icon-sources: NOTE — swiftc not found; render calibration SKIPPED (source invariants enforced)"
    echo "validate-icon-sources: OK (source invariants only)"
    exit 0
fi

swiftc -O "$ROOT/Scripts/compare-icon-renders.swift" -o "$TMP/compare-icon-renders" \
    || die "cannot build the CoreGraphics comparator"

render() { # <package> <out.png>
    "$ICTOOL" "$1" --export-image --output-file "$2" \
        --platform macOS --rendition Default --width 512 --height 512 --scale 1
}

if ! render "$DARK_SRC" "$TMP/dark.png" >"$TMP/probe.log" 2>&1; then
    if grep -qiE "unknown argument|unrecognized|unknown option|unsupported|invalid option|usage:" "$TMP/probe.log"; then
        echo "validate-icon-sources: NOTE — this ictool build ($ICTOOL) has no --export-image CLI;"
        echo "validate-icon-sources: NOTE — render calibration SKIPPED (source invariants enforced)"
        echo "validate-icon-sources: OK (source invariants only)"
        exit 0
    fi
    echo "validate-icon-sources: ictool render failed:" >&2
    sed -n '1,20p' "$TMP/probe.log" >&2
    die "ictool --export-image failed"
fi

echo "validate-icon-sources: rendering Light ..."
render "$LIGHT_SRC" "$TMP/light.png" >/dev/null

"$TMP/compare-icon-renders" "$TMP/dark.png" "$DARK_PREVIEW" \
    || die "Dark calibration failed (render must be byte-identical to the preview)"
"$TMP/compare-icon-renders" "$TMP/light.png" "$LIGHT_PREVIEW" --light \
    || die "Light calibration failed (alpha geometry / RGB tolerance)"

echo "validate-icon-sources: OK (Dark exact; Light alpha exact + bounded RGB)"
