# AGENTS.md — working in the Numlex repository

Orientation and operating guide for coding agents. Applies to the **whole
repository** unless a future nested `AGENTS.md` overrides it (closest file wins
for its subtree).

## Read this first

- Read the code before changing it; the source and tests are the primary
  sources of truth. Change the smallest correct surface.
- Never release, bump the version, move a tag, edit release assets, publish an
  appcast, or push the Homebrew tap without explicit, per-task authorization
  (section 3.7).
- `git status` first — and again before committing. Two untracked items
  (`Examples/`, root file `Numlex`) are intentional and must never be
  added, modified or deleted.
- Prefer existing precedent: most contracts are pinned by tests, usually pure
  engine cases or source-contract cases.

## Snapshot (2026-09-25)

These facts **age** — re-verify with git and the release endpoints before
relying on them, especially before any release task.

| Fact | Value |
| --- | --- |
| App version (`Sources/NumlexApp/Resources/Info.plist`) | `4.9.5` (`CFBundleShortVersionString` = `CFBundleVersion`) |
| App release commit | `43b09398d9d757506946b318145e35ac61c9786c` (release commit of annotated tag `4.9.5`) |
| Current release | GitHub [Qulierm/Numlex `4.9.5`](https://github.com/Qulierm/Numlex/releases/tag/4.9.5), annotated tag `4.9.5` (peels to `43b0939`), release id `RE_kwDOMGYWT84Xoloc`, published `2026-09-25T10:34:41Z` |
| Release DMG | `Numlex-4.9.5-macOS-arm64.dmg`, 10,796,720 bytes, SHA-256 `47228bb2ce0e45be294b529a5b879df2b51d07a7d9c34ea898176729c48861b9` |
| `SHA256SUMS` asset | 95 bytes, digest `sha256:c3506f90aa034013f1f45bc5cc53743020929febd95aa141f9690dfdb2647306` |
| Engine suite | 1429/1429 (observed 2026-09-25; runner output is authoritative) |
| Website (`../NumlexWeb`) HEAD | `01d0650822d818fbd669cd54ecd7b9a79d3f1abf` (private repo) |
| Homebrew tap HEAD | `011bedf8006c9b4766d019efc62e6d814a177584` |
| Release notes / feed | <https://numlex.tech/Numlex-4.9.5-macOS-arm64.md> · <https://numlex.tech/appcast.xml> |
| Previous release (historical) | `4.9.4.1` at `92db3d3d5f4a2787610c6d086cbb68927f91db31`, DMG `744fc564df6802db8ebb6fa9d3da5081a28d17b8a73593b5e4b006497ea7b4ee` (10,792,648 bytes) — immutable |

Verify with: `git rev-parse HEAD && git ls-remote origin main`,
`gh release view 4.9.5 --repo Qulierm/Numlex --json assets`,
`swift run NumlexTests | tail -1`.

---

# 1. Project scope and repository map

## 1.1 What Numlex is

A **native macOS notepad calculator**: plain-text lines evaluate as you type,
with results in a separate answer column.

- **Native**: SwiftUI shell + Swift 6.2 (package tools-version 6.0); the editor
  core is an AppKit `NSTextView` bridged via `NSViewRepresentable`. No web
  view, no Electron, no JavaScript, no runtime scripting.
- **arm64, macOS 26+**, ad-hoc signed and **not notarized** (deliberate).
- **Offline-first**: calculations and catalogs are local, from versioned
  hash-checked resource bundles. Network is limited to background currency
  rates and the Open-Meteo lookups that explicit `weather in …` /
  geography lines request.
- **Deterministic**: strict typed parser/evaluator, no silent coercion.

## 1.2 Package products, targets and dependencies

| Product | Kind | Path | Role |
| --- | --- | --- | --- |
| `NumlexApp` | executable | `Sources/NumlexApp` | The macOS app (SwiftUI + AppKit bridge, settings, export UI). Links Sparkle. |
| `NumlexCore` | library | `Sources/NumlexCore` | Pure dependency-free engine: parser, evaluator, models, catalogs, persistence, services, export. |
| `NumlexTestKit` | library | `Tests/NumlexTestKit` | Portable `EngineCase` arrays shared by both runners. |
| `NumlexCoreTests` | test target | `Tests/NumlexCoreTests` | Swift Testing suite (`swift test`, full Xcode toolchain). |
| `NumlexTests` | executable | `Tests/NumlexTests` | Standalone runner (`swift run NumlexTests`, CLT-only friendly). |

The only external dependency is **Sparkle, pinned exactly to `2.9.6`**; only
`NumlexApp` links it and the core stays dependency-free. `Package.resolved` is
gitignored.

`NumlexCore` declares five `.copy` resource directories under
`Sources/NumlexCore/Resources/` (`NumlexTimezones`, `NumlexHolidays`,
`NumlexIncomeTax`, `NumlexCPI`, `NumlexTax`). `NumlexApp` copies three icon
resources and excludes `Resources/Info.plist` / `Resources/AppIcon.icns` from
its bundle (consumed by `Scripts/build-app.sh` instead).

## 1.3 Directory and file map

| Path | Role |
| --- | --- |
| `Package.swift` | Products, targets, resources, Sparkle pin, test-toolchain wiring. |
| `Sources/NumlexApp/Entry.swift` | The real `@main` (`NumlexEntry`): `--validate-packaged-resources` or `NumlexApp.main()`. |
| `Sources/NumlexApp/NumlexApp.swift` | SwiftUI `App` scene, `AppDelegate`, welcome/curtain reveal stages, menus. |
| `Sources/NumlexApp/AppModel.swift` | The one observable state: sheets, selection, settings, folders, rates, weather/geo, random epochs, persistence, appearance/icon. |
| `Sources/NumlexApp/Editor/NotebookEditor.swift` | AppKit bridge: `NSTextView`/TextKit, editing hooks, token insertion, measurements, scroll/bounds. |
| `Sources/NumlexApp/Views/ContentView.swift` | Editor + divider + answer column; shared resolved inputs; `topOffset` and split geometry. |
| `Sources/NumlexApp/Views/AnswerColumnView.swift` | Answer rows, tokens, wheel forwarding, footer Total, motion model. |
| `Sources/NumlexApp/Views/AnswerColumnResizeHandle.swift` | 1 pt divider, 12 pt hit zone, cursor handling, drag-session wiring. |
| `Sources/NumlexApp/Views/SettingsView.swift` | All seven Settings pages and `SettingsDestination`. |
| `Sources/NumlexApp/Views/SidebarView.swift` | Sheet list, folder tabs, glass tone, rename/delete/reorder. |
| `Sources/NumlexApp/Views/WelcomeView.swift`, `WelcomeRenderers.swift` | First-launch calculation bloom and curtain. |
| `Sources/NumlexApp/Export/` | Export options sheet and export font catalog. |
| `Sources/NumlexApp/UpdateController.swift` | The one Sparkle integration. |
| `Sources/NumlexApp/AppIconController.swift`, `AppAppearanceController.swift` | Process-wide icon/appearance application. |
| `Sources/NumlexApp/Diagnostics.swift`, `MotionEvidence.swift` | Opt-in tracing (`--trace`, `--motion-evidence`); inert without flags. |
| `Sources/NumlexCore/Engine/Evaluator.swift` | `evaluateSheet` — sheet evaluation entry point. |
| `Sources/NumlexCore/Engine/ReferenceEvaluation.swift` | `resolveSheet` — token-aware resolution for UI and export. |
| `Sources/NumlexCore/Engine/TypedEnvironment.swift`, `Types.swift` | Typed env and `LineResult` types. |
| `Sources/NumlexCore/Engine/` (rest) | Lanes: arithmetic, units, money, dates/timezones, finance, CPI, tax, statistics, Package 7 aggregates, formatting, highlighting. |
| `Sources/NumlexCore/Models/` | `Sheet`, `Styling`, `Settings`, persistence payloads, `AnswerReference`, `AnswerColumnGeometry`, `FooterTotalLayout`, `ResourceLocator`, geometry/presentation. |
| `Sources/NumlexCore/Services/` | `FirstLaunch`, `Persistence` (paths + `--data-dir`), `RatesService`, `WeatherService`. |
| `Sources/NumlexCore/Units/` | Unit catalog, currencies, the five embedded catalogs, custom units/timezones. |
| `Sources/NumlexCore/Export/` | `ExportSnapshotBuilder`, `ExportTypes`, `PDFExportRenderer`, layout/print view. |
| `Sources/NumlexCore/Localization.swift` | All six UI languages (`L10n.t(key, language:)`). |
| `Sources/NumlexCore/Resources/` | Committed offline datasets + `sources.json` manifests (15 tracked files). |
| `Tests/NumlexTestKit/` | One `EngineCase` array file per area; framework-free. |
| `Tests/NumlexTests/main.swift` | Standalone runner concatenating every case array. |
| `Tests/NumlexCoreTests/EngineTests.swift` | Swift Testing wrappers, one `@Test(arguments:)` per array. |
| `Scripts/` | Build/packaging/validation tooling (3.2). Tracked capitalization is `Scripts/`; `scripts/` resolves on case-insensitive filesystems. |
| `docs/` | The four canonical documents + `docs/README.md` index. |
| `SYNTAX_REFERENCE.md` (root) | Pointer to `docs/SYNTAX_REFERENCE.md`. |
| `README.md` | User overview, feature summary, build/download. |
| `WEBSITE_BRIEF.md` | Marketing numbers/copy constraints for the website repo. |
| `Assets/` | Icon sources + compiled `Assets/AppIcon.compiled/Assets.car` (2.11). |
| `dist/` | Local DMG output (gitignored); never the source of published bytes. |
| `.build/` | SwiftPM products incl. assembled `.build/Numlex.app` (gitignored). |
| `.github/workflows/build-modern-app-icon.yml` | Manual CI compiling the Liquid Glass `Assets.car` on `macos-26`. |
| `LICENSE` | MIT. |

## 1.4 Adjacent repositories (only edit with an explicit task)

- **`../NumlexWeb`** — the website (`https://numlex.tech`), private GitHub repo
  `Qulierm/NumlexWeb` (Astro). Owns the Sparkle feed
  (`public/appcast.xml`), release-notes pages
  (`public/Numlex-<version>-macOS-arm64.md`), the release snapshot
  (`src/data/github-releases.generated.json`), doc provenance pins
  (`src/data/docs-sources.ts`, `docs-source-hashes.ts`) and the website docs
  locales. Has its own tests (`npm test`, 169 at snapshot), build and tools.
- **`Qulierm/homebrew-tap`** — one cask, `Casks/numlex.rb`: version, public DMG
  `sha256`, immutable URL, `livecheck`, `auto_updates true`.

The app repo never reads the website at build time. Release order: GitHub
release → appcast → website snapshot/locales → Homebrew → public verification
(3.7).

## 1.5 Locales — the sets differ

- **App UI**: `en`, `ru`, `de`, `fr`, `it`, `zh` (six), all in
  `Sources/NumlexCore/Localization.swift`, English fallback.
- **Website docs**: English root plus `de`, `es`, `ru`, `zh` — the website has
  `es` but not `fr`/`it`.

Never assume the sets match. New user-facing strings update **all six** app
languages; English doc edits may require website pin refreshes (3.6).

## 1.6 Sources of truth, in precedence order

1. **Source code + tests** — actual behavior and enforced contracts win over
   prose.
2. **The four canonical documents** in `docs/` — written contracts, updated in
   the same commit as behavior: [docs/SYNTAX_REFERENCE.md](docs/SYNTAX_REFERENCE.md)
   (Russian, full language reference),
   [docs/SETTINGS_AND_APPEARANCE.md](docs/SETTINGS_AND_APPEARANCE.md),
   [docs/EXPORT_AND_PRINT.md](docs/EXPORT_AND_PRINT.md),
   [docs/UPDATES.md](docs/UPDATES.md) (English).
   [docs/README.md](docs/README.md) is the index and states the
   `main`-vs-release rule.
3. **This file** — orientation only.
4. **`README.md`** — user overview; intentionally lags a little (its suite
   count is older than the runner's). Do not resync it unless asked.

The canonical docs describe current `main`; releases may lag, and docs say so
explicitly when behavior is newer than the release.

## 1.7 Git hygiene

- Inspect first: `git status --short`, `git log --oneline -5`,
  `git rev-parse HEAD && git ls-remote origin main`.
- **Never add/modify/delete**: `Examples/` (`Bubble.swift`, `Settings.swift`)
  and the root file `Numlex`. Because they are untracked, **never
  `git add -A` / `git add .`** — stage explicit paths and re-check status
  before committing.
- Never reset, rebase, rewrite history or force-push; never move a published
  tag; preserve unrelated in-flight commits.
- Ignored outputs: `.build/`, `dist/`, `*.app`, `Package.resolved`,
  `.DS_Store`, `.idea/`, `*.log`. Releases use `Release Numlex <version>`
  commit titles (3.7).

---

# 2. Architecture and non-negotiable invariants

## 2.1 Runtime entry, first launch, lifecycle

- `Sources/NumlexApp/Entry.swift` is the real `@main` (`NumlexEntry`). The
  opt-in `--validate-packaged-resources` flag runs
  `PackagedResourceValidation.run()` (one line per catalog, non-zero on
  failure) **before any window/store/updater/appearance work**; otherwise it
  calls `NumlexApp.main()`.
- **First launch** is file-presence based (`FirstLaunch.swift`) and evaluated
  **before anything creates the data directory**: no `welcome-v1` marker and
  no prior artifact (`store.json`, `rates.json`, `weather.json`,
  `locations.json` — even corrupt) → welcome; any prior artifact → no welcome,
  best-effort marker write without touching them; marker present → no welcome.
- The editor mounts only after **Get Started**; the notebook/TextKit are not
  created behind the welcome and focus lands after the curtain clears
  (`RevealStage`). There is **no “Replay Welcome”** feature.
- `AppDelegate` applies the persisted appearance/icon once, captures the
  primary bundle icon first, and only starts opt-in diagnostics when flagged.

## 2.2 AppModel — the one state owner

`AppModel` (`@Observable`) owns `sheets`, `selectedIndex`, `folders`,
`activeGroup` (the single presentation-only sidebar filter), `settings`,
rates/weather/geo publish state, the ephemeral per-sheet random stores +
`dynamicEpoch`, and the lazy main-actor `UpdateController` (disabled
gracefully without packaged metadata, e.g. `swift run`).

- `persist()` writes one `StorePayload` atomically — once per user-visible
  change, never per frame.
- Appearance/icon changes go through `setAppearance(_:)` / `setAppIcon(_:)`:
  one settings write, one persist, one process-wide application.
- A sheet switch re-seeds answer motion and starts a documented new random
  epoch.
- `ContentView` resolves **one** full input set (content, line IDs, references,
  rates, constants, weather/geo, number/unit/temporal/financial/random
  contexts) for both editor rows and the answer column. Never evaluate the same
  sheet twice with different inputs.

## 2.3 Editor and TextKit geometry

`NotebookEditor.swift` owns the `NSScrollView`/`NSTextView` pair and TextKit
bookkeeping; SwiftUI owns the surrounding chrome.

- **One logical row per newline**, including blanks and the trailing line after
  a final newline. `Sheet.lineIDs` stores one stable UUID per logical row;
  answers, overrides, highlights and tokens key off UUIDs, never indices.
- **Measured geometry**: row top/height/baseline come from live text layout.
  The answer column renders at `offset(y: -topOffset)` for pixel-exact 1:1.
- **Sacred state**: caret/selection, IME marked text, focus and scroll must
  survive presentation-only changes; text mutations go through the documented
  edit pipeline.
- **One scroll source**: no independent answer-column scroll view. Raw wheel
  events are forwarded verbatim to the editor's scroll view; its
  `BoundsDidChange` drives `topOffset`.

## 2.4 The answer column and its resize contract

- **Preference**: `StylingPreferences.answerColumnWidth` — app-global,
  persisted, default `AnswerColumnGeometry.defaultWidth` (200), hard bounds
  140...400.
- **Effective width**: `AnswerColumnGeometry.effectiveWidth(preference:availableDetailWidth:)`
  caps the preference so the editor keeps its 280 pt minimum plus the 1 pt
  divider. Rows, wheel catcher, hover map and footer all use the actual width.
- **Divider** (`AnswerColumnResizeHandle.swift`): visible footprint exactly
  1 pt, centered 12 pt transparent hit zone claiming no layout width.
- **Drag**:
  - global coordinates (`DragGesture(minimumDistance: 0, coordinateSpace: .global)`)
    — `.local` moves with the divider and feeds the layout delta back into the
    gesture (this caused a jitter bug; do not regress);
  - one immutable start per drag via `AnswerColumnDragSession` (displayed
    width + pointer x captured at the press);
  - movement is material only at `|delta| >= 1 pt` (`isMaterialDrag`): a click
    makes no live write and no end commit, so a window-capped display width
    cannot replace the stored preference;
  - live `onChange` is in-memory only; `onEnd` fires once per real drag with
    the exact final formula width, applied in memory before one guarded
    persist;
  - the resize cursor is hover-driven and deliberately not popped on drag end
    while the pointer stays over the zone (balanced push/pop).
- **Presentation-only**: width changes never touch content, line IDs,
  references, caret, selection, IME, focus, scroll, evaluation or export.

## 2.5 Evaluation

- **Strict lanes**: typed lanes parse each line's projection and produce typed
  results. No regex patches or guessy fallbacks — extend the right lane and add
  tests.
- `evaluateSheet` produces exactly **one `SheetLine` per logical source line**
  (1:1 contract), quiet lines included; `resolveSheet` is the token-aware
  variant used by UI/export.
- Results are **canonical values, not strings**; formatting happens later in
  the presentation layer.
- Contexts are explicit and injectable (number/regional format, units,
  temporal, financial, random, weather/geo); the UI passes one resolved set.
- Numeric semantics are strict: invalid input yields typed errors; error rows
  never dim the answer column.

### Package 7 lexical contracts

- `# ` at line start = **heading**; a terminal `#tag` marks a row for tag
  aggregates and is stripped from the evaluation projection.
- **Divider**: only an exact `---` (outer spaces/tabs tolerated). `----` is
  **not** a divider — it stays an ordinary expression row
  (`Tests/NumlexTestKit/Package7Cases.swift`).
- `total` = legacy section sum (nearest prior total/heading/divider);
  `subtotal` = sum since the nearest prior **subtotal**, heading or divider (a
  legacy total is not a boundary); `grand total` = sum of successful subtotal
  rows, requires at least two; a divider does not erase the grand list.
- Tag aggregates: `total of #tag`, `average of #tag`, `count of #tag`,
  `median of #tag` — exactly one terminal tag, no trailing garbage.
- `median` with even count averages the middle pair; `stdev` is the **sample**
  standard deviation.
- `rand` / `random number between X and Y`: inclusive, stable per random epoch,
  rerolled only by a semantic edit or explicit Recalculate (⌘R); never
  tokenizable and never propagates through tokens.

## 2.6 Answer tokens and document identity

- A token is exactly one U+FFFC marker in `Sheet.content` (one UTF-16 unit)
  plus an `AnswerReference` sidecar: token id, source **line UUID**, label line
  number, UTF-16 marker location.
- A token always shows its source line's current value (or its remembered
  `Line N` label when the source is gone); no numeric snapshot is truth.
- Positions reconcile from the pre-edit `EditIntent` when available, else a
  content-based fallback. Sanitization after content/lineID mutation keeps
  `lineIDs`, `references`, `answerDisplay` and `highlights` consistent —
  dropping only invalid entries.
- Chains and duplicates are allowed; every row counts once (no dependency-DAG
  dedup). Dynamic `rand` cannot mint or propagate through tokens.
- Display/hover/highlight key off UUIDs, never positions.
- `.nlx` preserves per-sheet metadata (line IDs, references, overrides,
  highlights) and never app-global settings or folders.

## 2.7 Persistence, settings and folders

- One store: `store.json` in the app data directory
  (`~/Library/Application Support/Numlex` by default).
- **Validation override**: `--data-dir <path>` or `NUMLEX_DATA_DIR` redirects
  the whole data directory (store + caches); inert unless passed. Use it for
  any manual launch.
- `StorePayload.currentVersion` is **2**; do not bump casually. Decoding is
  additive and key-by-key tolerant — a missing/malformed field falls back to
  its default without discarding the rest — and never rewrites unchanged user
  data.
- **App-global (never in `.nlx`)**: appearance, icon, language, input
  preferences, styling (fonts, syntax colors, answer-column width/alignment/
  surface), number presentation/regional formats, custom constants, custom
  units, temporal preferences (work hours, holiday region, custom timezones),
  tax configuration, footer statistic.
- **App-local**: sidebar folders (membership on `Sheet.folderID`; never
  exported). **Per-sheet `.nlx` metadata**: title flags, line IDs, tokens,
  rounding overrides, highlights.
- Settings are exactly **seven tiles** (`SettingsDestination`): **General,
  Editing, Numbers, Dates & Times, Constants & Units, Styling, About**.
  Settings changes never mutate editor/document state.
- Fresh installs default to Auto appearance + Dark (primary) icon; a legacy
  store without keys keeps its old behavior. Persisted choices always win.

## 2.8 Totals, tags and statistics

- **Inline** (`InlineTotal.swift`, `SubtotalEngine.swift`): `total`,
  `subtotal` (± percent, optionally named), `grand total`, tag aggregates. Each
  eligible row contributes once; source text is never rewritten.
- **Footer Total** (`SheetFooterTotal.swift`): a different contract — sums the
  evaluated scalar magnitude of every ordinary answer row (no conversion/FX,
  one plain number). Excludes boolean/date/location/DMS, blank/skip/title/
  error and every `isTotal` row (avoids double-counting inline totals).
- `FooterTotalLayout` is pure; callers supply measured widths. Runtime always
  uses the actual container width; its static constants exist only for
  default-width tests.
- The footer statistic (Sum/Average/Count/Median) is app-global, persisted,
  configurable from the floating Total's menu.

## 2.9 Export and printing

- `ExportSnapshotBuilder.build(context:options:)` resolves the **full sheet**
  once (tokens included), then projects the inclusive range and filters onto
  immutable rows. Invalid range or zero printable rows fail explicitly instead
  of producing a blank PDF.
- One renderer (`PDFExportRenderer.swift` + `ExportLayout.swift`,
  `ExportPaginatedPrintView.swift`) draws the frozen snapshot
  deterministically; export never mounts/screenshots the live editor.
- Options are session-only, clamped to the sheet; the exported footer runs over
  exported rows only; writes are atomic and fully offline.

## 2.10 Resources, network and security

**Offline catalogs (five).** `NumlexTimezones`, `NumlexHolidays`,
`NumlexIncomeTax`, `NumlexCPI`, `NumlexTax` under
`Sources/NumlexCore/Resources/`, each with a `sources.json` manifest of
per-file `sha256`. Catalogs verify required files **and** digests at load and
throw on mismatch; `embedded()` maps failure to `nil` (fail closed).

**Resource locator (critical).** `ResourceLocator.swift` is the only
production way to find the bundle. It:

- resolves in fixed order: `Bundle.main.resourceURL/<bundle>` (the standard
  packaged `Contents/Resources`), then SwiftPM-style layouts (`bundleURL`,
  executable sibling, cwd);
- **never** uses the SwiftPM-generated `Bundle.module` accessor — its
  candidates miss `Contents/Resources` and include a developer build path, and
  it traps when both miss. In 4.9.0/4.9.1 this crashed packaged installs on
  first launch; 4.9.2 replaced it. Never reintroduce `Bundle.module` in
  `NumlexCore`, and never put developer-absolute paths in production code;
- returns `nil`/typed errors for missing or corrupt resources — never crashes.

`Scripts/build-app.sh` takes the bundle from the exact `$BIN_PATH` of the
requested configuration (never a `find` over `.build`), installs it to
`Contents/Resources`, and fails closed on missing datasets or a non-`Contents`
app root. `Scripts/relocated-app-smoke.sh` copies the app outside the repo and
proves `--validate-packaged-resources` loads all five catalogs;
`Scripts/validate-dmg.sh` asserts the standard location and rejects root-level
bundles.

**Network.** Currency rates: `https://open.er-api.com/v6/latest/<BASE>` (8 s
timeout, `rates.json` cache, 1 h refresh, last-good table on any failure — the
app never blocks or errors on rates). Weather/geocoding: Open-Meteo
(`geocoding-api.open-meteo.com`, `api.open-meteo.com`) only for lines the user
typed, with last-good caches. No GPS, identifiers or analytics. Privacy claims
live in `../NumlexWeb/src/content/docs/privacy-network.md` and
`docs/UPDATES.md`; changing an endpoint means updating both.

**Update security.** Sparkle 2.9.6; HTTPS-only feed (`SUFeedURL`); EdDSA
archive signature verified **before extraction**
(`SUVerifyUpdateBeforeExtraction`); profiling off. The public key is committed
in the Info.plist; the **private key lives only in the maintainer's login
Keychain (or an offline key file) and must never be printed, copied into the
repo, or committed.** Feed generation: `Scripts/prepare-update-feed.sh`; policy
checks: `Scripts/verify-sparkle-policy.sh`.

## 2.11 Appearance and assets

- Auto (`system`) follows macOS live; Light/Dark apply process-wide through the
  one `AppAppearanceController`.
- Dark is the bundle primary (`CFBundleIconName=AppIcon`); Light is the
  alternate named asset (`AppIconLight`) with the same rendition ladder.
  Settings previews come from packaged resources; changing icons never mutates
  files on disk.
- `Assets/AppIcon.compiled/Assets.car` is compiled by the manual
  `macos-26` “Build Modern App Icon” workflow and committed. Its packaged
  SHA-256 is a protected invariant:
  `be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d`.
  Rebuild via the workflow and update every pinned place deliberately — never
  hand-edit the hash.
- Styling/theme actions are state-safe: they may re-render, never re-edit.

## 2.12 Do not (red flags)

- No `Bundle.module` or developer-absolute paths in production code.
- No second scroll view / independent answer-column scrolling.
- No mixed evaluation contexts on one screen.
- No presentation-only mutations of line IDs, tokens or editor state.
- No formatted strings as evaluation truth; no regex around a lane.
- No `StorePayload.currentVersion` bump, store rewrite or user-data migration
  without an explicit task.
- Never touch `Examples/` or the root `Numlex` file; never `git add -A`.
- No `codesign --deep`; never replace/re-upload published assets.
- Never print or commit the EdDSA private key.
- No “Replay Welcome”, analytics, telemetry or web view.
- Never rebuild over a frozen/published artifact — publish a new version.

---

# 3. Development, testing and release workflows

## 3.1 Change workflow by type

1. **Locate the contract**: source, pinning tests, and the canonical doc
   sentence; update docs in the same commit when behavior changes.
2. **Pure core first**: engine behavior lives in `NumlexCore` with pure,
   injectable APIs; add the pure case, then wire the view.
3. **Minimal, additive changes**: extend case arrays, decode paths and models
   additively; never reorder or rename persisted fields.
4. **Localize**: every new user-facing string lands in all six app languages.
5. **Register tests in BOTH runners** (3.4).
6. **Verify**: `git diff --check`, focused cases, full suite, debug+release
   builds; packaging changes also run the packaging scripts.

### 3.1.1 Definition of a completed action (completion protocol)

A code, UI or behavior task is **not Done because the source compiles**. Before
reporting Done, the task must satisfy the whole completion set below: an
intended diff only (no unrelated files); docs and tests updated for the change;
focused validation of the changed behavior; the full standalone suite
(`swift run NumlexTests`) unless the task explicitly justifies a narrower scope
(state the justification); debug and release builds; one focused commit; a
rebuilt assembled app at `.build/Numlex.app`; the relevant smoke checks; and a
final `git status` plus report. Push only after validation and only when it is
authorized and safe (step 8).

**Required normal order for code work:**

1. Inspect the baseline: `git status`, `git log --oneline -3`,
   `git rev-parse HEAD && git ls-remote origin main`.
2. Edit the source and add/update the focused tests.
3. Run the full standalone suite (`swift run NumlexTests`), `swift build`,
   `swift build -c release` and `git diff --check`.
4. Stage the intended files explicitly (never `git add -A`; re-check
   `git status`) and make one focused, imperative commit.
5. From the committed, clean tree assemble the release app:
   `bash Scripts/build-app.sh release` — invoke it with `bash` so the
   executable bit is irrelevant. This produces/replaces `.build/Numlex.app`.
6. Verify at minimum that the app exists and its executable runs, plus the
   packaged version, minOS, architecture, signature and resource contracts
   where relevant. Packaging/resource changes additionally run
   `Scripts/relocated-app-smoke.sh`; UI checks may launch the app with an
   isolated `--data-dir` (never the user's real data).
7. If post-commit validation fails, fix it in another clear commit (amend ONLY
   before any push and only when the commit ownership is certain — prefer a
   follow-up commit), then rebuild the app. Never claim Done with a stale app.
8. Push only once the commit **and** the assembled-artifact validation are
   green, then verify `HEAD == origin == ls-remote`. If unrelated local commits
   exist, do not push them silently: report the blocker and ask for
   authorization.

**`.build/Numlex.app` is an ephemeral, gitignored local deliverable.** A
`swift build -c release` alone builds a bare binary, NOT the assembled app;
`Scripts/build-app.sh release` is what packages the Info.plist, icons, offline
resource bundle, Sparkle framework and ad-hoc signatures. Any later source
edit makes the existing app stale — rebuild before handoff or reporting Done.

**Do not install or mutate the user's environment**: never copy the app to
`/Applications`, run `lsregister`, remove quarantine, replace the user's app,
or touch Application Support without explicit authorization. Runtime checks
use a temporary data directory and the `.build` app (or a temporary copy).

**Completion tiers:**

- **Documentation-only** tasks: diff/link/spelling/path audit plus a focused
  commit; no app build or full suite is required unless the docs change
  commands/contracts or the user asks.
- **Tests-only / core-only** changes still count as code and normally assemble
  the app when they affect a shipped target. If a task reasonably scopes the
  completion set down, state that scoped exception explicitly in the report.
- **Packaging changes** additionally run the relocated smoke, build the DMG
  and validate the DMG — only when the task scope authorizes packaging work.
  Releasing is the separate, explicitly gated flow in section 3.7.

**Commit convention:** one logical completed action per commit; imperative,
concise subject (for example `Fix packaged resource lookup`,
`Document completion workflow`); never mix unrelated files; never
amend/rewrite another author's or an in-flight commit.

**Final report template** (copyable):

```text
Status: Done | Blocked | Needs restart | Implemented, not delivered
Commit: <sha> <subject>
Files: <changed paths / count>
Tests: <exact suite counts / focused cases>
Build: .build/Numlex.app (<configuration>, version <x.y.z>)
Runtime/packaging validation: <smoke/diagnostic results, or "not run">
Git state/push: <HEAD vs origin vs ls-remote; push status/blocker>
Limitations: <host wedge, skipped checks, scoped exceptions>
```

Never claim a GUI validation you could not perform (the zero-window host wedge
is the usual case). When commit, app or push requirements are still pending,
label the task **implemented but not delivered** — honestly, in those words —
instead of Done.

## 3.2 Commands

```sh
swift build                    # debug
swift build -c release         # release
swift run NumlexTests          # standalone engine suite (CLT friendly)
swift test                     # Swift Testing suite (full Xcode toolchain)

git diff --check
git status --short

Scripts/build-app.sh release               # assembles .build/Numlex.app
Scripts/relocated-app-smoke.sh             # copied app must load all 5 catalogs
Scripts/build-dmg.sh                       # dist/Numlex-<version>-macOS-arm64.dmg
Scripts/validate-dmg.sh dist/<file>.dmg    # strict plain-DMG contract
Scripts/validate-appcast.sh <appcast> --archive <dmg> --expect-version <v> --expect-min-os 26.0
```

Notes: use the tracked `Scripts/` capitalization (lowercase resolves on
case-insensitive filesystems). `--data-dir <path>` / `NUMLEX_DATA_DIR` isolate
runtime state. Opt-in diagnostics: `--trace <dir>`, `--motion-evidence <dir>`
(inert otherwise).

## 3.3 Testing strategy

- **Pure cases** for engine behavior: inputs → canonical values, formatting,
  errors, hostile/malformed input, boundaries.
- **Source-contract cases** read repo source and assert structural invariants
  (no `Bundle.module`, global drag coordinates, exact bin path, immutable
  appcast pins). Use them when behavior must not regress but is hard to unit
  test.
- **Backward compatibility**: older/missing/malformed payloads decode to
  documented defaults; settings decode stays additive.
- **State invariants** (geometry, canonical values, token identity, persistence
  counts) are testable without a GUI — prefer them over screenshots.
- **Packaging tests**: `PlainDMGCases.swift` + the relocated smoke pin the
  packaged contract; validate the public artifact when releasing.
- The suite count grows; never “fix” docs to match — point at runner output.

## 3.4 Test registration mechanics

`Tests/NumlexTestKit/` exports `public let <area>Cases: [EngineCase]` per file.
Register a new array in **both**:

1. `Tests/NumlexTests/main.swift` — append `+ <area>Cases` to `allCases`.
2. `Tests/NumlexCoreTests/EngineTests.swift` — add
   `@Test(arguments: <area>Cases) func <area>Case(...)`.

Miss one and either the standalone runner or `swift test` silently skips those
cases.

## 3.5 Runtime validation and host limitations

- Isolate runtime state with `--data-dir` / `NUMLEX_DATA_DIR` for every manual
  launch.
- A host **zero-window wedge** can occur in agent environments: the process
  starts but never registers a window with `System Events`. Do not hack around
  it in the product — report the limitation honestly and rely on deterministic
  tests (relocated smoke, diagnostics, pure cases). Never claim a live GUI
  check you could not perform, and never use visible window counts as
  pass/fail; use exit codes and printed diagnostics.

## 3.6 Documentation ownership

- Behavior change → update the matching canonical doc in the same commit
  (syntax → `docs/SYNTAX_REFERENCE.md`; settings/appearance →
  `docs/SETTINGS_AND_APPEARANCE.md`; export/print → `docs/EXPORT_AND_PRINT.md`;
  updates → `docs/UPDATES.md`).
- The website (`../NumlexWeb`) pins the app revision, blob SHA-256/bytes/lines
  and a milestone (`src/data/docs-sources.ts`, `docs/SYNTAX_DOCUMENTATION.md`,
  verified by `tests/syntax-docs.test.ts`). Refresh those pins in the website
  repo as a separate explicit step when app docs change.
- `WEBSITE_BRIEF.md` owns marketing numbers (they stay on the released
  snapshot). Keep syntax docs free of implementation trivia; packaging
  contracts belong in `README.md` / `docs/UPDATES.md`.

## 3.7 Packaging and release — gated

> **Release actions are gated.** Never bump the version, tag, publish a
> release, upload assets, update the appcast, push the tap or publish website
> release metadata without an explicit per-task authorization. Below is the
> authorized flow, not a standing permission.

1. **Version source**: `Sources/NumlexApp/Resources/Info.plist` (both keys).
   Update current-release wording in `README.md`, `docs/README.md`,
   `docs/UPDATES.md`; commit as `Release Numlex <version>`; push main.
2. **Tag**: annotated tag at the exact release commit; push; verify the peeled
   remote tag equals app HEAD. Never move it again.
3. **Build from the clean tagged commit**: `Scripts/build-dmg.sh` (rebuilds the
   release app; `NUMLEX_USE_BUILT_APP=1` is for local validation only).
4. **Validate and freeze**: `Scripts/validate-dmg.sh` (27 checks at snapshot:
   plain root of exactly `Numlex.app` + `Applications`, signatures, Sparkle
   metadata, five datasets at the standard location, no root bundles, exact
   `Assets.car`), `Scripts/relocated-app-smoke.sh`, then size + SHA-256 and a
   one-line `SHA256SUMS` with the canonical filename. Never rebuild after
   freezing.
5. **Publish the GitHub release once** (frozen DMG + `SHA256SUMS`), then
   re-fetch and confirm the public name/size/digest equal the frozen bytes.
6. **Appcast only after the asset is live**:
   `Scripts/prepare-update-feed.sh --dmg <final> --version <v>
   --download-url-prefix https://github.com/Qulierm/Numlex/releases/download/<v>/
   --release-notes <md> --output <web>/public/appcast.xml`, then validate it
   cryptographically against the published archive. The EdDSA private key stays
   in the Keychain/offline key file.
7. **Website**: publish the exact notes in `../NumlexWeb/public/`, refresh the
   snapshot (`npm run releases:sync`), move current-version language across the
   five website locales, run its full gate (`npm test`, `npm run check`,
   `npm run build:production`, `npm run media:verify`, link audit).
8. **Homebrew**: fresh-clone the tap; bump `Casks/numlex.rb` (version, exact
   public SHA, immutable URL); keep `livecheck`/`auto_updates`; verify Ruby
   syntax + `brew style`; push.
9. **Public end-to-end**: freshly download the public DMG (not the local
   file); verify size/SHA/`SHA256SUMS`; run `validate-dmg.sh` and the relocated
   diagnostic on the mounted public app; validate the live appcast
   (`https://numlex.tech/appcast.xml`) against that download; re-confirm
   historical releases are untouched.

Immutable history:

- **Published assets are immutable** — never replace, re-upload, retag or
  delete a released archive or tag; fix post-publication problems with a **new
  version**. Historical releases (4.9.0/4.9.1/4.9.2 at snapshot) and their
  digests are frozen facts. The one documented exception: factual corrections
  to a release **body text** (assets/hashes untouched).
- The DMG is **plain**: root exactly `Numlex.app` + `Applications` symlink, no
  `.background`/`.DS_Store`/volume icon/Finder layout; app root exactly
  `Contents`; ad-hoc signing with explicit nested Sparkle signing (never
  `codesign --deep`); arm64; minOS 26.0; Sparkle 2.9.6.

## 3.8 Release snapshot (non-authoritative, time-stamped)

At 2026-09-25: current release **4.9.5** at release commit
`43b09398d9d757506946b318145e35ac61c9786c` (annotated tag `4.9.5`); DMG
`Numlex-4.9.5-macOS-arm64.dmg` (10,796,720 bytes, SHA-256
`47228bb2ce0e45be294b529a5b879df2b51d07a7d9c34ea898176729c48861b9`);
`SHA256SUMS` digest `c3506f90aa034013f1f45bc5cc53743020929febd95aa141f9690dfdb2647306`.
Engine suite 1429/1429. Release:
<https://github.com/Qulierm/Numlex/releases/tag/4.9.5> · feed:
<https://numlex.tech/appcast.xml> · notes:
<https://numlex.tech/Numlex-4.9.5-macOS-arm64.md> · website:
`01d0650822d818fbd669cd54ecd7b9a79d3f1abf` · tap:
`011bedf8006c9b4766d019efc62e6d814a177584`.

Previous releases 4.9.0/4.9.1/4.9.2/4.9.3/4.9.4/4.9.4.1 remain immutable and
untouched (4.9.4.1 is `92db3d3d5f4a2787610c6d086cbb68927f91db31`, DMG
`744fc564df6802db8ebb6fa9d3da5081a28d17b8a73593b5e4b006497ea7b4ee`; 4.9.4 is
`8a710bb6e5e27bee2fb814367017221741c07531`, DMG
`bc4f6a9a6cf38df2eb9f712c56922d113a52591655028a898f7dee5a45d1febf`).

Re-verify before any release task; these will go stale.

---

# 4. Where to look next

- Engine contracts: `Tests/NumlexTestKit/` (descriptive case names → source).
- Editor/answer geometry:
  [NotebookEditor.swift](Sources/NumlexApp/Editor/NotebookEditor.swift),
  [ContentView.swift](Sources/NumlexApp/Views/ContentView.swift),
  [AnswerColumnGeometry.swift](Sources/NumlexCore/Models/AnswerColumnGeometry.swift).
- Settings: [SettingsView.swift](Sources/NumlexApp/Views/SettingsView.swift),
  [Settings.swift](Sources/NumlexCore/Models/Settings.swift),
  [Styling.swift](Sources/NumlexCore/Models/Styling.swift).
- Persistence/first launch:
  [Persistence.swift](Sources/NumlexCore/Services/Persistence.swift),
  [FirstLaunch.swift](Sources/NumlexCore/Services/FirstLaunch.swift),
  [Sheet.swift](Sources/NumlexCore/Models/Sheet.swift).
- Export: [Sources/NumlexCore/Export/](Sources/NumlexCore/Export/),
  [docs/EXPORT_AND_PRINT.md](docs/EXPORT_AND_PRINT.md).
- Updates: [UpdateController.swift](Sources/NumlexApp/UpdateController.swift),
  [docs/UPDATES.md](docs/UPDATES.md),
  [UpdateConfiguration.swift](Sources/NumlexCore/Engine/UpdateConfiguration.swift).
- Packaging: [Scripts/build-app.sh](Scripts/build-app.sh),
  [Scripts/build-dmg.sh](Scripts/build-dmg.sh),
  [Scripts/validate-dmg.sh](Scripts/validate-dmg.sh),
  [Scripts/relocated-app-smoke.sh](Scripts/relocated-app-smoke.sh),
  [Scripts/prepare-update-feed.sh](Scripts/prepare-update-feed.sh),
  [Scripts/validate-appcast.sh](Scripts/validate-appcast.sh).
- Full language reference: [docs/SYNTAX_REFERENCE.md](docs/SYNTAX_REFERENCE.md)
  (Russian); English adaptation at <https://numlex.tech/docs/>.
