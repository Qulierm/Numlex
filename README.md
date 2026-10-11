<p align="center">
  <img src="Assets/AppIconPreview.png" alt="Numlex app icon" width="132" height="132"/>
</p>

<h1 align="center">Numlex</h1>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-26%2B-black?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 26 or later"/></a>
  <a href="https://www.swift.org"><img src="https://img.shields.io/badge/Swift-6.2-orange?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 6.2"/></a>
  <a href="https://github.com/Qulierm/Numlex/releases/latest"><img src="https://img.shields.io/github/v/release/Qulierm/Numlex?style=flat-square&amp;logo=github&amp;label=Release" alt="Latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License"/></a>
  <a href="https://github.com/Qulierm/homebrew-tap"><img src="https://img.shields.io/badge/Homebrew-Numlex-FFCC00?style=flat-square&amp;logo=homebrew&amp;logoColor=black" alt="Install Numlex with Homebrew"/></a>
  <a href="https://www.producthunt.com/products/numlex"><img src="https://img.shields.io/badge/Product%20Hunt-Numlex-DA552F?style=flat-square&amp;logo=producthunt&amp;logoColor=white" alt="Numlex on Product Hunt"/></a>
  <a href="https://alternativeto.net/software/numlex/about/"><img src="https://img.shields.io/badge/AlternativeTo-Numlex-0081C6?style=flat-square&amp;logo=alternativeto&amp;logoColor=white" alt="Numlex on AlternativeTo"/></a>
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
  <a href="Assets/NumlexScreenshot.png">
    <img src="Assets/NumlexScreenshot.png" alt="Numlex notebook with variables, conversions, totals, dates and linked answers" width="900"/>
  </a>
</p>

## Features

<table>
  <tr>
    <th>Variables &amp; Functions</th>
    <th>Natural Calculations</th>
  </tr>
  <tr>
    <td align="center"><a href="Assets/Demos/base.gif"><img src="Assets/Demos/base.gif" alt="Typing a variable assignment, a percentage of that variable, a power and a trigonometric function, with live results and a live total" width="388"/></a></td>
    <td align="center"><a href="Assets/Demos/household.gif"><img src="Assets/Demos/household.gif" alt="A household section with arithmetic, a percentage, a section total and a date calculation, each with a live result" width="388"/></a></td>
  </tr>
  <tr>
    <td align="center"><em>Name values, apply functions, and totals stay live</em></td>
    <td align="center"><em>Arithmetic, percentages, section totals and dates — as plain lines</em></td>
  </tr>
  <tr>
    <th>Units &amp; Currencies</th>
    <th>Linked Answers</th>
  </tr>
  <tr>
    <td align="center"><a href="Assets/Demos/kilometres.gif"><img src="Assets/Demos/kilometres.gif" alt="Distance, temperature, currency and mass conversions with live results" width="388"/></a></td>
    <td align="center"><a href="Assets/Demos/linked.gif"><img src="Assets/Demos/linked.gif" alt="Answer bubbles reusing earlier results as they are typed into later lines" width="388"/></a></td>
  </tr>
  <tr>
    <td align="center"><em>Convert distance, temperature, mass and currency in one line</em></td>
    <td align="center"><em>Reuse any result as a bubble that stays in sync</em></td>
  </tr>
</table>

Numlex is a native, offline-first macOS notebook calculator. Enter ordinary
text lines for arithmetic, named values, percentages, functions, dates, money,
unit conversions, totals and more. Results update as you edit; reusable answer
tokens stay linked to their source. The engine uses explicit typed rules rather
than silently guessing at invalid input.

## User documentation

The user manuals live on the [Numlex documentation site](https://www.numlex.tech/docs/):

- [Linked answers](https://www.numlex.tech/docs/linked-answers/)
- [Sheets and files](https://www.numlex.tech/docs/sheets-files/)
- [Styling and constants](https://www.numlex.tech/docs/styling-constants/)

Published manuals describe released behavior and may lag `main`; source code
and tests define the behavior of the current branch.

## Download and install

Numlex requires macOS 26 or later on Apple silicon (arm64). Download the
[latest release](https://github.com/Qulierm/Numlex/releases/latest), open the
plain disk image, and drag **Numlex.app** into Applications. The image contains
only the app and an Applications shortcut.

Numlex is ad-hoc signed and not notarized, so macOS may show a first-launch
warning. If you downloaded it from the official release, use Finder's normal
Control-click (or right-click) → **Open** confirmation; do not disable
Gatekeeper.

You can also install from the project's custom Homebrew tap:

```sh
brew install --cask Qulierm/tap/numlex
```

This is the [Numlex tap](https://github.com/Qulierm/homebrew-tap), not the
Homebrew core cask. The same signing and first-launch guidance applies.

## Build and test

Building from source requires macOS 26 and Swift 6.2; Xcode Command Line Tools
are sufficient.

```sh
swift build
swift run NumlexTests
swift test                 # Swift Testing suite; full Xcode toolchain
bash Scripts/build-app.sh release
bash Scripts/relocated-app-smoke.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository structure, contributor
workflow, security guidance and validation expectations.

## License

Numlex is available under the [MIT License](LICENSE).
