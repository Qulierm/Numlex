# BUG_INVESTIGATION.md — post-4.9.3 feature investigation

## 1. Scope and revision

**Revision investigated:** `d7ac83b5a49d4f49d8774a99167a491d903ef384`
("Fix linked answer conversions"), equal to `origin/main` at the time of the
investigation. **Date:** 2026-09-19. **Delivery:** report-only — no product,
test, script, asset or canonical-doc file was modified.

**Investigated (all with executed evidence):**

1. Linked answers and conversions — the `d7ac83b` bridge, differentially
   against its parent `c1b47f4`.
2. Bounded inline totals (`total last N`), subtotals, grand totals, tag
   aggregates and their token interaction.
3. Installed font family/face rules and styling persistence (core, executed)
   plus the app-side typography surfaces (read-only).
4. Cross-cutting invariants: export parity, footer Total, context
   propagation, source contracts, the removed public API, documentation drift.

**Deliberately NOT investigated:**

- Native macOS GUI behaviour (no window, menu, editor, answer column, font
  menu or preview was driven; this host performs no GUI interaction).
- The Swift Testing runner's execution (this CLT-only host compiles and links
  it but cannot run its bodies; the authoritative executed suite is
  `swift run NumlexTests`).
- Anything requiring the app executable target to be linked (it is an
  executable product and cannot be imported by a probe).
- Any feature outside the four 4.9.3-era areas above (arithmetic lanes, dates,
  finance, units catalogs, export rendering internals, persistence migration).

## 2. Method and harness

**Harness.** `/tmp/numlex-probe/probe.swift` is a spec-driven executable that
links the repository's OWN built module and drives the real public entry
points (`resolveSheet`, `evaluateSheet`). No engine logic is re-implemented: it
builds inputs, calls the engine and prints deterministic, timestamp-free JSON
(per-row `sourceLineIndex`, result case/value/unit/kind, `isTotal`,
`metadata`, `isDynamic`; every token's location and state; plus
`contentUnchanged`, `markerOffsets`, `idCount` and stability flags).

**Build (the `-lNumlexCore` form is unavailable — SwiftPM produces no
`libNumlexCore.a`; the object link is the documented fallback):**

```sh
cd /tmp/numlex-probe
REPO=/Users/nikita/Documents/Coding/numlex
swiftc -I "$REPO/.build/debug/Modules" probe.swift \
  $(find "$REPO/.build/debug/NumlexCore.build" -name '*.o') -o probe
```

**Pre-fix engine for the differential (executed A/B, not source-derived).**
`swift build` in an extracted parent tree cannot resolve Sparkle offline
(`error: .build/repositories/Sparkle-… already exists`), so the
dependency-free core was compiled directly:

```sh
mkdir -p /tmp/numlex-probe/parent
git -C "$REPO" archive c1b47f4 | tar -x -C /tmp/numlex-probe/parent
cd /tmp/numlex-probe/parent
swiftc -emit-module -emit-library -module-name NumlexCore -swift-version 6 \
  $(find Sources/NumlexCore -name '*.swift') \
  -o /tmp/numlex-probe/parent-module/libNumlexCore.dylib \
  -emit-module-path /tmp/numlex-probe/parent-module/NumlexCore.swiftmodule
cd /tmp/numlex-probe
swiftc -I parent-module probe.swift -L parent-module -lNumlexCore -o probe-parent
```

**Re-run everything:**

```sh
cd /tmp/numlex-probe
./probe --fidelity                      # 7 pinned values (see below)
./probe spec-A.json  > raw/A-new.txt    # linked-answer matrix (123 shapes)
./probe-parent spec-A.json > raw/A-parent.txt
./probe spec-B.json  > raw/B-all.txt    # totals/tags matrix (186 shapes)
./probe spec-claims.json > raw/A-claims.txt
./fontprobe  > raw/C-rules.txt          # 82 pure-rule inputs
./storeprobe > raw/C-store.txt          # 56 model-persistence checks
./storeprobe3 > raw/C-store2.txt        # 19 real-payload checks
./exportprobe > raw/D-export.txt        # export parity + footer
./ctxprobe    > raw/D-context.txt       # context propagation
./driftprobe  > raw/D-drift.txt         # documentation claims
```

**Fidelity proof** (`raw/fidelity.txt`, all seven reproduced exactly, each
cross-checked against the repo's own pinned expectation):

| Probe value | Result | Repo expectation |
| --- | --- | --- |
| `10 mg to kg` | `number(1e-05, kg)` | `ConversionCases.swift:78` `expectConversion("10 mg to kg", 1e-5, "kg")` |
| `1 g/cm³ to kg/m³` | `number(1000.0, kg/m³)` | `R84Cases.swift:492` |
| `3 in to cm` | `number(7.62, cm)` | `MoneyCases.swift:213` |
| `36 km/h to m/s` | `number(10.0, m/s)` | `LinkedConversionCases.swift:181` |
| weather token: `weather in London` + `￼ to fahrenheit` | row1 `number(65.3, F°)`, token `active(18.5, C°, "18.5 C°")` | `R55Cases.swift:655` |
| `10/20/blank/30/total last 2` | row4 `number(30.0), isTotal=true, meta=legacyTotal` | `TotalLastCases.swift` |
| `InstalledFontNames.families` synthetic | survivors exactly `alpha,Zed`, Zed faces `Regular,Bold` | `NotebookFontCases.swift` `r91-font-catalog-rejects-hidden-and-faceless-families` |

## 3. Coverage matrix

| Area | Input classes | Executed inputs |
| --- | --- | --- |
| Linked answers and conversions (A) | reported case + neighbours, inch/keyword collisions, marker topology, semantic kinds, conversion classes, numeric formats, junk suffixes | 123 shapes × 2 engines = 246 evaluations (A/B) |
| Totals, subtotals, tags (B) | `total last N` grammar, window semantics, boundaries, slot kinds, subtotal/grand forms, tag aggregates/lookups, token interaction, engine parity, invariants | 186 shapes (14 through both engines) + 4 footer-API sheets |
| Typography rules (C) | usableName, isHidden, regularRank, faces, families (including hidden/face-less/case-fold/Unicode/256-257-scalar/substring-rank cases) | 82 rule inputs |
| Styling persistence (C) | StylingPreferences decode/round-trip/mutation; real StorePayload payload surgery | 56 model + 19 payload checks |
| Cross-cutting (D) | export parity, footer Total, context propagation, source contracts, removed API, doc drift | 23 export/footer checks + 16 context checks + 6 greps + 1 removed-API grep |

**Total executed assertions:** 246 (A) + 186 + 4 (B) + 82 + 56 + 19 (C) +
23 + 16 (D) = **632**, plus 6 source-contract greps and 1 removed-API grep.
Evidence classes are marked per row below: *executed A/B*, *executed probe*,
*source-contract case*, *read-only inspection*.

## 4. Findings table

| ID | Severity | Area | Status | Title |
| --- | --- | --- | --- | --- |
| BUG-01 | High | Linked conversions | Confirmed defect | A carried `in` (inch) token plus the `in` conversion keyword now fails |
| BUG-02 | Low | Linked conversions | Confirmed defect | Carried unit + explicit source unit reports a misleading `Unknown units` |
| BC-01 | — | Linked conversions | Behavior change (regression) | Same as BUG-01; registered here for the differential count |
| BC-02 | — | Linked conversions | Behavior change (improvement) | 44 shapes that used to error now convert as documented |
| BC-03 | — | Linked conversions | Behavior change (value correction) | 5 shapes return the full-precision value instead of the display-rounded one |
| BC-04 | Low | Linked conversions | Behavior change (error string) | 22 shapes changed error message; `Invalid conversion` is gone from this route |
| SUS-01 | Info | Expression lane (out of scope) | Suspected | `1e-07` as a standalone line evaluates to `-6` (pre-existing) |
| SUS-02 | Info | Number parsing (out of scope) | Suspected | `1,125` bare vs `1,125 kg` disagree in decimal-comma mode (pre-existing) |
| SUS-03 | Info | Number parsing (out of scope) | Suspected | `1,234` in legacy mode reads as grouping (pre-existing, may be by design) |
| DRIFT-01 | Medium | Documentation | Confirmed defect (doc) | The Answer Tokens text promises the `in` spelling for a carried `in` unit |
| DRIFT-02 | Low | Documentation | Confirmed defect (doc) | The same paragraph implies only two spellings exist |
| C-01 | Info | Installed fonts | By design | The 256-scalar cap is a persistence rule, not an enumeration rule |
| C-02 | Info | Installed fonts | By design (harness note) | NFC/NFD names are equal Swift Strings and collapse to one family |
| B-01 | Info | Totals | By design | A limited total over an all-ineligible window returns 0 |
| B-02 | Info | Totals | By design | `rand` draws differ between runs; the structure is identical |

**No confirmed defect was found in: bounded totals, subtotals, grand totals,
tag aggregates, the footer Total, export parity, context propagation, source
contracts, or the installed-font rules and styling persistence.** Those areas
are recorded in the Verified-clean register with the invariant that held.

## 5. Per-finding detail

### BUG-01 — carried `in` token plus `in` keyword fails (High)

**Contract citation.** `docs/SYNTAX_REFERENCE.md` §Answer Tokens (bullet added
by `d7ac83b`): «`<token> to <unit>` / `<token> in <unit>` — когда
ответ-источник **уже несёт единицу** (`4673 mg`), токен наследует её и
конвертируется как обычное количество». The `/` presents `to` and `in` as
interchangeable. The pre-fix route accepted both spellings.

**Minimal repro.** Sheet content (line 0 is the source, line 1 the command):

```
3 in
￼ in cm
```

`AnswerReference(sourceLineID: <line 0 UUID>, labelLine: 1, location: 5)`,
`decimalPlaces: 7`, default rates and context.

**Observed vs expected.**

| Engine | row 1 result |
| --- | --- |
| parent `c1b47f4` | `number(7.62, cm)` |
| new `d7ac83b` | `error("Invalid expression")` |
| expected (documented) | `7.62 cm` |

Second shape, same cause: `3 in` + `￼ in in` -> parent `number(3.0, in)`,
new `error("Invalid expression")`.

**Executed evidence.** `raw/A-regression-repro-new.txt` vs
`raw/A-regression-repro-parent.txt` (ids `b02-repro`, `b05-repro`); matrix ids
`b02-carried-in-in-cm`, `b05-carried-in-in-in` in `raw/A-table.txt`.

**Root cause.** `Sources/NumlexCore/Engine/Conversions.swift:486-491` — the
bridge always appends the carried unit before the user's suffix, so the
synthetic line is `3 in in cm`. `conversionShape`
(`Sources/NumlexCore/Engine/Conversions.swift:164-168`) then sees two `in`
ranges and no `to` range, selects no keyword and returns nil; the row falls
through to the token-expression grammar, which cannot parse conversion
keywords, producing the generic `Invalid expression`. The parent route never
synthesized a line (it passed the carried label and the parsed target
separately to `convertTokenQuantity`), so the duplicate `in` never existed.

**User impact and blast radius.** Any linked answer whose source carries the
inch unit (`in`) and whose user writes the documented `in` keyword. The answer
column shows an error, the row breaks dependent tokens, and it contributes
nothing where it previously contributed a value (footer, export).

**Suggested fix direction (NOT implemented).** Do not blindly append the
carried label: detect the conversion keyword first and, when the carried label
equals the keyword word, emit a disambiguated synthetic line (e.g. `3 in to
cm`); or keep the parent's two-argument resolution as a fast path whenever the
carried unit is non-nil.

**Workaround.** Use `to`: `￼ to cm` returns `7.62 cm` (verified, id
`b01-workaround-to`, unchanged A/B).

### BUG-02 — carried unit + explicit source unit gives a misleading error (Low)

**Contract citation.** `docs/SYNTAX_REFERENCE.md` §Answer Tokens documents two
spellings and the three error classes `Unknown units` / `Incompatible units` /
`Rates unavailable`. This shape is undocumented, so no value is promised — but
the reported message names a condition that is not true.

**Minimal repro.**

```
4673 mg
￼ mg to kg
```

`AnswerReference(..., labelLine: 1, location: 8)`, `decimalPlaces: 7`.

**Observed vs expected.** parent -> `error("Invalid expression")`; new ->
`error("Unknown units")`. Expected: `mg` and `kg` are both known, so
`Unknown units` misdescribes the input (the synthetic line `4673 mg mg to kg`
is simply malformed).

**Executed evidence.** ids `a04-carried-plus-explicit-source`,
`a05-carried-plus-wrong-source`, `a08-currency-carried-plus-source` in
`raw/A-table.txt` (all `error-string-change`).

**Root cause.** The same synthesis site,
`Sources/NumlexCore/Engine/Conversions.swift:486-490`: appending the carried
label duplicates the source, and `tryConversion` reports the first failure it
meets while resolving the duplicated from-side
(`Sources/NumlexCore/Engine/Conversions.swift:346-350`).

**User impact and blast radius.** Message-only; the row errors in both
engines, so no value is lost. A user reading `Unknown units` may waste time
checking spelling.

**Suggested fix direction.** Same as BUG-01.

**Workaround.** Use one of the two documented spellings.

## 6. Behavior-change register for the linked-answer fix

Differential: 123 shapes × 2 engines, all **executed A/B**. Raw:
`raw/A-new.txt`, `raw/A-parent.txt`, `raw/A-table.txt`, `raw/A-buckets.json`.

| Bucket | Count |
| --- | --- |
| unchanged | 50 |
| newly converts | 44 |
| error-string-only change | 22 |
| value change | 5 |
| newly fails (regression = BUG-01) | 2 |

**Regressions (2)** — BUG-01's two shapes (`b02`, `b05`).

**Improvements the contract supports (44).** All were errors before and now
produce the ordinary conversion result, because they are exactly the
documented `<token> <source unit> to <target>` spelling: the reported case
(`4673` + `￼ mg to kg` -> 0.004673 kg), currency (`110` + `￼ USD to EUR` ->
100 EUR), exact-integer sources (`0x1F` -> 3.1e-05 kg; `255 as hex` ->
0.000255 kg), variable sources, negative/zero/negative-zero sources, mass,
length, temperature both ways, compound speed and acceleration, density ratio,
both fuel directions, custom units, same-unit, area, volume, data, energy,
multi-word units (`nautical miles to km` -> 18.52 km), slash units
(`m/s to km/h` -> 36 km/h), and 14 numeric-format cases (decimal-comma at
1/2/3/6 dp and grouped, dot, small and large exponents, large integers,
grouping-look, dp 0/2/10).

**Value changes (5) — precision corrections, contract-supported.** The pre-fix
route rounded the conversion to the DISPLAY precision
(`roundResult(v, decimalPlaces:)`) where the ordinary engine keeps
`max(decimalPlaces, 10)`. Documented by the new A7 claim.

| id | old | new |
| --- | --- | --- |
| `f15-dp0-carried` | `number(0.0, kg)` | `number(0.004673, kg)` |
| `f16-dp2-carried` | `number(0.0, kg)` | `number(0.004673, kg)` |
| `b08-carried-m-to-in` | `number(118.1102362, in)` | `number(118.1102362205, in)` |
| `b09-carried-cm-to-in` | `number(1.1811024, in)` | `number(1.1811023622, in)` |
| `d10-money` | `number(4.5454545, EUR)` | `number(4.5454545455, EUR)` |

The first two matter for users: at the app's low decimal-place settings the
carried form previously returned a wrong numeric result (`0.0 kg` for
4673 mg), and now returns the exact value.

**Error-string changes (22).** `Invalid conversion` was produced ONLY by the
deleted token route; it appears nowhere in `d7ac83b`'s token path and is pinned
by no test or document (grep: only `Evaluator.swift:414/424/428` produce it, for
the ordinary money/date lanes). The new strings are the documented classes
(`Unknown units`, `Incompatible units`, `Rates unavailable`, and
`Invalid expression` where the shape is not a conversion). User-visible because
the answer column renders error text. Full id-by-id list in
`/tmp/numlex-probe/findings-A.md` §“Error-string-only changes”.

**Surface impact per change.** The row's answer is consumed by the editor
answer column, the footer Total (a non-`isTotal` ordinary row contributes its
magnitude), export (0 divergences), and dependent tokens (an error row breaks
them; the fixed rows no longer do). Inline section totals are unaffected in
every case because unit-bearing rows are excluded by the documented
eligibility rule.

The footer Total delta was measured per spelling on the RESOLVED rows with
both engines (`raw/E-footdelta-new.txt` vs `raw/E-footdelta-parent.txt`):

| Sheet | parent `c1b47f4` | new `d7ac83b` | typed equivalent (both engines) |
| --- | --- | --- | --- |
| carried `10 mg` + `￼ to kg` | `[10, 1e-05]` | `[10, 1e-05]` (unchanged) | `[10, 1e-05]` |
| explicit-source `4673` + `￼ mg to kg` | `[4673]` (row was an error) | `[4673, 0.004673]` | `[4673, 0.004673]` |

So the footer contribution changes ONLY for the newly-converting spelling
(the row previously errored and contributed nothing); the carried spelling's
contribution is identical before and after, and in both spellings the new
value equals the typed equivalent's.

> **Correction (re-verification pass).** An earlier version of this report
> claimed the delta as "parent `[10]` vs new `[10, 1e-05]` for the carried
> form". That was wrong: the carried form did NOT change (it worked before the
> fix). The re-measurement above is authoritative and matches the differential
> register, where the carried shape sits in the `unchanged` bucket and only the
> explicit-source shape sits in `newly-converts`.

## 7. Verified-clean register

| # | Invariant probed | Evidence class | Result |
| --- | --- | --- | --- |
| 1 | `total last N` grammar: N = 1/2/3 accepted; 0, -1, +2, 3.5, 1e3, 1_0, missing count, trailing junk, overflowing integer, non-ASCII digit are ordinary rows; case/tabs/multi-space/trailing tag accepted; `007` and Int.max accepted; comment/heading forms inert | executed probe | all as documented (B2) |
| 2 | Window counts LOGICAL lines: blank, comment, prose, error, money, unit, boolean, date, tag-only, title and declaration rows each take one slot and contribute nothing | executed probe | holds |
| 3 | Boundaries: `---`, `# `, a prior `total`/`total last N` stop the window; `----` does not; subtotal/grand rows take slots without being boundaries | executed probe | holds |
| 4 | Window larger than the section, empty section, leading command, reset after resolution, consecutive limited totals | executed probe | holds (B5) |
| 5 | Overflow outside the window does not poison it; inside yields the quiet error with `isTotal=false` | executed probe | holds (B6/B8) |
| 6 | `rand` inside the window taints it; outside it does not | executed probe | holds |
| 7 | Variable and constant named `total` both suppress the command | executed probe | holds (B7) |
| 8 | `subtotal`, `± percent`, named subtotal, subtotal boundaries, `grand total` with one vs two subtotals, divider keeping the grand list, named grand, constant rejection, overflowed subtotal excluded | executed probe | 19/19 as documented (C1-C4) |
| 9 | Tag aggregates: four stat forms, duplicate tags once, case-insensitive and NFC/NFD lookup, headings/comments declare nothing, derived rows not re-consumed, empty-set results, trailing garbage inert, aggregate inside a window takes a slot | executed probe | 29/29 as documented (C5) |
| 10 | Exactly one `SheetLine` per logical line | executed probe | 186/186 |
| 11 | `isTotal`/`metadata` correct on derived rows | executed probe | 0 derived-but-unflagged rows |
| 12 | Repeat evaluation identical; content never rewritten | executed probe | holds on every case |
| 13 | `evaluateSheet`/`resolveSheet` agree on every field | executed probe | 14/14 paired shapes identical |
| 14 | Footer excludes every `isTotal` row and every documented non-scalar kind; no double counting | executed probe | 7 sheets, 0 violations |
| 15 | Export row answers equal the live answer column string; export footer over exported rows | executed probe | 8 sheets, 0 diffs |
| 16 | Context propagation: custom UnitContext, restricted and full rate tables, decimal-comma vs dot, error states | executed probe | 16/16 equal |
| 17 | `InstalledFontNames` rules (hidden, face-less, control, case-fold, Unicode, 256/257, rank substrings, stability) | executed probe | 82/82 |
| 18 | Styling persistence: tolerant decode, wrong types, nulls, 256/257, round-trip, unknown raws, width clamping, `currentVersion` 2 | executed probe | 75/75 (56 + 19) |
| 19 | Face-without-family invariant: the face chooser refuses an orphan face and the round-trip stays equal | executed probe | holds |
| 20 | No `Bundle.module`, no developer paths, no `codesign --deep`, `currentVersion` 2, U+FFFC marker, routes in their files | executed grep | 6/6 |
| 21 | App-side typography claims (delegation, unavailability, line height, one persist per choice, unavailable label, export inheritance) | read-only inspection + source-contract case | all verified |
| 22 | `SheetExport` carries no styling (the `.nlx` claim) | read-only inspection | `Sheet.swift:265-280` has no styling key |

## 8. Suspected leads (evidence insufficient — out of scope, all pre-existing)

**SUS-01 — `1e-07` as a standalone line evaluates to `-6`.** Concrete
condition: sheet `1e-07` (no unit, no conversion) -> `number(-6.0)`.
Executed A/B: identical in parent and new (`raw/A-preexist-parent.txt`,
`p1-exp-source-only`), so NOT caused by `d7ac83b`. Looks like a real defect
(the literal appears to read as `1 * e - 07`), but it is an expression-lane
issue outside this investigation's four areas. **Missing evidence:** the
`e`-constant/notation contract in `docs/SYNTAX_REFERENCE.md` §Числовые
литералы, and whether `e` is an intentional variable.

**SUS-02 — `1,125` bare vs `1,125 kg` disagree in decimal-comma mode.**
Concrete condition: comma context, `1,125` (bare) -> `number(1125.0)` while
`1,125 kg` -> `number(1.125, kg)` (and `1,125 kg to g` -> 1125 g).
Pre-existing (identical A/B). **Missing evidence:** the documented
decimal-comma grouping rule for exactly-three-digit groups.

**SUS-03 — `1,234` in legacy (dot) mode reads as grouping.** Concrete
condition: `1,234` -> `number(1234.0)`; `1,234 kg to g` -> 1234000 g. The
expression grammar and the conversion grammar agree here, so this may be by
design. Pre-existing (identical A/B). **Missing evidence:** the documented
legacy thousands-grouping rule for bare literals.

## 9. Documentation-drift list

**DRIFT-01 (Medium) — quoted sentence promises an `in` spelling the code
rejects for a carried `in` unit.**

> «`<token> to <unit>` / `<token> in <unit>` — когда ответ-источник **уже
> несёт единицу** (`4673 mg`), токен наследует её и конвертируется как обычное
> количество: `4673 mg`, затем `<token> to kg` → `0.004673 kg`.»
> — `docs/SYNTAX_REFERENCE.md`, §Answer Tokens (added by `d7ac83b`)

Contradicting executed result: `4673 mg` + `￼ in kg` -> `number(0.004673, kg)`
(correct) but `3 in` + `￼ in cm` -> `error(Invalid expression)`, while the `to`
spelling gives `7.62 cm` (`raw/D-drift.txt`). A user acting on the doc with an
inch-valued linked answer gets an error. Severity Medium: a documented
spelling fails on one carried unit, with a workaround (`to`).

**DRIFT-02 (Low) — the same paragraph implies only two spellings exist.**

The doc lists exactly two forms; the code also accepts `<token> <source> to
<target>` on a source that already carries a unit, which then errors with the
misleading `Unknown units` (BUG-02). Undocumented territory, so no promise is
broken, but the reader gets no guidance. Severity Low: message clarity only.

**Claims checked and found accurate (no drift):** the reported
`<token> mg to kg` -> 0.004673 kg; the carried `to` form -> 0.004673 kg; all
three documented error classes; the `max(decimalPlaces, 10)` precision claim at
dp 0/2/7/10; the semantic-kind refusal for percent/multiplier/fraction/boolean;
the inch disambiguation `3 in to cm` (ordinary AND linked); the
no-document-mutation claim; and every testable 4.9.3 release-note claim about
`total last N` (slot counting, boundaries, reset, overflow/rand windows,
shadowing) and typography (surfaces, line-height expansion, stored-name
retention, built-in clearing, names shown as macOS reports them), plus the
styling page's sanitizer / `.nlx` / no-version-bump claims.

## 10. Limitations

- **No native macOS GUI interaction** was performed or claimed. No window,
  menu, editor, answer column, font menu, preview or export dialog was driven.
  All evidence is deterministic engine/API level.
- **This CLT-only host cannot execute Swift Testing bodies.** `swift test`
  compiles and links the target but runs nothing; the authoritative executed
  suite is `swift run NumlexTests` (1387/1387).
- **App-side typography surfaces are read-only evidence.** `NotebookPalette`,
  `InstalledFontCatalog`, `SettingsView` and `ExportFontCatalog` live in the
  `NumlexApp` executable target and cannot be linked by a probe; their claims
  are marked read-only (with a passing source-contract case where one exists).
  In particular the "Unavailable" label wording has no executed coverage.
- **The differential used a directly compiled parent core**, not a SwiftPM
  build (Sparkle resolution is impossible offline). The compiled parent is the
  real `c1b47f4` source of `NumlexCore`; no logic was re-implemented for it.
- **Error-message strings** are asserted as observed text; no contract pins
  them for this route (that is itself a finding, BC-04).
- The two `1e-07`/comma-mode leads are labelled Suspected and are OUT of this
  investigation's scope; they would need their own pass with the numeric-literal
  contract located.

## 11. Reproduction instructions

1. `cd /Users/nikita/Documents/Coding/numlex && swift build` (module must be
   current; re-run after any source change).
2. Rebuild the probe and the parent probe with the commands in §2.
3. Run the harnesses listed in §2; every raw file referenced above is written
   under `/tmp/numlex-probe/raw/`.
4. For a single finding, write a spec JSON containing just its case (content,
   `refs: [{source, label, occurrence}]`, `decimalPlaces`) and run
   `./probe <spec.json>` (new engine) or `./probe-parent <spec.json>`
   (parent). Reference offsets are computed from the real document by the
   probe, so a spec cannot silently use a wrong offset.
5. The repository suite remains the authority for pinned behaviour:
   `swift run NumlexTests` -> 1387/1387.
