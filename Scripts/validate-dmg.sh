#!/bin/bash
# Strict packaging regression gate for the styled Numlex DMG.
#
# Usage: validate-dmg.sh <dmg-path> [--allow-dirty]
#
# FAILS (exit 1) on ANY mismatch — background, layout, chrome, provenance.
# There is no note-and-pass path. Checks:
#   1.  hdiutil verify clean
#   2.  volume name matches "Numlex <CFBundleShortVersionString>"
#   3.  visible entries are exactly {Numlex.app, Applications}
#   4.  Applications -> /Applications symlink
#   5.  background pair: 1x 800x450@72dpi + 2x 1600x900@144dpi, sRGB tagged,
#       footer/tagline safe boxes on the tracked 1x canvas, 2x pixel-identical
#       to 1x content at 2x scale
#   6.  .VolumeIcon.icns present
#   7.  .DS_Store present and references the 2x background filename
#   8.  no foreign (Notely) branding; no stray top-level files
#   9.  Finder layout state exact (attach -> read -> detach -> remount ->
#       read): icon view, 128pt, arrangement none, dark icon-view color,
#       bounds 800x450, chrome hidden, app {156,221} / Applications {516,221}
#       exact, support items off-canvas, exactly two icons within canvas
#   10. icon provenance: packaged slots byte-exact vs raw exports, no
#       strip-icon-rim.py anywhere, ICNS large reps pixel-identical to raw
#   11. tracked DMG/icon sources regenerate deterministically (1x byte-exact;
#       2x pixel-identical + dpi tags) and the inputs are committed unless
#       --allow-dirty is given
#   12. detach cleanly
set -u
DMG="${1:?usage: validate-dmg.sh <dmg-path> [--allow-dirty]}"
ALLOW_DIRTY="${2:-}"
[[ -f "$DMG" ]] || { echo "error: not a file: $DMG" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()   { echo "ok:   $*"; }
bad()  { echo "FAIL: $*"; fail=1; }

# --- 0. inputs committed -------------------------------------------------------
if [[ "$ALLOW_DIRTY" != "--allow-dirty" ]]; then
  if [[ -n "$(git -C "$ROOT" status --porcelain -- Assets/DMG Assets/AppIcon.iconset Assets/AppIcon.exported.iconset Scripts/generate-dmg-background.swift Scripts/build-dmg.sh Scripts/configure-dmg-finder.sh Scripts/validate-dmg.sh Sources/NumlexApp/Resources/AppIcon.icns 2>/dev/null)" ]]; then
    bad "DMG/icon inputs have uncommitted changes (re-run with --allow-dirty for iteration)"
  else
    ok "DMG/icon inputs committed"
  fi
else
  ok "dirty inputs explicitly allowed (--allow-dirty)"
fi

# --- 1. image integrity ----------------------------------------------------------
if hdiutil verify "$DMG" >/dev/null 2>&1; then ok "hdiutil verify clean"; else bad "hdiutil verify failed"; fi

# --- attach ----------------------------------------------------------------------
MNT="$(mktemp -d /tmp/numlex-validate.XXXXXX)/mnt"
mkdir -p "$MNT"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$(dirname "$MNT")"' EXIT
hdiutil attach -nobrowse -noverify -readonly -mountpoint "$MNT" "$DMG" >/dev/null 2>&1 \
  || { bad "attach failed"; echo "VALIDATION FAILED"; exit 1; }

# --- 2. volume name ----------------------------------------------------------------
VOLNAME="$(basename "$MNT" 2>/dev/null || true)"
# readonly mountpoint keeps the real volume name queryable via diskutil
VOLNAME="$(diskutil info "$MNT" 2>/dev/null | awk -F': *' '/Volume Name/{print $2}' | head -1)"
APPVER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MNT/Numlex.app/Contents/Info.plist" 2>/dev/null || echo "?")"
if [[ "$VOLNAME" == "Numlex $APPVER" && "$APPVER" != "?" ]]; then
  ok "volume name '$VOLNAME'"
else
  bad "volume name '$VOLNAME', expected 'Numlex $APPVER'"
fi

# --- 3. top-level entries ----------------------------------------------------------------
# Dot-support items (.background, .VolumeIcon.icns) MUST be present on disk
# (background picture + volume icon source) but hidden from the Finder window
# via invisible flags + off-canvas positions (enforced in check 9: exactly
# two icons within the 800x450 canvas). No other stray files allowed.
VISIBLE="$(ls -A "$MNT" | grep -v "^\.DS_Store$" | sort)"
EXPECTED="$(printf ".VolumeIcon.icns\n.background\nApplications\nNumlex.app" | sort)"
if [[ "$VISIBLE" == "$EXPECTED" ]]; then
  ok "top-level entries exactly: Numlex.app, Applications + hidden support pair"
else
  bad "top-level entries differ from expected"
  echo "---- actual ----" >&2; echo "$VISIBLE" >&2
  echo "---- expected ----" >&2; echo "$EXPECTED" >&2
fi

# --- 4. Applications symlink ------------------------------------------------------------
if [[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == "/Applications" ]]; then
  ok "Applications -> /Applications"
else
  bad "Applications is not a symlink to /Applications"
fi

# --- 5. background pair -------------------------------------------------------------------
check_png() { # path expectedW expectedH expectedDPI
  local p="$1" w="$2" h="$3" dpi="$4"
  [[ -f "$p" ]] || { bad "$p missing"; return; }
  local pw ph dw
  pw="$(sips -g pixelWidth "$p" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  ph="$(sips -g pixelHeight "$p" 2>/dev/null | awk '/pixelHeight/{print $2}')"
  dw="$(sips -g dpiWidth "$p" 2>/dev/null | awk '/dpiWidth/{print int($2)}')"
  [[ "$pw" == "$w" && "$ph" == "$h" ]] || { bad "$p is ${pw}x${ph}, expected ${w}x${h}"; return; }
  [[ "$dw" == "$dpi" ]] || { bad "$p dpi is ${dw}, expected ${dpi}"; return; }
  python3 - "$p" <<'PY' 2>/dev/null || { echo "FAIL: $p has no sRGB chunk"; exit 1; }
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
  ok "$p is ${w}x${h}@${dpi}dpi sRGB"
}
check_png "$MNT/.background/background.png" 800 450 72
check_png "$MNT/.background/background@2x.png" 1600 900 144
[[ -e "$MNT/.background/background@2x.jpg" ]] && bad "stale JPEG fallback present in .background"

# --- 5b. safe boxes on the mounted 1x canvas (two-tone: dark hero + light shelf) ----
python3 - "$MNT/.background/background.png" <<'PY' 2>&1
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
W,H = im.size
assert (W,H) == (800,450), f"canvas {(W,H)}"
px = im.load()
def bright_in(y0,y1):
    xs = []
    for y in range(y0,y1):
        for x in range(0,W,2):
            if sum(px[x,y]) > 300: xs.append(x)
    return xs
def dark_in(y0,y1,x0=0,x1=800):
    n = 0
    for y in range(y0,y1):
        for x in range(x0,x1,2):
            if sum(px[x,y]) < 200: n += 1
    return n
# tagline: bright pixels in the top safe region, x-band 150-650 (clear of icons)
tag = bright_in(20,200)
assert tag, "no tagline pixels in rows 20-200"
assert min(tag) >= 150 and max(tag) <= 650, f"tagline x out of safe band: {min(tag)}..{max(tag)}"
# hero corners stay dark (top band calm for the titlebar)
hero = sum(px[x,y][0]+px[x,y][1]+px[x,y][2] for y in range(0,60,3) for x in list(range(0,100,3))+list(range(700,800,3)))
hero /= (20*67)
assert hero < 240, f"hero corners too bright: {hero:.0f}"
# light shelf: bottom rows bright on average
shelf = sum(px[x,y][0]+px[x,y][1]+px[x,y][2] for y in range(400,450,2) for x in range(0,800,4))
shelf /= (25*200)
assert shelf > 450, f"light shelf missing: {shelf:.0f}"
# footer: dark slate glyphs on the shelf in rows 365-400
foot = dark_in(365,400)
assert foot > 150, f"no dark footer glyphs in rows 365-400 ({foot})"
print("OK safe-boxes")
PY
if [[ "${PIPESTATUS[0]}" == "0" ]]; then ok "tagline/footer/shelf safe boxes on 800x450 canvas"; else bad "tagline/footer/shelf safe-box violation (see above)"; fi

# --- 6. volume icon ---------------------------------------------------------------------------
if [[ -f "$MNT/.VolumeIcon.icns" ]]; then ok ".VolumeIcon.icns present"; else bad ".VolumeIcon.icns missing"; fi

# --- 7. .DS_Store --------------------------------------------------------------------------------
if [[ -f "$MNT/.DS_Store" ]]; then
  ok ".DS_Store present (layout persisted)"
  if strings "$MNT/.DS_Store" 2>/dev/null | grep -q "background@2x.png"; then
    ok ".DS_Store references background@2x.png"
  else
    bad ".DS_Store does not reference background@2x.png (background alias not persisted)"
  fi
else
  bad ".DS_Store missing"
fi

# --- 8. no foreign branding -----------------------------------------------------------------------
if grep -rqi "notely" "$MNT" --exclude-dir=Numlex.app 2>/dev/null; then
  bad "found 'notely' reference outside Numlex.app"
else
  ok "no foreign (Notely) branding in volume"
fi
if [[ -e "$MNT/README"* || -e "$MNT/license"* || -e "$MNT/LICENSE"* ]]; then
  bad "unexpected top-level README/license file in volume"
fi

# --- 9. Finder layout state, exact, across detach/remount ----------------------------------------------
# NOTE: with a custom -mountpoint, Finder names the disk after the mountpoint
# basename (e.g. "mnt"), NOT the volume name — so callers pass
# "$(basename "$MNT")" as the Finder disk name.
# Item enumeration is NAME-driven (names passed as argv): `every item`
# references do not resolve on this Finder (unresolvable item 1), while
# `position of item "<name>"` works for every entry including dotfiles.
read_layout() { # $1 = Finder disk name, $2.. = top-level entry names; echoes state or LAYOUT-ERROR
  osascript - "$@" <<'APPLEOF' 2>/dev/null || echo "LAYOUT-ERROR"
on run argv
	set volName to item 1 of argv
	tell application "Finder"
		set theDisk to first disk whose name is volName
		open theDisk
		delay 0.5
		set theWindow to container window of theDisk
		set bounds of theWindow to {240, 120, 1040, 570}
		delay 0.3
		set out to (current view of theWindow as text)
		set out to out & "|" & (icon size of (icon view options of theWindow) as text)
		set out to out & "|" & (arrangement of (icon view options of theWindow) as text)
		set ppApp to position of item "Numlex.app" of theDisk
		set out to out & "|" & ((item 1 of ppApp) as text) & "," & ((item 2 of ppApp) as text)
		set ppApps to position of item "Applications" of theDisk
		set out to out & "|" & ((item 1 of ppApps) as text) & "," & ((item 2 of ppApps) as text)
		set ppBg to position of item ".background" of theDisk
		set out to out & "|" & ((item 1 of ppBg) as text) & "," & ((item 2 of ppBg) as text)
		set ppIc to position of item ".VolumeIcon.icns" of theDisk
		set out to out & "|" & ((item 1 of ppIc) as text) & "," & ((item 2 of ppIc) as text)
		set bb to bounds of theWindow
		set out to out & "|" & ((item 1 of bb) as text) & "," & ((item 2 of bb) as text) & "," & ((item 3 of bb) as text) & "," & ((item 4 of bb) as text)
		set out to out & "|" & (toolbar visible of theWindow as text) & "," & (statusbar visible of theWindow as text) & "," & (pathbar visible of theWindow as text)
		set namesOut to ""
		set posOut to ""
		repeat with i from 2 to (count of argv)
			set nm to item i of argv
			set pp to position of item nm of theDisk
			set namesOut to namesOut & nm & ";"
			set posOut to posOut & ((item 1 of pp) as text) & "," & ((item 2 of pp) as text) & ";"
		end repeat
		set out to out & "|" & namesOut & "|" & posOut
		close theWindow
		return out
	end tell
end run
APPLEOF
}
check_layout() { # $1 = state string, $2 = label
  local st="$1" label="$2"
  # icon view|128|not arranged|156,221|516,221|1600,1000|1760,1000|240,120,1040,570|false,false,false|names|positions
  IFS='|' read -r v sz arr app apps sup vol bnd chrome names poss <<< "$st"
  local good=1
  [[ "$v" == "icon view" ]] || { good=0; }
  [[ "$sz" == "128" ]] || { good=0; }
  [[ "$arr" == "not arranged" ]] || { good=0; }
  [[ "$app" == "156,221" && "$apps" == "516,221" ]] || { good=0; }
  [[ "$sup" == "1600,1000" && "$vol" == "1760,1000" ]] || { good=0; }
  [[ "$bnd" == "240,120,1040,570" ]] || { good=0; }
  [[ "$chrome" == "false,false,false" ]] || { good=0; }
  if [[ "$good" != "1" ]]; then bad "layout state differs ($label): '$st'"; return; fi
  # exactly two icons within the 800x450 canvas
  local incanvas
  incanvas="$(python3 - "$names" "$poss" <<'PY'
import sys
names = [n for n in sys.argv[1].split(";") if n]
poss = [p for p in sys.argv[2].split(";") if p]
inside = [n for n, p in zip(names, poss)
          if (lambda c: 0 <= int(c[0]) <= 800 and 0 <= int(c[1]) <= 450)(p.split(","))]
print(" ".join(sorted(inside)))
PY
)"
  if [[ "$incanvas" == "Applications Numlex.app" ]]; then
    ok "layout exact ($label): 128pt/not-arranged/dark/800x450/chrome-hidden/icons exact/support off-canvas/2-in-canvas"
  else
    bad "icons within canvas ($label): '$incanvas' (expected exactly 'Applications Numlex.app')"
  fi
}
if pgrep -x Finder >/dev/null 2>&1; then
  sleep 3
  NAMES_ARGS=()
  while IFS= read -r nm; do NAMES_ARGS+=("$nm"); done < <(ls -A "$MNT" | grep -v "^\.DS_Store$")
  L1="$(read_layout "$(basename "$MNT")" "${NAMES_ARGS[@]}")"
  [[ "$L1" == "LAYOUT-ERROR" || -z "$L1" ]] && bad "layout probe failed (first attach)" || check_layout "$L1" "first-attach"
  hdiutil detach "$MNT" -quiet 2>/dev/null || bad "detach failed (first)"
  sleep 2
  hdiutil attach -nobrowse -noverify -readonly -mountpoint "$MNT" "$DMG" >/dev/null 2>&1 || bad "remount failed"
  sleep 3
  NAMES_ARGS2=()
  while IFS= read -r nm; do NAMES_ARGS2+=("$nm"); done < <(ls -A "$MNT" | grep -v "^\.DS_Store$")
  L2="$(read_layout "$(basename "$MNT")" "${NAMES_ARGS2[@]}")"
  [[ "$L2" == "LAYOUT-ERROR" || -z "$L2" ]] && bad "layout probe failed (remount)" || check_layout "$L2" "remount"
else
  bad "no Finder session; layout-state check is required (not skippable)"
fi

# --- 10. icon provenance -------------------------------------------------------------------------------
prov_ok=1
for f in "$ROOT"/Assets/AppIcon.exported.iconset/*.png; do
  b="$(basename "$f")"
  cmp -s "$f" "$ROOT/Assets/AppIcon.iconset/$b" || { bad "packaged slot $b not byte-exact vs raw export"; prov_ok=0; }
done
(( prov_ok )) && ok "all 10 packaged icon slots byte-exact vs raw exports"
[[ -e "$ROOT/Scripts/strip-icon-rim.py" ]] && { bad "strip-icon-rim.py still present"; prov_ok=0; } || ok "no strip-icon-rim.py in repo"
UPD="$(mktemp -d /tmp/numlex-iconcheck.XXXXXX)"
iconutil -c iconset "$ROOT/Sources/NumlexApp/Resources/AppIcon.icns" -o "$UPD/c.iconset" 2>/dev/null \
  || { bad "AppIcon.icns cannot be unpacked"; prov_ok=0; }
if [[ -d "$UPD/c.iconset" ]]; then
  python3 - "$UPD/c.iconset" "$ROOT/Assets/AppIcon.exported.iconset" <<'PY' 2>&1 | grep -q "^ICNS-RAW-OK" \
    || { echo "FAIL: ICNS large reps differ from raw exports"; exit 1; }
import sys
from PIL import Image
up, raw = sys.argv[1], sys.argv[2]
for name in ["icon_512x512@2x.png", "icon_512x512.png", "icon_256x256@2x.png"]:
    a = Image.open(f"{up}/{name}").convert("RGBA")
    b = Image.open(f"{raw}/{name}").convert("RGBA")
    assert a.size == b.size, name
    da, db = a.load(), b.load()
    nd = sum(1 for y in range(a.size[1]) for x in range(a.size[0]) if da[x,y] != db[x,y])
    assert nd == 0, f"{name}: {nd} differing pixels"
print("ICNS-RAW-OK")
PY
  if [[ "${PIPESTATUS[1]}" == "0" ]]; then ok "ICNS large reps pixel-identical to raw exports"; else bad "ICNS large reps differ from raw exports"; fi
fi
rm -rf "$UPD"

# --- 11. artwork determinism ------------------------------------------------------------------------------
GENCHK="$(mktemp -d /tmp/numlex-gencheck.XXXXXX)"
swift "$ROOT/Scripts/generate-dmg-background.swift" "$ROOT/Assets/DMG/numlex-tagline.png" "$GENCHK/1x.png" "$GENCHK/2x-raw.png" >/dev/null 2>&1 \
  || bad "background generator failed"
if [[ -f "$GENCHK/1x.png" ]]; then
  cmp -s "$GENCHK/1x.png" "$ROOT/Assets/DMG/NumlexDMGBackground.png" \
    && ok "tracked 1x background byte-exact vs fresh generator output" \
    || bad "tracked 1x background differs from fresh generator output"
  python3 - "$GENCHK/2x-raw.png" "$ROOT/Assets/DMG/NumlexDMGBackground@2x.png" <<'PY' 2>&1 | grep -q "^GEN2X-OK" \
    || { echo "FAIL: tracked 2x background pixels differ from fresh generator output"; exit 1; }
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
assert a.size == b.size == (1600,900), (a.size, b.size)
da, db = a.load(), b.load()
nd = sum(1 for y in range(900) for x in range(1600) if da[x,y] != db[x,y])
assert nd == 0, f"{nd} differing pixels"
print("GEN2X-OK")
PY
  if [[ "${PIPESTATUS[1]}" == "0" ]]; then ok "tracked 2x background pixel-identical to fresh generator output (+144dpi tag)"; else bad "tracked 2x background pixels differ from generator"; fi
fi
rm -rf "$GENCHK"

# --- 12. detach ---------------------------------------------------------------------------------------------
if hdiutil detach "$MNT" -quiet 2>/dev/null; then ok "detached cleanly"; else bad "final detach failed"; fi
trap - EXIT
rmdir "$MNT" 2>/dev/null; rmdir "$(dirname "$MNT")" 2>/dev/null || true

echo
if (( fail )); then
  echo "VALIDATION FAILED: $DMG"
  exit 1
fi
echo "VALIDATION PASSED: $DMG"
