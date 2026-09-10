# Settings and appearance

This document describes Numlex's settings and appearance contracts on the
current `main` branch. It is written for authors of the published
documentation: every claim here is pinned by the Swift source and the
canonical engine tests. Released builds may lag behind `main`.

Settings are organized into **five native tabs**, each one readable column of
grouped rows with native switches, pickers and sliders. Nothing here is
cloud-synced; every preference is stored on your Mac.

| Tab | Icon | Owns |
| --- | --- | --- |
| **General** | gear | Interface language, Light/Dark appearance, notebook window behaviour, currency-rate attribution |
| **Editing** | pencil tip | Operator helpers and automatic insertions — everything that rewrites text as you type |
| **Numbers** | globe | Regional number format, paste conversion, how answers are displayed and copied |
| **Constants** | function | Global constants and custom units (one segmented surface) |
| **Styling** | paintbrush | Typography, answer column, syntax colors, live preview |

The tab title stays the native System Settings convention (General, Editing,
Numbers, Constants, Styling).

## General

### Interface

| Control | Values | Notes |
| --- | --- | --- |
| Interface language | the app's shipped languages | Localizes the UI only — it never changes the numeric format. |
| Appearance | Light / Dark | Applies to the whole app immediately (one persisted settings write). |

### Notebook

| Control | Default | Behaviour |
| --- | --- | --- |
| Line numbers | on | Shows the line number beside each input line. |
| Hide sidebar button when collapsed | off | Hides the toolbar button while the sidebar is collapsed; reopen the sidebar with **⌃⌘S** (Control-Command-S) or View → Toggle Sidebar. |
| Show total bar | on | Hides the sheet's bottom Total panel. Inline `total` lines keep evaluating and rendering — the toggle never disables the command. |

### Updates

| Control | Behaviour |
| --- | --- |
| Check for Updates… | Starts Sparkle's standard update check (the same action as the app menu item). Disabled while a check is running. |
| Automatically check for updates | Sparkle's own persisted preference (`automaticallyChecksForUpdates` in the app's `UserDefaults`). Scheduling follows Sparkle's defaults (about every 24 hours, with its own consent prompt); Numlex never forces a launch-time check. |

When the build lacks the packaged update metadata (`swift run Numlex`, or a
missing feed/key), the group explains why in plain language and stays
disabled instead of failing. The automatic-check flag is deliberately **not**
part of `AppSettings` or `.nlx`. See [UPDATES.md](UPDATES.md) for the trust
chain, the endpoints and the release workflow.

The tab's footer is an understated, non-interactive attribution line for the
currency-rate source (`open.er-api.com`); it is not a setting.

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
| Total bar vs inline `total` | the bottom Total panel sums the sheet's unitless answers and is toggled on the General tab; inline `total` lines are a separate sheet command that is always active |

## Persistence

- Every preference is written locally in the app's settings store; the app is
  fully functional offline and no setting is uploaded.
- Sheet-level data (per-answer overrides, line highlights, sheet content) lives
  with the sheet and its `.nlx` export.
- Constants and custom units are app-global and are never embedded in `.nlx`.
