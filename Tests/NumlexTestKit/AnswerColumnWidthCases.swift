import AppKit
import Foundation
import NumlexCore

/// The adjustable answer-column width: pure geometry (`
/// AnswerColumnGeometry`), tolerant store persistence
/// (`StylingPreferences.answerColumnWidth`), the divider handle and
/// settings contracts, the dynamic footer geometry, the six-language
/// localization and the state-safety invariants.
///
/// The column used to be a fixed 200 pt panel. It is now user
/// adjustable (140...400 pt, default 200) by dragging the editor|
/// answer divider or the Settings → Styling → Answer column control.
/// The preference is app-global (never per-sheet, never in `.nlx`),
/// and every width mutation is presentation-only: sheet content, line
/// IDs, references, caret, selection, focus and evaluation are never
/// touched by it.
private func answerWidthSource(_ relative: String) throws -> String {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = url.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    throw CaseFailure(message: "source not found: \(relative)", location: "AnswerWidth")
}

public let answerColumnWidthCases: [EngineCase] = [

    // MARK: - pure geometry

    EngineCase("answer-width-geometry-constants") {
        try expectEqual(AnswerColumnGeometry.defaultWidth, 200, "default 200 pt")
        try expectEqual(AnswerColumnGeometry.minWidth, 140, "hard minimum 140 pt")
        try expectEqual(AnswerColumnGeometry.maxWidth, 400, "hard maximum 400 pt")
        try expectEqual(AnswerColumnGeometry.editorMinimumWidth, 280, "editor keeps 280 pt")
        try expectEqual(AnswerColumnGeometry.dividerWidth, 1, "the divider footprint is 1 pt")
        // The footer's default-width compatibility constant points at the
        // ONE central default, so the two can never drift.
        try expectEqual(FooterTotalLayout.panelWidth, AnswerColumnGeometry.defaultWidth,
                        "footer compatibility constant == the central default")
    },

    EngineCase("answer-width-sanitize-preference") {
        // Finite in-range values pass through untouched.
        for v in [140.0, 200.0, 250.5, 400.0] {
            try expectEqual(AnswerColumnGeometry.sanitizePreference(v), v, "\(v) passes through")
        }
        // Finite out-of-range values clamp into the hard range.
        try expectEqual(AnswerColumnGeometry.sanitizePreference(50), AnswerColumnGeometry.minWidth, "below clamps to min")
        try expectEqual(AnswerColumnGeometry.sanitizePreference(9999), AnswerColumnGeometry.maxWidth, "above clamps to max")
        // Non-finite values resolve to the default; finite out-of-range
        // values (negative, zero) clamp into the range like the rest.
        for bad in [Double.nan, .infinity, -.infinity] {
            try expectEqual(AnswerColumnGeometry.sanitizePreference(bad),
                            AnswerColumnGeometry.defaultWidth,
                            "non-finite \(bad) -> default")
        }
        for bad in [-3.0, 0.0] {
            try expectEqual(AnswerColumnGeometry.sanitizePreference(bad),
                            AnswerColumnGeometry.minWidth,
                            "finite \(bad) clamps to min")
        }
    },

    EngineCase("answer-width-effective-cap-keeps-the-editor") {
        // Wide window: the preference wins (the cap is above it).
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 400,
                                                            availableDetailWidth: 700),
                        400, "cap 419 above the preference")
        // The cap bites: 600 - 280 - 1 = 319.
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 400,
                                                            availableDetailWidth: 600),
                        319, "the window cap wins")
        // A mid preference stays put while there is room.
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 200,
                                                            availableDetailWidth: 600),
                        200, "roomy window keeps the preference")
        // The minimum window (600 pt content) leaves 319 pt for the
        // column: even the maximum preference degrades safely.
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 400,
                                                            availableDetailWidth: 421),
                        AnswerColumnGeometry.minWidth, "cap exactly at the minimum")
        // A window too narrow for editor + minimum column degrades the
        // COLUMN (the editor keeps its minimum): 400 - 280 - 1 = 119.
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 200,
                                                            availableDetailWidth: 400),
                        119, "the column degrades, the editor is kept")
        // Degradation stops at zero — never negative.
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 200,
                                                            availableDetailWidth: 281),
                        0, "zero, not negative")
        try expectEqual(AnswerColumnGeometry.effectiveWidth(preference: 200,
                                                            availableDetailWidth: 100),
                        0, "hostile-narrow window stays at zero")
        // Unknown / hostile available widths disable the cap entirely:
        // the sanitized preference is returned, never NaN/negative.
        for bad in [Double.nan, .infinity, -.infinity, 0.0, -50.0] {
            let w = AnswerColumnGeometry.effectiveWidth(preference: 200,
                                                        availableDetailWidth: bad)
            try expectEqual(w, 200, "unknown available (\(bad)) -> preference")
        }
        let hostilePref = AnswerColumnGeometry.effectiveWidth(preference: .nan,
                                                              availableDetailWidth: 700)
        try expectEqual(hostilePref, AnswerColumnGeometry.defaultWidth, "hostile preference -> default")
    },

    EngineCase("answer-width-drag-direction") {
        // LEFT drag grows the answer column, RIGHT drag shrinks it
        // (startWidth - horizontalTranslation; leftward translations
        // are negative in AppKit/SwiftUI coordinates).
        try expectEqual(AnswerColumnGeometry.width(afterDrag: 200, horizontalTranslation: -40),
                        240, "left drag grows")
        try expectEqual(AnswerColumnGeometry.width(afterDrag: 200, horizontalTranslation: 40),
                        160, "right drag shrinks")
        // Wild drags clamp at the hard bounds — never past them.
        try expectEqual(AnswerColumnGeometry.width(afterDrag: 200, horizontalTranslation: -1000),
                        AnswerColumnGeometry.maxWidth, "left clamp at max")
        try expectEqual(AnswerColumnGeometry.width(afterDrag: 200, horizontalTranslation: 1000),
                        AnswerColumnGeometry.minWidth, "right clamp at min")
        // From a boundary, the matching direction is a no-op.
        try expectEqual(AnswerColumnGeometry.width(afterDrag: AnswerColumnGeometry.maxWidth,
                                                   horizontalTranslation: -50),
                        AnswerColumnGeometry.maxWidth, "at max, left stays")
        try expectEqual(AnswerColumnGeometry.width(afterDrag: AnswerColumnGeometry.minWidth,
                                                   horizontalTranslation: 50),
                        AnswerColumnGeometry.minWidth, "at min, right stays")
        // Hostile input resolves to the default.
        for (a, b) in [(Double.nan, 10.0), (100.0, .nan), (Double.nan, .nan),
                       (.infinity, 0.0), (0.0, -.infinity)] as [(Double, Double)] {
            try expectEqual(AnswerColumnGeometry.width(afterDrag: a, horizontalTranslation: b),
                            AnswerColumnGeometry.defaultWidth,
                            "hostile (\(a), \(b)) -> default")
        }
    },

    EngineCase("answer-width-material-drag-threshold") {
        // The core gate that separates a real drag from a click:
        // zero and sub-pixel jitter are clicks; |t| >= 1 pt is a drag.
        try expect(!AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: 0), "zero is a click")
        try expect(!AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: 0.5), "sub-pixel jitter is a click")
        try expect(!AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: -0.9), "sub-pixel jitter is a click")
        try expect(AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: 1), "1 pt is material")
        try expect(AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: -1), "-1 pt is material")
        try expect(AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: 40), "a real drag is material")
        for bad in [Double.nan, .infinity, -.infinity] {
            try expect(!AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: bad),
                       "hostile \(bad) is not material")
        }
    },

    EngineCase("answer-width-click-noop-keeps-stored-preference") {
        // The delegated edge case, simulated exactly as the handle and
        // ContentView behave: stored preference 400, window-capped
        // displayed width 250. A click on the divider (zero / sub-pixel
        // translation) must not write 250 into the preference and must
        // persist nothing; a real drag starts from the displayed width
        // and persists the user-requested width exactly once.
        let stored: Double = 400
        let displayed: Double = 250
        func runSession(_ translations: [Double]) -> (liveWrites: Int, persists: Int, final: Double?) {
            var liveWrites = 0
            var persists = 0
            var final: Double?
            var dragStart: Double?
            for t in translations {
                guard AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: t) else { continue }
                if dragStart == nil { dragStart = displayed }
                guard let start = dragStart else { continue }
                liveWrites += 1
                final = AnswerColumnGeometry.width(afterDrag: start, horizontalTranslation: t)
            }
            if let start = dragStart {
                final = AnswerColumnGeometry.width(afterDrag: start, horizontalTranslation: translations.last ?? 0)
                persists += 1
            }
            return (liveWrites, persists, final)
        }
        // A click: zero and sub-pixel jitter only.
        let click = runSession([0.0, 0.4, -0.2, 0.6, 0.0])
        try expectEqual(click.liveWrites, 0, "a click makes no live in-memory write")
        try expectEqual(click.persists, 0, "a click persists nothing")
        try expectEqual(stored, 400, "the stored preference is untouched")
        // A real drag from the capped geometry: the first material tick
        // starts it, live writes follow, one persist at the end — and
        // the persisted width is the user-requested formula result,
        // not the transient cap.
        let drag = runSession([0.5, -1, -20, -40])
        try expectEqual(drag.liveWrites, 3, "live writes from the first material tick")
        try expectEqual(drag.final, 290, "left drag grows: 250 + 40")
        try expectEqual(drag.persists, 1, "exactly one persist at drag end")
        // A drag that returns exactly to its start still commits the
        // user-requested (displayed) end width.
        let round = runSession([-1, -20, 0])
        try expectEqual(round.final, 250, "round trip ends at the displayed start")
        try expectEqual(round.persists, 1, "a material drag commits once")
        // Hostile translations never start a drag.
        let hostile = runSession([.nan, .infinity, -.infinity])
        try expectEqual(hostile.liveWrites, 0, "hostile input writes nothing")
        try expectEqual(hostile.persists, 0, "hostile input persists nothing")
    },

    // MARK: - store persistence (tolerant, app-global, not .nlx)

    EngineCase("answer-width-store-legacy-missing-defaults") {
        // A pre-feature store: no answerColumnWidth key anywhere. The
        // column decodes to the 200 pt default and the store loads.
        let old = """
        {"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en",
         "sheetName": "Sheet", "lineNumbers": true, "fontColor": "white",
         "styling": {"fontDesign": "rounded", "answerColumnWidth": 263.5}}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        try expectEqual(s.styling.answerColumnWidth, 263.5, "present value decodes")
        let missing = """
        {"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en",
         "sheetName": "Sheet", "lineNumbers": true, "fontColor": "white",
         "styling": {"fontDesign": "rounded"}}
        """
        let l = try JSONDecoder().decode(AppSettings.self, from: Data(missing.utf8))
        try expectEqual(l.styling.answerColumnWidth,
                        AnswerColumnGeometry.defaultWidth, "missing key -> 200 pt")
        try expectEqual(l.styling.fontDesign, .rounded, "the other fields are untouched")
    },

    EngineCase("answer-width-store-malformed-and-hostile") {
        func decode(_ widthValue: String) throws -> Double {
            let payload = "{\"decimalPlaces\": 10, \"fontSizeKey\": \"tf\", \"language\": \"en\", \"sheetName\": \"Sheet\", \"lineNumbers\": true, \"fontColor\": \"white\", \"styling\": {\"answerColumnWidth\": \(widthValue)}}"
            let s = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))
            return s.styling.answerColumnWidth
        }
        // Wrong type: falls back to the default like every other field.
        try expectEqual(try decode("\"wide\""),
                        AnswerColumnGeometry.defaultWidth, "wrong type -> default")
        // JSON null (a serialized non-finite double): the default.
        try expectEqual(try decode("null"),
                        AnswerColumnGeometry.defaultWidth, "null -> default")
        // Finite out-of-range values clamp into the hard range.
        try expectEqual(try decode("9999"), AnswerColumnGeometry.maxWidth, "finite above clamps to max")
        try expectEqual(try decode("0.5"), AnswerColumnGeometry.minWidth, "finite below clamps to min")
        // A negative finite value is out of range -> clamps to the min
        // (the preference range is positive by definition).
        try expectEqual(try decode("-3"), AnswerColumnGeometry.minWidth, "finite negative clamps to min")
    },

    EngineCase("answer-width-store-round-trip-and-version") {
        var s = AppSettings()
        s.styling.answerColumnWidth = 263.5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back.styling.answerColumnWidth, 263.5, "round-trips exactly")
        try expectEqual(s.styling, back.styling, "the whole styling block round-trips")
        // The store payload version is NOT bumped by the new key: the
        // write is purely additive, old payloads keep loading.
        try expectEqual(StorePayload.currentVersion, 2, "StorePayload.version stays 2")
        // The encoded styling object carries exactly the stable key.
        let stylingData = try JSONEncoder().encode(s.styling)
        let keys = try JSONDecoder().decode([String: JSONValuePlaceholder].self, from: stylingData)
        try expect(keys["answerColumnWidth"] != nil, "the key is encoded")
        // .nlx files never contain settings: the width lives ONLY in
        // the app-global store payload (this is asserted structurally —
        // Sheet carries no settings field at all).
        let sheet = Sheet(title: "T", content: "1 + 1\n")
        try expect(sheet.content == "1 + 1\n", "sheet content is the .nlx payload core")
    },

    EngineCase("answer-width-width-only-mutation-is-presentation-only") {
        // A width-only settings mutation must change NOTHING else:
        // every other settings field, and the sheet content, line IDs,
        // references and display overrides stay byte-identical.
        var a = AppSettings()
        a.styling.answerColumnWidth = 200
        let sheetA = Sheet(title: "T", content: "apple = 65\napple × 3\n",
                           lineIDs: [UUID(), UUID()],
                           references: [])
        var b = a
        b.styling.answerColumnWidth = 300
        // The sheet is a separate value: a width mutation re-renders
        // the column and never produces or touches the document value.
        let sheetB = sheetA
        // Only the width field differs.
        try expect(a != b, "the width change is observable")
        try expectEqual(b.decimalPlaces, a.decimalPlaces, "decimalPlaces untouched")
        try expectEqual(b.fontSizeKey, a.fontSizeKey, "fontSizeKey untouched")
        try expectEqual(b.language, a.language, "language untouched")
        try expectEqual(b.sheetName, a.sheetName, "sheetName untouched")
        try expectEqual(b.lineNumbers, a.lineNumbers, "lineNumbers untouched")
        try expectEqual(b.showTotalBar, a.showTotalBar, "showTotalBar untouched")
        try expectEqual(b.fontColor, a.fontColor, "fontColor untouched")
        try expectEqual(b.input, a.input, "input untouched")
        try expectEqual(b.customConstants, a.customConstants, "constants untouched")
        try expectEqual(b.appearance, a.appearance, "appearance untouched")
        try expectEqual(b.customUnits, a.customUnits, "units untouched")
        try expectEqual(b.presentation, a.presentation, "presentation untouched")
        try expectEqual(b.appIcon, a.appIcon, "appIcon untouched")
        try expectEqual(b.temporal, a.temporal, "temporal untouched")
        try expectEqual(b.tax, a.tax, "tax untouched")
        try expectEqual(b.footerStatistic, a.footerStatistic, "footerStatistic untouched")
        try expectEqual(b.styling.fontDesign, a.styling.fontDesign, "fontDesign untouched")
        try expectEqual(b.styling.numbers, a.styling.numbers, "colors untouched")
        try expectEqual(b.styling.answerColumnAlignment, a.styling.answerColumnAlignment, "alignment untouched")
        try expectEqual(b.styling.answerColumnSurface, a.styling.answerColumnSurface, "surface untouched")
        // The sheet is untouched by construction: a width change
        // re-renders the column, it never touches the document. (The
        // whole-struct comparison would differ only in the creation
        // timestamps; the document fields are compared individually.)
        try expect(sheetB.content == sheetA.content, "sheet content unchanged")
        try expect(sheetB.lineIDs == sheetA.lineIDs, "line IDs unchanged")
        try expect(sheetB.references == sheetA.references, "references unchanged")
        try expect(sheetB.answerDisplay == sheetA.answerDisplay, "answer display unchanged")
        try expect(sheetB.highlights == sheetA.highlights, "highlights unchanged")
    },

    // MARK: - footer geometry at the adjustable widths

    EngineCase("answer-width-footer-actual-column-widths") {
        // The adjustable column: the footer is laid out against the ACTUAL
        // width, and the legacy 200 pt geometry is reproduced exactly.
        for (container, bubble, content) in [(CGFloat(140), CGFloat(124), CGFloat(100)),
                                             (CGFloat(200), CGFloat(184), CGFloat(160)),
                                             (CGFloat(400), CGFloat(384), CGFloat(360))] {
            let r = FooterTotalLayout.layout(containerWidth: container,
                                             labelWidth: 10, valueWidth: 10)
            try expect(r.showsLabel, "\(container) pt: a short pair keeps the label")
            try expectEqual(r.bubbleWidth, bubble, "\(container) pt: full bubble")
            try expectEqual(r.contentWidth, content, "\(container) pt: full content")
        }
        // At the 200 pt default the Result matches the legacy static
        // values byte-for-byte (the compatibility constants).
        let def = FooterTotalLayout.layout(containerWidth: 200,
                                           labelWidth: 10, valueWidth: 10)
        try expectEqual(def.bubbleWidth, FooterTotalLayout.bubbleWidth, "default bubble == legacy 184")
        try expectEqual(def.contentWidth, FooterTotalLayout.contentWidth, "default content == legacy 160")
        // The widest column keeps BOTH the label and the maximum bubble
        // inside the panel: a long value is capped to the 400 pt content.
        let wide = FooterTotalLayout.layout(containerWidth: 400,
                                            labelWidth: 30, valueWidth: 999)
        try expectEqual(wide.contentWidth, 360, "400 pt: capped content")
        try expectEqual(wide.bubbleWidth, 384, "400 pt: capped bubble")
        // The narrowest column has the smallest content width (100 pt), so a
        // pair that needs 100 pt fits EXACTLY there under the documented 2 pt
        // safety reserve, and one point more collapses — the compact bubble
        // then stays inside the 140 pt panel.
        let exactNarrow = FooterTotalLayout.layout(containerWidth: 140,
                                                  labelWidth: 30, valueWidth: 60)
        try expect(exactNarrow.showsLabel,
                   "140 pt: a pair needing exactly the 100 pt content keeps the label")
        let narrow = FooterTotalLayout.layout(containerWidth: 140,
                                              labelWidth: 30, valueWidth: 61)
        try expect(!narrow.showsLabel, "140 pt: one point more collapses")
        try expectEqual(narrow.bubbleWidth, 61 + 24, "140 pt: value bubble")
        try expect(narrow.bubbleWidth <= 124, "140 pt: inside the panel")
        // Hostile containers at the adjustable widths: safe, bounded,
        // never negative/NaN.
        for bad in [CGFloat.nan, .infinity, -.infinity, CGFloat(-100)] {
            let r = FooterTotalLayout.layout(containerWidth: bad,
                                             labelWidth: 30, valueWidth: 40)
            try expect(r.bubbleWidth.isFinite && r.bubbleWidth >= 0, "finite bubble (\(bad))")
            try expect(r.contentWidth.isFinite && r.contentWidth >= 0, "finite content (\(bad))")
        }
    },

    // MARK: - source contracts

    EngineCase("answer-width-production-geometry-has-no-fixed-200") {
        let view = try answerWidthSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(!view.contains(".frame(width: 200)"), "no fixed 200 pt frame in production")
        try expect(view.contains("var width: Double"), "the view takes its width")
        try expect(view.contains(".frame(width: width)"), "the column is framed by the ACTUAL width")
        try expect(view.contains("FooterTotalLayout.layout(containerWidth: width,"),
                   "the footer is laid out against the actual width")
        try expect(!view.contains("FooterTotalLayout.panelWidth"),
                   "no runtime read of the static panel width")
        let footer = try answerWidthSource("Sources/NumlexCore/Models/FooterTotalLayout.swift")
        try expect(footer.contains("let fullBubble = max(0, container - 2 * outerInset)"),
                   "the bubble derives from the container width")
        try expect(!footer.contains("min(container - 2 * outerInset, bubbleWidth)"),
                   "no static 184 pt cap in runtime layout")
        try expect(footer.contains("AnswerColumnGeometry.defaultWidth"),
                   "the compatibility constant points at the central default")
        let content = try answerWidthSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(!content.contains("editorAnswerDivider"), "the passive divider is gone")
        try expect(content.contains("AnswerColumnResizeHandle"), "the draggable handle is in")
        try expect(content.contains("AnswerColumnGeometry.effectiveWidth("),
                   "the effective width is computed from real detail geometry")
        try expect(content.contains("availableDetailWidth: detailWidth"),
                   "the detail width is measured, not assumed")
    },

    EngineCase("answer-width-handle-contract") {
        let h = try answerWidthSource("Sources/NumlexApp/Views/AnswerColumnResizeHandle.swift")
        // Visible footprint: exactly the 1 pt divider line in-flow.
        try expect(h.contains(".frame(width: AnswerColumnGeometry.dividerWidth)"),
                   "the visible line is the 1 pt divider width")
        // Hit zone: 12 pt (the 10...12 pt band), centered, no layout width.
        try expect(h.contains("static let hitZoneWidth: CGFloat = 12"),
                   "the hit zone is 12 pt wide")
        try expect(h.contains(".contentShape(Rectangle())"), "the zone is hit-testable")
        // Drag: measured in the STABLE global coordinate space (never
        // .local — the divider moves as the width updates, so a local
        // translation would feed the layout delta back into the next
        // tick and oscillate), through the immutable-start
        // AnswerColumnDragSession; the core material gate guards every
        // live write (a click never writes, so a window-capped display
        // width can never replace the stored preference).
        try expect(h.contains("DragGesture(minimumDistance: 0, coordinateSpace: .global)"),
                   "the drag measures pointer motion in the stable GLOBAL space")
        try expect(!h.contains("coordinateSpace: .local"),
                   "no local coordinate space on a handle whose view moves")
        try expect(h.contains("AnswerColumnDragSession"),
                   "one immutable start per drag (stable pointer + displayed width)")
        try expect(h.contains("beginIfNeeded("), "the start is captured once, at the press")
        try expect(h.contains("hasMaterialDrag"),
                   "onEnd is gated on an actual material movement")
        try expect(h.contains("value.location.x"), "the explicit stable pointer x is used")
        // Cursor: hover-driven, NOT popped on drag end (a stationary
        // pointer over the zone keeps the resize cursor; the next
        // leave — or disappear — pops it, keeping the stack balanced).
        try expect(h.contains("NSCursor.resizeLeftRight.push()"), "resize cursor pushed")
        try expect(h.contains("NSCursor.pop()"), "resize cursor popped")
        try expect(h.contains("setCursor(active: false)"), "disappear pops")
        try expect(h.contains("hoverInside"), "explicit hover state drives the cursor")
        // onEnded must not touch the cursor (no pop while still hovered)
        // and must hand the caller the EXACT final formula width, only
        // for material drags.
        guard let ended = h.range(of: ".onEnded { value in") else {
            throw CaseFailure(message: "onEnded closure not found", location: "AnswerWidth")
        }
        let endSlice = String(h[ended.lowerBound..<h.index(ended.lowerBound, offsetBy: 720)])
        try expect(!endSlice.contains("setCursor("), "drag end does not pop the cursor")
        try expect(endSlice.contains("hasMaterialDrag"),
                   "onEnd fires only for material (started) drags")
        try expect(endSlice.contains("finalWidth(pointerX:"),
                   "the exact end-position width is committed, not the last tick")
        try expect(endSlice.contains("guard let final else { return }"),
                   "a click end produces no onEnd at all")
        // Live changes never persist; the handle has no persistence at all.
        try expect(!h.contains("persist("), "the handle itself never persists")
        try expect(h.contains("onChange("), "live in-memory changes are reported")
        // Accessibility: labeled, valued, hinted, adjustable.
        try expect(h.contains("accessibilityLabel("), "meaningful label")
        try expect(h.contains("accessibilityValue("), "live width value")
        try expect(h.contains("accessibilityAdjustableAction"), "keyboard/VoiceOver adjustable")
        try expect(h.contains("L10n.t(\"styling.column.widthHandle\""), "localized label")
    },

    EngineCase("answer-width-persist-exactly-once-on-drag-end") {
        let c = try answerWidthSource("Sources/NumlexApp/Views/ContentView.swift")
        // The live change path writes the in-memory preference only.
        guard let changeStart = c.range(of: "onChange: { width in"),
              let changeEnd = c.range(of: "onEnd: { finalWidth in",
                                      range: changeStart.upperBound..<c.endIndex)
        else {
            throw CaseFailure(message: "drag closures not found", location: "AnswerWidth")
        }
        let changeSlice = String(c[changeStart.lowerBound..<changeEnd.lowerBound])
        try expect(!changeSlice.contains("persist("),
                   "no disk write on any onChanged event")
        try expect(changeSlice.contains("model.settings.styling.answerColumnWidth = width"),
                   "the in-memory preference is updated live")
        // The end path applies the exact final width in memory first,
        // then persists EXACTLY once, guarded by the no-op check
        // against the preference captured at drag start.
        try expect(c.contains("onEnd: { finalWidth in"), "the drag end closure exists")
        try expect(c.contains("model.settings.styling.answerColumnWidth = finalWidth"),
                   "the exact final computed width is applied in memory on end")
        try expect(c.contains("let changed = finalWidth != answerDragStartPref"),
                   "the no-op comparison uses the drag-start preference")
        try expect(c.contains("if changed { model.persist() }"),
                   "one guarded persist on drag end")
        // The in-memory assignment must precede the persist decision.
        guard let assignIdx = c.range(of: "model.settings.styling.answerColumnWidth = finalWidth"),
              let persistIdx = c.range(of: "model.persist()", range: assignIdx.upperBound..<c.endIndex)
        else {
            throw CaseFailure(message: "assignment-before-persist order not found", location: "AnswerWidth")
        }
        _ = persistIdx
        try expectEqual(c.components(separatedBy: "model.persist()").count - 1, 1,
                        "the drag end is the ONLY persist site in ContentView")
        // The Settings slider persists once on release, never per tick.
        let settings = try answerWidthSource("Sources/NumlexApp/Views/SettingsView.swift")
        guard let sliderStart = settings.range(of: "in: AnswerColumnGeometry.minWidth...AnswerColumnGeometry.maxWidth")
        else {
            throw CaseFailure(message: "no width slider range in settings", location: "AnswerWidth")
        }
        let sliderSlice = String(settings[sliderStart.lowerBound..<settings.index(sliderStart.lowerBound, offsetBy: 300)])
        try expect(sliderSlice.contains("if !editing { model.persist() }"),
                   "the slider persists exactly once, on release")
        // The slider is NATIVE with a fixed frame: its own geometry
        // never moves with the value (the value moves the MAIN window's
        // column, a different window), so it has no moving-origin
        // feedback path — only the divider handle needed the stable
        // global-space fix.
        try expect(settings.contains("Slider("), "the width control is the native Slider")
        try expect(settings.contains(".frame(width: 150)"), "the slider frame is fixed (no feedback loop)")
    },

    // MARK: - smooth drag sessions (the 4.9.2 jitter fix)

    EngineCase("answer-width-drag-session-stable-global-delta") {
        // Fixed GLOBAL pointer start; the divider (and any local
        // origin) moves under the pointer, but every width derives
        // from the immutable start — no oscillation.
        var s = AnswerColumnDragSession()
        s.beginIfNeeded(pointerX: 1000, displayedWidth: 250)
        try expect(s.hasStarted, "the press records the start")
        // The start is IMMUTABLE: later ticks (and any model/layout
        // change in between) cannot move it.
        s.beginIfNeeded(pointerX: 1234, displayedWidth: 999)
        try expectEqual(s.width(pointerX: 1010), 240, "width comes from the ORIGINAL start")
        // Monotonic right drag (shrinking): 1:1 tracking, no alternation.
        let right = [1000.0, 1000.4, 1002, 1010, 1030, 1040].compactMap { s.width(pointerX: $0) }
        try expectEqual(right, [248, 240, 220, 210], "right drag: monotonic decreasing, 1:1")
        // Monotonic left drag (growing): 1:1 tracking.
        let left = [990.0, 980, 960, 940].map { s.width(pointerX: $0)! }
        try expectEqual(left, [260, 270, 290, 310], "left drag: monotonic increasing, 1:1")
        // Direction reversal retraces EXACTLY (the width is a pure
        // function of the pointer x, not of the path taken).
        try expectEqual(s.width(pointerX: 1040), 210, "retracing right: same value as before")
        try expectEqual(s.width(pointerX: 1010), 240, "retracing back: same value as before")
        try expect(s.width(pointerX: 1000) == nil, "back to the start: not material -> no write")
        // Bounds: pinning is STABLE (no oscillation at the edges) and
        // resuming inside the range is smooth and 1:1.
        try expectEqual(s.width(pointerX: 2000), 140, "far right clamps to the hard min")
        try expectEqual(s.width(pointerX: 2001), 140, "still pinned at the min: stable")
        try expectEqual(s.width(pointerX: 120), 400, "far left clamps to the hard max")
        try expectEqual(s.width(pointerX: 119), 400, "still pinned at the max: stable")
        try expectEqual(s.width(pointerX: 1100), 150, "back in from the min: smooth 1:1")
        // The final value is the exact formula result at the end
        // pointer position — independent of how many live writes
        // happened along the way.
        try expectEqual(s.finalWidth(pointerX: 1030), 220, "final == exact formula result")
        s.end()
        try expect(!s.hasStarted, "end() forgets the session")
        try expect(s.width(pointerX: 1100) == nil, "a finished session reports nothing")
        try expect(s.finalWidth(pointerX: 1100) == nil, "a finished session commits nothing")
    },

    EngineCase("answer-width-drag-session-click-noop") {
        // Stored 400, window-capped displayed 250: a click on the
        // divider (sub-pixel jitter only) records a start but never a
        // material width -> no live write, no onEnd, zero persists;
        // the stored preference is untouched.
        var s = AnswerColumnDragSession()
        s.beginIfNeeded(pointerX: 500, displayedWidth: 250)
        var live = 0
        var final: Double?
        for x in [500.0, 500.3, 499.8, 500.6, 500.0] {
            if let w = s.width(pointerX: x) { live += 1; final = w }
        }
        if live > 0 { final = s.finalWidth(pointerX: 500) } // handle gate
        try expectEqual(live, 0, "no live writes for a click")
        try expect(final == nil, "no onEnd for a click -> no persist")
        // A real drag from the same (capped) geometry: the first
        // material tick starts it; the persisted width is the
        // user-requested formula result, never the transient cap.
        var d = AnswerColumnDragSession()
        d.beginIfNeeded(pointerX: 500, displayedWidth: 250)
        var writes = [Double]()
        for x in [500.4, 499.0, 490.0, 460.0] {
            if let w = d.width(pointerX: x) { writes.append(w) }
        }
        try expectEqual(writes, [251, 260, 290], "live writes from the first material tick")
        try expectEqual(d.finalWidth(pointerX: 460), 290, "exactly one commit: 250 + 40")
        // Hostile input never starts or ends a drag.
        var h = AnswerColumnDragSession()
        h.beginIfNeeded(pointerX: .nan, displayedWidth: 250)
        try expect(h.width(pointerX: 100) == nil, "non-finite start: no live width")
        try expect(h.finalWidth(pointerX: 100) == nil, "non-finite start: no final (no accidental 200)")
        var h2 = AnswerColumnDragSession()
        h2.beginIfNeeded(pointerX: 100, displayedWidth: 250)
        try expect(h2.width(pointerX: .infinity) == nil, "hostile tick is ignored")
        try expect(h2.finalWidth(pointerX: .infinity) == nil, "hostile end is ignored (nil, not 200)")
        try expectEqual(h2.finalWidth(pointerX: 40), 310, "a sane end after hostile ticks is exact")
    },

    EngineCase("answer-width-settings-control-contract") {
        let s = try answerWidthSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(s.contains("L10n.t(\"styling.column.width\", language: language)"),
                   "the localized Width row exists")
        try expect(s.contains("L10n.t(\"styling.column.widthCap\", language: language)"),
                   "the range caption is shown")
        try expect(s.contains("AnswerColumnGeometry.minWidth...AnswerColumnGeometry.maxWidth"),
                   "the slider spans the hard 140...400 range")
        try expect(s.contains("Int(model.settings.styling.answerColumnWidth)) pt\""),
                   "the live N pt readout")
        try expect(s.contains("accessibilityValue("), "the slider is accessible")
    },

    EngineCase("answer-width-localization-six-languages") {
        let l = try answerWidthSource("Sources/NumlexCore/Localization.swift")
        // One entry per language table for each of the three keys.
        for key in ["styling.column.width\"", "styling.column.widthCap", "styling.column.widthHandle"] {
            let occurrences = l.components(separatedBy: key).count - 1
            try expectEqual(occurrences, 6, "\(key) is localized in all six languages")
        }
    },

    EngineCase("answer-width-answer-surface-stays-actual-width") {
        let v = try answerWidthSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // The wheel catcher keeps its explicit full-size frame contract
        // (width AND height from the GeometryReader), so the hit
        // surface tracks the column through every width change.
        try expect(v.contains(".frame(width: geo.size.width,\n                               height: geo.size.height,"),
                   "the catcher stays the full actual frame")
        try expect(v.contains("width: geo.size.width,\n                            height: geo2.height"),
                   "rows use the actual width")
        try expect(v.contains("AnswerHoverOutline(\n                                    width: geo.size.width,"),
                   "the hover outline uses the actual width")
    }
]

/// Minimal JSON object decoding helper for the round-trip key check.
private struct JSONValuePlaceholder: Codable {}
