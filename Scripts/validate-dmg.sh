#!/bin/bash
# Validate the PLAIN Numlex DMG contract.
#
# Usage: Scripts/validate-dmg.sh <dmg-path>
#
# Contract (fail closed):
#   - valid disk image (hdiutil verify) with volume "Numlex <version>";
#   - exactly two root items: Numlex.app and Applications -> /Applications;
#   - no style artifacts or metadata: no .background, no .DS_Store, no
#     .VolumeIcon.icns, no other hidden root entries;
#   - app: CFBundleShortVersionString == CFBundleVersion, bundle id
#     com.numlex.app, LSMinimumSystemVersion 26.0, arm64-only executable;
#   - strict ad-hoc signatures: the outer app and every nested Sparkle
#     binary (framework, Autoupdate, Updater.app, both XPC services);
#   - Sparkle 2.9.6 with the canonical HTTPS feed, EdDSA public key,
#     verify-before-extraction on and system profiling off;
#   - the five offline resource datasets inside Numlex_NumlexCore.bundle;
#   - packaged Assets.car equals the compiled catalog hash.
#
# No Finder, osascript, Pillow or layout coordinates: the plain contract is
# file-system and bundle facts only, so it works headless.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:?usage: validate-dmg.sh <dmg-path>}"
[ -f "$DMG" ] || { echo "FAIL: DMG not found: $DMG" >&2; exit 1; }

fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "ok:   $*"; }

MNT="$(mktemp -d /tmp/numlex-plain-validate.XXXXXX)"
detach() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap detach EXIT

hdiutil verify "$DMG" >/dev/null 2>&1 && ok "hdiutil verify clean" || bad "hdiutil verify failed"

hdiutil attach -nobrowse -noverify -readonly -mountpoint "$MNT" "$DMG" >/dev/null 2>&1 \
  || { bad "cannot mount $DMG"; echo "VALIDATION FAILED: $DMG"; exit 1; }
[ -d "$MNT" ] || { bad "mount point missing after attach"; echo "VALIDATION FAILED: $DMG"; exit 1; }

APP="$MNT/Numlex.app"

# --- root layout: exactly the app and the Applications shortcut -------------
entries="$(ls -A "$MNT" | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$entries" = "Applications Numlex.app" ]; then
  ok "root entries exactly: Numlex.app, Applications"
else
  bad "root entries must be exactly 'Applications Numlex.app' (got: '$entries')"
fi
if [ -L "$MNT/Applications" ] && [ "$(readlink "$MNT/Applications")" = "/Applications" ]; then
  ok "Applications -> /Applications"
else
  bad "Applications is not a symlink to /Applications"
fi

# --- no styled-DMG artifacts or layout metadata -----------------------------
style_artifacts=0
for artifact in .background .DS_Store .VolumeIcon.icns .Trashes .fseventsd; do
  if [ -e "$MNT/$artifact" ]; then
    bad "style/metadata artifact present: $artifact"
    style_artifacts=1
  fi
done
(( style_artifacts )) || ok "no .background/.DS_Store/.VolumeIcon.icns or other hidden root entries"

# --- app bundle -------------------------------------------------------------
if [ -d "$APP" ]; then
  ok "Numlex.app present"
else
  bad "Numlex.app missing"
  echo "VALIDATION FAILED: $DMG"
  exit 1
fi
VERSION_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
VERSION_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$VERSION_SHORT" ] || bad "CFBundleShortVersionString missing"
[ "$VERSION_SHORT" = "$VERSION_BUILD" ] && ok "versions match ($VERSION_SHORT)" || bad "CFBundleShortVersionString '$VERSION_SHORT' != CFBundleVersion '$VERSION_BUILD'"
[ "$BUNDLE_ID" = "com.numlex.app" ] && ok "bundle id com.numlex.app" || bad "bundle id '$BUNDLE_ID'"
[ "$MIN_OS" = "26.0" ] && ok "minimum macOS 26.0" || bad "LSMinimumSystemVersion '$MIN_OS' != 26.0"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Numlex" 2>/dev/null || true)"
[ "$ARCHS" = "arm64" ] && ok "executable arm64-only" || bad "executable archs '$ARCHS' != arm64"

VOLNAME="$(diskutil info "$MNT" 2>/dev/null | sed -n 's/^ *Volume Name: *//p')"
[ "$VOLNAME" = "Numlex $VERSION_SHORT" ] && ok "volume name 'Numlex $VERSION_SHORT'" || bad "volume name '$VOLNAME' != 'Numlex $VERSION_SHORT'"

# --- strict signatures (outer + every nested Sparkle binary) ----------------
for target in \
  "$APP" \
  "$APP/Contents/Frameworks/Sparkle.framework" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"; do
  if codesign --verify --strict "$target" >/dev/null 2>&1; then
    ok "signature valid: ${target#"$APP"/}"
  else
    bad "signature invalid: ${target#"$APP"/}"
  fi
done

# --- Sparkle metadata and version ------------------------------------------
SPARKLE_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Info.plist" 2>/dev/null || true)"
[ "$SPARKLE_VER" = "2.9.6" ] && ok "Sparkle 2.9.6" || bad "Sparkle version '$SPARKLE_VER' != 2.9.6"
FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$FEED" = "https://numlex.tech/appcast.xml" ] && ok "canonical HTTPS feed" || bad "SUFeedURL '$FEED'"
PUB="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
KEY_LEN="$(printf '%s' "$PUB" | base64 -D 2>/dev/null | wc -c | tr -d ' ')"
[ "$KEY_LEN" = "32" ] && ok "EdDSA public key (32 bytes)" || bad "SUPublicEDKey decoded length '$KEY_LEN'"
VERIFY="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$VERIFY" = "true" ] && ok "verify before extraction" || bad "SUVerifyUpdateBeforeExtraction '$VERIFY'"
PROFILING="$(/usr/libexec/PlistBuddy -c 'Print :SUEnableSystemProfiling' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$PROFILING" = "false" ] && ok "system profiling off" || bad "SUEnableSystemProfiling '$PROFILING'"

# --- offline resource datasets ---------------------------------------------
BUNDLE="$APP/Contents/Resources/Numlex_NumlexCore.bundle"
missing_resources=0
for required in \
  NumlexTimezones/iana-zones.tsv NumlexTimezones/cities.tsv NumlexTimezones/countries.tsv \
  NumlexTimezones/airports.tsv NumlexTimezones/country-names.tsv NumlexTimezones/sources.json \
  NumlexHolidays/holidays.tsv NumlexHolidays/sources.json \
  NumlexIncomeTax/income-tax.json NumlexIncomeTax/sources.json \
  NumlexCPI/cpi-u.json NumlexCPI/sources.json \
  NumlexTax/tax-presets.json NumlexTax/sources.json; do
  if [ ! -f "$BUNDLE/$required" ]; then
    bad "missing offline resource: $required"
    missing_resources=1
  fi
done
(( missing_resources )) || ok "five offline resource datasets present"

# --- packaged icon catalog --------------------------------------------------
CAR="$(shasum -a 256 "$APP/Contents/Resources/Assets.car" 2>/dev/null | cut -d' ' -f1 || true)"
[ "$CAR" = "be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d" ] \
  && ok "packaged Assets.car matches compiled catalog" \
  || bad "packaged Assets.car '$CAR' != be00c077…"

hdiutil detach "$MNT" -quiet 2>/dev/null && ok "detached cleanly" || bad "detach failed"
trap - EXIT
rmdir "$MNT" 2>/dev/null || true

echo
if (( fail )); then
  echo "VALIDATION FAILED: $DMG"
  exit 1
fi
echo "VALIDATION PASSED: $DMG"
