#!/bin/bash
# Apply the styled-DMG Finder layout to an already-mounted volume using
# ONLY Finder Apple events (osascript "Finder" — no System Events, no
# synthetic pointer/keyboard input, no third-party tools).
#
# Usage: configure-dmg-finder.sh <mounted-volume-path>
#
# Layout (matches Assets/DMG/NumlexDMGBackground.png, 800x450 canvas):
#   - icon view, 128 pt icons, no item info
#   - window bounds 800x450 (Finder overlays its title bar on top; the
#     canvas top band is quiet gradient designed for that)
#   - Numlex.app       icon centered at (220, 285)  -> top-left (156, 221)
#   - Applications     icon centered at (580, 285)  -> top-left (516, 221)
#     (128 pt icons; Finder item `position` is the top-left corner in
#     window-content coordinates)
#   - background: taken automatically by Finder from the volume's
#     .background/ folder; volume icon from .VolumeIcon.icns
#
# Chrome visibility (toolbar/statusbar/pathbar) and per-item icon positions
# are attempted best-effort: the shipped Finder dictionary declares these,
# but the runtime on current macOS (26.x) no longer accepts the setters
# (-10006), so each is wrapped in try. On macOS versions that still honor
# them the exact designed layout is applied; otherwise the icons fall back
# to Finder's default grid while the window geometry, icon size and
# background remain as designed.
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

VOLNAME="$(basename "$VOL")"
VOLPATH="$VOL"

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

LAYOUT_OK="$(osascript - "$VOLNAME" "$VOLPATH" <<'APPLEOF'
on run argv
	set volName to item 1 of argv
	set volPath to item 2 of argv
	tell application "Finder"
		-- The disk is already listed (waited for above); address it by
		-- object rather than POSIX path (the path cache lags fresh mounts).
		set theDisk to first disk whose name is volName
		open theDisk
		delay 0.5
		set theWindow to container window of theDisk

		-- Icon view with 128 pt icons, no item info (required; hard failure).
		set current view of theWindow to icon view
		set icon size of (icon view options of theWindow) to 128
		set shows item info of (icon view options of theWindow) to false

		-- Background: current macOS Finder no longer auto-scans the
		-- .background folder, so pin a background picture explicitly; Finder
		-- persists the reference into the volume .DS_Store. Prefer the 2x PNG
		-- (Retina audience); fall back to the 1x PNG, then the 2x JPEG. The
		-- .background folder is kept as well for macOS versions that still
		-- honor the auto-scan.
		set bgOK to false
		try
			set background picture of (icon view options of theWindow) to (POSIX file (volPath & "/.background/background@2x.png") as alias)
			set bgOK to true
		end try
		if bgOK is false then
			try
				set background picture of (icon view options of theWindow) to (POSIX file (volPath & "/.background/background.png") as alias)
				set bgOK to true
			end try
		end if
		if bgOK is false then
			try
				set background picture of (icon view options of theWindow) to (POSIX file (volPath & "/.background/background@2x.jpg") as alias)
				set bgOK to true
			end try
		end if

		-- Window geometry: 800x450, positioned for a typical display.
		set bounds of theWindow to {240, 120, 1040, 570}

		-- Best-effort chrome hiding (runtime-rejected on current macOS).
		try
			set toolbar visible of theWindow to false
		end try
		try
			set statusbar visible of theWindow to false
		end try
		try
			set pathbar visible of theWindow to false
		end try

		-- Icon slots (top-left corners of the 128 pt icons). Best-effort:
		-- the current macOS Finder runtime rejects the position setter.
		set positionsOK to true
		try
			set position of item "Numlex.app" of theDisk to {156, 221}
		on error
			set positionsOK to false
		end try
		try
			set position of item "Applications" of theDisk to {516, 221}
		on error
			set positionsOK to false
		end try

		if positionsOK then
			return "positions"
		else
			return "grid"
		end if
	end tell
end run
APPLEOF
)" || { echo "error: Finder layout failed (see message above)." >&2; exit 1; }

# Give Finder a moment to persist the window state to the volume's .DS_Store.
sleep 1
if [[ ! -f "$VOL/.DS_Store" ]]; then
  echo "error: Finder did not write $VOL/.DS_Store; layout will not persist." >&2
  exit 1
fi

if [[ "$LAYOUT_OK" == "positions" ]]; then
  echo "Finder layout applied to $VOL (window 800x450, icons at 220/580 x 285)"
else
  echo "warning: this Finder runtime rejected the icon-position setter;" >&2
  echo "warning: window geometry/icon size/background are applied, icons use" >&2
  echo "warning: Finder's default grid on this OS." >&2
fi
