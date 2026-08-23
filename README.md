<p align="center">
  <img src="https://github.com/Qulierm/Numlex/assets/132899713/5d48f135-9a20-4b43-93b2-d304bf6c8da3" alt="Numlex" width="150px" height="150px"/>
</p>

<h1 align="center">Numlex</h1>
<p align="center">
<img src="https://github.com/Qulierm/Numlex/assets/132899713/82d4d861-3dbf-4a50-addd-01503269eb0f"/>
</p>

A simple and elegant notepad-based calculator to create and manage sheets with real-time evaluation of mathematical expressions.

## Architecture

Numlex is a native **Swift 6 / SwiftUI** macOS app (macOS 26, Liquid Glass). The calculation engine is a pure, evaluation-free domain parser in `Sources/NumlexCore` — no scripting, no web view.

- `Sources/NumlexCore/Engine/` — tokenizer, parser and evaluator. Grammar: parentheses, decimal numbers, unary `+`/`-`, `+ - * / ^ %` (postfix percent), variables and `name = expression` assignments, headings (`// Title`), `#` notes. Strict errors instead of silent coercion; rounding respects settings.
- `Sources/NumlexCore/Engine/Conversions.swift` — unit conversions (`10 km to meter`, `100 C to F`, …) and currency `USD/EUR/RUB` via `Rates`.
- `Sources/NumlexCore/Services/` — JSON persistence in Application Support, live rates from the open.er-api.com endpoint (cached 1 h, 5 s timeout, offline-safe).
- `Sources/NumlexCore/Localization.swift` — interface translations (en/ru/de/it/fr/ch).
- `Sources/NumlexApp/` — SwiftUI app: sidebar with sheet management (create, rename, delete, import/export `.nlx`), native `NSTextView` notebook editor with line numbers and syntax tinting, live results column with row alignment, settings scene (language, font size, line spacing, decimal places, rates).

## Prerequisites

- macOS 26 with Xcode Command Line Tools (`xcode-select --install`)
- Swift 6 toolchain

## Build

```sh
swift build            # debug
swift build -c release # release
```

## Tests

The engine test suite is registered with Swift Testing (`Tests/NumlexCoreTests`) and shares its 35 cases with a standalone runner (`Tests/NumlexTestKit`).

```sh
swift test             # Swift Testing suite (full Xcode toolchain)
swift run NumlexTests  # standalone runner — works with Command Line Tools only
```

## Package a .app bundle

```sh
Scripts/build-app.sh [debug|release]
```

Produces `.build/Numlex.app` (signed with an ad-hoc identity) and prints its path.
