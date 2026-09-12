# Export and print

This document describes Numlex's sheet export and printing contracts on the
current `main` branch. It is written for authors of the published documentation:
every claim here is pinned by the Swift source and the canonical engine tests.
Released builds may lag behind `main`.

## File menu

The File menu owns exactly these sheet commands:

| Command | Shortcut | What it does |
| --- | --- | --- |
| **Import Sheet…** | ⌘I | Opens a `.nlx` file as a new sheet (unchanged) |
| **Export Sheet (.nlx)…** | ⌘E | Writes the portable `.nlx` document (unchanged) |
| **Export Sheet as PDF…** | — | Opens the PDF export options sheet, then the native save panel |
| **Print…** | ⌘P | Opens the same options sheet, then the standard macOS print panel |

There is exactly one Print… item, in the standard File-menu position, and it is
never duplicated by the system. `.nlx` and PDF are distinct, unambiguous items.

## One snapshot, one renderer

When the options sheet opens, Numlex captures the selected sheet and **all**
app-global evaluation and presentation contexts in one immutable snapshot:

- the full sheet is resolved first (`resolveSheet`), so variables, references,
  tokens, inline totals and every lane keep working exactly as on screen;
- syntax spans are classified from the same captured pass (same date context,
  weather/geo snapshots, unit and financial contexts);
- per-line precision and notation are read through the stable line UUIDs
  (`AnswerDisplay.displayText`), and persistent highlights travel by UUID too;
- the footer Total uses `SheetFooterTotal.aggregate` over the **exported
  evaluated rows only** — never formatted-string sums, and inline `total` rows
  are never double-counted. With the full range the Total is the live footer.

Both the PDF writer and the print operation draw that one snapshot through one
deterministic paginated renderer. The editor view is never screenshotted,
mounted, mutated or scrolled: the live document, line IDs, references,
highlights, selection, caret and typing state are untouched by presenting,
cancelling, exporting or printing.

## Options

Every option is **session-only** — it never enters `AppSettings`, the store or
`.nlx`. The last choices are kept while the app is running and clamped to each
newly selected sheet (a stale line range can never become invalid on a shorter
sheet).

| Option | Default | Behavior |
| --- | --- | --- |
| Font family | Notebook font | Any installed family; a missing family falls back to the notebook font |
| Face | Regular | Faces of the chosen family; a missing face falls back to the family's first face |
| Size | Current notebook size | 8…36 pt |
| Syntax highlighting | On | On: the existing semantic roles and print-safe colors; Off: readable monochrome body text (token capsules stay legible) |
| Line numbers | On | The ORIGINAL 1-based source numbers; numbers are never renumbered after filtering |
| Show total | On | The footer Total once, after the final exported row; it may start a new page |
| Hide comments | Off | Drops the evaluator's `//` comment rows entirely |
| Hide `#` markers | Off | Strips one leading `#` plus at most one separator space; the heading role, typography and content survive |
| Lines | All | All, or an inclusive 1-based From/To range; invalid or empty ranges show an inline message and disable the action |

If range + filters leave nothing printable, the action is disabled and
explains why — a blank or corrupt PDF is never produced.

## Page layout

- White printable pages on the locale-appropriate default paper from
  `NSPrintInfo`, with sensible margins.
- A sheet-title header and an `N / M` page label on every page.
- The original source line numbers in an optional gutter.
- Expression and answer columns; `#` heading typography; persistent
  highlight fills; wrapped text; rows aligned line by line.
- Inline answer tokens are drawn as the same capsule labels the editor shows
  (each U+FFFC maps to its live `TokenResolution`; a broken token shows its
  remembered `Line N`). No replacement-character glyph is ever written.
- Width is guaranteed, not clipped: the layout and the renderer consume the
  SAME resolved inline text, so a token's label **and its capsule padding**
  are reserved while wrapping, and neither column can spill into the other or
  past a margin. A label longer than its column fragments between extended
  grapheme clusters (each fragment keeps its capsule), and a long unbreakable
  word (an identifier, URL or numeric string) hard-breaks the same way —
  surrogate pairs and composed sequences are never split. A defensive cell
  clip can only ever hide a single grapheme wider than its whole column.
- Rows stay intact when they fit; only a single row taller than the page body
  is fragmented safely. Page breaks are deterministic.
- The PDF carries the sheet title as its document title and **Numlex** as
  author/creator. Writing is atomic: a failed or cancelled save leaves no
  partial file.

## Privacy and offline behavior

Export and print are completely offline: no network request, no clipboard
access, no analytics, and no data leaves your Mac except to the destination
you choose in the save panel (or the printer you select). Printing uses the
standard macOS print panel with its normal page controls. Cancelling the
options sheet, the save panel or the print panel changes nothing.
