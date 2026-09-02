<p align="center">
  <img src="Assets/AppIcon.iconset/icon_512x512.png" alt="Numlex app icon" width="132" height="132"/>
</p>

<h1 align="center">Numlex</h1>

<p align="center">
  <img src="https://img.shields.io/github/v/release/Qulierm/Numlex" alt="Latest release"/>
  <img src="https://img.shields.io/badge/macOS-26%2B-111111" alt="macOS 26 or later"/>
  <img src="https://img.shields.io/badge/Platform-Apple%20Silicon%20(arm64)-111111" alt="Apple Silicon, arm64"/>
  <img src="https://img.shields.io/badge/Swift-6.2-F05138" alt="Swift 6.2"/>
</p>

<p align="center">
  A notepad calculator: type plain lines, get live, checked results — natural math,
  variables, percentages, dates, unit and currency conversions, and reusable
  live answer tokens.
</p>

<p align="center">
  <a href="https://github.com/Qulierm/Numlex/releases/latest">Download the latest release</a>
</p>

<p align="center">
  <img src="Assets/NumlexScreenshot.png" alt="Numlex in dark mode: a Lisbon trip budget with variable assignments and live results, two answer-token bubbles reusing the same earlier line, a live currency conversion, and General, Travel and Personal folder tabs at the bottom of the sidebar" width="800"/>
</p>

## Natural calculations

Numlex reads ordinary notebook text — no formula syntax, no cell references. Each line
is evaluated strictly; anything it cannot parse stays quiet instead of guessing.

```text
hotel = 1240          1,240
hotel + 10%           1,364
$240 + 10% tip        $264.00
sqrt(144)             12
room = 180 × 4        720
round(room / 3, 2)    240
sum(1, 2, 3)          6
20 km to meter        20,000 m
100 C to F            212 F°
Jan 10 + 12 days      Jan 22
```

Every line above runs through the real engine — these are its exact, deterministic
outputs, with no live rates involved. Declare values with `name = expression`, use
percentages and money with the same grammar (`$240 + 10% tip`), and do date arithmetic
on plain month names (`Jan 10 + 12 days`).

### Built-in math functions

The engine shares one pure function registry across every scalar path — free
expressions, assignments, constants and unitless answer tokens. Names are
case-insensitive, arguments are full expressions (nesting included), and a
function-shaped line is strict: an unknown name, a bad arity, a bad comma or a
domain failure is a precise error, never a guess.

- `sqrt`, `abs`, `round(x)` / `round(x, d)` (ties round away from zero)
- `min`, `max`, `sum`, `average` — variadic, one or more arguments
- `pow(b, e)` — same finite contract as the `^` operator
- `ln(x)`, `log(x)` (base 10), `log(x, b)`, `log10(x)`
- `sin`, `cos`, `tan` — radians; `asin`, `acos`, `atan`
- `radians(d)` and `degrees(r)` — explicit unit helpers

Inside argument lists a comma separates arguments; a comma directly before exactly
three digits is still a thousand separator, so `sum(1, 234)` is two arguments while
`sum(1,234)` is one grouped literal — and `1,234,567` outside a call is one number,
exactly as before. Built-ins activate only in call position: a variable or constant
named `sum` still works in `sum + 1`, and `sum(1, 2)` calls the function.
Answer tokens join the same engine when they are unitless: `sqrt(<token>)` and
`<token> ^ 2` evaluate with the token as a live argument, while unit-bearing and
money tokens passed to a function or to `^` fail safely instead of losing their
unit.

## Conversions

Write `10 km to meter` — `in` works just as well (`10 km in meter`).

- Around 290 measurement units across length, area, volume, mass, time, speed,
  pressure, force, torque, energy, power, flow and viscosity, plus temperature and
  fuel economy.
- 166 fiat currencies with live rates: codes (`10 EUR to USD`), symbol forms
  (`$100 in EUR`) and English names (`10 Indian rupees to Japanese yen`).
- Rates are cached locally for an hour; if the network is unavailable, Numlex keeps
  serving the last good table.

## Answer tokens

Double-click any answer — or type an operator on a new line — and Numlex inserts a
live token at the caret or selection. A token is a small bubble that always displays
the current value of its source line: change the source and the bubble updates
immediately. Several distinct bubbles may reuse the same earlier line — each keeps its
own identity and follows the live value, as in the screenshot above. If a source line
stops evaluating, its tokens stay in place and show the remembered `Line N` label
instead of a stale number.

## Sheets and folders

Work in named sheets with line numbers, syntax tinting and a live results column.
The native editor highlights matching parentheses, square and curly brackets with a
short Xcode-style pulse whenever the caret sits next to one — nested and mixed
call shapes included. Sheets are grouped by the one-level folder tabs pinned to the
bottom of the sidebar: the built-in **General** tab plus any custom folders you
create. Selecting a tab filters the sheet list only — your editor and cursor never
jump.

## Styling and constants

Choose Light or Dark for the whole app, then tune font size, font design and role
colors, decimal places, input helpers, line numbers, interface language and the
currency display. Define up to 100 app-wide constants (`PI = 3.141592653589793`,
`Sales Tax = 20%`, `Side = sqrt(4)`) that are available in every sheet and resolved
live through the same strict engine — function arguments included.

## Files and storage

Sheets persist locally in Application Support, and the only network traffic is the
background rates refresh. Import and export any sheet as a `.nlx` file from the File
menu, and drag a sheet onto a folder tab to re-file it.

## Download

- macOS 26 or later, Apple Silicon (arm64).
- Download the `.dmg` from the [latest release](https://github.com/Qulierm/Numlex/releases/latest),
  open it, and drag **Numlex.app** into Applications.
- Numlex is ad-hoc signed and **not notarized**. On first launch, Control-click (or
  right-click) **Numlex.app**, choose **Open**, and confirm the prompt.
- Verify your download with the checksums file from the same release:

```sh
shasum -a 256 -c SHA256SUMS
```

## Build from source

Requires macOS 26 with the Swift 6.2 toolchain; Xcode Command Line Tools are enough
(`xcode-select --install`).

```sh
swift build               # debug
swift build -c release    # release
```

The engine suite covers 518 shared cases, runnable two ways:

```sh
swift test                # Swift Testing suite (full Xcode toolchain)
swift run NumlexTests     # standalone runner (Command Line Tools only)
```

Package a signed app bundle:

```sh
Scripts/build-app.sh [debug|release]   # produces .build/Numlex.app
```

<details>
<summary>Architecture</summary>

- **Native UI** — SwiftUI on top of TextKit (`NSTextView`) with line numbers, syntax
  tinting and per-line answer alignment. No web view and no scripting engine —
  expressions run through the pure Swift parser.
- **`Sources/NumlexCore`** — a pure, deterministic parser: tokenizer,
  recursive-descent expression parser, unit catalog, currency presentation, date
  arithmetic and the live reference-token resolver. Strict errors instead of silent
  coercion.
- **Persistence** — one JSON store in `~/Library/Application Support/Numlex`; `.nlx`
  import/export per sheet.
- **Rates** — fetched from `open.er-api.com`, cached for one hour with an 8-second
  timeout; the last good table keeps serving when offline.

</details>
