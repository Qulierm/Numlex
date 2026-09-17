#!/bin/bash
# Deterministic RELOCATED packaged-app smoke (the 4.9.2 crash guard).
#
# Copies the assembled app OUTSIDE the repository (to a temp directory),
# so no developer .build layout can satisfy the resource lookup, then
# launches the COPIED binary with the opt-in --validate-packaged-resources
# flag. That flag (inert in normal launches — no window, store, updater
# or appearance work) makes the process prove, through the production
# ResourceLocator + embedded() catalog path, that:
#   - the offline bundle resolves from the copy's OWN Contents/Resources;
#   - all five offline catalogs load with their integrity checks.
# and then exit 0. Any SIGTRAP / nonzero exit fails this script.
#
# The developer .build location can never be consulted: the production
# locator contains no build-path literal (enforced by a test source
# contract), and this script also runs the binary from a cwd and HOME
# outside the repo.
#
# Usage: Scripts/relocated-app-smoke.sh   (after Scripts/build-app.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/Numlex.app"
if [ ! -d "$APP" ]; then
  echo "Missing $APP — run Scripts/build-app.sh first" >&2
  exit 1
fi

WORK="$(mktemp -d /tmp/numlex-relocated-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "Relocating $APP -> $WORK/Numlex.app (outside the repo)..."
ditto "$APP" "$WORK/Numlex.app"
BIN="$WORK/Numlex.app/Contents/MacOS/Numlex"
[ -x "$BIN" ] || { echo "FAIL: copied binary not executable" >&2; exit 1; }

echo "Launching the relocated binary with --validate-packaged-resources..."
# cwd and HOME inside $WORK, isolated data dir: no dev layout reachable.
set +e
( cd "$WORK" && HOME="$WORK" NUMLEX_DATA_DIR="$WORK/data" "$BIN" --validate-packaged-resources )
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  echo "RELOCATED SMOKE PASSED: the copied app resolved its offline bundle from its own Contents/Resources and loaded all five catalogs (no SIGTRAP)."
else
  echo "RELOCATED SMOKE FAILED: exit $STATUS (a trap or a missing/misplaced catalog in the packaged layout)" >&2
  exit "$STATUS"
fi
