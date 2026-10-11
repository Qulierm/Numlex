# Contributing to Numlex

This guide is for maintainers and contributors to the native macOS app. User
manuals are maintained on the [Numlex documentation site](https://www.numlex.tech/docs/),
not copied into this repository. Published manuals describe released behavior
and may lag `main`; current source and tests are authoritative.
Website edits, translations and documentation-pin refreshes are separate work
and require explicit authorization.

## Repository map

- `Sources/NumlexCore/`: dependency-free parser, evaluator, models, persistence,
  services, resources and export logic.
- `Sources/NumlexApp/`: SwiftUI/AppKit macOS application. Sparkle is linked only
  by this target and is pinned exactly to `2.9.6`.
- `Tests/NumlexTestKit/`: shared `EngineCase` arrays; `Tests/NumlexTests/` is the
  standalone runner and `Tests/NumlexCoreTests/` wraps the same arrays for
  Swift Testing.
- `Scripts/`: build, resource, icon and packaging validators.
- `Assets/README.md`: current icon sources, provenance and build wiring.
- `../NumlexWeb/`: separate repository that owns published user manuals and
  their immutable source-revision pins.

## Build and test

Use macOS 26 or later and Swift 6.2 (Xcode Command Line Tools are sufficient
for the standalone runner and package builds).

```sh
swift build
swift build -c release
swift run NumlexTests
swift test
```

`swift test` requires the full Xcode toolchain. Run the complete standalone
suite, both builds and `git diff --check` for code changes. Run focused cases
while iterating, but do not remove or bypass regressions. New shared case arrays
must be registered in **both** `Tests/NumlexTests/main.swift` and
`Tests/NumlexCoreTests/EngineTests.swift`.

For a packaged local app and its relocation check:

```sh
bash Scripts/build-app.sh release
bash Scripts/relocated-app-smoke.sh
```

Build and run from the exact committed clean tree when validating a handoff.
For any manual runtime launch, redirect all state with `--data-dir <temporary-path>`
or `NUMLEX_DATA_DIR`; never use a user's normal data directory. Resource
validation and the relocated smoke are deterministic checks, not GUI tests.

## Code and data invariants

- Keep `NumlexCore` pure and dependency-free. Use typed values and explicit
  evaluation lanes; do not add regex patches, silent coercion or guessy fallback
  parsing. Formatting is presentation, not evaluation truth.
- Resolve a sheet once with one explicit input/context set and share that result
  with the editor and answer column. Preserve one logical row per newline and
  stable line UUIDs.
- An answer token is a U+FFFC marker (one UTF-16 unit) plus a reference to a
  source-line UUID. It displays the source's current value, not a stored numeric
  snapshot. Dynamic random values cannot be tokenized or propagated.
- Preserve editor caret/selection, IME marked text, focus and scroll across
  presentation-only changes. Keep the editor as the single scroll source; drag
  geometry uses global coordinates. Presentation changes must not mutate text,
  references or evaluation state.
- Persist a user-visible change atomically and once. Do not casually change
  `StorePayload` schema/version or migrate user data. Export from one immutable
  resolved snapshot; distinguish inline totals from the footer statistic.
- New app UI strings belong in all six app locales in
  `Sources/NumlexCore/Localization.swift`.

## Packaged resources and icons

All five offline catalogs have `sources.json` hash manifests and must fail
closed on missing or corrupt data. `ResourceLocator` is the production lookup
path; packaged resources live in the standard
`Contents/Resources/Numlex_NumlexCore.bundle` location. Do not introduce
`Bundle.module`, developer-absolute paths or build-time dataset generation.
Preserve the existing dataset generators; they are active through manifests,
loaders and build/security tooling. `Scripts/build-app.sh` packages the exact
configuration output, and `Scripts/relocated-app-smoke.sh` verifies the copied
app loads all five catalogs.

The active icon pipeline combines the committed modern dual-stack
`Assets.car` with the ICNS fallback and Composer sources. Read
[Assets/README.md](Assets/README.md) before icon work; preserve source provenance,
previews, compiler inputs and validation contracts. Do not regenerate or replace
committed icon artifacts without an explicitly authorized task.

## Update security and releases

Sparkle `2.9.6` verifies the mandatory EdDSA archive signature **before
extraction**. After that check, Sparkle still requires a valid app signature;
Apple identity matching is only a fallback trust route. The app's normal build
is ad-hoc signed; a Developer ID identity is optional and notarization is not
required for this design.

The committed `SUPublicEDKey` is public. The EdDSA private key belongs only to
the maintainer: it stays in the maintainer's login Keychain and in an owner-
controlled offline backup. Agents and ordinary contributors must never access,
read, export, print, copy or commit it. The owner performs any manual offline
backup outside agent workflows; no runnable key-export procedure belongs here.
Losing the private key is serious because future update archives could no longer
be verified by existing clients.

Every release action is separately gated by explicit per-task authorization;
this guide grants none. The approved sequence is: update version and commit,
create an immutable annotated tag, build from the clean tagged source, validate
and freeze the app/DMG hashes, publish that release once, then prepare and
cryptographically validate the feed for the available asset. Website release
notes/docs/locales and Homebrew changes require separate authorization; finish
with public-byte and feed verification. Never replace, retag or delete published
assets or tags, and never use `codesign --deep`.

## Git hygiene and completion

Before work and before a commit, inspect `git status --short`, the current branch,
recent history and remote state. Read the relevant source and tests first. Keep
the diff scoped; stage explicit paths only—never `git add .` or `git add -A`.
Preserve unrelated edits, commits and untracked content. Do not reset, clean,
stash, rebase, amend another author's commit, rewrite history or force-push.

For code changes, run focused tests, the full standalone suite, debug and release
builds, and `git diff --check`. Assemble and validate a packaged app from the
clean committed source when the task requires an app handoff; use the resource
smoke for packaging changes. Commit one focused change. Push only after
validation and only when explicitly authorized; verify local `HEAD`, tracking
branch and fresh remote state afterward. Report exact commands/results and
limitations. Never claim GUI success without actually observing it.

Do not install or replace an app in `/Applications`, access user data, change
privacy/permissions/quarantine, or touch clipboard/global input state without
explicit authorization. Never print secrets, access the update private key,
modify `../NumlexWeb` or the Homebrew tap, change release metadata, publish or
move a tag, or produce a release artifact without a separate explicit task.
