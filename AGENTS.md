# AGENTS.md — repository work

Applies throughout this repository unless a closer `AGENTS.md` overrides it.
Read [CONTRIBUTING.md](CONTRIBUTING.md) for the maintainer workflow and
[Assets/README.md](Assets/README.md) before icon work.

## Authority and safe start

- Read the relevant source and tests before editing. Current source and tests
  define `main`; public manuals describe published releases and may lag.
- Start with `git status --short`, branch, recent history and remote state; check
  status again before staging and committing. Preserve every pre-existing edit,
  commit and untracked item. `Examples/`, root file `Numlex`, and `Promo/` are
  intentional; never add, modify or delete them.
- Stage explicit paths only. Never use `git add .` or `git add -A`. Do not
  reset, clean, stash, rebase, amend another commit, rewrite history, force-push
  or silently include unrelated commits.
- Never modify `Package.resolved`, frozen build/release outputs, `dist/`, user
  data or caches as a cleanup shortcut. Do not regenerate datasets or assets
  unless the task explicitly requires it.
- Do not install/replace apps, run `lsregister`, alter quarantine/privacy/
  permissions, or touch user Application Support, clipboard or global input
  state without explicit authorization. Isolate any runtime data in a temporary
  `--data-dir` / `NUMLEX_DATA_DIR`.
- Website manuals, translations, provenance pins and releases belong to the
  separate `../NumlexWeb` repository. Do not change it or the Homebrew tap
  unless explicitly tasked. Keep historical website pins at their real source
  revisions; never repoint them to deleted or recreated copies.
- Version bumps, tags, release assets, DMGs, appcast/feed, release notes,
  website/tap publication and release verification are separately gated:
  require explicit per-task authorization. Published assets and tags are
  immutable. No `codesign --deep`.

## Architecture and behavior invariants

- `NumlexCore` is pure and dependency-free; only `NumlexApp` links Sparkle,
  pinned exactly to `2.9.6`. Keep evaluation typed and lane-specific: no regex
  patches, string-based evaluation truth, silent coercion or guessy fallback.
- Resolve one sheet once using one explicit context/input set for the editor and
  answer column. Keep one logical row per newline and stable line UUIDs.
- A token is a U+FFFC marker (one UTF-16 unit) plus a sidecar reference to a
  source-line UUID. It follows the current source value, never a numeric
  snapshot. Dynamic random answers cannot be tokenized or propagated.
- Preserve caret/selection, IME marked text, focus and scroll across
  presentation-only changes. TextKit is the single scroll source; resize
  geometry uses global coordinates. Presentation changes must not mutate text,
  references, evaluation or export.
- Persist each user-visible change atomically and once. Do not casually bump
  `StorePayload` schema or migrate user data. Keep inline totals distinct from
  the footer statistic. Export one immutable resolved snapshot.
- New app UI strings go in all six app locales. No telemetry, analytics,
  “Replay Welcome” behavior or web view.

## Resources and security

- All five offline catalogs have per-file `sha256` manifests. Preserve the
  manifests and fail closed on missing/corrupt resources. `ResourceLocator` is
  the production lookup path; package the bundle at
  `Contents/Resources/Numlex_NumlexCore.bundle`. Never use `Bundle.module` or
  developer-absolute paths in production. Keep build checks on exact outputs.
  Preserve all five dataset generators and their loader/manifest contracts.
- Preserve the active modern dual-stack icon catalog, ICNS fallback, Composer
  sources, previews and validators. See [Assets/README.md](Assets/README.md);
  do not hand-edit protected artifact hashes.
- Sparkle requires EdDSA archive verification before extraction and a valid app
  signature; Apple identity matching is fallback only. The app normally uses
  ad-hoc signing; Developer ID is optional and notarization is not required.
  The committed update public key is not secret. The private key belongs only
  to the maintainer's login Keychain and owner-controlled offline backup.
  Agents must never access, read, export, print, copy or commit it. Key loss is
  serious. Do not add runnable private-key export instructions.

## Validation and completion

- Shared `EngineCase` arrays belong in `Tests/NumlexTestKit/` and must be
  registered in both `Tests/NumlexTests/main.swift` and
  `Tests/NumlexCoreTests/EngineTests.swift`.
- For code changes, run focused tests, `swift run NumlexTests`, `swift build`,
  `swift build -c release` and `git diff --check`. Use `swift test` with the
  full Xcode toolchain. Follow task-specific broader validation.
- For packaged handoffs, build from the exact clean committed source with
  `bash Scripts/build-app.sh release`; verify bundle metadata, signature and
  resource contracts. Packaging changes also run
  `bash Scripts/relocated-app-smoke.sh`. Never claim the bare SwiftPM binary is
  an assembled app.
- GUI/runtime checks use isolated temporary data. A host may start the process
  without producing a usable window; rely on deterministic tests and report
  honestly. Never claim GUI success without observing it.
- Finish with the scoped diff, explicit staging, one focused commit, final
  status and an accurate report. Push only after green validation and explicit
  per-task authorization; verify `HEAD`, tracking branch and fresh remote.
  State skipped checks and limitations; do not imply a commit, app, release or
  push exists before it does.
