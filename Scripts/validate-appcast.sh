#!/bin/bash
#
# Validate a Sparkle appcast against the Numlex update contract.
#
# Usage:
#   Scripts/validate-appcast.sh <appcast.xml> [--archive <path>]
#                               [--public-key <base64>|--public-key-file <path>]
#                               [--expect-version <version>]
#                               [--expect-url <exact-enclosure-url>]
#                               [--expect-length <bytes>]
#                               [--expect-min-os <version>]
#
# Checks (fail closed):
#   - well-formed XML with exactly one <item>;
#   - sparkle:version is a numeric dotted version and (optionally) the expected one;
#   - enclosure URL is HTTPS, version-pinned and (optionally) the exact URL;
#   - enclosure length is a positive integer and (optionally) the exact size;
#   - sparkle:edSignature is base64 of exactly 64 bytes (Ed25519);
#   - sparkle:minimumSystemVersion is present and (optionally) the expected one;
#   - when --archive is given: the archive size matches, and the signature
#     cryptographically verifies against the public key (CryptoKit Ed25519).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST=""
ARCHIVE=""
PUBLIC_KEY=""
PUBLIC_KEY_FILE="$ROOT/Sources/NumlexApp/Resources/Info.plist"   # source of truth by default
EXPECT_VERSION=""
EXPECT_URL=""
EXPECT_LENGTH=""
EXPECT_MIN_OS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --public-key) PUBLIC_KEY="$2"; shift 2 ;;
    --public-key-file) PUBLIC_KEY_FILE="$2"; shift 2 ;;
    --expect-version) EXPECT_VERSION="$2"; shift 2 ;;
    --expect-url) EXPECT_URL="$2"; shift 2 ;;
    --expect-length) EXPECT_LENGTH="$2"; shift 2 ;;
    --expect-min-os) EXPECT_MIN_OS="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) APPCAST="$1"; shift ;;
  esac
done

if [ -z "$APPCAST" ] || [ ! -f "$APPCAST" ]; then
  echo "usage: Scripts/validate-appcast.sh <appcast.xml> [options]" >&2
  exit 2
fi

if [ -z "$PUBLIC_KEY" ]; then
  if [ ! -f "$PUBLIC_KEY_FILE" ]; then
    echo "public key file not found: $PUBLIC_KEY_FILE" >&2
    exit 2
  fi
  PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PUBLIC_KEY_FILE")"
fi

FIELDS="$(python3 - "$APPCAST" <<'PY'
import sys, re, base64
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    tree = ET.parse(path)
except ET.ParseError as e:
    print("ERROR malformed XML: %s" % e); sys.exit(1)

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    print("ERROR no <channel>"); sys.exit(1)
items = channel.findall("item")
if len(items) != 1:
    print("ERROR expected exactly one <item>, found %d" % len(items)); sys.exit(1)
item = items[0]

def text(tag, ns=False):
    el = item.find(SPARKLE + tag if ns else tag)
    return (el.text or "").strip() if el is not None else ""

version = text("version", ns=True)
enclosure = item.find("enclosure")
if enclosure is None:
    print("ERROR no <enclosure>"); sys.exit(1)
url = (enclosure.get("url") or "").strip()
length = (enclosure.get("length") or "").strip()
sig = (enclosure.get(SPARKLE + "edSignature") or "").strip()
min_os = text("minimumSystemVersion", ns=True)

problems = []
if not re.match(r"^\d+(\.\d+)*$", version):
    problems.append("sparkle:version %r is not a numeric dotted version" % version)
if not url.startswith("https://"):
    problems.append("enclosure URL is not HTTPS: %r" % url)
if "latest" in url.lower():
    problems.append("enclosure URL looks mutable (contains 'latest')")
if not re.match(r"^\d+$", length) or int(length) <= 0:
    problems.append("enclosure length %r is not a positive integer" % length)
try:
    sig_bytes = base64.b64decode(sig, validate=True)
    if len(sig_bytes) != 64:
        problems.append("edSignature is %d bytes, expected 64" % len(sig_bytes))
except Exception:
    problems.append("edSignature is not valid base64")
if not re.match(r"^\d+(\.\d+)*$", min_os):
    problems.append("sparkle:minimumSystemVersion %r is missing/invalid" % min_os)

if problems:
    for p in problems:
        print("ERROR " + p)
    sys.exit(1)

print("version=%s" % version)
print("url=%s" % url)
print("length=%s" % length)
print("signature=%s" % sig)
print("min_os=%s" % min_os)
PY
)"

JS_ERROR=0
if echo "$FIELDS" | grep -q '^ERROR'; then
  echo "$FIELDS" >&2
  exit 1
fi
VERSION="$(echo "$FIELDS" | sed -n 's/^version=//p')"
URL="$(echo "$FIELDS" | sed -n 's/^url=//p')"
LENGTH="$(echo "$FIELDS" | sed -n 's/^length=//p')"
SIGNATURE="$(echo "$FIELDS" | sed -n 's/^signature=//p')"
MIN_OS="$(echo "$FIELDS" | sed -n 's/^min_os=//p')"

if [ -n "$EXPECT_VERSION" ] && [ "$VERSION" != "$EXPECT_VERSION" ]; then
  echo "version mismatch: appcast=$VERSION expected=$EXPECT_VERSION" >&2; JS_ERROR=1
fi
if [ -n "$EXPECT_URL" ] && [ "$URL" != "$EXPECT_URL" ]; then
  echo "enclosure URL mismatch: appcast=$URL expected=$EXPECT_URL" >&2; JS_ERROR=1
fi
if [ -n "$EXPECT_LENGTH" ] && [ "$LENGTH" != "$EXPECT_LENGTH" ]; then
  echo "length mismatch: appcast=$LENGTH expected=$EXPECT_LENGTH" >&2; JS_ERROR=1
fi
if [ -n "$EXPECT_MIN_OS" ] && [ "$MIN_OS" != "$EXPECT_MIN_OS" ]; then
  echo "minimumSystemVersion mismatch: appcast=$MIN_OS expected=$EXPECT_MIN_OS" >&2; JS_ERROR=1
fi

if [ -n "$ARCHIVE" ]; then
  if [ ! -f "$ARCHIVE" ]; then
    echo "archive not found: $ARCHIVE" >&2; exit 1
  fi
  ACTUAL_SIZE="$(stat -f%z "$ARCHIVE")"
  if [ "$ACTUAL_SIZE" != "$LENGTH" ]; then
    echo "archive size $ACTUAL_SIZE != appcast length $LENGTH" >&2; JS_ERROR=1
  fi
  if ! swift "$ROOT/Scripts/verify-ed25519.swift" "$ARCHIVE" "$SIGNATURE" "$PUBLIC_KEY" >/dev/null; then
    echo "EdDSA signature verification failed for $ARCHIVE" >&2; JS_ERROR=1
  fi
fi

if [ "$JS_ERROR" != "0" ]; then
  exit 1
fi

echo "appcast OK: version=$VERSION length=$LENGTH minOS=$MIN_OS url=$URL"
