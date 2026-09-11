# Settings and appearance

This document describes Numlex's settings and appearance contracts on the
current `main` branch. It is written for authors of the published
documentation: every claim here is pinned by the Swift source and the
canonical engine tests. Released builds may lag behind `main`.

Settings are organized into **six categories**, selected from a compact row of
**icon-over-label tiles across the top of the window**; each page is one readable
column of grouped rows with native switches, pickers and sliders. Nothing here is cloud-synced; every preference is
stored on your Mac.

| Category | Icon | Owns |
| --- | --- | --- |
| **General** | gear | Interface language, Auto / Light / Dark appearance, the Dock / App Switcher application icon (all three are rows of the Interface group), and notebook window behaviour (line numbers, hide-sidebar button, bottom Total bar) |
| **Editing** | pencil tip | Operator helpers and automatic insertions — everything that rewrites text as you type |
| **Numbers** | number | Regional number format, paste conversion, how answers are displayed and copied, the answer notation (including the custom pattern field) |
| **Constants & Units** | function | Global constants and custom units (one segmented surface) |
| **Styling** | paintbrush | Typography, answer column, syntax colors, live preview |
| **About** | info circle | The app icon and version, plus Check for Updates and the automatic-check schedule (never part of `.nlx`) |

The navigation is a compact, centered row of **six icon-over-label tiles** directly
below the compact native titlebar (no section title is repeated above it — the active
tile's visible label names the page, and no page title appears in the scrolling
detail either). Each tile is
an equal 66 × 50 pt slot holding its SF Symbol above its concise localized label; there
is no left sidebar, no split-view container, no full-width tab bar and no divider. The
selected tile carries a **calm neutral rounded rectangle** (a subtle theme-aware gray
with a hairline border) while its icon AND label turn accent-colored — never a solid
accent block and never a white icon. Unselected tiles are transparent with muted
content, and hover is a weaker neutral wash that never moves the layout. The selected
tile is the only one with the `.isSelected` accessibility trait; every tile also
carries a localized tooltip and accessibility label with its FULL page title. The
arrow keys move the selection across the row and the focus cue stays on the selected
tile. Categories, in order: General, Editing, Numbers, Constants, Styling, About.
Tiles use a concise visible label where the full page title would be too wide
("Constants" for Constants & Units, Russian "Стиль" for Styling, Italian "Info" for
Informazioni); the full page title always appears in the tooltip and the
accessibility label.

The selected page fills the rest of the window and is the ONLY thing that scrolls. It
uses the AVAILABLE width with one shared page padding (19 pt), so the cards reach the
window edges instead of leaving wide unused fields. The window content range is
520–640 × 500–640 pt (ideal 560 × 540). The selection is session-only, defaults to
General and is never persisted into the settings store.

The Settings window carries no toolbar: its empty NSToolbar is hidden through public
AppKit, so the compact native titlebar ("Numlex Settings"), the traffic lights and the
draggable region sit directly above the bar — no reserved blank band. Pages show their
title and then their group headings; there are no redundant page subtitles, and obvious
captions are omitted.

## First launch

A genuinely new install (an empty data directory) opens on the **welcome bloom**
instead of the notebook. Ten short calculations in the REAL editor palette float
in two airy columns around the packaged Dark app icon and gather into it:

| Column | Rows |
| --- | --- |
| left | `128 × 4 = 512`, `18% of 240 = 43.2`, `3.5 km → 3500 m`, `2h 15m + 45m = 3h`, `√144 = 12` |
| right | `price = 24`, `$42 + $18 = $60`, `12 kg ÷ 3 = 4 kg`, `2^10 = 1024`, `9 ft → 2.74 m` |

Every run resolves through the app's own editor tokens (`Design.numberColor` for
numerals, `variableColor` for the variable, `conversionColor` for units and time
units, `moneyMarkerColor` for currency markers, `baseText` for operators) on
`Design.editorBackground`, so the field matches the notebook in Auto, Light and
Dark automatically. There is no slogan and no marketing copy, and the notebook,
sidebar and TextKit are never created behind the screen.

The choreography is one deterministic one-shot sequence of roughly two seconds:
the icon fades in, the rows stream in with a per-row and per-token stagger, the
result runs brighten once, the rows gather into the icon in two tight batches,
and the icon answers with a **monochrome silver splash** — fourteen fine radial
rays with fixed varied lengths, a soft expanding wave and eight droplets, all
drawn from `Design.baseText` / the neutral label tones (never the palette hues),
plus one icon-masked silver sheen. The localized **Get Started** button then
fades in and takes focus. The button is monochrome too: its fill is the icon
family's dominant tone (near-white silver in Dark, graphite in Light) with the
opposite tone as the label, a 1 pt rim, a restrained shadow and an explicit
keyboard focus ring — no system accent colour. Nothing repeats, nothing ticks
after the sequence, and only opacity/offset/scale/rotation/trim change, so the
window never resizes.

With **Reduce Motion** the whole sequence is skipped: the icon and the button are
shown immediately, focused and interactive at once, with no staged state,
splash or sleep.

Pressing Get Started records a versioned completion marker (`welcome-v1`) in the
app's data directory — the same directory as `store.json`, and the one
`--data-dir` redirects — and then performs the reveal in three explicit steps:
the notebook mounts BENEATH the still-covering welcome (not animated), the next
runloop turn starts an animated vertical OFFSET that slides the welcome panel
fully up out of the clipped content bounds over 0.75 s on a soft acceleration
curve (a restrained shadow rides the panel's bottom edge for depth), and once
the travel time has elapsed the welcome is dropped for good and the editor takes
focus. The panel keeps its identity throughout — the slide is never a transition
attached to a newly inserted branch — and the actual NSWindow, its titlebar,
traffic lights and screen frame are never touched, moved or animated. Pointer
events are blocked while the panel is moving, and focus is requested only after
it has cleared. Under Reduce Motion the welcome is removed immediately: no
mount step, no animation, no delay, then focus.

If the marker cannot be written the app still opens for that session and shows
the bloom again later. Existing users are never onboarded: any prior artifact —
`store.json` (even corrupt or unreadable), `rates.json`, `weather.json` or
`locations.json` — counts as an existing install, and the marker is then recorded
best-effort without modifying those files, so a later cache delete cannot turn
that user into a "new" one. Onboarding never creates, edits or persists a sheet,
never changes the store schema/version, `AppSettings` (an explicit
Light/Dark/Auto choice and app icon survive untouched) or any `.nlx` file, and
the first-launch state lives outside the store and `UserDefaults`.

## General

r91 merged the former Appearance page into General: language, appearance,
application icon and notebook behaviour are now one page, each control with exactly
one home.

### Interface

| Control | Values | Notes |
| --- | --- | --- |
| Interface language | the app's shipped languages | Localizes the UI only — it never changes the numeric format. |
| Appearance | Auto / Light / Dark | Applies to the whole app immediately (one persisted settings write). **Auto** follows the macOS appearance live: the process appearance is released to the system (`NSApp.appearance = nil`, no SwiftUI scheme override), so window chrome, native menus, Liquid Glass surfaces, the answer palettes and the TextKit editor repaint when macOS switches Light ↔ Dark. **Light** and **Dark** pin the app and ignore system changes. **Fresh installs default to Auto** (the app follows macOS from the first launch); an explicit Light/Dark/Auto choice is stored exactly and survives relaunches, and a **legacy store whose `appearance` key is missing or malformed still decodes to Light**, so existing installs never change appearance on upgrade. |
| Application icon | Dark / Light | The **Dock and App Switcher** icon only. Dark (the fresh default) is the signed bundle icon — the modern Liquid Glass `Assets.car` primary; Light is the alternate icon shipped inside the app. Switching applies immediately and is remembered across launches, and it is color/image only: it never changes the Finder icon of the installed bundle, the code signature, the window geometry, the caret/selection or any document. Mirrors: the app never writes a Finder icon (`NSWorkspace.setIcon` is not used), so update trust and permissions stay intact. Implementation: both choices come from the SAME modern Liquid Glass catalog compiled into the app (`Assets.car` carries the `AppIcon` and alternate `AppIconLight` iconstacks), so Light and Dark share one rendition ladder and one 128 pt logical size. Dark is applied deterministically through the named `AppIcon` asset (`NSImage(named:)`); the Light ICNS shipped in the resources is used only by development builds without `Assets.car` and is normalized to the same logical size in memory. The launch capture happens before any persisted choice is applied, so a persisted Light can never be mistaken for the bundle default and Dark always restores the real primary icon. |

### Notebook

| Control | Default | Behaviour |
| --- | --- | --- |
| Line numbers | on | Shows the line number beside each input line. |
| Hide sidebar button when collapsed | off | Hides the toolbar button while the sidebar is collapsed; reopen the sidebar with **⌃⌘S** (Control-Command-S) or View → Toggle Sidebar. |
| Show total bar | on | Hides the sheet's bottom Total panel (the footer that sums the evaluated magnitude of every ordinary scalar answer — unitless, unit-bearing and money rows included — and formats the one unitless result with the global number settings). Inline `total` lines keep evaluating and rendering — the toggle never disables the command. |

## Editing

Everything here changes the text you type, never an evaluated value.

### Operators

| Control | Effect |
| --- | --- |
| Pad operators with spaces | `1+1` becomes `1 + 1` |
| Replace `*` with `×` | `3*3` becomes `3 × 3` |
| Replace backtick `` ` `` with `+` | ``5`5`` becomes `5 + 5` |
| Use QuickOperators | `5p5` → `5 + 5`, `5m5` → `5 − 5`, `5x5` → `5 × 5`, `5d5` → `5 ÷ 5` |

QuickOperators act only between two digits and never inside identifiers
(`0x…` is never rewritten).

### Automatic insertions

| Control | Effect |
| --- | --- |
| Format numbers with thousand separators | Groups numbers as you type (`10000` becomes `10,000`). How *answers* are grouped is a separate setting on the Numbers tab. |
| Insert previous answer after typing operator on new line | After pressing return, typing any operator (`+ − × ÷`) starts a line that reuses the previous answer as a live token. |

## Numbers

### Number format (region)

The region preset changes how numbers are typed, pasted, grouped and
displayed, and which separator function calls expect.

| Format | Example | Decimal | Grouping | Function argument separator |
| --- | --- | --- | --- | --- |
| System | platform | locale | locale | `;` if the system decimal separator is a comma, otherwise `,` |
| North America | `1,234.56` | `.` | `,` | `,` |
| Western Europe | `1.234,56` | `,` | `.` | `;` |
| Eastern Europe | `1 234,56` | `,` | NBSP (a space is accepted in input) | `;` |

If the region is not set explicitly, the app uses the pre-region (US) legacy
convention.

Changing the region can re-interpret numbers in the open sheet. The app warns
with a confirmation listing the answers that would change, and only applies the
change when confirmed.

Independent toggles in the same group:

| Control | Effect |
| --- | --- |
| Convert foreign numbers on paste | `1,234.56` pasted into a comma-decimal setup becomes the local form (`1.234,56`). Prose and already-local numbers are untouched. |
| Show thousands separator | Answers display `10000` as `10,000` (or the local form). |
| Compact large numbers | Answers display `100000` as `100k`. Copied values keep full precision. |

### Answer display

| Control | Range / values | Effect |
| --- | --- | --- |
| Rounding | 2…10 decimal places | Global answer rounding. Calculation precision is never changed — only the displayed and copied value. |
| Default answer format → Notation | Automatic, Decimal, Scientific, Engineering, Fraction, Custom | How numeric answers are shown and copied. |
| Fraction denominator | bounded denominator | Largest denominator the fraction approximation may use (Fraction mode). |
| Negative numbers | Minus prefix (`-123`), Parentheses (`(123)`), Trailing minus (`123-`) | Display-only style for negative results. |
| Currency symbol | Before (`$123`), Before, spaced (`$ 123`), After (`123$`), After, spaced (`123 $`) | Where the currency symbol sits. |
| Custom format | pattern string | A locale-neutral number skeleton (for example `#,##0.00`), at most 96 characters. |

`Automatic` shows a plain/compact value with a scientific fallback at very
large magnitudes (`|v| ≥ 1e16`) and never switches to engineering notation by
itself. An invalid custom pattern is still saved and editable but never
reaches rendering: those answers fall back to Automatic until the pattern is
fixed. The full pattern grammar is documented with the syntax reference (see
[SYNTAX_REFERENCE.md](SYNTAX_REFERENCE.md), "Отображение чисел").

Switching the *display* mode never changes a value, an answer token's payload,
a dependency or a total — only how the value is rendered and copied.

## Constants

One segmented surface with two tables:

| Section | Row limit | Values |
| --- | --- | --- |
| Constants | 100 | A finite unitless scalar, a percentage, or a single-fiat-code money value; may reference other constants; dependencies resolve independently of row order. |
| Units | 100 | A definition is either a multiple of an existing unit (`12 feet`) or the literal `new unit` (an independent dimension). |

Each row carries a stable identity and a deterministic status (incomplete,
invalid name, duplicate, reserved, invalid expression, unknown dependency,
cycle, limit reached, and so on). Invalid rows stay visible but inactive: they
reserve no name and are never referenced.

Constants and custom units are **app-global**. `.nlx` sheet exports never embed
them, and they can only be edited in Settings.

## Styling

### Typography

- Font size (continuous slider) and font design (System Default, Rounded,
  Serif, Monospaced). The chosen size is the single source of truth for the
  editor, the answer column and the settings preview, so line-height and
  baseline math always use the real font.

### Answer column

| Control | Values | Effect |
| --- | --- | --- |
| Alignment | Leading / Trailing | Where answers sit inside the fixed-width answer column. |
| Background | Neutral / Sand / Slate / Sage / Blush | The column's surface color. Answer text stays high-contrast on every choice. |

### Syntax colors

Eight syntax roles are individually styled:

`numbers`, `operators`, `variables`, `units`, `specifiers`, `headings`,
`comments`, `labels`.

Each role has:

- **preset swatches** — Standard Text, Cyan, Green, Pink Purple, Blue, Money
  Purple;
- **Custom** — an arbitrary opaque color picked with the system color picker,
  stored as canonical sRGB (`R`, `G`, `B` bytes, no alpha);
- **Default** — restores that role's factory preset without touching any other
  role.

**Reset Syntax Colors** restores all eight roles at once. Font and answer
column settings are kept. A live **Preview** block renders the current role
colors as you change them.

The money-marker color, answer-token color and caret color are not part of the
role set — they stay fixed by design.

## About

The About page is the app's identity AND its update home:

| Item | Behaviour |
| --- | --- |
| Identity hero | A centered block with the current app icon (the same packaged preview the chooser uses, following the chosen Dark/Light icon live), the name "Numlex" and the localized version read at runtime from the bundle (`CFBundleShortVersionString`, with a development fallback). No redundant "Application" heading. |
| Documentation | A native bordered link to `https://numlex.tech/docs/`. |
| GitHub | A native bordered link to `https://github.com/Qulierm/Numlex`. |
| Check for Updates… | One SettingsRow action whose trailing button ("Check Now", localized) runs Sparkle's user-initiated check. It is disabled exactly when `canCheckForUpdates` is false. |
| Automatically check for updates | The native switch over Sparkle's OWN preference (`SUEnableAutomaticChecks` in the app's `NSUserDefaults`) — never copied into `AppSettings`/`.nlx`. |

The generic security paragraph was removed from the UI; the HTTPS + EdDSA signature
guarantee is enforced by the updater implementation and the packaging policy scripts
and is documented in [UPDATES.md](UPDATES.md).

The identity is one combined accessibility element; the update button and the switch
stay separately focusable. When the build lacks the packaged update metadata
(`swift run Numlex`, or a missing feed/key), the group explains why in plain language
and stays disabled instead of failing; the automatic-check flag is deliberately
**not** part of `AppSettings` or `.nlx`. See [UPDATES.md](UPDATES.md) for the trust
chain, the endpoints and the release workflow.

## Answer context menu

Right-click (or Control-click) an **answer** for its native menu. The menu
exists only for rows that have one: quiet lines (blank, header, skipped),
malformed money/date/function errors and the weather-unavailable row offer no
menu at all.

| Item | Applies to | Behaviour |
| --- | --- | --- |
| **Copy Answer** | answers with a menu | Copies the exact displayed value. |
| **Round** (0…10 dp slider) | eligible numeric answers (the slider appears only where rounding applies) | Re-rounds just this answer, independent of the global 2…10 rounding. The source line is untouched. |
| **Number Format** | numeric answers | A local notation for this answer; **Default** clears the override. |
| **Reset Formatting to Defaults** | answers that carry an override | Appears only when an override exists; clears it. |
| **Delete Line** | answers with a menu | Removes the source line of that answer. |

The menu is fully native and follows the system appearance in Light and Dark.
A local override changes only that answer's rendering: never the value, a
token that references the line (tokens render with their own/global format), a
dependency or a total.

## Line highlights

Line highlights are **not** part of the answer context menu. They are applied
from:

- the app menu **Format → Highlight** (None, Yellow, Orange, Green, Blue,
  Purple, Pink), and
- the editor's text context menu.

Both target the **caret's logical line** (or every selected logical line), so
lines without an answer — headings, comments, prose — can be highlighted too.

- A highlight belongs to a line's stable identity, not its position, so it
  follows the line when lines are inserted or removed above it.
- Highlights persist in the sheet (`.nlx`) and are sanitized on load: a stale
  identity is dropped and, for a duplicate entry, the first valid color wins.
- Highlight is decoration only: it never affects evaluation, answers or tokens.

## Layout contracts

| Contract | Value |
| --- | --- |
| Answer column width | 200 pt |
| Line-number gutter | with line numbers on: 54 pt indent (36 pt gutter + 18 pt leading); hidden: 18 pt — the gutter is fully reclaimed, and toggling never accumulates drift |
| Total bar vs inline `total` | the bottom Total panel is dimension-agnostic: it sums the evaluated magnitude of every ordinary scalar answer row once (unitless numbers, unit-bearing quantities such as `2 kg`, money such as `$3`, named scalars and exact integers) into one plain unitless value — no unit conversion, no FX normalization and no unit/currency suffix — and excludes inline `total` rows so the two never double-count; inline `total` lines are a separate section-scoped command that is always active and still sums only unitless scalars |

## Persistence

- Every preference is written locally in the app's settings store; the app is
  fully functional offline and no setting is uploaded.
- Sheet-level data (per-answer overrides, line highlights, sheet content) lives
  with the sheet and its `.nlx` export.
- Constants and custom units are app-global and are never embedded in `.nlx`.
