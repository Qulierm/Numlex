import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

struct ContentView: View {
    var model: AppModel

    /// ContentView is constructed exactly ONCE, as `ContentView(model:)`,
    /// so this is where the normal sidebar visibility is seeded from the
    /// settings store. The attached-window coordinator records that value as
    /// its initial visibility baseline, so a hidden-sidebar launch is never
    /// mistaken for a user toggle or resized a second time.
    init(model: AppModel) {
        self.model = model
        _columnVisibility = State(initialValue: model.settings.sidebarVisible ? .all : .detailOnly)
    }
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
    /// Session-only export/print options and the frozen presentation.
    @State private var exportPresentation: ExportPresentation?
    @State private var exportOptions = ExportOptions()
    /// Localized failure alert (PDF write errors only happen after the
    /// user chose a destination; cancel is side-effect free).
    @State private var exportErrorMessage: String?
    /// r37: the STABLE source line ID of the token the pointer is
    /// hovering (ephemeral UI state — never persisted). Mapped against
    /// the CURRENT sheet's lineIDs at render time, so insertions and
    /// deletions above the source keep the highlight on the same line
    /// and a missing source maps to nil.
    @State private var hoveredSourceID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Session-only presentation state, owned by this ContentView/window.
    @State private var isMinimalMode = false
    @State private var owningWindowReady = false
    @State private var minimalModeCommandAvailable = false
    /// Only the ready main-window scene publishes a command target. Its live
    /// setter rechecks eligibility and changes this ContentView's state only.
    private var minimalModeCommandContext: MinimalModeCommandContext? {
        let enabled = owningWindowReady && minimalModeCommandAvailable
        guard enabled else { return nil }
        return MinimalModeCommandContext(
            isEnabled: enabled,
            isOn: Binding(
                get: { isMinimalMode },
                set: { requested in
                    guard owningWindowReady && minimalModeCommandAvailable,
                          requested != isMinimalMode else { return }
                    isMinimalMode = requested
                }))
    }
    /// The native sidebar command talks to the effective visibility, while
    /// the persisted normal choice remains in `columnVisibility`.
    private var effectiveColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                let visible = MinimalModePresentation.sidebarVisible(
                    isMinimalMode: isMinimalMode,
                    normalSidebarVisible: columnVisibility == .all)
                if isMinimalMode { return .detailOnly }
                return visible ? .all : columnVisibility
            },
            set: { requested in
                if isMinimalMode && requested == .detailOnly { return }
                if isMinimalMode { isMinimalMode = false }
                guard columnVisibility != requested else { return }
                columnVisibility = requested
            })
    }
    /// Live measured width of the sidebar column (tracks user resizes
    /// within 180...220). The window resize response uses this value, not
    /// a hardcoded ideal, so the width delta always matches the column.
    @State private var sidebarWidth: CGFloat = 190
    /// Live measured width of the detail pane (editor + divider +
    /// answer column). Drives the answer column's window cap: the
    /// effective width keeps the editor at least
    /// `AnswerColumnGeometry.editorMinimumWidth` wide.
    @State private var detailWidth: CGFloat = 0
    /// The answer-column width preference captured when the current
    /// divider drag started (nil outside a drag). The drag's one
    /// on-end persist is skipped when the final value equals this
    /// (a no-op click/drag never writes to disk).
    @State private var answerDragStartPref: Double?
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
        // Package 7: the dispatch already routed a successful,
        // non-dynamic row here — mint the token at the live selection.
        model.insertToken(sourceLineIndex: lineIndex, selection: range)
    }

    /// Package 7: double-click on an EMPTY answer row — the shared pure
    /// planner validates the target (whitespace-only or strict
    /// `<name> =`) and inserts `subtotal`; a rejection beeps and
    /// changes nothing. The live bridge snapshot is the marked-text +
    /// sheet-ID guard.
    private func emptyAnswerDoubleTap(lineIndex: Int,
                                      sheetID: Sheet.ID?,
                                      bridge: NotebookEditorCoordinator?) {
        guard let sheetID else { return }
        guard let range = bridge?.selectionSnapshot(sheetID: sheetID) else { return }
        if !model.addSubtotalCommand(grand: false, selection: range,
                                     targetLineIndex: lineIndex) {
            NSSound.beep()
        }
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

    /// Package 7: the localized footer-statistic name.
    private func footerStatisticLabel(_ statistic: FooterStatistic,
                                      language: AppLanguage) -> String {
        let key: String
        switch statistic {
        case .sum: key = "footerSum"
        case .average: key = "footerAverage"
        case .count: key = "footerCount"
        case .median: key = "footerMedian"
        }
        return L10n.t(key, language: language)
    }

    /// Package 7: Convert to Normal Line from the answer context menu.
    private func handleConvertToNormal(_ index: Int) {
        _ = model.convertSubtotalRowToNormal(at: index)
    }

    /// Package 7: the Add Subtotal / Add Grand Total command handler —
    /// the live bridge snapshot is the marked-text + sheet-ID guard; a
    /// rejected plan beeps and changes nothing.
    private func handleAddSubtotal(grand: Bool) {
        guard let sheetID = model.selectedSheet?.id,
              let selection = editorBridge?.selectionSnapshot(sheetID: sheetID) else {
            NSSound.beep()
            return
        }
        if !model.addSubtotalCommand(grand: grand, selection: selection) {
            NSSound.beep()
        }
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

    /// r90: THE effective notebook line height for the current typography
    /// — the legacy `settings.lineHeight` stays the floor, an installed
    /// font with taller natural metrics raises it. Computed ONCE here and
    /// handed identically to the editor, the answer column and the
    /// settings preview so their geometry cannot diverge.
    private func effectiveLineHeight(_ settings: AppSettings) -> Double {
        NotebookPalette.effectiveLineHeight(styling: settings.styling,
                                            requested: settings.lineHeight,
                                            fontSize: settings.fontSize)
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
        // Package 7: stable line IDs of the exact `---` divider rows.
        let dividerLineIDs: Set<UUID> = {
            guard let sheet else { return [] }
            var ids = Set<UUID>()
            for line in resolved.lines where line.metadata == .divider {
                if sheet.lineIDs.indices.contains(line.sourceLineIndex) {
                    ids.insert(sheet.lineIDs[line.sourceLineIndex])
                }
            }
            return ids
        }()
        let onHighlightLines: (Sheet.ID?, [UUID], HighlightColor?) -> Void = {
            sheetID, lineIDs, color in
            model.setLineHighlight(sheetID: sheetID, lineIDs: lineIDs, color: color)
        }
        return NotebookEditor(
            text: binding,
            sheetID: sheet?.id,
            fontSize: settings.fontSize,
            // r90: the ONE effective line height (see `effectiveLineHeight`).
            lineHeight: effectiveLineHeight(settings),
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
            financial: model.financialContext,
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
            dividerLineIDs: dividerLineIDs,
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

    /// One frozen export/print presentation: the captured contexts,
    /// the mode and the paper size resolved when the dialog opened.
    struct ExportPresentation: Identifiable {
        let id = UUID()
        let mode: ExportDialogMode
        let context: ExportPresentationContext
        let paperSize: CGSize
    }

    /// Captures the selected sheet and ALL app-global evaluation and
    /// presentation contexts at dialog presentation (one `now` for the
    /// whole captured pass) and clamps the session options to the new
    /// sheet. Reads only: no sheet/store/settings/editor mutation.
    private func presentExport(_ mode: ExportDialogMode) {
        guard let sheet = model.selectedSheet else { return }
        let settings = model.settings
        let context = ExportPresentationContext(
            sheetID: sheet.id,
            sheetTitle: sheet.title,
            content: sheet.content,
            lineIDs: sheet.lineIDs,
            references: sheet.references,
            answerDisplay: sheet.answerDisplay,
            highlights: sheet.highlights,
            rates: model.rates,
            decimalPlaces: settings.decimalPlaces,
            now: Date(),
            calendar: Calendar.current,
            constants: settings.customConstants,
            weather: model.weatherContext,
            geo: model.geoContext,
            numberContext: model.numberContext,
            unitContext: model.unitContext,
            preferences: settings.temporal,
            financial: model.financialContext,
            presentation: settings.presentation,
            language: settings.language,
            styling: settings.styling,
            random: model.currentRandomContext,
            // Floating Total: the frozen statistic AND contribution
            // policy travel with the presentation, so a full-range export
            // prints exactly the total the sheet shows, while a range or
            // filter applies the policy to the rows it kept.
            footerStatistic: settings.footerStatistic,
            footerPolicy: settings.footerContributionPolicy,
            // Numbers ▸ Auto-convert: the frozen measurement system, so
            // the printed answers/total equal the live ones.
            localUnits: model.localUnitContext)
        exportOptions = exportOptions.clamped(toLineCount: context.lineCount)
        exportPresentation = ExportPresentation(
            mode: mode,
            context: context,
            paperSize: NSPrintInfo.shared.paperSize)
    }

    /// The ONE rendered document for the frozen presentation: same
    /// snapshot, same fonts, same palette, same pagination for PDF and
    /// print.
    private func renderedDocument(for presentation: ExportPresentation) throws -> ExportRenderedDocument {
        let snapshot = try ExportSnapshotBuilder.build(context: presentation.context,
                                                       options: exportOptions).get()
        // Document construction consumes ONLY the frozen presentation
        // and the session options — never live settings.
        let styling = presentation.context.styling
        let fonts = ExportFontCatalog.fonts(options: exportOptions,
                                            styling: styling)
        let palette = ExportPalette.printPalette(styling: styling)
        let metrics = fonts.metrics(pageSize: presentation.paperSize)
        return ExportRenderedDocument(snapshot: snapshot, fonts: fonts,
                                      palette: palette, metrics: metrics)
    }

    private static func pdfFileName(for title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? "Sheet" : cleaned
        return name.hasSuffix(".pdf") ? name : name + ".pdf"
    }

    private func handleExportConfirm(_ presentation: ExportPresentation) {
        let doc: ExportRenderedDocument
        do {
            doc = try renderedDocument(for: presentation)
        } catch {
            exportPresentation = nil
            exportErrorMessage = L10n.t("export.emptyRange",
                                        language: model.settings.language)
            return
        }
        exportPresentation = nil
        switch presentation.mode {
        case .pdf:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = Self.pdfFileName(
                for: presentation.context.sheetTitle)
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try doc.writePDF(to: url)
            } catch {
                exportErrorMessage = L10n.t("export.saveError.message",
                                            language: model.settings.language)
            }
        case .print:
            // The options sheet is dismissed above; present the standard
            // print panel on the NEXT main-run-loop turn, so the host
            // window (never the dismissing sheet) owns the modal panel.
            let hostWindow = NSApp.windows.first {
                $0.isVisible && $0.title == "Numlex"
            } ?? NSApp.mainWindow
            DispatchQueue.main.async {
                let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
                info.paperSize = NSSize(width: doc.layout.pageSize.width,
                                        height: doc.layout.pageSize.height)
                info.topMargin = 0
                info.bottomMargin = 0
                info.leftMargin = 0
                info.rightMargin = 0
                info.horizontalPagination = .fit
                info.verticalPagination = .fit
                info.isHorizontallyCentered = false
                info.isVerticallyCentered = false
                let view = ExportPaginatedPrintView(document: doc)
                let operation = NSPrintOperation(view: view, printInfo: info)
                operation.showsPrintPanel = true
                operation.showsProgressPanel = true
                if let hostWindow {
                    operation.runModal(for: hostWindow, delegate: nil,
                                       didRun: nil, contextInfo: nil)
                } else {
                    operation.run()
                }
            }
        }
    }

    /// Editor|answers divider (extracted as a property ONLY to keep
    /// `body` inside the type-checker's budget): the 1 pt centralized
    /// panel separator, stretched through the titlebar safe-area gap
    /// to the very top and bottom, with the centered 12 pt drag hit
    /// zone that resizes the answer column (left drag grows it,
    /// right drag shrinks it; live in-memory, one persist on end).
    private func answerDivider(settings: AppSettings,
                               effectiveWidth: Double) -> some View {
        AnswerColumnResizeHandle(
            displayedWidth: effectiveWidth,
            language: settings.language,
            onChange: { width in
                // The first live change of a drag snapshots the
                // pre-drag preference (before this write), so the
                // on-end persist can skip a no-op.
                if answerDragStartPref == nil {
                    answerDragStartPref = model.settings.styling.answerColumnWidth
                }
                // In-memory only: the column re-lays-out live, the
                // editor yields/gains the same delta; nothing is
                // written to disk mid-drag.
                model.settings.styling.answerColumnWidth = width
            },
            onEnd: { finalWidth in
                // Apply the EXACT final computed width in memory first
                // (the last live write may lag the end tick), then
                // persist exactly ONCE — and only when the preference
                // actually changed vs the pre-drag snapshot.
                model.settings.styling.answerColumnWidth = finalWidth
                let changed = finalWidth != answerDragStartPref
                answerDragStartPref = nil
                if changed { model.persist() }
            }
        )
    }

    /// The answer column (extracted from `body` ONLY to keep the
    /// detail HStack inside the type-checker's budget — the r43
    /// pattern used by `editorView`). The tree is identical to the
    /// inline form: the reference-aware rows, the view's callbacks
    /// and the r77b motion observation all live here, and the column
    /// is laid out at `effectiveWidth` (the persisted 140...400 pt
    /// preference capped by the detail width for the editor minimum).
    private func answerColumn(settings: AppSettings,
                              effectiveWidth: Double,
                              weatherContext: WeatherContext,
                              geoContext: GeoContext) -> some View {
        // r37: the hovered token's source line in the CURRENT content
        // (stable ID → current index; nil when the source no longer
        // exists).
        let highlightedSourceLineIndex: Int? = {
            guard let id = hoveredSourceID,
                  let sheet = model.selectedSheet else { return nil }
            return sheet.lineIDs.firstIndex(of: id)
        }()
        // Reference-aware rows (same strict 1:1 contract as
        // evaluateSheet, with token lines resolved to their current
        // linked values).
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
                preferences: settings.temporal,
                financial: model.financialContext,
                random: model.currentRandomContext,
                localUnits: model.localUnitContext
            ).lines
        }()
        // r77b: per-line result state for the answer-appearance
        // motion model, parallel to `rows`: stable line ID + the row's
        // displayed answer key (the SAME string the answer view
        // crossfades on), nil for quiet lines (blank, heading, error,
        // broken token). A quiet→result edge is what starts a fade-in
        // — reporting from the view (the only place results are known)
        // after every re-evaluation is what makes the fade trigger on
        // the FIRST answer of an existing line, not on line creation.
        let motionEntries: [AnswerMotionEntry] = {
            guard let sheet = model.selectedSheet else { return [] }
            var out: [AnswerMotionEntry] = []
            out.reserveCapacity(rows.count)
            for line in rows where sheet.lineIDs.indices.contains(line.sourceLineIndex) {
                let id = sheet.lineIDs[line.sourceLineIndex]
                // Only real answers get a pass: quiet rows (blanks,
                // headings, errors, broken tokens) stay key-less, so a
                // result appearing on any of them is the quiet→result
                // edge, and errors never dim the column.
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
        return AnswerColumnView(
            width: effectiveWidth,
            rows: rows,
            metrics: metrics,
            topOffset: topOffset,
            onWheelScroll: { event in
                // Answer column wheel: forward the raw NSEvent to the
                // editor's scroll view; the editor stays the single
                // native momentum/elasticity source and its
                // BoundsDidChange drives topOffset back.
                editorBridge?.forwardScrollWheel(event)
            },
            onAnswerDoubleTap: { lineIndex in
                answerDoubleTap(lineIndex: lineIndex,
                                sheetID: model.selectedSheet?.id,
                                bridge: editorBridge)
            },
            onEmptyAnswerDoubleTap: { lineIndex in
                emptyAnswerDoubleTap(lineIndex: lineIndex,
                                     sheetID: model.selectedSheet?.id,
                                     bridge: editorBridge)
            },
            sourceLines: model.selectedSheet?.content
                .components(separatedBy: "\n") ?? [],
            fontSize: settings.fontSize,
            // r90: the SAME effective line height the editor uses.
            lineHeight: effectiveLineHeight(settings),
            decimalPlaces: settings.decimalPlaces,
            lineIDs: answerLineIDs,
            roundingOverrides: answerRounding,
            language: settings.language,
            onSetRounding: { idx, places in model.setAnswerRounding(at: idx, places: places) },
            onDeleteLine: { idx in model.deleteSourceLine(at: idx) },
            onConvertToNormal: { idx in handleConvertToNormal(idx) },
            // r90: the FULL typography selection (built-in design +
            // installed family/face), never a design-only reconstruction.
            styling: settings.styling,
            totalLabel: footerStatisticLabel(settings.footerStatistic,
                                             language: settings.language),
            footerStatistic: settings.footerStatistic,
            onSetFooterStatistic: { model.setFooterStatistic($0) },
            footerAvoidOverlap: settings.footerAvoidOverlap,
            // Floating Total: the same frozen policy + referenced source
            // line IDs the export snapshot uses, so the live statistic and
            // the printed one can never disagree.
            footerPolicy: settings.footerContributionPolicy,
            referencedSourceLineIDs: Set((model.selectedSheet?.references ?? [])
                .map(\.sourceLineID)),
            showTotalBar: MinimalModePresentation.showTotalBar(
                isMinimalMode: isMinimalMode,
                normalShowTotalBar: settings.showTotalBar),
            highlightedSourceLineIndex: highlightedSourceLineIndex,
            numberContext: model.numberContext,
            // r77: per-line fade-in opacities of the answer appearance
            // pass (empty = every row fully opaque).
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
        // r77b: report the per-line result state to the motion model.
        // `initial: true` delivers the INITIAL load state on first
        // appearance (the sheet is seeded pending in AppModel.init, so
        // this adopts silently — loaded answers never replay); every
        // later re-evaluation (edits, token insertions, sheet
        // switches) arrives as a change — the quiet→result edges among
        // them start the fade-in passes.
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

    var body: some View {
        NavigationSplitView(columnVisibility: effectiveColumnVisibility) {
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
                // The answer column's EFFECTIVE width: the persisted
                // preference (140...400) capped by the available detail
                // width so the editor keeps at least 280 pt. Unknown
                // detail widths (before first layout) fall back to the
                // sanitized preference — never negative/NaN.
                let effectiveAnswerWidth = AnswerColumnGeometry.effectiveWidth(
                    preference: model.settings.styling.answerColumnWidth,
                    availableDetailWidth: detailWidth)
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
                        preferences: settings.temporal,
                        financial: model.financialContext,
                        random: model.currentRandomContext,
                        localUnits: model.localUnitContext
                    )
                    // r43: the editor view (identical tree; the
                    // initializer is a method for the type-checker's
                    // budget).
                    editorView(sheet: sheet, settings: settings, resolved: resolved)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Editor|answers divider: 1 pt in-flow (same footprint
                // as the old Divider, so editor/answer widths stay
                // stable) with the centered 12 pt drag hit zone; full
                // height to the very top and bottom.
                answerDivider(settings: model.settings,
                              effectiveWidth: effectiveAnswerWidth)

                // The answer column (identical tree; the initializer is
                // a method for the type-checker's budget, r43 pattern).
                answerColumn(
                    settings: model.settings,
                    effectiveWidth: effectiveAnswerWidth,
                    weatherContext: weatherContext,
                    geoContext: geoContext
                )
            }
            .toolbar(removing: .title)
            // Track the ACTUAL detail width (the editor + divider +
            // answer column) so the answer column's window cap is
            // computed from real geometry, never a hardcoded panel
            // width. A zero/unmeasured width disables the cap (the
            // sanitized preference is used as-is).
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, w in
                            if w > 0 { detailWidth = w }
                        }
                }
            )
        }
        // r59: the compact content minimum (MainWindowGeometry — the
        // same source of truth the scene root and the WindowConfigurator
        // consume, so no drifting magic numbers).
        .frame(minWidth: MainWindowGeometry.contentMinWidth,
               minHeight: MainWindowGeometry.minContentHeight)
        // Window chrome + the sidebar-toggle window resize response.
        .background(WindowConfigurator(
            normalColumnVisibility: columnVisibility,
            minimalMode: isMinimalMode,
            savedNormalFrame: model.settings.windowFrame,
            sidebarWidth: sidebarWidth,
            reduceMotion: reduceMotion,
            hideSidebarButtonWhenCollapsed: model.settings.hideSidebarButtonWhenCollapsed,
            forceHideSidebarButton: sidebarToggleHiddenForWelcome,
            onWindowReady: { owningWindowReady = $0 },
            onMinimalModeCommandAvailability: { minimalModeCommandAvailable = $0 },
            onMinimalModeRequestRejected: { isMinimalMode = $0 },
            onCaptureNormalFrame: rememberWindowFrame,
            onWindowFrameSettled: rememberWindowFrame
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
        .onReceive(NotificationCenter.default.publisher(for: .exportSheetPDF)) { _ in
            presentExport(.pdf)
        }
        .onReceive(NotificationCenter.default.publisher(for: .printSheet)) { _ in
            presentExport(.print)
        }
        .modifier(SubtotalCommandReceiver(handler: handleAddSubtotal,
                                          onRecalculate: { model.recalculateDynamicValues() }))
        .sheet(item: $exportPresentation) { presentation in
            ExportDialogView(
                mode: presentation.mode,
                context: presentation.context,
                language: model.settings.language,
                options: $exportOptions,
                onCancel: { exportPresentation = nil },
                onConfirm: { handleExportConfirm(presentation) })
        }
        .alert(L10n.t("export.saveError.title", language: model.settings.language),
               isPresented: Binding(
                   get: { exportErrorMessage != nil },
                   set: { if !$0 { exportErrorMessage = nil } })) {
            Button(L10n.t("export.ok", language: model.settings.language)) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "")
        }
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
        .fileExporter(isPresented: $showExport, document: NLXDocument(model: model), contentType: .nlx, defaultFilename: SheetExport.suggestedFilename(for: model.selectedSheet?.title ?? "Sheet")) { result in
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
            // Rates are independent of geometry. The attached configurator
            // restores exactly the NSWindow that owns its NSView.
            Task { @MainActor in await model.loadRates() }
        }
        .onChange(of: columnVisibility) { _, visibility in
            // Persist the sidebar's shown/hidden state — in memory first,
            // then ONE store write, and only when it actually differs, so
            // a no-op change never touches the disk (the answer-column
            // width drag follows the same discipline). ContentView.init
            // seeds the state FROM this setting, so the initial value never
            // writes back the preference it just read.
            let visible = visibility == .all
            guard model.settings.sidebarVisible != visible else { return }
            model.settings.sidebarVisible = visible
            model.persist()
        }
        .focusedSceneValue(\.minimalModeCommandContext, minimalModeCommandContext)
    }
    /// Remember the frame the user left the window in.
    ///
    /// Called for a settled normal-frame motion, the normal-mode termination
    /// backstop, or once when capturing the pre-entry normal rectangle.
    /// Compact and transition frames are filtered by the owner before this
    /// callback. The rect is rounded to whole points and compared against the
    /// stored value, so sub-point churn and an unchanged launch restore write
    /// nothing.
    private func rememberWindowFrame(_ frame: CGRect) {
        let settled = SavedWindowFrame(x: frame.origin.x.rounded(),
                                       y: frame.origin.y.rounded(),
                                       width: frame.size.width.rounded(),
                                       height: frame.size.height.rounded())
        guard model.settings.windowFrame != settled else { return }
        model.settings.windowFrame = settled
        model.persist()
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
@MainActor
private final class WindowAttachmentView: NSView {
    var windowAttachmentChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowAttachmentChanged?(window)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    var normalColumnVisibility: NavigationSplitViewVisibility
    var minimalMode: Bool
    var savedNormalFrame: SavedWindowFrame?
    var sidebarWidth: CGFloat
    var reduceMotion: Bool
    /// r61: keyboard-only sidebar reopening — hide the native toggle
    /// button while the sidebar is collapsed. Applied via AppKit
    /// `NSToolbarItem.isHidden` (identity-preserving, reclaims toolbar
    /// space); never removed/reinserted.
    var hideSidebarButtonWhenCollapsed: Bool

    /// r105: the welcome transition asks for the NATIVE sidebar
    /// toggle to be hidden while the curtain covers or travels. It is OR-ed
    /// with the saved collapsed preference, so the transition can only ever
    /// HIDE the item — never force it visible against the user's setting.
    var forceHideSidebarButton: Bool

    /// State callbacks are refreshed from each representable update; geometry
    /// remains scoped to this configurator's attached window.
    var onWindowReady: (Bool) -> Void
    var onMinimalModeCommandAvailability: (Bool) -> Void
    var onMinimalModeRequestRejected: (Bool) -> Void

    /// The pre-entry normal frame is written once through the same rounded,
    /// equality-guarded ContentView writer used for settled normal geometry.
    var onCaptureNormalFrame: (CGRect) -> Void

    /// Called with the window's frame once a move/resize has SETTLED (or
    /// on termination). Coalesced by the coordinator — a window move posts
    /// many notifications and must never persist per frame; ContentView
    /// deduplicates against the stored value on top of that.
    var onWindowFrameSettled: (CGRect) -> Void

    /// ONE definition of the effective rule, used by every path (make,
    /// update, key re-assert and the toolbar item observer).
    @MainActor
    static func effectiveSidebarButtonHidden(preference: Bool,
                                             collapsed: Bool,
                                             forced: Bool,
                                             minimalMode: Bool = false) -> Bool {
        minimalMode || forced || (preference && collapsed)
    }

    /// Existing NORMAL-mode frame floor. Its historical style-based
    /// `frameRect(forContentRect:)` conversion and 800/600 frame widths are
    /// unchanged; Minimal Mode instead uses a live contentLayoutRect delta.
    @MainActor
    static func minFrameSize(for window: NSWindow,
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
        weak var attachedView: WindowAttachmentView?
        weak var attachedWindow: NSWindow?
        var didInitializeAttachedWindow = false
        var isWindowReady = false
        var lastVisibility: NavigationSplitViewVisibility = .all
        var hasVisibilityBaseline = false
        var normalVisibility: NavigationSplitViewVisibility = .all
        var effectiveVisibility: NavigationSplitViewVisibility = .all
        var requestedMinimalMode = false
        var activeMinimalMode = false
        var modeTransitionInFlight = false
        var modeBeforeTransition: Bool?
        var nativeFullScreen = false
        var nativeFullScreenTransition = false
        var normalFrameSnapshot: CGRect?
        /// Measured frame minimum for this coordinator's active compact session.
        var compactModeMinimumSize: NSSize?
        var savedNormalFrame: SavedWindowFrame?
        var sidebarWidth: CGFloat = 190
        var reduceMotion = false

        /// r61: latest inputs for reassertion observers; every callback and
        /// preference is refreshed from the current representable value.
        var hidePreference = false
        var collapsed = false
        var forcedHide = false
        var chromeObserver: NSObjectProtocol?
        var keyResignObserver: NSObjectProtocol?
        var itemObserver: NSObjectProtocol?
        var frameObservers: [NSObjectProtocol] = []
        var fullScreenObservers: [NSObjectProtocol] = []
        var onWindowReady: ((Bool) -> Void)?
        var onMinimalModeCommandAvailability: ((Bool) -> Void)?
        var onMinimalModeRequestRejected: ((Bool) -> Void)?
        var onCaptureNormalFrame: ((CGRect) -> Void)?
        var onFrameSettled: ((CGRect) -> Void)?

        var frameSettleTask: Task<Void, Never>?
        var sidebarResizeTask: Task<Void, Never>?
        var toolbarReassertionTask: Task<Void, Never>?
        var minimalModeMeasurementTask: Task<Void, Never>?
        var geometryRequestGeneration: UInt64 = 0

        static let frameSettleDelay: Duration = .milliseconds(400)
        static let minimalModeAnimationDuration: TimeInterval = 0.18

        func updateInputs(view: WindowAttachmentView,
                          minimalMode: Bool,
                          normalVisibility: NavigationSplitViewVisibility,
                          effectiveVisibility: NavigationSplitViewVisibility,
                          savedNormalFrame: SavedWindowFrame?,
                          sidebarWidth: CGFloat,
                          reduceMotion: Bool,
                          hidePreference: Bool,
                          forcedHide: Bool,
                          onWindowReady: @escaping (Bool) -> Void,
                          onMinimalModeCommandAvailability: @escaping (Bool) -> Void,
                          onMinimalModeRequestRejected: @escaping (Bool) -> Void,
                          onCaptureNormalFrame: @escaping (CGRect) -> Void,
                          onFrameSettled: @escaping (CGRect) -> Void) {
            let welcomeAvailabilityChanged = self.forcedHide != forcedHide
            attachedView = view
            requestedMinimalMode = minimalMode
            self.normalVisibility = normalVisibility
            self.effectiveVisibility = effectiveVisibility
            self.savedNormalFrame = savedNormalFrame
            self.sidebarWidth = sidebarWidth
            self.reduceMotion = reduceMotion
            self.hidePreference = hidePreference
            self.collapsed = effectiveVisibility != .all
            self.forcedHide = forcedHide
            self.onWindowReady = onWindowReady
            self.onMinimalModeCommandAvailability = onMinimalModeCommandAvailability
            self.onMinimalModeRequestRejected = onMinimalModeRequestRejected
            self.onCaptureNormalFrame = onCaptureNormalFrame
            self.onFrameSettled = onFrameSettled
            if !hasVisibilityBaseline {
                lastVisibility = effectiveVisibility
                hasVisibilityBaseline = true
            }
            windowAttachmentChanged(view.window, from: view)
            if isWindowReady {
                if welcomeAvailabilityChanged { publishMinimalModeCommandAvailability() }
                applyLatestInputs()
            }
        }

        /// Own only the NSWindow reached through this representable's view.
        /// Repeated callbacks for the same window cannot restore it twice.
        func windowAttachmentChanged(_ newWindow: NSWindow?, from view: WindowAttachmentView) {
            guard let newWindow else {
                if attachedWindow != nil { detachOwnedWindow() }
                return
            }
            if attachedWindow === newWindow {
                if !didInitializeAttachedWindow { initializeAttachedWindow(newWindow) }
                return
            }
            if attachedWindow != nil { detachOwnedWindow() }
            attachedView = view
            attachedWindow = newWindow
            didInitializeAttachedWindow = false
            isWindowReady = false
            activeMinimalMode = false
            modeTransitionInFlight = false
            nativeFullScreen = newWindow.styleMask.contains(.fullScreen)
            nativeFullScreenTransition = false
            normalFrameSnapshot = nil
            installOwnedWindowObservers(newWindow, view: view)
            initializeAttachedWindow(newWindow)
        }

        /// Exactly-once restore/fallback for the attached owner. Rate loading
        /// and NSApp's key/visible-window state are deliberately irrelevant.
        func initializeAttachedWindow(_ window: NSWindow) {
            guard attachedWindow === window, !didInitializeAttachedWindow else { return }
            didInitializeAttachedWindow = true
            let sidebarVisible = normalVisibility == .all
            let minSize = WindowConfigurator.minFrameSize(for: window,
                                                          sidebarVisible: sidebarVisible)
            window.minSize = minSize
            applyNoSeparatorChrome(to: window)

            let restored = MainWindowGeometry.restoredFrame(
                saved: savedNormalFrame,
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                minimumSize: minSize)
            if let restored {
                // Floor first; MainWindowGeometry keeps an accepted saved
                // origin as-is and rejects frames with less than 100 pt overlap.
                window.setFrame(restored, display: true)
            } else {
                // Preserve the established centered 800x600 CONTENT fallback
                // on the primary display, with center() as the small-screen
                // last resort. SwiftUI frame restoration remains disabled.
                window.setContentSize(NSSize(width: MainWindowGeometry.defaultContentWidth,
                                             height: MainWindowGeometry.defaultContentHeight))
                let primary = NSScreen.screens.first
                if let visible = (primary ?? NSScreen.main)?.visibleFrame,
                   visible.width >= MainWindowGeometry.defaultContentWidth,
                   visible.height >= MainWindowGeometry.defaultContentHeight {
                    let x = visible.minX + (visible.width - window.frame.width) / 2
                    let y = visible.minY + (visible.height - window.frame.height) / 2
                    window.setFrame(NSRect(x: x, y: y,
                                           width: window.frame.width,
                                           height: window.frame.height), display: true)
                } else {
                    window.center()
                }
            }

            lastVisibility = effectiveVisibility
            hasVisibilityBaseline = true
            isWindowReady = true
            onWindowReady?(true)
            publishMinimalModeCommandAvailability()
            reapply(to: window)
            scheduleToolbarReassertions(on: window)
            applyLatestInputs()
        }

        private func installOwnedWindowObservers(_ window: NSWindow,
                                                 view: WindowAttachmentView) {
            chromeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, self.owns(window) else { return }
                    applyNoSeparatorChrome(to: window)
                    self.reapply(to: window)
                    self.publishMinimalModeCommandAvailability()
                }
            }
            keyResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, self.owns(window) else { return }
                    self.publishMinimalModeCommandAvailability()
                }
            }
            itemObserver = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification, object: nil, queue: .main
            ) { [weak self, weak view] note in
                guard let toolbar = note.object as? NSToolbar else { return }
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view, toolbar === view.window?.toolbar else { return }
                    self.reapply(to: view.window)
                }
            }
            for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
                frameObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor [weak self, weak window] in
                        guard let self, let window, self.owns(window) else { return }
                        self.scheduleFrameSettle(window: window, immediate: false)
                    }
                })
            }
            frameObservers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, self.owns(window) else { return }
                    self.scheduleFrameSettle(window: window, immediate: true)
                }
            })
            for name in [NSWindow.willEnterFullScreenNotification,
                         NSWindow.didEnterFullScreenNotification,
                         NSWindow.willExitFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                fullScreenObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor [weak self, weak window] in
                        guard let self, let window, self.owns(window) else { return }
                        self.handleFullScreenEvent(name, window: window)
                    }
                })
            }
        }

        private func scheduleToolbarReassertions(on window: NSWindow) {
            toolbarReassertionTask?.cancel()
            guard let view = attachedView else { return }
            toolbarReassertionTask = Task { @MainActor [weak self, weak window, weak view] in
                guard let self, let window, let view, self.owns(window) else { return }
                self.reapply(to: window)
                for step in [8, 16, 24, 48, 96] as [UInt64] {
                    do { try await Task.sleep(nanoseconds: step * 1_000_000) }
                    catch { return }
                    guard !Task.isCancelled, self.owns(window), view.window === window else { return }
                    self.reapply(to: window)
                }
            }
        }

        private func applyLatestInputs() {
            guard isWindowReady, let window = attachedWindow, owns(window) else { return }
            let minSize: NSSize?
            if requestedMinimalMode {
                // Pending entry keeps the current normal floor until live chrome
                // has been measured. Active mode reapplies only its own cache.
                minSize = compactModeMinimumSize
            } else {
                minSize = WindowConfigurator.minFrameSize(
                    for: window, sidebarVisible: normalVisibility == .all)
            }
            if let minSize, window.minSize != minSize { window.minSize = minSize }
            reapply(to: window)

            let modeChanged = requestedMinimalMode != activeMinimalMode
            let visibilityChanged = lastVisibility != effectiveVisibility
            if modeChanged {
                // Consume the effective sidebar projection in the mode
                // transition. Never layer the ordinary 190 pt delta over it.
                lastVisibility = effectiveVisibility
                beginMinimalModeTransition(to: requestedMinimalMode, window: window)
                return
            }
            guard visibilityChanged else { return }
            lastVisibility = effectiveVisibility
            guard !activeMinimalMode else { return }
            scheduleSidebarResize(window: window,
                                  nowVisible: effectiveVisibility == .all)
        }

        private func beginMinimalModeTransition(to minimal: Bool, window: NSWindow) {
            guard owns(window) else { return }
            traceMinimalModeGeometry(event: "command", window: window, mode: minimal)
            guard isWindowReady, window.isKeyWindow,
                  !nativeFullScreen, !nativeFullScreenTransition else {
                rejectMinimalModeRequest()
                publishMinimalModeCommandAvailability()
                return
            }
            invalidatePendingGeometryRequests()
            geometryRequestGeneration &+= 1
            let generation = geometryRequestGeneration
            let previousMode = activeMinimalMode
            modeBeforeTransition = previousMode
            activeMinimalMode = minimal
            modeTransitionInFlight = true
            // The requested state was reasserted before this transition; apply
            // again after the active projection changes so exit restores the
            // normal collapsed-preference visibility immediately.
            reapply(to: window)
            publishMinimalModeCommandAvailability()

            if minimal {
                if normalFrameSnapshot == nil {
                    let normalFrame = window.frame
                    normalFrameSnapshot = normalFrame
                    onCaptureNormalFrame?(normalFrame)
                }
                scheduleMinimalModeMeasurement(window: window,
                                               generation: generation,
                                               previousMode: previousMode)
                return
            }

            let normalFloor = WindowConfigurator.minFrameSize(
                for: window, sidebarVisible: normalVisibility == .all)
            if window.minSize != normalFloor { window.minSize = normalFloor }
            guard let target = MinimalModeGeometry.restoringFrame(
                cachedNormalFrame: normalFrameSnapshot,
                savedNormalFrame: savedNormalFrame,
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                primaryVisibleFrame: NSScreen.screens.first?.visibleFrame,
                minimumSize: normalFloor) else {
                rejectModeTransition(generation: generation, window: window,
                                     mode: minimal, previousMode: previousMode)
                return
            }
            applyModeFrame(target, to: window, generation: generation, mode: minimal)
        }

        private func scheduleMinimalModeMeasurement(window: NSWindow,
                                                    generation: UInt64,
                                                    previousMode: Bool) {
            guard let view = attachedView else {
                rejectModeTransition(generation: generation, window: window,
                                     mode: true, previousMode: previousMode)
                return
            }
            minimalModeMeasurementTask = Task { @MainActor [weak self, weak window, weak view] in
                await Task.yield()
                guard let self, let window, let view, !Task.isCancelled,
                      self.isCurrentModeMeasurement(generation, window: window, view: view) else {
                    return
                }
                guard let contentView = window.contentView else {
                    self.rejectModeTransition(generation: generation, window: window,
                                              mode: true, previousMode: previousMode)
                    return
                }
                contentView.layoutSubtreeIfNeeded()
                guard !Task.isCancelled,
                      self.isCurrentModeMeasurement(generation, window: window, view: view) else {
                    return
                }
                let frameSize = window.frame.size
                let contentLayoutSize = window.contentLayoutRect.size
                guard let compactSize = MinimalModeGeometry.compactFrameSize(
                    currentFrameSize: frameSize,
                    currentContentLayoutSize: contentLayoutSize),
                      let normalAnchor = self.normalFrameSnapshot,
                      let target = MinimalModeGeometry.enteringFrame(
                        from: normalAnchor,
                        compactFrameSize: compactSize,
                        visibleFrames: NSScreen.screens.map(\.visibleFrame),
                        primaryVisibleFrame: NSScreen.screens.first?.visibleFrame) else {
                    self.rejectModeTransition(generation: generation, window: window,
                                              mode: true, previousMode: previousMode)
                    return
                }
                guard self.isCurrentModeMeasurement(generation, window: window, view: view) else {
                    return
                }
                let measuredMinimum = NSSize(width: compactSize.width,
                                             height: compactSize.height)
                self.compactModeMinimumSize = measuredMinimum
                if window.minSize != measuredMinimum { window.minSize = measuredMinimum }
                guard self.isCurrentModeMeasurement(generation, window: window, view: view) else {
                    return
                }
                self.minimalModeMeasurementTask = nil
                self.applyModeFrame(target, to: window,
                                    generation: generation, mode: true)
            }
        }

        private func isCurrentModeMeasurement(_ generation: UInt64,
                                              window: NSWindow,
                                              view: WindowAttachmentView) -> Bool {
            isCurrentGeometryRequest(generation, window: window)
                && attachedView === view && view.window === window
                && requestedMinimalMode && activeMinimalMode && modeTransitionInFlight
        }

        private func rejectModeTransition(generation: UInt64,
                                          window: NSWindow,
                                          mode: Bool,
                                          previousMode: Bool) {
            guard isCurrentGeometryRequest(generation, window: window) else { return }
            activeMinimalMode = previousMode
            modeTransitionInFlight = false
            modeBeforeTransition = nil
            minimalModeMeasurementTask = nil
            if mode && !previousMode {
                normalFrameSnapshot = nil
                compactModeMinimumSize = nil
                let normalFloor = WindowConfigurator.minFrameSize(
                    for: window, sidebarVisible: normalVisibility == .all)
                if window.minSize != normalFloor { window.minSize = normalFloor }
            } else if previousMode, let compactModeMinimumSize,
                      window.minSize != compactModeMinimumSize {
                window.minSize = compactModeMinimumSize
            }
            rejectMinimalModeRequest()
            publishMinimalModeCommandAvailability()
        }

        private func applyModeFrame(_ frame: CGRect,
                                    to window: NSWindow,
                                    generation: UInt64,
                                    mode: Bool) {
            guard isCurrentGeometryRequest(generation, window: window) else { return }
            if reduceMotion {
                window.setFrame(frame, display: true)
                finishModeTransition(generation: generation, window: window, mode: mode)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Coordinator.minimalModeAnimationDuration
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self, weak window] in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window,
                          self.isCurrentGeometryRequest(generation, window: window) else { return }
                    self.finishModeTransition(generation: generation,
                                              window: window, mode: mode)
                }
            }
        }

        private func finishModeTransition(generation: UInt64,
                                          window: NSWindow,
                                          mode: Bool) {
            guard isCurrentGeometryRequest(generation, window: window),
                  activeMinimalMode == mode else { return }
            modeTransitionInFlight = false
            modeBeforeTransition = nil
            if !mode {
                normalFrameSnapshot = nil
                compactModeMinimumSize = nil
                // The completed rectangle is normal geometry; the existing
                // rounded 400 ms settle writer will persist only a real change.
                scheduleFrameSettle(window: window, immediate: false)
            }
            traceMinimalModeGeometry(event: "finished", window: window, mode: mode)
            publishMinimalModeCommandAvailability()
        }

        private func rejectMinimalModeRequest() {
            requestedMinimalMode = activeMinimalMode
            onMinimalModeRequestRejected?(activeMinimalMode)
        }

        private func scheduleSidebarResize(window: NSWindow, nowVisible: Bool) {
            sidebarResizeTask?.cancel()
            geometryRequestGeneration &+= 1
            let generation = geometryRequestGeneration
            sidebarResizeTask = Task { @MainActor [weak self, weak window] in
                await Task.yield()
                guard let self, let window, !Task.isCancelled,
                      self.isCurrentGeometryRequest(generation, window: window),
                      !self.activeMinimalMode, !self.modeTransitionInFlight else { return }
                let frame = window.frame
                let edge = SidebarWindowGeometry.Edge(originX: frame.minX, width: frame.width)
                let screenVisible: ClosedRange<CGFloat>? = window.screen.map {
                    $0.visibleFrame.minX...$0.visibleFrame.maxX
                }
                let target = nowVisible
                    ? SidebarWindowGeometry.expanded(from: edge,
                                                     sidebarWidth: self.sidebarWidth,
                                                     screenVisible: screenVisible)
                    : SidebarWindowGeometry.collapsed(
                        from: edge, sidebarWidth: self.sidebarWidth,
                        minWidth: MainWindowGeometry.collapsedMinFrameWidth,
                        screenVisible: screenVisible)
                guard abs(target.originX - frame.minX) > 0.5
                        || abs(target.width - frame.width) > 0.5 else { return }
                var newFrame = frame
                newFrame.origin.x = target.originX
                newFrame.size.width = target.width
                if self.reduceMotion {
                    window.setFrame(newFrame, display: true)
                } else {
                    window.animator().setFrame(newFrame, display: true)
                }
            }
        }

        private func handleFullScreenEvent(_ name: Notification.Name, window: NSWindow) {
            guard owns(window) else { return }
            switch name {
            case NSWindow.willEnterFullScreenNotification:
                nativeFullScreenTransition = true
                invalidatePendingGeometryRequests()
                cancelModeTransitionForFullScreen(window: window)
            case NSWindow.didEnterFullScreenNotification:
                nativeFullScreen = true
                nativeFullScreenTransition = false
            case NSWindow.willExitFullScreenNotification:
                nativeFullScreenTransition = true
                invalidatePendingGeometryRequests()
                cancelModeTransitionForFullScreen(window: window)
            case NSWindow.didExitFullScreenNotification:
                nativeFullScreen = false
                nativeFullScreenTransition = false
            default:
                return
            }
            publishMinimalModeCommandAvailability()
            if !nativeFullScreen, !nativeFullScreenTransition { applyLatestInputs() }
        }

        private func cancelModeTransitionForFullScreen(window: NSWindow) {
            guard modeTransitionInFlight else { return }
            let previousMode = modeBeforeTransition ?? activeMinimalMode
            modeTransitionInFlight = false
            modeBeforeTransition = nil
            if previousMode {
                // An interrupted exit is retried after native full-screen ends.
                activeMinimalMode = false
                requestedMinimalMode = true
                onMinimalModeRequestRejected?(true)
            } else {
                activeMinimalMode = false
                requestedMinimalMode = false
                normalFrameSnapshot = nil
                compactModeMinimumSize = nil
                onMinimalModeRequestRejected?(false)
                let normalFloor = WindowConfigurator.minFrameSize(
                    for: window, sidebarVisible: normalVisibility == .all)
                if window.minSize != normalFloor { window.minSize = normalFloor }
            }
        }

        private func invalidatePendingGeometryRequests() {
            geometryRequestGeneration &+= 1
            frameSettleTask?.cancel()
            frameSettleTask = nil
            sidebarResizeTask?.cancel()
            sidebarResizeTask = nil
            minimalModeMeasurementTask?.cancel()
            minimalModeMeasurementTask = nil
        }

        private func isCurrentGeometryRequest(_ generation: UInt64,
                                             window: NSWindow) -> Bool {
            MinimalModePresentation.isCurrentGeometryRequest(
                requestGeneration: generation,
                latestGeneration: geometryRequestGeneration,
                ownsWindow: owns(window))
        }

        private func owns(_ window: NSWindow) -> Bool {
            attachedWindow === window
        }

        private var mayPersistNormalFrame: Bool {
            MinimalModePresentation.shouldPersistNormalFrame(
                isMinimalMode: requestedMinimalMode || activeMinimalMode,
                isTransitioning: modeTransitionInFlight || nativeFullScreenTransition,
                isNativeFullScreen: nativeFullScreen)
        }

        func scheduleFrameSettle(window: NSWindow, immediate: Bool) {
            frameSettleTask?.cancel()
            frameSettleTask = nil
            guard owns(window), isWindowReady, mayPersistNormalFrame else { return }
            guard !immediate else {
                // Termination persists only a settled NORMAL frame. Compact,
                // transition, and full-screen geometry is never the launch frame.
                onFrameSettled?(window.frame)
                return
            }
            let generation = geometryRequestGeneration
            frameSettleTask = Task { @MainActor [weak self, weak window] in
                do { try await Task.sleep(for: Coordinator.frameSettleDelay) }
                catch { return }
                guard let self, let window, !Task.isCancelled,
                      self.owns(window), self.geometryRequestGeneration == generation,
                      self.isWindowReady, self.mayPersistNormalFrame else { return }
                self.onFrameSettled?(window.frame)
            }
        }

        func reapply(to window: NSWindow?) {
            guard let window else { return }
            let hide = WindowConfigurator.effectiveSidebarButtonHidden(
                preference: hidePreference, collapsed: collapsed,
                forced: forcedHide,
                minimalMode: requestedMinimalMode || activeMinimalMode)
            applySidebarButtonVisibility(to: window, hide: hide)
        }

        private func modeCommandIsEligible(for window: NSWindow) -> Bool {
            owns(window) && isWindowReady && window.isKeyWindow && !forcedHide
                && !nativeFullScreen && !nativeFullScreenTransition
                && !modeTransitionInFlight
        }

        private func publishMinimalModeCommandAvailability() {
            let available = attachedWindow.map { modeCommandIsEligible(for: $0) } ?? false
            onMinimalModeCommandAvailability?(available)
        }

        private func traceMinimalModeGeometry(event: String,
                                              window: NSWindow,
                                              mode: Bool) {
            guard owns(window) else { return }
            let layoutRect = window.contentLayoutRect
            let contentBounds = window.contentView?.bounds ?? .zero
            let modeName = mode ? "on" : "off"
            Diagnostics.shared?.log(
                "minimalMode.\(event) window=\(window.windowNumber) "
                    + "mode=\(modeName) "
                    + "eligible=\(modeCommandIsEligible(for: window)) "
                    + "frame=\(window.frame) contentLayoutRect=\(layoutRect) "
                    + "contentViewBounds=\(contentBounds)")
        }

        private func detachOwnedWindow() {
            guard attachedWindow != nil else { return }
            invalidatePendingGeometryRequests()
            toolbarReassertionTask?.cancel()
            toolbarReassertionTask = nil
            if let chromeObserver { NotificationCenter.default.removeObserver(chromeObserver) }
            chromeObserver = nil
            if let keyResignObserver { NotificationCenter.default.removeObserver(keyResignObserver) }
            keyResignObserver = nil
            if let itemObserver { NotificationCenter.default.removeObserver(itemObserver) }
            itemObserver = nil
            for observer in frameObservers + fullScreenObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            frameObservers.removeAll()
            fullScreenObservers.removeAll()
            let wasReady = isWindowReady
            attachedWindow = nil
            isWindowReady = false
            didInitializeAttachedWindow = false
            activeMinimalMode = false
            modeTransitionInFlight = false
            modeBeforeTransition = nil
            nativeFullScreen = false
            nativeFullScreenTransition = false
            normalFrameSnapshot = nil
            compactModeMinimumSize = nil
            if wasReady { onWindowReady?(false) }
            publishMinimalModeCommandAvailability()
        }

        func dismantle(view: WindowAttachmentView) {
            view.windowAttachmentChanged = nil
            attachedView = nil
            detachOwnedWindow()
            onWindowReady = nil
            onMinimalModeCommandAvailability = nil
            onMinimalModeRequestRejected = nil
            onCaptureNormalFrame = nil
            onFrameSettled = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        let coord = context.coordinator
        view.windowAttachmentChanged = { [weak coord, weak view] window in
            guard let coord, let view else { return }
            coord.windowAttachmentChanged(window, from: view)
        }
        coord.updateInputs(
            view: view,
            minimalMode: minimalMode,
            normalVisibility: normalColumnVisibility,
            effectiveVisibility: minimalMode ? .detailOnly : normalColumnVisibility,
            savedNormalFrame: savedNormalFrame,
            sidebarWidth: sidebarWidth,
            reduceMotion: reduceMotion,
            hidePreference: hideSidebarButtonWhenCollapsed,
            forcedHide: forceHideSidebarButton,
            onWindowReady: onWindowReady,
            onMinimalModeCommandAvailability: onMinimalModeCommandAvailability,
            onMinimalModeRequestRejected: onMinimalModeRequestRejected,
            onCaptureNormalFrame: onCaptureNormalFrame,
            onFrameSettled: onWindowFrameSettled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowAttachmentView else { return }
        context.coordinator.updateInputs(
            view: view,
            minimalMode: minimalMode,
            normalVisibility: normalColumnVisibility,
            effectiveVisibility: minimalMode ? .detailOnly : normalColumnVisibility,
            savedNormalFrame: savedNormalFrame,
            sidebarWidth: sidebarWidth,
            reduceMotion: reduceMotion,
            hidePreference: hideSidebarButtonWhenCollapsed,
            forcedHide: forceHideSidebarButton,
            onWindowReady: onWindowReady,
            onMinimalModeCommandAvailability: onMinimalModeCommandAvailability,
            onMinimalModeRequestRejected: onMinimalModeRequestRejected,
            onCaptureNormalFrame: onCaptureNormalFrame,
            onFrameSettled: onWindowFrameSettled)
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let view = nsView as? WindowAttachmentView else { return }
        coordinator.dismantle(view: view)
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

/// Package 7: the ONE modifier that receives both subtotal commands —
/// extracting them keeps the main body inside the type-checker budget.
private struct SubtotalCommandReceiver: ViewModifier {
    let handler: (Bool) -> Void
    let onRecalculate: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .addSubtotal)) { _ in
                handler(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addGrandTotal)) { _ in
                handler(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .recalculateDynamic)) { _ in
                onRecalculate()
            }
    }
}

struct NLXDocument: FileDocument {
    var export: SheetExport
    static var readableContentTypes: [UTType] { [.nlx, .json] }
    init(model: AppModel) {
        export = model.exportCurrent() ?? SheetExport(title: "Sheet", content: "")
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
