import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

struct ContentView: View {
    var model: AppModel
    /// The EFFECTIVE color scheme: `.system` (Auto) follows macOS here,
    /// and the pinned modes are forced by the root's
    /// `preferredColorScheme`, so this single environment read is the
    /// authoritative effective appearance for every AppKit-backed
    /// surface (the editor especially).
    @Environment(\.colorScheme) private var colorScheme
    /// True while a welcome reveal owns the window: the native sidebar
    /// toggle stays hidden until the transition has finished. Transient
    /// environment state only — nothing here is persisted.
    @Environment(\.sidebarToggleHiddenForWelcome) private var sidebarToggleHiddenForWelcome
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
        // r77c: trace the double-click hop from the catcher into the
        // model (sheet identity at fire time + editor snapshot result).
        guard let sheetID else {
            Diagnostics.shared?.log("answerDoubleTap ABORT sheet-nil line=\(lineIndex)")
            return
        }
        let snap = bridge?.selectionSnapshot(sheetID: sheetID)
        let bridgeSheet = bridge?.sheetID?.uuidString.prefix(4) ?? "nil"
        let modelSel = model.selectedSheet.map { $0.id.uuidString.prefix(4) } ?? "nil"
        let snapDesc = snap.map { "\($0.location)+\($0.length)" } ?? "nil"
        Diagnostics.shared?.log("answerDoubleTap line=\(lineIndex) sheet=\(sheetID.uuidString.prefix(4)) modelSelected=\(modelSel) bridgeSheet=\(bridgeSheet) snapshot=\(snapDesc)")
        guard let range = snap else { return }
        model.insertToken(sourceLineIndex: lineIndex, selection: range)
    }

    /// r55: the weather refresh identity — selected sheet ID plus the
    /// sorted canonical query signature of its content.
    private var weatherTaskID: String {
        let sheet = model.selectedSheet
        let sig = WeatherQuery.signature(
            for: WeatherQuery.scanQueries(in: sheet?.content ?? ""))
        return (sheet?.id.uuidString ?? "none") + "\n" + sig
    }

    /// r85: the geography refresh identity — the same formula as the
    /// weather one, over the geo query set.
    private var geoTaskID: String {
        let sheet = model.selectedSheet
        let sig = GeoQueryParse.signature(
            for: GeoQueryParse.scanQueries(in: sheet?.content ?? ""))
        return (sheet?.id.uuidString ?? "none") + "\n" + sig
    }

    /// r87: the selected sheet's persistent line highlights (line
    /// UUID → color) — the editor's in-place fill and the answer
    /// pane's row background both read this one map.
    private var editorHighlightFills: [UUID: HighlightColor] {
        Dictionary(uniqueKeysWithValues: (model.selectedSheet?.highlights ?? [])
            .map { ($0.lineID, $0.color) })
    }

    /// r87: the selected sheet's per-line NOTATION overrides (line
    /// UUID → override; absent = Default/follow the global).
    private var notationOverrideMap: [UUID: AnswerNotationOverride] {
        Dictionary(uniqueKeysWithValues: (model.selectedSheet?.answerDisplay ?? [])
            .compactMap { pref in pref.notation.map { (pref.lineID, $0) } })
    }

    /// r87: the Format > Highlight command — every logical line
    /// intersecting the editor's current live selection.
    private func handleHighlightNotification(_ note: Notification) {
        guard let payload = note.object as? HighlightCommandPayload else { return }
        let sel = editorBridge?.selectionHighlightLineIDs()
        guard let sel, let sheetID = sel.sheetID else { return }
        model.setLineHighlight(sheetID: sheetID, lineIDs: sel.lineIDs,
                               color: payload.color)
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
        // r87: the sheet's persistent line highlights (line UUID →
        // color) for the editor's in-place fill rendering.
        let editorHighlightFills = Dictionary(
            uniqueKeysWithValues: (sheet?.highlights ?? []).map { ($0.lineID, $0.color) })
        let onHighlightLines: (Sheet.ID?, [UUID], HighlightColor?) -> Void = {
            sheetID, lineIDs, color in
            model.setLineHighlight(sheetID: sheetID, lineIDs: lineIDs, color: color)
        }
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
            effectiveDark: colorScheme == .dark,
            constants: settings.customConstants,
            numberContext: model.numberContext,
            unitContext: model.unitContext,
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
            onTokenHoverChanged: { id in hoveredSourceID = id },
            lineHighlightFills: editorHighlightFills,
            editorLineIDs: sheet?.lineIDs ?? [],
            onHighlightLines: onHighlightLines,
            appLanguage: settings.language
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
                // r55: ONE weather context per body pass, shared by the
                // editor and answer evaluations below — the two can
                // never render different snapshots in one frame.
                let weatherContext = model.weatherContext
                // r85: ONE geo context per body pass, shared by the
                // editor and answer evaluations below.
                let geoContext = model.geoContext
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
                        constants: settings.customConstants,
                        weather: weatherContext,
                        geo: geoContext,
                        context: model.numberContext,
                        unitContext: model.unitContext,
                        preferences: settings.temporal
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
                // r51: per-answer rounding overrides by stable line ID
                // (sanitized here so the view only ever sees live IDs).
                let answerSheet = model.selectedSheet
                let answerLineIDs: [UUID] = answerSheet?.lineIDs ?? []
                let answerRounding: [UUID: Int] = {
                    guard let s = answerSheet else { return [:] }
                    let clean = AnswerDisplay.sanitize(s.answerDisplay, lineIDs: s.lineIDs)
                    return Dictionary(uniqueKeysWithValues: clean.map { ($0.lineID, $0.decimalPlaces) })
                }()
                let rows: [SheetLine] = {
                    let sheet = model.selectedSheet
                    return resolveSheet(
                        content: sheet?.content ?? "",
                        lineIDs: sheet?.lineIDs ?? [],
                        references: sheet?.references ?? [],
                        rates: model.rates,
                        decimalPlaces: settings.decimalPlaces,
                        constants: settings.customConstants,
                        weather: weatherContext,
                        geo: geoContext,
                        context: model.numberContext,
                        unitContext: model.unitContext,
                        preferences: settings.temporal
                    ).lines
                }()
                // r77b: per-line result state for the answer-appearance
                // motion model, parallel to `rows`: stable line ID + the
                // row's displayed answer key (the SAME string the answer
                // view crossfades on), nil for quiet lines (blank,
                // heading, error, broken token). A quiet→result edge is
                // what starts a fade-in — reporting from the view (the
                // only place results are known) after every re-evaluation
                // is what makes the fade trigger on the FIRST answer of
                // an existing line, not on line creation.
                let motionEntries: [AnswerMotionEntry] = {
                    guard let sheet = model.selectedSheet else { return [] }
                    var out: [AnswerMotionEntry] = []
                    out.reserveCapacity(rows.count)
                    for line in rows where sheet.lineIDs.indices.contains(line.sourceLineIndex) {
                        let id = sheet.lineIDs[line.sourceLineIndex]
                        // Only real answers get a pass: quiet rows
                        // (blanks, headings, errors, broken tokens) stay
                        // key-less, so a result appearing on any of them
                        // is the quiet→result edge, and errors never dim
                        // the column.
                        var key: String?
                        switch line.result {
                        case .number, .variable, .money, .date, .boolean:
                            let places = AnswerDisplay.effective(
                                defaultPlaces: settings.decimalPlaces,
                                override: answerRounding[id])
                            key = AnswerDisplay.text(
                                for: line.result,
                                decimalPlaces: places,
                                context: model.numberContext)
                        default:
                            key = nil
                        }
                        out.append(AnswerMotionEntry(id: id, key: key))
                    }
                    return out
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
                    lineIDs: answerLineIDs,
                    roundingOverrides: answerRounding,
                    language: settings.language,
                    onSetRounding: { idx, places in model.setAnswerRounding(at: idx, places: places) },
                    onDeleteLine: { idx in model.deleteSourceLine(at: idx) },
                    fontDesign: settings.styling.fontDesign,
                    totalLabel: L10n.t("total", language: settings.language),
                    showTotalBar: settings.showTotalBar,
                    highlightedSourceLineIndex: highlightedSourceLineIndex,
                    numberContext: model.numberContext,
                    // r77: per-line fade-in opacities of the answer
                    // appearance pass (empty = every row fully opaque).
                    answerOpacities: model.answerOpacities,
                    presentation: settings.presentation,
                    notationOverrides: notationOverrideMap,
                    columnAlignment: settings.styling.answerColumnAlignment,
                    columnSurface: settings.styling.answerColumnSurface,
                    highlightFills: editorHighlightFills,
                    onSetNotation: { idx, notation in
                        model.setAnswerNotation(at: idx, notation: notation)
                    },
                    onRestoreFormatting: { idx in
                        model.resetAnswerFormatting(at: idx)
                    }
                )
                // r77b: report the per-line result state to the motion
                // model. `initial: true` delivers the INITIAL load state
                // on first appearance (the sheet is seeded pending in
                // AppModel.init, so this adopts silently — loaded answers
                // never replay); every later re-evaluation (edits, token
                // insertions, sheet switches) arrives as a change — the
                // quiet→result edges among them start the fade-in passes.
                .onChange(of: motionEntries, initial: true) { _, newEntries in
                    // r77c: record what the observation saw (compact).
                    let desc = newEntries.prefix(8).map {
                        let k = $0.key.map { String($0.prefix(5)) } ?? "q"
                        return $0.id.uuidString.prefix(4) + ":" + k
                    }.joined(separator: " ")
                    Diagnostics.shared?.log("motion.onChange n=\(newEntries.count) \(desc)")
                    model.noteAnswerResultActivity(newEntries)
                }
            }
            .toolbar(removing: .title)
        }
        // r59: the compact content minimum (MainWindowGeometry — the
        // same source of truth the scene root and the WindowConfigurator
        // consume, so no drifting magic numbers).
        .frame(minWidth: MainWindowGeometry.contentMinWidth,
               minHeight: MainWindowGeometry.minContentHeight)
        // Window chrome + the sidebar-toggle window resize response.
        .background(WindowConfigurator(
            columnVisibility: columnVisibility,
            sidebarWidth: sidebarWidth,
            reduceMotion: reduceMotion,
            hideSidebarButtonWhenCollapsed: model.settings.hideSidebarButtonWhenCollapsed,
            forceHideSidebarButton: sidebarToggleHiddenForWelcome
        ))
        // Reset the editor-bound state when the selected SHEET ID changes,
        // not only the numeric index: deleting the selected non-last row
        // changes the ID under an unchanged index, and stale answer
        // geometry from the previous sheet would flash or drift.
        // r77c: `editorBridge` is intentionally NOT nilled here. A
        // sheet switch recreates the editor (`.id(sheet.id)`) and its
        // coordinator re-arms via onReady — but whether onReady or this
        // onChange action ran last was a frame-ordering coin flip, and
        // a reset that landed AFTER onReady left the bridge nil for the
        // WHOLE lifetime of the new sheet: every answer double-click
        // (token insertion) on a freshly created or switched-to sheet
        // aborted on the dead bridge. The stale bridge is harmless:
        // selectionSnapshot guards on the coordinator's sheetID (a
        // mismatched snapshot is a no-op), and forwardScrollWheel no-ops
        // while the coordinator's scroll view is detached from a window.
        .onChange(of: model.selectedSheet?.id) { _, _ in
            topOffset = 0
            metrics = LineMetrics(lines: [])
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
        // r87: Format > Highlight — every logical line intersecting
        // the editor's current live selection (a collapsed caret
        // targets its own line, the trailing empty line included). The
        // bridge is sheet-ID guarded; a stale/missing bridge is a
        // no-op. Selection, caret, focus and scroll are untouched.
        .onReceive(NotificationCenter.default.publisher(for: .applyHighlight)) { note in
            handleHighlightNotification(note)
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
        // r55: weather refresh trigger — selected sheet ID plus the
        // deterministic unique-query signature. Body re-renders
        // (rounding, theme, hover) keep the same ID and refetch
        // nothing; any query change re-runs exactly once (the previous
        // run is cancelled), debounced inside the model so partial
        // keystrokes never geocode.
        .task(id: weatherTaskID) {
            let content = model.selectedSheet?.content ?? ""
            guard let sheetID = model.selectedSheet?.id else { return }
            await model.refreshWeather(content: content, sheetID: sheetID)
        }
        // r85: geography refresh trigger — same debounce/cancel
        // discipline as the weather one, geocoding only.
        .task(id: geoTaskID) {
            let content = model.selectedSheet?.content ?? ""
            guard let sheetID = model.selectedSheet?.id else { return }
            await model.refreshGeo(content: content, sheetID: sheetID)
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
                        // r59: the designed default CONTENT size
                        // (MainWindowGeometry). window.center() is a no-op
                        // when the window is fully off another display
                        // (its screen is nil), so the frame is placed
                        // explicitly in the visible area of the PRIMARY
                        // display (screens.first), never a secondary one a
                        // stale autosaved frame may have pointed to.
                        window.setContentSize(NSSize(width: MainWindowGeometry.defaultContentWidth,
                                                   height: MainWindowGeometry.defaultContentHeight))
                        let primary = NSScreen.screens.first
                        if let vf = (primary ?? NSScreen.main)?.visibleFrame,
                           vf.width >= MainWindowGeometry.defaultContentWidth,
                           vf.height >= MainWindowGeometry.defaultContentHeight {
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
    /// r61: keyboard-only sidebar reopening — hide the native toggle
    /// button while the sidebar is collapsed. Applied via AppKit
    /// `NSToolbarItem.isHidden` (identity-preserving, reclaims toolbar
    /// space); never removed/reinserted.
    var hideSidebarButtonWhenCollapsed: Bool

    /// r105: the welcome/replay transition asks for the NATIVE sidebar
    /// toggle to be hidden while the curtain covers or travels. It is OR-ed
    /// with the saved collapsed preference, so the transition can only ever
    /// HIDE the item — never force it visible against the user's setting.
    var forceHideSidebarButton: Bool

    /// ONE definition of the effective rule, used by every path (make,
    /// update, key re-assert and the toolbar item observer).
    @MainActor
    static func effectiveSidebarButtonHidden(preference: Bool,
                                             collapsed: Bool,
                                             forced: Bool) -> Bool {
        forced || (preference && collapsed)
    }

    /// r59: the exact FRAME floor enforcing the 260 pt CONTENT minimum.
    /// `frameRect(forContentRect:)` is the AppKit style-based
    /// content→frame conversion, so the titlebar/toolbar contribution
    /// is measured, never guessed: setting a raw frame height of 260
    /// would leave LESS than 260 pt of content. Widths stay the
    /// long-standing frame floors (800 expanded / 600 collapsed).
    @MainActor
    private static func minFrameSize(for window: NSWindow,
                                     sidebarVisible: Bool) -> NSSize {
        let probe = window.frameRect(forContentRect: NSRect(
            x: 0, y: 0, width: 100,
            height: MainWindowGeometry.minContentHeight))
        return NSSize(
            width: sidebarVisible
                ? MainWindowGeometry.expandedMinFrameWidth
                : MainWindowGeometry.collapsedMinFrameWidth,
            height: probe.height)
    }

    @MainActor
    final class Coordinator {
        var lastVisibility: NavigationSplitViewVisibility = .all
        var chromeObserver: NSObjectProtocol?
        /// r61: latest inputs for the key-reassertion observer (which
        /// outlives any single representable struct value).
        var hidePreference = false
        var collapsed = false
        /// r105: latest welcome/replay force flag, kept for the key and
        /// toolbar-item re-assertion paths.
        var forcedHide = false
        /// Observes toolbar item installation so a late-installed button is
        /// hidden immediately instead of flashing. Removed in dismantle.
        var itemObserver: NSObjectProtocol?

        @MainActor
        func reapply(to window: NSWindow?) {
            guard let window else { return }
            let hide = WindowConfigurator.effectiveSidebarButtonHidden(
                preference: hidePreference, collapsed: collapsed, forced: forcedHide)
            applySidebarButtonVisibility(to: window, hide: hide)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.lastVisibility = columnVisibility
        context.coordinator.hidePreference = hideSidebarButtonWhenCollapsed
        context.coordinator.collapsed = columnVisibility != .all
        context.coordinator.forcedHide = forceHideSidebarButton
        Task { @MainActor in
            guard let window = view.window else { return }
            window.minSize = Self.minFrameSize(for: window, sidebarVisible: true)
            applyNoSeparatorChrome(to: window)
            // r61: the toolbar is installed after this make pass, so
            // apply now (in case it already exists) plus one bounded
            // next-run-loop retry; every key reassertion below
            // re-applies idempotently. No polling, no timer.
            let coord = context.coordinator
            // Apply now, then over the NEXT RENDER TURNS — the toolbar is
            // installed asynchronously, and the curtain can start lifting
            // ~24 ms after this mount, so a single late retry would let the
            // toggle flash. Bounded (five steps), event-driven, no poller.
            coord.reapply(to: window)
            for step in [8, 16, 24, 48, 96] as [UInt64] {
                try? await Task.sleep(nanoseconds: step * 1_000_000)
                coord.reapply(to: window)
            }
            // SwiftUI re-asserts the default chrome during later layout and
            // activation passes; hold the override. The token is removed in
            // dismantleNSView so no observer outlives the representable.
            context.coordinator.chromeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in
                    applyNoSeparatorChrome(to: window)
                    // r61: re-assert the toggle visibility — the toolbar
                    // can be rebuilt on activation, which would drop the
                    // hidden flag. Coordinator holds the LATEST inputs.
                    coord.reapply(to: window)
                }
            }
            // A toolbar rebuilt later (item added after our retries) is
            // caught here instead of flashing: the notification's object is
            // the toolbar, so only OUR window's toolbar triggers a re-apply.
            context.coordinator.itemObserver = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification, object: nil, queue: .main
            ) { note in
                guard let toolbar = note.object as? NSToolbar else { return }
                Task { @MainActor in
                    guard toolbar === view.window?.toolbar else { return }
                    coord.reapply(to: view.window)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        // r61: hidden-state first — a preference-only change must hide
        // or restore the button immediately even when the visibility
        // guard below suppresses the width resize. Idempotent. The
        // coordinator keeps the latest inputs for key reassertion.
        coord.hidePreference = hideSidebarButtonWhenCollapsed
        coord.collapsed = columnVisibility != .all
        coord.forcedHide = forceHideSidebarButton
        if let window = nsView.window {
            let w = window
            Task { @MainActor in coord.reapply(to: w) }
        }
        guard coord.lastVisibility != columnVisibility else { return }
        let nowVisible = columnVisibility == .all
        coord.lastVisibility = columnVisibility
        Task { @MainActor in
            guard let window = nsView.window else { return }
            window.minSize = Self.minFrameSize(for: window, sidebarVisible: nowVisible)
            let frame = window.frame
            let edge = SidebarWindowGeometry.Edge(originX: frame.minX, width: frame.width)
            let screenVisible: ClosedRange<CGFloat>? = window.screen.map {
                $0.visibleFrame.minX...$0.visibleFrame.maxX
            }
            let target: SidebarWindowGeometry.Edge = nowVisible
                ? SidebarWindowGeometry.expanded(from: edge, sidebarWidth: sidebarWidth,
                                                 screenVisible: screenVisible)
                : SidebarWindowGeometry.collapsed(from: edge, sidebarWidth: sidebarWidth,
                                                  minWidth: MainWindowGeometry.collapsedMinFrameWidth,
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
        if let obs = coordinator.itemObserver {
            NotificationCenter.default.removeObserver(obs)
            coordinator.itemObserver = nil
        }
    }
}

/// r61: native sidebar toggle identifiers. SwiftUI's NavigationSplitView
/// installs its toggle under its own namespaced identifier (observed at
/// runtime: `com.apple.SwiftUI.navigationSplitView.toggleSidebar`), not
/// the classic `NSToolbarToggleSidebarItemIdentifier` — match both so
/// the lookup survives either host. `isHidden` keeps the item installed
/// (identity, customization, responder wiring intact) while reclaiming
/// its toolbar space; a missing toolbar/item is a silent no-op covered
/// by the configurator's retry and key-reassertion paths.
@MainActor
private func applySidebarButtonVisibility(to window: NSWindow, hide: Bool) {
    guard let item = window.toolbar?.items.first(where: { $0.itemIdentifier == .toggleSidebar || $0.itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" }) else { return }
    if item.isHidden != hide { item.isHidden = hide }
}

@MainActor
private func applyNoSeparatorChrome(to window: NSWindow) {    // The horizontal strip at the top of the detail area is the window
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
                                 lineIDs: s.lineIDs, references: s.references,
                                 answerDisplay: s.answerDisplay, highlights: s.highlights)
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
