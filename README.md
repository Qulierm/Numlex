<p align="center">
  <img src="https://github.com/Qulierm/Numlex/assets/132899713/5d48f135-9a20-4b43-93b2-d304bf6c8da3" alt="Sublime's custom image" width="150px" height="150px"/>
</p>

<h1 align="center">Numlex</h1>
<p align="center">
<img src="https://github.com/Qulierm/Numlex/assets/132899713/82d4d861-3dbf-4a50-addd-01503269eb0f"/>
</p>
A simple and elegant notepad-based calculator to create and manage sheets with real-time syntax highlighting and evaluation for mathematical expressions.

## Architecture

Numlex is a Tauri v2 desktop app. The frontend is a **React 19 + Vite** application (in `src/`) styled with **HeroUI** (Tailwind CSS v4) and dark theme. The notebook editor is CodeMirror 6 (`@uiw/react-codemirror`) used only as editor infrastructure — the calculation engine is a pure, `eval`-free domain parser.

- `src/App.jsx` — app state: sheets, active sheet, settings, rates.
- `src/engine/` — safe parser/tokenizer/evaluator (no `eval`/`Function`). Grammar: parentheses, decimal numbers, unary `+`/`-`, `+ - * / ^ %`, variables and `name = expression` assignments, headings (`// Title`), notes. Strict errors instead of silent coercion; decimal rounding respects settings.
- `src/engine/conversions.js` — unit conversions (`km to meter`, `F to C` …) and currency `USD/EUR/RUB` via Tauri rates.
- `src/lib/rates.js` — thin frontend wrapper that invokes the Tauri `get_rates` command.
- `src/lib/translations.js` — interface translations (en/ru/de/it/fr/ch).
- `src/lib/numlexMode.js` — CodeMirror 6 language + token styles.
- `src/components/` — Sidebar (HeroUI ListBox), EditorPane, OutputPanel, SettingsModal (HeroUI Modal/Tooltip/ListBox/Select).

The Rust side in `src-tauri/src/main.rs` exposes a single Tauri command `get_rates` (cached 1 h, 5 s timeout, no secret in the frontend). The app window is 860×600, identifier `com.numlex.app`. The frontend is built by Vite into `dist/` (Tauri `frontendDist`), with a dev server on `http://localhost:1420`. The CSP is tightened (`script-src 'self'` — no `unsafe-eval`).

## Prerequisites

- [Node.js](https://nodejs.org/) (Vite dev server + Tauri CLI)
- [Rust](https://rustup.rs/) (`cargo` in PATH)
- Platform requirements for Tauri:
  - macOS: Xcode Command Line Tools (`xcode-select --install`)
  - Windows: Microsoft Visual Studio C++ Build Tools and WebView2
  - Linux: `webkit2gtk`, `gtk`, `libayatana-appindicator` (see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/))

## Development

```sh
npm install
npm start        # or: npm run dev — Vite dev server only; `npm start` runs `tauri dev`
```

`npm start` launches the Tauri desktop app (it starts the Vite dev server via `beforeDevCommand`).

## Building the Application

```sh
npm run dist     # runs `tauri build` (Vite build + Tauri bundle)
```

The packaged application will be found in `src-tauri/target/release/bundle/`.

## Currency Rates

Currency conversions (`usd to rub`, `eur to rub`, etc.) are provided by the Tauri backend command `get_rates`. The command caches results for 1 hour, times out after 5 seconds, and never exposes a secret to the frontend. It reads the API key from the environment at **runtime** (`NUMLEX_EXCHANGE_API_KEY` or `EXCHANGE_API_KEY`) or from `NUMLEX_RATES_URL` (a URL template containing `{API}`). If no key is configured, or the provider is unreachable, the command returns `USD/EUR/EURUSD = null` and the UI shows an explicit **“Rates unavailable”** error for currency lines — never a silent wrong result.

Platform note: the Rust provider uses `reqwest` with `rustls`; outbound HTTPS requires network access. In preview/web mode without Tauri, `invoke('get_rates')` fails gracefully and rates stay unavailable.

Legacy: `server/server.rs` (Actix service with hard-coded `{API}` placeholder and a hard-coded `80.90.182.109:3000` fetch in older frontends) is no longer part of the active product and is not built; it remains in the repository only for reference. See `server/About.md` for the original standalone design.

## Usage

- **Create a New Sheet**: Click "New sheet" or press `Ctrl/Cmd+N`.
- **Switch Sheets**: Click a sheet in the sidebar.
- **Delete a Sheet**: Click the × on the active sheet or press `Ctrl/Cmd+D`.
- **Import / Export**: `.nlx` files (JSON) — buttons in the sidebar or `Ctrl/Cmd+I` / `Ctrl/Cmd+E`.
- **Input Expressions**: Type mathematical expressions in the editor.
- **View Results**: Results of the evaluated expressions are shown in real-time in the output panel.
- **Settings**: `Ctrl/Cmd+,` — rounding, font size, language, sheet title prefix, line numbers.

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. **Fork the repository**.
2. **Create a new branch** (`git checkout -b feature-branch`).
3. **Commit your changes** (`git commit -m 'Add some feature'`).
4. **Push to the branch** (`git push origin feature-branch`).
5. **Open a pull request**.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
