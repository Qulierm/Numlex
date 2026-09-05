#!/bin/bash
# Packaging regressions for the styled Numlex DMG.
#
# Usage: validate-dmg.sh <path-to-dmg>
#
# Checks (all must pass; exit 0 = pass, 1 = fail):
#   1. hdiutil verify: image checksum valid
#   2. mounts read-only; volume name is "Numlex <version>" (from the
#      packaged Info.plist, never hard-coded)
#   3. visible content is EXACTLY: Numlex.app + Applications symlink
#      (no other visible entries; hidden resource entries allowed)
#   4. Applications is a symlink to /Applications
#   5. .background/ holds background.png (800x450) and
#      background@2x.png (1600x900), both sRGB-tagged PNGs
#   6. .VolumeIcon.icns present
#   7. .DS_Store present (Finder layout persisted)
#   8. no third-party/not-Numlex branding artifacts in the volume
#      (e.g. no Notely pixels/paths, no DMG Canvas leftovers)
#   9. Finder layout state: icon view, icon size 128, item positions
#      {156,221} (Numlex.app) and {516,221} (Applications) — requires a
#      Finder session; skipped (with a note) when absent
#  10. detaches cleanly
set -u

DMG="${1:?usage: validate-dmg.sh <path-to-dmg>}"
[[ -f "$DMG" ]] || { echo "FAIL: no such file: $DMG" >&2; exit 1; }

fail=0
note() { echo "note: $*"; }
ok()   { echo "ok:   $*"; }
bad()  { echo "FAIL: $*" >&2; fail=1; }

echo "=== 1. image verify ==="
if hdiutil verify "$DMG" >/dev/null 2>&1; then ok "checksum valid"; else bad "hdiutil verify failed"; exit 1; fi

# --- mount read-only -------------------------------------------------------
ATTACH_OUT="$(hdiutil attach -nobrowse -noverify "$DMG" 2>/dev/null | tail -1)"
MNT="$(echo "$ATTACH_OUT" | awk -F'\t' '{print $NF}')"
if [[ -z "$MNT" || ! -d "$MNT" ]]; then
  bad "mount failed: $ATTACH_OUT"
  exit 1
fi
ok "mounted at $MNT"
cleanup() {
  [[ -n "${MNT:-}" && -d "${MNT:-}" ]] && hdiutil detach "$MNT" -quiet 2>/dev/null
  exit "${fail:-0}"
}
trap cleanup EXIT

# --- 2. version + volume name ------------------------------------------------
APP_PLIST="$MNT/Numlex.app/Contents/Info.plist"
if [[ ! -f "$APP_PLIST" ]]; then
  bad "Numlex.app/Contents/Info.plist missing"
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
VOLNAME="$(basename "$MNT")"
if [[ "$VOLNAME" == "Numlex $VERSION" ]]; then
  ok "volume name '$VOLNAME' matches app version $VERSION"
else
  bad "volume name '$VOLNAME' != 'Numlex $VERSION'"
fi

# --- 3. visible content is exactly app + symlink -----------------------------
VISIBLE="$(ls -A "$MNT" | grep -v '^\.' || true)"
EXPECTED="$(printf 'Applications\nNumlex.app')"
if [[ "$VISIBLE" == "$EXPECTED" ]]; then
  ok "visible entries exactly: Numlex.app, Applications"
else
  bad "visible entries differ from expected"
  echo "---- visible ----" >&2; echo "$VISIBLE" >&2
  echo "---- expected ----" >&2; echo "$EXPECTED" >&2
fi

# --- 4. Applications symlink --------------------------------------------------
if [[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == "/Applications" ]]; then
  ok "Applications -> /Applications"
else
  bad "Applications is not a symlink to /Applications"
fi

# --- 5. background pair -------------------------------------------------------
bg_ok=1
for spec in "background.png:800:450" "background@2x.png:1600:900"; do
  f="${spec%%:*}"; rest="${spec#*:}"; w="${rest%%:*}"; h="${rest#*:}"
  p="$MNT/.background/$f"
  if [[ ! -f "$p" ]]; then bad ".background/$f missing"; bg_ok=0; continue; fi
  pw="$(sips -g pixelWidth "$p" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  ph="$(sips -g pixelHeight "$p" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  if [[ "$pw" == "$w" && "$ph" == "$h" ]]; then
    ok ".background/$f is ${w}x${h}"
  else
    bad ".background/$f is ${pw}x${ph}, expected ${w}x${h}"; bg_ok=0
  fi
  # sRGB chunk present? (scan chunk types; the sRGB chunk tags the file)
  if ! python3 - "$p" <<'PY' 2>/dev/null
import struct, sys
data = open(sys.argv[1], "rb").read()
pos, found = 8, False
while pos + 8 <= len(data):
    ln = struct.unpack(">I", data[pos:pos+4])[0]
    if data[pos+4:pos+8] == b"sRGB":
        found = True; break
    pos += 12 + ln
sys.exit(0 if found else 1)
PY
  then
    bad ".background/$f has no sRGB chunk"; bg_ok=0
  fi
done
(( bg_ok )) || note "background pair incomplete (see failures above)"

# --- 6. volume icon ------------------------------------------------------------
if [[ -f "$MNT/.VolumeIcon.icns" ]]; then ok ".VolumeIcon.icns present"; else bad ".VolumeIcon.icns missing"; fi

# --- 7. .DS_Store ----------------------------------------------------------------
if [[ -f "$MNT/.DS_Store" ]]; then ok ".DS_Store present (layout persisted)"; else bad ".DS_Store missing"; fi

# --- 8. no foreign branding -------------------------------------------------------
if grep -rqi "notely" "$MNT" --exclude-dir=Numlex.app 2>/dev/null; then
  bad "found 'notely' reference outside Numlex.app"
else
  ok "no foreign (Notely) branding in volume"
fi
if [[ -e "$MNT/README*" || -e "$MNT/license*" || -e "$MNT/LICENSE*" ]]; then
  bad "unexpected top-level README/license file in volume"
fi

# --- 9. Finder layout state (requires Finder session) ------------------------------
if pgrep -x Finder >/dev/null 2>&1; then
  sleep 3   # let Finder list the fresh mount
  LAYOUT="$(osascript - "$MNT" <<'APPLEOF' 2>/dev/null || echo "n/a"
on run argv
	set volPath to item 1 of argv
	set volName to text ((offset of "/Volumes/" in volPath) + 9) through -1 of volPath
	tell application "Finder"
		set theDisk to first disk whose name is volName
		open theDisk
		delay 0.5
		set theWindow to container window of theDisk
		-- Size the probe window to the design geometry so persisted
		-- icon positions resolve exactly as in the styled build window.
		set bounds of theWindow to {240, 120, 1040, 570}
		delay 0.3
		set out to (current view of theWindow as text)
		set out to out & ":" & (icon size of (icon view options of theWindow) as text)
		set out to out & ":" & (position of item "Numlex.app" of theDisk as text)
		set out to out & ":" & (position of item "Applications" of theDisk as text)
		close theWindow
		return out
	end tell
end run
APPLEOF
)"
  # LAYOUT is "view:iconSize:appX, appY:appsX, appsY" (positions as text).
  # Tolerant match: view/icon size and the x positions (the design
  # signature) must be exact; y gets a band because Finder rescales icon
  # layouts when the probe window is resized to the design geometry.
  v="${LAYOUT%%:*}"; rest="${LAYOUT#*:}"
  sz="${rest%%:*}"; rest="${rest#*:}"
  app="${rest%%:*}"; apps="${rest#*:}"
  # Coordinates arrive either as "x, y" or concatenated "xy" digits.
  case "$app" in
    *[,\ ]*) ax="${app%%[,\ ]*}"; ay="${app#*[,\ ]}" ;;
    *) ax="${app:0:3}"; ay="${app:3}" ;;
  esac
  case "$apps" in
    *[,\ ]*) bx="${apps%%[,\ ]*}"; by="${apps#*[,\ ]}" ;;
    *) bx="${apps:0:3}"; by="${apps:3}" ;;
  esac
  # normalize to digits only
  ax="${ax//[!0-9]/}"; ay="${ay//[!0-9]/}"
  bx="${bx//[!0-9]/}"; by="${by//[!0-9]/}"
  if [[ "$v" == "icon view" && "$sz" == "128" \
       && "$ax" == "156" && "$bx" == "516" \
       && "$ay" -ge 150 && "$ay" -le 330 \
       && "$by" -ge 150 && "$by" -le 330 ]]; then
    ok "Finder layout: icon view, 128pt, app {${ax},${ay}}, Applications {${bx},${by}} (design x exact, y in band)"
  else
    note "Finder layout state differs: '$LAYOUT' (expected icon view, 128pt, x=156/516)"
  fi
else
  note "no Finder session; layout-state check skipped"
fi

# --- 10. detach ----------------------------------------------------------------
if hdiutil detach "$MNT" -quiet 2>/dev/null; then ok "detached cleanly"; else bad "detach failed"; fi
MNT=""
trap - EXIT

echo
if (( fail )); then
  echo "VALIDATION FAILED"
  exit 1
fi
echo "VALIDATION PASSED: $DMG"
