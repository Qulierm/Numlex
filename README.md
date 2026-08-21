<p align="center">
  <img src="https://github.com/Qulierm/Numlex/assets/132899713/5d48f135-9a20-4b43-93b2-d304bf6c8da3" alt="Sublime's custom image" width="150px" height="150px"/>
</p>

<h1 align="center">Numlex</h1>
<p align="center">
<img src="https://github.com/Qulierm/Numlex/assets/132899713/82d4d861-3dbf-4a50-addd-01503269eb0f"/>
</p>
A simple and elegant notepad-based calculator to create and manage sheets with real-time syntax highlighting and evaluation for mathematical expressions.

## Architecture

Numlex is a Tauri v2 desktop app. The frontend is a **React 19 + Vite** application (in `src/`) styled with **HeroUI** (Tailwind CSS v4) and dark theme. The expression editor is CodeMirror 6 (`@uiw/react-codemirror`) with a custom stream language that highlights comments, units (`to`), numbers, operators and variables.

- `src/App.jsx` — app state: sheets, active sheet, settings, exchange rates.
- `src/lib/evaluate.js` — the evaluation engine (pure functions, no UI).
- `src/lib/rates.js` — polling of the optional exchange-rate service.
- `src/lib/translations.js` — interface translations (en/ru/de/it/fr/ch).
- `src/lib/numlexMode.js` — CodeMirror 6 language + token styles.
- `src/components/` — Sidebar, EditorPane, OutputPanel, SettingsModal (HeroUI components).

The Rust side in `src-tauri/` is a minimal shell: window 860x600, app identifier `com.numlex.app`, no custom commands. The frontend is built by Vite into `dist/` (Tauri `frontendDist`), with a dev server on `http://localhost:1420`.

Note: the expression engine evaluates arithmetic with JavaScript `eval`, which is why the Tauri CSP keeps `script-src 'unsafe-eval'`.

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

## Optional: Exchange Rate Service

`server/server.rs` is an optional standalone Actix-web service that caches daily USD/EUR rates (from [exchangerate-api.com](https://exchangerate-api.com), 3000 requests/month limit — see `server/About.md`) and exposes `GET /rates` on `127.0.0.1:3000`. The frontend polls it hourly and silently skips currency conversions when it is unreachable. It is **not** part of the Tauri build: it has no `Cargo.toml` manifest, and the API key placeholder `{API}` in the URLs must be replaced before it can be run.

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
