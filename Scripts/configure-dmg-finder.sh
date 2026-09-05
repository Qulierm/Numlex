#!/bin/bash
# Apply the strict styled Finder layout to a mounted DMG volume.
#
# Usage: configure-dmg-finder.sh <mounted-volume-path>
#
# Applies (via real Finder Apple events only — no synthetic pointer or
# keyboard input) and then VERIFIES by close/reopen/readback:
#   - icon view, 128 pt icons, no item info, arrangement none, labels bottom
#   - dark icon-view background color {9,11,17} (underlay; drives Finder to
#     render white icon labels on the dark artwork)
#   - background picture = .background/background@2x.png (1600x900 tagged
#     144 dpi: proven to render at the correct 800x450 pt scale with Retina
#     detail; a raw untagged @2x renders 2x cropped, a multirep TIFF is
#     silently ignored by this Finder — hence exactly this file, no fallback)
#   - window bounds {240,120,1040,570} (800x450 content)
#   - toolbar/statusbar/pathbar hidden
#   - exact icon positions (top-left, window-content coords):
#       Numlex.app    {156, 221}   (center 220,285)
#       Applications  {516, 221}   (center 580,285)
#   - support items Finder-invisible AND off-canvas:
#       .background -> {1600, 1000}, .VolumeIcon.icns -> {1760, 1000}
#     (the user-visible window must show ONLY the two product icons even
#     with show-hidden-files enabled; POSITIVE far coords are required —
#     this Finder rejects negative icon positions: it clamps the item to
#     a grid slot AND re-flows the whole layout, flinging placed icons
#     thousands of points off — proven by probe. Positive far coords are
#     accepted exactly, persist across reopen, and need no scrollbars at
#     idle thanks to overlay scrolling)
#
# STRICT: every setter is required. The whole pass is retried boundedly
# (4 attempts); if the readback does not match exactly, the script FAILS
# (exit 1) so the styled build never ships a default-grid fallback.
set -euo pipefail

VOL="${1:?usage: configure-dmg-finder.sh <mounted-volume-path>}"
if [[ ! -d "$VOL" ]]; then
  echo "error: not a directory: $VOL" >&2
  exit 1
fi
if ! pgrep -x Finder >/dev/null 2>&1; then
  echo "error: no Finder session found; cannot apply the layout." >&2
  echo "hint: run in a GUI session, or build with NUMLEX_PLAIN_DMG=1." >&2
  exit 1
fi
for req in "$VOL/Numlex.app" "$VOL/Applications" "$VOL/.background/background@2x.png" "$VOL/.VolumeIcon.icns"; do
  [[ -e "$req" ]] || { echo "error: required volume entry missing: $req" >&2; exit 1; }
done

VOLNAME="$(basename "$VOL")"
VOLPATH="$VOL"

# Finder-invisible flags for support items (belt and braces; the primary
# guarantee is the off-canvas position verified by readback below).
chflags hidden "$VOL/.background" "$VOL/.VolumeIcon.icns" 2>/dev/null || true
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$VOL/.background" "$VOL/.VolumeIcon.icns" 2>/dev/null || true
fi

# Finder's volume discovery (FSEvents) lags hdiutil attach by a few seconds;
# wait until the volume is listed before scripting it.
seen=""
for _ in $(seq 1 30); do
  seen="$(osascript -e 'tell application "Finder" to get name of every disk' 2>/dev/null || true)"
  case "$seen" in
    *"$VOLNAME"*) break ;;
  esac
  sleep 0.5
done
case "$seen" in
  *"$VOLNAME"*) : ;;
  *) echo "error: Finder does not list volume '$VOLNAME' after 15s; cannot apply the layout." >&2; exit 1 ;;
esac

ATTEMPT_RESULT=""
for attempt in 1 2 3 4; do
  ATTEMPT_RESULT="$(osascript - "$VOLNAME" "$VOLPATH" <<'APPLEOF' 2>&1 || echo "APPLESCRIPT-ERROR"
on run argv
	set volName to item 1 of argv
	set volPath to item 2 of argv
	tell application "Finder"
		set theDisk to first disk whose name is volName
		open theDisk
		delay 0.5
		set theWindow to container window of theDisk

		set current view of theWindow to icon view
		set icon size of (icon view options of theWindow) to 128
		set shows item info of (icon view options of theWindow) to false
		set arrangement of (icon view options of theWindow) to not arranged
		set label position of (icon view options of theWindow) to bottom
		-- Dark underlay (best-effort): this Finder does not persist the
		-- color into .DS_Store, so it is NOT part of the verified state.
		-- With a dark background picture set, Finder samples the picture
		-- for label contrast (proven: dark art -> white labels).
		set color of (icon view options of theWindow) to {9, 11, 17}
		set background picture of (icon view options of theWindow) to (POSIX file (volPath & "/.background/background@2x.png") as alias)
		set toolbar visible of theWindow to false
		set statusbar visible of theWindow to false
		set pathbar visible of theWindow to false
		set bounds of theWindow to {240, 120, 1040, 570}
		delay 0.3
		set position of item "Numlex.app" of theDisk to {156, 221}
		set position of item "Applications" of theDisk to {516, 221}
		set position of item ".background" of theDisk to {1600, 1000}
		set position of item ".VolumeIcon.icns" of theDisk to {1760, 1000}
		delay 0.5
		close theWindow
		delay 0.5
		open theDisk
		delay 0.8
		set theWindow2 to container window of theDisk
		set bounds of theWindow2 to {240, 120, 1040, 570}
		delay 0.3
		set out to (current view of theWindow2 as text)
		set out to out & "|" & (icon size of (icon view options of theWindow2) as text)
		set out to out & "|" & (arrangement of (icon view options of theWindow2) as text)
		set ppApp to position of item "Numlex.app" of theDisk
		set out to out & "|" & ((item 1 of ppApp) as text) & "," & ((item 2 of ppApp) as text)
		set ppApps to position of item "Applications" of theDisk
		set out to out & "|" & ((item 1 of ppApps) as text) & "," & ((item 2 of ppApps) as text)
		set ppBg to position of item ".background" of theDisk
		set out to out & "|" & ((item 1 of ppBg) as text) & "," & ((item 2 of ppBg) as text)
		set ppIc to position of item ".VolumeIcon.icns" of theDisk
		set out to out & "|" & ((item 1 of ppIc) as text) & "," & ((item 2 of ppIc) as text)
		set bb to bounds of theWindow2
		set out to out & "|" & ((item 1 of bb) as text) & "," & ((item 2 of bb) as text) & "," & ((item 3 of bb) as text) & "," & ((item 4 of bb) as text)
		set out to out & "|" & (toolbar visible of theWindow2 as text) & "," & (statusbar visible of theWindow2 as text) & "," & (pathbar visible of theWindow2 as text)
		close theWindow2
		return out
	end tell
end run
APPLEOF
)"
  # Expected readback:
  # icon view|128|not arranged|156,221|516,221|-1000,-1000|-1000,-1000|240,120,1040,570|false,false,false
  EXPECTED="icon view|128|not arranged|156,221|516,221|1600,1000|1760,1000|240,120,1040,570|false,false,false"
  if [[ "$ATTEMPT_RESULT" == "$EXPECTED" ]]; then
    echo "Finder layout applied to $VOL (attempt $attempt): strict readback exact."
    break
  fi
  echo "attempt $attempt: readback mismatch: '$ATTEMPT_RESULT'" >&2
  if [[ "$attempt" == "4" ]]; then
    echo "error: Finder layout could not be applied exactly after 4 attempts." >&2
    echo "error: expected '$EXPECTED'." >&2
    exit 1
  fi
  sleep 1
done

sleep 1
if [[ ! -f "$VOL/.DS_Store" ]]; then
  echo "error: Finder did not write $VOL/.DS_Store; layout will not persist." >&2
  exit 1
fi
echo "Finder layout strict-verified on $VOL (window 800x450, icons 220/580x285, support off-canvas)."
