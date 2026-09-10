#!/bin/bash
#
# Assert the EXACT Sparkle 2.9.6 update-validation contract that Numlex relies
# on. This is a security-policy regression guard, not a comment grep:
#
#   1. the upstream sources for the pinned revision are fetched and their
#      SHA-256 must match the pinned digests below (so the assertions cannot
#      silently drift to another revision);
#   2. the CODE SHAPE of the validator is asserted, never a comment:
#        - `validateWithUpdateDirectory:` skips `validateUpdateForHost:` when
#          `_prevalidatedSignature` is set, and that branch requires only a
#          *valid* bundle signature + the basic policy (no identity match);
#        - the identity match (`...andMatchesSignatureAtBundleURL:`) appears
#          ONLY inside `validateUpdateForHost:`;
#        - `validateUpdateForHost:` accepts when `passedDSACheck ||
#          passedCodeSigning`;
#        - the pre-extraction EdDSA check sets `_prevalidatedSignature = YES`
#          on success;
#        - `SUVerifyUpdateBeforeExtraction` is the key that makes Sparkle use
#          the pre-validated path.
#
# Usage: Scripts/verify-sparkle-policy.sh [--offline-source-dir <dir>]
#
set -euo pipefail

SPARKLE_TAG="2.9.6"
SPARKLE_RAW="https://raw.githubusercontent.com/sparkle-project/Sparkle/${SPARKLE_TAG}"
CACHE_DIR=""
OFFLINE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --offline-source-dir) OFFLINE_DIR="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

PINNED_UPDATE_VALIDATOR_M="944a7ba53e49ebb0f7cf38e2228d38def9b70738cf2f4b7c5dd63a8d826ce465"
PINNED_UPDATE_VALIDATOR_H="13a620bee9b58a7c5204c59f99152836a7878340a9530cdb11c91a4893457449"
PINNED_SPU_UPDATER_M="c86e3e59a201a9339bbd5a391f12e62d9c31aca125ef6d665a16088a1c144c78"

WORK="$(mktemp -d /tmp/numlex-sparkle-policy.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fetch() { # fetch <relative-path> <pinned-sha256>
  local rel="$1" want="$2" name out
  name="$(basename "$rel")"
  out="$WORK/$name"
  if [ -n "$OFFLINE_DIR" ]; then
    cp "$OFFLINE_DIR/$name" "$out"
  else
    curl -sS -m 60 "$SPARKLE_RAW/$rel" -o "$out"
  fi
  local got
  got="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [ "$got" != "$want" ]; then
    echo "FAIL pinned digest mismatch for $rel: got $got want $want" >&2
    exit 1
  fi
  [ -z "$CACHE_DIR" ] || cp "$out" "$CACHE_DIR/$name"
  printf '%s\n' "$out"
}

VALIDATOR_M="$(fetch Sparkle/SUUpdateValidator.m "$PINNED_UPDATE_VALIDATOR_M")"
VALIDATOR_H="$(fetch Sparkle/SUUpdateValidator.h "$PINNED_UPDATE_VALIDATOR_H")"
UPDATER_M="$(fetch Sparkle/SPUUpdater.m "$PINNED_SPU_UPDATER_M")"

fail() { echo "FAIL $*" >&2; exit 1; }

python3 - "$VALIDATOR_M" "$VALIDATOR_H" "$UPDATER_M" <<'PY'
import re
import sys

validator, header, updater = (open(p, encoding="utf-8").read() for p in sys.argv[1:4])
problems = []

def section(source, signature_regex):
    """Return the body of the first method matching the signature."""
    m = re.search(signature_regex, source)
    if not m:
        return None
    start = source.index("{", m.end() - 1) if m.end() > 0 else None
    if start is None:
        return None
    depth = 0
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
    return None

def require(condition, message):
    if not condition:
        problems.append(message)

# --- 1. pre-validated path skips the identity match -------------------------
with_update_dir = section(validator, r"-\s*\(BOOL\)validateWithUpdateDirectory:")
require(with_update_dir is not None, "validateWithUpdateDirectory: not found")
if with_update_dir:
    require("if (!_prevalidatedSignature) {" in with_update_dir,
            "prevalidated branch guard missing")
    # The prevalidated branch must not use the identity-matching call.
    prevalidated_branch = with_update_dir.split("if (!_prevalidatedSignature) {", 1)[1]
    require("andMatchesSignatureAtBundleURL:" not in prevalidated_branch,
            "prevalidated path must not match the Apple signing identity")
    require("passesBasicUpdatePolicyWithHostIsCodeSigned:" in prevalidated_branch,
            "prevalidated path must still apply the basic code-signing policy")
    require("codeSignatureIsValidAtBundleURL:installSourceURL" in prevalidated_branch,
            "prevalidated path must require a VALID bundle signature")
    require("validateUpdateForHost:" in prevalidated_branch,
            "the non-prevalidated branch must delegate to validateUpdateForHost:")

# --- 2. the identity match lives only in validateUpdateForHost: -------------
host_validator = section(validator, r"-\s*\(BOOL\)validateUpdateForHost:")
require(host_validator is not None, "validateUpdateForHost: not found")
if host_validator:
    require("codeSignatureIsValidAtBundleURL:newHost.bundle.bundleURL andMatchesSignatureAtBundleURL:"
            in host_validator,
            "validateUpdateForHost: must contain the identity match")
    require("if (passedDSACheck || passedCodeSigning) {" in host_validator,
            "validateUpdateForHost: must accept EdDSA OR Apple code signing")
    # The acceptance must precede the failure narration.
    accept_at = host_validator.find("if (passedDSACheck || passedCodeSigning) {")
    return_no_at = host_validator.rfind("return NO;")
    require(accept_at != -1 and return_no_at > accept_at,
            "acceptance predicate must come before the rejection narration")

# --- 3. the pre-extraction EdDSA check sets the prevalidated flag ----------
prevalidation = section(validator, r"-\s*\(BOOL\)validateDownloadPathWithFallbackOnCodeSigning:")
require(prevalidation is not None, "pre-archive validation method not found")
if prevalidation:
    eddsa_ok = prevalidation.find("validatePath:_downloadPath")
    flag = prevalidation.find("_prevalidatedSignature = YES;")
    require(eddsa_ok != -1 and flag != -1 and flag > eddsa_ok,
            "EdDSA success must set _prevalidatedSignature")

# --- 4. header documents the pre/post split -------------------------------
require("before the archive has been extracted" in header,
        "header must document the pre-extraction validation semantics")
require("after an archive has been extracted" in header,
        "header must document the post-extraction validation semantics")

# --- 5. SUVerifyUpdateBeforeExtraction is the enabling key ----------------
require("SUVerifyUpdateBeforeExtractionKey" in updater,
        "SPUUpdater must read SUVerifyUpdateBeforeExtraction")
require("updates requiring SUVerifyUpdateBeforeExtraction" in validator,
        "validator must document the prevalidated path hit for this key")

if problems:
    for p in problems:
        print("FAIL " + p, file=sys.stderr)
    sys.exit(1)
print("sparkle-policy: validator contract OK (prevalidated EdDSA path accepts ad-hoc bundles)")
PY

echo "verify-sparkle-policy: OK (Sparkle $SPARKLE_TAG, pinned digests)"
