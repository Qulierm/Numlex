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
    /// r37: the STABLE source line ID of the token the pointer is
    /// hovering (ephemeral UI state — never persisted). Mapped against
    /// the CURRENT sheet's lineIDs at render time, so insertions and
    /// deletions above the source keep the highlight on the same line
    /// and a missing source maps to nil.
    @State private var hoveredSourceID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Live measured width of the sidebar column (tracks user resizes
    /// within 180...220). The window resize response uses this value, not
    /// a hardcoded ideal, so the width delta always matches the column.
    @State private var sidebarWidth: CGFloat = 190
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// r43: mint an answer token at the editor's CURRENT caret/selection.
    /// The live selection is snapshotted from the bridge IMMEDIATELY (the
    /// double-tap must never move it first) and tagged with the sheet the
    /// bridge is bound to: a stale bridge (sheet switch), a missing one
    /// (not attached yet), or IME marked text is a no-op — a late or
    /// cross-sheet event can never mint a token on the wrong sheet, and
    /// nothing is ever appended as a fallback. A method (not an inline
    /// multi-statement closure) keeps `body` inside the type-checker's
    /// budget without changing the view tree.
    private func answerDoubleTap(lineIndex: Int,
                                 sheetID: Sheet.ID?,
                                 bridge: NotebookEditorCoordinator?) {
        guard let sheetID,
              let range = bridge?.selectionSnapshot(sheetID: sheetID) else { return }
        model.insertToken(sourceLineIndex: lineIndex, selection: range)
    }

    /// r43: the editor construction for the detail pane, extracted as a
    /// method ONLY to keep `body` inside the type-checker's budget — the
    /// emitted view tree is identical to the inline initializer.
    private func editorView(sheet: Sheet?,
                            settings: AppSettings,
                            resolved: (lines: [SheetLine], tokens: [TokenResolution])) -> some View {
        let binding = Binding<String>(
            get: { sheet?.content ?? "" },
            set: { model.updateContent($0, edit: nil) }
        )
        return NotebookEditor(
            text: binding,
            sheetID: sheet?.id,
            fontSize: settings.fontSize,
            lineHeight: settings.lineHeight,
            lineNumbers: settings.lineNumbers,
            rates: model.rates,
            decimalPlaces: settings.decimalPlaces,
            inputPrefs: settings.input,
            styling: settings.styling,
            appAppearance: settings.appearance,
            constants: settings.customConstants,
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
            onReady: { bridge in editorBridge = bridge },
            onTokenHoverChanged: { id in hoveredSourceID = id }
        )
        .id(sheet?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // r36: the ONE centralized editor surface token —
        // the SwiftUI host matches the NSTextView exactly. The layer
        // expands vertically into the titlebar safe-area gap so the
        // top strip behind the editor matches the editor (no window
        // tint), while the text layout itself stays inset.
        .background {
            Color(nsColor: Design.editorBackground).ignoresSafeArea(edges: .vertical)
        }
    }

    /// Editor|answers hairline (extracted as a property ONLY to keep
    /// `body` inside the type-checker's budget — the emitted view is
    /// the centralized panel separator, 1 pt in-flow like the old
    /// Divider, stretched through the titlebar safe-area gap to the
    /// very top and bottom.
    private var editorAnswerDivider: some View {
        Color(nsColor: Design.panelSeparator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(edges: .vertical)
            .allowsHitTesting(false)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                // Track the ACTUAL rendered column width (user resizes
                // included) so the window resize response always uses the
                // true value.
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.width, initial: true) { _, w in
                                if w > 0 { sidebarWidth = w }
                            }
                    }
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Editor and answer column share the same detail top, so a row's
            // editor-content y equals its answer-content y (modulo the fixed
            // editor top inset) and scroll offsets are directly comparable.
            HStack(spacing: 0) {
                GeometryReader { _ in
                    let settings = model.settings
                    let sheet = model.selectedSheet
                    // Reference-aware evaluation: the SAME one-row-per-
                    // logical-line result as before, plus the live state
                    // of every token marker the editor renders.
                    let resolved = resolveSheet(
                        content: sheet?.content ?? "",
                        lineIDs: sheet?.lineIDs ?? [],
                        references: sheet?.references ?? [],
                        rates: model.rates,
                        decimalPlaces: settings.decimalPlaces,
                        constants: settings.customConstants
                    )
                    // r43: the editor view (identical tree; the
                    // initializer is a method for the type-checker's
                    // budget).
                    editorView(sheet: sheet, settings: settings, resolved: resolved)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Editor|answers hairline: 1 pt in-flow (same footprint
                // as the old Divider, so editor/answer widths stay
                // stable), full height to the very top and bottom.
                editorAnswerDivider

                let settings = model.settings
                // r37: the hovered token's source line in the CURRENT
                // content (stable ID → current index; nil when the
                // source no longer exists).
                let highlightedSourceLineIndex: Int? = {
                    guard let id = hoveredSourceID,
                          let sheet = model.selectedSheet else { return nil }
                    return sheet.lineIDs.firstIndex(of: id)
                }()
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
                        decimalPlaces: settings.decimalPlaces,
                        constants: settings.customConstants
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
                        answerDoubleTap(lineIndex: lineIndex,
                                        sheetID: model.selectedSheet?.id,
                                        bridge: editorBridge)
                    },
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    decimalPlaces: settings.decimalPlaces,
                    fontDesign: settings.styling.fontDesign,
                    totalLabel: L10n.t("total", language: settings.language),
                    highlightedSourceLineIndex: highlightedSourceLineIndex
                )
            }
            .toolbar(removing: .title)
        }
        .frame(minWidth: 600, minHeight: 260)
        // Window chrome + the sidebar-toggle window resize response.
        .background(WindowConfigurator(
            columnVisibility: columnVisibility,
            sidebarWidth: sidebarWidth,
            reduceMotion: reduceMotion
        ))
        // Reset the editor-bound state when the selected SHEET ID changes,
        // not only the numeric index: deleting the selected non-last row
        // changes the ID under an unchanged index, and stale answer
        // geometry (or a dead bridge) from the previous sheet would flash
        // or drift. The new coordinator re-arms itself via onReady.
        .onChange(of: model.selectedSheet?.id) { _, _ in
            topOffset = 0
            metrics = LineMetrics(lines: [])
            editorBridge = nil
            // r37: a stale hover from the previous sheet can never
            // highlight the new one.
            hoveredSourceID = nil
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
        .onAppear {
            Task { @MainActor in
                await model.loadRates()
                // The main window may not be key during the first layout
                // pass (and a stale autosaved frame can sit off-screen);
                // retry a few times so the designed default size and
                // centered position always apply on launch.
                for _ in 0..<15 {
                    if let window = NSApp.keyWindow
                        ?? NSApp.windows.first(where: { $0.isVisible }) {
                        // window.center() is a no-op when the window is
                        // fully off another display (its screen is nil),
                        // so place the designed 800x600 frame explicitly
                        // in the visible area of the PRIMARY display
                        // (screens.first), never a secondary one a stale
                        // autosaved frame may have pointed to.
                        window.setContentSize(NSSize(width: 800, height: 600))
                        let primary = NSScreen.screens.first
                        if let vf = (primary ?? NSScreen.main)?.visibleFrame,
                           vf.width >= 800, vf.height >= 600 {
                            let x = vf.minX + (vf.width - window.frame.width) / 2
                            let y = vf.minY + (vf.height - window.frame.height) / 2
                            window.setFrame(
                                NSRect(x: x, y: y,
                                       width: window.frame.width,
                                       height: window.frame.height),
                                display: true)
                        } else {
                            window.center()
                        }
                        break
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }
}

/// Grabs the hosting NSView's window once it exists and applies window
/// chrome the SwiftUI scene APIs cannot express: no titlebar separator
/// strip, the dynamic minimum size, and the resize response to the system
/// sidebar toggle. The representable's view is in the hierarchy, so
/// `view.window` is the real window (unlike NSApp.keyWindow, which can be
/// nil while the scene is still coming up).
///
/// Sidebar-toggle behavior: when the user hides the sidebar via the SYSTEM
/// toggle, the window narrows by the measured sidebar column width with the
/// RIGHT edge fixed (detail width stays stable instead of filling the
/// vacated space); showing it again widens leftward and restores the
/// previous frame. The math is the pure, tested
/// `SidebarWindowGeometry` helper — repeated cycles carry no drift.
private struct WindowConfigurator: NSViewRepresentable {
    var columnVisibility: NavigationSplitViewVisibility
    var sidebarWidth: CGFloat
    var reduceMotion: Bool

    private let expandedMinWidth: CGFloat = 800
    private let collapsedMinWidth: CGFloat = 600
    private let minHeight: CGFloat = 560

    @MainActor
    final class Coordinator {
        var lastVisibility: NavigationSplitViewVisibility = .all
        var chromeObserver: NSObjectProtocol?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.lastVisibility = columnVisibility
        Task { @MainActor in
            guard let window = view.window else { return }
            window.minSize = NSSize(width: expandedMinWidth, height: minHeight)
            applyNoSeparatorChrome(to: window)
            // SwiftUI re-asserts the default chrome during later layout and
            // activation passes; hold the override. The token is removed in
            // dismantleNSView so no observer outlives the representable.
            context.coordinator.chromeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in applyNoSeparatorChrome(to: window) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        guard coord.lastVisibility != columnVisibility else { return }
        let nowVisible = columnVisibility == .all
        coord.lastVisibility = columnVisibility
        Task { @MainActor in
            guard let window = nsView.window else { return }
            window.minSize = NSSize(width: nowVisible ? expandedMinWidth : collapsedMinWidth,
                                    height: minHeight)
            let frame = window.frame
            let edge = SidebarWindowGeometry.Edge(originX: frame.minX, width: frame.width)
            let screenVisible: ClosedRange<CGFloat>? = window.screen.map {
                $0.visibleFrame.minX...$0.visibleFrame.maxX
            }
            let target: SidebarWindowGeometry.Edge = nowVisible
                ? SidebarWindowGeometry.expanded(from: edge, sidebarWidth: sidebarWidth,
                                                 screenVisible: screenVisible)
                : SidebarWindowGeometry.collapsed(from: edge, sidebarWidth: sidebarWidth,
                                                  minWidth: collapsedMinWidth,
                                                  screenVisible: screenVisible)
            guard abs(target.originX - frame.minX) > 0.5
                || abs(target.width - frame.width) > 0.5 else { return }
            var newFrame = frame
            newFrame.origin.x = target.originX
            newFrame.size.width = target.width
            // Native frame animation; bottom/height unchanged. Reduce Motion
            // gets the non-animated variant.
            if reduceMotion {
                window.setFrame(newFrame, display: true)
            } else {
                window.animator().setFrame(newFrame, display: true)
            }
        }
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let obs = coordinator.chromeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
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
