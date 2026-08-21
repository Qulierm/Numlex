<p align="center">
  <img src="https://github.com/Qulierm/Numlex/assets/132899713/5d48f135-9a20-4b43-93b2-d304bf6c8da3" alt="Sublime's custom image" width="150px" height="150px"/>
</p>

<h1 align="center">Numlex</h1>
<p align="center">
<img src="https://github.com/Qulierm/Numlex/assets/132899713/82d4d861-3dbf-4a50-addd-01503269eb0f"/>
</p>
A simple and elegant notepad-based calculator to create and manage sheets with real-time syntax highlighting and evaluation for mathematical expressions.

## Architecture

Numlex is a Tauri v2 desktop app. The UI is a plain static frontend in `src/` (HTML/CSS/JS with locally vendored CodeMirror 5) that Tauri loads as the local frontend (`frontendDist: ../src` in `src-tauri/tauri.conf.json`). There is no Node integration — the frontend is ordinary browser code (localStorage, Blob, FileReader, relative asset paths). The Rust side in `src-tauri/` is a minimal shell: window 860x600, app identifier `com.numlex.app`, no custom commands.

## Prerequisites

- [Node.js](https://nodejs.org/) (for the Tauri CLI)
- [Rust](https://rustup.rs/) (`cargo` in PATH)
- Platform requirements for Tauri:
  - macOS: Xcode Command Line Tools (`xcode-select --install`)
  - Windows: Microsoft Visual Studio C++ Build Tools and WebView2
  - Linux: `webkit2gtk`, `gtk`, `libayatana-appindicator` (see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/))

## Development

```sh
npm install
npm start        # or: npm run dev — runs `tauri dev`
```

## Building the Application

```sh
npm run build    # or: npm run dist — runs `tauri build`
```

The packaged application will be found in `src-tauri/target/release/bundle/`.

## Optional: Exchange Rate Service

`server/server.rs` is an optional standalone Actix-web service that caches daily USD/EUR rates (from [exchangerate-api.com](https://exchangerate-api.com), 3000 requests/month limit — see `server/About.md`) and exposes `GET /rates` on `127.0.0.1:3000`. The frontend polls it hourly and silently skips currency conversions when it is unreachable. It is **not** part of the Tauri build: it has no `Cargo.toml` manifest, and the API key placeholder `{API}` in the URLs must be replaced before it can be run.

## Usage

- **Create a New Sheet**: Click on the "New Sheet" button to create a new sheet.
- **Switch Sheets**: Click on a sheet in the sidebar to switch to it.
- **Delete a Sheet**: Hover over a sheet in the sidebar and click the delete icon to remove it.
- **Input Expressions**: Type mathematical expressions in the input area.
- **View Results**: Results of the evaluated expressions are shown in real-time below the input area.

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. **Fork the repository**.
2. **Create a new branch** (`git checkout -b feature-branch`).
3. **Commit your changes** (`git commit -m 'Add some feature'`).
4. **Push to the branch** (`git push origin feature-branch`).
5. **Open a pull request**.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
