#!/bin/bash
#
# Reproducible Sparkle appcast generator for Numlex.
#
# Usage:
#   Scripts/prepare-update-feed.sh --dmg <path> --version <x.y.z>
#                                  --download-url-prefix <https://.../download/<version>/>
#                                  [--output <appcast.xml>]
#                                  [--release-notes <file.md|.html|.txt>]
#                                  [--key-file <private-key-file>]
#                                  [--min-os <version>]   (default 26.0)
#                                  [--bootstrap]  allow a pre-updater app bundle
#                                                 (no SUFeedURL inside the DMG)
#
# Contract (fails closed):
#   - pinned Sparkle 2.9.6 tools only (from the resolved SwiftPM artifact);
#   - DMG must exist, be a valid disk image, and contain Numlex.app whose
#     CFBundleVersion equals --version;
#   - the download URL must be HTTPS and version-pinned (no 'latest');
#   - a signing key must be available (login Keychain by default, or
#     --key-file for an offline key — never printed);
#   - no delta updates are produced;
#   - the output is validated (XML, version, URL, length, EdDSA signature
#     verified cryptographically against the committed public key) and then
#     written atomically.
#
# The immutable-asset rule: an appcast may only ever point at an uploaded,
# version-pinned asset. Never re-upload or replace a published asset to "fix"
# a feed — publish a new version instead.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG=""
VERSION=""
URL_PREFIX=""
OUTPUT=""
RELEASE_NOTES=""
KEY_FILE=""
MIN_OS="26.0"
BOOTSTRAP="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --download-url-prefix) URL_PREFIX="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --release-notes) RELEASE_NOTES="$2"; shift 2 ;;
    --key-file) KEY_FILE="$2"; shift 2 ;;
    --min-os) MIN_OS="$2"; shift 2 ;;
    --bootstrap) BOOTSTRAP="1"; shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) echo "unexpected argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "prepare-update-feed: $*" >&2; exit 1; }

[ -n "$DMG" ] || die "--dmg is required"
[ -n "$VERSION" ] || die "--version is required"
[ -n "$URL_PREFIX" ] || die "--download-url-prefix is required"
[ -f "$DMG" ] || die "DMG not found: $DMG"
echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || die "--version must be numeric (e.g. 4.8.0)"
case "$URL_PREFIX" in https://*) ;; *) die "--download-url-prefix must be HTTPS" ;; esac
case "$(echo "$URL_PREFIX" | tr 'A-Z' 'a-z')" in *latest*) die "URL prefix looks mutable (contains latest)" ;; esac
case "$URL_PREFIX" in *"/download/$VERSION/"*|*"/download/$VERSION") ;; *) die "URL prefix must be version-pinned (/download/$VERSION/)";; esac

# --- pinned Sparkle tools -----------------------------------------------------
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
[ -x "$GENERATE_APPCAST" ] || die "missing pinned generate_appcast (run 'swift package resolve')"
[ -x "$SIGN_UPDATE" ] || die "missing pinned sign_update (run 'swift package resolve')"
PINNED_VERSION="$(plutil -extract pins.0.state.version raw -o - "$ROOT/Package.resolved")"
[ "$PINNED_VERSION" = "2.9.6" ] || die "Package.resolved pins Sparkle $PINNED_VERSION, expected 2.9.6"

# --- key availability (never printed) ----------------------------------------
KEY_ARGS=()
if [ -n "$KEY_FILE" ]; then
  [ -f "$KEY_FILE" ] || die "key file not found: $KEY_FILE"
  KEY_ARGS=(--ed-key-file "$KEY_FILE")
else
  "$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1 || die "no EdDSA signing key in the login Keychain (run generate_keys once)"
fi

# --- DMG validation (read-only mount) ----------------------------------------
hdiutil imageinfo "$DMG" >/dev/null 2>&1 || die "not a valid disk image: $DMG"
DMG_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

MOUNT_DIR="$(mktemp -d /tmp/numlex-appcast-mount.XXXXXX)"
cleanup() { hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 2>&1 || true; rm -rf "$MOUNT_DIR"; }
trap cleanup EXIT
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG" >/dev/null 2>&1 || die "cannot mount DMG"
APP_PATH="$(find "$MOUNT_DIR" -maxdepth 2 -name "Numlex.app" -type d | head -1)"
[ -n "$APP_PATH" ] || die "Numlex.app not found inside the DMG"
DMG_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[ "$DMG_VERSION" = "$VERSION" ] || die "DMG app CFBundleVersion '$DMG_VERSION' != --version '$VERSION'"
DMG_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [ "$BOOTSTRAP" = "1" ]; then
  # Bootstrap only: the immutable 4.7.0 build predates the updater and has no
  # SUFeedURL. Any DMG that DOES declare a feed must still declare ours.
  if [ -n "$DMG_FEED" ] && [ "$DMG_FEED" != "https://numlex.tech/appcast.xml" ]; then
    die "DMG app SUFeedURL '$DMG_FEED' is not the canonical feed"
  fi
else
  [ "$DMG_FEED" = "https://numlex.tech/appcast.xml" ] || die "DMG app SUFeedURL '$DMG_FEED' is not the canonical feed"
fi
DMG_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[ "$DMG_MIN_OS" = "$MIN_OS" ] || die "DMG LSMinimumSystemVersion '$DMG_MIN_OS' != --min-os '$MIN_OS'"
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1

# --- generate the appcast in a scratch dir -----------------------------------
WORK_DIR="$(mktemp -d /tmp/numlex-appcast-work.XXXXXX)"
trap 'cleanup; rm -rf "$WORK_DIR"' EXIT
DMG_NAME="$(basename "$DMG")"
cp "$DMG" "$WORK_DIR/$DMG_NAME"
GEN_ARGS=(--download-url-prefix "$URL_PREFIX" --maximum-deltas 0 --maximum-versions 1
          --link "https://numlex.tech/" --disable-signing-warning)
if [ -n "$RELEASE_NOTES" ]; then
  [ -f "$RELEASE_NOTES" ] || die "release notes not found: $RELEASE_NOTES"
  NOTES_NAME="$(basename "${DMG_NAME%.*}").${RELEASE_NOTES##*.}"
  cp "$RELEASE_NOTES" "$WORK_DIR/$NOTES_NAME"
fi
"$GENERATE_APPCAST" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "${GEN_ARGS[@]}" "$WORK_DIR" >/dev/null 2>&1 || die "generate_appcast failed"
GENERATED="$WORK_DIR/appcast.xml"
[ -f "$GENERATED" ] || die "generate_appcast produced no appcast.xml"

# Sign the archive EXPLICITLY with sign_update (Ed25519, login Keychain by
# default). generate_appcast's own Keychain lookup can silently skip signing,
# so the signature is asserted here and injected into the enclosure — a feed
# without a verified signature must never ship.
SIGNATURE_OUTPUT="$("$SIGN_UPDATE" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "$WORK_DIR/$DMG_NAME")" \
  || die "sign_update failed (no usable EdDSA key?)"
SIGNATURE="$(echo "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
SIGNED_LENGTH="$(echo "$SIGNATURE_OUTPUT" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
[ -n "$SIGNATURE" ] || die "sign_update produced no sparkle:edSignature"
[ "$SIGNED_LENGTH" = "$(stat -f%z "$WORK_DIR/$DMG_NAME")" ] || die "sign_update length mismatch"

python3 "$ROOT/Scripts/inject-appcast-signature.py" "$GENERATED" "$SIGNATURE"

EXPECTED_URL="${URL_PREFIX%/}/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$DMG_NAME")"
EXPECTED_LENGTH="$(stat -f%z "$DMG")"
# Validate against the SOURCE Info.plist public key and the exact contract.
"$ROOT/Scripts/validate-appcast.sh" "$GENERATED" \
  --archive "$WORK_DIR/$DMG_NAME" \
  --expect-version "$VERSION" \
  --expect-url "$EXPECTED_URL" \
  --expect-length "$EXPECTED_LENGTH" \
  --expect-min-os "$MIN_OS"

if [ -z "$OUTPUT" ]; then
  OUTPUT="$WORK_DIR/appcast.xml"
  cat "$OUTPUT"
else
  TMP_OUT="$OUTPUT.tmp.$$"
  cp "$GENERATED" "$TMP_OUT"
  mv -f "$TMP_OUT" "$OUTPUT"
fi

echo "feed OK: version=$VERSION bytes=$EXPECTED_LENGTH sha256=$DMG_SHA url=$EXPECTED_URL output=${OUTPUT}"
