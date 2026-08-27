import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

struct ContentView: View {
    var model: AppModel
    /// Shared scroll offset (top-down, editor-content points). The editor's
    /// clip view is the primary surface; the answer column renders at this
    /// offset and its wheel deltas write it back, so both stay 1:1.
    @State private var topOffset: CGFloat = 0
    @State private var metrics = LineMetrics(lines: [])
    @State private var editorBridge: NotebookEditorCoordinator?
    @State private var showImport = false
    @State private var showExport = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // Editor and answer column share the same detail top, so a row's
            // editor-content y equals its answer-content y (modulo the fixed
            // editor top inset) and scroll offsets are directly comparable.
            HStack(spacing: 0) {
                GeometryReader { _ in
                    let settings = model.settings
                    let sheet = model.selectedSheet
                    let binding = Binding<String>(
                        get: { sheet?.content ?? "" },
                        set: { model.updateContent($0, edit: nil) }
                    )
                    // Reference-aware evaluation: the SAME one-row-per-
                    // logical-line result as before, plus the live state
                    // of every token marker the editor renders.
                    let resolved = resolveSheet(
                        content: sheet?.content ?? "",
                        lineIDs: sheet?.lineIDs ?? [],
                        references: sheet?.references ?? [],
                        rates: model.rates,
                        decimalPlaces: settings.decimalPlaces
                    )
                    NotebookEditor(
                        text: binding,
                        fontSize: settings.fontSize,
                        lineHeight: settings.lineHeight,
                        lineNumbers: settings.lineNumbers,
                        rates: model.rates,
                        decimalPlaces: settings.decimalPlaces,
                        inputPrefs: settings.input,
                        onPreviousAnswerTrigger: { key, caret in
                            model.insertPreviousAnswer(key: key, at: caret)
                        },
                        onScroll: { offset in
                            // Raw native offset: negative values are the
                            // elastic overscroll at the top and must show
                            // through on the answer column while they last.
                            topOffset = offset
                        },
                        onLayout: { m in metrics = m },
                        onTextChange: { text, edit in model.updateContent(text, edit: edit) },
                        tokenStates: resolved.tokens,
                        tokenRefs: sheet?.references ?? [],
                        onPasteReferences: { refs in model.addReferences(refs) },
                        focusRequestID: model.focusSheetID,
                        focusPosition: model.focusCaret,
                        onFocusConsumed: { model.focusSheetID = nil; model.focusCaret = nil },
                        onReady: { bridge in editorBridge = bridge }
                    )
                    .id(sheet?.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                let settings = model.settings
                // Reference-aware rows (same strict 1:1 contract as
                // evaluateSheet, with token lines resolved to their
                // current linked values).
                let rows: [SheetLine] = {
                    let sheet = model.selectedSheet
                    return resolveSheet(
                        content: sheet?.content ?? "",
                        lineIDs: sheet?.lineIDs ?? [],
                        references: sheet?.references ?? [],
                        rates: model.rates,
                        decimalPlaces: settings.decimalPlaces
                    ).lines
                }()
                AnswerColumnView(
                    rows: rows,
                    metrics: metrics,
                    topOffset: topOffset,
                    onWheelScroll: { event in
                        // Answer column wheel: forward the raw NSEvent to
                        // the editor's scroll view; the editor stays the
                        // single native momentum/elasticity source and its
                        // BoundsDidChange drives topOffset back.
                        editorBridge?.forwardScrollWheel(event)
                    },
                    onAnswerDoubleTap: { lineIndex in
                        model.insertToken(sourceLineIndex: lineIndex)
                    },
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    decimalPlaces: settings.decimalPlaces,
                    totalLabel: L10n.t("total", language: settings.language)
                )
            }
            .toolbar(removing: .title)
        }
        .frame(minWidth: 820, minHeight: 560)
        // Reset the editor-bound state when the selected SHEET ID changes,
        // not only the numeric index: deleting the selected non-last row
        // changes the ID under an unchanged index, and stale answer
        // geometry (or a dead bridge) from the previous sheet would flash
        // or drift. The new coordinator re-arms itself via onReady.
        .onChange(of: model.selectedSheet?.id) { _, _ in
            topOffset = 0
            metrics = LineMetrics(lines: [])
            editorBridge = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSheet)) { _ in model.newSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .importSheet)) { _ in showImport = true }
        .onReceive(NotificationCenter.default.publisher(for: .exportSheet)) { _ in showExport = true }
        // App-menu "Delete Sheet": consumed here (not in the sidebar), so
        // it works even when the sidebar column is collapsed. The sidebar
        // row animation is driven by the sheet-ID list change, so this and
        // the context-menu deletion animate identically.
        .onReceive(NotificationCenter.default.publisher(for: .deleteSheet)) { _ in
            model.deleteSelected()
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.nlx, .json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                model.importSheet(from: url)
            }
        }
        .fileExporter(isPresented: $showExport, document: NLXDocument(model: model), contentType: .nlx, defaultFilename: "\(model.selectedSheet?.title ?? "Sheet").nlx") { result in
            if case .failure(let err) = result { print("export failed \(err)") }
        }
        .background(WindowConfigurator())
        .onAppear {
            Task { @MainActor in await model.loadRates() }
            if let window = NSApp.keyWindow {
                window.setContentSize(NSSize(width: 890, height: 680))
                window.center()
            }
        }
    }
}

/// Grabs the hosting NSView's window once it exists and applies window
/// chrome the SwiftUI scene APIs cannot express: no titlebar separator
/// strip and the minimum content size. The representable's view is in the
/// hierarchy, so `view.window` is the real window (unlike NSApp.keyWindow,
/// which can be nil while the scene is still coming up).
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
            window.minSize = NSSize(width: 820, height: 560)
            applyNoSeparatorChrome(to: window)
            // SwiftUI re-asserts the default chrome during later layout and
            // activation passes; hold the override.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in applyNoSeparatorChrome(to: window) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private func applyNoSeparatorChrome(to window: NSWindow) {
    // The horizontal strip at the top of the detail area is the window
    // titlebar separator. In a NavigationSplitView window (whose sidebar
    // toggle installs an NSToolbar) the separator style is re-asserted to
    // .line after any assignment, so the titlebar itself is made
    // transparent: the separator strip disappears with it.
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
}

struct NLXDocument: FileDocument {
    var export: SheetExport
    static var readableContentTypes: [UTType] { [.nlx, .json] }
    init(model: AppModel) {
        if let s = model.sheets.indices.contains(model.selectedIndex) ? model.sheets[model.selectedIndex] : nil {
            export = SheetExport(title: s.title, content: s.content,
                                 isTitleCustom: s.isTitleCustom,
                                 lineIDs: s.lineIDs, references: s.references)
        } else {
            export = SheetExport(title: "Sheet", content: "")
        }
    }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let obj = try? JSONDecoder().decode(SheetExport.self, from: data) {
            export = obj
        } else {
            export = SheetExport(title: "Sheet", content: "")
        }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(export)
        return FileWrapper(regularFileWithContents: data)
    }
}
